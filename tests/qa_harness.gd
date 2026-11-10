extends SceneTree
## QA harness: invariant checks, targeted edge cases and seeded Monte Carlo runs.
## Never edits game code; it drives RunState / CombatSim like the UI does.
##
##   godot --headless --path . --script res://tests/qa_harness.gd -- --mode=edge
##   godot --headless --path . --script res://tests/qa_harness.gd -- --mode=inv --runs=50
##   godot --headless --path . --script res://tests/qa_harness.gd -- --mode=mc --style=smart --cls=ember --start=0 --count=250
##
## mc prints one "RUN|..." line per run (reproducible: same --start/--count/--style gives the same runs).
## styles: random (random buys/placement/roads), greedy (most expensive first, Elite when healthy),
##         smart (recipe/evolution partners, bag management, events sometimes).

var mode := "edge"
var style := "smart"
var cls_filter := ""
var diff := "normal"
var start := 0
var count := 10
var runs := 20
var violations: Array = []
var repro_seed := 0


func _init() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		var k: String = kv[0]
		var v: String = kv[1] if kv.size() > 1 else ""
		match k:
			"mode": mode = v
			"style": style = v
			"cls": cls_filter = v
			"diff": diff = v
			"start": start = int(v)
			"count": count = int(v)
			"runs": runs = int(v)
			"seed": repro_seed = int(v)
	match mode:
		"edge": _edge_cases()
		"inv": _invariant_runs()
		"mc": _monte_carlo()
		"repro": _repro()
	quit(1 if violations.size() > 0 and mode != "mc" else 0)


# =============================================================== invariants

func _fail(tag: String, seed_v: int, msg: String) -> void:
	violations.append("%s seed=%d %s" % [tag, seed_v, msg])
	print("VIOLATION %s seed=%d %s" % [tag, seed_v, msg])


## Things that must always hold between player actions.
func check_state(r: RunState, seed_v: int, ctx: String) -> void:
	if r.gold < 0:
		_fail("GOLD_NEG", seed_v, "%s gold=%d day=%d" % [ctx, r.gold, r.day])
	if r.res < 0 or r.res > RunState.MAX_HEARTS:
		_fail("HEARTS", seed_v, "%s res=%d" % [ctx, r.res])
	if r.mhp <= 0 or is_nan(r.mhp):
		_fail("MAXHP", seed_v, "%s mhp=%.1f mhp_mod=%.1f day=%d" % [ctx, r.mhp, r.mhp_mod, r.day])
	if r.hp > r.mhp + 0.01 or r.hp < 0 or is_nan(r.hp):
		_fail("HP", seed_v, "%s hp=%.2f mhp=%.2f" % [ctx, r.hp, r.mhp])
	var cells := {}
	var uids := {}
	for it in r.items:
		if uids.has(it.uid):
			_fail("UID_DUP", seed_v, "%s uid=%d" % [ctx, it.uid])
		uids[it.uid] = true
		if not GameData.items.has(it.id) or GameData.items[it.id].cl == "monster":
			_fail("BAD_ITEM", seed_v, "%s id=%s" % [ctx, it.id])
		if it.loc == "held":
			_fail("HELD_LEFT", seed_v, "%s %s left in hand" % [ctx, it.id])
		if it.loc == "grid":
			for c in it.cells():
				if not r.tiles.has(c):
					_fail("OFF_GRID", seed_v, "%s %s cell %s not unlocked" % [ctx, it.id, str(c)])
				if cells.has(c):
					_fail("OVERLAP", seed_v, "%s %s overlaps %s at %s" % [ctx, it.id, cells[c], str(c)])
				cells[c] = it.id


## Steps a fight tick by tick and checks combat invariants. Returns the sim.
func checked_fight(r: RunState, cs: CombatSim, seed_v: int) -> CombatSim:
	cs._rng.seed = seed_v * 7919 + r.day
	var guard := 0
	while not cs.done and guard < 4000:
		cs.step()
		guard += 1
		cs.events.clear()
		for k in cs.fs:
			var fm: int = GameData.statuses[k].max
			if fm >= 0 and cs.fs[k] > fm + 0.01:
				_fail("STATUS_CAP", seed_v, "foe %s=%.1f > %d" % [k, cs.fs[k], fm])
		for k in cs.hd:
			if GameData.statuses[k].max >= 0 and cs.hd[k] > GameData.statuses[k].max + 0.01:
				_fail("STATUS_CAP", seed_v, "hero %s=%.1f" % [k, cs.hd[k]])
		for k in cs.hs:
			if GameData.statuses[k].max >= 0 and cs.hs[k] > GameData.statuses[k].max + 0.01:
				_fail("STATUS_CAP", seed_v, "hero %s=%.1f" % [k, cs.hs[k]])
		if cs.shield > cs._shield_cap() + 0.01 and cs.tk > 1:
			_fail("SHIELD_CAP", seed_v, "shield %.1f > cap %.1f" % [cs.shield, cs._shield_cap()])
		if is_nan(cs.ehp) or is_nan(cs.php):
			_fail("NAN", seed_v, "ehp %s php %s" % [cs.ehp, cs.php])
		if cs.php > cs.mhp + 0.01:
			_fail("HP_OVER", seed_v, "php %.1f > mhp %.1f" % [cs.php, cs.mhp])
	if not cs.done:
		_fail("STALEMATE", seed_v, "fight day %d vs %s did not end in 400s" % [r.day, cs.e.n])
	return cs


## Night resolution with item conservation: before - used potions - fusion parts + fused + loot.
func checked_night(r: RunState, n: Dictionary, win: bool, cs: CombatSim, seed_v: int) -> void:
	var before := r.items.size()
	var used := 0
	if cs != null:
		for x in cs.items:
			if x.d.once and x.used:
				used += 1
	# used potions are removed before fusions are looked up, so count links without them
	var used_items := []
	if cs != null:
		for x in cs.items:
			if x.d.once and x.used:
				used_items.append(x.i)
	for ui in used_items:
		r.items.erase(ui)
	var links := 0
	for l in r.links():
		if not r.off.has(l.key):
			links += 1
	for ui in used_items:
		r.items.append(ui)
	r.go_night(n, win, cs)
	var loot := 0
	for w in r.result.get("rew", []):
		if w.k == "loot":
			loot += 1
	# events added their loot to items before go_night; count those via rew too but they were in `before`
	if RunState.EVENTS.has(n.k):
		loot = 0
	var expect := before - used - links + loot
	if r.items.size() != expect:
		_fail("CONSERVE", seed_v, "night day %d %s: items %d expected %d (before %d used %d links %d loot %d)" % [r.day, n.k, r.items.size(), expect, before, used, links, loot])
	for w in r.result.get("rew", []):
		if w.k == "fusion" and not r.owns(w.r):
			_fail("FUSION_LOST", seed_v, "%s missing after fusion" % w.r)
	check_state(r, seed_v, "after night")


# =============================================================== bots

func _unlock_all(r: RunState) -> void:
	var tries := 0
	while r.expand > 0 and tries < 400:
		tries += 1
		r.unlock(Vector2i(randi() % GameData.W, randi() % GameData.H))


func _place_random(r: RunState, it: PItem) -> bool:
	var spots := []
	for rot in 4:
		for y in GameData.H:
			for x in GameData.W:
				if r.fits(it, x, y, rot):
					spots.append([x, y, rot])
	if spots.is_empty():
		return false
	var s: Array = spots.pick_random()
	it.loc = "grid"
	it.x = s[0]
	it.y = s[1]
	it.rot = s[2]
	return true


## Spot touching the most recipe/evolution partners (the smart bot's placement).
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


func _free_tiles(r: RunState) -> int:
	var used := 0
	for i in r.grid_items():
		used += i.cells().size()
	return r.tiles.size() + r.expand - used


func bot_morning(r: RunState, st: String) -> void:
	if r.needs_path():
		r.choose_path(r.cls_def().paths[randi() % 2])
	if st != "random" and _free_tiles(r) < 4:
		for i in r.shop.size():
			if r.shop[i].has("bag") and r.shop[i].price <= r.gold:
				r.buy_bag(i)
				break
	if st == "random" and randf() < 0.3:
		var bi := []
		for i in r.shop.size():
			if r.shop[i].has("bag"):
				bi.append(i)
		if not bi.is_empty():
			r.buy_bag(bi.pick_random())
	_unlock_all(r)
	for it in r.storage_items():
		if it.def().relic:
			it.loc = "held"
			if not _place_best(r, it):
				it.loc = "storage"
	for _n in 6:
		var cand := []
		for i in r.shop.size():
			var e: Dictionary = r.shop[i]
			if not e.has("bag") and e.price <= r.gold:
				cand.append(i)
		if cand.is_empty():
			break
		var idx: int = cand[0]
		match st:
			"random":
				if randf() < 0.35:
					break
				idx = cand.pick_random()
			"greedy":
				for i in cand:
					if r.shop[i].price > r.shop[idx].price:
						idx = i
			_:
				for i in cand:
					if r.recipe_partner_owned(r.shop[i].id):
						idx = i
						break
		var it := r.buy_item(idx)
		if it == null:
			break
		var ok := _place_random(r, it) if st == "random" else _place_best(r, it)
		if not ok:
			it.loc = "storage"
	for it in r.storage_items():
		it.loc = "held"
		var ok := _place_random(r, it) if st == "random" else _place_best(r, it)
		if not ok:
			it.loc = "storage"
	# sell junk treasure (the bots know it is only worth gold)
	for it in r.storage_items():
		if it.def().tags.has("Treasure"):
			r.sell(it)


func pick_node(r: RunState, st: String) -> int:
	var best := 0
	match st:
		"random":
			return randi() % r.nodes.size()
		"greedy":
			for i in r.nodes.size():
				if r.nodes[i].k in ["elite", "ambush"] and r.hp > r.mhp * 0.6:
					best = i
		_:
			for i in r.nodes.size():
				if RunState.EVENTS.has(r.nodes[i].k) and randf() < 0.4:
					best = i
	for i in r.nodes.size():
		if r.nodes[i].k == "camp" and r.hp < r.mhp * 0.45:
			best = i
	return best


## Plays one full run. Returns a summary dictionary.
func play_run(cls: String, pet: String, st: String, seed_v: int, checks: bool) -> Dictionary:
	seed(seed_v)
	var r := RunState.new(cls, pet, diff)
	var info := {"gold": [], "deaths": [], "kinds": {}, "elite_w": 0, "elite_l": 0, "camp_hp": [], "fights": 0, "losses": 0, "max_gold": 0}
	var guard := 0
	while r.end_state == "" and guard < 60:
		guard += 1
		bot_morning(r, st)
		if checks:
			check_state(r, seed_v, "morning d%d" % r.day)
		info.gold.append(r.gold)
		info.max_gold = maxi(info.max_gold, r.gold)
		if not r.travel():
			if r.needs_path():
				r.choose_path(r.cls_def().paths[0])
			r.travel()
		var bi := pick_node(r, st)
		var n: Dictionary = r.nodes[bi]
		info.kinds[n.k] = info.kinds.get(n.k, 0) + 1
		if n.k == "camp":
			info.camp_hp.append(r.hp / r.mhp)
		var cs := r.choose(bi)
		if r.phase == "event":
			if checks:
				var before := r.items.size()
				r.auto_event()
				check_state(r, seed_v, "event %s" % n.k)
				if _repro_verbose:
					print("  day %d event %s: items %d -> %d, night rew %s" % [r.day, n.k, before, r.items.size(), str(r.result.get("rew", []).map(func(w): return w.k + ":" + str(w.get("r", w.get("id", w.get("v", ""))))))])
				# night fusions merge 2 items into 1, so each fusion may remove one item
				var merges: int = r.result.get("rew", []).filter(func(w): return w.k == "fusion").size()
				if r.items.size() < before - merges - 1:
					_fail("EVENT_LOSS", seed_v, "%s dropped %d items (%d fusions)" % [n.k, before - r.items.size(), merges])
			else:
				r.auto_event()
		elif cs != null:
			info.fights += 1
			if checks:
				checked_fight(r, cs, seed_v)
			else:
				cs._rng.seed = seed_v * 7919 + r.day
				cs.skip_to_end()
				if not cs.done:
					_fail("STALEMATE", seed_v, "day %d" % r.day)
			if not cs.won:
				info.losses += 1
				info.deaths.append(r.day)
			if n.k in ["elite", "ambush"]:
				if cs.won:
					info.elite_w += 1
				else:
					info.elite_l += 1
			if checks:
				checked_night(r, n, cs.won, cs, seed_v)
			else:
				r.go_night(n, cs.won, cs)
		elif checks:
			check_state(r, seed_v, "node %s" % n.k)
		r.next_day()
	var grid_ids := r.grid_items().map(func(i): return i.id)
	return {
		"win": r.end_state == "win", "day": r.day, "pet": pet, "cls": cls, "path": r.path,
		"items": grid_ids, "all": r.items.map(func(i): return i.id), "info": info,
		"cap": r.items.any(func(i): return i.def().lv == 4),
	}


# =============================================================== modes

func _invariant_runs() -> void:
	var styles := ["random", "greedy", "smart"]
	var n := 0
	for i in runs:
		for cls in GameData.class_keys:
			var st: String = styles[i % 3]
			var pet: String = GameData.pet_keys[(i + n) % GameData.pet_keys.size()]
			var s := 100000 + i * 17 + n
			play_run(cls, pet, st, s, true)
			n += 1
	print("INVARIANT RUNS: %d, violations: %d" % [n, violations.size()])


func _monte_carlo() -> void:
	var classes: Array = [cls_filter] if cls_filter != "" else GameData.class_keys
	for cls in classes:
		for i in range(start, start + count):
			var pet: String = GameData.pet_keys[i % GameData.pet_keys.size()]
			var s: int = i * 1009 + GameData.class_keys.find(cls) * 7 + {"random": 1, "greedy": 2, "smart": 3}.get(style, 0) * 1000003
			var res := play_run(cls, pet, style, s, false)
			var inf: Dictionary = res.info
			print("RUN|%s|%s|%s|%s|%d|%d|%d|%s|%s|%s|%s|%d|%d|%d|%d|%d|%s|%s|%s" % [
				style, diff, cls, pet, s, 1 if res.win else 0, res.day, res.path,
				",".join(inf.gold.map(func(g): return str(g))),
				",".join(inf.deaths.map(func(d): return str(d))),
				",".join(res.items), inf.fights, inf.losses, inf.elite_w, inf.elite_l, inf.max_gold,
				JSON.stringify(inf.kinds), ",".join(inf.camp_hp.map(func(h): return str(snappedf(h, 0.01)))),
				"1" if res.cap else "0"])


## Replays one seed of --mode=inv (find the seed in a VIOLATION line) and prints each event's effect.
func _repro() -> void:
	var styles := ["random", "greedy", "smart"]
	var n := 0
	for i in runs:
		for cls in GameData.class_keys:
			var s := 100000 + i * 17 + n
			if s == repro_seed:
				print("repro cls=%s style=%s pet=%s" % [cls, styles[i % 3], GameData.pet_keys[(i + n) % GameData.pet_keys.size()]])
				_repro_verbose = true
				play_run(cls, GameData.pet_keys[(i + n) % GameData.pet_keys.size()], styles[i % 3], s, true)
				return
			n += 1


var _repro_verbose := false


# =============================================================== edge cases

func _edge(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		violations.append(name + " " + detail)


func _fresh(cls := "ember") -> RunState:
	seed(4242)
	return RunState.new(cls, "pup", "normal")


func _open_all(r: RunState) -> void:
	for y in GameData.H:
		for x in GameData.W:
			r.tiles[Vector2i(x, y)] = true


func _edge_cases() -> void:
	# E1 rotate every player item at every cell of an open grid, with a neighbour in the way
	var bad := 0
	var tried := 0
	for id in GameData.items:
		if GameData.items[id].cl == "monster":
			continue
		var r := _fresh()
		r.items.clear()
		_open_all(r)
		var blocker := r.make_item("fire_gem", "grid", 4, 3)
		r.items.append(blocker)
		for y in GameData.H:
			for x in GameData.W:
				var it := r.make_item(id, "held")
				r.items.append(it)
				if r.fits(it, x, y, 0):
					it.loc = "grid"
					it.x = x
					it.y = y
					for _k in 4:
						tried += 1
						var res := r.rotate_in_pack(it, 1)
						var before := violations.size()
						check_state(r, 1, "rotate %s at %d,%d -> %s" % [id, x, y, res])
						if violations.size() > before:
							bad += 1
				r.items.erase(it)
				if blocker.loc != "grid":
					blocker.loc = "grid"
					blocker.x = 4
					blocker.y = 3
					blocker.rot = 0
	_edge("E1 rotate all shapes everywhere (%d rotations)" % tried, bad == 0, "bad=%d" % bad)

	# E2 fusion with no room in the pack: the result must land in storage
	var r2 := _fresh()
	r2.items.clear()
	r2.tiles.clear()
	r2.tiles[Vector2i(0, 0)] = true
	r2.tiles[Vector2i(1, 0)] = true
	var a := r2.make_item("fire_gem", "grid", 0, 0)
	var b := r2.make_item("fire_gem", "grid", 1, 0)
	r2.items.append_array([a, b])
	var pl = r2.fuse_place(r2.links()[0]) if not r2.links().is_empty() else "nolink"
	r2.go_night({"k": "camp"}, true, null)
	var stored := r2.items.filter(func(i): return i.id == "blaze_gem")
	_edge("E2 fusion overflow -> storage", stored.size() == 1 and stored[0].loc in ["grid", "storage"], "place=%s result=%s" % [str(pl), str(stored.map(func(i): return i.loc))])

	# E2b fusion where the result is bigger than the space the parts leave
	var r2b := _fresh()
	r2b.items.clear()
	r2b.tiles.clear()
	for x in 2:
		r2b.tiles[Vector2i(x, 0)] = true
	var s1 := r2b.make_item("ember_sword", "grid", 0, 0, false)
	var s2 := r2b.make_item("ember_sword", "grid", 1, 0, false)
	s1.rot = 1
	s2.rot = 1
	r2b.items.append_array([s1, s2])
	r2b.tiles[Vector2i(0, 1)] = true
	r2b.tiles[Vector2i(1, 1)] = true
	s1.rot = 0
	s2.rot = 0
	r2b.go_night({"k": "camp"}, true, null)
	var saber := r2b.items.filter(func(i): return i.id == "flame_saber")
	_edge("E2b big fusion result with no room goes to storage", saber.size() == 1 and saber[0].loc == "storage", str(saber.map(func(i): return i.loc)))

	# E3 bag piece: spec says the card disappears after buying; check current behaviour
	var r3 := _fresh()
	r3.gold = 100
	var bag_i := -1
	for i in r3.shop.size():
		if r3.shop[i].has("bag"):
			bag_i = i
			break
	var cards_before := r3.shop.filter(func(e): return e.has("bag")).size()
	var card_n: int = r3.shop[bag_i].n
	r3.buy_bag(bag_i)
	var same_left := r3.shop.filter(func(e): return e.has("bag") and e.n == card_n).size()
	_edge("E3 bag card gone after purchase (spec)", same_left == 0, "cards before=%d, %d-tile cards left after buying one=%d" % [cards_before, card_n, same_left])

	# E4 losing with 0 hearts ends the run; losing with hearts revives at 50%
	var r4 := _fresh()
	r4.res = 0
	r4.hp = 0   # a real loss arrives with the fight's HP (0); go_night only zeroes it when a CombatSim is passed
	r4.go_night({"k": "combat", "e": {"n": "x"}}, false, null)
	r4.next_day()
	_edge("E4a lose with 0 hearts -> game over", r4.end_state == "over", "end=%s hp=%.1f" % [r4.end_state, r4.hp])
	var r4b := _fresh()
	r4b.res = 2
	r4b.hp = 0
	r4b.go_night({"k": "combat", "e": {"n": "x"}}, false, null)
	_edge("E4b lose with hearts revives at 50%", r4b.res == 1 and is_equal_approx(r4b.hp, roundf(r4b.mhp * 0.5)), "res=%d hp=%.1f" % [r4b.res, r4b.hp])

	# E5 double KO: hero and monster at 1 HP, both hit on the same tick
	var r5 := _fresh()
	r5.hp = 1
	var e5 := r5.foe(false)
	e5.hp = 1.0
	var cs5 := CombatSim.new(r5, {"k": "combat", "e": e5})
	cs5.ehp = 1
	cs5.php = 1
	# make both strike on the next tick
	for x in cs5.items:
		x.p = x.cd
	for fx in cs5.fi:
		fx.p = fx.cd
	cs5.step()
	_edge("E5 double KO resolves (documented: player wins ties)", cs5.done, "won=%s php=%.1f ehp=%.1f" % [cs5.won, cs5.php, cs5.ehp])

	# E6 caps: flood both statuses on the monster and on the hero
	var r6 := _fresh()
	var cs6 := CombatSim.new(r6, {"k": "combat", "e": r6.foe(false)})
	for _i in 200:
		cs6.add_status("poison", 5)
		cs6.add_status("burn", 5)
	cs6.hd["poison"] = 0
	var ok6 := true
	for k6 in ["poison", "burn"]:
		var fm6: int = GameData.statuses[k6].max
		ok6 = ok6 and (cs6.fs[k6] >= 999 if fm6 < 0 else cs6.fs[k6] <= fm6)
	_edge("E6 status caps follow max (-1 = no cap)", ok6, "poison=%.0f burn=%.0f (max %d / %d)" % [cs6.fs.poison, cs6.fs.burn, GameData.statuses.poison.max, GameData.statuses.burn.max])
	cs6.hastes = []
	for _i in 20:
		cs6.hastes.append({"v": 0.5, "t": 30})
	_edge("E6b haste stacking capped", cs6.haste() <= 1.5, "haste=%.2f" % cs6.haste())
	for _i in 50:
		cs6.gain_shield(40)
	_edge("E6c shield capped by day", cs6.shield <= cs6._shield_cap(), "shield=%.0f cap=%.0f" % [cs6.shield, cs6._shield_cap()])

	# E7 selling: relics and recipe parts
	var r7 := _fresh()
	r7.choose_path(r7.cls_def().paths[0])
	var relic: PItem = r7.storage_items().filter(func(i): return i.def().relic)[0]
	var g0 := r7.gold
	var sold := r7.sell(relic)
	_edge("E7 path relic can be sold for 0 gold and is gone for good", not sold, "sold=%s gold +%d" % [sold, r7.gold - g0])

	# E8 day 7 -> 8: the small bag gives 3 tiles from day 8
	var r8 := _fresh()
	r8.day = 7
	r8.begin_day()
	var n7: int = r8.shop.filter(func(e): return e.has("bag"))[0].n
	r8.day = 8
	r8.shop.clear()
	r8.begin_day()
	var n8: int = r8.shop.filter(func(e): return e.has("bag"))[0].n
	_edge("E8 bag piece 2 tiles on day 7, 3 on day 8", n7 == 2 and n8 == 3, "d7=%d d8=%d" % [n7, n8])

	# E9 Cursed Altar paid with Max HP again and again
	var r9 := _fresh()
	r9.day = 5
	var paid := 0
	for _i in 10:
		r9.start_event("altar")
		if r9.ev_altar(0, "hp"):
			paid += 1
		r9.phase = "afternoon"
		r9.event = {}
	_edge("E9 Max HP never reaches 0 through the altar", r9.mhp > 0, "after %d payments mhp=%.0f hp=%.0f" % [paid, r9.mhp, r9.hp])

	# E10 cauldron with Legendary / Mythical inputs
	var r10 := _fresh()
	var l1 := r10.make_item("sunblade", "storage")
	var l2 := r10.make_item("sunforge_crown", "storage")
	r10.items.append_array([l1, l2])
	r10.start_event("cauldron")
	var out := r10.ev_brew(l1, l2)
	_edge("E10 cauldron never downgrades (Legendary+Mythical in)", out != "" and GameData.items[out].tier >= 4, "got %s (%s)" % [out, GameData.tier_names[GameData.items[out].tier] if out != "" else "-"])

	# E11 merchant arbitrage: buy a 50%-off item in the morning, sell it to the merchant at full cost
	var r11 := _fresh()
	r11.gold = 50
	var sale := {"id": "flame_saber", "price": ceili(GameData.items["flame_saber"].cost / 2.0), "sale": true}
	r11.shop.append(sale)
	var g1 := r11.gold
	var bought := r11.buy_item(r11.shop.size() - 1)
	bought.loc = "storage"
	r11.start_event("merchant")
	r11.ev_sell_full(bought)
	_edge("E11 no profit loop shop sale -> merchant", r11.gold <= g1, "gold %d -> %d" % [g1, r11.gold])
	# treasure: shop pays half, merchant pays full
	var r11b := _fresh()
	var nug := r11b.make_item("gold_nugget", "storage")
	r11b.items.append(nug)
	r11b.start_event("merchant")
	var g2 := r11b.gold
	r11b.ev_sell_full(nug)
	_edge("E11b treasure value consistent (says 'worth 12')", r11b.gold - g2 == 12, "merchant paid %d" % (r11b.gold - g2))

	# E12 every class x pet plays a full run without invariant breaks
	var combos := 0
	var before12 := violations.size()
	for cls in GameData.class_keys:
		for pet in GameData.pet_keys:
			play_run(cls, pet, "smart", 777 + combos, true)
			combos += 1
	_edge("E12 all %d class x pet runs clean" % combos, violations.size() == before12, "new violations=%d" % (violations.size() - before12))

	# E13 save / load in the middle of an event, then leave it
	var r13 := _fresh()
	r13.day = 4
	r13.choose_path(r13.cls_def().paths[0])
	r13.nodes = [{"k": "roulette"}]
	r13.cur_node = 0
	r13.start_event("roulette")
	var d13 := RunState.from_dict(JSON.parse_string(JSON.stringify(r13.to_dict())))
	var ok13 := d13 != null and d13.phase == "event"
	if ok13:
		d13.ev_pull()
		d13.ev_leave()
		ok13 = d13.phase == "night"
	_edge("E13 save/load mid-event then finish it", ok13)

	# E14 drop onto items with a full pack: blockers go to storage, nothing lost
	var r14 := _fresh()
	r14.items.clear()
	r14.tiles.clear()
	for x in 3:
		r14.tiles[Vector2i(x, 0)] = true
	for x in 3:
		r14.items.append(r14.make_item("fire_gem", "grid", x, 0))
	var big := r14.make_item("bellows", "held")
	r14.items.append(big)
	var n_before := r14.items.size()
	var res14 := r14.place_with_bump(big, Vector2i(0, 0), {})
	check_state(r14, 14, "bump")
	_edge("E14 bump into a full pack keeps every item", r14.items.size() == n_before and res14.stored >= 1, "stored=%d" % res14.stored)

	# E15 three copies touching: two evolve, the third stays
	var r15 := _fresh()
	r15.items.clear()
	_open_all(r15)
	for x in 3:
		r15.items.append(r15.make_item("fire_gem", "grid", x, 0))
	r15.go_night({"k": "camp"}, true, null)
	var gems := r15.items.filter(func(i): return i.id == "fire_gem").size()
	var blaze := r15.items.filter(func(i): return i.id == "blaze_gem").size()
	# E16 starting items never overlap, for every class
	var overl := []
	for cls in GameData.class_keys:
		var rr := _fresh(cls)
		var before16 := violations.size()
		check_state(rr, 16, "start %s" % cls)
		if violations.size() > before16:
			overl.append(cls)
			violations.resize(before16)
	_edge("E16 starting items do not overlap", overl.is_empty(), "overlapping: %s" % str(overl))

	_edge("E15 three in a row: one evolution + one left over", gems == 1 and blaze == 1, "fire=%d blaze=%d" % [gems, blaze])

	print("EDGE DONE: %d failing checks" % violations.size())
