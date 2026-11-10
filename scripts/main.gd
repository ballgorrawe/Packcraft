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
var show_how := false
var show_book := false

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

# widgets of the current screen
var screen: Control
var grid: BackpackGrid
var storage_panel: Control
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


func _overlay(title: String) -> Array:
	var ov := ColorRect.new()
	ov.color = Color(0.03, 0.02, 0.1, 0.86)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + s, 22)
	mc.add_theme_constant_override("margin_top", 46)
	mc.add_theme_constant_override("margin_bottom", 30)
	ov.add_child(mc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mc.add_child(sc)
	var v := UI.vbox(18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	if title != "":
		var t := UI.title(title, 42, UI.GOLD)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
	return [ov, v]


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
	var start := UI.big_btn("▶️ " + tr("START RUN"), func():
		run = RunState.new(sel_cls)
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
	# everything else on this screen is ~870px tall; the pack gets the rest (phones vary a lot)
	cell_px = clampf(floorf((get_viewport_rect().size.y - 870.0) / GameData.H), 46.0, 74.0)
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
	var h := UI.hbox(10)
	p.add_child(h)
	var av := UI.panel(Color("#ffcf3f"), Color("#c47a0c"), 4, 99, 4)
	av.custom_minimum_size = Vector2(66, 66)
	var al := UI.lbl(run.cls_def().hero, 38)
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(al)
	h.add_child(av)
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
	var dl := UI.lbl(tr("Day %d/%d") % [run.day, GameData.days] + "  ·  " + tr(run.phase.capitalize()), 16, UI.MU, true)
	hr.add_child(dl)
	hv.add_child(hr)
	h.add_child(hv)
	var gp := UI.panel(Color("#1d1546"), UI.GOLD, 3, 99, 10)
	gp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gp.custom_minimum_size.x = 120
	var gl := UI.title("", 26, UI.GOLD)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gp.add_child(gl)
	UI.count_to(gl, _shown_gold if _shown_gold >= 0 else run.gold, run.gold, "🪙 %d")
	_shown_gold = run.gold
	h.add_child(gp)
	return p


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
			pills.append(["💀 " + tr("Boss in %d days") % (b.d - run.day) if b.d > run.day else "💀 " + tr("Boss today!"), UI.BAD, tr("Day %d boss: %s (resists %s, weak to %s)") % [b.d, tr(b.n), tr(b.imm), tr(b.weak)]])
	if not run.hz.is_empty():
		pills.append([run.hz.ic + " " + tr(run.hz.n), Color("#ffb020"), tr(run.hz.d)])
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
	var sub := UI.lbl(tr("drag here to sell"), 15, UI.MU, true)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.clip_text = true
	head.add_child(sub)
	var rr := UI.btn("🎲 %d🪙" % run.reroll_cost(), func():
		if run.reroll():
			_clear_sel()
			_screen_key = ""   # replay the card animation
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
			if fresh:
				UI.pop_in(sc, 0.15 + 0.06 * k, 30)
			k += 1
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
	p.anchor_left = 0
	p.anchor_right = 1
	p.anchor_top = 1
	p.anchor_bottom = 1
	p.offset_left = 10
	p.offset_right = -10
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
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
		tips.add_child(_tip("🔄", tr("tap again")))
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
	# slide up
	p.modulate.a = 0
	p.offset_bottom = 80
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
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
		var f := run.forecast(e)
		icon = GameData.foe_icon(e.n)
		nm = tr(e.n)
		sub = {"Safe": "😎 ", "Risky": "😬 ", "Deadly": "☠️ "}.get(f.tag, "") + "%s · ~-%d HP" % [tr(f.tag), roundi(minf(run.hp, f.taken))]
		sub_col = f.color
		badges.append("❤️ %d" % roundi(e.hp))
		badges.append("⚔️ %s" % GameData._num(e.atk))
		if e.imm != "": badges.append("🛡️ " + tr("resists %s") % (GameData.elem_icon(e.imm) + tr(e.imm)))
		if e.weak != "": badges.append("💥 " + tr("weak to %s") % (GameData.elem_icon(e.weak) + tr(e.weak)))
		if e.tr != "": badges.append(GameData.traits[e.tr].ic + " " + tr(GameData.traits[e.tr].n))
		badges.append(("🎁 " + tr("loot")) if n.k != "combat" else ("🎲 " + tr("25% loot")))
		if n.k in ["elite", "ambush"]:
			badges.append("🎒+1")
	else:
		icon = k[0]
		nm = tr({"forge": "Forge", "camp": "Campfire", "shrine": "Dark Shrine", "tailor": "Tailor"}[n.k])
		sub = tr({"forge": "+3 damage on a random weapon", "camp": "Recover 50% HP", "shrine": "Free Epic+ item · -15 HP", "tailor": "+3 pack tiles"}[n.k])
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
	tv.add_child(UI.lbl(sub, 18, sub_col, true))
	if not badges.is_empty():
		var bf := UI.flow(6)
		for b in badges:
			var bp := UI.panel(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 99, 6)
			bp.add_child(UI.lbl(b, 14, Color("#e9e4ff"), true))
			bf.add_child(bp)
		v.add_child(bf)
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
	var o := _overlay(("🏆 " + tr("VICTORY!")) if r.win and r.n.has("e") else ("🌙 " + tr("NIGHT")))
	var v: VBoxContainer = o[1]
	var k := 0
	for l in r.lines:
		var fusion: bool = l.begins_with("✨")
		var fp := UI.card(Color("#4a3a12") if fusion else Color(UI.PN, 0.95), UI.GOLD if fusion else UI.BD, 18, 14)
		var line := UI.wrap_lbl(l, 20 if fusion else 18, UI.GOLD if fusion else UI.TX)
		fp.add_child(line)
		v.add_child(fp)
		UI.pop_in(fp, 0.15 + 0.15 * k, 30)
		if fusion:
			var ff := fp
			create_tween().tween_callback(func(): UI.burst(ff, ff.size / 2, UI.GOLD, 36, 380, 9)).set_delay(0.4 + 0.15 * k)
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
	var nb := UI.big_btn(label, func():
		run.next_day()
		_clear_sel()
		render(), "green", 28)
	v.add_child(nb)
	UI.pop_in(nb, 0.3 + 0.15 * k, 30)
	return o[0]


func _book_overlay() -> Control:
	var o := _overlay(tr("RECIPE BOOK"))
	var v: VBoxContainer = o[1]
	v.add_child(UI.wrap_lbl(tr("Place the two parts so they touch. They fuse at night. Two copies of the same item evolve into something new."), 18, Color("#e9e4ff")))
	var ep := UI.card(Color(UI.PN, 0.95), UI.BD, 18, 14)
	var ev := UI.vbox(8)
	ep.add_child(ev)
	ev.add_child(UI.title("✨ " + tr("Evolutions"), 22, UI.GOLD))
	for r in GameData.recipes:
		if r.evo and run.in_class_pool(r.a):
			ev.add_child(_recipe_row(r))
	v.add_child(ep)
	var rp := UI.card(Color(UI.PN, 0.95), UI.BD, 18, 14)
	var rv := UI.vbox(8)
	rp.add_child(rv)
	rv.add_child(UI.title("🔗 " + tr("Recipes"), 22, UI.GOLD))
	for r in GameData.recipes:
		if not r.evo and run.in_class_pool(r.r) and (r.path == "" or run.path == "" or r.path == run.path):
			rv.add_child(_recipe_row(r))
	v.add_child(rp)
	v.add_child(UI.big_btn(tr("Close"), func():
		show_book = false
		render(), "gray", 24))
	return o[0]


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


func _input(event: InputEvent) -> void:
	if run == null or run.end_state != "":
		return
	if event is InputEventMouseMotion:
		var pos := get_global_mouse_position()
		if not pending.is_empty() and drag_item == null and pos.distance_to(press_pos) > DRAG_THRESHOLD:
			_begin_drag()
		if drag_item != null:
			_update_drag(pos)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not pending.is_empty():
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
	run = RunState.new(sel_cls)
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
	run.travel()
	render()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/08_road.png")
	_choose(0)
	await get_tree().create_timer(3.5).timeout
	await _shot(dir + "/09_combat.png")
	if _pending_sim != null:
		_pending_sim.skip_to_end()
		_on_combat_done(_pending_sim.won)
	await get_tree().create_timer(1.2).timeout
	await _shot(dir + "/10_night.png")
	run.phase = "morning"
	render()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/11_morning_full.png")
	get_tree().quit()


func _shot(path: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
