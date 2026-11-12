extends SceneTree
## 🪄 auto-arrange (RunState.plan_arrange / apply_arrange): plans from pack + storage, keeps every item,
## leaves no overlaps, never offers a weaker pack, Cancel puts everything back, recipe pairs end up
## touching, and it is quick enough to press.
## Run: godot --headless --path . --script res://tests/arrange_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	for case in 8:
		seed(50 + case)
		var r := RunState.new(GameData.class_keys[case % GameData.class_keys.size()], "cat", "normal")
		for _u in 30:
			r.expand += 1
			r.unlock(Vector2i(randi() % GameData.W, randi() % GameData.H))
		# fill the pack first-come (a poor layout) and leave the rest in storage
		var pool := GameData.items.keys().filter(func(id): return r.in_class_pool(id) and GameData.items[id].tier <= 3 and not GameData.items[id].relic)
		pool.shuffle()
		for id in pool.slice(0, 18):
			var it := r.make_item(id, "storage")
			r.items.append(it)
			if randf() < 0.7:
				for y in GameData.H:
					for x in GameData.W:
						if it.loc == "storage" and r.fits(it, x, y):
							it.loc = "grid"
							it.x = x
							it.y = y
		if case >= 6:
			_add_recipe_pair(r)
		var before := _layout(r)
		var ids0 := r.items.map(func(i): return i.uid)
		var score0 := r.arrange_score()
		var t0 := Time.get_ticks_msec()
		var plan := r.plan_arrange()
		var ms := Time.get_ticks_msec() - t0
		_check(_layout(r) == before, "case %d: planning changes nothing (%d ms)" % [case, ms])
		_check(ms < 2500, "case %d: quick enough (%d ms)" % [case, ms])
		if plan.is_empty():
			print("     case %d: already the best" % case)
			continue
		r.apply_arrange(plan.moves)
		var score1 := r.arrange_score()
		_check(r.items.map(func(i): return i.uid) == ids0 and r.items.all(func(i): return i.loc == "grid" or i.loc == "storage"), "case %d: no item lost or added" % case)
		_check(_no_overlap(r), "case %d: no overlaps, all on unlocked tiles" % case)
		_check(score1 > score0, "case %d: better pack (%.1f -> %.1f, in %s, out %s)" % [case, score0, score1, plan["in"], plan.out])
		r.apply_arrange(plan.undo)
		_check(_layout(r) == before, "case %d: Cancel puts everything back" % case)
		r.apply_arrange(plan.moves, true)
		_check(_layout(r) != before, "case %d: Use keeps the new layout" % case)
		if case >= 6:
			_check(not r.links().is_empty(), "case %d: the recipe pair touches (Golden Link)" % case)
	print("ARRANGE TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


## A two-part recipe split between pack and storage, its parts apart.
func _add_recipe_pair(r: RunState) -> void:
	for rc in GameData.recipes:
		if rc.evo or str(rc.get("c", "")) != "" or not r.recipe_ok(rc):
			continue
		var a := r.make_item(rc.a, "storage")
		var b := r.make_item(rc.b, "storage")
		r.items.append(a)
		r.items.append(b)
		print("     recipe pair: %s + %s" % [rc.a, rc.b])
		return


func _layout(r: RunState) -> Array:
	return r.items.map(func(i): return [i.uid, i.loc, i.x, i.y, i.rot])


func _no_overlap(r: RunState) -> bool:
	var cells := {}
	for it in r.grid_items():
		for c in it.cells():
			if cells.has(c) or not r.tiles.has(c):
				return false
			cells[c] = true
	return true


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1
