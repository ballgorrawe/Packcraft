class_name UI
extends RefCounted
## Theme, palette and widget factories (mobile-game style: chunky 3D buttons, shadows,
## outlined headings, an animated background, and little bits of juice on every press).

const BG := Color("#120f2e")
const BG_TOP := Color("#2d1d5c")
const BG_BOT := Color("#0b1530")
const PN := Color("#28225a")
const PN2 := Color("#352c70")
const TX := Color("#ffffff")
const MU := Color("#b9b2e6")
const BD := Color("#5d4fb3")
const AC := Color("#ffcf3f")
const GOLD := Color("#ffd84a")
const GOOD := Color("#3ee07a")
const BAD := Color("#ff4d5e")
const STAR := Color("#c084fc")
const INK := Color("#14102b")

## Button colours: [face, lip (the 3D bottom edge), text]
const KINDS := {
	"green": [Color("#3fd17a"), Color("#15803d"), Color.WHITE],
	"gold": [Color("#ffc93c"), Color("#c47a0c"), Color("#4a2800")],
	"blue": [Color("#4f8cff"), Color("#2747a8"), Color.WHITE],
	"red": [Color("#ff5d6c"), Color("#a3172a"), Color.WHITE],
	"purple": [Color("#a77bff"), Color("#5b34c9"), Color.WHITE],
	"gray": [Color("#5d5894"), Color("#353064"), Color.WHITE],
}

static var font: Font
static var bold: Font
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
		t.set_stylebox("normal", tn, btn_box(c[0], c[1], false))
		t.set_stylebox("hover", tn, btn_box(c[0].lightened(0.08), c[1], false))
		t.set_stylebox("pressed", tn, btn_box(c[0].darkened(0.06), c[1], true))
		t.set_stylebox("disabled", tn, btn_box(Color("#4a4670"), Color("#2c2950"), false))
		t.set_stylebox("focus", tn, StyleBoxEmpty.new())
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(s, tn, c[2])
		t.set_color("font_disabled_color", tn, Color("#8f8ab8"))
		t.set_color("font_outline_color", tn, c[1].darkened(0.35) if c[2] == Color.WHITE else Color(0, 0, 0, 0))
		t.set_constant("outline_size", tn, 6 if c[2] == Color.WHITE else 0)
		t.set_font("font", tn, fb)
	# plain Button = gray kind
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(s, "Button", t.get_stylebox(s, "Btn_gray"))
	t.set_color("font_color", "Button", TX)
	t.set_color("font_hover_color", "Button", TX)
	t.set_color("font_pressed_color", "Button", TX)
	t.set_color("font_disabled_color", "Button", Color("#8f8ab8"))
	t.set_font("font", "Button", fb)

	t.set_stylebox("panel", "PanelContainer", box(PN, BD))
	var sbg := box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.8), 2, 99, 0)
	t.set_stylebox("background", "ProgressBar", sbg)
	t.set_stylebox("fill", "ProgressBar", box(GOOD, GOOD, 0, 99, 0))
	t.set_stylebox("panel", "TooltipPanel", box(INK, BD, 2, 10, 8))
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
	s.border_color = lip
	s.border_width_left = 0
	s.border_width_right = 0
	s.border_width_top = 0
	s.border_width_bottom = 2 if pressed else 8
	s.set_corner_radius_all(18)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 12 + (6 if pressed else 0)
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 0 if pressed else 6
	s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	return s


static func box(bg: Color, border := BD, bw := 2, radius := 16, pad := 12, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.4)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.5)
	return s


static func panel(bg := PN, border := BD, bw := 2, radius := 16, pad := 12, shadow := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, bw, radius, pad, shadow))
	return p


## A raised card: rounded, with a darker bottom edge and a shadow (like the buttons).
static func card(bg: Color, edge: Color, radius := 18, pad := 10) -> PanelContainer:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(3)
	s.border_width_bottom = 7
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 4)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", s)
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
static func title(text: String, size := 30, col := Color.WHITE, outline := Color("#1a0f3d")) -> Label:
	var l := lbl(text, size, col, true)
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
	c.mouse_filter = Control.MOUSE_FILTER_STOP
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
static func background() -> ColorRect:
	if _bg_shader == null:
		_bg_shader = Shader.new()
		_bg_shader.code = """
shader_type canvas_item;
uniform vec4 top : source_color;
uniform vec4 bottom : source_color;
float blob(vec2 uv, vec2 c, float r) { return smoothstep(r, 0.0, distance(uv, c)); }
void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top.rgb, bottom.rgb, smoothstep(0.0, 1.0, uv.y));
	float t = TIME * 0.12;
	vec2 a = vec2(0.25 + 0.15 * sin(t), 0.2 + 0.1 * cos(t * 1.3));
	vec2 b = vec2(0.8 + 0.1 * cos(t * 0.8), 0.65 + 0.12 * sin(t * 1.1));
	col += vec3(0.45, 0.25, 0.9) * 0.10 * blob(uv * vec2(0.6, 1.0), a * vec2(0.6, 1.0), 0.45);
	col += vec3(0.15, 0.55, 1.0) * 0.08 * blob(uv * vec2(0.6, 1.0), b * vec2(0.6, 1.0), 0.5);
	vec2 g = fract(uv * vec2(18.0, 36.0) + vec2(0.0, -TIME * 0.02));
	float star = smoothstep(0.06, 0.0, distance(g, vec2(0.5))) * step(0.82, fract(sin(dot(floor(uv * vec2(18.0, 36.0)), vec2(12.9898, 78.233))) * 43758.5453));
	col += vec3(star) * 0.25 * (0.5 + 0.5 * sin(TIME * 2.0 + uv.x * 40.0));
	COLOR = vec4(col, 1.0);
}
"""
	var r := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = _bg_shader
	m.set_shader_parameter("top", BG_TOP)
	m.set_shader_parameter("bottom", BG_BOT)
	r.material = m
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


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
