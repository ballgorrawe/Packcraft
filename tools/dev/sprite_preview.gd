extends SceneTree
## Preview sheet of data/sprites.json: every sprite (prefix filter) at 4x, with its skins in a row.
## godot --headless --path . --script <this> -- <out.png> <prefix>
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprites.json"))
	var ids: Array = d.sprites.keys().filter(func(k): return k.begins_with(a[1]))
	var sc := 4
	var cell := 32 * sc + 12
	var cols := 0
	for id in ids:
		cols = maxi(cols, maxi(1, d.get("looks", {}).get(id, []).size()))
	var sheet := Image.create(cell * cols * mini(ids.size(), 3) + 12, cell * ceili(ids.size() / 3.0) + 12, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#3a2818"))
	for i in ids.size():
		var n := maxi(1, d.get("looks", {}).get(ids[i], []).size())
		for s in n:
			var img := Sprites.tex(ids[i], s).get_image()
			img.resize(32 * sc, 32 * sc, Image.INTERPOLATE_NEAREST)
			sheet.blend_rect(img, Rect2i(0, 0, 32 * sc, 32 * sc), Vector2i(12 + ((i % 3) * cols + s) * cell, 12 + (i / 3) * cell))
	sheet.save_png(a[0])
	print("ids: ", ", ".join(ids))
	quit()
