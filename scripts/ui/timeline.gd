class_name Timeline
extends Control
## The run at a glance: one node per day joined by a path. Past days are ticked, today glows
## with the current phase, boss days show a skull, the path-choice day a fork.

var run: RunState
var _t := 0.0
var _idle := 0.0


func setup(r: RunState) -> Timeline:
	run = r
	custom_minimum_size = Vector2(0, 74)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func _process(delta: float) -> void:
	_t += delta
	_idle += delta
	if _idle >= 1.0 / 15.0:   # the torchlight flicker only needs ~15 redraws a second
		_idle = 0.0
		queue_redraw()


func _draw() -> void:
	if run == null:
		return
	var n := RunState.TRIAL_DAYS if run.mode == "trial" else GameData.days
	# Endless: the track slides along so today stays in view (15 days shown)
	var first := 1
	if run.endless:
		first = maxi(1, run.day - 9)
	var w := size.x
	var pad := 22.0
	var step := (w - pad * 2) / float(n - 1)
	var f: Font = UI.font if UI.font else get_theme_default_font()
	# each floor sits a little lower than the last: you are going down
	var ys := func(d: int) -> float: return 16.0 + 18.0 * float(d - first) / float(n - 1)
	var pt := func(d: int) -> Vector2: return Vector2(pad + step * (d - first), ys.call(d))
	# the chain between floors (bronze where you have been)
	for d in range(first, first + n - 1):
		var a0: Vector2 = pt.call(d)
		var a1: Vector2 = pt.call(d + 1)
		var walked := d < run.day
		var links := 4
		for k in links:
			var c0 := a0.lerp(a1, (k + 0.2) / links)
			var c1 := a0.lerp(a1, (k + 0.8) / links)
			draw_line(c0, c1, Color("#c9952f") if walked else Color("#4a4036"), 4.0, true)
	var phases := {"morning": "🏕️", "afternoon": "🚪", "evening": "⚔️", "night": "🔥"}
	for d in range(first, first + n):
		var c: Vector2 = pt.call(d)
		var boss: bool = run.boss_on(d) != null
		var mini: bool = RunState.MINI_DAYS.has(d) and run.mode == ""
		var fork: bool = d == GameData.path_day and run.mode in ["", "rush"]
		var cur := d == run.day
		var past := d < run.day
		var r := 10.0
		var col := Color("#3a3129")
		if past:
			col = Color("#8a6a3a")
		if boss:
			col = Color("#8f1d2c") if not past else Color("#5a1520")
			r = 13.0
		elif mini and not past:
			col = Color("#6b2448")
			r = 11.5
		if cur:
			r = 17.0
			# torchlight on the floor you are on
			var glow := 0.22 + 0.08 * sin(_t * 9.0) + 0.05 * sin(_t * 23.0)
			draw_circle(c, r + 10, Color(1.0, 0.55, 0.2, glow * 0.6))
			draw_circle(c, r + 5, Color(1.0, 0.6, 0.25, glow))
			col = Color("#d9a441")
		# a stone step: a diamond with a lit top face
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(pts, col)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c, c + Vector2(-r, 0)]), Color(1, 1, 1, 0.1))
		var rim := pts.duplicate()
		rim.append(pts[0])
		draw_polyline(rim, Color(0, 0, 0, 0.6), 2.0, true)
		var label := ""
		var lcol := Color.WHITE
		var fs := 12
		if cur:
			label = phases.get(run.phase, str(d))
			fs = 16
		elif boss:
			label = GameData.foe_icon(run.boss_on(d).n)
			fs = 13
		elif mini and not past:
			label = "👺"
			fs = 12
		elif past:
			label = "✔"
			lcol = Color("#2a1a05")
		elif fork:
			label = "🔀"
			fs = 11
		else:
			label = str(d)
			lcol = UI.MU
		_center(f, label, c, fs, lcol)
		# floor name under the important steps
		if cur or boss or d == first or d == first + n - 1:
			_center(f, "B%d" % d, c + Vector2(0, r + 13), 12 if not cur else 14, UI.GOLD if cur else UI.MU)


func _center(f: Font, t: String, c: Vector2, fs: int, col: Color) -> void:
	var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	draw_string(f, Vector2(c.x - sz.x / 2.0, c.y + (asc - desc) / 2.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
