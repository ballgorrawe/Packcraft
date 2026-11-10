extends SceneTree
## Headless smoke + balance test: plays full runs with a simple bot for every hero.
## Run: godot --headless --path . --script res://tests/sim_test.gd
## Options after `--`:  --greedy  take Elite/Ambush fights whenever offered (snowball check)
##                      --runs=N  runs per class (default 5)
##                      --quiet   only print the summary
##                      --losses  print every lost fight with the pack's numbers
##                      --events  take an event whenever one is offered

var greedy := false
var quiet := false
var losses := false
var events := false


func _init() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	var runs := 5
	for a in OS.get_cmdline_user_args():
		if a == "--greedy":
			greedy = true
		elif a == "--events":
			events = true
		elif a == "--losses":
			losses = true
		elif a == "--quiet":
			quiet = true
		elif a.begins_with("--runs="):
			runs = int(a.trim_prefix("--runs="))
	var total_w := 0
	var total := 0
	var summary := []
	for cls in GameData.class_keys:
		var w := 0
		var days := 0
		var caps := 0
		var evos := 0
		var ults := 0
		var fights := 0
		for trial in runs:
			var r := RunState.new(cls)
			var guard := 0
			var got_cap := false
			while r.end_state == "" and guard < 60:
				guard += 1
				if r.needs_path():
					r.choose_path(r.cls_def().paths[trial % 2])
				_bot_morning(r)
				r.travel()
				var best := 0
				for i in r.nodes.size():
					if greedy and (r.nodes[i].k == "elite" or r.nodes[i].k == "ambush"):
						best = i
				if events:
					for i in r.nodes.size():
						if RunState.EVENTS.has(r.nodes[i].k):
							best = i
				for i in r.nodes.size():
					if r.nodes[i].k == "camp" and r.hp < r.mhp * 0.5:
						best = i
				var cs := r.choose(best)
				if r.phase == "event":
					r.auto_event()
				if cs != null:
					cs.skip_to_end()
					assert(cs.done, "combat did not finish")
					ults += cs.ults
					fights += 1
					if losses and not cs.won:
						var pr := r.pack_rates()
						print("  LOSS %s day %d vs %s (%s, %d hp, %.1f dps, resist %s) pack %.1f dps %.1f shield/s, hp %d/%d, items %d, enemy left %d" % [cls, r.day, r.nodes[best].e.n, r.nodes[best].k, r.nodes[best].e.hp, r.nodes[best].e.dps, r.nodes[best].e.imm, pr.x, pr.y, r.hp, r.mhp, r.grid_items().size(), cs.ehp])
					r.go_night(r.nodes[best], cs.won, cs)
				for l in r.result.lines:
					if l.begins_with("✨ Evolution"):
						evos += 1
				if r.items.any(func(i): return i.def().tier == 4):
					got_cap = true
				r.next_day()
			if got_cap:
				caps += 1
			days += r.day
			if r.end_state == "win":
				w += 1
			if not quiet:
				print("%-7s %-11s -> %-4s day %2d  gold %3d  items %2d  tiles %2d" % [cls, r.path, r.end_state, r.day, r.gold, r.items.size(), r.tiles.size()])
		total_w += w
		total += runs
		summary.append("%-7s wins %d/%d · avg day %.1f · capstone runs %d · evolutions %d · ults/fight %.1f" % [cls, w, runs, float(days) / runs, caps, evos, float(ults) / maxi(1, fights)])
	for s in summary:
		print(s)
	print("bot wins: %d / %d" % [total_w, total])
	quit()


func _bot_morning(r: RunState) -> void:
	# a player grows the pack once it fills up: buy bag space first
	var used := 0
	for i in r.grid_items():
		used += i.cells().size()
	if r.tiles.size() + r.expand - used < 4:
		for i in r.shop.size():
			if r.shop[i].has("bag") and r.shop[i].price <= r.gold:
				r.buy_bag(i)
				break
	# unlock tiles next to the pack
	var tries := 0
	while r.expand > 0 and tries < 300:
		tries += 1
		r.unlock(Vector2i(randi() % GameData.W, randi() % GameData.H))
	# relic straight into the pack
	for it in r.storage_items():
		if it.def().relic:
			it.loc = "held"
			if not _place_best(r, it):
				it.loc = "storage"
	# buy what we can afford, preferring recipe/evolution partners
	for _n in 5:
		var idx := -1
		for i in r.shop.size():
			var e: Dictionary = r.shop[i]
			if e.has("bag") or e.price > r.gold:
				continue
			if idx < 0 or r.recipe_partner_owned(e.id):
				idx = i
		if idx < 0:
			break
		var it := r.buy_item(idx)
		if not _place_best(r, it):
			it.loc = "storage"
	# move storage items into the pack where possible
	for it in r.storage_items():
		it.loc = "held"
		if not _place_best(r, it):
			it.loc = "storage"
	if r.gold >= 8:
		for i in r.shop.size():
			if r.shop[i].has("bag") and r.shop[i].price <= r.gold:
				r.buy_bag(i)
				break


## Places `it` where it touches the most recipe/evolution partners (else anywhere).
func _place_best(r: RunState, it: PItem) -> bool:
	var best := {}
	var best_score := -1
	for rot in 4:
		it.rot = rot
		for y in GameData.H:
			for x in GameData.W:
				if r.fits(it, x, y):
					it.loc = "grid"
					it.x = x
					it.y = y
					var s := 0
					for o in r.neighbours(it):
						for rc in GameData.recipes:
							if r.recipe_ok(rc) and ((rc.a == it.id and rc.b == o.id) or (rc.b == it.id and rc.a == o.id)):
								s += 3
						s += 1
					it.loc = "held"
					if s > best_score:
						best_score = s
						best = {"x": x, "y": y, "rot": rot}
	if best.is_empty():
		it.rot = 0
		return false
	it.loc = "grid"
	it.x = best.x
	it.y = best.y
	it.rot = best.rot
	return true
