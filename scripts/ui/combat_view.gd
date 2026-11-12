class_name CombatView
extends PanelContainer
## Evening arena (portrait): steps the CombatSim in real time and animates its events.
## Top: the enemy. Middle: the stage. Then your HP, resource and Ultimate meter.
## Bottom: your pack, where every item shows its charge and flashes when it fires.

signal finished(won: bool)

var pcell := 60.0
var porg := Vector2i.ZERO   # top-left unlocked tile; the fight view shows only the unlocked area

var sim: CombatSim
var run: RunState
var speed := 1
var _acc := 0.0
var _end_wait := -1.0
var _t := 0.0

var php_bar: StatBar
var ehp_bar: StatBar
var hero_chips: HBoxContainer   # status chips under your HP: monster DoTs on you, Thorns, haste
var foe_chips: HBoxContainer    # status chips under the monster HP: your burn / poison on it
var _chips := {}                # "hero:key" / "foe:key" -> chip PanelContainer
var res_lbl: Label
var ult_bar: ProgressBar
var ult_lbl: Label
var stage: Control
var mpack: MiniPack
var world: Control
var pack: Control
var fxl: Control
var hero: Label
var foe: Label
var log_lbl: Label
var combo_lbl: Label
var _combo := 0
var _combo_t := 0.0
var _flash := {}        # uid -> seconds since it fired
var _xi := {}           # uid -> combat item dict
var _shake_tw: Tween
var _intro := 0.0        # seconds of boss entrance left (the fight waits)
var mech_box: PanelContainer    # boss move bar (bosses only)
var mech_lbl: Label
var mech_bar: ProgressBar
var _mech_was_warn := false
var _hero_hit_st := {}          # statuses a monster has put on you this fight (first-time callout)
var _ult_info: PanelContainer   # the Ultimate / resource explainer, while open
var _ult_info_lbl: RichTextLabel
var _wide := false
var _foe_info: Control          # the monster read-out while open (the fight is paused)


## wide: PC layout (your HP + pack on the left, the fight in the middle, the monster on the right).
func setup(r: RunState, s: CombatSim, wide := false) -> CombatView:
	var ks := 1.35 if wide else 1.0   # text / sprite scale on PC
	_wide = wide
	run = r
	sim = s
	for x in s.items:
		_xi[x.i.uid] = x
	add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0))
	var root := Control.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)
	var v := UI.vbox(6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(v)

	# enemy header
	var eh := UI.card(Color("#4a1a33"), Color("#ff4d5e"), 22, 12)
	var ev := UI.vbox(4)
	eh.add_child(ev)
	var en := UI.hbox(8)
	var tier_txt: String = "👺 " + tr("MINI-BOSS") if s.node.k == "mini" else {"boss": "💀 " + tr("BOSS"), "elite": "👹 " + tr("ELITE"), "tough": tr("TOUGH"), "easy": tr("EASY")}.get(s.e.tier, "")
	if tier_txt != "":
		var tp := UI.panel(Color("#7f1d1d"), Color(0, 0, 0, 0), 0, 99, 3)
		tp.add_child(UI.lbl(tr(tier_txt), 12, Color.WHITE, true))
		en.add_child(tp)
	en.add_child(UI.lbl(tr(s.e.n), roundi(20 * ks), Color.WHITE, true))
	var badges := []
	if s.e.imm != "":
		badges.append("🛡 %s%s -80%%" % [GameData.elem_icon(s.e.imm), tr(s.e.imm)])
	if s.e.weak != "":
		badges.append("💥 %s%s +50%%" % [GameData.elem_icon(s.e.weak), tr(s.e.weak)])
	var style_txt := GameData.foe_style_txt(s.e)
	if style_txt != "":
		badges.append(style_txt.get_slice(":", 0))   # icon + style name; the full line is on the road card
	for ch in FoeInfo.chips(s.e):
		if not String(ch).begins_with("⚠️") and ch != style_txt.get_slice(":", 0):
			badges.append(ch)
	badges.append("🔍")   # tap the monster for the full read-out
	var bl := UI.lbl("  ".join(badges), roundi(13 * ks), Color("#fca5a5"))
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # many skills / a pet must not push the screen wider
	bl.custom_minimum_size.x = 160
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	en.add_child(bl)
	ev.add_child(en)
	ehp_bar = StatBar.new().setup(Color("#ff4d5e"), 26 * ks)
	ev.add_child(ehp_bar)
	foe_chips = UI.hbox(6)
	foe_chips.alignment = BoxContainer.ALIGNMENT_END
	foe_chips.custom_minimum_size.y = 30
	ev.add_child(foe_chips)
	# boss move: a bar that fills toward the move, then flashes red while it warns
	if not s.mech.is_empty() or not s.fult_def.is_empty():
		mech_box = UI.panel(Color("#2a1020"), Color("#ff9f43"), 2, 14, 6)
		mech_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mv := UI.vbox(3)
		mech_box.add_child(mv)
		mech_lbl = UI.lbl("", roundi(15 * ks), Color("#ffd8a8"), true)
		mv.add_child(mech_lbl)
		mech_bar = _bar(Color("#ff9f43"), roundi(10 * ks))
		mech_bar.value = 0.0
		mv.add_child(mech_bar)
		ev.add_child(mech_box)
	# the monster's pack: its items charge and fire just like yours
	var mc := minf(46.0, minf(640.0 / maxf(1, s.e.get("gw", 4)), 150.0 / maxf(1, s.e.get("gh", 3))))
	if wide:
		mc = minf(78.0, minf(430.0 / maxf(1, s.e.get("gw", 4)), 400.0 / maxf(1, s.e.get("gh", 3))))
	mpack = MiniPack.new().setup(s.e, mc, s.fi)
	mpack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ev.add_child(mpack)
	v.add_child(eh)
	# tap (phone) or click (PC) the monster card: full read-out of what it does; the fight pauses
	eh.mouse_filter = Control.MOUSE_FILTER_STOP
	eh.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	eh.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_toggle_foe_info())

	# stage
	stage = Control.new()
	stage.custom_minimum_size = Vector2(0, 150)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.draw.connect(_draw_stage)
	v.add_child(stage)
	world = Control.new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(world)
	var boss: bool = s.node.k == "boss"
	foe = _sprite(GameData.foe_icon(s.e.n), roundi((110 if boss else 84) * ks * 1.4 if wide else (110 if boss else 84)), 0.74, 0.22 if boss else 0.34)
	if s.node.k in ["elite", "ambush", "boss", "mini"]:
		foe.add_theme_color_override("font_shadow_color", Color("#ff3b3b"))
		foe.add_theme_constant_override("shadow_outline_size", 12)
	hero = _sprite(r.cls_def().hero, 130 if wide else 70, 0.26, 0.42)
	if r.pet != "":
		_sprite(r.pet_def().ic, 64 if wide else 40, 0.1, 0.62)
	if not s.fpet.is_empty():
		_sprite(s.fpet.ic, 64 if wide else 40, 0.9, 0.62)   # the monster's pet (Hard and up)
	combo_lbl = UI.lbl("", 30, UI.GOLD, true)
	combo_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	combo_lbl.add_theme_constant_override("outline_size", 8)
	combo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_lbl.position = Vector2(16, 12)
	stage.add_child(combo_lbl)

	# hero bar
	var hb := UI.card(Color("#173a2f"), Color("#3ee07a"), 22, 12)
	var hv := UI.vbox(4)
	hb.add_child(hv)
	var hr := UI.hbox(8)
	hr.add_child(UI.lbl(r.cls_def().hero + " " + tr(r.cls_def().n), roundi(16 * ks * 1.2), Color.WHITE, true))
	hv.add_child(hr)
	php_bar = StatBar.new().setup(Color("#3ee07a"), 24 * ks)
	hv.add_child(php_bar)
	var ur := UI.hbox(8)
	hero_chips = UI.hbox(6)
	hero_chips.custom_minimum_size.y = 30
	ur.add_child(hero_chips)
	res_lbl = UI.lbl("", roundi(15 * ks), UI.GOLD, true)
	res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	res_lbl.pivot_offset = Vector2(60, 10)
	ur.add_child(res_lbl)
	hv.add_child(ur)
	var ulr := UI.hbox(8)
	ult_lbl = UI.lbl(r.cls_def().ult.ic + " " + tr(r.cls_def().ult.n), roundi(14 * ks), Color("#fde68a"), true)
	ulr.add_child(ult_lbl)
	ult_bar = _bar(Color("#ffd84a"), roundi(16 * ks))
	ult_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ult_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ulr.add_child(ult_bar)
	hv.add_child(ulr)
	# hover (PC) or tap (phone) the Ultimate / resource rows to read what they do mid-fight
	ult_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	for row in [ur, ulr]:
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_HELP
		if wide:
			row.mouse_entered.connect(func(): _show_ult_info(true))
			row.mouse_exited.connect(func(): _show_ult_info(false))
		else:
			row.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_show_ult_info(_ult_info == null))
	var tip := UI.lbl("ℹ️", roundi(14 * ks), Color("#fde68a"), true)
	ulr.add_child(tip)
	v.add_child(hb)

	# pack with live charge
	pack = Control.new()
	var mn := Vector2i(99, 99)
	var mx := Vector2i(-1, -1)
	for c in r.tiles:
		mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
		mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
	porg = mn
	var span := Vector2(mx - mn + Vector2i.ONE)
	pcell = minf(80.0, minf(680.0 / span.x, 330.0 / span.y))
	if wide:
		pcell = minf(92.0, minf(450.0 / span.x, 440.0 / span.y))
	pack.custom_minimum_size = span * pcell
	pack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pack.draw.connect(_draw_pack)
	v.add_child(pack)

	log_lbl = UI.lbl("", roundi(13 * ks), Color("#cbd5e1"))
	log_lbl.custom_minimum_size = Vector2(0, 36)
	log_lbl.clip_text = true
	v.add_child(log_lbl)

	# the chosen speed is remembered in settings, so every fight starts at it
	var saved: int = int(SaveGame.get_setting("combat_speed", 1))
	speed = saved if saved in [1, 2, 4] else 1
	var sp := UI.hbox(8)
	var sbs: Array[Button] = []
	for k in [1, 2, 4]:
		var kk: int = k
		var sb := UI.btn("%d×" % k, func():
			speed = kk
			SaveGame.set_setting("combat_speed", kk)
			for i in sbs.size():
				sbs[i].theme_type_variation = "Btn_blue" if [1, 2, 4][i] == kk else "Btn_gray", false, 20, "blue" if k == speed else "gray")
		sb.custom_minimum_size.x = 80
		sbs.append(sb)
		sp.add_child(sb)
	sp.add_child(UI.spacer())
	sp.add_child(UI.btn(tr("Skip") + " ⏭️", _skip, false, 20, "purple"))
	v.add_child(sp)

	if wide:
		# PC: [ your HP + pack | the fight | the monster + its pack ] above the log and speed buttons
		for c in [eh, stage, hb, pack]:
			v.remove_child(c)
		var top := UI.hbox(16)
		top.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var left := UI.vbox(12)
		left.custom_minimum_size.x = 500
		left.add_child(hb)
		pack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		left.add_child(pack)
		var right := UI.vbox(12)
		right.custom_minimum_size.x = 500
		eh.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		right.add_child(eh)
		stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(left)
		top.add_child(stage)
		top.add_child(right)
		v.add_child(top)
		v.move_child(top, 0)

	fxl = Control.new()
	fxl.set_anchors_preset(Control.PRESET_FULL_RECT)
	fxl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fxl)
	_refresh()
	if s.node.k == "boss":
		_intro = 2.6
		_boss_intro.call_deferred()
	return self


func _toggle_foe_info() -> void:
	if _foe_info:
		_foe_info.queue_free()
		_foe_info = null
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 30
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_toggle_foe_info())
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(cc)
	var vb := UI.vbox(8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(FoeInfo.build(sim.e, minf(size.x - 40.0, 760.0)))
	var hint := UI.lbl("⏸️ " + tr("Tap anywhere to close."), 15, UI.MU, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	cc.add_child(vb)
	add_child(dim)
	_foe_info = dim


## Opens / closes the explainer for your Ultimate and class resource (live charge numbers).
func _show_ult_info(on: bool) -> void:
	if not on:
		if _ult_info:
			_ult_info.queue_free()
			_ult_info = null
		return
	if _ult_info:
		return
	var p := UI.panel(Color("#1a1511", 0.97), Color("#fde68a"), 3, 16, 14)
	p.z_index = 20   # above floating numbers
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_size_override("normal_font_size", 22 if _wide else 18)
	rt.add_theme_font_size_override("bold_font_size", 24 if _wide else 20)
	var w := minf(fxl.size.x - 40.0, 620.0)
	rt.custom_minimum_size.x = w - 28.0
	p.add_child(rt)
	fxl.add_child(p)
	_ult_info = p
	_ult_info_lbl = rt
	_fill_ult_info()
	p.reset_size()
	# just above your HP card
	var hb_rect := php_bar.get_global_rect()
	var top := hb_rect.position.y - fxl.get_global_rect().position.y - 60.0
	p.position = Vector2(clampf(hb_rect.position.x - fxl.get_global_rect().position.x, 20.0, fxl.size.x - w - 20.0), 0)
	p.size.x = w
	(func():
		if is_instance_valid(p):
			p.position.y = maxf(10.0, top - p.size.y)).call_deferred()


func _fill_ult_info() -> void:
	if _ult_info_lbl == null:
		return
	var u: Dictionary = run.cls_def().ult
	var rd := sim.res_def()
	var t := "[b][color=#ffe14a]%s %s[/color][/b]\n%s\n" % [u.ic, tr(u.n), tr(u.d)]
	t += "[color=#fde68a]⚡ " + tr("Charges +1 every time one of your items triggers.") + " [b]%d / %d[/b][/color]\n\n" % [floori(sim.ult), sim.ult_need]
	t += "[b][color=#7dd3fc]%s %s: %d[/color][/b]\n%s" % [rd.ic, tr(rd.n), sim.resv, tr(rd.d)]
	if not _wide:
		t += "\n[color=#9ca3af][i]" + tr("Tap again to close.") + "[/i][/color]"
	_ult_info_lbl.text = t


func _bar(col: Color, h := 14) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, h)
	b.max_value = 1.0
	b.value = 1.0
	b.add_theme_stylebox_override("fill", UI.box(col, col.darkened(0.35), 2, 99, 0))
	return b


func _sprite(icon: String, fs: int, ax: float, ay: float) -> Label:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = ax
	holder.anchor_right = ax
	holder.anchor_top = ay
	holder.anchor_bottom = ay
	holder.offset_left = -fs * 0.7
	holder.offset_right = fs * 0.7
	holder.offset_bottom = fs * 1.25
	world.add_child(holder)
	var l := UI.lbl(icon, fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(fs * 1.4, fs * 1.25)
	l.pivot_offset = l.size / 2
	holder.add_child(l)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "position:y", -6.0, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(l, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	return l


# --------------------------------------------------------------- drawing

func _draw_stage() -> void:
	var s := stage.size
	var sky := StyleBoxFlat.new()
	sky.bg_color = Color("#3c3026")
	sky.set_corner_radius_all(22)
	stage.draw_style_box(sky, Rect2(Vector2.ZERO, s))
	for i in 6:
		var y := s.y * (0.1 + i * 0.1)
		stage.draw_rect(Rect2(0, y, s.x, s.y * 0.1), Color(1, 0.6, 0.9, 0.025 * i))
	var gr := StyleBoxFlat.new()
	gr.bg_color = Color("#2a5c45")
	gr.corner_radius_bottom_left = 22
	gr.corner_radius_bottom_right = 22
	stage.draw_style_box(gr, Rect2(0, s.y * 0.8, s.x, s.y * 0.2))
	stage.draw_rect(Rect2(0, s.y * 0.8, s.x, 6), Color("#3fa36f"))
	for l in [foe, hero]:
		var c: Vector2 = l.get_global_rect().get_center() - stage.get_global_rect().position
		stage.draw_set_transform(Vector2(c.x, c.y + l.size.y * 0.45), 0, Vector2(1, 0.28))
		stage.draw_circle(Vector2.ZERO, l.size.x * 0.32, Color(0, 0, 0, 0.3))
	stage.draw_set_transform(Vector2.ZERO)
	if sim and sim.tk > CombatSim.FATIGUE_TICK and not sim.done:
		stage.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.2, 0.25, 0.18))


## Each item is dark while it charges; its own colour fills it from the bottom up, and it
## flashes white when it fires. Passive items stay lit.
func _draw_pack() -> void:
	var f: Font = UI.font if UI.font else get_theme_default_font()
	var tile := StyleBoxFlat.new()
	tile.bg_color = Color("#1b1713")
	tile.border_color = Color("#3d3329")
	tile.set_border_width_all(2)
	tile.set_corner_radius_all(10)
	for c in run.tiles:
		pack.draw_style_box(tile, Rect2(Vector2(c - porg) * pcell, Vector2(pcell, pcell)).grow(-2))
	for it in run.grid_items():
		var col: Color = GameData.tier_color(it.id)
		var cells: Array = it.cells()
		var x = _xi.get(it.uid)
		var fl: float = _flash.get(it.uid, 9.0)
		var lit := clampf(1.0 - fl / 0.3, 0.0, 1.0)
		var ratio := 1.0
		var used := false
		if x != null:
			if x.d.once:
				used = x.used
				ratio = 0.0 if used else 1.0
			else:
				ratio = clampf(x.p / maxf(0.01, x.cd), 0.0, 1.0)
		# item height span, so the fill rises across the whole piece, not per cell
		var top := 999.0
		var bot := -999.0
		for c in cells:
			top = minf(top, (c.y - porg.y) * pcell)
			bot = maxf(bot, (c.y - porg.y + 1) * pcell)
		var level := bot - (bot - top) * ratio
		var charged: bool = ratio >= 0.999 and x != null and not x.d.once
		var dark := StyleBoxFlat.new()
		dark.bg_color = col.darkened(0.78)
		dark.border_color = col.darkened(0.35)
		dark.set_border_width_all(2)
		dark.set_corner_radius_all(10)
		var fill := StyleBoxFlat.new()
		fill.bg_color = col.lerp(Color.WHITE, 0.15 + lit * 0.7)
		fill.set_corner_radius_all(8)
		for c in cells:
			var r := Rect2(Vector2(c - porg) * pcell, Vector2(pcell, pcell)).grow(-3)
			var g := Rect2(r)
			if cells.has(c + Vector2i(1, 0)): g = g.grow_side(SIDE_RIGHT, 3.5)
			if cells.has(c + Vector2i(-1, 0)): g = g.grow_side(SIDE_LEFT, 3.5)
			if cells.has(c + Vector2i(0, 1)): g = g.grow_side(SIDE_BOTTOM, 3.5)
			if cells.has(c + Vector2i(0, -1)): g = g.grow_side(SIDE_TOP, 3.5)
			pack.draw_style_box(dark, g)
			# the part of this cell below the fill line
			var y0 := maxf(g.position.y, level)
			if y0 < g.end.y and not used:
				pack.draw_style_box(fill, Rect2(g.position.x + 2, y0, g.size.x - 4, g.end.y - y0 - 2))
			if lit > 0:
				pack.draw_rect(g.grow(2 + lit * 3), Color(1, 1, 1, lit * 0.8), false, 3.0)
			if charged or ratio > 0.85:
				pack.draw_rect(g.grow(1), Color(1, 1, 1, 0.25 + 0.25 * sin(_t * 18.0)), false, 2.0)
		var m := GameData.mid_cell(it.id, it.rot)
		var mc := (Vector2(Vector2i(it.x, it.y) + m - porg) + Vector2(0.5, 0.5)) * pcell
		var ic: String = it.def().ic
		var sz := int(pcell * 0.56 * (1.0 + lit * 0.4))
		var w := f.get_string_size(ic, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		pack.draw_string(f, mc + Vector2(-w / 2.0, sz * 0.36), ic, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(1, 1, 1, 0.3 if used else 1.0))
		if sim and sim.grab_t > 0 and sim.grab_uids.has(it.uid):
			# held by the Kraken: dark purple with a tentacle on top
			for c in cells:
				pack.draw_rect(Rect2(Vector2(c - porg) * pcell, Vector2(pcell, pcell)).grow(-3), Color(0.25, 0.05, 0.35, 0.7))
			var gs := int(pcell * 0.6)
			var gw := f.get_string_size("🐙", HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
			pack.draw_string(f, mc + Vector2(-gw / 2.0, gs * 0.36), "🐙", HORIZONTAL_ALIGNMENT_LEFT, -1, gs)
	if sim and sim.hero_freeze > 0:
		# Frost Nova / Earthquake: your items are frozen
		for c in run.tiles:
			pack.draw_rect(Rect2(Vector2(c - porg) * pcell, Vector2(pcell, pcell)).grow(-2), Color(0.55, 0.8, 1.0, 0.3))


# --------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if sim == null:
		return
	_t += delta
	for k in _flash:
		_flash[k] += delta
	if _combo > 0:
		_combo_t += delta
		if _combo_t > 1.5:
			_combo = 0
			combo_lbl.text = ""
	if sim.done:
		pack.queue_redraw()
		if _end_wait > 0:
			_end_wait -= delta
			if _end_wait <= 0:
				finished.emit(sim.won)
		return
	if _intro > 0:
		_intro -= delta
		return
	if _foe_info:
		return   # paused while you read what the monster does
	_acc += delta
	while _acc >= CombatSim.TICK and not sim.done:
		_acc -= CombatSim.TICK
		for _k in speed:
			sim.step()
			if sim.done:
				break
	_handle(sim.take_events())
	_refresh()
	pack.queue_redraw()


func _skip() -> void:
	speed = 99
	sim.skip_to_end()
	_refresh()
	_on_end(sim.won)


func _handle(evs: Array) -> void:
	var quiet := speed >= 4
	for ev in evs:
		match ev.t:
			"trigger":
				_flash[ev.uid] = 0.0
			"foe_trigger":
				mpack.flash[ev.uid] = 0.0
			"num":
				var kind: String = ev.get("kind", "")
				if kind == "shield":
					# shown by the white Shield strip on the HP bar, not as a floating number
					(php_bar if ev.side == "hero" else ehp_bar).pulse_shield()
				elif kind == "dot" or kind == "status":
					var ck: String = ev.side + ":" + ev.key
					var sk: String = String(ev.key).trim_prefix("hd:")
					if kind == "status" and ev.side == "hero" and String(ev.key).begins_with("hd:") and not _hero_hit_st.has(sk):
						# the first time a monster puts a status on you this fight: say it loud
						_hero_hit_st[sk] = true
						var s0: Dictionary = GameData.statuses[sk]
						var word: String = {"burn": "BURNING!", "poison": "POISONED!", "bleed": "BLEEDING!", "soaked": "SOAKED!"}.get(sk, s0.n)
						_float_at(_center_of(hero) + Vector2(0, -90), s0.ic + " " + tr(word), s0.col, true)
						var tw0 := hero.create_tween()
						hero.scale = Vector2(1.25, 1.25)
						tw0.tween_property(hero, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
					_pop_chip(ck, kind == "dot")
					if fxl.get_child_count() < (25 if quiet else 70):
						var at := (_chip_pos(ck) + Vector2(0, -34)) if _chips.has(ck) else _side_pos(ev.side, ev.uid)
						at.x = clampf(at.x, 70, fxl.size.x - 70)
						var txt: String = ev.text if kind == "status" else GameData.statuses[sk].ic + ev.text
						_float_at(at, txt, ev.col, false, kind == "status")
				elif fxl.get_child_count() < (25 if quiet else 70):
					_float_at(_side_pos(ev.side, ev.uid), ev.text, ev.col, ev.big)
			"hit":
				_hit_anim(ev, quiet)
			"foe_atk":
				if not quiet:
					_lunge(foe, -70)
					if ev.has("uid"):
						_projectile(ev.get("icon", "💥"), mpack.get_global_rect().position + mpack.item_center(ev.uid) - fxl.get_global_rect().position, _center_of(hero))
				if ev.ab > 0:
					php_bar.pulse_shield()
				var r := snappedf(ev.dm - ev.ab, 0.1)
				_flash_lbl(hero)
				_float_at(_center_of(hero), ("🛡️ " + tr("BLOCK")) if r <= 0 else "-" + GameData._num(r), Color("#7dd3fc") if r <= 0 else Color("#ff4d5e"), r >= 8)
				if r > 0:
					_hurt_flash(r / sim.mhp * 2.5)
				if r >= 8:
					_shake()
			"res":
				var tw := res_lbl.create_tween()
				res_lbl.pivot_offset = Vector2(res_lbl.size.x, res_lbl.size.y / 2)
				res_lbl.scale = Vector2(1.35, 1.35)
				tw.tween_property(res_lbl, "scale", Vector2.ONE, 0.25)
			"ult":
				_ult_banner(ev.ic + " " + tr(ev.n) + "!")
			"enrage":
				_ult_banner("💢 " + tr("ENRAGED!"))
				foe.self_modulate = Color(1.4, 0.55, 0.55)
				var tw := foe.create_tween().set_loops(3)
				tw.tween_property(foe, "scale", Vector2(1.25, 1.25), 0.12)
				tw.tween_property(foe, "scale", Vector2.ONE, 0.12)
			"mech_warn":
				_float_at(_center_of(foe) + Vector2(0, -70), "⚠️ " + tr(ev.n) + "!", Color("#ff9f43"), true)
			"mech":
				_ult_banner(ev.ic + " " + tr(ev.n) + "!")
				foe.self_modulate = Color(1.5, 0.8, 0.5)
				foe.create_tween().tween_property(foe, "self_modulate", Color(1.4, 0.55, 0.55) if sim.enraged else Color.WHITE, 0.4)
			"burst":
				_shake()
				_float_at(_center_of(foe), "💥 " + GameData._num(ev.v), Color("#ff8a3d"), true)
			"end":
				_on_end(ev.win)
	stage.queue_redraw()


## Global position (inside fxl) for numbers: foe/hero sprite, or the item that caused it.
func _side_pos(side: String, uid: int) -> Vector2:
	if side == "hero":
		if uid >= 0 and randf() < 0.5:
			return _item_pos(uid)
		return _center_of(hero)
	return _center_of(foe)


func _center_of(l: Control) -> Vector2:
	return l.get_global_rect().get_center() - fxl.get_global_rect().position


func _item_pos(uid: int) -> Vector2:
	var x = _xi.get(uid)
	if x == null:
		return _center_of(hero)
	var it: PItem = x.i
	var m := GameData.mid_cell(it.id, it.rot)
	var local := (Vector2(Vector2i(it.x, it.y) + m - porg) + Vector2(0.5, 0.5)) * pcell
	return pack.get_global_rect().position + local - fxl.get_global_rect().position


func _hit_anim(ev: Dictionary, quiet: bool) -> void:
	var col: Color = GameData.elem_colors.get(ev.el, Color.WHITE)
	var txt: String = GameData._num(ev.v)
	var big: bool = ev.crit or ev.v >= 25
	if ev.m < 1:
		txt = "🛡" + txt
		col = Color("#9ca3af")
	elif ev.crit:
		txt = tr("CRIT") + " " + txt + "!"
		col = Color("#ffe14a")
	elif ev.m > 1:
		txt = "✨" + txt
		col = Color("#fde047")
	_combo += 1
	_combo_t = 0.0
	if _combo >= 5:
		combo_lbl.text = tr("COMBO ×%d") % _combo
		combo_lbl.pivot_offset = combo_lbl.size / 2
		combo_lbl.scale = Vector2(1.3, 1.3)
		combo_lbl.create_tween().tween_property(combo_lbl, "scale", Vector2.ONE, 0.15)
	var land := func():
		_flash_lbl(foe)
		UI.burst(fxl, _center_of(foe), col, 10 if not big else 24, 260, 6 if not big else 9)
		_float_at(_center_of(foe) + Vector2(randf_range(-60, 60), randf_range(-20, 30)), txt, col, big)
		if big:
			_shake()
	if quiet or ev.uid < 0:
		land.call()
		return
	if ev.melee:
		_lunge(hero, 70)
	_projectile(ev.icon, _item_pos(ev.uid), _center_of(foe))
	create_tween().tween_callback(land).set_delay(0.22)


func _lunge(l: Label, dx: float) -> void:
	var tw := l.create_tween()
	tw.tween_property(l, "position:x", dx, 0.1)
	tw.tween_property(l, "position:x", 0.0, 0.16)


func _flash_lbl(l: Label) -> void:
	var tw := l.create_tween()
	l.modulate = Color(1, 0.4, 0.4)
	tw.tween_property(l, "modulate", Color.WHITE, 0.18)


func _projectile(icon: String, from: Vector2, to: Vector2) -> void:
	var p := UI.lbl(icon, 28)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.add_child(p)
	p.position = from - Vector2(16, 18)
	p.pivot_offset = Vector2(16, 18)
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "position", to - Vector2(16, 18), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(p, "rotation", TAU, 0.22)
	tw.chain().tween_callback(p.queue_free)


## Floating number: slams in oversized, settles, drifts up and fades. Big hits are huge.
func _float_at(pos: Vector2, text: String, col: Color, big: bool, small := false) -> void:
	var l := UI.lbl(text, 52 if big else (24 if small else 34), col, true)
	l.add_theme_color_override("font_outline_color", col.darkened(0.8))
	l.add_theme_constant_override("outline_size", 14 if big else 10)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.add_child(l)
	var sz := l.get_minimum_size()
	l.position = pos + Vector2(randf_range(-30, 30), randf_range(-14, 14)) - sz / 2
	l.pivot_offset = sz / 2
	l.scale = Vector2(2.2, 2.2) if big else Vector2(1.7, 1.7)
	l.rotation = randf_range(-0.12, 0.12)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.15, 1.15) if big else Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25 if big else 0.15)
	tw.tween_property(l, "position:y", l.position.y - (110 if big else 70), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.tween_callback(l.queue_free)


## Red edge flash when you take a big hit.
func _hurt_flash(strength: float) -> void:
	var r := ColorRect.new()
	r.color = Color(1, 0.1, 0.15, clampf(strength, 0.15, 0.45))
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.add_child(r)
	r.create_tween().tween_property(r, "color:a", 0.0, 0.35).finished.connect(r.queue_free)


func _ult_banner(text: String) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 0.9, 0.4, 0.45)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.add_child(flash)
	flash.create_tween().tween_property(flash, "color:a", 0.0, 0.5).finished.connect(flash.queue_free)
	var l := UI.lbl(text, 44, Color("#fff3b0"), true)
	l.add_theme_color_override("font_outline_color", Color("#7c2d12"))
	l.add_theme_constant_override("outline_size", 12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fxl.add_child(l)
	l.size = Vector2(fxl.size.x, 60)
	l.position = Vector2(0, stage.get_global_rect().get_center().y - fxl.get_global_rect().position.y - 30)
	l.pivot_offset = l.size / 2
	l.scale = Vector2(2.2, 2.2)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)
	_shake()


func _shake() -> void:
	if _shake_tw and _shake_tw.is_running():
		return
	_shake_tw = world.create_tween()
	for o in [Vector2(-6, 3), Vector2(6, -4), Vector2(-4, -3), Vector2(4, 3), Vector2.ZERO]:
		_shake_tw.tween_property(world, "position", o, 0.04)


func _on_end(won: bool) -> void:
	if _end_wait > 0:
		return
	_end_wait = 1.8
	if won:
		for k in 4:
			create_tween().tween_callback(func(): UI.burst(fxl, Vector2(randf_range(80, fxl.size.x - 80), randf_range(150, 450)), [UI.GOLD, UI.GOOD, UI.STAR, Color("#4f8cff")].pick_random(), 36, 380, 8)).set_delay(0.15 * k)
	var dead := foe if won else hero
	var tw := dead.create_tween().set_parallel()
	tw.tween_property(dead, "rotation", deg_to_rad(80), 0.9)
	tw.tween_property(dead, "modulate:a", 0.0, 0.9)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.add_child(dim)
	var saved: bool = not won and run.res > 0   # a Heart will bring you back: you survived this one
	var ban := UI.lbl(tr("VICTORY!") if won else (tr("SURVIVED") if saved else tr("DEFEAT")), 56, Color("#ffe14a") if won else (Color("#ffb020") if saved else Color("#ff5a5f")), true)
	ban.add_theme_color_override("font_outline_color", Color.BLACK)
	ban.add_theme_constant_override("outline_size", 12)
	ban.set_anchors_preset(Control.PRESET_FULL_RECT)
	ban.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ban.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fxl.add_child(ban)
	ban.pivot_offset = fxl.size / 2
	ban.scale = Vector2(2.2, 2.2)
	ban.create_tween().tween_property(ban, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)


func _refresh() -> void:
	var hd_col := _dot_col(sim.hd)
	var fd_col := _dot_col(sim.fs)
	php_bar.set_values(sim.php / sim.mhp, sim.shield, sim.mhp, sim.dot_forecast("hero") / sim.mhp, hd_col,
		"HP %d / %d" % [maxi(0, roundi(sim.php)), roundi(sim.mhp)])
	ehp_bar.set_values(sim.ehp / sim.e.hp, sim.fshield, sim.e.hp, sim.dot_forecast("foe") / sim.e.hp, fd_col,
		"%d / %d" % [maxi(0, roundi(sim.ehp)), roundi(sim.e.hp)])
	var seen := {}
	# on the monster: your burn / poison, with what each tick deals right now
	for k in sim.fs:
		if sim.fs[k] > 0:
			_chip("foe:" + k, foe_chips, k, "%s %s" % [GameData.statuses[k].ic, GameData._num(sim.fs[k])], _status_sub(k, sim.fs[k], sim.dot_tick("foe", k)), seen)
	# on you: what the monster put on you, then your own statuses (Thorns)
	for k in sim.hd:
		if sim.hd[k] > 0:
			_chip("hero:hd:" + k, hero_chips, k, "%s %s" % [GameData.statuses[k].ic, GameData._num(sim.hd[k])], _status_sub(k, sim.hd[k], sim.dot_tick("hero", k)), seen)
	for k in sim.hs:
		if sim.hs[k] > 0:
			var s: Dictionary = GameData.statuses[k]
			var sub := ("↩%s" % GameData._num(snappedf(sim.hs[k] * s.reflect, 0.1))) if s.reflect > 0 else ""
			_chip("hero:" + k, hero_chips, k, "%s %s" % [s.ic, GameData._num(sim.hs[k])], sub, seen)
	# your hero is tinted by the worst status a monster put on you
	var bad := ""
	for k in sim.hd:
		if sim.hd[k] > 0 and (bad == "" or sim.hd[k] > sim.hd[bad]):
			bad = k
	hero.self_modulate = Color.WHITE.lerp(GameData.statuses[bad].col, 0.45 + 0.15 * sin(_t * 6.0)) if bad != "" else Color.WHITE
	var h := sim.haste()
	if h > 0:
		_chip("hero:haste", hero_chips, "", "💨 +%d%%" % roundi(h * 100), "", seen)
	# boss moves and late-monster traits
	if sim.hero_freeze > 0:
		_chip("hero:frozen", hero_chips, "", "❄️ %.1fs" % (sim.hero_freeze / 10.0), "", seen)
	if sim.grab_t > 0:
		_chip("hero:grab", hero_chips, "", "🐙 %.1fs" % (sim.grab_t / 10.0), "", seen)
	if sim.spiders > 0:
		_chip("foe:spiders", foe_chips, "", "🕷️ %d" % sim.spiders, "", seen)
	if sim.rally > 0:
		_chip("foe:rally", foe_chips, "", "%s +%d%%" % ["😡" if sim.e.tr == "berserk" else "📯", roundi(sim.rally * 100)], "", seen)
	if mech_box:
		var ms := sim.mech_state()
		var warn: bool = ms.warn
		var when: String = ("%.1fs" % ms.s) if ms.s >= 0 else ("⭐ " + tr("Ultimate") + " " + str(ms.cnt))
		mech_lbl.text = ("⚠️ " if warn else "") + "%s %s  %s" % [ms.ic, tr(ms.n), when]
		mech_bar.value = clampf(ms.p, 0.0, 1.0)
		if warn != _mech_was_warn:
			_mech_was_warn = warn
			var col := Color("#ff3b3b") if warn else Color("#ff9f43")
			mech_bar.add_theme_stylebox_override("fill", UI.box(col, col.darkened(0.35), 2, 99, 0))
			mech_lbl.add_theme_color_override("font_color", Color("#ffb4b4") if warn else Color("#ffd8a8"))
		mech_box.self_modulate = Color(1.0, 0.55 + 0.45 * absf(sin(_t * 9.0)), 0.55 + 0.45 * absf(sin(_t * 9.0))) if warn else Color.WHITE
	for key in _chips.keys():
		if not seen.has(key):
			_chips[key].queue_free()
			_chips.erase(key)
	var rd := sim.res_def()
	res_lbl.text = "%s %s %d" % [rd.ic, tr(rd.n), sim.resv]
	ult_bar.value = float(sim.ult) / float(sim.ult_need)
	if _ult_info:
		_fill_ult_info()
	log_lbl.text = "  ·  ".join(sim.log_lines.slice(0, 2))


## One status chip: icon + stacks, and underneath what it does right now (damage per tick, Thorns
## reflect). Created on first sight, updated in place, freed when the status runs out.
func _chip(key: String, row: HBoxContainer, sid: String, main_txt: String, sub_txt: String, seen: Dictionary) -> void:
	seen[key] = true
	var p: PanelContainer = _chips.get(key)
	if p == null:
		var col: Color = GameData.statuses[sid].col if sid != "" else Color("#ffe14a")
		p = UI.panel(col.darkened(0.72), col, 2, 99, 4)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hb := UI.hbox(4)
		var ml := UI.plbl("", 17, Color.WHITE, true)
		var sl := UI.plbl("", 13, col.lightened(0.35), true)
		hb.add_child(ml)
		hb.add_child(sl)
		p.add_child(hb)
		p.set_meta("ml", ml)
		p.set_meta("sl", sl)
		row.add_child(p)
		_chips[key] = p
		p.scale = Vector2(0.4, 0.4)
		p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	(p.get_meta("ml") as Label).text = main_txt
	var sl2: Label = p.get_meta("sl")
	sl2.text = sub_txt
	sl2.visible = sub_txt != ""
	p.pivot_offset = p.size / 2


## What a status chip says under its stacks: damage per second, Bleed per item use, Soaked effect.
func _status_sub(k: String, n: float, tick: float) -> String:
	var s: Dictionary = GameData.statuses[k]
	if s.get("trig", 0.0) > 0:
		return "-%s/%s" % [GameData._num(snappedf(n * s.trig, 0.1)), tr("use")]
	if s.get("magic_amp", 0.0) > 0:
		return "+%d%% %s" % [roundi(n * s.magic_amp * 100), tr("Magic")]
	return _rate_txt(tick)


## Per-tick damage under a DoT chip, e.g. "-4.8/s".
func _rate_txt(v: float) -> String:
	return ("-%s/%s" % [GameData._num(snappedf(v, 0.1)), tr("s")]) if v > 0 else ""


## Colour of the strongest DoT on a side (for the HP bar forecast segment).
func _dot_col(st: Dictionary) -> Color:
	var best := ""
	for k in st:
		if GameData.statuses[k].tick > 0 and st[k] > 0 and (best == "" or st[k] > st[best]):
			best = k
	return GameData.statuses[best].col if best != "" else Color("#a855f7")


func _chip_pos(key: String) -> Vector2:
	return _chips[key].get_global_rect().get_center() - fxl.get_global_rect().position


## Chip bounce when its status ticks (small) or gains stacks (bigger).
func _pop_chip(key: String, tick: bool) -> void:
	var p: PanelContainer = _chips.get(key)
	if p == null:
		return
	p.pivot_offset = p.size / 2
	p.scale = Vector2(1.15, 1.15) if tick else Vector2(1.35, 1.35)
	p.modulate = Color(1.6, 1.6, 1.6)
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "scale", Vector2.ONE, 0.2)
	tw.tween_property(p, "modulate", Color.WHITE, 0.25)


## Boss entrance: the screen darkens, the boss slams in huge, its name crashes down with
## a shake, and its resist / weakness flash up. The fight waits until it is over.
func _boss_intro() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0, 0.02, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.add_child(dim)
	var v := UI.vbox(10)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var warn := UI.title("⚠️ " + tr("BOSS") + " ⚠️", 34, UI.BAD, Color.BLACK)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(warn)
	var ic := UI.lbl(GameData.foe_icon(sim.e.n), 160)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ic)
	var nm := UI.title(tr(sim.e.n), 56, UI.GOLD, Color("#4a0000"))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var info := []
	if sim.e.get("imm", "") != "":
		info.append("🛡️ " + tr("resists %s") % (GameData.elem_icon(sim.e.imm) + tr(sim.e.imm)))
	if sim.e.get("weak", "") != "":
		info.append("💥 " + tr("weak to %s") % (GameData.elem_icon(sim.e.weak) + tr(sim.e.weak)))
	info.append("❤️ %d" % roundi(sim.e.hp))
	var il := UI.lbl("   ".join(info), 20, Color("#ffd0d0"), true)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(il)
	var rage := UI.lbl(tr("Enrages at half HP!"), 18, UI.BAD, true)
	rage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rage)
	for c in [warn, ic, nm, il, rage]:
		c.modulate.a = 0
	await get_tree().process_frame
	ic.pivot_offset = ic.size / 2
	nm.pivot_offset = nm.size / 2
	var tw := dim.create_tween()
	tw.tween_property(warn, "modulate:a", 1.0, 0.15)
	tw.tween_callback(func():
		ic.scale = Vector2(3, 3)
		ic.modulate.a = 1)
	tw.tween_property(ic, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_shake()
		UI.burst(fxl, fxl.size / 2, UI.BAD, 40, 520, 10)
		nm.scale = Vector2(2.4, 2.4)
		nm.modulate.a = 1)
	tw.tween_property(nm, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	tw.tween_property(il, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(rage, "modulate:a", 1.0, 0.2)
	tw.tween_interval(0.9)
	tw.tween_property(dim, "modulate:a", 0.0, 0.35)
	tw.tween_callback(dim.queue_free)
