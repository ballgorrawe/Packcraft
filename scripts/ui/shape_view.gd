class_name ShapeView
extends Control
## Draws an item's polyomino (optionally with its icon). Used for cards, the inspector and the drag ghost.

var id := ""
var rot := 0
var cell := 12.0
var show_icon := false
var tint := Color(1, 1, 1, 1)
var origin_offset := Vector2.ZERO   # pixel position of shape cell (0,0)
var icon_px := 0.0                  # icon size in px (0 = 60% of a cell); shop cards draw it bigger


func setup(item_id: String, rotation_steps: int, cell_px: float, icon := false) -> ShapeView:
	id = item_id
	rot = rotation_steps
	cell = cell_px
	show_icon = icon
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	var art := Sprites.item(id, rot)
	var ft := Color(tint, tint.a * 0.4) if art != null else tint   # with art the cells are only a faint footprint
	var pad := maxf(1.0, cell * 0.06)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c.lerp(Color.WHITE, 0.15) * ft
	sb.border_color = c.darkened(0.35) * ft
	sb.set_border_width_all(maxi(1, int(cell / 18)))
	sb.set_corner_radius_all(int(cell * 0.18))
	for p in cs:
		var r := Rect2(origin_offset + Vector2(p) * cell + Vector2(pad, pad) * 0.5, Vector2(cell - pad, cell - pad))
		if cs.has(p + Vector2i(1, 0)): r = r.grow_side(SIDE_RIGHT, pad)
		if cs.has(p + Vector2i(0, 1)): r = r.grow_side(SIDE_BOTTOM, pad)
		draw_style_box(sb, r)
	if art != null:
		var ar := Rect2(origin_offset, art.get_size() / Sprites.N * cell)
		if cs.size() == 1 and icon_px > cell:   # a one-cell item on a shop card: as big as the icon was
			ar = Rect2(ar.get_center() - Vector2(icon_px, icon_px) / 2.0, Vector2(icon_px, icon_px))
		draw_texture_rect(art, ar, false, tint)
	elif show_icon:
		var m := GameData.mid_cell(id, rot)
		var fs := icon_px if icon_px > 0 else cell * 0.6
		_center_text(GameData.items[id].ic, Rect2(origin_offset + Vector2(m) * cell, Vector2(cell, cell)), fs, Color(1, 1, 1, tint.a))
		if GameData.items[id].bd != "":
			_center_text(GameData.items[id].bd, Rect2(origin_offset + Vector2(m) * cell + Vector2(cell * 0.5, cell * 0.5), Vector2(cell * 0.5, cell * 0.5)), fs * 0.45, Color(1, 1, 1, tint.a))


func _center_text(t: String, r: Rect2, fs: float, col: Color) -> void:
	var f: Font = UI.font if UI.font else get_theme_default_font()
	var sz := int(fs)
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var asc := f.get_ascent(sz)
	var desc := f.get_descent(sz)
	draw_string(f, Vector2(r.position.x + (r.size.x - w) / 2.0, r.position.y + (r.size.y + asc - desc) / 2.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
