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
var show_how := false
var show_book := false
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
	sel_cls = GameData.class_keys[0]
	sel_pet = SaveGame.get_setting("pet", GameData.pet_keys[0] if not GameData.pet_keys.is_empty() else "")
	sel_diff = SaveGame.get_setting("diff", "normal")
	add_child(UI.background())
	ghost_layer = CanvasLayer.new()
	ghost_layer.layer = 50
	add_child(ghost_layer)
	ghost = ShapeView.new()
	ghost.visible = false
	ghost_layer.add_child(ghost)
	toast_layer = CanvasLayer.new()
	toast_layer.layer = 60
	add_child(toast_layer)
	get_tree().auto_accept_quit = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_dev = true
	render()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_autoshot(a.trim_prefix("--autoshot="))


func _process(delta: float) -> void:
	for k in pops:
		pops[k] += delta


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


func _continue_run() -> void:
	var r := SaveGame.load_run()
	if r == null:
		SaveGame.clear_run()
		render()
		return
	run = r
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
func _safe_margins() -> Vector4:
	var m := Vector4(14, 14, 14, 14)
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
func toast(text: String, col := UI.AC) -> void:
	if text == "" or toast_layer == null:
		return
	for c in toast_layer.get_children():
		c.queue_free()
	var p := UI.panel(Color(UI.INK, 0.94), col, 3, 18, 14, 8)
	p.anchor_left = 0.06
	p.anchor_right = 0.94
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
	tw.tween_interval(2.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


# =============================================================== render

func render() -> void:
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
	var sm := _safe_margins()
	m.add_theme_constant_override("margin_left", int(sm.x))
	m.add_theme_constant_override("margin_top", int(sm.y))
	m.add_theme_constant_override("margin_right", int(sm.z))
	m.add_theme_constant_override("margin_bottom", int(sm.w))
	screen.add_child(m)
	if run != null:
		_autosave()   # every state change is saved; finished runs clear the save
		if run.msg != "":
			toast(run.msg)
			run.msg = ""
	var key := _key()
	var fresh := key != _screen_key
	_screen_key = key
	var body: Control
	if run == null:
		body = _title_screen()
	elif run.end_state != "":
		body = _end_screen()
	elif run.phase == "evening" and _pending_sim != null:
		var cvw := CombatView.new().setup(run, _pending_sim)
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
	elif show_book:
		ov = _book_overlay()
	if ov != null:
		screen.add_child(ov)
		if fresh:
			ov.modulate.a = 0
			ov.create_tween().tween_property(ov, "modulate:a", 1.0, 0.25)
	elif drag_item == null and (selected != null or inspect_id != ""):
		popup = _inspector_popup()
		screen.add_child(popup)


func _key() -> String:
	if run == null:
		return "title"
	if run.end_state != "":
		return "end"
	var k := run.phase + str(run.day)
	if run.needs_path():
		k += "path"
	if show_book:
		k += "book"
	return k


## Full-screen popup layer. Content is centred vertically when it is short and scrolls when
## it is long; `close_cb` adds a ✖️ that stays in the corner whatever the scroll position.
func _overlay(title: String, close_cb := Callable()) -> Array:
	var ov := ColorRect.new()
	ov.color = Color(0.03, 0.02, 0.1, 0.88)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + s, 20)
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

func _title_screen() -> Control:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UI.vbox(18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var lang := UI.hbox(8)
	lang.add_child(UI.spacer())
	for code in ["en", "th"]:
		var cc: String = code
		lang.add_child(UI.btn("EN" if code == "en" else "ไทย", func():
			I18n.set_lang(cc)
			SaveGame.set_setting("lang", cc)
			render(), false, 16, "blue" if I18n.lang() == code else "gray"))
	v.add_child(lang)
	var logo := UI.title("PACKCRAFT", 76, UI.GOLD, Color("#5a2300"))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(logo)
	UI.breathe(logo, 0.03)
	var tag := UI.lbl(tr("Pack it. Craft it. Watch it fight."), 20, UI.MU, true)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	var ver := UI.lbl("v" + str(ProjectSettings.get_setting("application/config/version", "")), 14, Color(UI.MU, 0.7))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ver)
	var summary := "" if _dev else SaveGame.run_summary()
	if summary != "":
		var cb := UI.btn("▶️ " + tr("CONTINUE") + "\n" + summary, _continue_run, false, 20, "gold")
		cb.custom_minimum_size = Vector2(0, 90)
		v.add_child(cb)
	var hh := UI.title(tr("Choose your hero"), 26)
	v.add_child(hh)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 14)
	var i := 0
	for k in GameData.class_keys:
		var kk: String = k
		var c: Dictionary = GameData.classes[k]
		var on: bool = k == sel_cls
		var p := UI.card(Color("#4a3a92") if on else UI.PN, UI.GOLD if on else UI.BD, 22, 14)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size.y = 178
		UI.on_tap(p, func():
			sel_cls = kk
			render())
		UI.juice(p)
		var cv := UI.vbox(4)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(cv)
		var ic := UI.plbl(c.hero, 58, UI.TX, false, true)
		cv.add_child(ic)
		var nm := UI.title(tr(c.n), 22, Color.WHITE)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(nm)
		var dl := UI.plbl(c.ic + " " + tr(c.res.n), 16, UI.GOLD if on else UI.MU, true, true)
		cv.add_child(dl)
		g.add_child(p)
		if on:
			UI.breathe(ic, 0.08)
		i += 1
	v.add_child(g)
	v.add_child(_class_info(sel_cls))
	v.add_child(_pet_picker())
	v.add_child(_diff_picker())
	var start := UI.big_btn("▶️ " + tr("START RUN"), func():
		SaveGame.set_setting("pet", sel_pet)
		SaveGame.set_setting("diff", sel_diff)
		run = RunState.new(sel_cls, sel_pet, sel_diff)
		_clear_sel()
		anim.clear()
		render(), "green", 32)
	start.custom_minimum_size = Vector2(0, 96)
	v.add_child(start)
	UI.breathe(start, 0.025)
	v.add_child(_center(UI.btn(tr("How to play") + (" 🔼" if show_how else " 🔽"), func():
		show_how = not show_how
		render(), false, 17, "purple")))
	if show_how:
		var hp := UI.panel(Color(UI.INK, 0.8), UI.BD, 2, 18, 16)
		hp.add_child(UI.wrap_lbl(tr("HOW_TO_PLAY"), 18, Color("#e9e4ff")))
		v.add_child(hp)
	v.add_child(UI.spacer(false))
	return sc


## Pick a companion: a small, always-on buff.
func _pet_picker() -> Control:
	var p := UI.panel(Color(UI.INK, 0.75), UI.BD, 2, 20, 14)
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.title("🐾 " + tr("Choose your pet"), 24))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for k in GameData.pet_keys:
		var kk: String = k
		var pd: Dictionary = GameData.pets[k]
		var on: bool = k == sel_pet
		var c := UI.card(Color("#4a3a92") if on else UI.PN, UI.GOLD if on else UI.BD, 18, 6)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := UI.vbox(0)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(cv)
		var il := UI.plbl(pd.ic, 40, UI.TX, false, true)
		cv.add_child(il)
		var nl := UI.plbl(tr(pd.n), 13, UI.GOLD if on else UI.MU, true, true)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size.x = 120
		cv.add_child(nl)
		UI.on_tap(c, func():
			sel_pet = kk
			render())
		UI.juice(c)
		if on:
			UI.breathe(il, 0.1)
		g.add_child(c)
	v.add_child(g)
	if GameData.pets.has(sel_pet):
		var dl := UI.wrap_lbl(GameData.pets[sel_pet].ic + " " + tr(GameData.pets[sel_pet].n) + ": " + tr(GameData.pets[sel_pet].d), 17, UI.GOLD)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(dl)
	return p


## Pick a difficulty: enemies get tougher (HP and damage) step by step.
func _diff_picker() -> Control:
	var p := UI.panel(Color(UI.INK, 0.75), UI.BD, 2, 20, 14)
	var v := UI.vbox(10)
	p.add_child(v)
	v.add_child(UI.title("⚔️ " + tr("Difficulty"), 24))
	var row := UI.hbox(8)
	var kinds := ["green", "gold", "red", "purple"]
	var i := 0
	for df in GameData.difficulties:
		var id: String = df.id
		var on: bool = id == sel_diff
		var b := UI.btn(df.ic + "
" + tr(df.n), func():
			sel_diff = id
			render(), false, 16, kinds[mini(i, 3)] if on else "gray")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 84
		if on:
			UI.breathe(b, 0.03)
		row.add_child(b)
		i += 1
	v.add_child(row)
	var cur := GameData.diff_def(sel_diff)
	var dl := UI.wrap_lbl(tr("Enemies: HP ×%.2f · damage ×%.2f") % [cur.hp, cur.dps] + ("" if cur.elite <= 0 else "  ·  " + tr("more Elites")), 16, UI.MU)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(dl)
	return p


func _class_info(k: String) -> Control:
	var c: Dictionary = GameData.classes[k]
	var p := UI.panel(Color(UI.INK, 0.75), UI.BD, 2, 20, 16)
	var v := UI.vbox(10)
	p.add_child(v)
	var t := UI.title("%s %s" % [c.hero, tr(c.n)], 24, UI.GOLD)
	v.add_child(t)
	v.add_child(UI.wrap_lbl(tr(c.d), 18, Color("#e9e4ff")))
	v.add_child(UI.wrap_lbl("%s %s: %s" % [c.res.ic, tr(c.res.n), tr(c.res.d)], 17, Color("#cfc8ff")))
	v.add_child(UI.wrap_lbl("%s %s: %s" % [c.ult.ic, tr(c.ult.n), tr(c.ult.d)], 17, UI.GOLD))
	var pr := UI.hbox(8)
	pr.add_child(UI.lbl(tr("Paths (day %d):") % GameData.path_day, 17, UI.MU, true))
	for pid in c.paths:
		var pd: Dictionary = GameData.paths[pid]
		var pp := UI.panel(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 99, 8)
		pp.add_child(UI.lbl(pd.ic + " " + tr(pd.n), 17, UI.TX, true))
		pr.add_child(pp)
	v.add_child(pr)
	var chips := UI.hbox(8)
	chips.add_child(UI.lbl(tr("Starts with"), 17, UI.MU, true))
	for st in c.st:
		chips.add_child(UI.item_chip(st[0]))
	v.add_child(chips)
	return p


func _end_screen() -> Control:
	var cc := CenterContainer.new()
	var v := UI.vbox(18)
	cc.add_child(v)
	var w := run.end_state == "win"
	var t := UI.title(tr("VICTORY") if w else tr("DEFEATED"), 64, UI.GOLD if w else UI.BAD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var i := UI.lbl("🏆" if w else "💀", 130)
	i.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(i)
	UI.breathe(i, 0.06)
	var s := UI.wrap_lbl(tr("The Stone Titan falls. Your build held.") if w else tr("You fell on day %d of %d.") % [run.day, GameData.days], 22)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var path_txt := ""
	if run.path != "":
		path_txt = " · " + run.path_def().ic + " " + tr(run.path_def().n)
	var s2 := UI.lbl("%s %s%s · 🪙 %d" % [run.cls_def().hero, tr(run.cls_def().n), path_txt, run.gold], 18, UI.MU, true)
	s2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s2)
	var b := UI.big_btn("🔁 " + tr("PLAY AGAIN"), func():
		run = null
		render(), "green", 30)
	v.add_child(b)
	if w:
		for k in 5:
			create_tween().tween_callback(func(): UI.burst(cc, Vector2(randf_range(80, 640), randf_range(200, 500)), [UI.GOLD, UI.GOOD, UI.STAR, Color("#4f8cff")].pick_random(), 40, 420, 9)).set_delay(0.3 + k * 0.35)
	return cc


# --------------------------------------------------------------- run screen

func _run_screen(fresh: bool) -> Control:
	run.sync_hp()
	# everything else on this screen is ~940px tall; the pack gets the rest (phones vary a lot)
	cell_px = clampf(floorf((get_viewport_rect().size.y - 940.0) / GameData.H), 46.0, 74.0)
	var root := UI.vbox(10)
	root.add_child(_hud())
	root.add_child(_ribbon())

	# backpack
	var gp := UI.card(Color(UI.PN, 0.92), UI.BD, 22, 10)
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
		render(), false, 22, "purple")
	book.custom_minimum_size = Vector2(60, 56)
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
				create_tween().tween_callback(func():
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

	# storage
	var sp := UI.card(Color(UI.PN, 0.92), UI.BD, 22, 10)
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
	scr.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scr.custom_minimum_size.y = 112
	storage_scroll = scr
	var keep_x := _storage_x
	scr.ready.connect(func(): scr.set_deferred("scroll_horizontal", keep_x))
	scr.get_h_scroll_bar().value_changed.connect(func(v): _storage_x = int(v))
	var row := UI.hbox(10)
	scr.add_child(row)
	sv.add_child(scr)
	for it in items:
		row.add_child(_storage_card(it))
	if items.is_empty():
		var el := UI.lbl(tr("Empty. Drag items here to store them."), 17, UI.MU)
		el.custom_minimum_size.y = 100
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(el)
	root.add_child(sp)

	if run.phase == "morning":
		var shop := _shop_panel(fresh)
		root.add_child(shop)
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


func _hud() -> Control:
	var p := UI.card(Color("#3a2d7a"), Color("#1d1546"), 24, 10)
	var outer := UI.vbox(2)
	p.add_child(outer)
	var h := UI.hbox(10)
	outer.add_child(h)
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
	var col := UI.GOOD if r > 0.5 else Color("#ffb020") if r > 0.25 else UI.BAD
	bar.add_theme_stylebox_override("fill", UI.box(col, col.darkened(0.3), 2, 99, 0))
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
	hr.add_child(UI.lbl("❤️".repeat(run.res) + "🖤".repeat(RunState.MAX_HEARTS - run.res), 18))
	hr.add_child(UI.spacer())
	var dl := UI.lbl(tr("Day %d/%d") % [run.day, GameData.days], 16, UI.GOLD, true)
	hr.add_child(dl)
	hv.add_child(hr)
	h.add_child(hv)
	if run.phase != "morning":
		h.add_child(_gold_pill())   # in the morning the gold sits on the shop, next to the prices
	return p


func _gold_pill() -> Control:
	var gp := UI.panel(Color("#1d1546"), UI.GOLD, 3, 99, 8)
	gp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gp.custom_minimum_size.x = 112
	var gl := UI.title("", 26, UI.GOLD)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gp.add_child(gl)
	UI.count_to(gl, _shown_gold if _shown_gold >= 0 else run.gold, run.gold, "🪙 %d")
	_shown_gold = run.gold
	return gp


## One tidy row of pills: boss warning, today's hazard, modifier, path. Tap one for details.
func _ribbon() -> Control:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 46
	var h := UI.hbox(8)
	sc.add_child(h)
	var pills := []
	for b in GameData.bosses:
		if b.d >= run.day and b.d - run.day <= 3:
			pills.append([("💀 " + tr("Boss in %d days") % (b.d - run.day)) if b.d > run.day + 1 else ("💀 " + tr("Boss tomorrow!")) if b.d == run.day + 1 else ("💀 " + tr("Boss today!")), UI.BAD, tr("Day %d boss: %s (resists %s, weak to %s)") % [b.d, tr(b.n), tr(b.imm), tr(b.weak)]])
	if not run.hz.is_empty():
		pills.append([run.hz.ic + " " + tr(run.hz.n), Color("#ffb020"), tr(run.hz.d)])
	if run.diff != "normal":
		var dd := run.diff_def()
		pills.append([dd.ic + " " + tr(dd.n), UI.BAD, tr("Enemies: HP ×%.2f · damage ×%.2f") % [dd.hp, dd.dps]])
	if run.pet != "":
		pills.append([run.pet_def().ic + " " + tr(run.pet_def().n), UI.GOOD, tr(run.pet_def().d)])
	pills.append(["🌐 " + tr(run.mod.n), UI.STAR, tr(run.mod.d)])
	if run.path != "":
		pills.append([run.path_def().ic + " " + tr(run.path_def().n), UI.GOLD, tr(run.path_def().d)])
	for pl in pills:
		var info: String = pl[2]
		var p := UI.panel(Color(pl[1], 0.18), pl[1], 2, 99, 8)
		p.add_child(UI.plbl(pl[0], 15, Color.WHITE, true))
		UI.on_tap(p, func(): toast(info, UI.MU))
		h.add_child(p)
	return sc


func _held_text() -> String:
	if drag_item != null:
		var t := "✌️ " + tr("Tap with a second finger to rotate")
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
	return tr("Tap an item to see it · tap again to rotate")


func _storage_card(it: PItem) -> Control:
	var d := it.def()
	var c: Color = GameData.tier_colors[d.tier]
	var on := selected == it
	var p := UI.card(c.darkened(0.55), Color.WHITE if on else c, 16, 6)
	p.custom_minimum_size = Vector2(112, 104)
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var top := UI.hbox(6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.custom_minimum_size.y = 50
	top.add_child(UI.plbl(d.ic, 36))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(ShapeView.new().setup(it.id, it.rot, 11))
	top.add_child(cc)
	v.add_child(top)
	var nm := UI.plbl(tr(d.n), 14, UI.TX, true, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size.x = 96
	v.add_child(nm)
	if run.recipe_partner_owned(it.id, true):
		v.add_child(UI.plbl("🔗 " + tr("match!"), 13, UI.GOLD, true, true))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_press({"item": it, "src": "storage"}))
	UI.juice(p)
	return p


# --------------------------------------------------------------- shop

func _shop_panel(fresh: bool) -> Control:
	var shop := UI.card(Color("#2f2468", 0.95), Color("#c47a0c"), 22, 10)
	sell_zone = shop
	var v := UI.vbox(10)
	shop.add_child(v)
	var head := UI.hbox(8)
	sell_lbl = UI.title("🛒 " + tr("Shop"), 24, UI.GOLD)
	head.add_child(sell_lbl)
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
		empty.custom_minimum_size = Vector2(0, 184)
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
	var p := UI.card(col.darkened(0.5), Color.WHITE if on else col, 16, 6)
	p.custom_minimum_size = Vector2(0, 184)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_press({"src": "shop", "idx": i, "id": e.id}))
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
	var ic := UI.plbl(d.ic, 38, UI.TX, false, true)
	v.add_child(ic)
	var nm := UI.plbl(tr(d.n), 15, UI.TX, true, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(80, 34)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var sl := UI.plbl(GameData.short_stats(e.id), 14, Color("#e9e4ff"), true, true)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size.x = 80
	v.add_child(sl)
	v.add_child(UI.spacer(false))
	var can: bool = run.gold >= e.price
	var pb := UI.panel(Color("#ffc93c") if can else Color("#4a4670"), Color("#c47a0c") if can else Color("#2c2950"), 0, 12, 4)
	var sbx: StyleBoxFlat = pb.get_theme_stylebox("panel")
	sbx.border_width_bottom = 5
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_child(UI.plbl("🪙 %d" % e.price, 19, Color("#4a2800") if can else Color("#8f8ab8"), true, true))
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
	var p := UI.card(Color("#221b4d"), col, 26, 18)
	# always at the top: the shop row and storage stay visible while you read
	var at_top := true
	p.anchor_left = 0
	p.anchor_right = 1
	p.anchor_top = 0 if at_top else 1
	p.anchor_bottom = 0 if at_top else 1
	p.offset_left = 10
	p.offset_right = -10
	p.grow_vertical = Control.GROW_DIRECTION_END if at_top else Control.GROW_DIRECTION_BEGIN
	if at_top:
		p.offset_top = 10
	else:
		p.offset_bottom = -10
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
		v.add_child(UI.wrap_lbl(line, 18, Color("#efeaff")))
	for r in run.recipes_for(id):
		v.add_child(_recipe_row(r))
	if owned and run.phase == "morning":
		var tips := UI.hbox(8)
		var rb := UI.btn("🔄 " + tr("Rotate"), func(): _rotate(1), false, 17, "blue")
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tips.add_child(rb)
		tips.add_child(_tip("📦", tr("drag to storage")))
		tips.add_child(_tip("🛒", (tr("sell +%d🪙") % run.sell_price(selected)) if not selected.starter else tr("starter")))
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
		v.add_child(UI.wrap_lbl("💡 " + tr("Or drag it straight into your pack."), 15, UI.MU))
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


func _tip(icon: String, t: String) -> Control:
	var p := UI.panel(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 14, 8)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(0)
	p.add_child(v)
	v.add_child(UI.plbl(icon, 24, UI.TX, false, true))
	v.add_child(UI.plbl(t, 14, UI.MU, true, true))
	return p


func _recipe_row(r: Dictionary) -> Control:
	var h := UI.hbox(6)
	h.add_child(UI.item_chip(r.a, run.owns(r.a)))
	h.add_child(UI.lbl("+", 20, UI.MU, true))
	h.add_child(UI.item_chip(r.b, run.owns(r.b) and (r.a != r.b or run.count_owned(r.a) >= 2)))
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
	var o := _overlay(tr("CHOOSE YOUR PATH"))
	var v: VBoxContainer = o[1]
	var s := UI.wrap_lbl(tr("This choice lasts the whole run. Your path relic goes to storage, and it unlocks that path's Capstone recipe."), 18, Color("#e9e4ff"))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var k := 0
	for pid in run.cls_def().paths:
		var pp: String = pid
		var pd: Dictionary = GameData.paths[pid]
		var p := UI.card(Color("#3a2d7a"), UI.GOLD, 24, 18)
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
		var rl := UI.wrap_lbl("%s: %s" % [tr(rd.n), tr(rd.d)], 16, Color("#e9e4ff"))
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rh.add_child(rl)
		pv.add_child(rh)
		for r in GameData.recipes:
			if r.path == pid:
				pv.add_child(UI.wrap_lbl("👑 " + tr("Capstone: %s = %s + %s") % [tr(GameData.items[r.r].n), tr(GameData.items[r.a].n), tr(GameData.items[r.b].n)], 16, UI.AC))
		pv.add_child(UI.big_btn(tr("Choose %s") % tr(pd.n), func():
			run.choose_path(pp)
			render(), "gold", 24))
		v.add_child(p)
		UI.pop_in(p, 0.15 + 0.12 * k, 40)
		k += 1
	return o[0]


const NK := {
	"combat": ["⚔️", "FIGHT", "#6b7bd6", "red"], "elite": ["👹", "ELITE", "#ef4444", "red"], "boss": ["💀", "BOSS", "#a855f7", "red"],
	"forge": ["🔨", "FORGE", "#f59e0b", "gold"], "camp": ["🏕️", "CAMPFIRE", "#22c55e", "green"], "ambush": ["⚠️", "AMBUSH", "#f97316", "red"],
	"shrine": ["🗿", "DARK SHRINE", "#7c3aed", "purple"], "tailor": ["🧵", "TAILOR", "#0ea5e9", "blue"],
	"smith": ["🔨", "EVENT", "#f59e0b", "gold"], "merchant": ["🛒", "EVENT", "#0ea5e9", "blue"], "roulette": ["🔫", "EVENT", "#ef4444", "red"],
	"cauldron": ["⚗️", "EVENT", "#22c55e", "green"], "altar": ["🗿", "EVENT", "#7c3aed", "purple"], "chest": ["📦", "EVENT", "#d97706", "gold"],
}

const EV := {
	"smith": ["🔨", "Blacksmith", "Pay to evolve one item right now: no second copy needed."],
	"merchant": ["🛒", "Wandering Merchant", "Rare wares, and he buys your items at full price."],
	"roulette": ["🔫", "Russian Roulette", "One bullet, six chambers. Every empty click grows the pot. Walk away any time."],
	"cauldron": ["⚗️", "Alchemist's Cauldron", "Put in two items, get one better item back."],
	"altar": ["🗿", "Cursed Altar", "Take a Legendary item. Pay with 10 Max HP forever, or with a Heart."],
	"chest": ["📦", "Mystery Chests", "Open one. Treasure, gold... or a trap."],
}


func _road_overlay() -> Control:
	var o := _overlay(tr("CHOOSE YOUR ROAD"))
	var v: VBoxContainer = o[1]
	var s := UI.lbl(tr("Day %d · HP %d/%d · Hearts %d/%d") % [run.day, roundi(run.hp), roundi(run.mhp), run.res, RunState.MAX_HEARTS], 18, UI.MU, true)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	for i in run.nodes.size():
		var c := _road_card(run.nodes[i], i)
		v.add_child(c)
		UI.pop_in(c, 0.1 + 0.1 * i, 40)
	v.add_child(_center(UI.btn("◀️ " + tr("Back to the shop"), func():
		run.phase = "morning"
		render(), false, 18, "gray")))
	return o[0]


func _road_card(n: Dictionary, i: int) -> Control:
	var k: Array = NK[n.k]
	var c := Color(k[2])
	var boss: bool = n.k == "boss"
	var p := UI.card(c.darkened(0.62), c, 24, 14)
	var v := UI.vbox(8)
	p.add_child(v)
	var h := UI.hbox(14)
	v.add_child(h)
	var icon := ""
	var nm := ""
	var badges := []
	var sub := ""
	var sub_col := Color("#e9e4ff")
	if n.has("e"):
		var e: Dictionary = n.e
		icon = GameData.foe_icon(e.n)
		nm = tr(e.n)
		badges.append("❤️ %d" % roundi(e.hp))
		badges.append("⚔️ %.1f/s" % (e.get("dps", 0.0) * run.hz.get("atk", 1.0)))
		if e.imm != "": badges.append("🛡️ " + tr("resists %s") % (GameData.elem_icon(e.imm) + tr(e.imm)))
		if e.weak != "": badges.append("💥 " + tr("weak to %s") % (GameData.elem_icon(e.weak) + tr(e.weak)))
		if e.tr != "": badges.append(GameData.traits[e.tr].ic + " " + tr(GameData.traits[e.tr].n))
		badges.append(("🎁 " + tr("loot")) if n.k != "combat" else ("🎲 " + tr("25% loot")))
		if n.k in ["elite", "ambush"]:
			badges.append("🎒+1")
	else:
		icon = k[0]
		nm = tr(EV[n.k][1]) if EV.has(n.k) else tr("Campfire")
		sub = tr(EV[n.k][2]) if EV.has(n.k) else tr("Recover 50% HP")
	var il := UI.lbl(icon, 84 if boss else 68)
	h.add_child(il)
	UI.breathe(il, 0.06)
	var tv := UI.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var tgp := UI.panel(c, c.darkened(0.3), 2, 99, 6)
	tgp.add_child(UI.lbl(k[0] + " " + tr(k[1]), 15, Color.WHITE, true))
	tgp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tv.add_child(tgp)
	tv.add_child(UI.title(nm, 26))
	if sub != "":
		tv.add_child(UI.lbl(sub, 18, sub_col, true))
	if not badges.is_empty():
		var bf := UI.flow(6)
		for b in badges:
			var bp := UI.panel(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 99, 6)
			bp.add_child(UI.lbl(b, 14, Color("#e9e4ff"), true))
			bf.add_child(bp)
		v.add_child(bf)
	if n.has("e") and n.e.has("items"):
		var mp := MiniPack.new().setup(n.e, 34.0)
		mp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var mh := UI.hbox(8)
		mh.alignment = BoxContainer.ALIGNMENT_CENTER
		mh.add_child(UI.lbl("🎒", 22))
		mh.add_child(mp)
		v.add_child(mh)
	var go := UI.btn(("⚔️ " + tr("FIGHT!")) if n.has("e") else (tr("GO") + " ▶️"), func(): _choose(i), false, 26, k[3])
	go.custom_minimum_size.y = 78
	v.add_child(go)
	if n.k in ["elite", "boss", "ambush"]:
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "self_modulate", Color(1.2, 1.1, 1.1), 0.8)
		tw.tween_property(p, "self_modulate", Color.WHITE, 0.8)
	return p


func _choose(i: int) -> void:
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
		head = ("🏆 " + tr("VICTORY!")) if r.win else ("💔 " + tr("DEFEAT"))
	var o := _overlay(head)
	var v: VBoxContainer = o[1]
	var rew: Array = r.get("rew", [])
	var k := 0
	# rewards as big tiles
	var tiles := []
	for w in rew:
		if w.k != "fusion":
			tiles.append(w)
	if not tiles.is_empty():
		var row := UI.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for w in tiles:
			var t := _reward_tile(w, 0.2 + 0.15 * k)
			row.add_child(t)
			k += 1
		v.add_child(row)
	# other happenings that have no tile (used potions, defeat note...)
	var covered := ["🏆", "🎁", "🎒", "❤️", "✨", "🧵", "🗿"]
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
	# evolutions and fusions, animated one after another
	for w in rew:
		if w.k == "fusion":
			v.add_child(_fusion_card(w, 0.4 + 0.5 * k))
			k += 1
	var cs: CombatSim = r.cs
	if cs != null:
		var tp := UI.card(Color(UI.INK, 0.85), UI.BD, 18, 14)
		var tv := UI.vbox(6)
		tp.add_child(tv)
		tv.add_child(UI.title("📊 " + tr("Damage"), 20))
		var rows := cs.items.duplicate()
		rows.sort_custom(func(a, b): return a.st.dmg + a.st.heal + a.st.shield > b.st.dmg + b.st.heal + b.st.shield)
		var top := 1.0
		for x in rows:
			top = maxf(top, x.st.dmg + x.st.heal + x.st.shield)
		for x in rows.slice(0, 8):
			var rh := UI.hbox(8)
			var nl := UI.lbl(x.d.ic + " " + tr(x.d.n), 16, UI.TX, true)
			nl.clip_text = true
			nl.custom_minimum_size.x = 230
			rh.add_child(nl)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = 1
			bar.custom_minimum_size = Vector2(0, 18)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var heal_only: bool = x.st.dmg <= 0
			bar.add_theme_stylebox_override("fill", UI.box(Color("#7dd3fc") if heal_only else Color("#ff9b5e"), Color(0, 0, 0, 0), 0, 99, 0))
			bar.value = 0
			bar.create_tween().tween_property(bar, "value", (x.st.dmg + x.st.heal + x.st.shield) / top, 0.6).set_delay(0.3)
			rh.add_child(bar)
			rh.add_child(UI.lbl(str(roundi(x.st.dmg + x.st.heal + x.st.shield)), 16, UI.TX, true))
			tv.add_child(rh)
		var extra := []
		for kk in cs.stat_dmg:
			if cs.stat_dmg[kk] > 0:
				extra.append("%s %d" % [GameData.statuses[kk].ic, roundi(cs.stat_dmg[kk])])
		extra.append("🛡️ " + tr("Blocked %d") % roundi(cs.blocked))
		extra.append("⭐ " + tr("Ultimates %d") % cs.ults)
		extra.append("⏱️ %.1fs" % (cs.tk / 10.0))
		tv.add_child(UI.wrap_lbl(" · ".join(extra), 16, UI.MU))
		v.add_child(tp)
		UI.pop_in(tp, 0.2 + 0.15 * k, 30)
	var label := tr("See result") if r.over else tr("Claim victory") if r.victory else tr("Next day") + " ▶️"
	var fused: Array = r.get("fused", [])
	var nb := UI.big_btn(label, func():
		_fused_flash = fused.duplicate()
		run.next_day()
		_clear_sel()
		render(), "green", 28)
	v.add_child(nb)
	UI.pop_in(nb, 0.3 + 0.15 * k, 30)
	return o[0]


## A reward tile: big icon, a number that counts up, a caption. Pops in after `delay`.
func _reward_tile(w: Dictionary, delay: float) -> Control:
	var col := UI.GOLD
	var icon := ""
	var cap := ""
	var num := 0
	var fmt := "+%d"
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
		"loot", "forge":
			var d: Dictionary = GameData.items[w.id]
			icon = d.ic
			col = GameData.tier_colors[d.tier]
			cap = tr(d.n)
			fmt = ""
	var p := UI.card(col.darkened(0.55), col, 20, 10)
	p.custom_minimum_size = Vector2(148, 168)
	var vb := UI.vbox(2)
	p.add_child(vb)
	var il := UI.lbl(icon, 56)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(il)
	if w.k in ["loot", "forge"]:
		var tag := UI.panel(col, col.darkened(0.3), 2, 99, 4)
		tag.add_child(UI.plbl(tr("NEW!") if w.k == "loot" else "+3 ⚔️", 14, Color.WHITE, true, true))
		vb.add_child(tag)
	else:
		var nl := UI.title("", 30, col.lightened(0.3))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(nl)
		nl.text = fmt % 0
		var ff := fmt
		var target := num
		create_tween().tween_callback(func(): UI.count_to(nl, 0, target, ff)).set_delay(delay + 0.2)
	var cl := UI.plbl(cap, 14, Color("#e9e4ff"), true, true)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.custom_minimum_size.x = 128
	vb.add_child(cl)
	UI.pop_in(p, delay, 30)
	var pp := p
	create_tween().tween_callback(func(): UI.burst(pp, pp.size / 2, col, 20, 300, 7)).set_delay(delay + 0.15)
	return p


## Two items slide together, flash, and the new item pops out.
func _fusion_card(w: Dictionary, delay: float) -> Control:
	var rd: Dictionary = GameData.items[w.r]
	var col: Color = GameData.tier_colors[rd.tier]
	var p := UI.card(Color("#3d2f10"), UI.GOLD, 22, 12)
	var vb := UI.vbox(4)
	p.add_child(vb)
	var t := UI.title(("✨ " + tr("EVOLUTION!")) if w.evo else ("🔗 " + tr("FUSION!")), 26, UI.GOLD)
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
	var lr: Label = mk.call(rd.ic)
	lr.scale = Vector2.ZERO
	var cap := UI.wrap_lbl("%s + %s ➡️ %s" % [tr(GameData.items[w.a].n), tr(GameData.items[w.b].n), tr(rd.n)] + (("  (" + tr("in storage") + ")") if w.get("stored", false) else ""), 18, Color("#fff3c4"))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.modulate.a = 0
	vb.add_child(cap)
	# park both parts apart once the card has its width
	stage.resized.connect(func():
		var cx := stage.size.x / 2 - 48
		if lr.scale == Vector2.ZERO and la.visible:
			la.position = Vector2(cx - 170, 12)
			lb.position = Vector2(cx + 170, 12)
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
		t2.tween_callback(func():
			la.visible = false
			lb.visible = false
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
	var o := _overlay("")
	var v: VBoxContainer = o[1]
	var big := UI.lbl(info[0], 96)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	UI.breathe(big, 0.05)
	var t := UI.title(tr(info[1]), 38, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var d := UI.wrap_lbl(tr(info[2]), 18, Color("#e9e4ff"))
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
	var tiles := UI.hbox(10)
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	var k := 0
	for w in ev.rew:
		if w.k == "fusion":
			v.add_child(_fusion_card(w, 0.2))
		elif w.k in ["gold", "loot", "hp", "heart", "maxhp"]:
			tiles.add_child(_reward_tile(w, 0.15 * k))
			k += 1
	if tiles.get_child_count() > 0:
		v.add_child(tiles)
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
		vb.add_child(UI.plbl(GameData.short_stats(s.id), 14, Color("#e9e4ff"), true, true))
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
	v.add_child(st)
	var fl := UI.flow(10)
	for it in run.items:
		if it.starter or it.loc == "held" or it.def().relic:
			continue
		var itr: PItem = it
		fl.add_child(_item_pick_card(it, "+%d🪙" % it.def().cost, false, func():
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
		tv.add_child(UI.wrap_lbl(GameData.describe_lines(id)[0], 15, Color("#e9e4ff")))
		var br := UI.hbox(8)
		var ii: int = i
		br.add_child(UI.btn("-10 " + tr("Max HP"), func():
			run.ev_altar(ii, "hp")
			render(), false, 16, "red"))
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


## Every entry the book can show, in page order: evolution chains, then recipes, then Capstones.
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
		render())
	var v: VBoxContainer = o[1]
	var entries := _book_entries()
	var pages := maxi(1, ceili(entries.size() / float(BOOK_PER_PAGE)))
	book_page = clampi(book_page, 0, pages - 1)
	var slice := entries.slice(book_page * BOOK_PER_PAGE, (book_page + 1) * BOOK_PER_PAGE)
	var sec: String = slice[0].sec if not slice.is_empty() else "evo"
	var titles := {"evo": "✨ " + tr("Evolutions"), "recipe": "🔗 " + tr("Recipes"), "cap": "👑 " + tr("Capstones")}
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
	var hl := UI.wrap_lbl(hints[sec], 16, Color("#7a5a3a"))
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
		# storage: a sideways swipe scrolls the strip; up/down picks the item up
		if not pending.is_empty() and drag_item == null and pending.src == "storage" and storage_scroll:
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
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and drag_item != null:
			_rotate(1)
			get_viewport().set_input_as_handled()
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
	match p.src:
		"shop":
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
		else:
			sell_lbl.text = "🛒 " + tr("Sell: +%d🪙") % run.sell_price(drag_item)
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
		if it.starter:
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
		create_tween().tween_callback(func():
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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			I18n.set_lang(a.trim_prefix("--lang="))
			render()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/01_title.png")
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
	get_tree().quit()


func _shot(path: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
