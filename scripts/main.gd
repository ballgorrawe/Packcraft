extends Control
## Screen manager + drag-and-drop controller for PackCraft (portrait, phone-first).
## Screens are rebuilt in code from RunState on every change (like a render() call).
## Items have no Store / Sell / Rotate buttons: drag to the shop to sell, drag to storage
## to store, tap a placed item again to rotate it.

const CELL := 72.0
const DRAG_THRESHOLD := 12.0
const W := 720.0

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

var _dev := false   # screenshot/dev mode never touches the real save
var _pending_sim: CombatSim = null


func _ready() -> void:
	GameData.ensure_loaded()
	I18n.setup(SaveGame.get_setting("lang", "th" if OS.get_locale_language() == "th" else "en"))
	theme = UI.build_theme()
	sel_cls = GameData.class_keys[0]
	ghost_layer = CanvasLayer.new()
	ghost_layer.layer = 50
	add_child(ghost_layer)
	ghost = ShapeView.new()
	ghost.visible = false
	ghost_layer.add_child(ghost)
	get_tree().auto_accept_quit = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_dev = true
	render()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_autoshot(a.trim_prefix("--autoshot="))


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
	var m := Vector4(12, 12, 12, 12)
	if not OS.has_feature("mobile"):
		return m
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var vis := get_viewport_rect().size
	if win.x <= 0 or vis.x <= 0:
		return m
	var k := vis.x / win.x
	m.x = maxf(12, safe.position.x * k)
	m.y = maxf(12, safe.position.y * k)
	m.z = maxf(12, (win.x - safe.end.x) * k)
	m.w = maxf(12, (win.y - safe.end.y) * k)
	return m


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
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen = bg
	add_child(screen)
	move_child(screen, 0)
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
	if run == null:
		m.add_child(_title_screen())
		return
	if run.end_state != "":
		m.add_child(_end_screen())
		return
	if run.phase == "evening" and _pending_sim != null:
		var cvw := CombatView.new().setup(run, _pending_sim)
		cvw.finished.connect(_on_combat_done)
		m.add_child(cvw)
		return
	m.add_child(_run_screen())
	if run.needs_path():
		screen.add_child(_path_choice_overlay())
	elif run.phase == "afternoon":
		screen.add_child(_road_overlay())
	elif run.phase == "night":
		screen.add_child(_night_overlay())
	elif show_book:
		screen.add_child(_book_overlay())
	elif drag_item == null and (selected != null or inspect_id != ""):
		popup = _inspector_popup()
		screen.add_child(popup)


func _overlay(title: String) -> Array:
	var ov := ColorRect.new()
	ov.color = Color(0.02, 0.05, 0.06, 0.9)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + s, 18)
	mc.add_theme_constant_override("margin_top", 40)
	mc.add_theme_constant_override("margin_bottom", 30)
	ov.add_child(mc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mc.add_child(sc)
	var v := UI.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	if title != "":
		v.add_child(_logo(title, 34))
	return [ov, v]


func _logo(text: String, size := 54) -> Label:
	var l := UI.lbl(text, size, Color("#ffb43a"), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_outline_color", Color("#3a1600"))
	l.add_theme_constant_override("outline_size", 12)
	return l


func _center(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return c


# --------------------------------------------------------------- title

func _title_screen() -> Control:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UI.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(UI.spacer(false))
	var lang := UI.hbox(6)
	lang.add_child(UI.spacer())
	for code in ["en", "th"]:
		var cc: String = code
		lang.add_child(UI.btn("EN" if code == "en" else "ไทย", func():
			I18n.set_lang(cc)
			SaveGame.set_setting("lang", cc)
			render(), I18n.lang() == code, 14))
	v.add_child(lang)
	v.add_child(_logo("PACKCRAFT", 64))
	var tag := UI.lbl(tr("Pack it. Craft it. Watch it fight."), 17, Color("#9fb7c4"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	var summary := "" if _dev else SaveGame.run_summary()
	if summary != "":
		v.add_child(_center(UI.btn("▶ " + tr("CONTINUE") + "  —  " + summary, _continue_run, true, 18)))
	v.add_child(UI.lbl(tr("Choose your hero"), 20, UI.TX, true))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	for k in GameData.class_keys:
		var kk: String = k
		var c: Dictionary = GameData.classes[k]
		var on: bool = k == sel_cls
		var p := UI.panel(Color(UI.GOLD, 0.16) if on else Color(1, 1, 1, 0.05), UI.GOLD if on else Color(1, 1, 1, 0.18), 3 if on else 2, 14, 12)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size.y = 150
		UI.on_tap(p, func():
			sel_cls = kk
			render())
		var cv := UI.vbox(4)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(cv)
		cv.add_child(UI.plbl(c.hero + " " + c.ic, 40, UI.TX, false, true))
		cv.add_child(UI.plbl(tr(c.n), 18, Color.WHITE, true, true))
		var dl := UI.plbl(tr(c.d), 13, Color("#b6c8d2"), false, true)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(dl)
		g.add_child(p)
	v.add_child(g)
	v.add_child(_class_info(sel_cls))
	v.add_child(_center(UI.btn(tr("START RUN") + " ▶", func():
		run = RunState.new(sel_cls)
		_clear_sel()
		render(), true, 22)))
	v.add_child(_center(UI.btn(tr("How to play") + (" 🔼" if show_how else " 🔽"), func():
		show_how = not show_how
		render(), false, 15)))
	if show_how:
		v.add_child(UI.wrap_lbl(tr("HOW_TO_PLAY"), 15, Color("#cfe0e8")))
	v.add_child(UI.spacer(false))
	return sc


func _class_info(k: String) -> Control:
	var c: Dictionary = GameData.classes[k]
	var p := UI.panel(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 14, 14)
	var v := UI.vbox(8)
	p.add_child(v)
	v.add_child(UI.wrap_lbl("%s %s — %s" % [c.res.ic, tr(c.res.n), tr(c.res.d)], 14, Color("#cfe0e8")))
	v.add_child(UI.wrap_lbl("%s %s: %s %s" % [c.ult.ic, tr("Ultimate"), tr(c.ult.n), "— " + tr(c.ult.d)], 14, UI.GOLD))
	var pr := UI.hbox(8)
	pr.add_child(UI.lbl(tr("Paths (day %d):") % GameData.path_day, 14, UI.MU))
	for pid in c.paths:
		var pd: Dictionary = GameData.paths[pid]
		var pp := UI.panel(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 99, 5)
		pp.add_child(UI.lbl(pd.ic + " " + tr(pd.n), 14, UI.TX, true))
		pr.add_child(pp)
	v.add_child(pr)
	var chips := UI.flow(6)
	chips.add_child(UI.lbl(tr("Starts with"), 14, UI.MU))
	for st in c.st:
		chips.add_child(UI.item_chip(st[0]))
	v.add_child(chips)
	return p


func _end_screen() -> Control:
	var cc := CenterContainer.new()
	var v := UI.vbox(14)
	cc.add_child(v)
	var w := run.end_state == "win"
	v.add_child(_logo(tr("VICTORY") if w else tr("DEFEATED"), 48))
	var i := UI.lbl("🏆" if w else "💀", 96)
	i.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(i)
	var t := UI.lbl(tr("The Stone Titan falls. Your build held.") if w else tr("You fell on day %d of %d.") % [run.day, GameData.days], 18)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var path_txt := ""
	if run.path != "":
		path_txt = " · " + run.path_def().ic + " " + tr(run.path_def().n)
	var s := UI.lbl("%s %s%s · 🪙 %d" % [run.cls_def().ic, tr(run.cls_def().n), path_txt, run.gold], 15, Color("#9fb7c4"))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(_center(UI.btn(tr("PLAY AGAIN") + " ▶", func():
		run = null
		render(), true, 20)))
	return cc


# --------------------------------------------------------------- run screen

func _run_screen() -> Control:
	run.sync_hp()
	var root := UI.vbox(8)
	root.add_child(_top_bar())
	var info := _info_strip()
	if info != null:
		root.add_child(info)

	# backpack
	var gp := UI.panel(UI.PN, UI.BD, 1, 12, 8)
	var gv := UI.vbox(6)
	gp.add_child(gv)
	var gh := UI.hbox(8)
	gh.add_child(UI.lbl("🎒 " + tr("Pack"), 18, UI.TX, true))
	var st := UI.rich(_stats_text(), 14)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gh.add_child(st)
	gh.add_child(UI.btn("📖", func():
		show_book = true
		render(), false, 16))
	gv.add_child(gh)
	grid = BackpackGrid.new().setup(self, CELL)
	grid.cell_pressed.connect(_on_grid_press)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gv.add_child(grid)
	held_lbl = UI.wrap_lbl(_held_text(), 14, UI.AC if run.msg != "" else UI.MU)
	held_lbl.custom_minimum_size.y = 40
	gv.add_child(held_lbl)
	root.add_child(gp)

	# storage
	var sp := UI.panel(UI.PN, UI.BD, 1, 12, 8)
	storage_panel = sp
	var sv := UI.vbox(6)
	sp.add_child(sv)
	var items := run.storage_items()
	var sh := UI.hbox(8)
	sh.add_child(UI.lbl("📦 " + tr("Storage") + " (%d)" % items.size(), 16, UI.TX, true))
	var hint := UI.lbl(tr("inactive in fights"), 13, UI.MU)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.clip_text = true
	sh.add_child(hint)
	if run.phase == "morning" and not run.grid_items().is_empty():
		sh.add_child(UI.btn("📥 " + tr("Empty pack"), func():
			if drag_item != null:
				return
			var n := run.clear_pack()
			_clear_sel()
			run.msg = tr("Moved %d items into storage.") % n
			render(), false, 14))
	sv.add_child(sh)
	var scr := ScrollContainer.new()
	scr.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scr.custom_minimum_size.y = 128
	var row := UI.hbox(8)
	scr.add_child(row)
	sv.add_child(scr)
	for it in items:
		row.add_child(_storage_card(it))
	if items.is_empty():
		row.add_child(UI.lbl(tr("Empty. Drag items here to store them."), 14, UI.MU))
	root.add_child(sp)

	if run.phase == "morning":
		root.add_child(_shop_panel())
	return root


func _top_bar() -> Control:
	var p := UI.panel(UI.PN, UI.BD, 1, 12, 8)
	var h := UI.hbox(10)
	p.add_child(h)
	h.add_child(UI.lbl(run.cls_def().hero, 30))
	var hv := UI.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	bar.max_value = 1
	var r := run.hp / run.mhp
	bar.value = r
	var col := UI.GOOD if r > 0.5 else Color("#f59e0b") if r > 0.25 else UI.BAD
	bar.add_theme_stylebox_override("fill", UI.box(col, col, 0, 4, 0))
	hv.add_child(bar)
	hv.add_child(UI.lbl("HP %d/%d   %s" % [roundi(run.hp), roundi(run.mhp), "❤️".repeat(run.res) + "🖤".repeat(RunState.MAX_HEARTS - run.res)], 14, UI.TX, true))
	h.add_child(hv)
	h.add_child(_pill("🪙 %d" % run.gold, 20))
	var dv := UI.vbox(0)
	dv.add_child(UI.lbl(tr("Day %d/%d") % [run.day, GameData.days], 16, UI.TX, true))
	dv.add_child(UI.lbl(tr(run.phase.capitalize()), 13, UI.MU))
	h.add_child(dv)
	return p


func _pill(t: String, size := 15) -> Control:
	var p := UI.panel(Color(UI.AC, 0.18), UI.AC, 1, 99, 6)
	p.add_child(UI.lbl(t, size, UI.TX, true))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


func _info_strip() -> Control:
	var parts := []
	for b in GameData.bosses:
		if b.d >= run.day and b.d - run.day <= 3:
			parts.append("⚠️ " + tr("Day %d boss: %s (resists %s, weak to %s)") % [b.d, tr(b.n), tr(b.imm), tr(b.weak)])
	if not run.hz.is_empty():
		parts.append("%s %s: %s" % [run.hz.ic, tr(run.hz.n), tr(run.hz.d)])
	parts.append("🌐 %s: %s" % [tr(run.mod.n), tr(run.mod.d)])
	if run.path != "":
		parts.append("%s %s: %s" % [run.path_def().ic, tr(run.path_def().n), tr(run.path_def().d)])
	var l := UI.wrap_lbl("\n".join(parts), 13, UI.MU)
	return l


func _stats_text() -> String:
	var pr := run.pack_rates()
	var used := 0
	for i in run.grid_items():
		used += GameData.shape(i.id, i.rot).c.size()
	return "[right]⚔ [b]%.1f[/b]/s   🛡 [b]%.1f[/b]/s   🔲 %d/%d[/right]" % [pr.x, pr.y, used, run.tiles.size()]


func _held_text() -> String:
	if drag_item != null:
		var t := tr("Holding %s — tap with a 2nd finger, right-click or R to rotate.") % tr(drag_item.def().n)
		if hover_cell.x >= 0:
			var a := run.anchor_for(drag_item, hover_cell)
			var pr := run.preview(drag_item, a.x, a.y)
			if pr.ok:
				t = tr("Here: damage %+.1f/s · shield %+.1f/s") % [pr.d.x, pr.d.y]
				if pr.lk:
					t += "  ✨ " + tr("forms a Golden Link!")
			else:
				t = tr("Does not fit here.")
		return t
	if run.msg != "":
		return run.msg
	if run.phase != "morning":
		return tr("The market is closed.")
	if run.expand > 0:
		return tr("Tap %d glowing tile(s) to grow your pack.") % run.expand
	return tr("Drag items into the pack. Touching items buff each other; matching pairs fuse at night.")


func _storage_card(it: PItem) -> Control:
	var d := it.def()
	var c: Color = GameData.tier_colors[d.tier]
	var p := UI.panel(c.darkened(0.62), Color.WHITE if selected == it else c, 2, 10, 6)
	p.custom_minimum_size = Vector2(100, 120)
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var top := UI.hbox(4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.custom_minimum_size.y = 48
	top.add_child(UI.plbl(d.ic, 28))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(ShapeView.new().setup(it.id, 0, 11))
	top.add_child(cc)
	v.add_child(top)
	var nm := UI.plbl(tr(d.n), 12, UI.TX, true, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size.x = 88
	v.add_child(nm)
	var tl := UI.plbl(tr(GameData.tier_names[d.tier]) + (" · 🔗" if run.recipe_partner_owned(it.id, true) else ""), 11, c.lightened(0.35), false, true)
	v.add_child(tl)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_press({"item": it, "src": "storage"}))
	return p


# --------------------------------------------------------------- shop

func _shop_panel() -> Control:
	var shop := UI.panel(Color("#1f3236"), UI.AC.darkened(0.3), 2, 12, 10)
	sell_zone = shop
	var v := UI.vbox(8)
	shop.add_child(v)
	var head := UI.hbox(8)
	sell_lbl = UI.lbl("🛒 " + tr("Shop"), 18, UI.TX, true)
	head.add_child(sell_lbl)
	var sub := UI.lbl(tr("drag an item here to sell it"), 13, UI.MU)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.clip_text = true
	head.add_child(sub)
	v.add_child(head)
	var cards := UI.hbox(8)
	var bag_entries := []
	for i in run.shop.size():
		var e: Dictionary = run.shop[i]
		if e.has("bag"):
			bag_entries.append(i)
		else:
			cards.add_child(_shop_card(e, i))
	for _k in range(cards.get_child_count(), 5):
		var empty := UI.panel(Color(0, 0, 0, 0.15), UI.BD, 1, 12, 6)
		empty.custom_minimum_size = Vector2(0, 196)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_child(UI.plbl(tr("Sold"), 13, UI.MU, false, true))
		cards.add_child(empty)
	v.add_child(cards)
	var act := UI.hbox(8)
	for i in bag_entries:
		var e: Dictionary = run.shop[i]
		var ii: int = i
		var b := UI.btn("🎒+%d · %d🪙" % [e.n, e.price], func():
			run.buy_bag(ii)
			render(), false, 14)
		b.disabled = run.gold < e.price
		act.add_child(b)
	act.add_child(UI.btn("🎲 %d🪙" % run.reroll_cost(), func():
		run.reroll()
		_clear_sel()
		render(), false, 14))
	act.add_child(UI.spacer())
	act.add_child(UI.btn(tr("Depart") + " ▶", func():
		if run.travel():
			_clear_sel()
		render(), true, 18))
	v.add_child(act)
	return shop


func _shop_card(e: Dictionary, i: int) -> Control:
	var d: Dictionary = GameData.items[e.id]
	var col: Color = GameData.tier_colors[d.tier]
	var on := inspect_idx == i
	var p := UI.panel(col.darkened(0.62), Color.WHITE if on else col, 2, 12, 6)
	p.custom_minimum_size = Vector2(0, 196)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.0
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_press({"src": "shop", "idx": i, "id": e.id}))
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var top := UI.hbox(0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if e.get("sale", false):
		top.add_child(UI.plbl("-50%", 12, Color("#ff7b7f"), true))
	elif run.recipe_partner_owned(e.id):
		top.add_child(UI.plbl("🔗", 14))
	top.add_child(UI.spacer())
	if e.get("lock", false):
		top.add_child(UI.plbl("🔒", 14))
	top.custom_minimum_size.y = 18
	v.add_child(top)
	v.add_child(UI.plbl(d.ic, 34, UI.TX, false, true))
	var nm := UI.plbl(tr(d.n), 13, UI.TX, true, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(80, 36)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.custom_minimum_size.y = 32
	cc.add_child(ShapeView.new().setup(e.id, 0, 10))
	v.add_child(cc)
	var sl := UI.plbl(GameData.short_stats(e.id), 12, UI.TX, false, true)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size.x = 80
	v.add_child(sl)
	v.add_child(UI.spacer(false))
	var pb := UI.panel(UI.GOLD if run.gold >= e.price else UI.BD, Color(0, 0, 0, 0), 0, 8, 3)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_child(UI.plbl("🪙 %d" % e.price, 15, Color("#3a2600") if run.gold >= e.price else UI.MU, true, true))
	v.add_child(pb)
	return p


func _buy_to_storage(i: int) -> void:
	if drag_item != null:
		return
	var it := run.buy_item(i)
	if it != null:
		it.loc = "storage"
		_clear_sel()
		run.msg = tr("Bought %s — it's in storage.") % tr(it.def().n)
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
	var p := UI.panel(Color("#132328"), col, 3, 16, 14)
	p.anchor_left = 0
	p.anchor_right = 1
	p.anchor_top = 1
	p.anchor_bottom = 1
	p.offset_left = 12
	p.offset_right = -12
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -12
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(8)
	p.add_child(v)
	var h := UI.hbox(12)
	v.add_child(h)
	var sv := ShapeView.new().setup(id, rot, 26, true)
	sv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(sv)
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	tv.add_child(UI.lbl("%s %s" % [d.ic, tr(d.n)], 20, Color.WHITE, true))
	var tags := " · ".join(d.tags.map(func(t): return tr(t)))
	tv.add_child(UI.lbl("%s · %s" % [tr(GameData.tier_names[d.tier]), tags], 13, col.lightened(0.35)))
	h.add_child(UI.btn("✖️", func():
		_clear_sel()
		render(), false, 16))
	for line in GameData.describe_lines(id):
		v.add_child(UI.wrap_lbl(line, 15))
	for r in run.recipes_for(id):
		v.add_child(_recipe_row(r))
	# how to act on it
	var hint := ""
	if owned and run.phase == "morning":
		if selected.starter:
			hint = tr("Starter item: can't be sold.") + "  "
		else:
			hint = tr("Drag to 🛒 to sell (+%d🪙).") % run.sell_price(selected) + "  "
		if selected.loc == "grid":
			hint += tr("Drag to 📦 to store. Tap it again to rotate.")
		else:
			hint += tr("Drag into the pack to use it.")
	elif not owned and inspect_idx >= 0 and inspect_idx < run.shop.size():
		var e: Dictionary = run.shop[inspect_idx]
		var ii := inspect_idx
		hint = tr("Drag into your pack to buy for %d🪙.") % e.price
		var ah := UI.hbox(8)
		ah.add_child(UI.btn(("🔓 " + tr("Unlock")) if e.get("lock", false) else ("🔒 " + tr("Keep for tomorrow")), func():
			run.toggle_lock(ii)
			render(), false, 14))
		ah.add_child(UI.spacer())
		var bb := UI.btn(tr("Buy to storage") + " · %d🪙" % e.price, func(): _buy_to_storage(ii), true, 15)
		bb.disabled = run.gold < e.price
		ah.add_child(bb)
		v.add_child(ah)
	if hint != "":
		var hl := UI.wrap_lbl(hint, 13, UI.AC)
		v.add_child(hl)
	return p


func _recipe_row(r: Dictionary) -> Control:
	var h := UI.hbox(4)
	h.add_child(UI.item_chip(r.a, run.owns(r.a)))
	h.add_child(UI.lbl("+", 16, UI.MU, true))
	h.add_child(UI.item_chip(r.b, run.owns(r.b) and (r.a != r.b or run.count_owned(r.a) >= 2)))
	h.add_child(UI.lbl("➡️", 16, UI.MU, true))
	var known: bool = run.seen.has(r.r) or (run.seen.has(r.a) and run.seen.has(r.b))
	if known:
		h.add_child(UI.item_chip(r.r, run.owns(r.r)))
		var t := tr(GameData.items[r.r].n)
		if r.path != "":
			t += "  (" + GameData.paths[r.path].ic + " " + tr(GameData.paths[r.path].n) + ")"
		var l := UI.lbl(t, 14, UI.TX)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	else:
		h.add_child(UI.unknown_chip())
		h.add_child(UI.lbl("???" + (("  (" + GameData.paths[r.path].ic + ")") if r.path != "" else ""), 14, UI.MU))
	return h


# --------------------------------------------------------------- overlays

func _path_choice_overlay() -> Control:
	var o := _overlay(tr("CHOOSE YOUR PATH"))
	var v: VBoxContainer = o[1]
	var s := UI.wrap_lbl(tr("This choice lasts the whole run. Your path relic goes to storage, and it unlocks that path's Capstone recipe."), 15, Color("#cfe0e8"))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	for pid in run.cls_def().paths:
		var pp: String = pid
		var pd: Dictionary = GameData.paths[pid]
		var p := UI.panel(Color(UI.GOLD, 0.08), UI.GOLD, 2, 16, 16)
		var pv := UI.vbox(8)
		p.add_child(pv)
		pv.add_child(UI.lbl(pd.ic + " " + tr(pd.n), 26, UI.GOLD, true))
		pv.add_child(UI.wrap_lbl(tr(pd.d), 16))
		var rd: Dictionary = GameData.items[pd.relic]
		var rh := UI.hbox(8)
		rh.add_child(UI.item_chip(pd.relic))
		rh.add_child(UI.wrap_lbl("%s: %s" % [tr(rd.n), tr(rd.d)], 14, Color("#cfe0e8")))
		rh.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pv.add_child(rh)
		for r in GameData.recipes:
			if r.path == pid:
				pv.add_child(UI.wrap_lbl("👑 " + tr("Capstone: %s = %s + %s") % [tr(GameData.items[r.r].n), tr(GameData.items[r.a].n), tr(GameData.items[r.b].n)], 14, UI.AC))
		pv.add_child(_center(UI.btn(tr("Choose %s") % tr(pd.n), func():
			run.choose_path(pp)
			render(), true, 18)))
		v.add_child(p)
	return o[0]


const NK := {
	"combat": ["⚔️", "FIGHT", "#64748b"], "elite": ["👹", "ELITE", "#ef4444"], "boss": ["💀", "BOSS", "#a855f7"],
	"forge": ["🔨", "FORGE", "#f59e0b"], "camp": ["🏕️", "CAMPFIRE", "#22c55e"], "ambush": ["⚠️", "AMBUSH", "#f97316"],
	"shrine": ["🗿", "DARK SHRINE", "#7c3aed"], "tailor": ["🧵", "TAILOR", "#0ea5e9"],
}


func _road_overlay() -> Control:
	var o := _overlay(tr("CHOOSE YOUR ROAD"))
	var v: VBoxContainer = o[1]
	var s := UI.lbl(tr("Day %d · HP %d/%d · Hearts %d/%d") % [run.day, roundi(run.hp), roundi(run.mhp), run.res, RunState.MAX_HEARTS], 15, Color("#9fb7c4"))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	for i in run.nodes.size():
		v.add_child(_road_card(run.nodes[i], i))
	v.add_child(_center(UI.btn("◀ " + tr("Back to the shop"), func():
		run.phase = "morning"
		render(), false, 15)))
	return o[0]


func _road_card(n: Dictionary, i: int) -> Control:
	var k: Array = NK[n.k]
	var c := Color(k[2])
	var boss: bool = n.k == "boss"
	var p := UI.panel(c.darkened(0.72), c, 4 if boss else 3, 16, 12)
	var h := UI.hbox(12)
	p.add_child(h)
	var icon := ""
	var nm := ""
	var badges := []
	var sub := ""
	var sub_col := Color("#b6c8d2")
	if n.has("e"):
		var e: Dictionary = n.e
		var f := run.forecast(e)
		icon = GameData.foe_icon(e.n)
		nm = tr(e.n)
		sub = "%s · ~-%d HP" % [tr(f.tag), roundi(minf(run.hp, f.taken))]
		sub_col = f.color
		badges.append("❤️ %d · ⚔ %s" % [roundi(e.hp), GameData._num(e.atk)])
		if e.imm != "": badges.append("🛡 " + tr("resists %s") % (GameData.elem_icon(e.imm) + tr(e.imm)))
		if e.weak != "": badges.append("💥 " + tr("weak to %s") % (GameData.elem_icon(e.weak) + tr(e.weak)))
		if e.tr != "": badges.append(GameData.traits[e.tr].ic + " " + tr(GameData.traits[e.tr].n))
		badges.append(("🎁 " + tr("loot")) if n.k != "combat" else ("🎲 " + tr("25% loot")))
		if n.k in ["elite", "ambush"]:
			badges.append("🎒+1 · " + tr("lose: no gold"))
	else:
		icon = k[0]
		nm = tr({"forge": "Forge", "camp": "Campfire", "shrine": "Dark Shrine", "tailor": "Tailor"}[n.k])
		sub = tr({"forge": "+3 damage on a random weapon", "camp": "Recover 50% HP", "shrine": "Free Epic+ item · -15 HP", "tailor": "+3 pack tiles"}[n.k])
	h.add_child(UI.lbl(icon, 64 if boss else 52))
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var tg := UI.hbox(6)
	var tgp := UI.panel(c, c, 0, 99, 3)
	tgp.add_child(UI.lbl(k[0] + " " + tr(k[1]), 12, Color.WHITE, true))
	tg.add_child(tgp)
	tg.add_child(UI.lbl(nm, 18, Color.WHITE, true))
	v.add_child(tg)
	v.add_child(UI.lbl(sub, 15, sub_col, true))
	if not badges.is_empty():
		v.add_child(UI.wrap_lbl("  ·  ".join(badges), 13, Color("#cfe0e8")))
	h.add_child(UI.btn(tr("GO") + " ▶", func(): _choose(i), true, 18))
	if n.k in ["elite", "boss", "ambush"]:
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "self_modulate", Color(1.25, 1.25, 1.25), 0.8)
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
	var o := _overlay(tr("NIGHT"))
	var v: VBoxContainer = o[1]
	var r := run.result
	for l in r.lines:
		var fusion: bool = l.begins_with("✨")
		var line := UI.wrap_lbl(l, 17, UI.GOLD if fusion else UI.TX)
		if fusion:
			var fp := UI.panel(Color(UI.GOLD, 0.15), UI.GOLD, 2, 10, 10)
			fp.add_child(line)
			v.add_child(fp)
			fp.modulate.a = 0
			fp.create_tween().tween_property(fp, "modulate:a", 1.0, 0.6)
		else:
			v.add_child(line)
	var cs: CombatSim = r.cs
	if cs != null:
		var tp := UI.panel(UI.PN, UI.BD, 1, 12, 12)
		var g := GridContainer.new()
		g.columns = 4
		g.add_theme_constant_override("h_separation", 18)
		tp.add_child(g)
		for hd in ["Item", "Damage", "Heal/Shield", "Triggers"]:
			g.add_child(UI.lbl(tr(hd), 14, UI.MU, true))
		var rows := cs.items.duplicate()
		rows.sort_custom(func(a, b): return a.st.dmg > b.st.dmg)
		for x in rows:
			var nl := UI.lbl(x.d.ic + " " + tr(x.d.n), 14)
			nl.clip_text = true
			nl.custom_minimum_size.x = 220
			g.add_child(nl)
			g.add_child(UI.lbl(str(roundi(x.st.dmg)), 14))
			g.add_child(UI.lbl(str(roundi(x.st.heal + x.st.shield)), 14))
			g.add_child(UI.lbl(str(x.st.hits), 14))
		v.add_child(tp)
		var extra := []
		for k in cs.stat_dmg:
			if cs.stat_dmg[k] > 0:
				extra.append("%s %d" % [GameData.statuses[k].ic, roundi(cs.stat_dmg[k])])
		extra.append(tr("Blocked %d") % roundi(cs.blocked))
		extra.append(tr("Ultimates %d") % cs.ults)
		extra.append("%.1fs" % (cs.tk / 10.0))
		v.add_child(UI.wrap_lbl(" · ".join(extra), 14, UI.MU))
	var label := tr("See result") if r.over else tr("Claim victory") if r.victory else tr("Next day") + " ▶"
	v.add_child(_center(UI.btn(label, func():
		run.next_day()
		_clear_sel()
		render(), true, 20)))
	return o[0]


func _book_overlay() -> Control:
	var o := _overlay(tr("RECIPE BOOK"))
	var v: VBoxContainer = o[1]
	v.add_child(UI.wrap_lbl(tr("Place the two parts so they touch. They fuse at night. Two copies of the same item evolve into something new."), 15, Color("#cfe0e8")))
	v.add_child(UI.lbl("✨ " + tr("Evolutions"), 18, UI.GOLD, true))
	for r in GameData.recipes:
		if r.evo and run.in_class_pool(r.a):
			v.add_child(_recipe_row(r))
	v.add_child(UI.lbl("🔗 " + tr("Recipes"), 18, UI.GOLD, true))
	for r in GameData.recipes:
		if not r.evo and run.in_class_pool(r.r) and (r.path == "" or run.path == "" or r.path == run.path):
			v.add_child(_recipe_row(r))
	v.add_child(_center(UI.btn(tr("Close"), func():
		show_book = false
		render(), true, 18)))
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
			if selected == it and it.loc == "grid" and run.phase == "morning":
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
	ghost.setup(drag_item.id, drag_item.rot, grid.cell if grid else CELL, true)
	ghost.visible = true
	if sell_zone and sell_lbl:
		if drag_src == "shop":
			sell_lbl.text = "🛒 " + tr("Shop")
		elif drag_item.starter:
			sell_lbl.text = "🛒 " + tr("Starter items can't be sold")
		else:
			sell_lbl.text = "🛒 " + tr("Drop here to sell: +%d🪙") % run.sell_price(drag_item)
			sell_zone.self_modulate = Color(1.5, 1.25, 0.8)
	if storage_panel and drag_src != "storage":
		storage_panel.self_modulate = Color(1.2, 1.4, 1.5)
	_update_drag(get_global_mouse_position())


func _update_drag(pos: Vector2) -> void:
	if grid and grid.get_global_rect().has_point(pos):
		hover_cell = grid.cell_at(pos)
	else:
		hover_cell = Vector2i(-1, -1)
	var m := GameData.mid_cell(drag_item.id, drag_item.rot)
	var k := get_viewport().get_canvas_transform()
	ghost.position = k * pos - ghost.origin_offset - (Vector2(m) + Vector2(0.5, 0.5)) * ghost.cell
	ghost.tint = Color(1, 1, 1, 0.55 if hover_cell.x >= 0 else 0.9)
	ghost.queue_redraw()
	if held_lbl:
		held_lbl.text = _held_text()


func _rotate(d: int) -> void:
	if run == null or run.phase != "morning":
		return
	if drag_item != null:
		drag_item.rot = (drag_item.rot + d + 4) % 4
		ghost.set_rot(drag_item.rot)
		_update_drag(get_global_mouse_position())
		return
	if selected == null or not run.items.has(selected):
		return
	var it := selected
	var nr := (it.rot + d + 4) % 4
	if it.loc == "grid":
		var mid_world := Vector2i(it.x, it.y) + GameData.mid_cell(it.id, it.rot)
		var a := mid_world - GameData.mid_cell(it.id, nr)
		if run.fits(it, a.x, a.y, nr, it):
			it.rot = nr
			it.x = a.x
			it.y = a.y
			run.msg = ""
		else:
			run.msg = tr("No room to rotate it here — drag it somewhere with more space.")
	else:
		it.rot = nr
	render()


func _drop(pos: Vector2) -> void:
	var it := drag_item
	var done := false
	if grid and grid.get_global_rect().has_point(pos):
		var a := run.anchor_for(it, grid.cell_at(pos))
		if run.fits(it, a.x, a.y):
			if drag_src != "shop" or _pay_shop():
				it.loc = "grid"
				it.x = a.x
				it.y = a.y
				run.msg = ""
				done = true
		else:
			run.msg = tr("Does not fit there.")
	elif storage_panel and storage_panel.get_global_rect().has_point(pos):
		if drag_src != "shop" or _pay_shop():
			it.loc = "storage"
			run.msg = ""
			done = true
	elif sell_zone and sell_zone.get_global_rect().has_point(pos) and drag_src != "shop":
		if it.starter:
			run.msg = tr("Starter items can't be sold.")
		else:
			var g := run.sell_price(it)
			it.loc = drag_orig.loc
			run.sell(it)
			run.msg = tr("Sold %s for %d🪙.") % [tr(it.def().n), g]
			_clear_sel()
			done = true
	if not done:
		_cancel_drag()
	_end_drag()
	if done and drag_src != "shop" and selected == it and it.loc != "grid":
		_clear_sel()
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
	pending = {}


# =============================================================== dev: screenshots

func _autoshot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			I18n.set_lang(a.trim_prefix("--lang="))
			render()
	await _shot(dir + "/01_title.png")
	run = RunState.new(sel_cls)
	run.gold = 40
	for id in ["flame_saber", "bellows", "ash_plate", "health_potion", "smith_hammer"]:
		run.items.append(run.make_item(id, "storage"))
	render()
	await _shot(dir + "/02_morning.png")
	# inspect a shop card
	inspect_id = run.shop[0].id
	inspect_idx = 0
	render()
	await _shot(dir + "/03_inspect_shop.png")
	# inspect an owned item
	_clear_sel()
	selected = run.grid_items()[0]
	render()
	await _shot(dir + "/04_inspect_owned.png")
	_clear_sel()
	render()
	# simulate dragging the first shop card into the pack
	await get_tree().process_frame
	var gr := grid.get_global_rect()
	_press({"src": "shop", "idx": 0, "id": run.shop[0].id})
	_begin_drag()
	_update_drag(gr.position + Vector2(CELL * 3.5, CELL * 2.5))
	await _shot(dir + "/05_dragging.png")
	_cancel_drag()
	_end_drag()
	show_book = true
	render()
	await _shot(dir + "/06_book.png")
	show_book = false
	run.day = GameData.path_day
	render()
	await _shot(dir + "/07_path_choice.png")
	run.choose_path(run.cls_def().paths[0])
	# fill the pack so the fight screen has something to show
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
	await _shot(dir + "/08_road.png")
	_choose(0)
	await get_tree().create_timer(3.5).timeout
	await _shot(dir + "/09_combat.png")
	if _pending_sim != null:
		_pending_sim.skip_to_end()
		_on_combat_done(_pending_sim.won)
	await _shot(dir + "/10_night.png")
	get_tree().quit()


func _shot(path: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
