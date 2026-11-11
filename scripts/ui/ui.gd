class_name UI
extends RefCounted
## Theme, palette and widget factories (mobile-game style: chunky 3D buttons, shadows,
## outlined headings, an animated background, and little bits of juice on every press).

# Dungeon look: dark stone, iron and bronze edges, torch-lit gold, parchment text.
const BG := Color("#0e0c0a")
const BG_TOP := Color("#2a241e")
const BG_BOT := Color("#0c0a08")
const PN := Color("#1e1712")
const PN2 := Color("#2c221a")
const TX := Color("#f6eedd")
const MU := Color("#c9b99a")
const BD := Color("#c8902c")
const AC := Color("#ffcf3f")
const GOLD := Color("#ffd84a")
const GOOD := Color("#3ee07a")
const BAD := Color("#ff4d5e")
const STAR := Color("#f0b44c")
const INK := Color("#14100c")
const IRON := Color("#15110d")   # dark iron rim on stone buttons and cards

## Button colours: [face, lip (the 3D bottom edge), text]
const KINDS := {
	"green": [Color("#4e8b3a"), Color("#24401b"), Color.WHITE],
	"gold": [Color("#d9a441"), Color("#7a5414"), Color("#2a1a05")],
	"blue": [Color("#4a6f8f"), Color("#22374a"), Color.WHITE],
	"red": [Color("#b9382f"), Color("#5e1712"), Color.WHITE],
	"purple": [Color("#9a7444"), Color("#4f3818"), Color.WHITE],   # bronze
	"gray": [Color("#5b5249"), Color("#2e2823"), Color.WHITE],
}

static var font: Font
static var bold: Font
static var display: Font   # headings: Pixelify Sans (Latin pixel font) with Sriracha (Thai)
const PX := 3              # one art pixel of the pixel frames = 3 screen pixels
static var _px_cache := {}
static var _surf_shader: Shader
static var _bg_shader: Shader
static var _spark: Texture2D


static func build_theme() -> Theme:
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray(["Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji"])
	var sym := SystemFont.new()
	sym.font_names = PackedStringArray(["Segoe UI Symbol", "Noto Sans Symbols 2", "Noto Sans Symbols", "DejaVu Sans"])
	# Thai is bundled so it renders on every phone (system fonts vary).
	var thai: Font = load("res://assets/fonts/NotoSansThai.ttf")
	var thai_b := FontVariation.new()
	thai_b.base_font = thai
	thai_b.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	# Browsers give Godot no system fonts, so emoji are bundled too (used when the system has none).
	var emoji_b: Font = load("res://assets/fonts/NotoColorEmoji.ttf")
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bricolage Grotesque", "Segoe UI", "Roboto", "Noto Sans", "Helvetica Neue", "Arial"])
	f.font_weight = 600
	f.fallbacks = [thai, emoji, emoji_b, sym]
	var fb := SystemFont.new()
	fb.font_names = f.font_names
	fb.font_weight = 800
	fb.fallbacks = [thai_b, emoji, emoji_b, sym]
	font = f
	bold = fb
	var pixel: Font = load("res://assets/fonts/PixelifySans.ttf")
	var cz := FontVariation.new()
	cz.base_font = pixel
	cz.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	var srir: Font = load("res://assets/fonts/Sriracha-Regular.ttf")
	var sr := FontVariation.new()
	sr.base_font = srir
	sr.variation_embolden = 0.5   # Sriracha has one weight: thicken it for headings
	sr.fallbacks = [thai_b, emoji, emoji_b, sym]
	cz.fallbacks = [sr, thai_b, emoji, emoji_b, sym]
	display = cz

	var t := Theme.new()
	t.default_font = f
	t.default_font_size = 18
	t.set_color("font_color", "Label", TX)
	t.set_color("default_color", "RichTextLabel", TX)
	t.set_font("bold_font", "RichTextLabel", fb)

	for k in KINDS:
		var c: Array = KINDS[k]
		var tn: String = "Btn_" + k
		t.set_type_variation(tn, "Button")
		t.set_stylebox("normal", tn, px_button(c[0], c[1], false))
		t.set_stylebox("hover", tn, px_button(c[0].lightened(0.08), c[1], false))
		t.set_stylebox("pressed", tn, px_button(c[0].darkened(0.06), c[1], true))
		t.set_stylebox("disabled", tn, px_button(Color("#3d3731"), Color("#221e1a"), false))
		t.set_stylebox("focus", tn, StyleBoxEmpty.new())
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(s, tn, c[2])
		t.set_color("font_disabled_color", tn, Color("#8a7f70"))
		t.set_color("font_outline_color", tn, c[1].darkened(0.35) if c[2] == Color.WHITE else Color(0, 0, 0, 0))
		t.set_constant("outline_size", tn, 6 if c[2] == Color.WHITE else 0)
		t.set_font("font", tn, fb)
	# plain Button = gray kind
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(s, "Button", t.get_stylebox(s, "Btn_gray"))
	t.set_color("font_color", "Button", TX)
	t.set_color("font_hover_color", "Button", TX)
	t.set_color("font_pressed_color", "Button", TX)
	t.set_color("font_disabled_color", "Button", Color("#8a7f70"))
	t.set_font("font", "Button", fb)

	t.set_stylebox("panel", "PanelContainer", px_frame(PN, BD))
	var sbg := box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.8), 2, 99, 0)
	t.set_stylebox("background", "ProgressBar", sbg)
	t.set_stylebox("fill", "ProgressBar", box(GOOD, GOOD, 0, 99, 0))
	t.set_stylebox("panel", "TooltipPanel", px_frame(INK, BD, 0, 8))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.25)
	sb.set_corner_radius_all(4)
	t.set_stylebox("grabber", "HScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t


## Chunky 3D button: coloured face, darker lip underneath, soft drop shadow.
static func btn_box(face: Color, lip: Color, pressed: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = face
	s.border_color = lip.darkened(0.25)
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_top = 2
	s.border_width_bottom = 3 if pressed else 8
	s.set_corner_radius_all(9)
	s.corner_detail = 1   # 45-degree cut corners: hewn stone, not rounded plastic
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 12 + (6 if pressed else 0)
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 0 if pressed else 6
	s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	return s


static func box(bg: Color, border := BD, bw := 2, radius := 16, pad := 12, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius if radius >= 40 else mini(radius, 10))
	if radius < 40:
		s.corner_detail = 1
	s.set_content_margin_all(pad)
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.4)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.5)
	return s


static func panel(bg := PN, border := BD, bw := 2, radius := 16, pad := 12, shadow := 0) -> PanelContainer:
	var p := PanelContainer.new()
	if radius >= 40:
		p.add_theme_stylebox_override("panel", box(bg, border, bw, radius, pad, shadow))   # pills stay round
	else:
		p.add_theme_stylebox_override("panel", px_frame(bg, border, 0, pad, bw >= 3))
	return p


## A raised card: rounded, with a darker bottom edge and a shadow (like the buttons).
static func card(bg: Color, edge: Color, radius := 18, pad := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", px_frame(bg, edge, 1, pad, true))
	return p


## Card for items (shop, storage). item_style picks the look:
##   "iron"  - every card the same dark iron; rarity is only the thin rim
##   "frame" - the game's pixel frame art, the frame itself in the rarity colour (plain iron studs)
##   "shelf" - no card at all: the item stands on a plinth with a rarity-coloured light under it
##   "tint"  - dark card tinted by rarity with a rarity glow (the earlier look)
static var item_style := "frame"


static func item_card(_bg: Color, edge: Color, radius := 14, pad := 6) -> PanelContainer:
	if item_style == "frame":
		var pf := PanelContainer.new()
		pf.add_theme_stylebox_override("panel", px_frame(Color("#1a1410"), edge.darkened(0.1), 1, pad, true, Color("#6b5a48")))
		return pf
	var s := StyleBoxFlat.new()
	match item_style:
		"iron":
			s.bg_color = Color("#1a1410")
			s.border_color = edge.darkened(0.25)
			s.set_border_width_all(2)
			s.border_width_bottom = 4
			s.shadow_color = Color(0, 0, 0, 0.55)
			s.shadow_size = 5
			s.shadow_offset = Vector2(0, 3)
		"shelf":
			s.bg_color = Color(0, 0, 0, 0)
		_:
			s.bg_color = Color("#17110d").lerp(edge, 0.13)
			s.border_color = edge.darkened(0.1)
			s.set_border_width_all(2)
			s.border_width_bottom = 5
			s.shadow_color = Color(edge, 0.28)
			s.shadow_size = 7
			s.shadow_offset = Vector2(0, 2)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", s)
	return p


## Pixel-art 9-slice frame, built pixel by pixel and enlarged PX times (crisp, no smoothing):
## black outline with notched corners, a metal rim lit top-left and shaded bottom-right,
## a dark inner line, the fill, and optionally a heavier bottom lip and corner studs.
static func px_frame(fill: Color, rim: Color, lip := 0, pad := 12, studs := false, stud := Color("#e04a3a")) -> StyleBoxTexture:
	var key := "f%s%s%d%d%s%s" % [fill.to_html(), rim.to_html(), lip, pad, studs, stud.to_html()]
	if _px_cache.has(key):
		return _px_cache[key]
	var m := 4                      # border width in art pixels (outline + 2 rim + inner line)
	var n := m * 2 + 2
	var h := n + lip
	var img := Image.create(n, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	var hi := rim.lightened(0.4)
	var lo := rim.darkened(0.45)
	var ink := Color(0.04, 0.03, 0.02, maxf(0.9, fill.a))
	for y in h:
		for x in n:
			var edge := mini(mini(x, y), mini(n - 1 - x, h - 1 - y))
			var bottom := h - 1 - y < lip + m and y >= m
			if x == 0 or y == 0 or x == n - 1 or y == h - 1:
				img.set_pixel(x, y, ink)
			elif bottom and h - 1 - y <= lip + 2 and x > 0 and x < n - 1:
				img.set_pixel(x, y, lo.darkened(0.3) if h - 1 - y <= lip else lo)   # the lip
			elif edge == 1 or edge == 2:
				var lit := x <= 2 or y <= 2
				img.set_pixel(x, y, hi if (lit and edge == 1) else (rim if lit else lo))
			elif edge == 3:
				img.set_pixel(x, y, fill.darkened(0.55))
	# notched corners
	for c in [Vector2i(0, 0), Vector2i(n - 1, 0), Vector2i(0, h - 1), Vector2i(n - 1, h - 1)]:
		img.set_pixel(c.x, c.y, Color(0, 0, 0, 0))
	if studs:
		for c in [Vector2i(1, 1), Vector2i(n - 3, 1), Vector2i(1, h - 3), Vector2i(n - 3, h - 3)]:
			img.set_pixel(c.x, c.y, stud.lightened(0.25))
			img.set_pixel(c.x + 1, c.y, stud)
			img.set_pixel(c.x, c.y + 1, stud)
			img.set_pixel(c.x + 1, c.y + 1, stud.darkened(0.5))
	img.resize(n * PX, h * PX, Image.INTERPOLATE_NEAREST)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.texture_margin_left = m * PX
	s.texture_margin_right = m * PX
	s.texture_margin_top = m * PX
	s.texture_margin_bottom = (m + lip) * PX
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad   # the lip sits inside the padding (keeps screens from growing)
	_px_cache[key] = s
	return s


## Pixel button: black outline, bright top line, flat face, a thick darker lip underneath.
static func px_button(face: Color, lip: Color, pressed: bool) -> StyleBoxTexture:
	var key := "b%s%s%s" % [face.to_html(), lip.to_html(), pressed]
	if _px_cache.has(key):
		return _px_cache[key]
	var lp := 1 if pressed else 3
	var n := 8
	var h := 2 + 2 + 2 + lp + 2
	var img := Image.create(n, h, false, Image.FORMAT_RGBA8)
	img.fill(face)
	var ink := Color(0.04, 0.03, 0.02)
	for y in h:
		for x in n:
			if x == 0 or y == 0 or x == n - 1 or y == h - 1:
				img.set_pixel(x, y, ink)
			elif y == 1:
				img.set_pixel(x, y, face.lightened(0.35))
			elif y >= h - 1 - lp:
				img.set_pixel(x, y, lip)
			elif x == 1:
				img.set_pixel(x, y, face.lightened(0.15))
			elif x == n - 2:
				img.set_pixel(x, y, face.darkened(0.15))
	for c in [Vector2i(0, 0), Vector2i(n - 1, 0), Vector2i(0, h - 1), Vector2i(n - 1, h - 1)]:
		img.set_pixel(c.x, c.y, Color(0, 0, 0, 0))
	img.resize(n * PX, h * PX, Image.INTERPOLATE_NEAREST)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.texture_margin_left = 3 * PX
	s.texture_margin_right = 3 * PX
	s.texture_margin_top = 3 * PX
	s.texture_margin_bottom = (lp + 2) * PX
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 10 + (6 if pressed else 0)
	s.content_margin_bottom = 10
	_px_cache[key] = s
	return s


## Gives a panel a material look on top of its colours: 0 rough stone, 1 wooden planks,
## 2 stitched leather. Rivets go in the corners. Only the panel itself is affected: its
## children keep their own (default) material, so text stays crisp.
static func surface(c: Control, kind := 0, rivets := true) -> void:
	if _surf_shader == null:
		_surf_shader = Shader.new()
		_surf_shader.code = """
shader_type canvas_item;
uniform int kind = 0;
uniform vec2 size = vec2(100.0, 100.0);
uniform float rivets = 1.0;
varying vec2 lp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() { lp = VERTEX; }
void fragment() {
	vec4 c = COLOR;
	vec2 p = FRAGCOORD.xy;
	float g = 1.0;
	if (kind == 0) {
		g = 0.84 + 0.2 * noise(p * 0.05) + 0.1 * noise(p * 0.32);
		float crack = smoothstep(0.012, 0.0, abs(noise(p * 0.018 + 3.0) - 0.5));
		g -= 0.05 * crack;
	} else if (kind == 1) {
		float plank = floor(lp.y / 30.0);
		float grain = noise(vec2(lp.x * 0.012 + plank * 17.0, lp.y * 0.45));
		g = 0.74 + 0.36 * grain + 0.06 * sin(lp.x * 0.05 + grain * 9.0);
		float seam = smoothstep(2.0, 0.0, abs(mod(lp.y, 30.0)));
		g -= 0.35 * seam * step(14.0, lp.y) * step(lp.y, size.y - 14.0);
	} else {
		g = 0.88 + 0.16 * noise(p * 0.45) + 0.06 * noise(p * 0.08);
		float in_x = min(abs(lp.x - 9.0), abs(lp.x - (size.x - 9.0)));
		float in_y = min(abs(lp.y - 9.0), abs(lp.y - (size.y - 9.0)));
		bool on_v = in_x < 1.0 && lp.y > 9.0 && lp.y < size.y - 9.0;
		bool on_h = in_y < 1.0 && lp.x > 9.0 && lp.x < size.x - 9.0;
		float dash = step(fract((on_v ? lp.y : lp.x) / 11.0), 0.55);
		if ((on_v || on_h) && dash > 0.5) {
			c.rgb = mix(c.rgb, vec3(0.78, 0.63, 0.42), 0.75);
			g = 1.0;
		}
	}
	c.rgb *= g;
	if (rivets > 0.5 && size.x > 60.0 && size.y > 44.0) {
		vec2 corners[4] = vec2[](vec2(10.0, 10.0), vec2(size.x - 10.0, 10.0), vec2(10.0, size.y - 13.0), vec2(size.x - 10.0, size.y - 13.0));
		for (int i = 0; i < 4; i++) {
			vec2 d = lp - corners[i];
			float r = length(d);
			if (r < 4.2) {
				float lit = clamp(0.75 - d.y * 0.16 - d.x * 0.06, 0.25, 1.1);
				c.rgb = vec3(0.52, 0.47, 0.42) * lit;
			} else if (r < 5.4) {
				c.rgb *= 0.45;
			}
		}
	}
	COLOR = c;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _surf_shader
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("rivets", 1.0 if rivets else 0.0)
	c.material = m
	c.resized.connect(func(): m.set_shader_parameter("size", c.size))


## Slow light rolling through a red liquid (the HP vial). Only reddish pixels shimmer.
static var _liquid_shader: Shader


static func liquid(c: Control) -> void:
	if _liquid_shader == null:
		_liquid_shader = Shader.new()
		_liquid_shader.code = """
shader_type canvas_item;
void fragment() {
	vec4 c = COLOR;
	if (c.r > c.g * 1.8 && c.r > 0.25) {
		float w = sin(FRAGCOORD.x * 0.045 - TIME * 2.2) * 0.5 + 0.5;
		float b = sin(FRAGCOORD.x * 0.11 + TIME * 1.3 + FRAGCOORD.y * 0.2) * 0.5 + 0.5;
		c.rgb *= 0.82 + 0.26 * w + 0.08 * b;
	}
	COLOR = c;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _liquid_shader
	c.material = m


## A recessed slot for an item icon: a dark hollow with a shadowed top edge.
static func slot(child: Control, min_h := 60.0, glow := Color(0, 0, 0, 0)) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)   # the item picture sits right on the card
	s.set_corner_radius_all(10)
	s.set_content_margin_all(4)
	if item_style == "shelf" and glow.a > 0.0:
		# a stone plinth with the rarity light spilling out under it
		s.bg_color = Color("#211a14")
		s.border_color = Color("#4a3c2c")
		s.border_width_top = 2
		s.border_width_bottom = 6
		s.shadow_color = Color(glow, 0.55)
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 6)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size.y = min_h
	p.add_child(child)
	return p


static func lbl(text: String, size := 18, col := TX, is_bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if is_bold:
		l.add_theme_font_override("font", bold)
	return l


## Heading with a dark outline, like mobile game titles.
static func title(text: String, size := 30, col := Color.WHITE, outline := Color("#120c06")) -> Label:
	var l := lbl(text, size, col, true)
	if display != null:
		l.add_theme_font_override("font", display)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", maxi(6, size / 4))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func wrap_lbl(text: String, size := 17, col := TX) -> Label:
	var l := lbl(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	return l


static func rich(bb: String, size := 17) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bb
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


## Chunky button. kind: green, gold, blue, red, purple, gray.
static func btn(text: String, cb: Callable, primary := false, size := 18, kind := "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.theme_type_variation = "Btn_" + (kind if kind != "" else ("gold" if primary else "gray"))
	b.custom_minimum_size.y = maxf(52.0, size * 2.6)
	b.pressed.connect(cb)
	juice(b)
	return b


## Big call-to-action button.
static func big_btn(text: String, cb: Callable, kind := "green", size := 28) -> Button:
	var b := btn(text, cb, false, size, kind)
	b.custom_minimum_size = Vector2(260, 84)
	if display != null:
		b.add_theme_font_override("font", display)
	return b


## Squash on press, springy bounce on release.
static func juice(c: Control) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size / 2)
	c.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			var tw := c.create_tween()
			if e.pressed:
				tw.tween_property(c, "scale", Vector2(0.93, 0.93), 0.06)
			else:
				tw.tween_property(c, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## PC: a card brightens while the mouse is over it (pickers).
static func hover_glow(c: Control) -> void:
	c.mouse_entered.connect(func(): c.create_tween().tween_property(c, "modulate", Color(1.22, 1.17, 1.06), 0.1))
	c.mouse_exited.connect(func(): c.create_tween().tween_property(c, "modulate", Color.WHITE, 0.15))


## Gentle looping "breathe" for the main button on a screen.
static func breathe(c: Control, amount := 0.04) -> void:
	c.resized.connect(func(): c.pivot_offset = c.size / 2)
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "scale", Vector2(1 + amount, 1 + amount), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)


## Entrance animation: fade in and grow with a slight overshoot.
## (Only scale and alpha: position belongs to the parent container.)
static func pop_in(c: Control, delay := 0.0, _rise := 24.0) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		c.pivot_offset = c.size / 2
		c.scale = Vector2(0.9, 0.9))
	tw.tween_property(c, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(c, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func flow(sep := 8) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	return f


## Label that ignores the mouse (for content inside clickable cards).
static func plbl(text: String, size := 18, col := TX, is_bold := false, center := false) -> Label:
	var l := lbl(text, size, col, is_bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func spacer(h := true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Calls `cb` when a Control is tapped (left press).
static func on_tap(c: Control, cb: Callable) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_PASS   # PASS: a drag can still scroll the list behind
	c.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			cb.call())


## Small rounded chip with an item icon, coloured by rarity.
static func item_chip(id: String, owned := false) -> PanelContainer:
	var d: Dictionary = GameData.items[id]
	var c: Color = GameData.tier_colors[d.tier]
	var p := panel(c.darkened(0.45), GOOD if owned else c.lightened(0.1), 3, 12, 2)
	p.custom_minimum_size = Vector2(48, 48)
	p.tooltip_text = I18n.t(d.n) + (I18n.t(" (owned)") if owned else "")
	var l := lbl(d.ic, 26)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


static func unknown_chip() -> PanelContainer:
	var p := panel(PN2, BD, 3, 12, 2)
	p.custom_minimum_size = Vector2(48, 48)
	p.tooltip_text = I18n.t("Undiscovered recipe")
	var l := lbl("?", 24, MU, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Animated gradient background with slowly drifting light blobs.
static func background() -> Control:
	if _bg_shader == null:
		_bg_shader = Shader.new()
		_bg_shader.code = """
shader_type canvas_item;
// Torch-lit dungeon wall. Staggered stone blocks with mortar and cracks, two burning torches in
// iron brackets, embers and dust drifting, low fog along the floor, a heavy vignette.
// depth 0..1: deeper floors are darker and colder.
uniform vec4 top : source_color;
uniform vec4 bottom : source_color;
uniform float depth = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { return 0.5 * noise(p) + 0.25 * noise(p * 2.1) + 0.125 * noise(p * 4.3); }
// a flame at c (uv, aspect-corrected), w wide: bright core, orange body, licking tips
vec3 flame(vec2 q, vec2 c, float w, float t) {
	vec2 d = (q - c) / w;
	d.x += 0.25 * (fbm(vec2(d.y * 3.0 - t * 4.0, t)) - 0.5) * (0.6 - d.y);
	float body = smoothstep(1.0, 0.0, length(vec2(d.x * 2.2, (d.y + 0.25) * 0.9)));
	body *= smoothstep(0.9, -0.6, -d.y) * (0.7 + 0.5 * fbm(vec2(d.x * 4.0, d.y * 3.0 + t * 6.0)));
	float core = smoothstep(0.55, 0.0, length(vec2(d.x * 3.0, (d.y + 0.35) * 1.4)));
	return vec3(1.0, 0.45, 0.12) * body * 1.4 + vec3(1.0, 0.85, 0.5) * core;
}
void fragment() {
	vec2 res = 4.0 / SCREEN_PIXEL_SIZE;    // the screen size (this runs in a quarter-size viewport)
	vec2 p = FRAGCOORD.xy * 4.0;           // each fragment is one 4x4 pixel-art block
	vec2 uv = p / res;
	float aspect = res.x / res.y;
	vec2 q = uv * vec2(aspect, 1.0);
	float t = TIME;
	// stone blocks
	float bw = 118.0;
	float bh = 58.0;
	float row = floor(p.y / bh);
	vec2 b = vec2(p.x / bw + mod(row, 2.0) * 0.5 + hash(vec2(row, 1.0)) * 0.2, p.y / bh);
	vec2 cell = floor(b);
	vec2 f = fract(b);
	float edge = min(min(f.x, 1.0 - f.x) * bw, min(f.y, 1.0 - f.y) * bh);
	float stone = smoothstep(1.5, 5.5, edge + 2.0 * (noise(p * 0.2) - 0.5));
	float grain = 0.78 + 0.32 * fbm(p * 0.035 + cell * 7.0) + 0.06 * noise(p * 0.4);
	float crack = smoothstep(0.012, 0.0, abs(fbm(p * 0.012 + cell) - 0.5)) * step(0.55, hash(cell + 9.0)) * 0.35;
	vec3 base = mix(top.rgb, bottom.rgb, smoothstep(0.0, 1.0, uv.y));
	base = mix(base, base * vec3(0.7, 0.78, 0.95), depth * 0.6);   // colder down below
	vec3 col = base * (0.7 + 0.42 * hash(cell)) * grain * (1.0 - crack);
	col = mix(base * 0.28, col, stone);
	col += vec3(0.05, 0.04, 0.03) * smoothstep(6.0, 1.0, f.y * bh) * stone;
	// torches: iron bracket + flame, light falls off around them
	vec2 t1 = vec2(0.055 * aspect, 0.2);
	vec2 t2 = vec2(0.945 * aspect, 0.2);
	float fl1 = 0.85 + 0.1 * sin(t * 9.0) + 0.08 * noise(vec2(t * 3.0, 1.0));
	float fl2 = 0.85 + 0.1 * sin(t * 7.3 + 2.0) + 0.08 * noise(vec2(t * 2.6, 5.0));
	float l1 = exp(-distance(q, t1) * 3.0) * fl1;
	float l2 = exp(-distance(q, t2) * 3.0) * fl2;
	float dark = 0.42 - 0.18 * depth;
	vec3 warm = vec3(1.0, 0.55, 0.22);
	col = col * (dark + 1.0 * (l1 + l2)) + warm * 0.14 * (l1 + l2);
	float px = 1.0 / res.y;
	for (int i = 0; i < 2; i++) {
		vec2 tc = i == 0 ? t1 : t2;
		vec2 d = q - tc;
		// bracket: a short dark bar with a cup
		float bar = step(abs(d.x), 0.006) * step(0.0, d.y) * step(d.y, 0.05);
		float cup = step(abs(d.x), 0.016 - d.y * 0.1) * step(-0.012, d.y) * step(d.y, 0.004);
		col = mix(col, vec3(0.06, 0.05, 0.04), max(bar, cup));
		col += flame(q, tc - vec2(0.0, 0.01), 0.035, t + float(i) * 3.1);
	}
	// embers rising from the torches, dust hanging in the light
	vec2 g = uv * vec2(16.0 * aspect, 18.0) + vec2(0.0, t * 0.35);
	vec2 gc = floor(g);
	vec2 gf = fract(g) - vec2(0.5 + 0.3 * sin(t + gc.y), 0.5);
	float ember = smoothstep(0.07, 0.0, length(gf)) * step(0.94, hash(gc));
	col += warm * ember * (0.5 + 0.5 * sin(t * 4.0 + gc.x * 3.0)) * (l1 + l2 + 0.25);
	vec2 dg = uv * vec2(40.0 * aspect, 40.0) + vec2(t * 0.08, t * 0.03);
	float dust = smoothstep(0.05, 0.0, length(fract(dg) - 0.5)) * step(0.97, hash(floor(dg)));
	col += vec3(0.9, 0.8, 0.6) * dust * 0.35 * (l1 + l2 + 0.15);
	// low fog rolling along the floor
	float fog = fbm(vec2(uv.x * 3.0 * aspect + t * 0.05, uv.y * 6.0 - t * 0.02));
	float fogmask = smoothstep(0.55, 1.0, uv.y) * (0.35 + 0.65 * fog);
	col = mix(col, vec3(0.32, 0.3, 0.3) * (0.6 - 0.3 * depth), fogmask * 0.55);
	// vignette
	col *= smoothstep(1.3, 0.2, length((uv - vec2(0.5, 0.45)) * vec2(1.0, 1.1))) * (1.0 - 0.15 * depth);
	col = floor(col * 20.0 + 0.5) / 20.0;   // fewer colours, like a palette
	COLOR = vec4(col, 1.0);
}
"""
	# Drawn into a quarter-size viewport and blown up with nearest filtering: it is pixel art anyway,
	# and this is 16x less shader work per frame (phones feel it most). It updates at 30 fps.
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.size = Vector2i(180, 320)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var r := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = _bg_shader
	m.set_shader_parameter("top", BG_TOP)
	m.set_shader_parameter("bottom", BG_BOT)
	r.material = m
	r.size = Vector2(vp.size)
	vp.add_child(r)
	holder.add_child(vp)
	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	holder.set_meta("mat", m)
	holder.resized.connect(func():
		vp.size = Vector2i(ceili(holder.size.x / 4.0), ceili(holder.size.y / 4.0))
		r.size = Vector2(vp.size))
	var frame := [0]
	holder.tree_entered.connect(func():
		holder.get_tree().process_frame.connect(func():
			frame[0] += 1
			if frame[0] % 2 == 0 and is_instance_valid(vp):
				vp.render_target_update_mode = SubViewport.UPDATE_ONCE))
	return holder


## Deeper floors look darker and colder (0 = top, 1 = the last floor).
static func set_depth(bg: Control, d: float) -> void:
	if bg != null and bg.has_meta("mat"):
		(bg.get_meta("mat") as ShaderMaterial).set_shader_parameter("depth", clampf(d, 0.0, 1.0))


## One-shot sparkle burst at a position inside `parent`.
static func burst(parent: Node, pos: Vector2, col: Color, amount := 18, speed := 260.0, size := 7.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.6
	p.spread = 180
	p.direction = Vector2(0, -1)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 520)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var g := Gradient.new()
	g.set_color(0, col.lightened(0.4))
	g.set_color(1, Color(col, 0.0))
	p.color_ramp = g
	if _spark == null:
		var sg := Gradient.new()
		sg.set_color(0, Color.WHITE)
		sg.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = sg
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 32
		gt.height = 32
		_spark = gt
	p.texture = _spark
	p.scale_amount_min = size * 0.06
	p.scale_amount_max = size * 0.12
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Rolls a label's number from `from` to `to` (gold, HP...).
static func count_to(l: Label, from: int, to: int, fmt := "%d") -> void:
	if from == to:
		l.text = fmt % to
		return
	l.text = fmt % from
	var tw := l.create_tween()
	tw.tween_method(func(v: float): l.text = fmt % roundi(v), float(from), float(to), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	l.pivot_offset = l.size / 2
	tw.parallel().tween_property(l, "scale", Vector2(1.25, 1.25), 0.12)
	tw.tween_property(l, "scale", Vector2.ONE, 0.2)
