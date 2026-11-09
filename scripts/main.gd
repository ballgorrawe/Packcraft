extends Control
## Screen manager + drag-and-drop controller for PackCraft.
## Screens are rebuilt in code from RunState on every change (like a render() call).

const CELL := 46.0
const DRAG_THRESHOLD := 10.0

var run: RunState
var sel_cls := ""
var sel_pet := ""
var title_step := 0
var show_how := false

# drag / selection
var drag_item: PItem = null
var drag_src := ""
var drag_shop_idx := -1
var drag_orig := {}
var pending := {}            # press waiting to become a tap or a drag
var press_pos := Vector2.ZERO
var hover_cell := Vector2i(-1, -1)
var selected: PItem = null
var inspect_id := ""
var inspect_rot := 0

# widgets of the current screen
var screen: Control
var grid: BackpackGrid
var storage_panel: Control
var sell_zone: Control
var sell_lbl: Label
var held_lbl: Label
var inspector: PanelContainer
var ghost: ShapeView
var ghost_layer: CanvasLayer


func _ready() -> void:
	GameData.ensure_loaded()
	theme = UI.build_theme()
	sel_cls = GameData.class_keys[0]
	sel_pet = GameData.classes[sel_cls].pets[0]
	ghost_layer = CanvasLayer.new()
	ghost_layer.layer = 50
	add_child(ghost_layer)
	ghost = ShapeView.new()
	ghost.visible = false
	ghost_layer.add_child(ghost)
	_apply_ui_scale(SaveGame.get_setting("ui_scale", 1.2 if OS.has_feature("mobile") else 1.0))
	get_tree().auto_accept_quit = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_dev = true
	render()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoshot="):
			_autoshot(a.trim_prefix("--autoshot="))


var _dev := false   # screenshot/dev mode never touches the real save
var ui_scale := 1.0


func _apply_ui_scale(s: float) -> void:
	ui_scale = s
	get_window().content_scale_factor = s


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
	selected = null
	inspect_id = ""
	_pending_sim = run.resume_combat() if run.phase == "evening" else null
	if run.phase == "evening" and _pending_sim == null:
		run.phase = "afternoon"
	render()


## Safe-area margins (notches / rounded corners) converted to canvas units.
func _safe_margins() -> Vector4:
	var m := Vector4(10, 10, 10, 10)
	if not OS.has_feature("mobile"):
		return m
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var vis := get_viewport_rect().size
	if win.x <= 0 or vis.x <= 0:
		return m
	var k := vis.x / win.x
	m.x = maxf(10, safe.position.x * k)
	m.y = maxf(10, safe.position.y * k)
	m.z = maxf(10, (win.x - safe.end.x) * k)
	m.w = maxf(10, (win.y - safe.end.y) * k)
	return m


# =============================================================== render

func render() -> void:
	if screen:
		screen.queue_free()
	grid = null
	storage_panel = null
	sell_zone = null
	inspector = null
	held_lbl = null
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
	elif run.end_state != "":
		m.add_child(_end_screen())
	else:
		m.add_child(_run_screen())
		if run.phase == "afternoon":
			screen.add_child(_path_overlay())


func _center_card() -> Array:
	var cc := CenterContainer.new()
	var p := UI.panel(Color("#14232f"), Color.BLACK, 2, 16, 24)
	p.custom_minimum_size = Vector2(760, 0)
	cc.add_child(p)
	var v := UI.vbox(10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	return [cc, v]


func _centered(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return c


func _logo(text: String, size := 54) -> Label:
	var l := UI.lbl(text, size, Color("#ffb43a"), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color("#3a1600"))
	l.add_theme_constant_override("outline_size", 12)
	return l


# --------------------------------------------------------------- title

func _title_screen() -> Control:
	var cv := _center_card()
	var v: VBoxContainer = cv[1]
	var c: Dictionary = GameData.classes[sel_cls]
	if title_step == 0:
		v.add_child(_logo("PACKCRAFT"))
		var tag := UI.lbl("Pure strategy · Deep crafting · Zero pay-to-win", 14, Color("#9fb7c4"))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tag)
		var summary := "" if _dev else SaveGame.run_summary()
		if summary != "":
			var cb := UI.btn("▶ CONTINUE  —  " + summary, _continue_run, true, 17)
			v.add_child(_centered(cb))
			var nl := UI.lbl("Starting a new run replaces this save.", 12, UI.MU)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(nl)
		var h := UI.lbl("Choose your hero", 16, Color("#cfe0e8"), true)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(h)
		var row := UI.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for k in GameData.class_keys:
			var kk: String = k
			var x: Dictionary = GameData.classes[k]
			row.add_child(_pick_card(x.ic, x.n, x.d, k == sel_cls, func():
				sel_cls = kk
				sel_pet = GameData.classes[kk].pets[0]
				render()))
		v.add_child(row)
		var info := UI.panel(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 12, 10)
		var iv := UI.vbox(6)
		info.add_child(iv)
		var t1 := UI.lbl("%s %s — Bag: %s" % [c.ic, c.n, c.bag.label], 14, Color("#cfe0e8"))
		t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		iv.add_child(t1)
		var chips := UI.flow(4)
		chips.alignment = FlowContainer.ALIGNMENT_CENTER
		chips.add_child(UI.lbl("Starter", 13, UI.MU))
		chips.add_child(UI.item_chip(c.st[0]))
		chips.add_child(UI.lbl("  Class items", 13, UI.MU))
		for id in GameData.items:
			if GameData.items[id].cl == sel_cls and GameData.items[id].shop:
				chips.add_child(UI.item_chip(id))
		iv.add_child(chips)
		v.add_child(info)
		v.add_child(_centered(UI.btn("NEXT ▶", func():
			title_step = 1
			render(), true, 18)))
		var opts := UI.hbox(8)
		opts.alignment = BoxContainer.ALIGNMENT_CENTER
		opts.add_child(UI.btn("How to play " + ("▲" if show_how else "▼"), func():
			show_how = not show_how
			render()))
		opts.add_child(UI.lbl("   Text size", 13, UI.MU))
		for pair in [["S", 1.0], ["M", 1.2], ["L", 1.4]]:
			var s: float = pair[1]
			var b := UI.btn(pair[0], func():
				_apply_ui_scale(s)
				SaveGame.set_setting("ui_scale", s)
				render(), is_equal_approx(ui_scale, s), 13)
			opts.add_child(b)
		v.add_child(opts)
		if show_how:
			v.add_child(UI.wrap_lbl("1. Morning: buy gear and drag it into your backpack. Rotate with R / Q, right-click, or a second finger while dragging. Tap a placed item twice to rotate it in place.\n2. ✦ star slots buff neighbours. Recipe items placed side by side form a Golden Link and fuse at night.\n3. Afternoon: pick a fight or event. Evening: the auto-battle plays out.\n4. 25% of every enemy hit pierces your block. HP carries over between fights: rest at Campfires and save potions. Hearts are 3 extra lives: at 0 HP you spend one and revive at 50% HP.\n5. Survive 15 days and beat the Stone Titan.", 13, Color("#cfe0e8")))
	else:
		var big := UI.lbl(c.ic, 84)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(big)
		var nm := UI.lbl(c.n, 18, UI.GOLD, true)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nm)
		var h := UI.lbl("Choose your companion", 16, Color("#cfe0e8"), true)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(h)
		var row := UI.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for p in c.pets:
			var pp: String = p
			var d: Dictionary = GameData.pets[p]
			row.add_child(_pick_card(d.ic, d.n, d.d, p == sel_pet, func():
				sel_pet = pp
				render(), 190))
		v.add_child(row)
		var act := UI.hbox(10)
		act.alignment = BoxContainer.ALIGNMENT_CENTER
		act.add_child(UI.btn("◀ Back", func():
			title_step = 0
			render()))
		act.add_child(UI.btn("START RUN ▶", func():
			run = RunState.new(sel_cls, sel_pet)
			selected = null
			inspect_id = ""
			render(), true, 18))
		v.add_child(act)
	return cv[0]


func _pick_card(icon: String, name: String, desc: String, on: bool, cb: Callable, w := 132) -> Control:
	var p := UI.panel(Color(UI.GOLD, 0.14) if on else Color(1, 1, 1, 0.05), UI.GOLD if on else Color(1, 1, 1, 0.2), 2, 12, 8)
	p.custom_minimum_size = Vector2(w, 150)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			cb.call())
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var i := UI.lbl(icon, 40)
	i.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(i)
	var n := UI.wrap_lbl(name, 14, Color.WHITE)
	n.add_theme_font_override("font", UI.bold)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var d := UI.wrap_lbl(desc, 12, Color("#b6c8d2"))
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)
	return p


func _end_screen() -> Control:
	var cv := _center_card()
	var v: VBoxContainer = cv[1]
	var w := run.end_state == "win"
	v.add_child(_logo("VICTORY" if w else "DEFEATED", 40))
	var i := UI.lbl("🏆" if w else "💀", 84)
	i.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(i)
	var t := UI.lbl("The Stone Titan falls. Your build held." if w else "You fell on day %d of %d." % [run.day, GameData.days], 16)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.lbl("🪙 %d gold · %d items collected" % [run.gold, run.items.size()], 14, Color("#9fb7c4"))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(_centered(UI.btn("PLAY AGAIN ▶", func():
		run = null
		title_step = 0
		render(), true, 18)))
	return cv[0]


# --------------------------------------------------------------- run screen

func _run_screen() -> Control:
	run.sync_hp()
	var root := UI.vbox(6)
	root.add_child(_top_bar())
	root.add_child(_timeline())
	var body := UI.hbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# left: backpack, storage, inspector
	var ls := ScrollContainer.new()
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ls.custom_minimum_size.x = GameData.W * CELL + 40
	var left := UI.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(left)
	body.add_child(ls)

	var gp := UI.panel()
	var gv := UI.vbox(6)
	gp.add_child(gv)
	var gh := UI.hbox()
	gh.add_child(UI.lbl("🎒 Backpack", 16, UI.TX, true))
	var bl := UI.lbl("  gold tiles: " + run.cls_def().bag.label, 12, UI.MU)
	bl.clip_text = true
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gh.add_child(bl)
	gv.add_child(gh)
	grid = BackpackGrid.new().setup(self, CELL)
	grid.cell_pressed.connect(_on_grid_press)
	gv.add_child(grid)
	gv.add_child(UI.rich(_stats_text(), 13))
	held_lbl = UI.wrap_lbl(_held_text(), 13, UI.MU)
	gv.add_child(held_lbl)
	if run.msg != "":
		gv.add_child(UI.wrap_lbl(run.msg, 13, UI.AC))
	left.add_child(gp)

	var sp := UI.panel()
	storage_panel = sp
	var sv := UI.vbox(6)
	sp.add_child(sv)
	var st := run.storage_items()
	var sh := UI.hbox(8)
	var stl := UI.lbl("📦 Storage Box (%d) — inactive in combat, never fuses" % st.size(), 13, UI.MU)
	stl.clip_text = true
	stl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(stl)
	if run.phase == "morning" and not run.grid_items().is_empty():
		sh.add_child(UI.btn("⤓ Clear pack", func():
			if drag_item != null:
				return
			var n := run.clear_pack()
			selected = null
			run.msg = "Moved %d item%s from the pack into storage." % [n, "" if n == 1 else "s"]
			render(), false, 13))
	sv.add_child(sh)
	var sf := UI.flow(6)
	sf.custom_minimum_size.y = 40
	sv.add_child(sf)
	for it in st:
		sf.add_child(_storage_card(it))
	if st.is_empty():
		sf.add_child(UI.lbl("Empty. Drag an item here to store it.", 13, UI.MU))
	left.add_child(sp)

	inspector = UI.panel(UI.PN2)
	inspector.custom_minimum_size.y = 90
	left.add_child(inspector)
	_fill_inspector()

	# right: phase content
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := UI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(right)
	body.add_child(rs)
	match run.phase:
		"morning", "afternoon":
			_morning(right)
		"evening":
			pass
		"night":
			_night(right)
	if run.phase == "evening" and _pending_sim != null:
		var cvw := CombatView.new().setup(run, _pending_sim)
		cvw.finished.connect(_on_combat_done)
		right.add_child(cvw)
	return root


func _top_bar() -> Control:
	var p := UI.panel(UI.PN, UI.BD, 1, 8, 8)
	var h := UI.flow(10)
	p.add_child(h)
	h.add_child(UI.lbl("🎒 PackCraft", 16, UI.AC, true))
	h.add_child(_pill("Day %d/%d" % [run.day, GameData.days]))
	h.add_child(_pill("🪙 %d" % run.gold))
	h.add_child(_pill("Lives " + "❤️".repeat(run.res) + "🖤".repeat(RunState.MAX_HEARTS - run.res)))
	var hpbox := UI.hbox(4)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(110, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1
	var r := run.hp / run.mhp
	bar.value = r
	var col := UI.GOOD if r > 0.5 else Color("#f59e0b") if r > 0.25 else UI.BAD
	bar.add_theme_stylebox_override("fill", UI.box(col, col, 0, 3, 0))
	hpbox.add_child(bar)
	hpbox.add_child(UI.lbl("HP %d/%d" % [roundi(run.hp), roundi(run.mhp)], 14, UI.TX, true))
	hpbox.tooltip_text = "HP carries over between fights. Hearts are extra lives: at 0 HP you spend one and revive at 50% HP."
	h.add_child(hpbox)
	h.add_child(_pill(run.cls_def().ic + " " + run.cls_def().n))
	h.add_child(_pill(run.pet_def().ic + " " + run.pet_def().n))
	return p


func _pill(t: String) -> Control:
	var p := UI.panel(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 99, 4)
	p.add_child(UI.lbl(t, 14, UI.TX, true))
	return p


func _timeline() -> Control:
	var v := UI.vbox(3)
	var row := UI.hbox(3)
	for d in range(1, GameData.days + 1):
		var cur := d == run.day
		var boss := run.boss_on(d) != null
		var p := UI.panel(UI.AC if cur else Color(0, 0, 0, 0), UI.AC if cur else UI.BD, 1, 4, 2)
		p.custom_minimum_size = Vector2(28, 24)
		if d < run.day:
			p.modulate.a = 0.45
		var l := UI.lbl("💀" if boss else str(d), 11, UI.BG if cur else UI.MU, cur)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(l)
		row.add_child(p)
	row.add_child(UI.lbl("   ", 10))
	for ph in ["morning", "afternoon", "evening", "night"]:
		var on: bool = ph == run.phase
		var pp := UI.panel(UI.TX if on else Color(0, 0, 0, 0), UI.TX if on else UI.BD, 1, 99, 3)
		pp.add_child(UI.lbl(" " + ph.capitalize() + " ", 12, UI.BG if on else UI.MU, on))
		row.add_child(pp)
	v.add_child(row)
	var warn := []
	for b in GameData.bosses:
		if b.d >= run.day and b.d - run.day <= 5:
			warn.append("⚠️ Day %d: %s (resists %s, weak %s)" % [b.d, b.n, b.imm, b.weak])
	var w2 := "Modifier — %s: %s" % [run.mod.n, run.mod.d]
	if not run.hz.is_empty():
		w2 += "   ·   %s Today: %s — %s" % [run.hz.ic, run.hz.n, run.hz.d]
	if not warn.is_empty():
		v.add_child(UI.lbl(" · ".join(warn), 12, UI.AC))
	v.add_child(UI.lbl(w2, 12, UI.MU))
	return v


func _stats_text() -> String:
	run.calc()
	var by := {}
	var bl := 0.0
	var hl := 0.0
	var n := 0
	for i in run.grid_items():
		var d: Dictionary = i.def()
		var f := run.eff(i)
		n += GameData.shape(i.id, i.rot).c.size()
		if d.type == "atk":
			by[d.dt] = by.get(d.dt, 0.0) + f.dmg / f.cd
		elif d.type == "def":
			bl += f.blk / f.cd
		elif d.type == "heal":
			hl += d.heal
	var t := 0.0
	var parts := []
	for k in by:
		t += by[k]
		parts.append(GameData.elem_icons[k] + "%.1f" % by[k])
	var s := "DPS [b]%.1f[/b] %s · Block [b]%.1f[/b]/s · Heal %d · Tiles %d/%d · Max HP %d" % [t, " ".join(parts), bl, roundi(hl), n, run.tiles.size(), roundi(run.mhp)]
	var rg := run.regen()
	if rg > 0:
		s += " · Regen %.1f/s" % rg
	return s


func _held_text() -> String:
	if drag_item != null:
		var t := "Holding %s %s — R/Q, right-click or a 2nd finger rotates. Drop on the pack, storage, or the shop to sell." % [drag_item.def().ic, drag_item.def().n]
		if hover_cell.x >= 0:
			var a := run.anchor_for(drag_item, hover_cell)
			var pr := run.preview(drag_item, a.x, a.y)
			if pr.ok:
				t += "\nIf placed here: DPS %+.1f · Block %+.1f%s" % [pr.d.x, pr.d.y, " · ✨ forms a Golden Link" if pr.lk else ""]
			else:
				t += "\nDoes not fit here."
		return t
	if run.phase != "morning":
		return "The market is closed. Tap items to inspect them."
	if run.expand > 0:
		return "Bag expansion: tap %d glowing tile(s) next to your pack." % run.expand
	return "Drag items to move them. Tap to inspect, tap again to rotate in place."


## Storage card: the item's real shape (so you can see what fits), icon, name and tier.
func _storage_card(it: PItem) -> Control:
	var d := it.def()
	var c: Color = GameData.tier_colors[d.tier]
	var p := UI.panel(c.darkened(0.6), Color.WHITE if selected == it else c, 2, 8, 5)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.tooltip_text = GameData.describe(it.id)
	p.custom_minimum_size.x = 92
	var v := UI.vbox(3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var top := UI.hbox(6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.custom_minimum_size.y = 46
	var ic := UI.lbl(d.ic, 26)
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(ic)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(ShapeView.new().setup(it.id, 0, 12, false, false))
	top.add_child(cc)
	v.add_child(top)
	var nm := UI.lbl(d.n, 12, UI.TX, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.custom_minimum_size.x = 82
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var tl := UI.lbl(GameData.tier_names[d.tier] + (" · 🔗" if run.recipe_partner_owned(it.id) else ""), 11, c.lightened(0.3))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tl)
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_press({"item": it, "src": "storage"}))
	return p


# --------------------------------------------------------------- inspector

func _fill_inspector() -> void:
	if inspector == null:
		return
	for c in inspector.get_children():
		c.queue_free()
	var id := inspect_id
	var rot := inspect_rot
	if drag_item != null:
		id = drag_item.id
		rot = drag_item.rot
	elif selected != null and run.items.has(selected):
		id = selected.id
		rot = selected.rot
	if id == "":
		inspector.add_child(UI.wrap_lbl("Tap an item to inspect it: shape, ✦ star slots, recipes and sets.", 13, UI.MU))
		return
	var d: Dictionary = GameData.items[id]
	var h := UI.hbox(10)
	inspector.add_child(h)
	var sv := ShapeView.new().setup(id, rot, 18, true, false)
	sv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(sv)
	var v := UI.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var col: Color = GameData.tier_colors[d.tier]
	v.add_child(UI.rich("[b]%s %s[/b]  [color=#%s]%s[/color]" % [d.ic, d.n, col.to_html(false), GameData.tier_names[d.tier]], 15))
	v.add_child(UI.wrap_lbl(GameData.describe(id), 13))
	var extra := " · ".join(d.tags)
	var seen_st := []
	for s in d.st:
		var tx := GameData.stat_text(s.tag, s.key, s.val)
		if not seen_st.has(tx):
			seen_st.append(tx)
	if not seen_st.is_empty():
		extra += "\n✦ neighbours: " + ", ".join(seen_st)
	if d.hp > 0:
		extra += "\n❤️ +%s max HP%s" % [GameData._num(d.hp), (", regen %s/s" % GameData._num(d.rg)) if d.rg > 0 else ""]
	if d.ls > 0:
		extra += "\n🩸 heals %d%% of its damage" % roundi(d.ls * 100)
	v.add_child(UI.wrap_lbl(extra, 12, UI.MU))
	for r in GameData.recipes:
		if r.has(id):
			v.add_child(_recipe_row(r))
	for s in GameData.sets:
		if s.parts.has(id):
			var ok: bool = run.set_inst(s).ok
			v.add_child(UI.wrap_lbl("%s %s: %s — %s" % ["✅" if ok else "◻", s.n, " + ".join(s.parts.map(func(p): return GameData.items[p].ic)), s.txt], 12, UI.GOOD if ok else UI.MU))
	# actions for an owned, selected item
	if drag_item == null and selected != null and run.items.has(selected) and run.phase == "morning":
		var a := UI.hbox(8)
		a.add_child(UI.btn("Rotate ↻", func(): _rotate(1), true))
		if selected.loc == "grid":
			a.add_child(UI.btn("Store 📦", _store_selected))
		var sb := UI.btn("Sell 🪙 +%d" % ceili(d.cost / 2.0), _sell_selected)
		sb.disabled = selected.starter
		a.add_child(sb)
		v.add_child(a)


func _recipe_row(r: Array) -> Control:
	var h := UI.hbox(4)
	h.add_child(UI.item_chip(r[0], run.owns(r[0])))
	h.add_child(UI.lbl("+", 14, UI.MU, true))
	h.add_child(UI.item_chip(r[1], run.owns(r[1])))
	h.add_child(UI.lbl("➜", 14, UI.MU, true))
	if run.seen.has(r[2]) or (run.seen.has(r[0]) and run.seen.has(r[1])):
		h.add_child(UI.item_chip(r[2], run.owns(r[2])))
		h.add_child(UI.lbl(GameData.items[r[2]].n, 13, UI.MU))
	else:
		h.add_child(UI.unknown_chip())
		h.add_child(UI.lbl("???", 13, UI.MU))
	return h


# --------------------------------------------------------------- morning

func _morning(right: VBoxContainer) -> void:
	var shop := UI.panel(Color("#1f3236"), UI.AC.darkened(0.3), 2, 10, 12)
	sell_zone = shop
	var v := UI.vbox(10)
	shop.add_child(v)
	var head := UI.hbox(10)
	var mer := UI.panel(Color(UI.AC, 0.2), UI.AC, 2, 26, 6)
	mer.add_child(UI.lbl("🧔", 28))
	head.add_child(mer)
	var hv := UI.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_lbl = UI.lbl("Merchant’s Stall", 16, UI.TX, true)
	hv.add_child(sell_lbl)
	hv.add_child(UI.lbl("Rank %d · today’s drop odds" % (run.rank() + 1), 12, UI.MU))
	var odds := UI.hbox(0)
	odds.custom_minimum_size.y = 8
	var w: Array = GameData.rarity_table[run.rank()]
	for t in w.size():
		if w[t] > 0:
			var cr := ColorRect.new()
			cr.color = GameData.tier_colors[t]
			cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cr.size_flags_stretch_ratio = w[t]
			cr.tooltip_text = "%s %d%%" % [GameData.tier_names[t], roundi(w[t])]
			odds.add_child(cr)
	hv.add_child(odds)
	head.add_child(hv)
	var gold := UI.panel(Color(UI.AC, 0.2), UI.AC, 2, 99, 6)
	gold.add_child(UI.lbl("🪙 %d" % run.gold, 17, UI.TX, true))
	gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(gold)
	v.add_child(head)
	var cards := UI.flow(10)
	for i in run.shop.size():
		var e: Dictionary = run.shop[i]
		cards.add_child(_bag_card(e, i) if e.has("bag") else _shop_card(e, i))
	v.add_child(cards)
	var act := UI.hbox(8)
	act.add_child(UI.btn("🎲 Reroll · %dg" % run.reroll_cost(), func():
		run.reroll()
		render()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(sp)
	act.add_child(UI.btn("Depart ▶", func():
		if run.travel():
			selected = null
		render(), true, 17))
	v.add_child(act)
	right.add_child(shop)

	# Golden Links
	var lp := UI.panel()
	var lv := UI.vbox(4)
	lp.add_child(lv)
	lv.add_child(UI.lbl("🔗 Golden Links — fuse at night", 15, UI.TX, true))
	var ls := run.links()
	if ls.is_empty():
		lv.add_child(UI.wrap_lbl("No links yet. Place recipe items side by side and they fuse at night.", 13, UI.MU))
	for l in ls:
		var row := UI.hbox(4)
		row.add_child(UI.item_chip(l.a.id, true))
		row.add_child(UI.lbl("+", 14, UI.MU, true))
		row.add_child(UI.item_chip(l.b.id, true))
		row.add_child(UI.lbl("➜", 14, UI.MU, true))
		row.add_child(UI.item_chip(l.r))
		row.add_child(UI.lbl(GameData.items[l.r].n, 13))
		if run.fuse_place(l) == null:
			row.add_child(UI.lbl("⚠ no room: goes to storage", 12, UI.BAD))
		var key: String = l.key
		var isoff := run.off.has(key)
		var tb := UI.btn("OFF" if isoff else "ON", func():
			if run.off.has(key):
				run.off.erase(key)
			else:
				run.off[key] = true
			render(), not isoff)
		row.add_child(tb)
		lv.add_child(row)
	right.add_child(lp)

	# Sets
	var setp := UI.panel()
	var setv := UI.vbox(4)
	setp.add_child(setv)
	setv.add_child(UI.lbl("🧩 Set Bonuses — parts must touch", 15, UI.TX, true))
	for s in GameData.sets:
		if not s.parts.all(func(p): return run.in_class_pool(p)):
			continue
		var row := UI.hbox(4)
		for j in s.parts.size():
			if j > 0:
				row.add_child(UI.lbl("+", 14, UI.MU, true))
			row.add_child(UI.item_chip(s.parts[j], run.owns(s.parts[j])))
		var ok: bool = run.set_inst(s).ok
		var t := UI.wrap_lbl("%s: %s%s" % [s.n, s.txt, "  ACTIVE" if ok else ""], 12, UI.GOOD if ok else UI.MU)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		setv.add_child(row)
	right.add_child(setp)

	# Recipe book
	var rp := UI.panel()
	var rv := UI.vbox(4)
	rp.add_child(rv)
	rv.add_child(UI.lbl("📖 Recipe Book — ??? until you own both parts", 15, UI.TX, true))
	for r in GameData.recipes:
		if r.all(func(id): return run.in_class_pool(id)):
			rv.add_child(_recipe_row(r))
	right.add_child(rp)

	# Encounters forecast
	var ep := UI.panel()
	var ev := UI.vbox(4)
	ep.add_child(ev)
	ev.add_child(UI.lbl("Today’s encounters (forecast is a rough estimate)", 15, UI.TX, true))
	for n in run.nodes:
		var t := _node_line(n)
		if n.has("e"):
			var f := run.forecast(n.e)
			t += "  [color=#%s][b][%s · %s][/b][/color]" % [f.color.to_html(false), f.tag, ("~%ds" % roundi(f.T)) if f.T < 40 else "you deal no damage"]
		ev.add_child(UI.rich(t, 13))
	right.add_child(ep)


func _node_line(n: Dictionary) -> String:
	var e: Dictionary = n.get("e", {})
	var im: String = (" · resists " + e.imm + " (−80%)") if e.get("imm", "") != "" else ""
	match n.k:
		"combat": return "⚔️ %s — %d HP, %s dmg%s" % [e.n, roundi(e.hp), GameData._num(e.atk), im]
		"elite": return "👹 %s — %d HP, %s dmg%s. Win: double gold and a Rare+ item. Lose: no gold." % [e.n, roundi(e.hp), GameData._num(e.atk), im]
		"boss": return "💀 BOSS %s — %d HP, %s dmg · resists %s (−80%%), weak to %s" % [e.n, roundi(e.hp), GameData._num(e.atk), e.imm, e.weak]
		"ambush": return "⚠️ Ambush! %s strikes: a tough fight, double gold and a Rare+ item. Lose: no gold." % e.n
		"shrine": return "🗿 Dark Shrine: a free Epic+ item, but you lose 15 HP"
		"tailor": return "🧵 Tailor: your pack grows by 3 tiles"
		"forge": return "🔨 Forge — +3 damage on a random weapon in your pack"
	return "🔥 Campfire — recover 50% HP (or −5% cooldown if at full HP)"


func _shop_card(e: Dictionary, i: int) -> Control:
	var d: Dictionary = GameData.items[e.id]
	var col: Color = GameData.tier_colors[d.tier]
	var p := UI.panel(col.darkened(0.62), col, 2, 12, 8)
	p.custom_minimum_size = Vector2(136, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.tooltip_text = GameData.describe(e.id)
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_press({"src": "shop", "idx": i, "id": e.id}))
	var v := UI.vbox(3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var top := UI.hbox(2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if e.get("sale", false):
		top.add_child(UI.lbl("50% OFF", 11, Color("#ff7b7f"), true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var lk := UI.btn("🔒" if e.get("lock", false) else "🔓", func():
		run.toggle_lock(i)
		render(), false, 12)
	lk.tooltip_text = "Lock: keep this item on the shelf for tomorrow"
	top.add_child(lk)
	v.add_child(top)
	var ic := UI.lbl(d.ic, 30)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ic)
	var nm := UI.lbl(d.n, 13, UI.TX, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var tr := UI.lbl(GameData.tier_names[d.tier], 11, col.lightened(0.2), true)
	tr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tr)
	var sv := ShapeView.new().setup(e.id, 0, 10, true, false)
	sv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(sv)
	var stt := ""
	match d.type:
		"atk": stt = "⚔ %s  ⏱ %ss" % [GameData._num(d.dmg), GameData._num(d.cd)]
		"def": stt = "🛡 %s  ⏱ %ss" % [GameData._num(d.blk), GameData._num(d.cd)]
		"heal": stt = "💚 %s" % GameData._num(d.heal)
		_: stt = "✦ aura"
	if not d.fx.is_empty():
		stt += "  " + GameData.fx_icons(d.fx)
	var sl := UI.lbl(stt, 12)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sl)
	if run.recipe_partner_owned(e.id):
		var pl := UI.lbl("🔗 recipe partner", 11, Color("#d49b00"), true)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(pl)
	var b := UI.btn("🪙 %d" % e.price, func(): _buy_tap(i), true)
	if run.gold < e.price:
		b.modulate = Color(0.6, 0.6, 0.6)
	v.add_child(b)
	return p


func _bag_card(e: Dictionary, i: int) -> Control:
	var p := UI.panel(Color("#2a3a3e"), Color("#8b9aa0"), 2, 12, 8)
	p.custom_minimum_size = Vector2(136, 0)
	var v := UI.vbox(4)
	p.add_child(v)
	var ic := UI.lbl("🎒", 30)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ic)
	var nm := UI.lbl("Large Bag" if e.n == 4 else "Bag Piece", 13, UI.TX, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var d := UI.lbl("Unlock %d more tiles" % e.n, 12, UI.MU)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var b := UI.btn("🪙 %d" % e.price, func():
		run.buy_bag(i)
		render(), true)
	if run.gold < e.price:
		b.modulate = Color(0.6, 0.6, 0.6)
	v.add_child(b)
	return p


func _buy_tap(i: int) -> void:
	if drag_item != null:
		return
	var it := run.buy_item(i)
	if it != null:
		it.loc = "storage"
		selected = it
		run.msg = "Bought %s %s — it's in storage. Drag it into your pack." % [it.def().ic, it.def().n]
	render()


# --------------------------------------------------------------- afternoon

func _path_overlay() -> Control:
	var ov := ColorRect.new()
	ov.color = Color(0.02, 0.05, 0.06, 0.88)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(cc)
	var v := UI.vbox(12)
	cc.add_child(v)
	var t := _logo("CHOOSE YOUR PATH", 30)
	v.add_child(t)
	var s := UI.lbl("Day %d · HP %d/%d · Hearts %d/%d" % [run.day, roundi(run.hp), roundi(run.mhp), run.res, RunState.MAX_HEARTS], 14, Color("#9fb7c4"))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in run.nodes.size():
		row.add_child(_path_card(run.nodes[i], i))
	v.add_child(row)
	return ov


const NK := {
	"combat": ["⚔️", "FIGHT", "#64748b"], "elite": ["👹", "ELITE", "#ef4444"], "boss": ["💀", "BOSS", "#a855f7"],
	"forge": ["🔨", "FORGE", "#f59e0b"], "camp": ["🏕️", "CAMPFIRE", "#22c55e"], "ambush": ["⚠️", "AMBUSH", "#f97316"],
	"shrine": ["🗿", "DARK SHRINE", "#7c3aed"], "tailor": ["🧵", "TAILOR", "#0ea5e9"],
}


func _path_card(n: Dictionary, i: int) -> Control:
	var k: Array = NK[n.k]
	var c := Color(k[2])
	var boss: bool = n.k == "boss"
	var p := UI.panel(c.darkened(0.7), c, 4 if boss else 3, 16, 12)
	p.custom_minimum_size = Vector2(230 if boss else 190, 0)
	var v := UI.vbox(6)
	p.add_child(v)
	var tg := UI.panel(c, c, 0, 99, 3)
	var tl := UI.lbl(k[0] + " " + k[1], 12, Color.WHITE, true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tg.add_child(tl)
	v.add_child(tg)
	var sp := ""
	var nm := ""
	var badges := []
	var sub: Control
	if n.has("e"):
		var e: Dictionary = n.e
		var f := run.forecast(e)
		var sk := 1 if f.tag == "Safe" else 2 if f.tag == "Risky" else 3
		sp = GameData.foe_icon(e.n)
		nm = e.n
		sub = UI.lbl("%s\n%s · ≈−%d HP" % ["💀".repeat(sk), f.tag, roundi(minf(run.hp, f.taken))], 14, f.color, true)
		if e.imm != "": badges.append("🛡 %s resist" % GameData.elem_icons[e.imm])
		if e.weak != "": badges.append("💥 weak %s" % GameData.elem_icons[e.weak])
		if e.tr != "": badges.append(GameData.traits[e.tr].ic + " " + GameData.traits[e.tr].n)
		if e.tier == "easy": badges.append("😴 easy")
		badges.append("🎁 loot" if n.k != "combat" else "🎲 25% loot")
	else:
		sp = k[0]
		nm = {"forge": "Forge", "camp": "Campfire", "shrine": "Dark Shrine", "tailor": "Tailor"}[n.k]
		sub = UI.lbl({"forge": "Sharpen a weapon", "camp": "Recover 50% HP", "shrine": "Free Epic+ item · −15 HP", "tailor": "+3 pack tiles"}[n.k], 13, Color("#b6c8d2"))
	var big := UI.lbl(sp, 88 if boss else 64)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	var nl := UI.wrap_lbl(nm, 15, Color.WHITE)
	nl.add_theme_font_override("font", UI.bold)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var bf := UI.flow(4)
	bf.alignment = FlowContainer.ALIGNMENT_CENTER
	for b in badges:
		var bp := UI.panel(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 99, 3)
		bp.add_child(UI.lbl(b, 11))
		bf.add_child(bp)
	v.add_child(bf)
	v.add_child(UI.btn("GO ▶", func(): _choose(i), true, 16))
	if n.k in ["elite", "boss", "ambush"]:
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "self_modulate", Color(1.25, 1.25, 1.25), 0.8)
		tw.tween_property(p, "self_modulate", Color.WHITE, 0.8)
	return p


var _pending_sim: CombatSim = null


func _choose(i: int) -> void:
	_pending_sim = run.choose(i)
	render()


func _on_combat_done(won: bool) -> void:
	var cs := _pending_sim
	_pending_sim = null
	run.go_night(cs.node, won, cs)
	selected = null
	render()


# --------------------------------------------------------------- night

func _night(right: VBoxContainer) -> void:
	var r := run.result
	var p := UI.panel()
	var v := UI.vbox(8)
	p.add_child(v)
	v.add_child(UI.lbl("🌙 Night — resolution", 17, UI.TX, true))
	for l in r.lines:
		var fusion: bool = l.begins_with("✨")
		var line := UI.wrap_lbl(l, 15, UI.GOLD if fusion else UI.TX)
		if fusion:
			var fp := UI.panel(Color(UI.GOLD, 0.15), UI.GOLD, 1, 6, 6)
			fp.add_child(line)
			v.add_child(fp)
			fp.modulate.a = 0
			fp.create_tween().tween_property(fp, "modulate:a", 1.0, 0.6)
		else:
			v.add_child(line)
	var cs: CombatSim = r.cs
	if cs != null:
		var g := GridContainer.new()
		g.columns = 4
		g.add_theme_constant_override("h_separation", 24)
		for hd in ["Item", "Damage", "Healed", "Triggers"]:
			g.add_child(UI.lbl(hd, 13, UI.MU, true))
		for x in cs.items:
			g.add_child(UI.lbl(x.d.ic + " " + x.d.n, 13))
			g.add_child(UI.lbl(str(roundi(x.st.dmg)), 13))
			g.add_child(UI.lbl(str(roundi(x.st.heal)), 13))
			g.add_child(UI.lbl(str(x.st.hits), 13))
		if run.pet_def().k == "dmg":
			g.add_child(UI.lbl(run.pet_def().ic + " " + run.pet_def().n, 13))
			g.add_child(UI.lbl(str(roundi(cs.pet_dmg)), 13))
			g.add_child(UI.lbl("0", 13))
			g.add_child(UI.lbl("", 13))
		v.add_child(g)
		v.add_child(UI.lbl("Burn %d · Poison %d · Damage blocked %d · Fight length %.1fs" % [roundi(cs.stat_dmg.burn), roundi(cs.stat_dmg.pois), roundi(cs.blocked), cs.tk / 10.0], 13, UI.MU))
	var label := "See result" if r.over else "Claim victory" if r.victory else "Next day ▶"
	v.add_child(UI.btn(label, func():
		run.next_day()
		selected = null
		render(), true, 17))
	right.add_child(p)


# =============================================================== input / drag

func _on_grid_press(cell: Vector2i) -> void:
	if drag_item != null:
		return
	var it: PItem = run.occ().get(cell)
	if run.phase != "morning":
		if it != null:
			selected = it
			_fill_inspector()
		return
	if it != null:
		_press({"item": it, "src": "grid"})
		return
	if run.can_unlock(cell):
		run.unlock(cell)
		render()
		return
	selected = null
	_fill_inspector()


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
					render()


func _tap() -> void:
	var p := pending
	match p.src:
		"shop":
			selected = null
			inspect_id = p.id
			inspect_rot = 0
			_fill_inspector()
		_:
			var it: PItem = p.item
			if selected == it and it.loc == "grid" and run.phase == "morning":
				_rotate(1)
				return
			selected = it
			inspect_id = it.id
			render()


func _begin_drag() -> void:
	if run.phase != "morning":
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
	ghost.setup(drag_item.id, drag_item.rot, grid.cell if grid else CELL, false, true)
	ghost.visible = true
	if sell_zone and drag_src != "shop":
		sell_lbl.text = "Drop here to sell for 🪙 %d" % ceili(drag_item.def().cost / 2.0) if not drag_item.starter else "Starter items can't be sold"
		sell_zone.self_modulate = Color(1.4, 1.2, 0.8)
	_fill_inspector()
	_update_drag(get_global_mouse_position())


func _update_drag(pos: Vector2) -> void:
	if grid and grid.get_global_rect().has_point(pos):
		hover_cell = grid.cell_at(pos)
	else:
		hover_cell = Vector2i(-1, -1)
	var m := GameData.mid_cell(drag_item.id, drag_item.rot)
	ghost.position = pos - ghost.origin_offset - (Vector2(m) + Vector2(0.5, 0.5)) * ghost.cell
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
		_fill_inspector()
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
			run.msg = "No room to rotate it here — drag it somewhere with more space."
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
			run.msg = "Does not fit there."
	elif storage_panel and storage_panel.get_global_rect().has_point(pos):
		if drag_src != "shop" or _pay_shop():
			it.loc = "storage"
			run.msg = ""
			done = true
	elif sell_zone and sell_zone.get_global_rect().has_point(pos) and drag_src != "shop":
		if it.starter:
			run.msg = "Starter items can't be sold."
		else:
			it.loc = drag_orig.loc
			run.sell(it)
			run.msg = "Sold %s for 🪙 %d." % [it.def().n, ceili(it.def().cost / 2.0)]
			selected = null
			done = true
	if not done:
		_cancel_drag()
	_end_drag()
	render()


func _pay_shop() -> bool:
	var e: Dictionary = run.shop[drag_shop_idx]
	if run.gold < e.price:
		run.msg = "Not enough gold."
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
		inspect_id = drag_item.id
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


func _store_selected() -> void:
	if selected == null:
		return
	selected.loc = "storage"
	render()


func _sell_selected() -> void:
	if selected == null or selected.starter:
		return
	var n: String = selected.def().n
	var g := ceili(selected.def().cost / 2.0)
	if run.sell(selected):
		run.msg = "Sold %s for 🪙 %d." % [n, g]
		selected = null
	render()


# =============================================================== dev: screenshots

func _autoshot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _shot(dir + "/01_title.png")
	run = RunState.new(sel_cls, sel_pet)
	run.gold = 30
	render()
	await _shot(dir + "/02_morning.png")
	# storage box with a mix of shapes and tiers (then put things back)
	var extra := []
	for id in ["iron_cuirass", "fire_gem", "phoenix_staff", "health_potion", "tower_shield", "dragon_heart", "eternal_winter"]:
		var it := run.make_item(id, "storage")
		run.items.append(it)
		extra.append(it)
	render()
	await _shot(dir + "/02b_storage.png")
	for it in extra:
		run.items.erase(it)
	render()
	# simulate dragging the first shop card into the pack
	await get_tree().process_frame
	var gr := grid.get_global_rect()
	_press({"src": "shop", "idx": 0, "id": run.shop[0].id})
	_begin_drag()
	_update_drag(gr.position + Vector2(CELL * 1.5, CELL * 1.5))
	await _shot(dir + "/03_dragging.png")
	_cancel_drag()
	_end_drag()
	run.travel()
	render()
	await _shot(dir + "/04_path.png")
	var idx := 0
	_choose(idx)
	await get_tree().create_timer(2.5).timeout
	await _shot(dir + "/05_combat.png")
	if _pending_sim != null:
		_pending_sim.skip_to_end()
		_on_combat_done(_pending_sim.won)
	await _shot(dir + "/06_night.png")
	get_tree().quit()


func _shot(path: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
