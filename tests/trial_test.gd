extends SceneTree
## Class trials: every path's trial, played by following its steps (buy the planned items, let the
## arranger put them in place), makes the path's Masterwork in time and beats the training boss.
## Run: godot --headless --path . --script res://tests/trial_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	var wins := 0
	var made := 0
	var n := 0
	for path_id in GameData.paths:
		var cls: String = GameData.paths[path_id].cl
		seed(n + 5)
		var r := RunState.new(cls, "", "normal")
		r.start_trial(path_id)
		n += 1
		var plan := r.trial
		_check(not plan.is_empty(), "%s: has a plan" % path_id)
		var mw_by_boss := false
		var lost := []
		while r.end_state == "" and r.day <= RunState.TRIAL_DAYS:
			# buy what the plan sells today
			for id in plan.days.get(r.day, {}).get("buy", []):
				var i := r.shop.find_custom(func(e): return e.get("id", "") == id)
				if i >= 0:
					var it := r.buy_item(i)
					if it != null:
						it.loc = "storage"   # the shop hands it over held, like a drag
			# a player clears room first: everything back to storage, then the joins, then the rest
			for e in r.items:
				if e.loc == "grid":
					e.loc = "storage"
			# do today's joins the way a player follows the steps: each pair (or trio) placed touching
			var claimed := []
			for st in r.trial_steps():
				if st.step.t in ["link", "mw"] and not st.done:
					_place_together(r, st.step.ids, claimed)
			# then the rest, best and biggest first (the Masterwork before the leftovers)
			var rest := r.items.filter(func(e): return e.loc == "storage")
			rest.sort_custom(func(x, y): return x.def().tier * 10 + x.cells().size() > y.def().tier * 10 + y.cells().size())
			for e in rest:
				if e.loc == "storage":
					var s := r.nearest_spot(e, Vector2i(4, 3))
					if not s.is_empty():
						e.loc = "grid"
						e.x = s.x
						e.y = s.y
						e.rot = s.rot
			# a Golden Link the plan does not want is switched off (tap it), like a player following the steps
			var wanted := {}
			for d in plan.days:
				for s in plan.days[d].steps:
					if s.has("r"):
						wanted[s.r] = true
			for l in r.links():
				if not wanted.has(l.r):
					r.off[l.key] = true
			if r.day == RunState.TRIAL_DAYS:
				mw_by_boss = r.owns(plan.mw.r)
			var undone := r.trial_steps().filter(func(x): return not x.done)
			if not undone.is_empty():
				print("     %s day %d: steps not done: %s" % [path_id, r.day, str(undone.map(func(x): return x.step.t + ":" + str(x.step.get("r", x.step.get("id", "")))))])
			r.travel()
			var cs := r.choose(0)
			if cs != null:
				cs.skip_to_end()
				if not cs.won:
					lost.append(r.day)
				r.go_night(r.nodes[0], cs.won, cs)
			r.next_day()
		if mw_by_boss:
			made += 1
		if r.end_state == "win":
			wins += 1
		_check(mw_by_boss, "%s: Masterwork %s ready for the boss" % [path_id, plan.mw.r])
		print("     %s: %s (hearts %d, lost floors %s, Masterwork in pack: %s)" % [path_id, r.end_state, r.res, str(lost), r.grid_items().any(func(e): return e.id == plan.mw.r)])
	print("trials: %d, Masterwork in time: %d, boss beaten: %d" % [n, made, wins])
	_check(wins >= n - 2, "almost every trial is beaten by following its steps")
	print("TRIAL TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


## Moves one item of each id next to the first one (ids may repeat, e.g. two copies to evolve).
func _place_together(r: RunState, ids: Array, claimed: Array) -> void:
	var picked := []
	for id in ids:
		var it = null
		for e in r.items:
			if e.id == id and not picked.has(e) and not claimed.has(e) and e.loc in ["grid", "storage"]:
				it = e
				break
		if it == null:
			return
		picked.append(it)
	claimed.append_array(picked)
	var first: PItem = picked[0]
	for it in picked:
		it.loc = "held"
	var s0 := r.nearest_spot(first, Vector2i(4, 3))
	if s0.is_empty():
		for it in picked:
			it.loc = "storage"
		return
	first.loc = "grid"
	first.x = s0.x
	first.y = s0.y
	first.rot = s0.rot
	var group := [first]
	for it in picked.slice(1):
		var ok := false
		for rot in 4:
			for y in GameData.H:
				for x in GameData.W:
					if ok or not r.fits(it, x, y, rot):
						continue
					it.loc = "grid"
					it.x = x
					it.y = y
					it.rot = rot
					if group.any(func(g): return r.adj(g, it)):
						ok = true
					else:
						it.loc = "held"
		if ok:
			group.append(it)
		else:
			it.loc = "storage"


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
