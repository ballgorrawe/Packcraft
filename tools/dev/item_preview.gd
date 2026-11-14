extends SceneTree
## Item art preview sheet: each item's art on its bag cells, packed in rows, 2x.
## godot --headless --path . --script res://tools/dev/item_preview.gd -- <out.png> <item id or tag>...
## Add --turn to also show each item turned 90 degrees.
const C := 32
const Z := 2
const ROW := 14   # cells per row


func _initialize() -> void:
	GameData.ensure_loaded()
	var a := OS.get_cmdline_user_args()
	var turn := a.has("--turn")
	var ids: Array = []
	for k in a.slice(1):
		if k == "--turn":
			continue
		if GameData.items.has(k):
			ids.append(k)
		else:   # a tag: every item with art that has it
			for id in GameData.items:
				if GameData.items[id].tags.has(k) and Sprites.item(id) != null:
					ids.append(id)
	var pics := []
	for id in ids:
		for r in ([0, 1] if turn else [0]):
			if Sprites.item(id, r) != null:
				pics.append([Sprites.item(id, r).get_image(), GameData.shape(id, r).c])
	# pack left to right
	var x := 0
	var y := 0
	var row_h := 0
	var spots := []
	for p in pics:
		var w: int = p[0].get_width() / C
		var h: int = p[0].get_height() / C
		if x + w > ROW:
			x = 0
			y += row_h + 1
			row_h = 0
		spots.append(Vector2i(x, y))
		x += w + 1
		row_h = maxi(row_h, h)
	var out := Image.create((ROW * C + 16) * Z, ((y + row_h) * C + 16) * Z, false, Image.FORMAT_RGBA8)
	out.fill(Color("#2b211b"))
	for i in pics.size():
		_put(out, pics[i][0], pics[i][1], 8 + spots[i].x * C, 8 + spots[i].y * C)
	out.save_png(a[0])
	print("saved ", pics.size())
	quit()


func _put(out: Image, img: Image, cells: Array, x0: int, y0: int) -> void:
	for c in cells:   # the bag cells under the item
		for yy in range(2, C - 2):
			for xx in range(2, C - 2):
				_px(out, x0 + c.x * C + xx, y0 + c.y * C + yy, Color("#1b1713"))
	for yy in img.get_height():
		for xx in img.get_width():
			var col := img.get_pixel(xx, yy)
			if col.a > 0:
				_px(out, x0 + xx, y0 + yy, col)


func _px(out: Image, x: int, y: int, col: Color) -> void:
	for dy in Z:
		for dx in Z:
			out.set_pixel(x * Z + dx, y * Z + dy, col)
