class_name Timeline
extends Control
## The run at a glance: one node per day joined by a path. Past days are ticked, today glows
## with the current phase, boss days show a skull, the path-choice day a fork.

var run: RunState
var _t := 0.0


func setup(r: RunState) -> Timeline:
	run = r
	custom_minimum_size = Vector2(0, 74)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if run == null:
		return
	var n := GameData.days
	# Endless: the track slides along so today stays in view (15 days shown)
	var first := 1
	if run.endless:
		first = maxi(1, run.day - 9)
	var w := size.x
	var pad := 22.0
	var step := (w - pad * 2) / float(n - 1)
	var y := 30.0
	var f: Font = UI.font if UI.font else get_theme_default_font()
	# the path
	draw_line(Vector2(pad, y), Vector2(w - pad, y), Color(1, 1, 1, 0.12), 6.0, true)
	var done_x := pad + step * (run.day - first)
	draw_line(Vector2(pad, y), Vector2(done_x, y), Color(UI.GOLD, 0.8), 6.0, true)
	var phases := {"morning": "☀️", "afternoon": "🗺️", "evening": "⚔️", "night": "🌙"}
	for d in range(first, first + n):
		var x := pad + step * (d - first)
		var boss: bool = run.boss_on(d) != null
		var fork: bool = d == GameData.path_day
		var cur := d == run.day
		var past := d < run.day
		var r := 9.0
		var col := Color("#3d3383")
		if past:
			col = UI.GOLD.darkened(0.25)
		if boss:
			col = Color("#ff4d5e") if not past else Color("#ff4d5e").darkened(0.4)
			r = 12.0
		if cur:
			r = 17.0 + 1.5 * sin(_t * 4.0)
			draw_circle(Vector2(x, y), r + 6, Color(UI.GOLD, 0.25))
			col = UI.GOLD
		draw_circle(Vector2(x, y), r, col)
		draw_arc(Vector2(x, y), r, 0, TAU, 24, Color(0, 0, 0, 0.35), 2.0, true)
		var label := ""
		var lcol := Color.WHITE
		var fs := 13
		if cur:
			label = phases.get(run.phase, str(d))
			fs = 17
		elif boss:
			label = GameData.foe_icon(run.boss_on(d).n)
			fs = 14
		elif past:
			label = "✔"
			lcol = Color("#4a2800")
		elif fork:
			label = "🔀"
			fs = 12
		else:
			label = str(d)
			lcol = UI.MU
		_center(f, label, Vector2(x, y), fs, lcol)
		# day number under the important nodes
		if cur or boss or d == first or d == first + n - 1:
			_center(f, str(d), Vector2(x, y + 30), 13 if not cur else 15, UI.GOLD if cur else UI.MU)


func _center(f: Font, t: String, c: Vector2, fs: int, col: Color) -> void:
	var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	draw_string(f, Vector2(c.x - sz.x / 2.0, c.y + (asc - desc) / 2.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
