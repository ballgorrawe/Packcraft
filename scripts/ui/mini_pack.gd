class_name MiniPack
extends Control
## A monster's pack drawn small (road cards) or live (fight screen: each item shows its charge
## filling up and flashes when it fires, like the player's pack).

var gw := 4
var gh := 3
var cell := 26.0
var entries: Array = []      # [{id, x, y, rot}] or the CombatSim's fi dicts (with p / cd)
var flash := {}              # uid -> seconds since it fired (fight screen)
var live := false
var _t := 0.0


func setup(e: Dictionary, cell_px: float, sim_items: Array = []) -> MiniPack:
	gw = int(e.get("gw", 4))
	gh = int(e.get("gh", 3))
	cell = cell_px
	live = not sim_items.is_empty()
	if live:
		entries = sim_items
	else:
		for it in e.get("items", []):
			entries.append({"id": it[0], "x": int(it[1]), "y": int(it[2]), "rot": int(it[3]) if it.size() > 3 else 0})
	custom_minimum_size = Vector2(gw, gh) * cell
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func _process(delta: float) -> void:
	_t += delta
	for k in flash:
		flash[k] += delta
	if live:
		queue_redraw()


func item_center(uid: int) -> Vector2:
	for x in entries:
		if x.get("uid", 0) == uid:
			var m := GameData.mid_cell(x.id, x.rot)
			return (Vector2(x.x, x.y) + Vector2(m) + Vector2(0.5, 0.5)) * cell
	return size / 2


func _draw() -> void:
	var f: Font = UI.font if UI.font else get_theme_default_font()
	var tile := StyleBoxFlat.new()
	tile.bg_color = Color("#3a1427")
	tile.border_color = Color("#6b2343")
	tile.set_border_width_all(1)
	tile.set_corner_radius_all(int(cell * 0.18))
	for y in gh:
		for x in gw:
			draw_style_box(tile, Rect2(Vector2(x, y) * cell, Vector2(cell, cell)).grow(-1.5))
	for x in entries:
		var d: Dictionary = GameData.items[x.id]
		var cells: Array = GameData.shape(x.id, x.rot).c
		var col := Color("#ff6b81") if d.on.dmg > 0 or not d.on.st.is_empty() else Color("#7dd3fc") if d.on.shield > 0 else Color("#4ade80") if d.on.heal > 0 else Color("#facc15")
		var ratio := 1.0
		var lit := 0.0
		if live and d.cd > 0:
			ratio = clampf(x.p / maxf(0.01, x.cd), 0.0, 1.0)
			lit = clampf(1.0 - flash.get(x.uid, 9.0) / 0.3, 0.0, 1.0)
		var top := 999.0
		var bot := -999.0
		for c in cells:
			top = minf(top, (x.y + c.y) * cell)
			bot = maxf(bot, (x.y + c.y + 1) * cell)
		var level := bot - (bot - top) * ratio
		var dark := StyleBoxFlat.new()
		dark.bg_color = col.darkened(0.75)
		dark.border_color = col.darkened(0.3)
		dark.set_border_width_all(2)
		dark.set_corner_radius_all(int(cell * 0.2))
		var fill := StyleBoxFlat.new()
		fill.bg_color = col.lerp(Color.WHITE, 0.1 + lit * 0.7)
		fill.set_corner_radius_all(int(cell * 0.16))
		for c in cells:
			var r := Rect2(Vector2(x.x + c.x, x.y + c.y) * cell, Vector2(cell, cell)).grow(-2)
			if cells.has(c + Vector2i(1, 0)): r = r.grow_side(SIDE_RIGHT, 2.5)
			if cells.has(c + Vector2i(0, 1)): r = r.grow_side(SIDE_BOTTOM, 2.5)
			draw_style_box(dark, r)
			var y0 := maxf(r.position.y, level)
			if y0 < r.end.y:
				draw_style_box(fill, Rect2(r.position.x + 1, y0, r.size.x - 2, r.end.y - y0 - 1))
			if lit > 0:
				draw_rect(r.grow(2 + lit * 3), Color(1, 1, 1, lit * 0.8), false, 2.5)
		var m := GameData.mid_cell(x.id, x.rot)
		var mc := (Vector2(x.x, x.y) + Vector2(m) + Vector2(0.5, 0.5)) * cell
		var sz := int(cell * 0.6 * (1.0 + lit * 0.4))
		var w := f.get_string_size(d.ic, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string(f, mc + Vector2(-w / 2.0, sz * 0.36), d.ic, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color.WHITE)
