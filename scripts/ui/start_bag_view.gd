class_name StartBagView
extends Control
## A class's starting bag for the hero screen: its unlocked tiles and the starter items in them.

var cls := ""
var cell := 56.0
var _org := Vector2i.ZERO


func setup(class_id: String, cell_px: float) -> StartBagView:
	cls = class_id
	cell = cell_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c: Dictionary = GameData.classes[cls]
	var mn := Vector2i(99, 99)
	var mx := Vector2i(-99, -99)
	for t in c.bag:
		mn = Vector2i(mini(mn.x, int(t[0])), mini(mn.y, int(t[1])))
		mx = Vector2i(maxi(mx.x, int(t[0])), maxi(mx.y, int(t[1])))
	_org = mn
	custom_minimum_size = Vector2(mx - mn + Vector2i.ONE) * cell
	return self


func _draw() -> void:
	var c: Dictionary = GameData.classes[cls]
	var tile := StyleBoxFlat.new()
	tile.bg_color = Color("#1b1713")
	tile.border_color = Color("#3d3329")
	tile.set_border_width_all(2)
	tile.set_corner_radius_all(int(cell * 0.18))
	for t in c.bag:
		draw_style_box(tile, _rect(Vector2i(int(t[0]), int(t[1]))).grow(-3))
	for st in c.st:
		var id: String = st[0]
		var at := Vector2i(int(st[1]), int(st[2]))
		var col: Color = GameData.tier_color(id)
		var body := StyleBoxFlat.new()
		body.bg_color = col.darkened(0.2)
		body.border_color = col.darkened(0.55)
		body.set_border_width_all(2)
		body.border_width_bottom = 5
		body.set_corner_radius_all(int(cell * 0.2))
		var shp: Array = GameData.shape(id, 0).c
		for sc in shp:
			draw_style_box(body, _rect(at + sc).grow(-4))
		var mid := GameData.mid_cell(id, 0)
		var r := _rect(at + mid)
		var f: Font = UI.font if UI.font else get_theme_default_font()
		var fs := int(cell * 0.55)
		var ic: String = GameData.items[id].ic
		var w := f.get_string_size(ic, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(r.position.x + (r.size.x - w) / 2.0, r.position.y + (r.size.y + f.get_ascent(fs) - f.get_descent(fs)) / 2.0), ic, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c - _org) * cell, Vector2(cell, cell))
