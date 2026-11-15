extends SceneTree
## A replayed fight (the night screen's "Watch the fight again") plays out exactly like the real one.
## godot --headless --path . --script res://tests/replay_test.gd

var fails := 0
var checked := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	RunState.keep_replay = true
	for cls in GameData.class_keys:
		for day in [3, 9, 15]:
			var r := RunState.new(cls, "pup", "hard")
			r.day = day
			r.path = r.cls_def().paths[0] if day >= GameData.path_day else ""
			r.travel()
			var i := r.nodes.find(r.nodes.filter(func(n): return n.has("e"))[0]) if r.nodes.any(func(n): return n.has("e")) else -1
			if i < 0:
				continue
			var cs := r.choose(i)
			cs.skip_to_end()
			var rs := r.replay_sim()
			if rs == null:
				fails += 1
				print("FAIL %s day %d: no replay kept" % [cls, day])
				continue
			rs.skip_to_end()
			checked += 1
			var same := rs.won == cs.won and rs.tk == cs.tk and is_equal_approx(rs.ehp, cs.ehp) and is_equal_approx(rs.php, cs.php)
			if not same:
				fails += 1
				print("FAIL %s day %d: replay %s %d ticks %.1f/%.1f vs real %s %d ticks %.1f/%.1f" % [cls, day, rs.won, rs.tk, rs.ehp, rs.php, cs.won, cs.tk, cs.ehp, cs.php])
	RunState.keep_replay = false
	if checked < 10:
		fails += 1
		print("FAIL only %d fights checked" % checked)
	print("REPLAY TEST: %s (%d fights)" % [("PASS" if fails == 0 else "%d FAIL" % fails), checked])
	quit()
