class_name StatBar
extends Control
## Fight health bar: a white Shield strip on top, the HP bar below, and a blinking segment at the
## end of the HP fill showing how much HP the burn / poison on this side will eat in the next 3 s.

var hp_col := Color("#3ee07a")
var hp := 1.0          # 0..1 of max HP
var shield := 0.0      # shield points
var shield_max := 1.0  # shield that fills the strip (max HP)
var dot := 0.0         # 0..1 of max HP the DoTs will deal soon
var dot_col := Color("#a855f7")
var hp_text := ""

var _shown_hp := 1.0   # trails behind hp so damage leaves a fading "ghost" chunk
var _ghost := 1.0
var _sh_pulse := 0.0
var _t := 0.0

const SH_H := 14.0
const GAP := 3.0


func setup(col: Color, h: float) -> StatBar:
	hp_col = col
	custom_minimum_size = Vector2(0, h + SH_H + GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func set_values(p_hp: float, p_shield: float, p_shield_max: float, p_dot: float, p_dot_col: Color, text: String) -> void:
	if p_hp < hp:
		_ghost = maxf(_ghost, hp)
	hp = clampf(p_hp, 0, 1)
	shield = maxf(0, p_shield)
	shield_max = maxf(1, p_shield_max)
	dot = clampf(p_dot, 0, 1)
	dot_col = p_dot_col
	hp_text = text
	queue_redraw()


## A short white flash on the shield strip (shield gained or broken).
func pulse_shield() -> void:
	_sh_pulse = 1.0


func _process(delta: float) -> void:
	_t += delta
	_shown_hp = hp
	if _ghost > hp:
		_ghost = maxf(hp, _ghost - delta * 0.6)
	if _sh_pulse > 0:
		_sh_pulse = maxf(0, _sh_pulse - delta * 3.0)
	if _ghost > hp or _sh_pulse > 0 or dot > 0 or shield > 0:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var bar_h := size.y - SH_H - GAP
	# shield strip
	var sr := Rect2(0, 0, w, SH_H)
	draw_style_box(UI.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 99, 0), sr)
	if shield > 0:
		var sw := maxf(SH_H, w * minf(1.0, shield / shield_max))
		var glow := 0.75 + 0.25 * _sh_pulse
		draw_style_box(UI.box(Color(1, 1, 1, glow), Color("#bfe6ff"), 2 if _sh_pulse > 0 else 0, 99, 0), Rect2(0, 0, sw, SH_H))
	# HP bar
	var br := Rect2(0, SH_H + GAP, w, bar_h)
	draw_style_box(UI.box(Color("#0f172a"), Color(0, 0, 0, 0.6), 2, 99, 0), br)
	var fw := w * _shown_hp
	if _ghost > _shown_hp:
		draw_style_box(UI.box(Color(1, 0.9, 0.9, 0.55), Color(0, 0, 0, 0), 0, 99, 0), Rect2(br.position, Vector2(w * _ghost, bar_h)))
	if fw > 1:
		draw_style_box(UI.box(hp_col, hp_col.darkened(0.35), 2, 99, 0), Rect2(br.position, Vector2(fw, bar_h)))
	# DoT forecast: the end of the HP fill that the statuses will burn away
	if dot > 0 and fw > 1:
		var dw := minf(fw, w * dot)
		var a := 0.55 + 0.35 * sin(_t * 7.0)
		var c := dot_col
		c.a = a
		draw_rect(Rect2(br.position.x + fw - dw, br.position.y + 3, dw, bar_h - 6), c)
		# stripes so it reads as "about to go" even for colour-blind players
		var x := br.position.x + fw - dw
		while x < br.position.x + fw:
			draw_line(Vector2(x, br.end.y - 3), Vector2(minf(x + 8, br.position.x + fw), br.position.y + 3), Color(0, 0, 0, 0.35), 2)
			x += 9
	# text
	var f := get_theme_default_font()
	var fs := int(clampf(bar_h * 0.62, 12, 18))
	var ts := f.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var tp := Vector2((w - ts.x) / 2, br.position.y + (bar_h + fs * 0.75) / 2)
	draw_string_outline(f, tp, hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
	draw_string(f, tp, hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if shield > 0:
		var st := "🛡 %d" % roundi(shield)
		var sfs := 12
		var sts := f.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs)
		# the number rides just past the end of the white fill (inside it when the strip is full)
		var end_x := maxf(SH_H, w * minf(1.0, shield / shield_max))
		var sp := Vector2(end_x + 6, SH_H - 2)
		if sp.x + sts.x > w - 4:
			sp.x = end_x - sts.x - 8
		draw_string_outline(f, sp, st, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, 4, Color(0, 0, 0, 0.9))
		draw_string(f, sp, st, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color.WHITE)
