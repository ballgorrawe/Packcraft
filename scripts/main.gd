extends Control
## Screen manager + drag-and-drop controller for PackCraft (portrait, phone-first).
## Screens are rebuilt in code from RunState on every change (like a render() call);
## entrance animations only play when the screen itself changes, so taps feel instant.
## Items have no Store / Sell / Rotate buttons: drag to the shop to sell, drag to storage
## to store, tap an item again to rotate it.

var cell_px := 66.0   # pack cell size, fitted to the screen height in _run_screen()
const DRAG_THRESHOLD := 12.0

var run: RunState
var sel_cls := ""
var sel_pet := ""
var sel_diff := "normal"
var sel_asc := 0               # Ascension picked on the difficulty step
var show_how := false
var show_book := false
var show_effects := false      # the 📜 popup (what affects this run)
var arr_plan := {}             # 🪄 hint (puzzles): the best layout found, drawn as outlines until closed or done
var arr_done := {}             # 🪄 (runs): the layout it just put in place, kept for ↩️ undo while nothing else moved
var _arr_busy := false
var book_item := ""          # recipe book: item whose details are open
var foe_info_e := {}      # the monster whose Details popup is open (road card)
var book_page := 0

# drag / selection
var drag_item: PItem = null
var drag_src := ""
var drag_shop_idx := -1
var drag_orig := {}
var pending := {}            # press waiting to become a tap or a drag
var press_pos := Vector2.ZERO
var hover_cell := Vector2i(-1, -1)
var selected: PItem = null
var inspect_id := ""         # shop item being inspected (not owned)
var inspect_idx := -1

# animation state that survives re-renders
var anim := {}               # uid -> Vector2 drawn cell position (eases toward the real one)
var pops := {}               # uid -> seconds since it landed (squash/stretch)
var _screen_key := ""
var _shown_gold := -1
var _shown_hp := -1
var _shop_anim := false
var _last_shop_tap_idx := -1   # for double-tap to lock
var _last_shop_tap_ms := 0
var _fusion_queue: Array = []  # fusions / evolutions from last night, shown one by one when the day opens
var _fusion_seen := 0
var _all_stats_cs: CombatSim   # the night's full item list, while its popup is open
var _fused_flash: Array = []   # uids created at night: they pop and sparkle when the new day opens

# widgets of the current screen
var screen: Control
var grid: BackpackGrid
var storage_panel: Control
var storage_scroll: ScrollContainer
var _storage_x := 0          # storage scroll position, kept across re-renders
var _press_scroll := 0
var sell_zone: Control
var sell_lbl: Label
var held_lbl: Label
var popup: Control
var ghost: ShapeView
var ghost_layer: CanvasLayer
var toast_layer: CanvasLayer

var _dev := false   # screenshot/dev mode never touches the real save
var _pending_sim: CombatSim = null


func _ready() -> void:
	GameData.ensure_loaded()
	I18n.setup(SaveGame.get_setting("lang", "th" if OS.get_locale_language() == "th" else "en"))
	theme = UI.build_theme()
	# also on the window, so CanvasLayers (toasts, hover cards, drag ghost) and tooltip popups get
	# the bundled emoji / Thai fonts too (the web build has no system fonts)
	get_tree().root.theme = theme
	sel_cls = GameData.class_keys[0]
	sel_pet = SaveGame.get_setting("pet", GameData.pet_keys[0] if not GameData.pet_keys.is_empty() else "")
	sel_diff = SaveGame.get_setting("diff", "normal")
	_refresh_locks()
	_bg = UI.background()
	add_child(_bg)
	ghost_layer = CanvasLayer.new()
	ghost_layer.layer = 50
	add_child(ghost_layer)
	ghost = ShapeView.new()
	ghost.visible = false
	ghost_layer.add_child(ghost)
	toast_layer = CanvasLayer.new()
	toast_layer.layer = 60
	add_child(toast_layer)
	tip_layer = CanvasLayer.new()
	tip_layer.layer = 55
	add_child(tip_layer)
	get_tree().auto_accept_quit = false
	get_tree().root.size_changed.connect(func():
		if _fit_screen() and not _render_queued:
			_render_queued = true
			render.call_deferred())
	_fit_screen()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_dev = true
	if _dev:
		_splash = false
	render()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_autoshot(a.trim_prefix("--autoshot="))


func _process(delta: float) -> void:
	for k in pops:
		pops[k] += delta
	# debounced autosave: one write per burst of actions, never in the middle of a drag
	if _save_dirty and drag_item == null and Time.get_ticks_msec() - _save_at >= SAVE_DELAY_MS:
		_save_dirty = false
		if not _dev and run != null:
			SaveGame.save_run(run)


## Marks the run as changed. Saving writes the whole run (with its play log) to storage, which is slow
## in a browser, so it happens once the player pauses (or right away when the phase or the run ends).
func _save_soon() -> void:
	var ph: String = run.phase + run.end_state
	if ph != _saved_phase:
		_saved_phase = ph
		_save_dirty = false
		_autosave()
		return
	_save_dirty = true
	_save_at = Time.get_ticks_msec()


func _autosave() -> void:
	if _dev or run == null:
		return
	if drag_item != null:
		_cancel_drag()
		_end_drag()
	SaveGame.save_run(run)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			_autosave()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			_autosave()


## Sends a finished (or abandoned) run's play log to the collector (anonymous: decisions + a random player id).
## Off when no collector URL is set, in dev/test builds, and for runs with nothing recorded.
func _send_play_log(r: RunState, how: String) -> void:
	var url := str(ProjectSettings.get_setting("packcraft/log_url", ""))
	if url == "" or _dev or r == null or r.plog.is_empty() or r.has_meta("plog_sent"):
		return
	r.set_meta("plog_sent", true)
	var pid := str(SaveGame.get_setting("pid", ""))
	if pid == "":
		pid = "%08x" % (randi() & 0x7fffffff)
		SaveGame.set_setting("pid", pid)
	var d := r.plog_payload()
	d.end = how
	var body := JSON.stringify({"k": "pc1", "ver": str(ProjectSettings.get_setting("application/config/version", "")), "pid": pid,
		"when": Time.get_datetime_string_from_system(true), "run": d})
	var h := HTTPRequest.new()
	add_child(h)
	h.request_completed.connect(func(_res, _code, _hd, _b): h.queue_free())
	if h.request(url, ["Content-Type: text/plain;charset=utf-8"], HTTPClient.METHOD_POST, body) != OK:
		h.queue_free()


func _continue_run() -> void:
	var r := SaveGame.load_run()
	if r == null:
		SaveGame.clear_run()
		render()
		return
	run = r
	run.plog_start()
	_clear_sel()
	anim.clear()
	_pending_sim = run.resume_combat() if run.phase == "evening" else null
	if run.phase == "evening" and _pending_sim == null:
		run.phase = "afternoon"
	render()


func _clear_sel() -> void:
	selected = null
	inspect_id = ""
	inspect_idx = -1


## Safe-area margins (notches / rounded corners) converted to canvas units.
## Screen modes. Phones (portrait): the 720x1280 layout fills the screen.
## Wider than a phone: screens stay a phone-shaped column (COLUMN_W) in the middle.
## PC / landscape (_wide): the logical height drops to WIDE_H so everything is drawn bigger,
## and the morning screen splits into two columns (pack + storage | shop), WIDE_W across.
const COLUMN_W := 760.0
const WIDE_W := 1720.0
const WIDE_H := 1000
var _landscape := false   # anything wider than a phone (mouse hints, centred column)
var _end_tab := 0         # end screen on phones: 0 pack, 1 buffs
var _bg: Control                # the dungeon wall behind everything (darker on deeper floors)
const SAVE_DELAY_MS := 1500
var _save_dirty := false        # a save is waiting (see _save_soon)
var _save_at := 0
var _saved_phase := ""
var _bench_cache := {}    # class -> starting-kit numbers for the hero picker
var _wide := false        # landscape wide enough for the two-column morning screen
var _render_queued := false


## Returns true when the screen needs a re-render (mode changed, or the column must re-centre).
func _fit_screen() -> bool:
	var win := Vector2(get_window().size)
	if win.y <= 0:
		return false
	var aspect := win.x / win.y
	var was := [_landscape, _wide]
	_landscape = aspect > 0.8
	_wide = aspect >= 1.3
	return was != [_landscape, _wide] or _landscape


## Extra space on each side that keeps the game inside a centred column of width w.
func _side_pad(w := COLUMN_W) -> float:
	return maxf(0.0, (get_viewport_rect().size.x - w) / 2.0)


func _safe_margins(col_w := COLUMN_W) -> Vector4:
	var m := Vector4(14, 14, 14, 14)
	var pad := _side_pad(col_w)
	if pad > 0:
		return Vector4(14 + pad, 14, 14 + pad, 14)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		return m
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var vis := get_viewport_rect().size
	if win.x <= 0 or vis.x <= 0 or safe.size.x <= 0:
		return m
	var k := vis.x / win.x
	m.x = maxf(14, safe.position.x * k)
	m.y = maxf(14, safe.position.y * k)
	m.z = maxf(14, (win.x - safe.end.x) * k)
	m.w = maxf(14, (win.y - safe.end.y) * k)
	return m


## Slides a message down from the top, then fades it.
func toast(text: String, col := UI.AC, hold := 2.2) -> void:
	if text == "" or toast_layer == null:
		return
	for c in toast_layer.get_children():
		c.queue_free()
	var p := UI.panel(Color(UI.INK, 0.94), col, 3, 18, 14, 8)
	p.theme = theme   # a CanvasLayer does not inherit the theme: without it emoji show as boxes
	p.anchor_left = 0.06
	p.anchor_right = 0.94
	if _side_pad() > 0:
		p.anchor_left = 0
		p.anchor_right = 1
		p.offset_left = _side_pad() + 20
		p.offset_right = -_side_pad() - 20
	p.offset_top = 24
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.wrap_lbl(text, 19, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size.x = 560   # wrap at the panel width from the start, so the box stays short
	p.add_child(l)
	toast_layer.add_child(p)
	p.reset_size.call_deferred()
	p.modulate.a = 0
	p.position.y = -40
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(p, "position:y", 24.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


# =============================================================== render

func render() -> void:
	_render_queued = false
	UI.set_depth(_bg, 0.0 if run == null else float(mini(run.day, GameData.days) - 1) / float(GameData.days - 1))
	_refresh_tip.call_deferred()   # the card under the mouse may have changed or gone
	if screen:
		screen.queue_free()
	grid = null
	storage_panel = null
	storage_scroll = null
	sell_zone = null
	sell_lbl = null
	held_lbl = null
	popup = null
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen = root
	add_child(screen)
	move_child(screen, 1)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	# PC / landscape: every screen uses the bigger scale and its own wide layout
	var want := Vector2i(720, WIDE_H if _wide else 1280)
	if get_window().content_scale_size != want:
		get_window().content_scale_size = want
	var sm := _safe_margins(WIDE_W if _wide else COLUMN_W)
	m.add_theme_constant_override("margin_left", int(sm.x))
	m.add_theme_constant_override("margin_top", int(sm.y))
	m.add_theme_constant_override("margin_right", int(sm.z))
	m.add_theme_constant_override("margin_bottom", int(sm.w))
	screen.add_child(m)
	# the build version, small in the bottom-left corner of every screen (handy while testing)
	var ver := UI.lbl("v" + str(ProjectSettings.get_setting("application/config/version", "")), 12, Color(1, 1, 1, 0.35))
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 6
	ver.offset_top = -19
	ver.offset_bottom = -2
	ver.z_index = 50
	screen.add_child(ver)
	if run != null:
		_save_soon()   # saved shortly after (not on every tap); finished runs clear the save
		if run.msg != "":
			toast(run.msg)
			run.msg = ""
	var key := _key()
	var fresh := key != _screen_key
	_screen_key = key
	var body: Control
	if run == null:
		body = _title_screen()
	elif run.end_state != "" and run.mode == "trial":
		body = _trial_end_screen()
	elif run.end_state != "" and run.mode == "puzzle":
		body = _puzzle_end_screen()
	elif run.end_state != "":
		_send_play_log(run, run.end_state)
		body = _end_screen()
	elif run.phase == "evening" and _pending_sim != null:
		var cvw := CombatView.new().setup(run, _pending_sim, _wide)
		cvw.finished.connect(_on_combat_done)
		body = cvw
	else:
		body = _run_screen(fresh)
	m.add_child(body)
	if run == null or run.end_state != "" or (run.phase == "evening" and _pending_sim != null):
		if fresh:
			UI.pop_in(body, 0.0, 30)
		return
	var ov: Control = null
	if run.needs_path():
		ov = _path_choice_overlay()
	elif run.phase == "afternoon":
		ov = _road_overlay()
	elif run.phase == "event":
		ov = _event_overlay()
	elif run.phase == "night":
		ov = _night_overlay()
	elif run.phase == "morning" and _fusion_seen < _fusion_queue.size():
		ov = _fusion_overlay()
	elif show_book:
		ov = _book_overlay()
	elif show_effects:
		ov = _effects_overlay()
	if ov != null and not foe_info_e.is_empty():
		ov.add_child(_foe_info_overlay())
	if ov != null and _all_stats_cs != null and run.phase == "night":
		var so := _overlay("", func():
			_all_stats_cs = null
			render(), _wide)
		so[1].add_child(_summary_rows(_all_stats_cs))
		ov.add_child(so[0])
	if ov != null:
		screen.add_child(ov)
		if fresh:
			ov.modulate.a = 0
			ov.create_tween().tween_property(ov, "modulate:a", 1.0, 0.25)
	elif drag_item == null and not _landscape and (selected != null or inspect_id != ""):
		popup = _inspector_popup()
		screen.add_child(popup)


## Morning: last night's fusions / evolutions, up to 3 per page (Next page), with Skip all.
const FX_PER_PAGE := 3

func _fusion_overlay() -> Control:
	var o := _overlay("")
	var v: VBoxContainer = o[1]
	var n := _fusion_queue.size()
	var pages := ceili(n / float(FX_PER_PAGE))
	var page := _fusion_seen / FX_PER_PAGE
	if pages > 1:
		var c := UI.lbl(tr("Page %d / %d") % [page + 1, pages], 20, UI.MU, true)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(c)
	var k := 0
	for w in _fusion_queue.slice(_fusion_seen, _fusion_seen + FX_PER_PAGE):
		v.add_child(_fusion_card(w, 0.2 + 0.45 * k))
		k += 1
	var last := _fusion_seen + FX_PER_PAGE >= n
	var nb := UI.big_btn((tr("Next page") + " ▶️") if not last else (tr("Continue") + " ▶️"), func():
		_fusion_seen += FX_PER_PAGE
		render(), "green", 26)
	v.add_child(_center(nb))
	if not last:
		v.add_child(_center(UI.btn(tr("Skip all") + " ⏭️", func():
			_fusion_seen = n
			render(), false, 18, "gray")))
	return o[0]


## Full-screen dim with the monster Details panel; a tap anywhere closes it.
func _foe_info_overlay() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			foe_info_e = {}
			render())
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(cc)
	var w := minf(get_viewport_rect().size.x - 40.0, 760.0)
	var v := UI.vbox(8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(FoeInfo.build(foe_info_e, w))
	var hint := UI.lbl(tr("Tap anywhere to close."), 15, UI.MU, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	cc.add_child(v)
	return dim


func _key() -> String:
	if run == null:
		return "title" + str(title_step) + ("s" if _splash else "")
	if run.end_state != "":
		return "end"
	var k := run.phase + str(run.day)
	if run.needs_path():
		k += "path"
	if show_book:
		k += "book" + book_item
	if show_effects:
		k += "fx"
	if run.phase == "morning" and _fusion_seen < _fusion_queue.size():
		k += "fx%d" % _fusion_seen
	return k


## Full-screen popup layer. Content is centred vertically when it is short and scrolls when
## it is long; `close_cb` adds a ✖️ that stays in the corner whatever the scroll position.
func _overlay(title: String, close_cb := Callable(), wide := false) -> Array:
	var ov := ColorRect.new()
	ov.color = Color(0.04, 0.03, 0.02, 0.9)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + s, 20 + int(_side_pad(WIDE_W if wide else COLUMN_W)))
	mc.add_theme_constant_override("margin_top", 30)
	mc.add_theme_constant_override("margin_bottom", 30)
	ov.add_child(mc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 8
	mc.add_child(sc)
	var outer := UI.vbox(0)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(outer)
	outer.add_child(UI.spacer(false))
	var v := UI.vbox(18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(v)
	outer.add_child(UI.spacer(false))
	if title != "":
		var t := UI.title(title, 42, UI.GOLD)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
	if close_cb.is_valid():
		var x := UI.btn("✖️", close_cb, false, 22, "red")
		x.custom_minimum_size = Vector2(64, 64)
		x.anchor_left = 1
		x.anchor_right = 1
		x.offset_left = -80
		x.offset_right = -16
		x.offset_top = 16
		x.offset_bottom = 80
		ov.add_child(x)
	# let drags that start on cards/chips scroll the list (touch)
	v.child_entered_tree.connect(func(n): _pass_mouse.call_deferred(n))
	return [ov, v]


## Makes every panel under `n` pass input up, so a finger drag anywhere scrolls the parent.
func _pass_mouse(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if n is Control and not n is ScrollContainer and n.mouse_filter == Control.MOUSE_FILTER_STOP:
		n.mouse_filter = Control.MOUSE_FILTER_PASS
	for c in n.get_children():
		_pass_mouse(c)


func _center(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return c


# --------------------------------------------------------------- title
# 0 start screen » 1 hero » 2 pet » 3 difficulty » run

var title_step := 0
var _splash := true     # first screen of a launch: "tap anywhere", then the menu
var _hero_dir := 0      # -1 / +1 when the hero card was just swiped, for its slide-in
var _swipe_x := 0.0


func _title_screen() -> Control:
	var body: Control
	match title_step:
		1: body = _hero_screen()
		2: body = _pet_screen()
		3: body = _diff_screen()
		10: body = _trial_screen()
		11: body = _puzzle_screen()
		_: body = _start_screen()
	# scrolls on short screens; spacers inside still centre things on tall ones
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	return sc


func _start_screen() -> Control:
	var v := UI.vbox(16)
	var lang := UI.hbox(8)
	lang.add_child(UI.spacer())
	for code in ["en", "th"]:
		var cc: String = code
		lang.add_child(UI.btn("EN" if code == "en" else "ไทย", func():
			I18n.set_lang(cc)
			SaveGame.set_setting("lang", cc)
			render(), false, 16, "blue" if I18n.lang() == code else "gray"))
	v.add_child(lang)
	v.add_child(UI.spacer(false))
	var logo := UI.title("PACKCRAFT", 84, UI.GOLD, Color("#5a2300"))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(logo)
	UI.breathe(logo, 0.035)
	var tag := UI.lbl(tr("Pack it. Craft it. Watch it fight."), 22, UI.MU, true)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	# the party waiting at the dungeon door
	var party := UI.hbox(18 if _wide else 2)
	party.alignment = BoxContainer.ALIGNMENT_CENTER
	var k := 0
	var hero_px := 64 if _wide else clampi(int((minf(get_viewport_rect().size.x, COLUMN_W) - 90.0) / (GameData.class_keys.size() * 1.75)), 26, 64)
	for c in GameData.class_keys:
		var hl := UI.lbl(GameData.classes[c].hero, hero_px)
		party.add_child(hl)
		var tw := hl.create_tween().set_loops()
		tw.tween_interval(0.15 * k)
		tw.tween_property(hl, "position:y", -14.0, 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(hl, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
		k += 1
	v.add_child(party)
	var door := UI.lbl("🔥  🚪  🔥", 54)
	door.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(door)
	v.add_child(UI.spacer(false))
	if _splash:
		# splash: tap / click anywhere to open the menu (the language buttons still work)
		var hint := UI.title(tr("Click anywhere to start") if _landscape else tr("Tap anywhere to start"), 34, Color.WHITE, Color("#3d2716"))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(hint)
		var blink := hint.create_tween().set_loops()
		blink.tween_property(hint, "modulate:a", 0.2, 0.7).set_trans(Tween.TRANS_SINE)
		blink.tween_property(hint, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
		v.add_child(UI.spacer(false))
		var sv := UI.lbl("v" + str(ProjectSettings.get_setting("application/config/version", "")), 14, Color(UI.MU, 0.7))
		sv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sv)
		v.mouse_filter = Control.MOUSE_FILTER_STOP
		v.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_splash = false
				render())
		return v
	var summary := "" if _dev else SaveGame.run_summary()
	if summary != "":
		var cb := UI.btn("▶️ " + tr("CONTINUE") + "\n" + summary, _continue_run, false, 20, "gold")
		cb.custom_minimum_size = Vector2(0, 96)
		if _wide:
			cb.custom_minimum_size.x = 640
			cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(cb)
	var play := UI.big_btn("⚔️ " + tr("NEW GAME"), func():
		title_step = 1
		render(), "green", 34)
	play.custom_minimum_size = Vector2(0, 104)
	if _wide:
		play.custom_minimum_size.x = 640
		play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(play)
	UI.breathe(play, 0.03)
	var tb := UI.btn("🎓 " + tr("Class trials"), func():
		title_step = 10
		render(), false, 24, "blue")
	tb.custom_minimum_size = Vector2(640 if _wide else 0, 72)
	if _wide:
		tb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(tb)
	var pz := UI.btn("🧩 " + tr("Puzzles"), func():
		title_step = 11
		render(), false, 24, "purple")
	pz.custom_minimum_size = Vector2(640 if _wide else 0, 72)
	if _wide:
		pz.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pz)
	v.add_child(_center(UI.btn(tr("How to play") + (" 🔼" if show_how else " 🔽"), func():
		show_how = not show_how
		render(), false, 17, "purple")))
	if show_how:
		var hp := UI.panel(Color(UI.INK, 0.85), UI.BD, 2, 18, 16)
		hp.add_child(UI.wrap_lbl(tr("HOW_TO_PLAY"), 18, Color("#efe4cf")))
		v.add_child(hp)
	var ver := UI.lbl("v" + str(ProjectSettings.get_setting("application/config/version", "")), 14, Color(UI.MU, 0.7))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ver)
	return v


## Header for the three setup steps: "STEP 2 / 3" with dots.
func _step_head(n: int, title: String) -> Control:
	var v := UI.vbox(4)
	var dots := UI.hbox(10)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in range(1, 4):
		var d := UI.panel(UI.GOLD if i <= n else Color(1, 1, 1, 0.15), Color(0, 0, 0, 0), 0, 99, 0)
		d.custom_minimum_size = Vector2(48 if i == n else 18, 12)
		dots.add_child(d)
	v.add_child(dots)
	var t := UI.title(title, 36, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return v


func _step_nav(back_cb: Callable, next_text: String, next_cb: Callable, kind := "green") -> Control:
	var h := UI.hbox(10)
	var b := UI.btn("◀️ " + tr("Back"), back_cb, false, 20, "gray")
	b.custom_minimum_size = Vector2(150, 84)
	h.add_child(b)
	var n := UI.btn(next_text, next_cb, false, 26, kind)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.custom_minimum_size.y = 84
	h.add_child(n)
	UI.breathe(n, 0.02)
	return h


## Max HP and damage / shield / healing per second (from bench_rates) as [text, colour] pairs.
func _rate_texts(b: Dictionary) -> Array:
	var per := func(v: float) -> String: return "%s/%s" % [GameData._num(snappedf(v, 0.1)), tr("s")]
	return [["❤️ %d" % roundi(b.hp), Color("#ffb4b4")], ["⚔️ " + per.call(b.dps), Color("#ffd27a")], ["🛡️ " + per.call(b.sps), Color("#7dd3fc")], ["💚 " + per.call(b.hps), Color("#4ade80")]]


## The starting kit of a class on the training dummy (cached): Max HP and damage / shield / heal per second.
func _class_bench(k: String) -> Dictionary:
	if not _bench_cache.has(k):
		var r := RunState.new(k, "", "normal")
		r.mod = {"id": "", "n": "", "d": ""}
		_bench_cache[k] = r.bench_rates(12.0)
	return _bench_cache[k]


func _hero_screen() -> Control:
	var v := UI.vbox(12)
	v.add_child(_step_head(1, tr("Choose your hero")))
	var idx: int = GameData.class_keys.find(sel_cls)
	var c: Dictionary = GameData.classes[sel_cls]
	var col: Color = c.col
	# swipeable hero card, with arrows either side
	var row := UI.hbox(6)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var prev := UI.btn("◀️", func(): _hero_step(-1), false, 26, "purple")
	prev.custom_minimum_size = Vector2(58, 120)
	prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(prev)
	var card := UI.card(col.darkened(0.62), col, 26, 16)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_swipe_x = e.position.x
			elif absf(e.position.x - _swipe_x) > 70:
				_hero_step(-1 if e.position.x > _swipe_x else 1))
	row.add_child(card)
	var nxt := UI.btn("▶️", func(): _hero_step(1), false, 26, "purple")
	nxt.custom_minimum_size = Vector2(58, 120)
	nxt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nxt)
	var cv := UI.vbox(8)          # info column (the whole card on phones)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := cv                 # portrait column (PC: hero on top, starting bag below)
	if _wide:
		var hb := UI.hbox(28)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hb)
		pic = UI.vbox(14)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.custom_minimum_size.x = 430
		hb.add_child(pic)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_child(cv)
	else:
		card.add_child(cv)
	var hp_panel: Control = pic
	if _wide:
		hp_panel = UI.panel(Color(0, 0, 0, 0.28), col.darkened(0.2), 3, 22, 12)
		hp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pic.add_child(hp_panel)
	var hero := UI.plbl(c.hero, 190 if _wide else 120, UI.TX, false, true)
	hero.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_panel.add_child(hero)
	UI.breathe(hero, 0.06)
	if _wide:
		var bagp := UI.panel(Color(0, 0, 0, 0.28), col.darkened(0.2), 3, 22, 14)
		bagp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bv := UI.vbox(8)
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bagp.add_child(bv)
		bv.add_child(UI.plbl("🎒 " + tr("Starting bag"), 18, col.lightened(0.35), true, true))
		var sbv := StartBagView.new().setup(sel_cls, 62)
		sbv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		bv.add_child(sbv)
		pic.add_child(bagp)
	var nm := UI.title(c.ic + " " + tr(c.n), 42 if _wide else 34, Color.WHITE, col.darkened(0.7))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _wide else HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(nm)
	var dl := UI.wrap_lbl(tr(c.d), 22 if _wide else 18, Color("#f4ebd8"))
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _wide else HORIZONTAL_ALIGNMENT_CENTER
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(dl)
	# stat bars
	var sg := GridContainer.new()
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", 12)
	sg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icons := {"Damage": "⚔️", "Defense": "🛡️", "Sustain": "💚", "Difficulty": "🧠"}
	for s in ["Damage", "Defense", "Sustain", "Difficulty"]:
		sg.add_child(UI.plbl(icons[s] + " " + tr(s), 21 if _wide else 16, Color("#efe4cf"), true))
		var pips := UI.hbox(4)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var val := int(c.stats.get(s, 0))
		for p in 5:
			var pip := PanelContainer.new()   # a plain square block (a pixel frame would be too tall)
			pip.add_theme_stylebox_override("panel", UI.box(col if p < val else Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.5), 2, 2, 0))
			pip.custom_minimum_size = Vector2(52, 22) if _wide else Vector2(36, 16)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.add_child(pip)
		sg.add_child(pips)
	cv.add_child(sg)
	# the starting kit's real numbers, measured on a training dummy
	var b := _class_bench(sel_cls)
	var nums := UI.hbox(14)
	nums.alignment = BoxContainer.ALIGNMENT_BEGIN if _wide else BoxContainer.ALIGNMENT_CENTER
	nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := 19 if _wide else 15
	nums.add_child(UI.plbl(tr("At start:"), fs, Color("#cdbfa2"), true))
	for rt in _rate_texts(b):
		nums.add_child(UI.plbl(rt[0], fs, rt[1], true))
	cv.add_child(nums)
	var cap := UI.wrap_lbl(tr("Bars: average over the whole run (pro bot, 15 runs). Numbers: the starting items on a training dummy."), 15 if _wide else 12, Color(1, 1, 1, 0.5))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _wide else HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(cap)
	# signature skills
	var sk := UI.panel(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 14, 10)
	sk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skv := UI.vbox(6)
	skv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sk.add_child(skv)
	skv.add_child(UI.wrap_lbl("%s %s: %s" % [c.res.ic, tr(c.res.n), tr(c.res.d)], 20 if _wide else 16, Color("#efe4cf")))
	skv.add_child(UI.wrap_lbl("%s %s: %s" % [c.ult.ic, tr(c.ult.n), tr(c.ult.d)], 20 if _wide else 16, UI.GOLD))
	cv.add_child(sk)
	(pic if _wide else cv).add_child(_goals_panel(sel_cls, 18 if _wide else 15))   # PC: under the portrait, where there is room
	# how it is usually built
	var bt := UI.title("🧩 " + tr("How to build it"), 24 if _wide else 20, col.lightened(0.3))
	bt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(bt)
	for line in c.comp:
		var ll := UI.wrap_lbl("• " + tr(line), 17 if _wide else 15, Color("#f4ebd8"))
		ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(ll)
	var chips := UI.hbox(8)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(UI.plbl(tr("Starts with"), 15, UI.MU, true))
	for st in c.st:
		chips.add_child(UI.item_chip(st[0]))
	if not _wide:   # PC shows the starting bag picture instead
		cv.add_child(chips)
	v.add_child(row)
	# page dots
	var pd := UI.hbox(8)
	pd.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in GameData.class_keys.size():
		var d := UI.panel(UI.GOLD if i == idx else Color(1, 1, 1, 0.2), Color(0, 0, 0, 0), 0, 99, 0)
		d.custom_minimum_size = Vector2(34 if i == idx else 12, 12)
		pd.add_child(d)
	v.add_child(pd)
	v.add_child(_step_nav(func():
		title_step = 0
		render(), tr("Next") + " ▶️", func():
		title_step = 2
		render()))
	if _hero_dir != 0:
		# fade and grow in place: the card's position belongs to its row, so never tween it
		card.modulate.a = 0
		card.scale = Vector2(0.92, 0.92)
		card.resized.connect(func(): card.pivot_offset = card.size / 2)
		var tw := card.create_tween()
		tw.tween_property(card, "modulate:a", 1.0, 0.18)
		tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_hero_dir = 0
	return v


## What a class has left to earn, in one row: highest Ascension opened, deepest Endless floor and
## its two signature items (locked ones dimmed; their tooltip says how to unlock them).
func _goals_panel(cls: String, fs: int) -> Control:
	var best := 0
	var deep := 0
	for df in GameData.difficulties:
		best = maxi(best, _asc_open(cls, df.id))
		deep = maxi(deep, int(SaveGame.get_setting("endless_best_%s_%s" % [cls, df.id], 0)))
	var p := UI.panel(Color(0, 0, 0, 0.3), Color("#c8602c"), 2, 14, 8)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var medals := 0
	for p_id in GameData.classes[cls].paths:
		medals += 1 if int(SaveGame.get_setting("trial_" + p_id, 0)) > 0 else 0
	var txt := "🔥 " + tr("Ascension %d/%d") % [best, GameData.ascension.size()] + "   🎓 %d/%d" % [medals, GameData.classes[cls].paths.size()]
	if deep > 0:
		txt += "   ♾️ " + tr("Endless: floor %d") % deep
	var l := UI.wrap_lbl(txt, fs + 1, Color("#ffb37a"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	var sigs := GameData.items.keys().filter(func(k): return GameData.items[k].cl == cls and GameData.items[k].sig > 0)
	sigs.sort_custom(func(x, y): return GameData.items[x].sig < GameData.items[y].sig)
	for id in sigs:
		var d: Dictionary = GameData.items[id]
		var got := not RunState.locked.has(id)
		var chip := UI.item_chip(id, got)
		if not got:
			chip.modulate = Color(1, 1, 1, 0.35)
		chip.tooltip_text = "🎁 " + tr(d.n) + "
" + (tr(d.d) if got else (tr("Unlock: win with this class.") if d.sig == 1 else tr("Unlock: open Ascension 5 with this class.")))
		h.add_child(chip)
	return p


func _hero_step(d: int) -> void:
	var keys := GameData.class_keys
	var i: int = (keys.find(sel_cls) + d + keys.size()) % keys.size()
	sel_cls = keys[i]
	_hero_dir = d
	render()


func _pet_screen() -> Control:
	var v := UI.vbox(14)
	v.add_child(_step_head(2, tr("Choose your pet")))
	var sub := UI.wrap_lbl(tr("Your pet gives a small buff for the whole run."), 18, UI.MU)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	if not GameData.pets.has(sel_pet):
		sel_pet = GameData.pet_keys[0]
	# the whole screen is the pet grid; the chosen pet just lights up
	var g := GridContainer.new()
	g.columns = 4 if _wide else 2
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(g)
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for k in GameData.pet_keys:
		var kk: String = k
		var p: Dictionary = GameData.pets[k]
		var on: bool = k == sel_pet
		var c := UI.card(Color("#5a3f12") if on else UI.PN, UI.GOLD if on else Color("#6b5636"), 18, 6)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL   # the tiles share the rest of the screen
		var cv := UI.vbox(2)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		c.add_child(cv)
		var pic := UI.plbl(p.ic, 96 if _wide else 64, UI.TX, false, true)
		cv.add_child(pic)
		if on:
			UI.breathe(pic, 0.08)
		var nl := UI.plbl(tr(p.n), 19 if _wide else 16, UI.GOLD if on else UI.TX, true, true)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size.x = 120
		cv.add_child(nl)
		# what it does, so pets can be compared without tapping each one
		var pdl := UI.plbl(tr(p.d), 16 if _wide else 14, Color("#f6e3b4") if on else UI.MU, false, true)
		pdl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pdl.custom_minimum_size.x = 120
		cv.add_child(pdl)
		UI.on_tap(c, func():
			sel_pet = kk
			render())
		UI.juice(c)
		UI.hover_glow(c)
		g.add_child(c)
	v.add_child(_step_nav(func():
		title_step = 1
		render(), tr("Next") + " ▶️", func():
		title_step = 3
		render()))
	return v


func _diff_screen() -> Control:
	var v := UI.vbox(12)
	v.add_child(_step_head(3, tr("Difficulty")))
	var list: Container = v
	if _wide:
		# PC: the four modes as a 2 x 2 grid of big cards
		var dg := GridContainer.new()
		dg.columns = 2
		dg.add_theme_constant_override("h_separation", 18)
		dg.add_theme_constant_override("v_separation", 18)
		dg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(dg)
		list = dg
	var kinds := {"normal": Color("#3fd17a"), "hard": Color("#ffc93c"), "vhard": Color("#ff5d6c"), "abyss": Color("#9b74c4")}
	for df in GameData.difficulties:
		var id: String = df.id
		var on: bool = id == sel_diff
		var col: Color = kinds.get(id, UI.BD)
		var c := UI.card(col.darkened(0.55) if on else UI.PN, col if on else UI.BD, 22, 14)
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL   # the four cards share the screen
		var h := UI.hbox(14)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(h)
		var il := UI.plbl(df.ic, 90 if _wide else 76)
		if _wide:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		h.add_child(il)
		var tv := UI.vbox(2)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # centred in the tall card
		h.add_child(tv)
		var tl := UI.title(tr(df.n), 34 if _wide else 26, col.lightened(0.2) if on else Color.WHITE)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(tl)
		var dl := UI.wrap_lbl(tr(df.d), 21 if _wide else 16, Color("#efe4cf"))
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(dl)
		var who := {"normal": "Recommended for your first runs.", "hard": "For players who can beat Normal.", "vhard": "A real challenge: plan your build.", "abyss": "Nearly impossible. Good luck."}
		var wl := UI.plbl(tr(who.get(id, "")), 16 if _wide else 14, col.lightened(0.35), true)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(wl)
		# what this mode adds, as chips
		var chips := HFlowContainer.new()
		chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 4)
		var adds := ["❤️ ×%.2f · ⚔️ ×%.2f" % [df.hp, df.dps]]
		if df.get("pet", false):
			adds.append("🐾 " + tr("Monster pets"))
		if df.get("ult", false):
			adds.append("⭐ " + tr("Monster Ultimates"))
		if float(df.elite) > 0.0:
			adds.append("👹 " + tr("More Elites (+%d%%)") % roundi(float(df.elite) * 100.0))
		for a in adds:
			chips.add_child(_chip(a, UI.MU))
		tv.add_child(chips)
		if on:
			UI.breathe(il, 0.1)
		UI.on_tap(c, func():
			sel_diff = id
			render())
		UI.juice(c)
		UI.hover_glow(c)
		list.add_child(c)
	v.add_child(_asc_picker())
	var cls: Dictionary = GameData.classes[sel_cls]
	var pet: Dictionary = GameData.pets.get(sel_pet, {})
	var sum := UI.lbl("%s %s   +   %s %s   ·   %s %s%s" % [cls.hero, tr(cls.n), pet.get("ic", ""), tr(pet.get("n", "")), GameData.diff_def(sel_diff).ic, tr(GameData.diff_def(sel_diff).n), ("   🔥%d" % sel_asc) if sel_asc > 0 else ""], 18, UI.GOLD, true)
	sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sum)
	v.add_child(_step_nav(func():
		title_step = 2
		render(), "⚔️ " + tr("START RUN"), func():
		SaveGame.set_setting("pet", sel_pet)
		SaveGame.set_setting("diff", sel_diff)
		_send_play_log(SaveGame.load_run(), "quit")   # a saved run left unfinished
		run = RunState.new(sel_cls, sel_pet, sel_diff, sel_asc)
		run.plog_start()
		title_step = 0
		_clear_sel()
		anim.clear()
		render(), "red" if sel_diff in ["vhard", "abyss"] else "green"))
	return v


## Locks the signature items not earned yet (first win with the class: the 1st; Ascension 5: the 2nd).
## Returns the ids that just unlocked.
func _refresh_locks() -> Array:
	var before: Dictionary = RunState.locked.duplicate()
	RunState.locked = {}
	for id in GameData.items:
		var d: Dictionary = GameData.items[id]
		if d.sig <= 0:
			continue
		var open := 0
		for df in GameData.difficulties:
			open = maxi(open, _asc_open(d.cl, df.id))
		if open < (1 if d.sig == 1 else 5):
			RunState.locked[id] = true
	return before.keys().filter(func(k): return not RunState.locked.has(k))


## A one-time explanation the first time a player meets a system (kept per player in the settings).
func _first_tip(key: String, text: String) -> void:
	if _dev or SaveGame.get_setting("tip_" + key, false):
		return
	SaveGame.set_setting("tip_" + key, true)
	toast(text, Color("#7dd3fc"), 7.0)


# ---------------------------------------------------------------- puzzles

## A puzzle's name: lessons have their own, challenges are "<class> vs <boss>".
func _puzzle_name(p: Dictionary) -> String:
	if int(p.ch) == 2:
		return tr(GameData.classes[p.cls].n) + " vs " + tr(str(p.foe.n))
	return tr(str(p.n))


func _stars_text(n: int) -> String:
	return ("⭐".repeat(n) + " " if n > 0 else "") + "%d/3" % n   # the web build has no font with a hollow star


## The puzzle list: lessons, then challenges, each with the stars earned.
func _puzzle_screen() -> Control:
	var v := UI.vbox(10)
	var total := 0
	for p in GameData.puzzles:
		total += int(SaveGame.get_setting("puzzle_" + str(p.id), 0))
	var t := UI.title("🧩 " + tr("Puzzles") + "   ⭐ %d/%d" % [total, GameData.puzzles.size() * 3], 34, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UI.wrap_lbl(tr("Arrange the items you are given and win one fight. More HP left, more stars."), 17, UI.MU)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	for ch in [1, 2]:
		v.add_child(UI.lbl(("📘 " + tr("Lessons")) if ch == 1 else ("💀 " + tr("Challenges: packs the bot won with")), 20, Color("#bfe3ff"), true))
		var grid := GridContainer.new()
		grid.columns = 3 if _wide else 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		v.add_child(grid)
		for p in GameData.puzzles:
			if int(p.ch) != ch:
				continue
			var stars := int(SaveGame.get_setting("puzzle_" + str(p.id), 0))
			var pp: Dictionary = p
			var b := UI.btn(GameData.classes[p.cls].hero + " " + _puzzle_name(p) + "\n" + _stars_text(stars), func():
				_start_puzzle(pp), false, 15, "gold" if stars >= 3 else "purple" if stars > 0 else "gray")
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size.y = 64
			grid.add_child(b)
	var back := UI.btn("◀️ " + tr("Back"), func():
		title_step = 0
		render(), false, 20, "gray")
	back.custom_minimum_size = Vector2(0, 64)
	v.add_child(back)
	return v


func _start_puzzle(p: Dictionary) -> void:
	run = RunState.new(str(p.cls), "", "normal")
	run.start_puzzle(p)
	title_step = 0
	arr_plan = {}
	_clear_sel()
	anim.clear()
	render()


## In the shop's place during a puzzle: what it teaches, the foe, Fight / Hint / Leave.
func _puzzle_panel() -> Control:
	var p := UI.card(Color("#2a1f3a", 0.96), Color("#a78bfa"), 22, 12)
	var v := UI.vbox(8)
	p.add_child(v)
	var pz: Dictionary = run.puzzle
	v.add_child(UI.title("🧩 " + _puzzle_name(pz), 22, Color("#ddd6fe")))
	var d := UI.wrap_lbl(tr(str(pz.d)), 16, Color("#efe4cf"))
	v.add_child(d)
	var e: Dictionary = run.nodes[0].e
	var foe := "%s %s  ❤️ %d  ⚔️ %.1f/%s" % [GameData.foe_icon(e.n), tr(str(e.n)), roundi(e.hp), e.dps, tr("s")]
	if str(e.get("imm", "")) != "":
		foe += "  🛡️ " + tr("resists %s") % (GameData.elem_icon(e.imm) + tr(e.imm))
	v.add_child(UI.lbl(foe, 16, UI.MU, true))
	if run.puzzle_hint:
		v.add_child(UI.lbl("🪄 " + tr("Hint used: this try earns at most 2 stars."), 15, UI.MU))
	var bt := UI.hbox(8)
	var leave := UI.btn("◀️ " + tr("Leave"), func():
		run = null
		title_step = 11
		render(), false, 18, "gray")
	leave.custom_minimum_size = Vector2(120, 64)
	bt.add_child(leave)
	var fight := UI.btn("⚔️ " + tr("Fight!"), func():
		if drag_item != null or run.grid_items().is_empty():
			return
		run.travel()
		_clear_sel()
		_choose(0), false, 24, "green")
	fight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fight.custom_minimum_size.y = 64
	bt.add_child(fight)
	v.add_child(bt)
	return p


## A finished puzzle: its stars (kept when better than before), and where to go next.
func _puzzle_end_screen() -> Control:
	var cc := CenterContainer.new()
	var v := UI.vbox(14)
	v.custom_minimum_size.x = 640.0
	cc.add_child(v)
	var pz: Dictionary = run.puzzle
	var stars := int(run.result.get("stars", 0))
	var key := "puzzle_" + str(pz.id)
	if stars > 0 and not _dev and stars > int(SaveGame.get_setting(key, 0)):
		SaveGame.set_setting(key, stars)
	var t := UI.title(_stars_text(stars) if stars > 0 else ("💀 " + tr("Not this time")), 52, UI.GOLD if stars > 0 else UI.BAD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l := UI.wrap_lbl("🧩 " + _puzzle_name(pz) + "\n" + (tr("More HP left means more stars: try another layout for 3.") if stars in [1, 2] else tr("Perfect!") if stars >= 3 else tr("Try another layout: what touches what matters.")), 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var again := UI.big_btn("🔁 " + tr("Try again"), func(): _start_puzzle(pz), "green", 26)
	v.add_child(again)
	var i := GameData.puzzles.find(pz)
	if i >= 0 and i + 1 < GameData.puzzles.size():
		var nxt: Dictionary = GameData.puzzles[i + 1]
		var nb := UI.btn("▶️ " + tr("Next puzzle"), func(): _start_puzzle(nxt), false, 22, "purple")
		nb.custom_minimum_size.y = 64
		v.add_child(nb)
	var lst := UI.btn("🧩 " + tr("All puzzles"), func():
		run = null
		title_step = 11
		render(), false, 20, "gray")
	lst.custom_minimum_size.y = 60
	v.add_child(lst)
	return cc


# ---------------------------------------------------------------- class trials

## The trial picker: every class with its three paths; a path shows the medal earned there.
func _trial_screen() -> Control:
	var v := UI.vbox(12)
	var t := UI.title("🎓 " + tr("Class trials"), 36, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UI.wrap_lbl(tr("A short guided run for each path: buy what the steps say, put it together, and build the path's Masterwork before the training boss."), 17, UI.MU)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 3 if _wide else 1
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for c in GameData.class_keys:
		var cd: Dictionary = GameData.classes[c]
		var card := UI.card(Color(cd.col).darkened(0.65), Color(cd.col), 18, 10)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UI.vbox(6)
		card.add_child(cv)
		cv.add_child(UI.lbl(cd.hero + " " + tr(cd.n), 20, Color.WHITE, true))
		var row := UI.hbox(6)
		cv.add_child(row)
		for p_id in cd.paths:
			var pd: Dictionary = GameData.paths[p_id]
			var medal := int(SaveGame.get_setting("trial_" + p_id, 0))
			var cls_id: String = c
			var path_id: String = p_id
			var b := UI.btn(pd.ic + " " + tr(pd.n) + ("  🥇" if medal >= 2 else "  🎓" if medal == 1 else ""), func():
				run = RunState.new(cls_id, "", "normal")
				run.start_trial(path_id)
				title_step = 0
				_clear_sel()
				anim.clear()
				render(), false, 15, "gold" if medal > 0 else "gray")
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size.y = 48
			row.add_child(b)
		grid.add_child(card)
	var back := UI.btn("◀️ " + tr("Back"), func():
		title_step = 0
		render(), false, 20, "gray")
	back.custom_minimum_size = Vector2(0, 64)
	v.add_child(back)
	return v


## One trial step as a line of text.
func _trial_step_text(s: Dictionary) -> String:
	var nm := func(id: String) -> String: return GameData.items[id].ic + " " + tr(GameData.items[id].n)
	match s.t:
		"buy":
			return "🛒 " + tr("Buy %s") % nm.call(s.id) + (" ×%d" % s.n if s.n > 1 else "")
		"link":
			if s.get("evo", false):
				return "🔗 " + tr("Put two %s together: tonight they evolve into %s") % [nm.call(s.ids[0]), nm.call(s.r)]
			return "🔗 " + tr("Put %s next to %s: tonight they fuse into %s") % [nm.call(s.ids[0]), nm.call(s.ids[1]), nm.call(s.r)]
		"mw":
			return "⭐ " + tr("Put %s, %s and %s together: tonight they become the Masterwork %s") % [nm.call(s.ids[0]), nm.call(s.ids[1]), nm.call(s.ids[2]), nm.call(s.r)]
		"tip":
			var mw: String = nm.call(run.trial.mw.r)
			match s.k:
				"start":
					return "👋 " + tr("Follow the steps: the goal is %s before the training boss on floor 5. Tap a Golden Link you don't want to switch it off.") % mw
				"arrange":
					return "🎒 " + tr("Arrange %s and the rest so they buff each other (try 🪄).") % mw
				"boss":
					return "💀 " + tr("Training boss! Beat it with %s.") % mw
	return ""


## Today's steps still to do (at most 3) under a header that counts the done ones. The day's tip
## comes as a toast when the day starts (see _run_screen), so the panel stays short on phones.
func _trial_steps_panel() -> Control:
	var p := UI.card(Color("#1d2a36", 0.95), Color("#6fa3c8"), 16, 8)
	var v := UI.vbox(3)
	p.add_child(v)
	var todo := run.trial_steps().filter(func(x): return x.step.t != "tip")
	var open := todo.filter(func(x): return not x.done)
	v.add_child(UI.lbl("📋 " + tr("Trial · day %d of %d") % [run.day, RunState.TRIAL_DAYS] + "   ✔ %d/%d" % [todo.size() - open.size(), todo.size()], 16, Color("#bfe3ff"), true))
	for st in open.slice(0, 3):
		v.add_child(UI.wrap_lbl(_trial_step_text(st.step), 15, Color.WHITE))
	if open.is_empty():
		v.add_child(UI.wrap_lbl("✅ " + tr("All done for today: head out!"), 15, UI.GOOD))
	return p


## The end of a trial: the medal (🥇 when no Heart was lost), and where to go next.
func _trial_end_screen() -> Control:
	var cc := CenterContainer.new()
	var v := UI.vbox(14)
	v.custom_minimum_size.x = 640.0
	cc.add_child(v)
	var won := run.end_state == "win"
	var pd: Dictionary = GameData.paths[run.trial.path]
	if won and not run.has_meta("medal"):
		var medal := 2 if run.res >= run.max_hearts() else 1
		run.set_meta("medal", medal)
		if not _dev:   # layout tests play trials too: they must not hand out medals
			SaveGame.set_setting("trial_" + run.trial.path, maxi(medal, int(SaveGame.get_setting("trial_" + run.trial.path, 0))))
	var t := UI.title(("🎓 " + tr("Trial passed!")) if won else ("💀 " + tr("Trial failed")), 48, UI.GOLD if won else UI.BAD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var line: String = pd.ic + " " + tr(pd.n)
	if won:
		line += "\n" + (("🥇 " + tr("Gold medal: no Heart lost.")) if int(run.get_meta("medal")) >= 2 else ("🎓 " + tr("Medal earned. Pass without losing a Heart for gold.")))
	else:
		line += "\n" + tr("Follow the steps a little closer and try again.")
	var l := UI.wrap_lbl(line, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var path_id: String = run.trial.path
	var cls_id: String = run.cls
	var again := UI.big_btn("🔁 " + tr("Try this trial again"), func():
		run = RunState.new(cls_id, "", "normal")
		run.start_trial(path_id)
		_clear_sel()
		anim.clear()
		render(), "green", 26)
	v.add_child(again)
	var other := UI.btn("🎓 " + tr("Other trials"), func():
		run = null
		title_step = 10
		render(), false, 22, "blue")
	other.custom_minimum_size.y = 64
	v.add_child(other)
	return cc


## Highest Ascension open for a class on a mode (beat level N to open N+1).
func _asc_open(c: String, d: String) -> int:
	return int(SaveGame.get_setting("asc_%s_%s" % [c, d], 0))


## Ascension picker on the difficulty step: ◀ level ▶, and what the newest rule adds.
func _asc_picker() -> Control:
	var open := _asc_open(sel_cls, sel_diff)
	sel_asc = clampi(sel_asc, 0, open)
	if open > 0:
		_first_tip.call_deferred("asc", "🔥 " + tr("Ascension is open! Pick a level with the arrows: each one adds a rule. Win it to open the next."))
	var p := UI.card(Color("#2a1a12", 0.95), Color("#c8602c") if sel_asc > 0 else UI.BD, 18, 10)
	var h := UI.hbox(10)
	p.add_child(h)
	var lt := UI.btn("◀", func():
		sel_asc = maxi(0, sel_asc - 1)
		render(), false, 20, "gray")
	lt.disabled = sel_asc <= 0
	lt.custom_minimum_size = Vector2(56, 52)
	h.add_child(lt)
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var head := "🔥 " + tr("Ascension %d") % sel_asc + "  (" + tr("open: %d/%d") % [open, GameData.ascension.size()] + ")"
	var hl := UI.lbl(head, 18, Color("#ffb37a") if sel_asc > 0 else UI.MU, true)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(hl)
	var sub := ""
	if sel_asc == 0:
		sub = tr("Win with this class on this mode to open Ascension 1.") if open == 0 else tr("Off: normal rules. Higher levels stack new rules.")
	else:
		sub = tr(GameData.ascension[sel_asc - 1].d) + (("  " + tr("(+%d earlier rules)") % (sel_asc - 1)) if sel_asc > 1 else "")
	var sl := UI.wrap_lbl(sub, 15, Color("#efe4cf"))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(sl)
	var rt := UI.btn("▶", func():
		sel_asc = mini(open, sel_asc + 1)
		render(), false, 20, "gray")
	rt.disabled = sel_asc >= open
	rt.custom_minimum_size = Vector2(56, 52)
	h.add_child(rt)
	return p


func _end_screen() -> Control:
	var cc := CenterContainer.new()
	var v := UI.vbox(10 if not _wide else 12)
	v.custom_minimum_size.x = 1500.0 if _wide else 680.0
	cc.add_child(v)
	var w := run.end_state == "win"
	var t := UI.title(("♾️ " + tr("ENDLESS")) if run.endless else (("🏆 " + tr("VICTORY")) if w else ("💀 " + tr("DEFEATED"))), 52 if _wide else 44, UI.GOLD if w or run.endless else UI.BAD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var line := (tr("%s falls. Your build held.") % tr(run.boss_on(GameData.days).n if run.boss_on(GameData.days) != null else "")) if w else tr("You fell on day %d of %d.") % [run.day, GameData.days]
	if run.endless:
		# Endless: how far you got, and the best on this difficulty
		var key := "endless_best_" + run.diff
		if not run.has_meta("best_before"):
			run.set_meta("best_before", int(SaveGame.get_setting(key, 0)))
		var best: int = run.get_meta("best_before")
		if run.day > int(SaveGame.get_setting(key, 0)):
			SaveGame.set_setting(key, run.day)
		var ck := "endless_best_%s_%s" % [run.cls, run.diff]
		if run.day > int(SaveGame.get_setting(ck, 0)):
			SaveGame.set_setting(ck, run.day)
		line = tr("Endless: you reached day %d.") % run.day + "  " + (("🏅 " + tr("New best!")) if run.day > best else tr("Best on this difficulty: day %d") % best)
	if w and not run.endless:
		# Ascension: this win opens the next level for this class on this mode
		if not run.has_meta("asc_new"):
			var open := _asc_open(run.cls, run.diff)
			var nxt := mini(run.asc + 1, GameData.ascension.size())
			run.set_meta("asc_new", nxt if nxt > open else 0)
			if nxt > open:
				SaveGame.set_setting("asc_%s_%s" % [run.cls, run.diff], nxt)
			run.set_meta("sig_new", _refresh_locks())
		for id in run.get_meta("sig_new", []):
			line += "
🎁 " + tr("New item unlocked: %s") % (GameData.items[id].ic + " " + tr(GameData.items[id].n))
		if int(run.get_meta("asc_new")) > 0:
			line += "\n🔓 " + tr("Ascension %d unlocked for %s on %s!") % [int(run.get_meta("asc_new")), tr(run.cls_def().n), tr(run.diff_def().n)]
	var s := UI.wrap_lbl(line, 20 if _wide else 18)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(_end_header())
	if _wide:
		# PC: the pack and the buffs side by side
		var cols := UI.hbox(14)
		var pk := _end_pack_panel(Vector2(700, 430))
		var bf := _end_buffs_panel()
		pk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(pk)
		cols.add_child(bf)
		v.add_child(cols)
	else:
		# phone: one tab at a time
		var tabs := UI.hbox(10)
		for i in 2:
			var ii := i
			var tb := UI.btn(["🎒 " + tr("Final pack"), "✨ " + tr("All buffs")][i], func():
				_end_tab = ii
				render(), _end_tab == i, 18, "gold" if _end_tab == i else "gray")
			tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tabs.add_child(tb)
		v.add_child(tabs)
		v.add_child(_end_pack_panel(Vector2(640, 400)) if _end_tab == 0 else _end_buffs_panel())
	var b := UI.big_btn("🔁 " + tr("PLAY AGAIN"), func():
		_end_tab = 0
		run = null
		render(), "green", 28)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	if w:
		for k in 5:
			cc.create_tween().tween_callback(func(): UI.burst(cc, Vector2(randf_range(80, 640), randf_range(200, 500)), [UI.GOLD, UI.GOOD, UI.STAR, Color("#4f8cff")].pick_random(), 40, 420, 9)).set_delay(0.3 + k * 0.35)
	return cc


## End screen header: who you played and how the run went.
func _end_header() -> Control:
	var card := UI.card(Color(UI.PN, 0.92), run.cls_def().col, 18, 12)
	var hb := UI.hbox(14)
	card.add_child(hb)
	hb.add_child(UI.lbl(run.cls_def().hero, 64 if _wide else 52))
	var cv := UI.vbox(6)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(cv)
	var who: String = str(run.cls_def().ic) + " " + tr(run.cls_def().n)
	if run.path != "":
		who += "  ·  " + run.path_def().ic + " " + tr(run.path_def().n)
	cv.add_child(UI.title(who, 26 if _wide else 21, Color.WHITE))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	var dd := run.diff_def()
	chips.add_child(_chip(str(dd.ic) + " " + tr(dd.n), UI.GOLD))
	var pt: Dictionary = GameData.pets.get(run.pet, {})
	if not pt.is_empty():
		chips.add_child(_chip(str(pt.ic) + " " + tr(pt.n), Color("#d9c49a")))
	if str(run.mod.get("n", "")) != "":
		chips.add_child(_chip("🌍 " + tr(run.mod.n), Color("#93c5fd")))
	chips.add_child(_chip("📅 " + tr("Day %d/%d") % [run.day, GameData.days], UI.MU))
	chips.add_child(_chip("⭐ " + tr("Lv %d") % run.lv, Color("#bae6fd")))
	if run.asc > 0:
		chips.add_child(_chip("🔥 " + tr("Ascension %d") % run.asc, Color("#ffb37a")))
	chips.add_child(_chip("❤️ ×%d" % run.res, Color("#fca5a5")))
	chips.add_child(_chip("🪙 %d" % run.gold, UI.GOLD))
	cv.add_child(chips)
	return card


## The pack the run ended with (drawn small) and its real numbers on the training dummy.
func _end_pack_panel(room: Vector2) -> Control:
	var card := UI.card(Color(UI.PN, 0.92), UI.BD, 18, 12)
	var cv := UI.vbox(8)
	card.add_child(cv)
	cv.add_child(UI.title("🎒 " + tr("Final pack"), 22, UI.GOLD))
	var g := run.grid_items()
	if g.is_empty():
		cv.add_child(UI.lbl(tr("Empty pack."), 18, UI.MU))
		return card
	var lo := Vector2i(99, 99)
	var hi := Vector2i(-1, -1)
	for it in g:
		for c in it.cells():
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var gw := hi.x - lo.x + 1
	var gh := hi.y - lo.y + 1
	var e := {"gw": gw, "gh": gh, "items": g.map(func(it): return [it.id, it.x - lo.x, it.y - lo.y, it.rot])}
	var cell := floorf(minf(minf((room.x - 40.0) / gw, (room.y - 120.0) / gh), 72.0))
	var mp := MiniPack.new().setup(e, cell)
	var mc := CenterContainer.new()
	mc.add_child(mp)
	cv.add_child(mc)
	var b := run.bench_rates(12.0)
	var nums := HFlowContainer.new()
	nums.alignment = FlowContainer.ALIGNMENT_CENTER
	nums.add_theme_constant_override("h_separation", 6)
	for rt in _rate_texts(b):
		nums.add_child(_chip(rt[0], rt[1]))
	nums.add_child(_chip("🧩 %d" % g.size(), UI.MU))
	cv.add_child(nums)
	return card


## Every buff the run ended with: level-ups, pet, path relic, Masterwork, growing items, run modifier.
func _end_buffs_panel() -> Control:
	var card := UI.card(Color(UI.PN, 0.92), UI.BD, 18, 12)
	var cv := UI.vbox(6)
	card.add_child(cv)
	cv.add_child(UI.title("✨ " + tr("All buffs"), 22, UI.GOLD))
	var fs := 17 if _wide else 16
	var rows := []
	# level-up bonuses (stacked picks of the same bonus count together)
	for k in run.lvl_bonus:
		var total := float(run.lvl_bonus[k])
		if total <= 0.0:
			continue
		for pd in GameData.leveling.get("picks", []):
			if pd.k == k:
				rows.append(["%s %s ×%d" % [pd.ic, tr(pd.n), maxi(1, roundi(total / float(pd.v)))], tr(pd.d), Color("#fde68a")])
				break
	if rows.is_empty():
		rows.append(["⭐ " + tr("Level-ups"), tr("No level-up bonuses."), UI.MU])
	var pt: Dictionary = GameData.pets.get(run.pet, {})
	if not pt.is_empty():
		rows.append(["%s %s" % [pt.ic, tr(pt.n)], tr(pt.d), Color("#d9c49a")])
	if run.path != "":
		var pd2 := run.path_def()
		var relic: String = str(pd2.get("relic", ""))
		var rtxt: String = tr(GameData.items[relic].n) if GameData.items.has(relic) else ""
		rows.append(["%s %s" % [pd2.ic, tr(pd2.n)], rtxt, Color("#fdba74")])
	for it in run.grid_items():
		if GameData.recipes.any(func(rc): return str(rc.get("c", "")) != "" and rc.r == it.id):
			rows.append(["👑 " + tr("Masterwork"), "%s %s" % [it.def().ic, tr(it.def().n)], UI.GOLD])
	var grown := []
	for it in run.grid_items():
		var gr: Dictionary = it.def().get("grow", {})
		if not gr.is_empty() and it.gc > 0:
			grown.append("%s %s %d/%d" % [it.def().ic, tr(it.def().n), it.gc, int(gr.get("max", 12))])
	if not grown.is_empty():
		rows.append(["⭐ " + tr("Growing items"), ", ".join(grown), Color("#a7f3d0")])
	if str(run.mod.get("n", "")) != "":
		rows.append(["🌍 " + tr(run.mod.n), tr(run.mod.get("d", "")), Color("#93c5fd")])
	for r in rows:
		var hb := UI.hbox(8)
		var nm := UI.lbl(r[0], fs, r[2], true)
		nm.custom_minimum_size.x = 210 if _wide else 190
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hb.add_child(nm)
		var d := UI.wrap_lbl(r[1], fs - 1, Color("#efe4cf"))
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(d)
		cv.add_child(hb)
	return card


# --------------------------------------------------------------- run screen

func _run_screen(fresh: bool) -> Control:
	run.sync_hp()
	# everything else on this screen is ~1000px tall; the pack gets the rest (phones vary a lot)
	cell_px = clampf(floorf((get_viewport_rect().size.y - (1040.0 if run.mode == "trial" else 930.0)) / GameData.H), 34.0, 82.0)
	if _wide:
		# PC: the pack has the whole left half to itself
		var vp := get_viewport_rect().size
		var left_w := (minf(vp.x, WIDE_W) - 40.0) * 0.5
		cell_px = clampf(floorf(minf((vp.y - 276.0) / GameData.H, (left_w - 60.0) / GameData.W)), 40.0, 110.0)
	var root := UI.vbox(10)
	root.add_child(_memo("hud", _hud_key(), _hud))
	var steps: Control = null
	if run.mode == "trial" and run.phase == "morning":
		steps = _trial_steps_panel()
		root.add_child(steps)
		if fresh:
			for st in run.trial_steps():
				if st.step.t == "tip":
					toast(_trial_step_text(st.step), Color("#7dd3fc"), 6.0)

	# backpack
	var gp := UI.card(Color("#3a2818", 0.96), Color("#7a5232"), 22, 10)
	var gv := UI.vbox(6)
	gp.add_child(gv)
	var gh := UI.hbox(8)
	gh.add_child(UI.title("🎒 " + tr("Pack"), 24))
	var pr := run.pack_rates()
	var used := 0
	for it in run.grid_items():
		used += it.cells().size()
	var stats := UI.hbox(6)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.alignment = BoxContainer.ALIGNMENT_END
	stats.add_child(_chip("⚔️ %.1f" % pr.x, Color("#ff9b5e")))
	stats.add_child(_chip("🛡️ %.1f" % pr.y, Color("#7dd3fc")))
	stats.add_child(_chip("🔲 %d/%d" % [used, run.tiles.size()], UI.MU))
	gh.add_child(stats)
	var book := UI.btn("📖", func():
		show_book = true
		book_item = ""
		render(), false, 22, "purple")
	book.custom_minimum_size = Vector2(60, 56)
	if run.phase == "morning" and arr_plan.is_empty() and run.items.any(func(i): return i.loc == "grid" or i.loc == "storage"):
		# 🪄 hint: the best layout from pack + storage, as outlines to follow (it never moves items itself)
		var wand := UI.btn("🪄", func():
			if drag_item != null or _arr_busy:
				return
			# planning takes a moment on the web: say so first, then think
			_arr_busy = true
			toast("🪄 " + tr("Looking for the best layout..."), UI.MU)
			await get_tree().process_frame
			await get_tree().process_frame
			_arr_busy = false
			if run == null or run.phase != "morning":
				return
			var plan := run.plan_arrange()
			if plan.is_empty():
				toast("🪄 " + tr("Already the best layout I can find."), UI.MU)
			elif run.mode == "puzzle":
				# puzzles are about arranging it yourself: only the outlines, and at most 2 stars
				_clear_sel()
				arr_plan = plan
				run.puzzle_hint = true
				_first_tip("hint", "🪄 " + tr("Follow the blue outlines: drag each item there yourself. The hint closes when the pack matches."))
			else:
				_clear_sel()
				run.apply_arrange(plan.moves)
				arr_done = plan
				var a: Vector3 = plan.before
				var b: Vector3 = plan.after
				toast("🪄 " + tr("Arranged: ⚔️ %.1f » %.1f  🛡️ %.1f » %.1f. Tap ↩️ to undo.") % [a.x, b.x, a.y, b.y], UI.GOOD)
			render(), false, 22, "blue")
		wand.custom_minimum_size = Vector2(60, 56)
		wand.tooltip_text = tr("Auto-arrange the pack")
		gh.add_child(wand)
	if run.phase == "morning" and not arr_done.is_empty() and _plan_left(arr_done).is_empty():
		# ↩️ only while the pack is still exactly as 🪄 left it (a buy, sale or move ends it)
		var undo := UI.btn("↩️", func():
			if drag_item != null or arr_done.is_empty():
				return
			run.apply_arrange(arr_done.undo)
			arr_done = {}
			_clear_sel()
			render(), false, 22, "gray")
		undo.custom_minimum_size = Vector2(60, 56)
		undo.tooltip_text = tr("Undo auto-arrange")
		gh.add_child(undo)
	else:
		arr_done = {}
	gh.add_child(book)
	gv.add_child(gh)
	grid = BackpackGrid.new().setup(self, cell_px)
	grid.cell_pressed.connect(_on_grid_press)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gv.add_child(grid)
	if not _fused_flash.is_empty():
		var g := grid
		for it in run.grid_items():
			if _fused_flash.has(it.uid):
				var c: Vector2 = (Vector2(it.x, it.y) + Vector2(GameData.mid_cell(it.id, it.rot)) + Vector2(0.5, 0.5)) * cell_px
				var col: Color = GameData.tier_color(it.id)
				var uid: int = it.uid
				g.create_tween().tween_callback(func():
					if is_instance_valid(g):
						pops[uid] = 0.0
						UI.burst(g, c, UI.GOLD, 30, 320, 9)
						UI.burst(g, c, col, 20, 240, 7)).set_delay(0.45)
		_fused_flash.clear()
	held_lbl = UI.wrap_lbl(_held_text(), 16, UI.MU)
	held_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	held_lbl.custom_minimum_size.y = 26
	gv.add_child(held_lbl)
	root.add_child(gp)

	# storage (reused while nothing it shows has changed)
	var sp: Control = _memo("storage", _storage_key(), _storage_section)
	storage_panel = sp
	storage_scroll = sp.get_meta("scroll")
	root.add_child(sp)

	var shop: Control = null
	if run.phase == "morning" and not run.nodes.is_empty() and run.nodes[0].k == "mini":
		_first_tip.call_deferred("mini", "👺 " + tr("Mini-boss floor: one tough fight, no other road. Win it for a Rare-or-better item and +1 pack tile."))
	if run.phase != "morning":
		arr_plan = {}
	if not arr_plan.is_empty() and hint_moves().is_empty():
		arr_plan = {}
		toast("🪄 " + tr("Done: the pack matches the hint."), UI.GOOD)
	if not arr_plan.is_empty():
		shop = _arrange_panel()
		root.add_child(shop)
	elif run.mode == "puzzle":
		shop = _puzzle_panel()
		root.add_child(shop)
	elif run.phase == "morning":
		shop = _memo("shop", _shop_key(), func(): return _shop_panel(fresh)) if not fresh and not _shop_anim else _memo_put("shop", _shop_key(), _shop_panel(fresh))
		sell_zone = shop
		sell_lbl = shop.get_meta("sell_lbl")
		root.add_child(shop)
	if _wide:
		# PC: the pack big on the left; shop (with Depart) and the storage grid on the right
		var cols := UI.hbox(14)
		cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var left := UI.vbox(10)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var right := UI.vbox(10)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(left)
		cols.add_child(right)
		gp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for c in [gp, sp, shop, steps]:
			if c != null:
				root.remove_child(c)
		left.add_child(gp)
		if steps != null:
			right.add_child(steps)   # PC: the trial's steps above the shop
		if shop != null:
			right.add_child(shop)
		right.add_child(sp)
		root.add_child(cols)
	if fresh:
		var k := 0
		for c in root.get_children():
			UI.pop_in(c, 0.05 * k, 18)
			k += 1
	return root


func _chip(t: String, col: Color) -> Control:
	var p := UI.panel(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 99, 6)
	p.add_child(UI.lbl(t, 16, col, true))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


# ---- reusing unchanged parts of the screen
# Every action rebuilds the screen. Rebuilding the HUD, the ribbon and the shop is most of that cost,
# and a tap in the pack changes none of them, so each keeps its node while its fingerprint (the data
# it shows) is the same: the node moves into the new screen instead of being built again.
var _memo_nodes := {}   # name -> {"key": String, "node": Control}


func _memo(name: String, key: String, build: Callable) -> Control:
	var e: Dictionary = _memo_nodes.get(name, {})
	if not e.is_empty() and e.key == key and is_instance_valid(e.node):
		var n: Control = e.node
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		return n
	return _memo_put(name, key, build.call())


func _memo_put(name: String, key: String, node: Control) -> Control:
	_memo_nodes[name] = {"key": key, "node": node}
	return node


func _memo_base() -> String:
	return "%s|%s|%s|%s" % [I18n.lang(), _wide, get_viewport_rect().size, run.day]


## The storage box: what you keep out of the pack.
func _storage_section() -> Control:
	var sp := UI.card(Color("#33261a", 0.96), Color("#6b4f33"), 22, 10)
	storage_panel = sp
	var sv := UI.vbox(6)
	sp.add_child(sv)
	var items := run.storage_items()
	var sh := UI.hbox(8)
	sh.add_child(UI.title("📦 " + tr("Storage"), 22))
	var cnt := _chip(str(items.size()), UI.MU)
	sh.add_child(cnt)
	sh.add_child(UI.spacer())
	if run.phase == "morning" and not run.grid_items().is_empty():
		sh.add_child(UI.btn("📥 " + tr("Empty pack"), func():
			if drag_item != null:
				return
			var n := run.clear_pack()
			_clear_sel()
			run.msg = tr("Moved %d items into storage.") % n
			render(), false, 16, "blue"))
	sv.add_child(sh)
	var scr := ScrollContainer.new()
	if _wide:
		# PC: a grid of cards that scrolls down (the panel fills the rest of the right column)
		scr.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		scr.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scr.custom_minimum_size.y = 112
	storage_scroll = scr
	scr.set_meta("scrolls", true)   # storage is meant to scroll (the fit test allows it)
	sp.set_meta("scroll", scr)
	var keep_x := _storage_x
	scr.ready.connect(func(): scr.set_deferred("scroll_horizontal", keep_x))
	scr.get_h_scroll_bar().value_changed.connect(func(v): _storage_x = int(v))
	var row: Container = UI.hbox(10)
	if _wide:
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 10)
		fl.add_theme_constant_override("v_separation", 10)
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row = fl
	scr.add_child(row)
	sv.add_child(scr)
	# cards keep their normal size; the row scrolls when there are many (shrinking made items hard to find)
	var sw := 112.0
	for it in items:
		row.add_child(_storage_card(it, sw))
	if items.is_empty():
		var el := UI.lbl(tr("Empty. Drag items here to store them."), 17, UI.MU)
		el.custom_minimum_size.y = 100
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(el)
	return sp


func _hud_key() -> String:
	return _memo_base() + "|%d|%d|%d|%d|%d|%d|%d|%s|%s|%s|%d|%s|%s" % [roundi(run.hp), roundi(run.mhp), run.res, run.max_hearts(), run.lv, run.xp, run.gold, run.phase, run.endless, run.pet, run.picks.size(), run.boss_on(run.day) != null or run.boss_on(run.day + 1) != null, run.path + "|a%d" % run.asc]


func _storage_key() -> String:
	var owned := run.items.map(func(i): return i.id)
	owned.sort()
	var st := run.storage_items().map(func(i): return "%d:%s:%d" % [i.uid, i.id, i.rot])
	return _memo_base() + "|%s|%s|%s|%s|%s" % [run.phase, selected.uid if selected != null else -1, ",".join(st), ",".join(owned), run.grid_items().is_empty()]


func _shop_key() -> String:
	var owned := run.items.map(func(i): return i.id)
	owned.sort()
	return _memo_base() + "|%s|%d|%d|%d|%s" % [JSON.stringify(run.shop), run.gold, inspect_idx, run.reroll_cost(), ",".join(owned)]


func _hud() -> Control:
	var p := UI.card(Color("#3a2f25"), Color("#1c1713"), 24, 10)
	var outer := UI.vbox(2)
	p.add_child(outer)
	var h := UI.hbox(10)
	outer.add_child(h)
	if run.mode != "puzzle":   # a puzzle is one fight, not a climb
		outer.add_child(Timeline.new().setup(run))
	var av := UI.panel(Color("#ffcf3f"), Color("#c47a0c"), 4, 99, 4)
	av.custom_minimum_size = Vector2(66, 66)
	var al := UI.lbl(run.cls_def().hero, 38)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(al)
	h.add_child(av)
	if run.pet != "":
		# the pet rides next to the hero
		var pb := UI.lbl(run.pet_def().ic, 32)
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pb)
		UI.breathe(pb, 0.08)
	var hv := UI.vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 28)
	bar.max_value = 1
	var r := run.hp / run.mhp
	var col := Color("#b3121b") if r > 0.25 else Color("#7a0a10")
	bar.add_theme_stylebox_override("fill", UI.box(col, col.darkened(0.45), 2, 99, 0))
	bar.add_theme_stylebox_override("background", UI.box(Color("#1a0807"), Color("#6b5a44"), 3, 99, 0))
	UI.liquid(bar)
	var hpl := UI.lbl("", 17, Color.WHITE, true)
	hpl.add_theme_color_override("font_outline_color", Color.BLACK)
	hpl.add_theme_constant_override("outline_size", 5)
	hpl.set_anchors_preset(Control.PRESET_FULL_RECT)
	hpl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hpl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(hpl)
	var hp_now := roundi(run.hp)
	if _shown_hp >= 0 and _shown_hp != hp_now:
		bar.value = float(_shown_hp) / run.mhp
		bar.create_tween().tween_property(bar, "value", r, 0.5).set_trans(Tween.TRANS_CUBIC)
	else:
		bar.value = r
	hpl.text = "❤️ %d / %d" % [hp_now, roundi(run.mhp)]
	_shown_hp = hp_now
	hv.add_child(bar)
	var hr := UI.hbox(6)
	if run.mode != "puzzle":   # a puzzle has no Hearts, levels or floors
		hr.add_child(UI.lbl("❤️".repeat(run.res) + "🖤".repeat(maxi(0, run.max_hearts() - run.res)), 18))
		hr.add_child(_level_badge())
	hr.add_child(UI.spacer())
	hr.add_child(_effects_button())
	if run.mode != "puzzle":
		var dl := UI.lbl(("♾️ " + tr("Day %d") % run.day) if run.endless else tr("Day %d/%d") % [run.day, RunState.TRIAL_DAYS if run.mode == "trial" else GameData.days], 16, UI.GOLD, true)
		hr.add_child(dl)
	hv.add_child(hr)
	h.add_child(hv)
	if run.phase != "morning":
		h.add_child(_gold_pill())   # in the morning the gold sits on the shop, next to the prices
	return p


## Hero level and EXP toward the next one, next to the Hearts.
func _level_badge() -> Control:
	var p := UI.panel(Color("#2a1d0c"), Color("#c9952f"), 2, 99, 5)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hb := UI.hbox(6)
	hb.add_child(UI.plbl("⭐ " + tr("Lv %d") % run.lv, 15, Color("#f6e3b4"), true))
	if run.asc > 0:
		hb.add_child(UI.plbl("🔥%d" % run.asc, 15, Color("#ffb37a"), true))
	var xb := ProgressBar.new()
	xb.show_percentage = false
	xb.custom_minimum_size = Vector2(70, 10)
	xb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xb.max_value = 1.0
	xb.value = float(run.xp) / float(run.xp_need())
	xb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xb.add_theme_stylebox_override("background", UI.box(Color("#140d05"), Color(0, 0, 0, 0), 0, 99, 0))
	xb.add_theme_stylebox_override("fill", UI.box(Color("#e0a030"), Color(0, 0, 0, 0), 0, 99, 0))
	hb.add_child(xb)
	hb.add_child(UI.plbl("%d/%d" % [run.xp, run.xp_need()], 13, Color("#f0d9a0"), true))
	p.add_child(hb)
	return p


## Level-up choice on the night screen: three bonuses, pick one. "Next day" waits for it.
func _level_pick_card(delay: float) -> Control:
	var lv_at: int = run.lv - (run.picks.size() - 1) * int(GameData.leveling.get("pick_every", 5))
	var card := UI.card(Color("#2a1f05"), UI.STAR, 20, 14)
	var cv := UI.vbox(10)
	card.add_child(cv)
	var t := UI.title("⭐ " + tr("LEVEL %d — choose a bonus") % lv_at, 24, UI.STAR)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(t)
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var offer: Array = run.picks[0]
	for i in offer.size():
		var pd := run.pick_def(offer[i])
		if pd.is_empty():
			continue
		var ii := i
		var b := UI.btn("%s
%s
%s" % [pd.ic, tr(pd.n), tr(pd.d)], func():
			run.pick_level(ii)
			SaveGame.save_run(run)
			render(), false, 16, "gold")
		b.custom_minimum_size = Vector2(190, 130 if _wide else 100)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(b)
	cv.add_child(row)
	UI.pop_in(card, delay, 30)
	return card


func _gold_pill() -> Control:
	var gp := UI.panel(Color("#2a1d0c"), Color("#b07a2a"), 3, 8, 8)   # square pixel coin purse
	gp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gp.custom_minimum_size.x = 112
	# plain bold digits with an outline: the pixel heading font was hard to read at this size
	var gl := UI.lbl("", 26, UI.GOLD, true)
	gl.add_theme_color_override("font_outline_color", Color("#1a0f05"))
	gl.add_theme_constant_override("outline_size", 6)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gp.add_child(gl)
	UI.count_to(gl, _shown_gold if _shown_gold >= 0 else run.gold, run.gold, "💰 %d")
	_shown_gold = run.gold
	return gp


## One tidy row of pills: boss warning, today's hazard, modifier, path. Tap one for details.
## Everything affecting this run: a near boss, the floor's hazard, mode, pet, run modifier, path.
## Each entry: [label, colour, explanation, is_boss_warning?].
func _effect_list() -> Array:
	var pills := []
	for bd in (range(run.day, run.day + 4) if run.mode != "puzzle" else []):
		var b = run.boss_on(bd)
		if b == null:
			continue
		var bi := GameData.foe_icon(b.n) + " "
		pills.append([(bi + tr("Boss in %d days") % (b.d - run.day)) if b.d > run.day + 1 else (bi + tr("Boss tomorrow!")) if b.d == run.day + 1 else (bi + tr("Boss today!")), UI.BAD, tr("Day %d boss: %s (resists %s, weak to %s)") % [b.d, tr(b.n), tr(b.imm) if b.imm != "" else "-", tr(b.weak)], true])
	if not run.hz.is_empty():
		pills.append([run.hz.ic + " " + tr(run.hz.n), Color("#ffb020"), tr(run.hz.d)])
	if run.diff != "normal":
		var dd := run.diff_def()
		pills.append([dd.ic + " " + tr(dd.n), UI.BAD, tr(dd.d)])
	if run.pet != "":
		pills.append([run.pet_def().ic + " " + tr(run.pet_def().n), UI.GOOD, tr(run.pet_def().d)])
	if run.mod.id != "":   # trials and puzzles have no world modifier
		pills.append(["🌐 " + tr(run.mod.n), UI.STAR, tr(run.mod.d)])
	if run.path != "":
		pills.append([run.path_def().ic + " " + tr(run.path_def().n), UI.GOLD, tr(run.path_def().d)])
	return pills


## The top-bar button that replaced the effect ribbon: 📜 (and 💀 when a boss is a floor away or here).
func _effects_button() -> Control:
	var boss_near := false
	for b in [run.boss_on(run.day), run.boss_on(run.day + 1)]:
		if b != null and run.mode != "puzzle":
			boss_near = true
	# a compact chip (a full button's side padding made the top bar too wide)
	var col: Color = UI.BAD if boss_near else UI.BD
	var p := UI.panel(Color(col, 0.3), col, 2, 40, 5)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(UI.plbl(("💀" if boss_near else "") + "📜", 16, Color.WHITE, true))
	UI.on_tap(p, func():
		show_effects = true
		render())
	return p


## Popup with every effect on the run, explained (opened from the 📜 button).
func _effects_overlay() -> Control:
	var o := _overlay("📜 " + tr("This run"), func():
		show_effects = false
		render())
	var v: VBoxContainer = o[1]
	var card := UI.card(Color(UI.PN, 0.96), UI.BD, 18, 14)
	var cv := UI.vbox(10)
	card.add_child(cv)
	for pl in _effect_list():
		var row := UI.hbox(10)
		var nm := UI.lbl(pl[0], 18, pl[1].lightened(0.25), true)
		nm.custom_minimum_size.x = 230
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(nm)
		var d := UI.wrap_lbl(pl[2], 16, Color("#efe4cf"))
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(d)
		cv.add_child(row)
	v.add_child(card)
	return o[0]


## The 🪄 hint's steps still to do: [item, loc, x, y, rot] for every item not yet where the plan puts it.
func hint_moves() -> Array:
	return _plan_left(arr_plan).filter(func(e): return e != null)


## A plan's moves not yet true in the pack; [null] when the items changed since (bought, sold, fused).
func _plan_left(plan: Dictionary) -> Array:
	if plan.is_empty():
		return []
	var mine := run.items.filter(func(i): return i.loc in ["grid", "storage", "held"])
	if mine.size() != plan.moves.size() or plan.moves.any(func(e): return not mine.has(e[0])):
		return [null]
	# same cells counts as done (a symmetric item may sit at another rotation)
	return plan.moves.filter(func(e): return run.items.has(e[0]) and (e[0].loc != e[1] or (e[1] == "grid" and (e[0].x != e[2] or e[0].y != e[3] or GameData.shape(e[0].id, e[0].rot).c != GameData.shape(e[0].id, e[4]).c))))


## 🪄 hint (in the shop's place): the outlines in the pack show where things go; here, the steps, what
## the layout would give and the combos it makes.
func _arrange_panel() -> Control:
	var p := UI.card(Color("#1d2a36", 0.97), Color("#6fa3c8"), 22, 12)
	var v := UI.vbox(10)
	p.add_child(v)
	var head := UI.hbox(8)
	head.add_child(UI.title("🪄 " + tr("Layout hint"), 24, Color("#bfe3ff")))
	head.add_child(UI.spacer())
	v.add_child(head)
	var a: Vector3 = arr_plan.before
	var b: Vector3 = arr_plan.after
	var rates := UI.hbox(6)
	for r in [["⚔️", a.x, b.x, Color("#ff9b5e")], ["🛡️", a.y, b.y, Color("#7dd3fc")], ["💚", a.z, b.z, Color("#4ade80")]]:
		if r[1] <= 0.05 and r[2] <= 0.05:
			continue
		var d: float = r[2] - r[1]
		rates.add_child(_chip("%s %.1f » %.1f (%+.1f)" % [r[0], r[1], r[2], d], r[3] if d >= -0.05 else UI.BAD))
	v.add_child(rates)
	var nm := func(id: String) -> String: return GameData.items[id].ic + " " + tr(GameData.items[id].n)
	var lines := []   # [text, colour]
	for e in hint_moves():
		if e[1] == "storage":
			lines.append(["📤 " + tr("Put %s in storage") % nm.call(e[0].id), UI.MU])
		elif e[0].loc == "storage":
			lines.append(["📥 " + tr("Drag %s from storage to its blue outline") % nm.call(e[0].id), UI.GOOD])
		else:
			lines.append(["➡️ " + tr("Move %s to its blue outline") % nm.call(e[0].id), Color("#bfe3ff")])
	for c in arr_plan.combos:
		if c.k == "link":
			var t: String = "🔗 " + " + ".join(c.ids.map(nm)) + " » " + nm.call(c.r)
			lines.append([t + "  (" + tr("fuses tonight") + ")", UI.GOLD])
	for c in arr_plan.combos:
		if c.k == "buff":
			lines.append(["✨ " + nm.call(c.id) + " » " + ", ".join(c.to.map(nm)) + "  " + GameData._buff_short(c.bf), Color("#d9c49a")])
	if arr_plan.combos.is_empty():
		lines.append([tr("No items buff each other here: the layout just packs the strongest items."), UI.MU])
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 150
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.set_meta("scrolls", true)
	var lv := UI.vbox(4)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for ln in lines:
		lv.add_child(UI.wrap_lbl(ln[0], 16, ln[1]))
	sc.add_child(lv)
	v.add_child(sc)
	var close := UI.btn("✖️ " + tr("Close the hint"), func():
		arr_plan = {}
		render(), false, 20, "gray")
	close.custom_minimum_size.y = 58
	v.add_child(close)
	return p


func _held_text() -> String:
	if drag_item != null:
		var t := ("" + tr("Right-click, scroll or R to rotate")) if _landscape else ("✌️ " + tr("Tap with a second finger to rotate"))
		if hover_cell.x >= 0:
			var a := run.anchor_for(drag_item, hover_cell)
			var pr := run.preview(drag_item, a.x, a.y)
			if pr.ok:
				t = tr("Here: damage %+.1f/s · shield %+.1f/s") % [pr.d.x, pr.d.y]
				if pr.lk:
					t += "  ✨ " + tr("forms a Golden Link!")
			elif run.on_tiles(drag_item.id, drag_item.rot, a):
				t = "🔄 " + tr("Swap: items here move to where this came from, or to storage.")
			else:
				t = "❌ " + tr("Does not fit here.")
		return t
	if run.phase != "morning":
		return ""
	if run.expand > 0:
		return "✨ " + tr("Tap %d glowing tile(s) to grow your pack.") % run.expand
	return tr("Point at an item to see it · right-click to rotate") if _landscape else tr("Tap an item to see it · tap again to rotate")


func _storage_card(it: PItem, w := 112.0) -> Control:
	var d := it.def()
	var c: Color = GameData.tier_colors[d.tier]
	var on := selected == it
	var p := UI.item_card(Color.WHITE if on else c)
	p.custom_minimum_size = Vector2(w, 104)
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var narrow := w < 84.0
	var top: BoxContainer = UI.vbox(2) if narrow else UI.hbox(6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.custom_minimum_size.y = 50
	top.add_child(UI.plbl(d.ic, (24 if w < 56.0 else 28) if narrow else 36))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(ShapeView.new().setup(it.id, it.rot, (6 if w < 56.0 else 8) if narrow else 11))
	top.add_child(cc)
	v.add_child(UI.slot(top, 54))
	var nm := UI.plbl(tr(d.n), 14, UI.TX, true, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size.x = w - 16.0
	nm.visible = w >= 84.0   # many items: icon + shape only, so the row still fits
	v.add_child(nm)
	if run.recipe_partner_owned(it.id, true):
		v.add_child(UI.plbl("🔗" if narrow else "🔗 " + tr("match!"), 13, UI.GOLD, true, true))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_press({"item": it, "src": "storage"}))
	_hoverable(p, {"kind": "storage", "uid": it.uid})
	UI.juice(p)
	return p


# --------------------------------------------------------------- shop

func _shop_panel(fresh: bool) -> Control:
	var shop := UI.card(Color("#45301c", 0.97), Color("#b07a2a"), 22, 10)
	sell_zone = shop
	var v := UI.vbox(10)
	shop.add_child(v)
	var head := UI.hbox(8)
	sell_lbl = UI.title("🛒 " + tr("Shop"), 24, UI.GOLD)
	shop.set_meta("sell_lbl", sell_lbl)
	var sign := PanelContainer.new()   # the merchant's sign
	sign.add_theme_stylebox_override("panel", UI.px_frame(Color("#3a2414"), Color("#c8902c"), 0, 8, true))
	sign.add_child(sell_lbl)
	head.add_child(sign)
	head.add_child(UI.spacer())
	head.add_child(_gold_pill())
	var rr := UI.btn("🎲 %d🪙" % run.reroll_cost(), func():
		if run.reroll():
			_clear_sel()
			_shop_anim = true   # only the new cards animate (not the whole screen)
		render(), false, 18, "purple")
	rr.disabled = run.gold < run.reroll_cost()
	head.add_child(rr)
	v.add_child(head)
	var cards := UI.hbox(8)
	var bag_entries := []
	var k := 0
	for i in run.shop.size():
		var e: Dictionary = run.shop[i]
		if e.has("bag"):
			bag_entries.append(i)
		else:
			var sc := _shop_card(e, i)
			cards.add_child(sc)
			if fresh or _shop_anim:
				UI.pop_in(sc, 0.15 + 0.06 * k, 30)
			k += 1
	_shop_anim = false
	for _k in range(cards.get_child_count(), 5):
		var empty := UI.panel(Color(0, 0, 0, 0.2), UI.BD, 2, 16, 6)
		empty.custom_minimum_size = Vector2(0, 170)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var el := UI.plbl("✅\n" + tr("Sold"), 16, UI.MU, true, true)
		el.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		empty.add_child(el)
		cards.add_child(empty)
	v.add_child(cards)
	var act := UI.hbox(10)
	for i in bag_entries:
		var e: Dictionary = run.shop[i]
		var ii: int = i
		var b := UI.btn("🎒 +%d\n%d🪙" % [e.n, e.price], func():
			if run.buy_bag(ii):
				toast("🎒 " + tr("Tap the glowing tiles to place your new space!"), UI.GOOD)
			render(), false, 18, "blue")
		b.custom_minimum_size = Vector2(112, 68)
		b.disabled = run.gold < e.price
		act.add_child(b)
	var dep := UI.btn(tr("Depart") + " ▶️", func():
		if run.travel():
			_clear_sel()
		render(), false, 26, "green")
	dep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dep.custom_minimum_size.y = 68
	act.add_child(dep)
	v.add_child(act)
	return shop


func _shop_card(e: Dictionary, i: int) -> Control:
	var d: Dictionary = GameData.items[e.id]
	var col: Color = GameData.tier_colors[d.tier]
	var on := inspect_idx == i
	var p := UI.item_card(Color.WHITE if on else col)
	p.custom_minimum_size = Vector2(0, 180)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_press({"src": "shop", "idx": i, "id": e.id}))
	_hoverable(p, {"kind": "shop", "idx": i})
	UI.juice(p)
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var top := UI.hbox(0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.custom_minimum_size.y = 20
	if e.get("sale", false):
		top.add_child(UI.plbl("-50%", 14, Color("#ff7b7f"), true))
	elif run.recipe_partner_owned(e.id):
		top.add_child(UI.plbl("🔗", 16))
	top.add_child(UI.spacer())
	if e.get("lock", false):
		top.add_child(UI.plbl("🔒", 16))
	v.add_child(top)
	# the item's real shape, scaled down, with its icon: you can see how it will sit in the pack
	var bb := Vector2i.ZERO
	for c in GameData.shape(e.id, 0).c:
		bb = Vector2i(maxi(bb.x, c.x + 1), maxi(bb.y, c.y + 1))
	var cpx := minf(36.0, minf(104.0 / bb.x, 80.0 / bb.y))
	var shv := ShapeView.new().setup(e.id, 0, cpx, true)
	shv.icon_px = clampf(cpx * 1.15, 30.0, 44.0)   # big enough to read at a glance
	var shc := CenterContainer.new()
	shc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shc.custom_minimum_size.y = 84
	shc.add_child(shv)
	v.add_child(UI.slot(shc, 88))
	var nm := UI.plbl(tr(d.n), 15, UI.TX, true, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(80, 34)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(nm)
	# just the overview here (picture, name, price): tap (phone) or hover (PC) shows the full card
	v.add_child(UI.spacer(false))
	var can: bool = run.gold >= e.price
	# a gold coin plate (dull iron when you cannot afford it)
	var pb := UI.panel(Color("#2a1c0b") if can else Color("#1d1916"), Color("#d9a441") if can else Color("#4a433b"), 2, 8, 4)   # square pixel coin plate
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_child(UI.plbl("🪙 %d" % e.price, 19, Color("#ffd27a") if can else Color("#7d7266"), true, true))
	v.add_child(pb)
	return p


func _buy_to_storage(i: int) -> void:
	if drag_item != null:
		return
	var it := run.buy_item(i)
	if it != null:
		it.loc = "storage"
		_clear_sel()
		toast("✅ " + tr("Bought %s — it's in storage.") % tr(it.def().n), UI.GOOD)
	render()


# --------------------------------------------------------------- inspector popup

func _inspector_popup() -> Control:
	var id := inspect_id
	var rot := 0
	var owned := selected != null and run.items.has(selected)
	if owned:
		id = selected.id
		rot = selected.rot
	if id == "":
		return Control.new()
	var d: Dictionary = GameData.items[id]
	var col: Color = GameData.tier_colors[d.tier]
	var p := UI.card(Color("#231d17"), col, 26, 18)
	# always at the top: the shop row and storage stay visible while you read
	var at_top := true
	p.anchor_left = 0
	p.anchor_right = 1
	p.anchor_top = 0 if at_top else 1
	p.anchor_bottom = 0 if at_top else 1
	p.offset_left = 10 + _side_pad()
	p.offset_right = -10 - _side_pad()
	p.grow_vertical = Control.GROW_DIRECTION_END if at_top else Control.GROW_DIRECTION_BEGIN
	if at_top:
		p.offset_top = 10
	else:
		p.offset_bottom = -10
	if _wide and run.phase == "morning":
		# PC: in the free space under the shop (right column), anchored to the bottom
		var half := WIDE_W / 2.0
		p.anchor_left = 0.5
		p.anchor_right = 0.5
		p.anchor_top = 1
		p.anchor_bottom = 1
		p.offset_left = 7
		p.offset_right = half - 14
		p.offset_top = 0
		p.offset_bottom = -14
		p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(10)
	p.add_child(v)
	var h := UI.hbox(14)
	v.add_child(h)
	var sh := UI.panel(col.darkened(0.6), col, 2, 16, 8)
	sh.add_child(ShapeView.new().setup(id, rot, 28, true))
	sh.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(sh)
	var tv := UI.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	tv.add_child(UI.title("%s %s" % [d.ic, tr(d.n)], 26))
	var tags := " · ".join(d.tags.map(func(t): return tr(t)))
	var tp := UI.panel(Color(col, 0.25), col, 2, 99, 6)
	tp.add_child(UI.lbl(tr(GameData.tier_names[d.tier]) + " · " + tags, 15, Color.WHITE, true))
	tp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tv.add_child(tp)
	var close := UI.btn("✖️", func():
		_clear_sel()
		render(), false, 20, "red")
	close.custom_minimum_size = Vector2(56, 56)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(close)
	for line in GameData.describe_lines(id):
		v.add_child(UI.wrap_lbl(line, 18, Color("#f4ebd8")))
	if owned:
		v.add_child(_buff_panel(selected, minf(get_viewport_rect().size.x, COLUMN_W) - 2.0 * _side_pad() - 60.0))
	for row in _recipe_rows(id):
		v.add_child(row)
	if owned and run.phase == "morning":
		var tips := UI.hbox(8)
		var rb := UI.btn("🔄 " + tr("Rotate"), func(): _rotate(1), false, 17, "blue")
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tips.add_child(rb)
		tips.add_child(_tip("📦", tr("drag to storage")))
		tips.add_child(_tip("🛒", (tr("sell +%d🪙") % run.sell_price(selected)) if not (selected.starter or selected.def().relic) else tr("starter")))
		v.add_child(tips)
	elif not owned and inspect_idx >= 0 and inspect_idx < run.shop.size():
		var e: Dictionary = run.shop[inspect_idx]
		var ii := inspect_idx
		var ah := UI.hbox(10)
		var lk := UI.btn(("🔓 " + tr("Unlock")) if e.get("lock", false) else ("🔒 " + tr("Keep")), func():
			run.toggle_lock(ii)
			render(), false, 18, "purple")
		ah.add_child(lk)
		var bb := UI.btn(tr("Buy") + " · %d🪙" % e.price, func(): _buy_to_storage(ii), false, 22, "gold")
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bb.disabled = run.gold < e.price
		ah.add_child(bb)
		v.add_child(ah)
		v.add_child(UI.wrap_lbl("💡 " + tr("Or drag it straight into your pack. Double-tap a shop card to lock it."), 15, UI.MU))
	# slide in from its edge
	p.modulate.a = 0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	if at_top:
		p.offset_top = -80
		tw.parallel().tween_property(p, "offset_top", 10.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		p.offset_bottom = 80
		tw.parallel().tween_property(p, "offset_bottom", -10.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return p


# --------------------------------------------------------------- PC hover cards
# On PC (_landscape) pointing at an item shows its card next to the mouse; left click only
# drags, right-click rotates a pack item or keeps a shop card for tomorrow.

var tip_layer: CanvasLayer
var _hover := {}          # {"kind": "grid" | "storage", "uid"} or {"kind": "shop", "idx"}
var _tip_panel: Control


func _hoverable(c: Control, h: Dictionary) -> void:
	if not _landscape:
		return
	c.mouse_entered.connect(func(): _set_hover(h))
	c.mouse_exited.connect(func():
		if _hover == h:
			_set_hover({}))


func _set_hover(h: Dictionary) -> void:
	if h == _hover:
		return
	_hover = h
	_refresh_tip()


## What the hover points at: {id, rot, item (PItem or null), shop (Dictionary or {})}, or {}.
func _hover_target() -> Dictionary:
	if run == null or _hover.is_empty():
		return {}
	if _hover.kind == "shop":
		var i: int = _hover.idx
		if run.phase != "morning" or i < 0 or i >= run.shop.size() or run.shop[i].has("bag"):
			return {}
		return {"id": run.shop[i].id, "rot": 0, "item": null, "shop": run.shop[i]}
	for it in run.items:
		if it.uid == _hover.uid and it.loc != "held":
			return {"id": it.id, "rot": it.rot, "item": it, "shop": {}}
	return {}


func _refresh_tip() -> void:
	if _tip_panel and is_instance_valid(_tip_panel):
		_tip_panel.queue_free()
	_tip_panel = null
	if not _landscape or drag_item != null or tip_layer == null:
		return
	var t := _hover_target()
	if t.is_empty():
		return
	_tip_panel = _item_info_card(t)
	_tip_panel.theme = theme   # CanvasLayer content does not inherit the theme (emoji would be boxes)
	tip_layer.add_child(_tip_panel)
	_tip_panel.reset_size()
	_move_tip()
	# wrapped text settles after one layout pass: shrink to it, then re-place
	var tp := _tip_panel
	get_tree().process_frame.connect(func():
		if is_instance_valid(tp):
			tp.reset_size()
			_move_tip(), CONNECT_ONE_SHOT)
	_tip_panel.modulate.a = 0
	_tip_panel.create_tween().tween_property(_tip_panel, "modulate:a", 1.0, 0.12)


## Keeps the hover card next to the mouse and inside the screen.
func _move_tip() -> void:
	if _tip_panel == null or not is_instance_valid(_tip_panel):
		return
	var m := get_global_mouse_position()
	var vp := get_viewport_rect().size
	var sz := _tip_panel.get_combined_minimum_size()
	var p := m + Vector2(28, 24)
	if p.x + sz.x > vp.x - 10:
		p.x = m.x - sz.x - 28
	p.y = clampf(p.y, 10, maxf(10, vp.y - sz.y - 10))
	_tip_panel.position = p


## The hover card: shape, name, rarity and tags, what it does, its recipes, and the mouse controls.
## "In your pack now": the item's numbers with every buff applied, and what each buff comes from
## (greyed out with the reason when a buff does nothing on this item).
func _buff_panel(it: PItem, width: float) -> Control:
	var p := UI.panel(Color(0, 0, 0, 0.3), Color("#8c7558"), 2, 12, 8)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.custom_minimum_size.x = width - 20.0
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 17)
	p.add_child(rt)
	if it.loc != "grid":
		rt.text = "[color=#a59fd6]📦 " + tr("In storage: buffs only work in the pack.") + "[/color]"
		return p
	var rep := run.buff_report(it)
	var s := "[b][color=#c4b5fd]📊 " + tr("In your pack now") + "[/color][/b]"
	for r in rep.rows:
		var base: float = r[2]
		var now: float = r[3]
		var fmt := func(x: float) -> String: return ("%d%%" % roundi(x * 100)) if r[5] else ((GameData._num(snappedf(x, 0.1)) + "s") if r[4] else GameData._num(snappedf(x, 0.1)))
		var changed := absf(now - base) > 0.001
		var better: bool = (now < base) if r[4] else (now > base)
		var line := "%s %s  %s" % [r[0], tr(r[1]), fmt.call(base)]
		if changed:
			var diff := now - base
			var dtxt: String = ("%+d%%" % roundi(diff * 100)) if r[5] else ("%+.1fs" % diff if r[4] else "%+.1f" % diff)
			line += " » [b][color=%s]%s (%s)[/color][/b]" % ["#4ade80" if better else "#ff6b81", fmt.call(now), dtxt]
		s += "
" + line
	if rep.src.is_empty():
		s += "
[color=#a59fd6]" + tr("No buffs yet. Items with ✨ buff what they touch.") + "[/color]"
	else:
		s += "
[color=#a59fd6]" + tr("From:") + "[/color]"
		for x in rep.src:
			if x[3]:
				s += "
%s %s: [color=#4ade80]%s[/color]" % [x[0], x[1], x[2]]
			else:
				s += "
[color=#7c779e]%s %s: [s]%s[/s] — %s[/color]" % [x[0], x[1], x[2], tr("no effect") + ": " + x[4]]
	rt.text = s
	return p


func _item_info_card(t: Dictionary) -> Control:
	var id: String = t.id
	var d: Dictionary = GameData.items[id]
	var col: Color = GameData.tier_colors[d.tier]
	var p := UI.card(Color("#231d17", 0.97), col, 22, 16)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size.x = 520
	var v := UI.vbox(8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var h := UI.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	var sh := UI.panel(col.darkened(0.6), col, 2, 14, 6)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(ShapeView.new().setup(id, t.rot, 24, true))
	sh.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(sh)
	var tv := UI.vbox(4)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	tv.add_child(UI.plbl("%s %s" % [d.ic, tr(d.n)], 26, Color.WHITE, true))
	var tags := " · ".join(d.tags.map(func(x): return tr(x)))
	tv.add_child(UI.plbl(tr(GameData.tier_names[d.tier]) + " · " + tags, 15, col.lightened(0.3), true))
	for line in GameData.describe_lines(id):
		var l := UI.wrap_lbl(line, 18, Color("#f4ebd8"))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.custom_minimum_size.x = 488
		v.add_child(l)
	var it: PItem = t.item
	if it != null and run.items.has(it):
		v.add_child(_buff_panel(it, 488))
	for rr in _recipe_rows(id):
		rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(rr)
	var hint := ""
	if not t.shop.is_empty():
		hint = tr("Drag into your pack to buy (%d🪙) · Right-click: keep for tomorrow") % t.shop.price
		if t.shop.get("lock", false):
			hint = "🔒 " + tr("Kept for tomorrow.") + "  " + hint
	elif it != null and run.phase == "morning":
		var sell := "" if (it.starter or it.def().relic) else "  ·  " + tr("Drag to the shop to sell (+%d🪙)") % run.sell_price(it)
		if it.loc == "grid":
			hint = tr("Drag to move · Right-click: rotate") + sell
		else:
			hint = tr("Drag into your pack") + sell
	if hint != "":
		var hl := UI.wrap_lbl(hint, 15, UI.MU)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hl.custom_minimum_size.x = 488
		v.add_child(hl)
	return p


## PC right-click (not dragging): rotate the pack item under the mouse, or keep / release a shop card.
func _right_click() -> void:
	if run == null or run.phase != "morning":
		return
	var t := _hover_target()
	if t.is_empty():
		return
	if not t.shop.is_empty():
		var i: int = _hover.idx
		run.toggle_lock(i)
		var locked: bool = run.shop[i].get("lock", false)
		toast(("🔒 " + tr("Locked: it stays in the shop tomorrow.")) if locked else ("🔓 " + tr("Unlocked.")), UI.STAR)
		render()
		return
	var it: PItem = t.item
	if it == null:
		return
	if it.loc == "grid":
		var res := run.rotate_in_pack(it, 1)
		if res == "x":
			run.msg = tr("No room to rotate it here — drag it somewhere with more space.")
		elif res != "":
			run.msg = res
		pops[it.uid] = 0.0
	else:
		it.rot = (it.rot + 1) % 4
	render()


func _tip(icon: String, t: String) -> Control:
	var p := UI.panel(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 14, 8)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(0)
	p.add_child(v)
	v.add_child(UI.plbl(icon, 24, UI.TX, false, true))
	v.add_child(UI.plbl(t, 14, UI.MU, true, true))
	return p


## The item card's recipe rows: the ones you are closest to first, at most 4, then "+N more".
func _recipe_rows(id: String) -> Array:
	var rs := run.recipes_for(id)
	var have := func(r: Dictionary) -> int: return [r.a, r.b, r.get("c", "")].filter(func(q): return q != "" and run.owns(q)).size()
	rs.sort_custom(func(x, y): return have.call(x) > have.call(y))
	var out: Array = rs.slice(0, 4).map(func(r): return _recipe_row(r))
	if rs.size() > 4:
		out.append(UI.lbl("📖 " + tr("+%d more recipes in the book") % (rs.size() - 4), 15, UI.MU))
	return out


func _recipe_row(r: Dictionary) -> Control:
	var h := UI.hbox(6)
	h.add_child(UI.item_chip(r.a, run.owns(r.a)))
	h.add_child(UI.lbl("+", 20, UI.MU, true))
	h.add_child(UI.item_chip(r.b, run.owns(r.b) and (r.a != r.b or run.count_owned(r.a) >= 2)))
	if r.get("c", "") != "":
		h.add_child(UI.lbl("+", 20, UI.MU, true))
		h.add_child(UI.item_chip(r.c, run.owns(r.c)))
	h.add_child(UI.lbl("➡️", 18))
	var known: bool = run.seen.has(r.r) or (run.seen.has(r.a) and run.seen.has(r.b))
	if known:
		h.add_child(UI.item_chip(r.r, run.owns(r.r)))
		var t := tr(GameData.items[r.r].n)
		if r.path != "":
			t += "  " + GameData.paths[r.path].ic
		var l := UI.lbl(t, 17, UI.TX, true)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	else:
		h.add_child(UI.unknown_chip())
		h.add_child(UI.lbl("???" + (("  " + GameData.paths[r.path].ic) if r.path != "" else ""), 17, UI.MU, true))
	return h


# --------------------------------------------------------------- overlays

func _path_choice_overlay() -> Control:
	var o := _overlay(tr("CHOOSE YOUR PATH"), Callable(), _wide)
	var v: VBoxContainer = o[1]
	var list: BoxContainer = v
	if _wide:
		# PC: the three paths side by side
		list = UI.hbox(18)
	var s := UI.wrap_lbl(tr("This choice lasts the whole run. Your path relic goes to storage, and it unlocks that path's Masterwork recipe."), 18, Color("#efe4cf"))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var k := 0
	for pid in run.cls_def().paths:
		var pp: String = pid
		var pd: Dictionary = GameData.paths[pid]
		var p := UI.card(Color("#3a2f25"), UI.GOLD, 24, 18)
		var pv := UI.vbox(10)
		p.add_child(pv)
		var hh := UI.hbox(12)
		hh.add_child(UI.lbl(pd.ic, 56))
		var tv := UI.vbox(2)
		tv.add_child(UI.title(tr(pd.n), 32, UI.GOLD))
		tv.add_child(UI.wrap_lbl(tr(pd.d), 18))
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh.add_child(tv)
		pv.add_child(hh)
		var rd: Dictionary = GameData.items[pd.relic]
		var rh := UI.hbox(10)
		rh.add_child(UI.item_chip(pd.relic))
		var rl := UI.wrap_lbl("%s: %s" % [tr(rd.n), tr(rd.d)], 16, Color("#efe4cf"))
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rh.add_child(rl)
		pv.add_child(rh)
		for r in GameData.recipes:
			if r.path == pid:
				pv.add_child(UI.wrap_lbl("👑 " + tr("Masterwork: %s = %s + %s + %s") % [tr(GameData.items[r.r].n), tr(GameData.items[r.a].n), tr(GameData.items[r.b].n), tr(GameData.items[r.c].n)] if r.c != "" else "👑 " + tr("Masterwork: %s = %s + %s") % [tr(GameData.items[r.r].n), tr(GameData.items[r.a].n), tr(GameData.items[r.b].n)], 16, UI.AC))
		if _wide:
			pv.add_child(UI.spacer(false))   # buttons line up along the bottom
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pv.add_child(UI.big_btn(tr("Choose %s") % tr(pd.n), func():
			run.choose_path(pp)
			render(), "gold", 24))
		list.add_child(p)
		UI.pop_in(p, 0.15 + 0.12 * k, 40)
		k += 1
	if _wide:
		v.add_child(list)
	return o[0]


const NK := {
	"combat": ["⚔️", "FIGHT", "#8c6c4a", "red"], "elite": ["👹", "ELITE", "#b0302a", "red"], "boss": ["💀", "BOSS", "#9b1c3c", "red"],
	"forge": ["🔨", "FORGE", "#b7791f", "gold"], "camp": ["🏕️", "CAMPFIRE", "#3d7a3a", "green"], "ambush": ["⚠️", "AMBUSH", "#b8581f", "red"],
	"mini": ["👺", "MINI-BOSS", "#8a2b5c", "red"],
	"shrine": ["🗿", "DARK SHRINE", "#5b3a7a", "purple"], "tailor": ["🧵", "TAILOR", "#3a6a8a", "blue"],
	"smith": ["🔨", "EVENT", "#b7791f", "gold"], "merchant": ["🛒", "EVENT", "#3a6a8a", "blue"], "roulette": ["🔫", "EVENT", "#b0302a", "red"],
	"cauldron": ["⚗️", "EVENT", "#3d7a3a", "green"], "altar": ["🗿", "EVENT", "#5b3a7a", "purple"], "chest": ["📦", "EVENT", "#a8641a", "gold"],
}

const EV := {
	"smith": ["🔨", "Blacksmith", "Pay to evolve one item right now: no second copy needed."],
	"merchant": ["🛒", "Wandering Merchant", "Rare wares, and he buys your items at full price."],
	"roulette": ["🔫", "Russian Roulette", "One bullet, six chambers. Every empty click grows the pot. Walk away any time."],
	"cauldron": ["⚗️", "Alchemist's Cauldron", "Put in two items, get one better item back."],
	"altar": ["🗿", "Cursed Altar", "Take a Legendary item. The price: one Heart."],
	"chest": ["📦", "Mystery Chests", "Open one. Treasure, gold... or a trap."],
}


func _road_overlay() -> Control:
	var o := _overlay(tr("CHOOSE YOUR ROAD"), Callable(), _wide)
	var v: VBoxContainer = o[1]
	var s := UI.lbl(tr("Day %d · HP %d/%d · Hearts %d/%d") % [run.day, roundi(run.hp), roundi(run.mhp), run.res, run.max_hearts()], 18, UI.MU, true)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var list: BoxContainer = v
	if _wide:
		# PC: tall cards side by side, so every road fits on one screen
		list = UI.hbox(18)
		v.add_child(list)
	for i in run.nodes.size():
		var c := _road_card(run.nodes[i], i)
		if _wide:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.size_flags_stretch_ratio = 1.0
		list.add_child(c)
		UI.pop_in(c, 0.1 + 0.1 * i, 40)
	v.add_child(_center(UI.btn("◀️ " + tr("Back to the shop"), func():
		run.phase = "morning"
		render(), false, 18, "gray")))
	return o[0]


func _road_card(n: Dictionary, i: int) -> Control:
	var k: Array = NK[n.k]
	var c := Color(k[2])
	var boss: bool = n.k == "boss"
	# phone: compact (3 cards must fit one screen with no scrolling); PC: tall cards side by side
	var p := UI.card(c.darkened(0.62), c, 24, 14 if _wide else 10)
	var v := UI.vbox(8 if _wide else 5)
	p.add_child(v)
	var h: BoxContainer = UI.vbox(6) if _wide else UI.hbox(12)   # PC: a tall card, everything centred
	if _wide:
		h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var icon := ""
	var nm := ""
	var badges := []
	var sub := ""
	var sub_col := Color("#efe4cf")
	if n.has("e"):
		var e: Dictionary = n.e
		icon = GameData.foe_icon(e.n)
		nm = tr(e.n)
		badges.append("❤️ %d" % roundi(e.hp))
		badges.append("⚔️ %.1f/%s" % [e.get("dps", 0.0) * run.hz.get("atk", 1.0), tr("s")])
		if e.imm != "": badges.append("🛡️ " + tr("resists %s") % (GameData.elem_icon(e.imm) + tr(e.imm)))
		if e.weak != "": badges.append("💥 " + tr("weak to %s") % (GameData.elem_icon(e.weak) + tr(e.weak)))
		badges.append(("🎁 " + tr("loot")) if n.k != "combat" else ("🎲 " + tr("25% loot")))
		if n.k in ["elite", "ambush", "mini"]:
			badges.append("🎒+1")
	else:
		icon = k[0]
		nm = tr(EV[n.k][1]) if EV.has(n.k) else tr("Campfire")
		sub = tr(EV[n.k][2]) if EV.has(n.k) else tr("Recover 50% HP")
	var il := UI.lbl(icon, (110 if boss else 90) if _wide else (64 if boss else 52))
	if _wide:
		il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(il)
	UI.breathe(il, 0.06)
	var tv := UI.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var tgp := UI.panel(c, c.darkened(0.3), 2, 99, 6)
	tgp.add_child(UI.lbl(k[0] + " " + tr(k[1]), 15, Color.WHITE, true))
	tgp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if _wide else Control.SIZE_SHRINK_BEGIN
	tv.add_child(tgp)
	var ttl := UI.title(nm, 30 if _wide else 22)
	if _wide:
		ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(ttl)
	if sub != "":
		# wraps on every screen: a long event line (Russian Roulette) must not push the card wider
		var sl := UI.wrap_lbl(sub, 19 if _wide else 16, sub_col)
		sl.custom_minimum_size.x = 200
		if _wide:
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(sl)
	if n.has("e"):
		# short chips: style, pet, Ultimate, skills, boss move — the full story is behind Details
		var chips: Array = FoeInfo.chips(n.e)
		if not chips.is_empty():
			var cf := UI.flow(6)
			if _wide:
				cf.alignment = FlowContainer.ALIGNMENT_CENTER
			for ch in chips:
				var warn: bool = String(ch).begins_with("⚠️")
				var cp := UI.panel(Color("#3a1408", 0.9) if warn else Color("#2b1f14", 0.85), Color("#ff9f43") if warn else Color("#c084fc"), 2, 99, 6)
				cp.add_child(UI.lbl(ch, 15 if _wide else 13, Color("#ffd8a8") if warn else Color("#f5ecd9"), true))
				cf.add_child(cp)
			v.add_child(cf)
	if not badges.is_empty():
		var bf := UI.flow(6)
		if _wide:
			bf.alignment = FlowContainer.ALIGNMENT_CENTER
		for b in badges:
			var bp := UI.panel(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 99, 6)
			bp.add_child(UI.lbl(b, 14 if _wide else 12, Color("#efe4cf"), true))
			bf.add_child(bp)
		v.add_child(bf)
	if n.has("e") and n.e.has("items"):
		if _wide:
			var mp := MiniPack.new().setup(n.e, 28.0)
			mp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			var mh := UI.hbox(8)
			mh.alignment = BoxContainer.ALIGNMENT_CENTER
			mh.add_child(UI.lbl("🎒", 22))
			mh.add_child(mp)
			v.add_child(mh)
		else:
			# phone: the monster's pack sits small at the right of the header
			var mp2 := MiniPack.new().setup(n.e, minf(18.0, 100.0 / maxf(1.0, n.e.get("gh", 3))))
			mp2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(mp2)
	if _wide:
		v.add_child(UI.spacer(false))   # buttons line up along the bottom
	var go := UI.btn(("⚔️ " + tr("FIGHT!")) if n.has("e") else (tr("GO") + " ▶️"), func(): _choose(i), false, 26, k[3])
	go.custom_minimum_size.y = 66 if _wide else 54
	if not _wide:
		go.add_theme_font_size_override("font_size", 22)
	if n.has("e"):
		var br := UI.hbox(8)
		var info_b := UI.btn("🔍 " + tr("Details"), func():
			foe_info_e = run.with_hazard(n.e)
			render(), false, 18 if _wide else 16, "purple")
		info_b.custom_minimum_size = Vector2(150 if _wide else 128, go.custom_minimum_size.y)
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		br.add_child(info_b)
		br.add_child(go)
		v.add_child(br)
	else:
		v.add_child(go)
	if n.k in ["elite", "boss", "ambush", "mini"]:
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "self_modulate", Color(1.2, 1.1, 1.1), 0.8)
		tw.tween_property(p, "self_modulate", Color.WHITE, 0.8)
	return p


func _choose(i: int) -> void:
	foe_info_e = {}
	_pending_sim = run.choose(i)
	render()


func _on_combat_done(won: bool) -> void:
	var cs := _pending_sim
	_pending_sim = null
	run.go_night(cs.node, won, cs)
	_clear_sel()
	render()


func _night_overlay() -> Control:
	var r := run.result
	var fight: bool = r.n.has("e")
	var head := "🌙 " + tr("NIGHT")
	if fight:
		# won: Victory · went down but a Heart pulled you through: Survived · no Hearts left: Defeat
		head = ("🏆 " + tr("VICTORY!")) if r.win else (("💔 " + tr("DEFEAT")) if r.over else ("🩹 " + tr("SURVIVED") + "  -1 ❤️"))
	var o := _overlay(head, Callable(), _wide)
	var v: VBoxContainer = o[1]
	var side: VBoxContainer = v   # where the fight summary goes
	if _wide:
		# PC: rewards, fusions, level-up and "Next day" on the left; the fight summary on the right
		var cols := UI.hbox(28)
		cols.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(cols)
		v = UI.vbox(16)
		v.custom_minimum_size.x = 660
		cols.add_child(v)
		side = UI.vbox(16)
		side.custom_minimum_size.x = 660
		cols.add_child(side)
	var rew: Array = r.get("rew", [])
	var k := 0
	# rewards as big tiles
	var tiles := []
	for w in rew:
		if w.k == "level":
			# several level-ups in one night show as one tile (the newest level)
			tiles = tiles.filter(func(x): return x.k != "level")
		if w.k != "fusion":
			tiles.append(w)
	if not tiles.is_empty():
		v.add_child(_reward_row(tiles, 0.2))
		k += tiles.size()
	# other happenings that have no tile (used potions, defeat note...)
	var covered := ["🏆", "🎁", "🎒", "❤️", "✨", "🧵", "🗿", "⭐"]
	if rew.any(func(w): return w.k == "forge"):
		covered.append("🔨")
	if rew.any(func(w): return w.k == "heal"):
		covered.append("🔥")
	for l in r.lines:
		if covered.any(func(p): return l.begins_with(p)):
			continue
		var fp := UI.card(Color(UI.PN, 0.95), UI.BD, 18, 12)
		fp.add_child(UI.wrap_lbl(l, 18))
		v.add_child(fp)
		UI.pop_in(fp, 0.2 + 0.12 * k, 30)
		k += 1
	# evolutions and fusions are shown when the next day opens (one at a time), so this screen stays short
	var n_fx := rew.filter(func(w): return w.k == "fusion").size()
	if n_fx > 0:
		var fl := UI.lbl("✨ " + tr("%d fusion(s) tonight — see them in the morning!") % n_fx, 17, UI.GOLD, true)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(fl)
	var cs: CombatSim = r.cs
	if cs != null:
		var tp := UI.card(Color(UI.INK, 0.85), UI.BD, 18, 14)
		var tv := UI.vbox(6)
		tp.add_child(tv)
		tv.add_child(_summary_rows(cs, 9 if _wide else 6))
		var extra := []
		for kk in cs.stat_dmg:
			if cs.stat_dmg[kk] > 0:
				extra.append("%s %d" % [GameData.statuses[kk].ic, roundi(cs.stat_dmg[kk])])
		extra.append("🛡️ " + tr("Blocked %d") % roundi(cs.blocked))
		extra.append("⭐ " + tr("Ultimates %d") % cs.ults)
		extra.append("⏱️ %.1fs" % (cs.tk / 10.0))
		tv.add_child(UI.wrap_lbl(" · ".join(extra), 16, UI.MU))
		side.add_child(tp)
		UI.pop_in(tp, 0.2 + 0.15 * k, 30)
	var choosing: bool = not r.over and not run.picks.is_empty()
	if choosing:
		v.add_child(_level_pick_card(0.25 + 0.15 * k))
		k += 1
	var label := tr("See result") if r.over else tr("Claim victory") if r.victory else tr("Next day") + " ▶️"
	var fused: Array = r.get("fused", [])
	var nb := UI.big_btn(label, func():
		_fused_flash = fused.duplicate()
		_fusion_queue = rew.filter(func(w): return w.k == "fusion")
		_fusion_seen = 0
		_all_stats_cs = null
		run.next_day()
		_clear_sel()
		render(), "green", 28)
	nb.disabled = choosing
	if r.victory and run.mode == "":
		# beat the day-15 boss: claim the win, or keep going in Endless (+2 Hearts, max 5)
		var eb := UI.big_btn("♾️ " + tr("Keep going (Endless)") + "  +2 ❤️", func():
			_fused_flash = fused.duplicate()
			_fusion_queue = rew.filter(func(w): return w.k == "fusion")
			_fusion_seen = 0
			_all_stats_cs = null
			run.go_endless()
			run.next_day()
			_clear_sel()
			render(), "purple", 24)
		eb.disabled = choosing
		var hb := UI.hbox(12)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.custom_minimum_size.x = 0
		eb.custom_minimum_size.x = 0
		hb.add_child(nb)
		hb.add_child(eb)
		v.add_child(hb)
		UI.pop_in(hb, 0.3 + 0.15 * k, 30)
	else:
		v.add_child(nb)
		UI.pop_in(nb, 0.3 + 0.15 * k, 30)
	return o[0]


const SUM_COLS := {
	"Fire": Color("#ff7a3d"), "Nature": Color("#7ee06e"), "Physical": Color("#e5e7eb"), "Shock": Color("#facc15"),
	"burn": Color("#e11d48"), "poison": Color("#a77bd0"), "bleed": Color("#f87171"), "shield": Color("#60a5fa"), "heal": Color("#4ade80"),
}


## Fight summary: per item a stacked bar (hit damage by element, Burn, Poison, Shield, Heal)
## and the numbers for each part, so you can see what every item actually did.
func _summary_rows(cs: CombatSim, max_rows := 99) -> Control:
	var v := UI.vbox(6)
	v.add_child(UI.title("📊 " + tr("What each item did"), 20))
	# legend
	var lg := UI.flow(10)
	for pair in [["⚔️", tr("Hit"), Color("#e5e7eb")], ["🔥", tr("Burn"), SUM_COLS.burn], ["☠️", tr("Poison"), SUM_COLS.poison], ["🩸", tr("Bleed"), SUM_COLS.bleed], ["🛡️", tr("Shield"), SUM_COLS.shield], ["💚", tr("Heal"), SUM_COLS.heal]]:
		var p := UI.panel(Color(pair[2], 0.2), pair[2], 2, 99, 6)
		p.add_child(UI.lbl(pair[0] + " " + pair[1], 13, Color.WHITE, true))
		lg.add_child(p)
	v.add_child(lg)
	var parts_of := func(x: Dictionary) -> Array:
		var out := []
		if x.st.dmg > 0:
			out.append(["hit", x.st.dmg, SUM_COLS.get(x.st.get("el", ""), SUM_COLS.Physical), "⚔️"])
		for k in x.st.get("dot", {}):
			if x.st.dot[k] > 0:
				out.append([k, x.st.dot[k], SUM_COLS.get(k, Color.WHITE), GameData.statuses[k].ic])
		if x.st.shield > 0:
			out.append(["shield", x.st.shield, SUM_COLS.shield, "🛡️"])
		if x.st.heal > 0:
			out.append(["heal", x.st.heal, SUM_COLS.heal, "💚"])
		return out
	var rows := []
	var top := 1.0
	for x in cs.items:
		var parts: Array = parts_of.call(x)
		var tot := 0.0
		for p in parts:
			tot += p[1]
		rows.append([x, parts, tot])
		top = maxf(top, tot)
	rows.sort_custom(func(a, b): return a[2] > b[2])
	# one thin line per item (name · bar · numbers), strongest first; as many as fit, the rest behind See all
	var shown := rows.slice(0, mini(rows.size(), max_rows if rows.size() > max_rows else rows.size()))
	if rows.size() > max_rows:
		shown = rows.slice(0, max_rows - 1)
	for row in shown:
		var x: Dictionary = row[0]
		var parts: Array = row[1]
		var tot: float = row[2]
		var line := UI.hbox(8)
		var nl := UI.lbl(x.d.ic + " " + tr(x.d.n), 15, UI.TX, true)
		nl.clip_text = true
		nl.custom_minimum_size.x = 170 if not _wide else 210
		line.add_child(nl)
		# stacked bar, grows in
		var track := UI.panel(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 99, 0)
		track.custom_minimum_size.y = 12
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bar := UI.hbox(0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track.add_child(bar)
		for p in parts:
			var seg := ColorRect.new()
			seg.color = p[2]
			seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			seg.size_flags_stretch_ratio = maxf(0.001, p[1])
			bar.add_child(seg)
		var empty := Control.new()
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.size_flags_stretch_ratio = maxf(0.001, top - tot)
		bar.add_child(empty)
		bar.scale.x = 0.0
		bar.create_tween().tween_property(bar, "scale:x", 1.0, 0.6).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		line.add_child(track)
		var nums := UI.hbox(6)
		nums.custom_minimum_size.x = 120 if not _wide else 150
		nums.alignment = BoxContainer.ALIGNMENT_END
		for p in parts:
			var chip := UI.lbl("%s%d" % [p[3], roundi(p[1])], 14, p[2], true)
			chip.add_theme_color_override("font_outline_color", Color.BLACK)
			chip.add_theme_constant_override("outline_size", 4)
			nums.add_child(chip)
		if parts.is_empty():
			nums.add_child(UI.lbl("-", 14, UI.MU))
		line.add_child(nums)
		v.add_child(line)
	if rows.size() > shown.size():
		var more := rows.size() - shown.size()
		v.add_child(_center(UI.btn("+%d · " % more + tr("See all"), func():
			_all_stats_cs = cs
			render(), false, 15, "blue")))
	return v


## A reward tile: big icon, a number that counts up, a caption. Pops in after `delay`.
## Reward tiles in a centered row that always fits the column: tiles narrow when there are many
## (gold, heart, tiles, EXP, level...), and wrap to a second line if they still don't fit.
func _reward_row(list: Array, delay0: float) -> Control:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	var n := list.size()
	var w := clampf(floorf((650.0 - 10.0 * (n - 1)) / maxf(1.0, n)), 70.0, 148.0)
	for i in n:
		row.add_child(_reward_tile(list[i], delay0 + 0.15 * i, w))
	return row


func _reward_tile(w: Dictionary, delay: float, tw := 148.0) -> Control:
	var col := UI.GOLD
	var icon := ""
	var cap := ""
	var num := 0
	var fmt := "+%d"
	var sub := ""
	match w.k:
		"gold":
			icon = "🪙"
			num = w.v
			cap = tr("Gold")
		"tiles":
			icon = "🎒"
			num = w.v
			cap = tr("Pack tiles")
			col = Color("#4f8cff")
		"heart":
			icon = "❤️" if w.v > 0 else "💔"
			num = w.v
			fmt = "+%d" if w.v > 0 else "%d"
			cap = tr("Heart")
			col = UI.BAD
		"maxhp":
			icon = "🖤"
			num = w.v
			fmt = "%d"
			cap = tr("Max HP")
			col = UI.STAR
		"heal":
			icon = "💚"
			num = w.v
			cap = tr("HP")
			col = UI.GOOD
		"hp":
			icon = "💔"
			num = w.v
			fmt = "%d"
			cap = tr("HP")
			col = UI.BAD
		"xp":
			icon = "🔷"
			num = w.v
			cap = tr("EXP")
			col = Color("#38bdf8")
		"level":
			icon = "⭐"
			num = w.v
			fmt = "Lv %d"
			cap = tr("Level up!")
			col = UI.STAR
			# what every level gives, so the tile explains itself
			sub = "+%d ❤️  +%d%% ⚔️" % [int(GameData.leveling.get("hp", 0)), roundi(float(GameData.leveling.get("dmg", 0.0)) * 100)]
		"loot", "forge":
			var d: Dictionary = GameData.items[w.id]
			icon = d.ic
			col = GameData.tier_colors[d.tier]
			cap = tr(d.n)
			fmt = ""
	var p := UI.card(col.darkened(0.55), col, 20, 10)
	var small := not _wide and tw < 110.0   # phone with many rewards: a smaller tile so they stay in one row
	p.custom_minimum_size = Vector2(tw, 168 if _wide else (116 if small else 148))
	var vb := UI.vbox(2)
	p.add_child(vb)
	var il := UI.lbl(icon, 38 if small else 56)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(il)
	if w.k in ["loot", "forge"]:
		var tag := UI.panel(col, col.darkened(0.3), 2, 99, 4)
		tag.add_child(UI.plbl(tr("NEW!") if w.k == "loot" else "+3 ⚔️", 14, Color.WHITE, true, true))
		vb.add_child(tag)
	else:
		var nl := UI.title("", 22 if small else 30, col.lightened(0.3))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(nl)
		nl.text = fmt % 0
		var ff := fmt
		var target := num
		nl.create_tween().tween_callback(func(): UI.count_to(nl, 0, target, ff)).set_delay(delay + 0.2)
	var cl := UI.plbl(cap, 14, Color("#efe4cf"), true, true)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.custom_minimum_size.x = tw - 20.0
	vb.add_child(cl)
	if sub != "":
		vb.add_child(UI.plbl(sub, 13, col.lightened(0.45), true, true))
	UI.pop_in(p, delay, 30)
	var pp := p
	pp.create_tween().tween_callback(func(): UI.burst(pp, pp.size / 2, col, 20, 300, 7)).set_delay(delay + 0.15)
	return p


## Two items slide together, flash, and the new item pops out.
func _fusion_card(w: Dictionary, delay: float) -> Control:
	var rd: Dictionary = GameData.items[w.r]
	var col: Color = GameData.tier_colors[rd.tier]
	var p := UI.card(Color("#3d2f10"), UI.GOLD, 22, 12)
	var vb := UI.vbox(4)
	p.add_child(vb)
	var three: bool = str(w.get("c", "")) != ""   # a Masterwork: three pieces fly together
	var t := UI.title(("👑 " + tr("MASTERWORK!")) if three else (("✨ " + tr("EVOLUTION!")) if w.evo else ("🔗 " + tr("FUSION!"))), 26, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 120)
	stage.clip_contents = false
	vb.add_child(stage)
	var mk := func(ic: String) -> Label:
		var l := UI.lbl(ic, 64)
		l.size = Vector2(96, 96)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.pivot_offset = Vector2(48, 48)
		stage.add_child(l)
		return l
	var la: Label = mk.call(GameData.items[w.a].ic)
	var lb: Label = mk.call(GameData.items[w.b].ic)
	var lc: Label = mk.call(GameData.items[w.c].ic if three else "")
	lc.visible = three
	var lr: Label = mk.call(rd.ic)
	lr.scale = Vector2.ZERO
	var parts_txt := "%s + %s" % [tr(GameData.items[w.a].n), tr(GameData.items[w.b].n)] + ((" + " + tr(GameData.items[w.c].n)) if three else "")
	var cap := UI.wrap_lbl("%s ➡️ %s" % [parts_txt, tr(rd.n)] + (("  (" + tr("in storage") + ")") if w.get("stored", false) else ""), 18, Color("#fff3c4"))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.modulate.a = 0
	vb.add_child(cap)
	# park both parts apart once the card has its width
	stage.resized.connect(func():
		var cx := stage.size.x / 2 - 48
		if lr.scale == Vector2.ZERO and la.visible:
			la.position = Vector2(cx - 170, 12)
			lb.position = Vector2(cx + 170, 12)
			lc.position = Vector2(cx, -40)
		lr.position = Vector2(cx, 12))
	var tw := p.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		var cx := stage.size.x / 2 - 48
		var t2 := p.create_tween()
		t2.tween_property(la, "position:x", cx - 34, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t2.parallel().tween_property(lb, "position:x", cx + 34, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t2.parallel().tween_property(la, "rotation", -0.4, 0.45)
		t2.parallel().tween_property(lb, "rotation", 0.4, 0.45)
		if three:
			t2.parallel().tween_property(lc, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t2.tween_callback(func():
			la.visible = false
			lb.visible = false
			lc.visible = false
			UI.burst(stage, Vector2(stage.size.x / 2, 60), UI.GOLD, 40, 420, 10)
			UI.burst(stage, Vector2(stage.size.x / 2, 60), col, 24, 300, 8))
		t2.tween_property(lr, "scale", Vector2(1.5, 1.5), 0.2).set_trans(Tween.TRANS_BACK)
		t2.tween_property(lr, "scale", Vector2.ONE, 0.2)
		t2.parallel().tween_property(cap, "modulate:a", 1.0, 0.3))
	return p


# --------------------------------------------------------------- events

var _cauldron_pick: Array = []   # uids picked for the cauldron


func _event_overlay() -> Control:
	var ev: Dictionary = run.event
	var info: Array = EV.get(ev.k, ["❔", "Event", ""])
	# PC: the Merchant gets the full width so its buy + sell cards fit without scrolling
	var o := _overlay("", Callable(), _wide and ev.k == "merchant")
	var v: VBoxContainer = o[1]
	var big := UI.lbl(info[0], 72 if _wide else 96)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	UI.breathe(big, 0.05)
	var t := UI.title(tr(info[1]), 38, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var d := UI.wrap_lbl(tr(info[2]), 18, Color("#efe4cf"))
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)
	var gl := UI.lbl("🪙 %d    ❤️ %d/%d    %s" % [run.gold, roundi(run.hp), roundi(run.mhp), "❤️".repeat(run.res)], 18, UI.MU, true)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(gl)
	if ev.get("done", false):
		_event_result(v)
	else:
		match ev.k:
			"smith": _ev_smith(v)
			"merchant": _ev_merchant(v)
			"roulette": _ev_roulette(v)
			"cauldron": _ev_cauldron(v)
			"altar": _ev_altar(v)
			"chest": _ev_chest(v)
	var done: bool = ev.get("done", false)
	var leave := UI.big_btn((tr("Continue") if done else tr("Leave")) + " ▶️", func():
		_cauldron_pick.clear()
		run.ev_leave()
		render(), "green" if done else "gray", 24)
	v.add_child(leave)
	return o[0]


## What the event gave you: reward tiles and an evolution/fusion card.
func _event_result(v: VBoxContainer) -> void:
	var ev: Dictionary = run.event
	var tiles := []
	for w in ev.rew:
		if w.k == "fusion":
			v.add_child(_fusion_card(w, 0.2))
		elif w.k in ["gold", "loot", "hp", "heart", "maxhp"]:
			tiles.append(w)
	if not tiles.is_empty():
		v.add_child(_reward_row(tiles, 0.0))
	for l in ev.lines:
		if l.begins_with("💥") or l.begins_with("📦") or l.begins_with("🗿"):
			var p := UI.card(Color(UI.PN, 0.95), UI.BD, 18, 12)
			p.add_child(UI.wrap_lbl(l, 18))
			v.add_child(p)


func _item_pick_card(it: PItem, sub: String, on: bool, cb: Callable) -> Control:
	var d: Dictionary = it.def()
	var col: Color = GameData.tier_colors[d.tier]
	var p := UI.card(col.darkened(0.5), Color.WHITE if on else col, 16, 8)
	p.custom_minimum_size = Vector2(150, 0)
	var vb := UI.vbox(2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	vb.add_child(UI.plbl(d.ic, 40, UI.TX, false, true))
	var nl := UI.plbl(tr(d.n), 15, UI.TX, true, true)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size.x = 130
	vb.add_child(nl)
	if sub != "":
		vb.add_child(UI.plbl(sub, 14, UI.GOLD, true, true))
	UI.on_tap(p, cb)
	UI.juice(p)
	return p


func _ev_smith(v: VBoxContainer) -> void:
	var cost := run.smith_cost()
	var hl := UI.title(tr("Reforge price: %d🪙") % cost, 24, UI.GOLD)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hl)
	var fl := UI.flow(10)
	fl.alignment = FlowContainer.ALIGNMENT_CENTER
	var any := false
	for it in run.items:
		if it.loc == "held" or it.def().evo == "":
			continue
		any = true
		var nx: Dictionary = GameData.items[it.def().evo]
		var itr: PItem = it
		fl.add_child(_item_pick_card(it, "➡️ " + nx.ic + " " + tr(nx.n), false, func():
			if run.ev_smith(itr):
				render()
			else:
				toast(tr("Not enough gold."), UI.BAD)))
	if not any:
		v.add_child(UI.wrap_lbl(tr("You have nothing he can reforge."), 18, UI.MU))
	v.add_child(fl)


func _ev_merchant(v: VBoxContainer) -> void:
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in run.event.stock.size():
		var s: Dictionary = run.event.stock[i]
		var d: Dictionary = GameData.items[s.id]
		var col: Color = GameData.tier_colors[d.tier]
		var p := UI.card(col.darkened(0.5), col, 18, 10)
		p.custom_minimum_size = Vector2(200, 0)
		var vb := UI.vbox(4)
		p.add_child(vb)
		vb.add_child(UI.plbl(d.ic, 48, UI.TX, false, true))
		var nl := UI.plbl(tr(d.n), 16, UI.TX, true, true)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size.x = 180
		vb.add_child(nl)
		var ssl := UI.rich(GameData.stats_bb(s.id), 14)
		ssl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(ssl)
		var ii: int = i
		var b := UI.btn((tr("Sold") if s.get("sold", false) else "🪙 %d" % s.price), func():
			if run.ev_buy(ii):
				toast("✅ " + tr("Bought %s — it's in storage.") % tr(d.n), UI.GOOD)
			render(), false, 20, "gold")
		b.disabled = s.get("sold", false) or run.gold < s.price
		vb.add_child(b)
		row.add_child(p)
	v.add_child(row)
	var st := UI.title("💰 " + tr("Sell at full price"), 22, UI.GOLD)
	if _wide:
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var fl := UI.flow(10)
	if _wide:
		fl.alignment = FlowContainer.ALIGNMENT_CENTER
	for it in run.items:
		if it.starter or it.loc == "held" or it.def().relic:
			continue
		var itr: PItem = it
		fl.add_child(_item_pick_card(it, "+%d🪙" % run.merchant_price(it), false, func():
			run.ev_sell_full(itr)
			render()))
	v.add_child(fl)


func _ev_roulette(v: VBoxContainer) -> void:
	var ev: Dictionary = run.event
	var cyl := UI.hbox(10)
	cyl.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 6:
		var used: bool = i < ev.pulls
		var c := UI.lbl("⭕" if used else "⚪", 44)
		c.modulate = Color(1, 1, 1, 0.35) if used else Color.WHITE
		cyl.add_child(c)
	v.add_child(cyl)
	var left: int = 6 - ev.pulls
	var odds := UI.title(tr("Chance of the bullet: 1 in %d") % left, 22, UI.BAD if left <= 3 else Color.WHITE)
	odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(odds)
	var pot := UI.title(tr("Pot: %d🪙") % ev.pot, 40, UI.GOLD)
	pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pot)
	var nxt := run.roulette_pot(ev.pulls + 1)
	var hint := UI.wrap_lbl(tr("Next empty click: pot becomes %d🪙. Bullet: lose 35%% Max HP and the pot. 3+ clicks also win an item.") % nxt, 16, UI.MU)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	var row := UI.hbox(10)
	var pull := UI.btn("🔫 " + tr("PULL"), func():
		var r := run.ev_pull()
		if r == "click":
			toast("*click* 😅", UI.GOOD)
		elif r == "bang":
			toast("💥 " + tr("BANG!"), UI.BAD)
		render(), false, 26, "red")
	pull.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pull.custom_minimum_size.y = 84
	row.add_child(pull)
	var cash := UI.btn("💰 " + tr("Take %d🪙") % ev.pot, func():
		run.ev_cash_out()
		render(), false, 22, "green")
	cash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash.custom_minimum_size.y = 84
	cash.disabled = ev.pulls == 0
	row.add_child(cash)
	v.add_child(row)


func _ev_cauldron(v: VBoxContainer) -> void:
	var hl := UI.title(tr("Pick two items (%d/2)") % _cauldron_pick.size(), 24, UI.GOLD)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hl)
	var fl := UI.flow(10)
	fl.alignment = FlowContainer.ALIGNMENT_CENTER
	for it in run.items:
		if it.starter or it.loc == "held" or it.def().relic:
			continue
		var uid: int = it.uid
		fl.add_child(_item_pick_card(it, "✅" if _cauldron_pick.has(uid) else "", _cauldron_pick.has(uid), func():
			if _cauldron_pick.has(uid):
				_cauldron_pick.erase(uid)
			elif _cauldron_pick.size() < 2:
				_cauldron_pick.append(uid)
			render()))
	v.add_child(fl)
	var brew := UI.btn("⚗️ " + tr("Brew"), func():
		var a: PItem = null
		var b: PItem = null
		for it in run.items:
			if it.uid == _cauldron_pick[0]:
				a = it
			elif it.uid == _cauldron_pick[1]:
				b = it
		if a != null and b != null:
			run.ev_brew(a, b)
		_cauldron_pick.clear()
		render(), false, 26, "green")
	brew.custom_minimum_size.y = 80
	brew.disabled = _cauldron_pick.size() < 2
	v.add_child(brew)


func _ev_altar(v: VBoxContainer) -> void:
	for i in run.event.offer.size():
		var id: String = run.event.offer[i]
		var d: Dictionary = GameData.items[id]
		var col: Color = GameData.tier_colors[d.tier]
		var p := UI.card(col.darkened(0.55), col, 20, 12)
		var h := UI.hbox(12)
		p.add_child(h)
		h.add_child(UI.lbl(d.ic, 56))
		var tv := UI.vbox(4)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		tv.add_child(UI.title(tr(d.n), 22))
		tv.add_child(UI.wrap_lbl(GameData.describe_lines(id)[0], 15, Color("#efe4cf")))
		var br := UI.hbox(8)
		var ii: int = i
		var hb := UI.btn("-1 ❤️", func():
			run.ev_altar(ii, "heart")
			render(), false, 16, "purple")
		hb.disabled = run.res <= 0
		br.add_child(hb)
		tv.add_child(br)
		v.add_child(p)


func _ev_chest(v: VBoxContainer) -> void:
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		var ii: int = i
		var b := UI.btn("📦", func():
			var c := run.ev_chest(ii)
			if c.get("k", "") == "curse":
				toast("💥 " + tr("A trap!"), UI.BAD)
			render(), false, 64, "gold")
		b.custom_minimum_size = Vector2(170, 170)
		row.add_child(b)
	v.add_child(row)


const BOOK_PER_PAGE := 4


## Every entry the book can show, in page order: evolution chains, then recipes, then Masterworks.
func _book_entries() -> Array:
	var out := []
	for id in GameData.items:
		var d: Dictionary = GameData.items[id]
		if d.lv == 1 and d.evo != "" and run.in_class_pool(id):
			var chain := [id]
			var cur: String = id
			while GameData.items[cur].evo != "":
				cur = GameData.items[cur].evo
				chain.append(cur)
			out.append({"sec": "evo", "chain": chain})
	for r in GameData.recipes:
		if not r.evo and r.path == "" and run.in_class_pool(r.r):
			out.append({"sec": "recipe", "r": r})
	for r in GameData.recipes:
		if r.path != "" and run.in_class_pool(r.r):
			out.append({"sec": "cap", "r": r})
	return out


func _book_overlay() -> Control:
	var o := _overlay("📖 " + tr("RECIPE BOOK"), func():
		show_book = false
		book_item = ""
		render())
	var v: VBoxContainer = o[1]
	var entries := _book_entries()
	var pages := maxi(1, ceili(entries.size() / float(BOOK_PER_PAGE)))
	book_page = clampi(book_page, 0, pages - 1)
	var slice := entries.slice(book_page * BOOK_PER_PAGE, (book_page + 1) * BOOK_PER_PAGE)
	var sec: String = slice[0].sec if not slice.is_empty() else "evo"
	var titles := {"evo": "✨ " + tr("Evolutions"), "recipe": "🔗 " + tr("Recipes"), "cap": "👑 " + tr("Masterworks")}
	var hints := {
		"evo": tr("Two copies of the same item, touching, evolve at night."),
		"recipe": tr("Two different items, touching, fuse at night."),
		"cap": tr("Path-only. Build the parts, choose the right path, and place them together."),
	}
	var page := UI.card(Color("#f3e6c4"), Color("#8a5a2b"), 22, 16)
	var pv := UI.vbox(12)
	page.add_child(pv)
	var st := UI.title(titles[sec], 26, Color("#5a3300"), Color("#f3e6c4"))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(st)
	var hl := UI.wrap_lbl(hints[sec] + "  " + tr("Tap an item to see what it does."), 16, Color("#7a5a3a"))
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(hl)
	for e in slice:
		pv.add_child(_book_entry(e))
	v.add_child(page)
	UI.pop_in(page, 0.0, 10)
	var nav := UI.hbox(10)
	var prev := UI.btn("◀️", func():
		book_page -= 1
		render(), false, 26, "purple")
	prev.custom_minimum_size = Vector2(96, 72)
	prev.disabled = book_page == 0
	nav.add_child(prev)
	var pl := UI.title(tr("Page %d / %d") % [book_page + 1, pages], 22)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(pl)
	var nxt := UI.btn("▶️", func():
		book_page += 1
		render(), false, 26, "purple")
	nxt.custom_minimum_size = Vector2(96, 72)
	nxt.disabled = book_page >= pages - 1
	nav.add_child(nxt)
	v.add_child(nav)
	if book_item != "" and GameData.items.has(book_item):
		# the tapped item's full card on top; tap anywhere to close
		var io := _overlay("", func():
			book_item = ""
			render())
		var ic := _item_info_card({"id": book_item, "rot": 0, "item": null, "shop": {}})
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		io[1].add_child(ic)
		var cb := UI.btn("✖ " + tr("Close"), func():
			book_item = ""
			render(), false, 20, "gray")
		cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		io[1].add_child(cb)
		UI.pop_in(ic, 0.0, 12)
		o[0].add_child(io[0])
	return o[0]


## One book line with big icons and names: A ×2 ➡️ B ×2 ➡️ C, or A + B ➡️ R.
func _book_entry(e: Dictionary) -> Control:
	var p := UI.panel(Color(1, 1, 1, 0.45), Color("#c9a876"), 2, 16, 10)
	var h := UI.hbox(6)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(h)
	if e.sec == "evo":
		var chain: Array = e.chain
		for i in chain.size():
			var id: String = chain[i]
			var known: bool = i == 0 or run.seen.has(id) or run.seen.has(chain[i - 1])
			h.add_child(_book_chip(id, known, "×2" if i < chain.size() - 1 else ""))
			if i < chain.size() - 1:
				h.add_child(UI.lbl("➡️", 22))
	else:
		var r: Dictionary = e.r
		h.add_child(_book_chip(r.a, true, ""))
		h.add_child(UI.title("+", 28, Color("#5a3300"), Color("#f3e6c4")))
		h.add_child(_book_chip(r.b, true, ""))
		if r.get("c", "") != "":
			h.add_child(UI.title("+", 28, Color("#5a3300"), Color("#f3e6c4")))
			h.add_child(_book_chip(r.c, true, ""))
		h.add_child(UI.lbl("➡️", 22))
		var known: bool = run.seen.has(r.r) or (run.seen.has(r.a) and run.seen.has(r.b))
		var path_tag := ""
		if r.path != "":
			path_tag = GameData.paths[r.path].ic + " " + tr(GameData.paths[r.path].n)
		h.add_child(_book_chip(r.r, known, path_tag))
	return p


func _book_chip(id: String, known: bool, tag: String) -> Control:
	var d: Dictionary = GameData.items[id]
	var col: Color = GameData.tier_colors[d.tier]
	var v := UI.vbox(2)
	v.custom_minimum_size.x = 104
	var c := UI.card(col.darkened(0.35) if known else Color("#8f8170"), _owned_col(run.owns(id), col), 16, 4)
	c.custom_minimum_size = Vector2(80, 80)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var il := UI.lbl(d.ic if known else "❓", 44)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	il.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(il)
	if known:
		c.tooltip_text = I18n.t(d.n)
		# tap / click: open the item's full card
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		c.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				book_item = id
				render())
	v.add_child(c)
	var nl := UI.lbl(tr(d.n) if known else "???", 14, Color("#3b2410"), true)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size.x = 100
	v.add_child(nl)
	if tag != "":
		var tl := UI.lbl(tag, 13, Color("#8a5a2b"), true)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tl)
	return v


func _owned_col(owned: bool, col: Color) -> Color:
	return UI.GOOD if owned else col


# =============================================================== input / drag

func _on_grid_press(cell: Vector2i) -> void:
	if drag_item != null:
		return
	var it: PItem = run.occ().get(cell)
	if run.phase != "morning":
		if it != null:
			selected = it
			render()
		return
	if it != null:
		_press({"item": it, "src": "grid"})
		return
	if run.can_unlock(cell):
		run.unlock(cell)
		if grid:
			UI.burst(grid, (Vector2(cell) + Vector2(0.5, 0.5)) * cell_px, UI.GOOD, 14, 200, 6)
		render()
		return
	if selected != null or inspect_id != "":
		_clear_sel()
		render()


func _press(p: Dictionary) -> void:
	if drag_item != null:
		return
	pending = p
	press_pos = get_global_mouse_position()
	if storage_scroll and is_instance_valid(storage_scroll):
		_press_scroll = storage_scroll.scroll_horizontal


func _input(event: InputEvent) -> void:
	if run == null or run.end_state != "":
		return
	if event is InputEventMouseMotion:
		var pos := get_global_mouse_position()
		if _landscape and drag_item == null and pending.is_empty():
			# PC: pointing at a pack item shows its card (storage and shop cards use mouse_entered)
			if grid and is_instance_valid(grid) and grid.get_global_rect().has_point(pos):
				var gi: PItem = run.occ().get(grid.cell_at(pos))
				if gi != null:
					_set_hover({"kind": "grid", "uid": gi.uid})
				elif _hover.get("kind", "") == "grid":
					_set_hover({})
			elif _hover.get("kind", "") == "grid":
				_set_hover({})
			_move_tip()
		# storage on a touch screen: a sideways swipe scrolls the strip; up/down picks the item up.
		# With a real mouse any drag picks it up (the wheel scrolls the strip instead).
		var touch: bool = event.device == InputEvent.DEVICE_ID_EMULATION or not _landscape
		if touch and not pending.is_empty() and drag_item == null and pending.src == "storage" and storage_scroll:
			var dv := pos - press_pos
			if pending.get("scroll", false) or (absf(dv.x) > DRAG_THRESHOLD and absf(dv.x) > absf(dv.y) * 1.2):
				pending["scroll"] = true
				storage_scroll.scroll_horizontal = maxi(0, _press_scroll - int(dv.x))
				return
		if not pending.is_empty() and drag_item == null and pos.distance_to(press_pos) > DRAG_THRESHOLD:
			_begin_drag()
		if drag_item != null:
			_update_drag(pos)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not pending.is_empty():
			if pending.get("scroll", false):
				pending = {}
				return
			if drag_item != null:
				_drop(get_global_mouse_position())
				get_viewport().set_input_as_handled()
			else:
				_tap()
			pending = {}
		elif (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN) and event.pressed and drag_item != null:
			_rotate(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			get_viewport().set_input_as_handled()
		elif (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN) and event.pressed and storage_scroll and is_instance_valid(storage_scroll) and storage_scroll.get_global_rect().has_point(get_global_mouse_position()):
			# the wheel scrolls the storage strip sideways (its cards would swallow it otherwise)
			var step := 90 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -90
			if _wide:
				storage_scroll.scroll_vertical = maxi(0, storage_scroll.scroll_vertical + step)
			else:
				storage_scroll.scroll_horizontal = maxi(0, storage_scroll.scroll_horizontal + step)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and drag_item != null:
			_rotate(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _landscape and pending.is_empty():
			_right_click()
	elif event is InputEventScreenTouch and event.pressed and event.index >= 1 and drag_item != null:
		_rotate(1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R: _rotate(1)
			KEY_Q: _rotate(-1)
			KEY_ESCAPE:
				if drag_item != null:
					_cancel_drag()
					_end_drag()
				_clear_sel()
				show_book = false
				render()


func _tap() -> void:
	var p := pending
	if _landscape:
		return   # PC: left click only drags; pointing shows the card, right-click rotates / keeps
	match p.src:
		"shop":
			# a second tap on the same card within 0.4 s locks / unlocks it for tomorrow
			var now := Time.get_ticks_msec()
			if p.idx == _last_shop_tap_idx and now - _last_shop_tap_ms < 400 and p.idx < run.shop.size():
				run.toggle_lock(p.idx)
				var locked: bool = run.shop[p.idx].get("lock", false)
				toast(("🔒 " + tr("Locked: it stays in the shop tomorrow.")) if locked else ("🔓 " + tr("Unlocked.")), UI.STAR)
				_last_shop_tap_idx = -1
			else:
				_last_shop_tap_idx = p.idx
				_last_shop_tap_ms = now
			selected = null
			inspect_id = p.id
			inspect_idx = p.idx
		_:
			var it: PItem = p.item
			if selected == it and run.phase == "morning":
				_rotate(1)
				return
			inspect_id = ""
			inspect_idx = -1
			selected = it
	render()


func _begin_drag() -> void:
	if run.phase != "morning" or run.needs_path():
		pending = {}
		return
	_set_hover({})
	var p := pending
	drag_src = p.src
	if drag_src == "shop":
		drag_shop_idx = p.idx
		var it := PItem.new()
		it.uid = -1
		it.id = p.id
		it.loc = "held"
		it.b = run._zero_b()
		run.items.append(it)
		drag_item = it
		drag_orig = {}
	else:
		drag_item = p.item
		drag_orig = {"loc": drag_item.loc, "x": drag_item.x, "y": drag_item.y, "rot": drag_item.rot}
		drag_item.loc = "held"
	selected = drag_item
	inspect_id = ""
	inspect_idx = -1
	if popup:
		popup.visible = false
	ghost.setup(drag_item.id, drag_item.rot, grid.cell if grid else cell_px, true)
	ghost.visible = true
	ghost.scale = Vector2(0.8, 0.8)
	ghost.create_tween().tween_property(ghost, "scale", Vector2(1.08, 1.08), 0.15).set_trans(Tween.TRANS_BACK)
	if sell_zone and sell_lbl:
		if drag_src == "shop":
			pass
		elif drag_item.starter:
			sell_lbl.text = "🛒 " + tr("Starter items can't be sold")
			UI.heading_font(sell_lbl)
		else:
			sell_lbl.text = "🛒 " + tr("Sell: +%d🪙") % run.sell_price(drag_item)
			UI.heading_font(sell_lbl)
			sell_zone.self_modulate = Color(1.4, 1.25, 0.9)
	if storage_panel and drag_src != "storage":
		storage_panel.self_modulate = Color(1.15, 1.3, 1.5)
	_update_drag(get_global_mouse_position())


func _update_drag(pos: Vector2) -> void:
	if grid and grid.get_global_rect().has_point(pos):
		hover_cell = grid.cell_at(pos)
	else:
		hover_cell = Vector2i(-1, -1)
	var m := GameData.mid_cell(drag_item.id, drag_item.rot)
	var target := pos - (Vector2(m) + Vector2(0.5, 0.5)) * ghost.cell * ghost.scale.x
	if ghost.position.distance_to(target) > 400:
		ghost.position = target
	else:
		ghost.position = ghost.position.lerp(target, 0.65)
	ghost.tint = Color(1, 1, 1, 0.6 if hover_cell.x >= 0 else 0.95)
	ghost.queue_redraw()
	if held_lbl:
		held_lbl.text = _held_text()


func _rotate(d: int) -> void:
	if run == null or run.phase != "morning":
		return
	if drag_item != null:
		drag_item.rot = (drag_item.rot + d + 4) % 4
		ghost.set_rot(drag_item.rot)
		ghost.rotation = -PI / 2 * d
		ghost.create_tween().tween_property(ghost, "rotation", 0.0, 0.15).set_trans(Tween.TRANS_BACK)
		_update_drag(get_global_mouse_position())
		return
	if selected == null or not run.items.has(selected):
		return
	var it := selected
	if it.loc == "grid":
		var res := run.rotate_in_pack(it, d)
		if res == "x":
			run.msg = tr("No room to rotate it here — drag it somewhere with more space.")
		elif res != "":
			run.msg = res
		pops[it.uid] = 0.0
	else:
		it.rot = (it.rot + d + 4) % 4
	render()


func _drop(pos: Vector2) -> void:
	var it := drag_item
	var done := false
	var landed := false
	if grid and grid.get_global_rect().has_point(pos):
		var a := run.anchor_for(it, grid.cell_at(pos))
		if run.fits(it, a.x, a.y):
			if drag_src != "shop" or _pay_shop():
				it.loc = "grid"
				it.x = a.x
				it.y = a.y
				done = true
				landed = true
		elif run.on_tiles(it.id, it.rot, a):
			# items in the way swap into the spot it came from, step aside, or go to storage
			if drag_src != "shop" or _pay_shop():
				var before := {}
				for o in run.grid_items():
					before[o.uid] = Vector2(o.x, o.y)
				var origin: Dictionary = drag_orig if drag_src == "grid" and drag_orig.get("loc", "") == "grid" else {}
				var res := run.place_with_bump(it, a, origin)
				for uid in res.moved:
					anim[uid] = before.get(uid, Vector2.ZERO)
					pops[uid] = 0.0
				if res.stored > 0:
					toast("📦 " + tr("%d item(s) had no room and went to storage.") % res.stored, UI.AC)
				done = true
				landed = true
		else:
			run.msg = tr("Does not fit there.")
	elif storage_panel and storage_panel.get_global_rect().has_point(pos):
		if drag_src != "shop" or _pay_shop():
			it.loc = "storage"
			done = true
	elif sell_zone and sell_zone.get_global_rect().has_point(pos) and drag_src != "shop":
		if it.starter or it.def().relic:
			run.msg = tr("Starter items can't be sold.")
		else:
			var g := run.sell_price(it)
			it.loc = drag_orig.loc
			run.sell(it)
			toast("🪙 " + tr("Sold %s for %d🪙.") % [tr(it.def().n), g], UI.GOLD)
			_clear_sel()
			done = true
	if not done:
		_cancel_drag()
	elif landed and grid:
		# start the slide from where the finger let go, then pop
		var local: Vector2 = grid.get_global_transform().affine_inverse() * (ghost.position)
		anim[it.uid] = local / cell_px
		pops[it.uid] = 0.0
		var c := (Vector2(it.x, it.y) + Vector2(GameData.mid_cell(it.id, it.rot)) + Vector2(0.5, 0.5)) * cell_px
		var gref := grid
		gref.create_tween().tween_callback(func():
			if is_instance_valid(gref):
				UI.burst(gref, c, GameData.tier_color(it.id), 14, 220, 6)).set_delay(0.08)
	_end_drag()
	if done and drag_src != "shop" and selected == it and it.loc != "grid":
		_clear_sel()
	if landed:
		selected = null
	render()


func _pay_shop() -> bool:
	var e: Dictionary = run.shop[drag_shop_idx]
	if run.gold < e.price:
		run.msg = tr("Not enough gold.")
		return false
	run.gold -= e.price
	run._pl({"a": "buy", "id": e.id, "price": e.price})   # the play log's buys (buy_item logs the tap-to-buy ones)
	drag_item.paid = int(e.price)
	run.shop.remove_at(drag_shop_idx)
	drag_item.uid = run.uid_ctr
	run.uid_ctr += 1
	run.seen[drag_item.id] = true
	return true


func _cancel_drag() -> void:
	if drag_item == null:
		return
	if drag_src == "shop":
		run.items.erase(drag_item)
		if selected == drag_item:
			selected = null
	else:
		drag_item.loc = drag_orig.loc
		drag_item.x = drag_orig.x
		drag_item.y = drag_orig.y
		drag_item.rot = drag_orig.rot


func _end_drag() -> void:
	drag_item = null
	drag_src = ""
	drag_shop_idx = -1
	hover_cell = Vector2i(-1, -1)
	ghost.visible = false
	ghost.rotation = 0
	ghost.scale = Vector2.ONE
	pending = {}


# =============================================================== dev: screenshots

func _autoshot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_splash = true
	render()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/00_splash.png")
	_splash = false
	render()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			I18n.set_lang(a.trim_prefix("--lang="))
			render()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/01_title.png")
	for st in [1, 2, 3]:
		title_step = st
		render()
		await get_tree().create_timer(0.8).timeout
		await _shot(dir + "/01_title_step%d.png" % st)
	title_step = 0
	run = RunState.new(sel_cls, sel_pet, sel_diff)
	run.gold = 40
	for id in ["flame_saber", "bellows", "ash_plate", "health_potion", "smith_hammer"]:
		run.items.append(run.make_item(id, "storage"))
	render()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/02_morning.png")
	inspect_id = run.shop[0].id
	inspect_idx = 0
	render()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/03_inspect_shop.png")
	_clear_sel()
	selected = run.grid_items()[0]
	render()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/04_inspect_owned.png")
	_clear_sel()
	render()
	await get_tree().process_frame
	var gr := grid.get_global_rect()
	_press({"src": "shop", "idx": 0, "id": run.shop[0].id})
	_begin_drag()
	for _i in 6:
		_update_drag(gr.position + Vector2(cell_px * 3.5, cell_px * 2.5))
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/05_dragging.png")
	_cancel_drag()
	_end_drag()
	show_book = true
	book_item = ""
	render()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/06_book.png")
	show_book = false
	run.day = GameData.path_day
	render()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/07_path_choice.png")
	run.choose_path(run.cls_def().paths[0])
	run.expand = 12
	for _k in 400:
		run.unlock(Vector2i(randi() % GameData.W, randi() % GameData.H))
	for it in run.storage_items():
		var placed := false
		for y in GameData.H:
			for x in GameData.W:
				if not placed and run.fits(it, x, y):
					it.loc = "grid"
					it.x = x
					it.y = y
					placed = true
	# a second Fire Gem touching the first, so the night shows an evolution
	var gem := run.make_item("fire_gem", "held")
	run.items.append(gem)
	var first: PItem = run.grid_items().filter(func(i): return i.id == "fire_gem")[0]
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var a: Vector2i = Vector2i(first.x, first.y) + dv
		if gem.loc == "held" and run.fits(gem, a.x, a.y):
			gem.loc = "grid"
			gem.x = a.x
			gem.y = a.y
	if gem.loc == "held":
		gem.loc = "storage"
	run.travel()
	render()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/08_road.png")
	# every event screen
	var keep_nodes := run.nodes.duplicate(true)
	var gold0 := run.gold
	for k in RunState.EVENTS:
		run.gold = 60
		run.nodes = [{"k": k}]
		run.cur_node = 0
		run.start_event(k)
		if k == "roulette":
			run.ev_pull()
		render()
		await get_tree().create_timer(0.8).timeout
		await _shot(dir + "/08_event_%s.png" % k)
		run.phase = "afternoon"
		run.event = {}
	run.nodes = keep_nodes
	run.gold = gold0
	render()
	_choose(0)
	await get_tree().create_timer(3.5).timeout
	await _shot(dir + "/09_combat.png")
	if _pending_sim != null:
		_pending_sim.skip_to_end()
		_on_combat_done(_pending_sim.won)
	await get_tree().create_timer(3.5).timeout
	await _shot(dir + "/10_night.png")
	_fused_flash = run.result.get("fused", []).duplicate()
	run.next_day()
	render()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/11_morning_full.png")
	# boss entrance
	run.day = 5
	run.nodes = [{"k": "boss", "e": run.boss_foe(run.boss_on(5))}]
	run.travel()
	_choose(0)
	await get_tree().create_timer(1.3).timeout
	await _shot(dir + "/12_boss_intro.png")
	get_tree().quit()


func _shot(path: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
