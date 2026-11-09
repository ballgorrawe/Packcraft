class_name CombatView
extends PanelContainer
## Evening arena: steps the CombatSim in real time and animates its events.

signal finished(won: bool)

var sim: CombatSim
var run: RunState
var speed := 1
var _acc := 0.0
var _end_wait := -1.0

var php_bar: ProgressBar
var ehp_bar: ProgressBar
var php_lbl: Label
var ehp_lbl: Label
var hero_status: Label
var foe_status: Label
var stage: Control
var world: Control
var fx: Control
var hero: Label
var pet: Label
var foe: Label
var belt := {}      # uid -> {tile, bar}
var log_lbl: Label
var _shake_tw: Tween


func setup(r: RunState, s: CombatSim) -> CombatView:
	run = r
	sim = s
	add_theme_stylebox_override("panel", UI.box(Color("#0b1220"), Color.BLACK, 2, 10, 0))
	var v := UI.vbox(0)
	add_child(v)

	# HUD
	var hud := UI.hbox(14)
	var hm := MarginContainer.new()
	for side in ["left", "right", "top"]:
		hm.add_theme_constant_override("margin_" + side, 10)
	hm.add_child(hud)
	v.add_child(hm)
	var hcol := UI.vbox(2)
	hcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hrow := UI.hbox()
	hrow.add_child(UI.lbl(r.cls_def().ic + " You", 15, Color.WHITE, true))
	hero_status = UI.lbl("", 13, Color("#7dd3fc"))
	hrow.add_child(hero_status)
	hcol.add_child(hrow)
	php_bar = _bar(Color("#4ade80"))
	hcol.add_child(php_bar)
	php_lbl = UI.lbl("", 12, Color("#cbd5e1"))
	hcol.add_child(php_lbl)
	hud.add_child(hcol)
	var ecol := UI.vbox(2)
	ecol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var erow := UI.hbox()
	erow.add_child(UI.lbl(s.e.n + (("  🛡 resists " + s.e.imm) if s.e.imm != "" else ""), 15, Color.WHITE, true))
	foe_status = UI.lbl("", 13, Color("#fca5a5"))
	erow.add_child(foe_status)
	ecol.add_child(erow)
	ehp_bar = _bar(Color("#ef4444"))
	ecol.add_child(ehp_bar)
	ehp_lbl = UI.lbl("", 12, Color("#cbd5e1"))
	ecol.add_child(ehp_lbl)
	hud.add_child(ecol)

	# Stage
	stage = Control.new()
	stage.custom_minimum_size = Vector2(0, 200)
	stage.clip_contents = true
	stage.draw.connect(_draw_stage)
	v.add_child(stage)
	world = Control.new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(world)
	pet = _sprite(r.pet_def().ic, 34, 0.04)
	hero = _sprite(r.cls_def().ic, 66, 0.16)
	var boss: bool = s.node.k == "boss"
	foe = _sprite(GameData.foe_icon(s.e.n), 96 if boss else 66, 0.70 if boss else 0.72)
	if s.node.k in ["elite", "ambush"]:
		foe.add_theme_color_override("font_shadow_color", Color("#ff3b3b"))
		foe.add_theme_constant_override("shadow_outline_size", 10)
	fx = Control.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(fx)

	# Belt of active items with cooldown bars
	var bp := UI.panel(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 0, 6)
	var bf := UI.flow(4)
	bp.add_child(bf)
	v.add_child(bp)
	for x in s.items:
		var tile := UI.panel(Color("#111111"), GameData.tier_colors[x.d.tier], 2, 6, 0)
		tile.custom_minimum_size = Vector2(38, 38)
		tile.tooltip_text = x.d.n
		var l := UI.lbl(x.d.ic, 19)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tile.add_child(l)
		var bar := ColorRect.new()
		bar.color = UI.GOLD
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.custom_minimum_size = Vector2(0, 4)
		bar.size_flags_vertical = Control.SIZE_SHRINK_END
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tile.add_child(bar)
		bf.add_child(tile)
		belt[x.i.uid] = {"tile": tile, "bar": bar, "x": x}

	var lm := MarginContainer.new()
	lm.add_theme_constant_override("margin_left", 10)
	lm.add_theme_constant_override("margin_top", 4)
	log_lbl = UI.lbl("", 13, Color("#cbd5e1"))
	log_lbl.custom_minimum_size = Vector2(0, 54)
	lm.add_child(log_lbl)
	v.add_child(lm)

	var sp := UI.hbox()
	var sm := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		sm.add_theme_constant_override("margin_" + side, 10)
	sm.add_child(sp)
	v.add_child(sm)
	for k in [1, 3, 10]:
		var kk: int = k
		sp.add_child(UI.btn("%d×" % k, func(): speed = kk))
	sp.add_child(UI.btn("Skip ⏭", _skip))
	_refresh()
	return self


func _bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 14)
	b.max_value = 1.0
	b.value = 1.0
	b.add_theme_stylebox_override("fill", UI.box(col, col, 0, 3, 0))
	return b


func _sprite(icon: String, fs: int, ax: float) -> Label:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = ax
	holder.anchor_right = ax
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_top = -30 - fs * 1.25
	holder.offset_bottom = -30
	holder.offset_right = fs * 1.4
	world.add_child(holder)
	var l := UI.lbl(icon, fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(fs * 1.4, fs * 1.25)
	l.pivot_offset = l.size / 2
	holder.add_child(l)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "position:y", -5.0, 0.65).set_trans(Tween.TRANS_SINE)
	tw.tween_property(l, "position:y", 0.0, 0.65).set_trans(Tween.TRANS_SINE)
	return l


func _draw_stage() -> void:
	var s := stage.size
	var sky := 0.62
	stage.draw_rect(Rect2(0, 0, s.x, s.y * sky), Color("#26365c"))
	stage.draw_rect(Rect2(0, 0, s.x, s.y * 0.25), Color("#1c2a4d"))
	stage.draw_rect(Rect2(0, s.y * sky, s.x, s.y * (1 - sky)), Color("#3d3029"))
	stage.draw_rect(Rect2(0, s.y * 0.8, s.x, s.y * 0.2), Color("#241b17"))
	if sim and sim.tk > CombatSim.FATIGUE_TICK and not sim.done:
		stage.draw_rect(Rect2(Vector2.ZERO, s), Color(0.9, 0.2, 0.25, 0.18))


func _process(delta: float) -> void:
	if sim == null:
		return
	if sim.done:
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


func _skip() -> void:
	speed = 99
	sim.skip_to_end()
	_refresh()
	_on_end(sim.won)


func _handle(evs: Array) -> void:
	var quiet := speed > 3
	for ev in evs:
		match ev.t:
			"num":
				if not quiet or fx.get_child_count() < 10:
					_float(ev.side, ev.text, ev.col, ev.big)
			"pulse":
				if belt.has(ev.uid):
					var t: Control = belt[ev.uid].tile
					t.pivot_offset = t.size / 2
					var tw := t.create_tween()
					tw.tween_property(t, "scale", Vector2(1.25, 1.25), 0.1)
					tw.tween_property(t, "scale", Vector2.ONE, 0.15)
			"hit":
				_hit_anim(ev, quiet)
			"foe_atk":
				if not quiet:
					_lunge(foe, -70)
				var r := snappedf(ev.dm - ev.ab, 0.1)
				_flash(hero)
				_float("hero", "BLOCK" if r <= 0 else "-" + GameData._num(r), Color("#7dd3fc") if r <= 0 else Color("#ff5a5f"), false)
				if r >= 8:
					_shake()
			"end":
				_on_end(ev.win)
	stage.queue_redraw()


func _hit_anim(ev: Dictionary, quiet: bool) -> void:
	var col: Color = GameData.elem_colors.get(ev.dt, Color.WHITE)
	var txt: String
	if ev.m < 1:
		txt = "🛡" + GameData._num(ev.v)
		col = Color("#9ca3af")
	else:
		txt = ("✦" if ev.m > 1 else "") + GameData._num(ev.v)
		if ev.m > 1:
			col = Color("#ffe14a")
	if quiet:
		_flash(foe)
		_float("foe", txt, col, ev.m > 1)
		return
	if ev.melee:
		_lunge(hero, 70)
	else:
		_projectile(ev.icon)
	var cb := func():
		_flash(foe)
		_float("foe", txt, col, ev.m > 1)
		if ev.v >= 12:
			_shake()
	create_tween().tween_callback(cb).set_delay(0.11 if ev.melee else 0.25)


func _lunge(l: Label, dx: float) -> void:
	var tw := l.create_tween()
	tw.tween_property(l, "position:x", dx, 0.11)
	tw.tween_property(l, "position:x", 0.0, 0.17)


func _flash(l: Label) -> void:
	var tw := l.create_tween()
	l.modulate = Color(1, 0.35, 0.35)
	tw.tween_property(l, "modulate", Color.WHITE, 0.18)


func _projectile(icon: String) -> void:
	var p := UI.lbl(icon, 26)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(p)
	var y := stage.size.y - 110
	p.position = Vector2(stage.size.x * 0.24, y)
	p.pivot_offset = Vector2(14, 14)
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "position:x", stage.size.x * 0.70, 0.25)
	tw.tween_property(p, "rotation", TAU, 0.25)
	tw.chain().tween_callback(p.queue_free)


func _float(side: String, text: String, col: Color, big: bool) -> void:
	var l := UI.lbl(text, 20 if big else 15, col, true)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(l)
	var x0 := (0.14 if side == "hero" else 0.66) + randf() * 0.1
	l.position = Vector2(stage.size.x * x0, stage.size.y - 110 - randf() * 30)
	l.pivot_offset = Vector2(20, 10)
	l.scale = Vector2(0.6, 0.6)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.2, 1.2), 0.12)
	tw.parallel().tween_property(l, "position:y", l.position.y - 54, 0.85)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.85).set_delay(0.3)
	tw.tween_callback(l.queue_free)


func _shake() -> void:
	if _shake_tw and _shake_tw.is_running():
		return
	_shake_tw = world.create_tween()
	for o in [Vector2(-4, 2), Vector2(4, -3), Vector2(-3, -2), Vector2(3, 2), Vector2.ZERO]:
		_shake_tw.tween_property(world, "position", o, 0.05)


func _on_end(won: bool) -> void:
	if _end_wait > 0:
		return
	_end_wait = 1.6
	var dead := foe if won else hero
	var tw := dead.create_tween().set_parallel()
	tw.tween_property(dead, "rotation", deg_to_rad(80), 0.9)
	tw.tween_property(dead, "modulate:a", 0.0, 0.9)
	var ban := UI.lbl("VICTORY!" if won else "DEFEAT", 40, Color("#ffe14a") if won else Color("#ff5a5f"), true)
	ban.add_theme_color_override("font_outline_color", Color.BLACK)
	ban.add_theme_constant_override("outline_size", 10)
	ban.set_anchors_preset(Control.PRESET_FULL_RECT)
	ban.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ban.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(dim)
	stage.add_child(ban)
	ban.pivot_offset = stage.size / 2
	ban.scale = Vector2(2.2, 2.2)
	ban.create_tween().tween_property(ban, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)


func _refresh() -> void:
	var pp := clampf(sim.php / sim.mhp, 0, 1)
	var ep := clampf(sim.ehp / sim.e.hp, 0, 1)
	php_bar.value = pp
	ehp_bar.value = ep
	php_lbl.text = "%d / %d · %.1fs" % [maxi(0, roundi(sim.php)), roundi(sim.mhp), sim.tk / 10.0]
	ehp_lbl.text = "%d / %d" % [maxi(0, roundi(sim.ehp)), roundi(sim.e.hp)]
	var hs := []
	if sim.blk > 0: hs.append("🛡️ %d" % roundi(sim.blk))
	if sim.ht > 0: hs.append("⚡+%d%%" % roundi(sim.hv * 100))
	hero_status.text = "  ".join(hs)
	var es := []
	if sim.s.burn > 0: es.append("🔥" + GameData._num(sim.s.burn))
	if sim.s.pois > 0: es.append("☠️" + GameData._num(sim.s.pois))
	if sim.s.chill > 0: es.append("❄️")
	if sim.s.frz > 0: es.append("🧊")
	if sim.e.tr != "": es.append(GameData.traits[sim.e.tr].ic)
	foe_status.text = " ".join(es)
	foe.self_modulate = Color("#9be7ff") if sim.s.frz > 0 else Color("#cfefff") if sim.s.chill > 0 else Color.WHITE
	for uid in belt:
		var b: Dictionary = belt[uid]
		var x: Dictionary = b.x
		var ratio := 0.0
		if x.d.type == "heal":
			ratio = 0.0 if x.used else 1.0
			if x.used:
				b.tile.modulate.a = 0.4
		else:
			ratio = clampf(x.t / maxf(1.0, x.cdT), 0, 1)
		b.bar.custom_minimum_size.x = 34.0 * ratio
	var lines := sim.log_lines.slice(0, 3)
	log_lbl.text = "\n".join(lines)
