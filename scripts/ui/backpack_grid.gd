class_name BackpackGrid
extends Control
## The 9x7 master grid: unlocked tiles, placed items, Golden Links (recipes and evolutions) and drag previews.

signal cell_pressed(cell: Vector2i)

var main: Node
var cell := 48.0
var _t := 0.0


func setup(m: Node, cell_px: float) -> BackpackGrid:
	main = m
	cell = cell_px
	custom_minimum_size = Vector2(GameData.W, GameData.H) * cell
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func _process(delta: float) -> void:
	_t += delta
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
	for y in GameData.H:
		for x in GameData.W:
			var c := Vector2i(x, y)
			var r := cell_rect(c).grow(-2)
			if run.tiles.has(c):
				draw_rect(r, UI.PN2.lerp(UI.BD, 0.45))
			elif morning and run.can_unlock(c):
				draw_rect(r, Color(UI.GOOD, 0.12 + 0.18 * pulse))
				draw_rect(r, Color(UI.GOOD, 0.7), false, 2.0)
				_text("+", r, cell * 0.5, Color(UI.GOOD, 0.9))
			else:
				draw_rect(r, Color(UI.BD, 0.3), false, 1.0)

	# drag preview data
	var h: PItem = main.drag_item
	var pre := {}
	var pv := {}
	var ok := false
	var partners := {}
	if h != null:
		for rc in GameData.recipes:
			if not run.recipe_ok(rc):
				continue
			var q := ""
			if h.id == rc.a:
				q = rc.b
			elif h.id == rc.b:
				q = rc.a
			if q != "":
				for i in run.grid_items():
					if i.id == q and i != h:
						partners[i.uid] = true
		var hc: Vector2i = main.hover_cell
		if hc.x >= 0:
			var a := run.anchor_for(h, hc)
			pre = run.preview(h, a.x, a.y)
			ok = pre.ok
			for sc in GameData.shape(h.id, h.rot).c:
				pv[a + sc] = true

	# links
	var linked := {}
	for l in run.links():
		if not run.off.has(l.key):
			linked[l.a.uid] = true
			linked[l.b.uid] = true

	# items
	for it in run.grid_items():
		var col: Color = GameData.tier_color(it.id)
		var cells: Array = it.cells()
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.25)
		sb.border_color = col.lightened(0.15)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(cell * 0.18))
		for c in cells:
			var r := cell_rect(c).grow(-3)
			# merge into neighbouring cells of the same item so shapes read as one piece
			var g := Rect2(r)
			if cells.has(c + Vector2i(1, 0)): g = g.grow_side(SIDE_RIGHT, 3.5)
			if cells.has(c + Vector2i(-1, 0)): g = g.grow_side(SIDE_LEFT, 3.5)
			if cells.has(c + Vector2i(0, 1)): g = g.grow_side(SIDE_BOTTOM, 3.5)
			if cells.has(c + Vector2i(0, -1)): g = g.grow_side(SIDE_TOP, 3.5)
			draw_style_box(sb, g)
		var tier: int = it.def().tier
		for c in cells:
			var r := cell_rect(c).grow(-3)
			if linked.has(it.uid):
				draw_rect(r, Color(UI.GOLD, 0.35 + 0.5 * pulse), false, 3.0)
			if tier >= 3:
				draw_rect(r, Color(col, 0.18 * pulse))
			if pre.has("bf") and pre.bf.has(it.uid):
				draw_rect(r.grow(-3), UI.STAR, false, 3.0)
			if partners.has(it.uid):
				draw_rect(r.grow(-1), Color(UI.GOLD, 0.6 + 0.4 * pulse), false, 2.0)
			if main.selected == it:
				draw_rect(r.grow(1), Color.WHITE, false, 2.5)
		var m := GameData.mid_cell(it.id, it.rot)
		_text(it.def().ic, cell_rect(Vector2i(it.x, it.y) + m), cell * 0.55, Color.WHITE)
		if it.def().relic:
			_text("✨", Rect2(cell_rect(Vector2i(it.x, it.y) + m).position, Vector2(cell * 0.4, cell * 0.4)), cell * 0.25, UI.GOLD)

	# preview of the held item
	if h != null and not pv.is_empty():
		for k in pv:
			var r := cell_rect(k).grow(-2)
			draw_rect(r, Color(UI.GOOD if ok else UI.BAD, 0.25))
			draw_rect(r, UI.GOOD if ok else UI.BAD, false, 2.5)


func _text(t: String, r: Rect2, fs: float, col: Color) -> void:
	var f: Font = UI.font if UI.font else get_theme_default_font()
	var sz := int(fs)
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var asc := f.get_ascent(sz)
	var desc := f.get_descent(sz)
	draw_string(f, Vector2(r.position.x + (r.size.x - w) / 2.0, r.position.y + (r.size.y + asc - desc) / 2.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
