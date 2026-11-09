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

var php_bar: ProgressBar
var ehp_bar: ProgressBar
var php_lbl: Label
var ehp_lbl: Label
var hero_status: Label
var foe_status: Label
var res_lbl: Label
var ult_bar: ProgressBar
var ult_lbl: Label
var stage: Control
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


func setup(r: RunState, s: CombatSim) -> CombatView:
	run = r
	sim = s
	for x in s.items:
		_xi[x.i.uid] = x
	add_theme_stylebox_override("panel", UI.box(Color("#0b1220"), Color.BLACK, 0, 0, 0))
	var root := Control.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)
	var v := UI.vbox(6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(v)

	# enemy header
	var eh := UI.panel(Color("#2a1416"), Color("#7f1d1d"), 2, 12, 10)
	var ev := UI.vbox(4)
	eh.add_child(ev)
	var en := UI.hbox(8)
	var tier_txt: String = {"boss": "💀 BOSS", "elite": "👹 ELITE", "tough": "TOUGH", "easy": "EASY"}.get(s.e.tier, "")
	if tier_txt != "":
		var tp := UI.panel(Color("#7f1d1d"), Color(0, 0, 0, 0), 0, 99, 3)
		tp.add_child(UI.lbl(tr(tier_txt), 12, Color.WHITE, true))
		en.add_child(tp)
	en.add_child(UI.lbl(tr(s.e.n), 20, Color.WHITE, true))
	var badges := []
	if s.e.imm != "":
		badges.append("🛡 %s%s −80%%" % [GameData.elem_icon(s.e.imm), tr(s.e.imm)])
	if s.e.weak != "":
		badges.append("💥 %s%s +50%%" % [GameData.elem_icon(s.e.weak), tr(s.e.weak)])
	if s.e.tr != "":
		badges.append(GameData.traits[s.e.tr].ic + " " + tr(GameData.traits[s.e.tr].n))
	var bl := UI.lbl("  ".join(badges), 13, Color("#fca5a5"))
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	en.add_child(bl)
	ev.add_child(en)
	ehp_bar = _bar(Color("#ef4444"), 20)
	ev.add_child(ehp_bar)
	var er := UI.hbox(8)
	ehp_lbl = UI.lbl("", 14, Color("#fecaca"), true)
	er.add_child(ehp_lbl)
	foe_status = UI.lbl("", 16, Color.WHITE, true)
	foe_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foe_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	er.add_child(foe_status)
	ev.add_child(er)
	v.add_child(eh)

	# stage
	stage = Control.new()
	stage.custom_minimum_size = Vector2(0, 250)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.draw.connect(_draw_stage)
	v.add_child(stage)
	world = Control.new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(world)
	var boss: bool = s.node.k == "boss"
	foe = _sprite(GameData.foe_icon(s.e.n), 110 if boss else 84, 0.5, 0.06)
	if s.node.k in ["elite", "ambush", "boss"]:
		foe.add_theme_color_override("font_shadow_color", Color("#ff3b3b"))
		foe.add_theme_constant_override("shadow_outline_size", 12)
	hero = _sprite(r.cls_def().hero, 70, 0.5, 0.62)
	combo_lbl = UI.lbl("", 30, UI.GOLD, true)
	combo_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	combo_lbl.add_theme_constant_override("outline_size", 8)
	combo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_lbl.position = Vector2(16, 12)
	stage.add_child(combo_lbl)

	# hero bar
	var hb := UI.panel(Color("#10241c"), Color("#14532d"), 2, 12, 10)
	var hv := UI.vbox(4)
	hb.add_child(hv)
	var hr := UI.hbox(8)
	hr.add_child(UI.lbl(r.cls_def().hero + " " + tr(r.cls_def().n), 16, Color.WHITE, true))
	hero_status = UI.lbl("", 16, Color("#7dd3fc"), true)
	hero_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hr.add_child(hero_status)
	hv.add_child(hr)
	php_bar = _bar(Color("#4ade80"), 18)
	hv.add_child(php_bar)
	var ur := UI.hbox(8)
	php_lbl = UI.lbl("", 14, Color("#bbf7d0"), true)
	ur.add_child(php_lbl)
	res_lbl = UI.lbl("", 15, UI.GOLD, true)
	res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	res_lbl.pivot_offset = Vector2(60, 10)
	ur.add_child(res_lbl)
	hv.add_child(ur)
	var ulr := UI.hbox(8)
	ult_lbl = UI.lbl(r.cls_def().ult.ic + " " + tr(r.cls_def().ult.n), 14, Color("#fde68a"), true)
	ulr.add_child(ult_lbl)
	ult_bar = _bar(Color("#facc15"), 12)
	ult_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ult_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ulr.add_child(ult_bar)
	hv.add_child(ulr)
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
	pcell = minf(84.0, minf(680.0 / span.x, 380.0 / span.y))
	pack.custom_minimum_size = span * pcell
	pack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pack.draw.connect(_draw_pack)
	v.add_child(pack)

	log_lbl = UI.lbl("", 13, Color("#cbd5e1"))
	log_lbl.custom_minimum_size = Vector2(0, 36)
	log_lbl.clip_text = true
	v.add_child(log_lbl)

	var sp := UI.hbox(8)
	for k in [1, 2, 4]:
		var kk: int = k
		sp.add_child(UI.btn("%d×" % k, func(): speed = kk, false, 18))
	sp.add_child(UI.spacer())
	sp.add_child(UI.btn(tr("Skip") + " ⏭", _skip, false, 18))
	v.add_child(sp)

	fxl = Control.new()
	fxl.set_anchors_preset(Control.PRESET_FULL_RECT)
	fxl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fxl)
	_refresh()
	return self


func _bar(col: Color, h := 14) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, h)
	b.max_value = 1.0
	b.value = 1.0
	b.add_theme_stylebox_override("fill", UI.box(col, col, 0, 4, 0))
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
	stage.draw_rect(Rect2(Vector2.ZERO, s), Color("#1c2a4d"))
	stage.draw_rect(Rect2(0, s.y * 0.35, s.x, s.y * 0.65), Color("#26365c"))
	stage.draw_rect(Rect2(0, s.y * 0.78, s.x, s.y * 0.22), Color("#3d3029"))
	if sim and sim.tk > CombatSim.FATIGUE_TICK and not sim.done:
		stage.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.2, 0.25, 0.18))


func _draw_pack() -> void:
	var f: Font = UI.font if UI.font else get_theme_default_font()
	for c in run.tiles:
		pack.draw_rect(Rect2(Vector2(c - porg) * pcell, Vector2(pcell, pcell)).grow(-2), Color("#1d2b33"))
	for it in run.grid_items():
		var col: Color = GameData.tier_color(it.id)
		var cells: Array = it.cells()
		var x = _xi.get(it.uid)
		var fl: float = _flash.get(it.uid, 9.0)
		var lit := clampf(1.0 - fl / 0.35, 0.0, 1.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.45).lerp(Color.WHITE, lit * 0.55)
		sb.border_color = col.lerp(Color.WHITE, lit)
		sb.set_border_width_all(2 + int(lit * 2))
		sb.set_corner_radius_all(10)
		var bb := Rect2(Vector2(cells[0] - porg) * pcell, Vector2(pcell, pcell))
		for c in cells:
			var r := Rect2(Vector2(c - porg) * pcell, Vector2(pcell, pcell)).grow(-3)
			if cells.has(c + Vector2i(1, 0)): r = r.grow_side(SIDE_RIGHT, 3.5)
			if cells.has(c + Vector2i(-1, 0)): r = r.grow_side(SIDE_LEFT, 3.5)
			if cells.has(c + Vector2i(0, 1)): r = r.grow_side(SIDE_BOTTOM, 3.5)
			if cells.has(c + Vector2i(0, -1)): r = r.grow_side(SIDE_TOP, 3.5)
			pack.draw_style_box(sb, r)
			bb = bb.merge(Rect2(Vector2(c - porg) * pcell, Vector2(pcell, pcell)))
		# charge: fill rises from the bottom of each cell, ring around the icon
		var ratio := 0.0
		if x != null:
			if x.d.once:
				ratio = 0.0 if x.used else 1.0
			else:
				ratio = clampf(x.p / maxf(0.01, x.cd), 0.0, 1.0)
			for c in cells:
				var r := Rect2(Vector2(c - porg) * pcell, Vector2(pcell, pcell)).grow(-4)
				var hgt := r.size.y * ratio
				pack.draw_rect(Rect2(r.position.x, r.end.y - hgt, r.size.x, hgt), Color(1, 1, 1, 0.13))
		var m := GameData.mid_cell(it.id, it.rot)
		var mc := (Vector2(Vector2i(it.x, it.y) + m - porg) + Vector2(0.5, 0.5)) * pcell
		if x != null and not x.d.once:
			pack.draw_arc(mc, pcell * 0.42, -PI / 2, -PI / 2 + TAU * ratio, 32, Color(UI.GOLD, 0.95), 4.0)
		var used: bool = x != null and x.d.once and x.used
		var ic: String = it.def().ic
		var sz := int(pcell * 0.5 * (1.0 + lit * 0.35))
		var w := f.get_string_size(ic, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		pack.draw_string(f, mc + Vector2(-w / 2.0, sz * 0.36), ic, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(1, 1, 1, 0.35 if used else 1.0))


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
			"num":
				if fxl.get_child_count() < (25 if quiet else 70):
					_float_at(_side_pos(ev.side, ev.uid), ev.text, ev.col, ev.big)
			"hit":
				_hit_anim(ev, quiet)
			"foe_atk":
				if not quiet:
					_lunge(foe, 60)
				var r := snappedf(ev.dm - ev.ab, 0.1)
				_flash_lbl(hero)
				_float_at(_center_of(hero), tr("BLOCK") if r <= 0 else "-" + GameData._num(r), Color("#7dd3fc") if r <= 0 else Color("#ff5a5f"), r >= 10)
				if r >= 10:
					_shake()
			"res":
				var tw := res_lbl.create_tween()
				res_lbl.pivot_offset = Vector2(res_lbl.size.x, res_lbl.size.y / 2)
				res_lbl.scale = Vector2(1.35, 1.35)
				tw.tween_property(res_lbl, "scale", Vector2.ONE, 0.25)
			"ult":
				_ult_banner(ev.ic + " " + tr(ev.n) + "!")
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
		txt = "✦" + txt
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
		_float_at(_center_of(foe) + Vector2(randf_range(-60, 60), randf_range(-20, 30)), txt, col, big)
		if big:
			_shake()
	if quiet or ev.uid < 0:
		land.call()
		return
	if ev.melee:
		_lunge(hero, -60)
	_projectile(ev.icon, _item_pos(ev.uid), _center_of(foe))
	create_tween().tween_callback(land).set_delay(0.22)


func _lunge(l: Label, dy: float) -> void:
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", dy, 0.1)
	tw.tween_property(l, "position:y", 0.0, 0.16)


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


func _float_at(pos: Vector2, text: String, col: Color, big: bool) -> void:
	var l := UI.lbl(text, 30 if big else 19, col, true)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7 if big else 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.add_child(l)
	l.position = pos + Vector2(randf_range(-24, 24), randf_range(-10, 10)) - Vector2(20, 12)
	l.pivot_offset = Vector2(20, 12)
	l.scale = Vector2(0.5, 0.5)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.35, 1.35) if big else Vector2(1.1, 1.1), 0.12)
	tw.parallel().tween_property(l, "position:y", l.position.y - (80 if big else 56), 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.tween_callback(l.queue_free)


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
	var dead := foe if won else hero
	var tw := dead.create_tween().set_parallel()
	tw.tween_property(dead, "rotation", deg_to_rad(80), 0.9)
	tw.tween_property(dead, "modulate:a", 0.0, 0.9)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.add_child(dim)
	var ban := UI.lbl(tr("VICTORY!") if won else tr("DEFEAT"), 56, Color("#ffe14a") if won else Color("#ff5a5f"), true)
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
	php_bar.value = clampf(sim.php / sim.mhp, 0, 1)
	ehp_bar.value = clampf(sim.ehp / sim.e.hp, 0, 1)
	php_lbl.text = "HP %d / %d" % [maxi(0, roundi(sim.php)), roundi(sim.mhp)]
	ehp_lbl.text = "%d / %d" % [maxi(0, roundi(sim.ehp)), roundi(sim.e.hp)]
	var hs := []
	if sim.shield > 0:
		hs.append("🛡%d" % roundi(sim.shield))
	for k in sim.hs:
		if sim.hs[k] > 0:
			hs.append(GameData.statuses[k].ic + GameData._num(sim.hs[k]))
	var h := sim.haste()
	if h > 0:
		hs.append("💨+%d%%" % roundi(h * 100))
	hero_status.text = "  ".join(hs)
	var es := []
	for k in sim.fs:
		if sim.fs[k] > 0:
			es.append(GameData.statuses[k].ic + GameData._num(sim.fs[k]))
	foe_status.text = "  ".join(es)
	var rd := sim.res_def()
	res_lbl.text = "%s %s %d" % [rd.ic, tr(rd.n), sim.resv]
	ult_bar.value = float(sim.ult) / float(sim.ult_need)
	log_lbl.text = "  ·  ".join(sim.log_lines.slice(0, 2))
