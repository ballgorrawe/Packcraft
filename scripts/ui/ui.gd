class_name UI
extends RefCounted
## Theme, palette and small widget factories so screens can be built in code.

const BG := Color("#0e1a1d")
const PN := Color("#162a2f")
const PN2 := Color("#1d363c")
const TX := Color("#e3eeec")
const MU := Color("#8fa8ab")
const BD := Color("#2c474d")
const AC := Color("#e0b04a")
const GOLD := Color("#ffd24a")
const GOOD := Color("#3ec46d")
const BAD := Color("#e5484d")
const STAR := Color("#a78bfa")

static var font: Font
static var bold: Font


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
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bricolage Grotesque", "Segoe UI", "Roboto", "Noto Sans", "Helvetica Neue", "Arial"])
	f.fallbacks = [thai, emoji, sym]
	var fb := SystemFont.new()
	fb.font_names = f.font_names
	fb.font_weight = 700
	fb.fallbacks = [thai_b, emoji, sym]
	font = f
	bold = fb

	var t := Theme.new()
	t.default_font = f
	t.default_font_size = 15
	t.set_color("font_color", "Label", TX)
	t.set_color("default_color", "RichTextLabel", TX)
	t.set_font("bold_font", "RichTextLabel", fb)

	t.set_stylebox("normal", "Button", button_style(PN2, BD.lightened(0.15)))
	t.set_stylebox("hover", "Button", button_style(PN2.lightened(0.06), AC))
	t.set_stylebox("pressed", "Button", button_style(PN2.darkened(0.1), AC, 2))
	t.set_stylebox("disabled", "Button", button_style(PN2.darkened(0.2), BD))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TX)
	t.set_color("font_hover_color", "Button", TX)
	t.set_color("font_pressed_color", "Button", TX)
	t.set_color("font_disabled_color", "Button", MU)
	t.set_font("font", "Button", fb)

	t.set_type_variation("PrimaryButton", "Button")
	var gold := Color("#e5a91f")
	t.set_stylebox("normal", "PrimaryButton", button_style(gold, Color("#8a5d00")))
	t.set_stylebox("hover", "PrimaryButton", button_style(gold.lightened(0.15), Color("#8a5d00")))
	t.set_stylebox("pressed", "PrimaryButton", button_style(gold.darkened(0.1), Color("#8a5d00"), 2))
	t.set_stylebox("disabled", "PrimaryButton", button_style(gold.darkened(0.5), Color("#5a3d00")))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		t.set_color(k, "PrimaryButton", Color("#3a2600"))

	t.set_stylebox("panel", "PanelContainer", box(PN, BD))
	t.set_stylebox("background", "ProgressBar", box(Color.BLACK, Color.BLACK, 2, 4, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOOD, GOOD, 0, 3, 0))
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("h_separation", "HFlowContainer", 8)
	t.set_constant("v_separation", "HFlowContainer", 8)
	return t


static func button_style(bg: Color, border: Color, bottom := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.border_width_bottom = bottom
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func box(bg: Color, border := BD, bw := 1, radius := 8, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func panel(bg := PN, border := BD, bw := 1, radius := 8, pad := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, bw, radius, pad))
	return p


static func lbl(text: String, size := 15, col := TX, is_bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if is_bold:
		l.add_theme_font_override("font", bold)
	return l


static func wrap_lbl(text: String, size := 14, col := TX) -> Label:
	var l := lbl(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	return l


static func rich(bb: String, size := 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bb
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


static func btn(text: String, cb: Callable, primary := false, size := 15) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	return b


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func flow(sep := 8) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	return f


## Label that ignores the mouse (for content inside clickable cards).
static func plbl(text: String, size := 15, col := TX, is_bold := false, center := false) -> Label:
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
	var p := panel(c.darkened(0.55), GOOD if owned else c, 2, 8, 2)
	p.custom_minimum_size = Vector2(40, 40)
	p.tooltip_text = I18n.t(d.n) + (I18n.t(" (owned)") if owned else "")
	var l := lbl(d.ic, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


static func unknown_chip() -> PanelContainer:
	var p := panel(PN2, BD, 2, 8, 2)
	p.custom_minimum_size = Vector2(40, 40)
	p.tooltip_text = I18n.t("Undiscovered recipe")
	var l := lbl("?", 22, MU, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p
