extends SceneTree
## Item art preview: each it_<id> sprite on its own bag cells (and turned 90 degrees), 3x.
## godot --headless --path . --script res://tools/dev/item_preview.gd -- <out.png> <item id>...
const C := 32
const Z := 3


func _initialize() -> void:
	GameData.ensure_loaded()
	Sprites.has("")   # loads data/sprites.json
	var a := OS.get_cmdline_user_args()
	var ids: Array = a.slice(1)
	var row_h := 3 * C + 16
	var out := Image.create(8 * C * Z, (row_h * ids.size() + 8) * Z, false, Image.FORMAT_RGBA8)
	out.fill(Color("#2b211b"))
	var y := 8
	for id in ids:
		var it: Dictionary = GameData.items[id]
		var cells: Array = it.c
		var w := 1
		var h := 1
		for c in cells:
			w = maxi(w, int(c[0]) + 1)
			h = maxi(h, int(c[1]) + 1)
		var img: Image = Sprites.raster(Sprites._data.sprites["it_" + id], Sprites._data.palette, w * C, h * C)
		_put(out, img, cells, 8, y)
		var rot: Image = img.duplicate()
		rot.rotate_90(CLOCKWISE)
		var rc := cells.map(func(c): return [h - 1 - int(c[1]), int(c[0])])
		_put(out, rot, rc, 8 + (w + 1) * C, y)
		y += row_h
	out.save_png(a[0])
	print("saved")
	quit()


func _put(out: Image, img: Image, cells: Array, x0: int, y0: int) -> void:
	for c in cells:   # the bag cells under the item
		for yy in range(2, C - 2):
			for xx in range(2, C - 2):
				_px(out, x0 + int(c[0]) * C + xx, y0 + int(c[1]) * C + yy, Color("#1b1713"))
	for yy in img.get_height():
		for xx in img.get_width():
			var col := img.get_pixel(xx, yy)
			if col.a > 0:
				_px(out, x0 + xx, y0 + yy, col)


func _px(out: Image, x: int, y: int, col: Color) -> void:
	for dy in Z:
		for dx in Z:
			out.set_pixel(x * Z + dx, y * Z + dy, col)
