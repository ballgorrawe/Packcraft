extends SceneTree
## 🪄 auto-arrange (RunState.auto_arrange): keeps every item, leaves no overlaps, never makes the pack
## weaker, and is quick enough to press. Run: godot --headless --path . --script res://tests/arrange_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	for case in 6:
		seed(50 + case)
		var r := RunState.new(GameData.class_keys[case % GameData.class_keys.size()], "cat", "normal")
		for _u in 30:
			r.expand += 1
			r.unlock(Vector2i(randi() % GameData.W, randi() % GameData.H))
		# fill the pack with class items placed first-come (a poor layout)
		var pool := GameData.items.keys().filter(func(id): return r.in_class_pool(id) and GameData.items[id].tier <= 3 and not GameData.items[id].relic)
		pool.shuffle()
		for id in pool.slice(0, 14):
			var it := r.make_item(id, "storage")
			r.items.append(it)
			for y in GameData.H:
				for x in GameData.W:
					if it.loc == "storage" and r.fits(it, x, y):
						it.loc = "grid"
						it.x = x
						it.y = y
		var before_ids := r.items.map(func(i): return i.uid)
		var grid_before := r.grid_items().map(func(i): return i.uid)
		var score0 := r.arrange_score()
		var t0 := Time.get_ticks_msec()
		var changed := r.auto_arrange()
		var ms := Time.get_ticks_msec() - t0
		var score1 := r.arrange_score()
		_check(r.items.map(func(i): return i.uid) == before_ids, "case %d: no item lost or added" % case)
		_check(r.grid_items().map(func(i): return i.uid).size() == grid_before.size(), "case %d: every pack item is still in the pack" % case)
		var cells := {}
		var overlap := false
		for it in r.grid_items():
			for c in it.cells():
				if cells.has(c) or not r.tiles.has(c):
					overlap = true
				cells[c] = true
		_check(not overlap, "case %d: no overlaps, all on unlocked tiles" % case)
		_check(score1 >= score0 - 0.001, "case %d: pack not weaker (%.1f -> %.1f, changed=%s, %d ms)" % [case, score0, score1, changed, ms])
		# pressing again never makes it worse
		r.auto_arrange()
		_check(r.arrange_score() >= score1 - 0.001, "case %d: a second press keeps it as good" % case)
	print("ARRANGE TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1
