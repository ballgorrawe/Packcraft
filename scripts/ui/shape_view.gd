class_name ShapeView
extends Control
## Draws an item's polyomino (optionally with its icon). Used for cards, the inspector and the drag ghost.

var id := ""
var rot := 0
var cell := 12.0
var show_icon := false
var tint := Color(1, 1, 1, 1)
var origin_offset := Vector2.ZERO   # pixel position of shape cell (0,0)


func setup(item_id: String, rotation_steps: int, cell_px: float, icon := false) -> ShapeView:
	id = item_id
	rot = rotation_steps
	cell = cell_px
	show_icon = icon
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relayout()
	return self


func set_rot(r: int) -> void:
	rot = r
	_relayout()


func _relayout() -> void:
	if id == "":
		return
	var pts: Array = GameData.shape(id, rot).c
	var mx := Vector2i(0, 0)
	for p in pts:
		mx = Vector2i(maxi(mx.x, p.x), maxi(mx.y, p.y))
	origin_offset = Vector2.ZERO
	custom_minimum_size = Vector2(mx + Vector2i.ONE) * cell
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	if id == "":
		return
	var cs: Array = GameData.shape(id, rot).c
	var c: Color = GameData.tier_color(id)
	var pad := maxf(1.0, cell * 0.06)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c.lerp(Color.WHITE, 0.15) * tint
	sb.border_color = c.darkened(0.35) * tint
	sb.set_border_width_all(maxi(1, int(cell / 18)))
	sb.set_corner_radius_all(int(cell * 0.18))
	for p in cs:
		var r := Rect2(origin_offset + Vector2(p) * cell + Vector2(pad, pad) * 0.5, Vector2(cell - pad, cell - pad))
		if cs.has(p + Vector2i(1, 0)): r = r.grow_side(SIDE_RIGHT, pad)
		if cs.has(p + Vector2i(0, 1)): r = r.grow_side(SIDE_BOTTOM, pad)
		draw_style_box(sb, r)
	if show_icon:
		var m := GameData.mid_cell(id, rot)
		_center_text(GameData.items[id].ic, Rect2(origin_offset + Vector2(m) * cell, Vector2(cell, cell)), cell * 0.6, Color(1, 1, 1, tint.a))


func _center_text(t: String, r: Rect2, fs: float, col: Color) -> void:
	var f: Font = UI.font if UI.font else get_theme_default_font()
	var sz := int(fs)
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var asc := f.get_ascent(sz)
	var desc := f.get_descent(sz)
	draw_string(f, Vector2(r.position.x + (r.size.x - w) / 2.0, r.position.y + (r.size.y + asc - desc) / 2.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
