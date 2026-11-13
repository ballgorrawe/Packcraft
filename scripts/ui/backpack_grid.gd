class_name BackpackGrid
extends Control
## The 9x7 master grid: unlocked tiles, placed items, Golden Links (recipes and evolutions) and drag previews.
## Items ease toward their cell (main.anim) and squash when they land (main.pops), so moves feel physical.

signal cell_pressed(cell: Vector2i)

var main: Node
var cell := 48.0
var _t := 0.0
var _idle := 0.0


func setup(m: Node, cell_px: float) -> BackpackGrid:
	main = m
	cell = cell_px
	custom_minimum_size = Vector2(GameData.W, GameData.H) * cell
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func _process(delta: float) -> void:
	_t += delta
	var run: RunState = main.run
	if run != null:
		var k := 1.0 - exp(-delta * 16.0)
		for it in run.grid_items():
			var target := Vector2(it.x, it.y)
			var cur: Vector2 = main.anim.get(it.uid, target)
			cur = cur.lerp(target, k)
			if cur.distance_to(target) < 0.01:
				main.anim.erase(it.uid)
			else:
				main.anim[it.uid] = cur
	# redraw every frame only while something moves (items sliding, a drag, a squash); otherwise the
	# glows and pulses look the same at ~15 redraws a second, which saves most of the pack's cost
	var busy: bool = not main.anim.is_empty() or main.drag_item != null or main.pops.values().any(func(p): return p < 0.4)
	_idle += delta
	if busy or _idle >= 1.0 / 15.0:
		_idle = 0.0
		queue_redraw()


func cell_at(global_pos: Vector2) -> Vector2i:
	var p: Vector2 = get_global_transform().affine_inverse() * global_pos
	return Vector2i(floori(p.x / cell), floori(p.y / cell))


func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * cell, Vector2(cell, cell))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var c := Vector2i(floori(event.position.x / cell), floori(event.position.y / cell))
		if c.x >= 0 and c.y >= 0 and c.x < GameData.W and c.y < GameData.H:
			cell_pressed.emit(c)
			accept_event()


func _draw() -> void:
	var run: RunState = main.run
	if run == null:
		return
	run.calc()
	var morning := run.phase == "morning"
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)

	# tiles
	var tile := UI.px_frame(run.dress().slot_bg, run.dress().slot_bd, 0, 0)   # pixel slot (mastery pack theme)
	for y in GameData.H:
		for x in GameData.W:
			var c := Vector2i(x, y)
			var r := cell_rect(c).grow(-3)
			if run.tiles.has(c):
				draw_style_box(tile, r)
			elif morning and run.can_unlock(c):
				draw_style_box(UI.px_frame(Color("#1c3a16"), UI.GOOD, 0, 0), r.grow(-1 + 2 * pulse))
				_text("+", r, cell * 0.55, Color(1, 1, 1, 0.95))
			else:
				draw_rect(r.grow(-6), Color(1, 1, 1, 0.025))

	# drag preview data
	var h: PItem = main.drag_item
	var pre := {}
	var pv := {}
	var ok := false
	var swap := false   # lands on items that will move aside
	var partners := {}
	if h != null:
		for rc in GameData.recipes:
			if not run.recipe_ok(rc):
				continue
			var parts := [rc.a, rc.b] + ([rc.c] if rc.get("c", "") != "" else [])
			if not parts.has(h.id):
				continue
			var others := parts.duplicate()
			others.erase(h.id)
			for i in run.grid_items():
				if others.has(i.id) and i != h:
					partners[i.uid] = true
		var hc: Vector2i = main.hover_cell
		if hc.x >= 0:
			var a := run.anchor_for(h, hc)
			pre = run.preview(h, a.x, a.y)
			ok = pre.ok
			swap = not ok and run.on_tiles(h.id, h.rot, a)
			for sc in GameData.shape(h.id, h.rot).c:
				pv[a + sc] = true

	# preview of the held item (under the items so neighbours stay readable)
	if h != null and not pv.is_empty():
		for k in pv:
			var r := cell_rect(k).grow(-3)
			var s := StyleBoxFlat.new()
			var pc: Color = UI.GOOD if ok else (UI.AC if swap else UI.BAD)
			s.bg_color = Color(pc, 0.3)
			s.border_color = pc
			s.set_border_width_all(3)
			s.set_corner_radius_all(10)
			draw_style_box(s, r)

	# links
	var linked := {}
	for l in run.links():
		if not run.off.has(l.key):
			linked[l.a.uid] = true
			linked[l.b.uid] = true
			if l.get("c") != null:
				linked[l.c.uid] = true

	# who sits on which cell (for the aura arrows)
	var occ := {}
	for it in run.grid_items():
		for c in it.cells():
			occ[c] = it

	# items
	for it in run.grid_items():
		var col: Color = GameData.tier_color(it.id)
		var base: Vector2 = main.anim.get(it.uid, Vector2(it.x, it.y))
		var shp: Array = GameData.shape(it.id, it.rot).c
		var m := GameData.mid_cell(it.id, it.rot)
		var center := (base + Vector2(m) + Vector2(0.5, 0.5)) * cell
		var t: float = main.pops.get(it.uid, 9.0)
		var sq := 1.0
		if t < 0.35:
			sq = 1.0 + 0.16 * sin(t / 0.35 * PI) * (1.0 - t / 0.35)
		draw_set_transform(center, 0.0, Vector2(sq, 2.0 - sq))
		var body := StyleBoxFlat.new()
		# dark iron body tinted by rarity, with a bright rarity rim: the icon stands out
		body.bg_color = Color("#1a130e").lerp(col, 0.42)
		body.border_color = col.lightened(0.05)
		body.set_border_width_all(2)
		body.border_width_bottom = 5
		body.set_corner_radius_all(int(cell * 0.2))
		var shine := StyleBoxFlat.new()
		shine.bg_color = Color(1, 1, 1, 0.14)
		shine.set_corner_radius_all(int(cell * 0.16))

		for c in shp:
			var r := Rect2((base + Vector2(c)) * cell - center, Vector2(cell, cell)).grow(-4)
			var g := Rect2(r)
			if shp.has(c + Vector2i(1, 0)): g = g.grow_side(SIDE_RIGHT, 4.5)
			if shp.has(c + Vector2i(-1, 0)): g = g.grow_side(SIDE_LEFT, 4.5)
			if shp.has(c + Vector2i(0, 1)): g = g.grow_side(SIDE_BOTTOM, 4.5)
			if shp.has(c + Vector2i(0, -1)): g = g.grow_side(SIDE_TOP, 4.5)
			draw_style_box(body, g)
			draw_style_box(shine, Rect2(r.position + Vector2(4, 3), Vector2(r.size.x - 8, r.size.y * 0.32)))
		var tier: int = it.def().tier
		for c in shp:
			var r := Rect2((base + Vector2(c)) * cell - center, Vector2(cell, cell)).grow(-4)
			if linked.has(it.uid):
				draw_rect(r.grow(1), Color(UI.GOLD, 0.45 + 0.5 * pulse), false, 3.5)
			if tier >= 4:
				draw_rect(r, Color(col.lightened(0.4), 0.14 * pulse))
			if pre.has("bf") and pre.bf.has(it.uid):
				draw_rect(r.grow(-3), UI.STAR, false, 3.5)
			if partners.has(it.uid):
				draw_rect(r.grow(2), Color(UI.GOLD, 0.6 + 0.4 * pulse), false, 3.0)
			if main.selected == it:
				draw_rect(r.grow(2), Color.WHITE, false, 3.0)
		_text(it.def().ic, Rect2(-cell / 2, -cell / 2, cell, cell), cell * 0.6, Color.WHITE)
		if it.def().bd != "":
			_text(it.def().bd, Rect2(cell * 0.02, -cell / 2, cell * 0.48, cell * 0.48), cell * 0.32, Color.WHITE)   # top-right: the other corners mark buffs, relics and links
		if it.def().relic:
			_text("✨", Rect2(-cell / 2, -cell / 2, cell * 0.45, cell * 0.45), cell * 0.28, UI.GOLD)
		if linked.has(it.uid):
			_text("✨", Rect2(cell * 0.05, -cell / 2, cell * 0.45, cell * 0.45), cell * 0.28 * (0.8 + 0.3 * pulse), UI.GOLD)
		_aura_marks(it, shp, base, center, occ, pulse)
		draw_set_transform(Vector2.ZERO)

	# 🪄 hint: a blue outline (and a faint icon) where each item should go; 📤 on items headed to storage
	if morning and main.has_method("hint_moves"):
		var hc := Color(0.49, 0.83, 0.99, 0.75 + 0.25 * pulse)
		for e in main.hint_moves():
			var it: PItem = e[0]
			if e[1] == "storage":
				if it.loc == "grid":
					var mc := Vector2i(it.x, it.y) + GameData.mid_cell(it.id, it.rot)
					_text("📤", cell_rect(mc).grow(-cell * 0.3).grow_individual(cell * 0.3, -cell * 0.1, 0, cell * 0.1), cell * 0.32, Color.WHITE)
				continue
			for sc in GameData.shape(it.id, e[4]).c:
				var hr := cell_rect(Vector2i(e[2], e[3]) + sc).grow(-5)
				draw_rect(hr, Color(hc, 0.18))
				draw_rect(hr, hc, false, 4.5)
			var gm := Vector2i(e[2], e[3]) + GameData.mid_cell(it.id, e[4])
			_text(it.def().ic, cell_rect(gm), cell * 0.46, Color(1, 1, 1, 0.7))


## Aura items: a corner badge with the tag they buff, and a green arrow on every side that touches
## an item they are buffing right now. Buffed items get a small green triangle in the other corner.
func _aura_marks(it: PItem, shp: Array, base: Vector2, center: Vector2, occ: Dictionary, pulse: float) -> void:
	var d: Dictionary = it.def()
	var mid := GameData.mid_cell(it.id, it.rot)
	var mr := Rect2((base + Vector2(mid)) * cell - center, Vector2(cell, cell)).grow(-4)
	var bs := cell * 0.36
	if not d.adj.is_empty():
		var br := Rect2(mr.position + Vector2(1, mr.size.y - bs - 1), Vector2(bs, bs))
		draw_circle(br.get_center(), bs * 0.5, Color("#1f1a15"))
		draw_arc(br.get_center(), bs * 0.5, 0, TAU, 20, Color("#d9c49a"), 2.0)
		_text(GameData.tag_icon(d.adj[0].tag), br, bs * 0.62, Color.WHITE)
		var arrow_col := Color(UI.GOOD, 0.7 + 0.3 * pulse)
		for c in shp:
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if shp.has(c + dv):
					continue
				var o = occ.get(Vector2i(it.x, it.y) + c + dv)
				if o == null or o == it:
					continue
				if not d.adj.any(func(bf): return o.def().tags.has(bf.tag)):
					continue
				var cr := Rect2((base + Vector2(c)) * cell - center, Vector2(cell, cell))
				var dir := Vector2(dv)
				var tip := cr.get_center() + dir * (cell * 0.5 + 3)
				var side := Vector2(-dir.y, dir.x) * cell * 0.13
				var back := tip - dir * cell * 0.17
				draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), arrow_col)
	var buffed := false
	for k in it.b:
		if float(it.b[k]) > 0:
			buffed = true
			break
	if buffed:
		var rr := Rect2(mr.position + Vector2(mr.size.x - bs - 1, mr.size.y - bs - 1), Vector2(bs, bs))
		draw_circle(rr.get_center(), bs * 0.5, Color("#14532d"))
		# drawn, not a text glyph: the web build has no font with a triangle in it
		var cc := rr.get_center()
		var tr_ := bs * 0.26
		draw_colored_polygon(PackedVector2Array([cc + Vector2(0, -tr_), cc + Vector2(tr_ * 1.05, tr_ * 0.75), cc + Vector2(-tr_ * 1.05, tr_ * 0.75)]), UI.GOOD)


func _text(t: String, r: Rect2, fs: float, col: Color) -> void:
	var f: Font = UI.font if UI.font else get_theme_default_font()
	var sz := int(fs)
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var asc := f.get_ascent(sz)
	var desc := f.get_descent(sz)
	draw_string(f, Vector2(r.position.x + (r.size.x - w) / 2.0, r.position.y + (r.size.y + asc - desc) / 2.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
