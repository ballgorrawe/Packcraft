extends SceneTree
## Puzzles: every puzzle's good layout earns 3 stars, the same layout always ends the same way, a
## used hint caps a try at 2 stars, and a puzzle never touches the saved run.
## Run: godot --headless --path . --script res://tests/puzzle_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	_check(GameData.puzzles.size() >= 10, "at least 10 puzzles (%d)" % GameData.puzzles.size())
	for p in GameData.puzzles:
		var a := _play(p, false)
		var b := _play(p, false, true)
		_check(a.stars == 3, "%s: the good layout earns 3 stars (got %d, %d%% HP)" % [p.id, a.stars, roundi(a.left * 100)])
		_check(a.left == b.left, "%s: the same layout fights the same way, even with other dice rolled during it (the fight screen's effects)" % p.id)
		_check(_play(p, true).stars <= 2, "%s: a used hint caps it at 2 stars" % p.id)
	print("PUZZLE TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _play(p: Dictionary, hint: bool, noise := false) -> Dictionary:
	var r := RunState.new(str(p.cls), "", "normal")
	r.start_puzzle(p)
	r.puzzle_hint = hint
	var left := r.items.duplicate()
	for e in p.best:
		for it in left:
			if it.id == e[0]:
				it.loc = "grid"
				it.x = int(e[1])
				it.y = int(e[2])
				it.rot = int(e[3])
				left.erase(it)
				break
	r.travel()
	var cs := r.choose(0)
	var guard := 0
	while not cs.done and guard < 900:
		cs.step()
		if noise:
			randf()   # the fight screen rolls dice for its sparks between steps
		guard += 1
	r.go_night(r.nodes[0], cs.won, cs)
	r.next_day()
	_check(r.end_state in ["win", "over"], "%s: the puzzle ends after its fight" % p.id)
	return {"stars": int(r.result.get("stars", 0)), "left": cs.php / maxf(1.0, cs.mhp)}


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
