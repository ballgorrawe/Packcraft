extends SceneTree
## Play log: a recorded run keeps one entry per day with a replayable morning snapshot and the
## player's actions; it survives save/load; bots (plog off) record nothing.
## Run: godot --headless --path . --script res://tests/plog_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	seed(5)
	var r := RunState.new("rogue", "cat", "hard")
	r.plog_start()
	for _d in 6:
		# buy what we can, lock one card, reroll once
		if r.gold >= r.reroll_cost() + 3:
			r.reroll()
		for i in range(r.shop.size() - 1, -1, -1):
			if not r.shop[i].has("bag") and r.shop[i].price <= r.gold:
				var it := r.buy_item(i)
				it.loc = "storage"
				break
		if r.shop.size() > 0:
			r.toggle_lock(0)
		var i_node := 0
		var cs := r.choose(i_node)
		if cs != null:
			cs.skip_to_end()
			r.go_night(r.nodes[i_node], cs.won, cs)
		elif r.phase == "event":
			r.auto_event()
		while not r.picks.is_empty():
			r.pick_level(0)
		r.next_day()
		if r.end_state != "":
			break
	_check(r.plog.size() == r.day and r.plog.size() >= 3, "one entry per day (%d entries, day %d)" % [r.plog.size(), r.day])
	var acts := {}
	for d in r.plog:
		for a in d.a:
			acts[a.a] = true
	for k in ["buy", "rr", "lock", "go", "night"]:
		_check(acts.has(k), "action '%s' recorded" % k)
	var go: Dictionary = r.plog[0].a.filter(func(a): return a.a == "go")[0]
	_check(go.has("pack") and go.pack.size() > 0, "the pack layout is kept when the road is chosen")
	# a morning snapshot replays as a RunState
	var m: Dictionary = JSON.parse_string(JSON.stringify(r.plog[2].m))
	var r2 := RunState.from_dict(m)
	_check(r2 != null and r2.day == int(r.plog[2].d) and r2.shop.size() > 0 and r2.items.size() > 0, "day-3 morning replays (day %s)" % (r2.day if r2 != null else -1))
	_check(not m.has("plog"), "snapshots do not nest the log")
	# save / load keeps the log
	var r3 := RunState.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	_check(r3 != null and r3.plog.size() == r.plog.size(), "save/load keeps the log")
	var size := JSON.stringify({"run": r.plog_payload()}).length()
	print("payload for %d days: %d KB" % [r.plog.size(), size / 1024])
	_check(size < 400 * 1024, "payload stays small")
	# bots record nothing
	var b := RunState.new("rogue", "cat", "hard")
	b.reroll()
	_check(b.plog.is_empty(), "plog off: nothing recorded")
	print("PLOG TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1
