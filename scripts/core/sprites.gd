class_name Sprites
extends RefCounted
## 32x32 pixel sprites drawn from shapes in data/sprites.json: ellipses, rectangles and polygons in a
## shared palette, rasterised at pixel centres, then lit top-left, shaded bottom-right and outlined.
## A sprite may use the slots "A" (main colour), "a" (its dark) and "C" (accent); a class's look and
## its mastery skins fill them (data "looks"). Hand-written shapes, no image files.

const N := 32
static var _data := {}
static var _cache := {}


static func _load() -> void:
	if _data.is_empty() and FileAccess.file_exists("res://data/sprites.json"):
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprites.json"))


static func has(id: String) -> bool:
	_load()
	return _data.get("sprites", {}).has(id)


## The sprite as a texture (nearest-filter it when scaling), or null if there is none.
## skin: index into the class's "looks" (0 = the class's own colours).
static func tex(id: String, skin := 0) -> Texture2D:
	var key := "%s#%d" % [id, skin]
	if _cache.has(key):
		return _cache[key]
	if not has(id):
		return null
	var pal: Dictionary = _data.palette.duplicate()
	var looks: Array = _data.get("looks", {}).get(id, [])
	if not looks.is_empty():
		pal.merge(looks[clampi(skin, 0, looks.size() - 1)], true)
	_cache[key] = ImageTexture.create_from_image(raster(_data.sprites[id], pal))
	return _cache[key]


## A hero in a class's look (Mastery.look: skin -1 plain, 0 / 1 the mastery skins).
static func hero(cls: String, look: Dictionary) -> Texture2D:
	return tex("hero_" + cls, int(look.get("skin", -1)) + 1)


## A monster or boss by its name ("Elite Goblin" draws the Goblin); null if it has no sprite.
static func foe(name: String) -> Texture2D:
	var snake := name.replace("Elite ", "").replace("Ambusher ", "").to_lower().replace(" ", "_").replace("'", "")
	for pre in ["elite_", "boss_", "foe_"]:
		if has(pre + snake):
			return tex(pre + snake)
	return null


## A bitmap font whose glyphs are the sprites in data "glyphs" (emoji codepoint hex -> sprite id).
## Put it before the emoji fonts in a fallback chain and those emoji draw as pixel art everywhere.
static func glyph_font() -> FontFile:
	_load()
	var gl: Dictionary = _data.get("glyphs", {})
	var ff := FontFile.new()
	ff.fixed_size = N
	ff.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var sz := Vector2i(N, 0)
	var atlas := Image.create(N * maxi(gl.size(), 1), N, false, Image.FORMAT_RGBA8)
	var i := 0
	for hex in gl:
		var t := tex(gl[hex])
		if t == null:
			continue
		atlas.blit_rect(t.get_image(), Rect2i(0, 0, N, N), Vector2i(i * N, 0))
		var cp: int = str(hex).hex_to_int()
		ff.set_glyph_advance(0, N, cp, Vector2(N + 2, 0))
		ff.set_glyph_offset(0, sz, cp, Vector2(1, -N + 5))
		ff.set_glyph_size(0, sz, cp, Vector2(N, N))
		ff.set_glyph_uv_rect(0, sz, cp, Rect2(i * N, 0, N, N))
		ff.set_glyph_texture_idx(0, sz, cp, 0)
		i += 1
	ff.set_texture_image(0, sz, 0, atlas)
	ff.set_cache_ascent(0, N, N - 5)
	ff.set_cache_descent(0, N, 5)
	return ff


static func _hit(op: Array, p: Vector2) -> bool:
	match op[0]:
		"ell": return pow((p.x - op[1]) / op[3], 2) + pow((p.y - op[2]) / op[4], 2) <= 1.0
		"rect": return p.x >= op[1] and p.x < op[1] + op[3] and p.y >= op[2] and p.y < op[2] + op[4]
		"poly":
			var pts := PackedVector2Array()
			for q in op[1]:
				pts.append(Vector2(q[0], q[1]))
			return Geometry2D.is_point_in_polygon(p, pts)
		"px": return int(p.x) == int(op[1]) and int(p.y) == int(op[2])
	return false


static func raster(ops: Array, pal: Dictionary, w := N, h := N) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for op in ops:
		var col := Color(pal.get(op[-1], "#ff00ff"))
		for y in h:
			for x in w:
				if _hit(op, Vector2(x + 0.5, y + 0.5)):
					img.set_pixel(x, y, col)
	var clear := Color(0, 0, 0, 0)
	# volume: light on top-left edges, shade on bottom-right edges
	var src: Image = img.duplicate()
	for y in h:
		for x in w:
			var c: Color = src.get_pixel(x, y)
			if c.a == 0:
				continue
			var ul: Color = src.get_pixel(x - 1, y - 1) if x > 0 and y > 0 else clear
			var dr: Color = src.get_pixel(x + 1, y + 1) if x < w - 1 and y < h - 1 else clear
			if ul.a == 0:
				img.set_pixel(x, y, c.lightened(0.15))
			elif dr.a == 0:
				img.set_pixel(x, y, c.darkened(0.25))
	# one dark outline around the whole shape
	var out: Image = img.duplicate()
	var line := Color(pal.get("K", "#24161c"))
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0:
				continue
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + dv
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and img.get_pixelv(q).a > 0:
					out.set_pixel(x, y, line)
					break
	return out
