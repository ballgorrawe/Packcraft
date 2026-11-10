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


func setup(r: RunState, s: CombatSim) -> CombatView:
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
	var tier_txt: String = {"boss": "💀 BOSS", "elite": "👹 ELITE", "tough": "TOUGH", "easy": "EASY"}.get(s.e.tier, "")
	if tier_txt != "":
		var tp := UI.panel(Color("#7f1d1d"), Color(0, 0, 0, 0), 0, 99, 3)
		tp.add_child(UI.lbl(tr(tier_txt), 12, Color.WHITE, true))
		en.add_child(tp)
	en.add_child(UI.lbl(tr(s.e.n), 20, Color.WHITE, true))
	var badges := []
	if s.e.imm != "":
		badges.append("🛡 %s%s -80%%" % [GameData.elem_icon(s.e.imm), tr(s.e.imm)])
	if s.e.weak != "":
		badges.append("💥 %s%s +50%%" % [GameData.elem_icon(s.e.weak), tr(s.e.weak)])
	if s.e.tr != "":
		badges.append(GameData.traits[s.e.tr].ic + " " + tr(GameData.traits[s.e.tr].n))
	var bl := UI.lbl("  ".join(badges), 13, Color("#fca5a5"))
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	en.add_child(bl)
	ev.add_child(en)
	ehp_bar = _bar(Color("#ff4d5e"), 26)
	ev.add_child(ehp_bar)
	var er := UI.hbox(8)
	ehp_lbl = UI.lbl("", 14, Color("#fecaca"), true)
	er.add_child(ehp_lbl)
	foe_status = UI.lbl("", 16, Color.WHITE, true)
	foe_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foe_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	er.add_child(foe_status)
	ev.add_child(er)
	# the monster's pack: its items charge and fire just like yours
	var mc := minf(46.0, minf(640.0 / maxf(1, s.e.get("gw", 4)), 150.0 / maxf(1, s.e.get("gh", 3))))
	mpack = MiniPack.new().setup(s.e, mc, s.fi)
	mpack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ev.add_child(mpack)
	v.add_child(eh)

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
	foe = _sprite(GameData.foe_icon(s.e.n), 110 if boss else 84, 0.74, 0.22 if boss else 0.34)
	if s.node.k in ["elite", "ambush", "boss"]:
		foe.add_theme_color_override("font_shadow_color", Color("#ff3b3b"))
		foe.add_theme_constant_override("shadow_outline_size", 12)
	hero = _sprite(r.cls_def().hero, 70, 0.26, 0.42)
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
	hr.add_child(UI.lbl(r.cls_def().hero + " " + tr(r.cls_def().n), 16, Color.WHITE, true))
	hero_status = UI.lbl("", 16, Color("#7dd3fc"), true)
	hero_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hr.add_child(hero_status)
	hv.add_child(hr)
	php_bar = _bar(Color("#3ee07a"), 24)
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
	ult_bar = _bar(Color("#ffd84a"), 16)
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
	pcell = minf(80.0, minf(680.0 / span.x, 330.0 / span.y))
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
		var sb := UI.btn("%d×" % k, func(): speed = kk, false, 20, "gray")
		sb.custom_minimum_size.x = 80
		sp.add_child(sb)
	sp.add_child(UI.spacer())
	sp.add_child(UI.btn(tr("Skip") + " ⏭️", _skip, false, 20, "purple"))
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
	sky.bg_color = Color("#3b2a7a")
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
	tile.bg_color = Color("#1c1745")
	tile.border_color = Color("#3d3383")
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
			"foe_trigger":
				mpack.flash[ev.uid] = 0.0
			"num":
				if fxl.get_child_count() < (25 if quiet else 70):
					_float_at(_side_pos(ev.side, ev.uid), ev.text, ev.col, ev.big)
			"hit":
				_hit_anim(ev, quiet)
			"foe_atk":
				if not quiet:
					_lunge(foe, -70)
					if ev.has("uid"):
						_projectile(ev.get("icon", "💥"), mpack.get_global_rect().position + mpack.item_center(ev.uid) - fxl.get_global_rect().position, _center_of(hero))
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
func _float_at(pos: Vector2, text: String, col: Color, big: bool) -> void:
	var l := UI.lbl(text, 52 if big else 34, col, true)
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
