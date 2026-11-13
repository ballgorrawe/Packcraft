extends SceneTree
## Boss Rush: five bosses, easiest first, on floors 11-15 and known from floor 1; floors 1-10 are
## events only (with EXP); a lost boss ends the run; the run saves and loads with its bosses.
## Run: godot --headless --path . --script res://tests/rush_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	seed(3)
	var r := RunState.new("warden", "", "normal")
	r.start_rush()
	_check(r.rush.size() == RunState.RUSH_BOSSES, "five bosses picked")
	var hps := []
	for d in range(11, 16):
		var b = r.boss_on(d)
		_check(b != null, "a boss on floor %d" % d)
		if b != null:
			hps.append(b.hp)
	_check(hps.size() == 5 and hps[0] < hps[4], "easiest first (%s)" % str(hps))
	_check(r.boss_on(5) == null and r.boss_on(10) == null, "no boss before floor 11")
	var lv0 := r.lv
	# floors 1-10: only events (and a camp when hurt)
	var fights := 0
	while r.day <= 10 and r.end_state == "":
		fights += r.nodes.filter(func(n): return n.has("e")).size()
		if r.needs_path():
			r.choose_path(r.cls_def().paths[0])
		r.travel()
		var cs := r.choose(0)
		if r.phase == "event":
			r.auto_event()
		elif cs != null:
			cs.skip_to_end()
			r.go_night(r.nodes[0], cs.won, cs)
		r.next_day()
	_check(fights == 0, "no fights on floors 1-10 (%d)" % fights)
	_check(r.lv > lv0, "events give EXP (level %d)" % r.lv)
	_check(r.path != "", "a path was chosen")
	_check(r.day == 11 and r.nodes.size() == 1 and r.nodes[0].k == "boss" and r.shop.is_empty(), "floor 11: the first boss, no shop")
	# save and load keep the rush
	var back := RunState.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	_check(back != null and back.mode == "rush" and back.rush == r.rush and back.boss_on(15) != null, "a saved rush keeps its bosses")
	# a lost boss ends the run
	r.travel()
	var cs2 := r.choose(0)
	r.go_night(r.nodes[0], false, cs2)
	r.next_day()
	_check(r.end_state == "over", "losing a boss ends the rush")
	print("RUSH TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
