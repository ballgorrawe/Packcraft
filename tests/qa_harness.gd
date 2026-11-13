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
var endless_on := false   # --endless=1: after the day-15 win, keep going until the run ends
var pro_cfg := {}      # --cfg=key:val,key:val  pro bot weights (aff, cap, fuse, verify, sim_w, rr, min_gain, elite)
var force_boss := ""   # --boss=Name: every run meets this boss on its day (balance checks)
var start := 0
var count := 10
var runs := 20
var violations: Array = []
var repro_seed := 0
# --mode=trace: one recorded pro run per class (every decision with its numbers) -> --out JSON
var tr_on := false
var cs_on := false        # --mode=cstats: measure the pack on the training dummy on days 5, 10, 15
var cs_marks := {}
var tr_day := {}
var tr_days: Array = []
var tr_out := "user://bot_trace.json"


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
			"endless": endless_on = v == "1"
			"start": start = int(v)
			"count": count = int(v)
			"runs": runs = int(v)
			"seed": repro_seed = int(v)
			"boss": force_boss = v
			"out": tr_out = v
			"cfg":
				for pair in v.split(",", false):
					pro_cfg[pair.get_slice(":", 0)] = float(pair.get_slice(":", 1))
	match mode:
		"edge": _edge_cases()
		"inv": _invariant_runs()
		"mc": _monte_carlo()
		"trace": _trace_runs()
		"repro": _repro()
		"cstats": _class_stats()
		"one": _one_run()
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
			links += 2 if l.get("c") != null else 1   # a Masterwork uses up three items
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
	if st == "pro":
		_pro_morning(r)
		return
	# the simple bots take the first level-up bonus offered
	while not r.picks.is_empty():
		r.pick_level(0)
	if r.needs_path():
		r.choose_path(r.cls_def().paths.pick_random())
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
	if st == "pro":
		return _pro_node(r)
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


## A pack as text for the Bot Lab dashboard: day#tiles#items, tiles "x.y" and items "id:x:y:rot" joined by ";".
func _board(r: RunState) -> String:
	var t := r.tiles.keys().map(func(c): return "%d.%d" % [c.x, c.y])
	var it := r.grid_items().map(func(i): return "%s:%d:%d:%d" % [i.id, i.x, i.y, i.rot])
	return "%d#%s#%s" % [r.day, ";".join(t), ";".join(it)]


## Plays one full run. Returns a summary dictionary.
func play_run(cls: String, pet: String, st: String, seed_v: int, checks: bool) -> Dictionary:
	seed(seed_v)
	var r := RunState.new(cls, pet, diff)
	if force_boss != "":
		for b in GameData.bosses:
			if b.n == force_boss:
				r.boss_pick[b.d] = b.n
	var info := {"gold": [], "deaths": [], "kinds": {}, "elite_w": 0, "elite_l": 0, "camp_hp": [], "fights": 0, "losses": 0, "max_gold": 0, "bosses": [], "boards": []}
	var guard := 0
	while r.end_state == "" and guard < (120 if endless_on else 60):
		guard += 1
		bot_morning(r, st)
		if r.day in [5, 10, 15] or (r.endless and r.day % 10 == 0):
			info.boards.append(_board(r))   # the pack it takes into each boss fight (Bot Lab shows it)
		if cs_on and r.day in [5, 10, 15] and not cs_marks.has(r.day):
			cs_marks[r.day] = r.bench_rates(12.0)
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
			elif st == "pro" and float(pro_cfg.get("events", 1.0)) > 0.0:
				_pro_event(r)
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
			if n.k == "boss":
				info.bosses.append("%s:%d" % [n.e.n, 1 if cs.won else 0])
			if not cs.won:
				info.losses += 1
				info.deaths.append(r.day)
			if n.k in ["elite", "ambush", "mini"]:
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
		if tr_on:
			_tr_end_day(r, n, cs)
		r.next_day()
		if endless_on and r.end_state == "win" and not r.endless:
			r.end_state = ""
			r.go_endless()
			r.next_day()
	var grid_ids := r.grid_items().map(func(i): return i.id)
	return {
		"win": r.end_state == "win", "day": r.day, "pet": pet, "cls": cls, "path": r.path,
		"items": grid_ids, "all": r.items.map(func(i): return i.id), "info": info,
		"cap": r.items.any(func(i): return i.def().lv == 4), "lv": r.lv,
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
			var s: int = i * 1009 + GameData.class_keys.find(cls) * 7 + {"random": 1, "greedy": 2, "smart": 3, "pro": 3}.get(style, 0) * 1000003
			var res := play_run(cls, pet, style, s, false)
			var inf: Dictionary = res.info
			print("RUN|%s|%s|%s|%s|%d|%d|%d|%s|%s|%s|%s|%d|%d|%d|%d|%d|%s|%s|%s|%d|%s|%s" % [
				style, diff, cls, pet, s, 1 if res.win else 0, res.day, res.path,
				",".join(inf.gold.map(func(g): return str(g))),
				",".join(inf.deaths.map(func(d): return str(d))),
				",".join(res.items), inf.fights, inf.losses, inf.elite_w, inf.elite_l, inf.max_gold,
				JSON.stringify(inf.kinds), ",".join(inf.camp_hp.map(func(h): return str(snappedf(h, 0.01)))),
				"1" if res.cap else "0", res.lv, ",".join(inf.bosses), "~".join(inf.boards)])


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

	# E9 Cursed Altar: the only price is a Heart (never Max HP), and not when you have none
	var r9 := _fresh()
	r9.day = 5
	var mhp9 := r9.mhp
	var hp_paid := 0
	var hearts_paid := 0
	for _i in 5:
		r9.start_event("altar")
		if r9.ev_altar(0, "hp"):
			hp_paid += 1
		if r9.ev_altar(0, "heart"):
			hearts_paid += 1
		r9.phase = "afternoon"
		r9.event = {}
	_edge("E9 altar takes only Hearts", hp_paid == 0 and hearts_paid == RunState.MAX_HEARTS and r9.res == 0 and r9.mhp == mhp9 and not r9.event_ok("altar"), "hp payments=%d heart payments=%d hearts left=%d mhp %.0f->%.0f" % [hp_paid, hearts_paid, r9.res, mhp9, r9.mhp])

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


# =============================================================== pro bot
# Plays like a careful human: it uses the game's own forecasts (the drag preview's damage/shield
# delta and a no-dice fight simulation) to pick its path, level-up bonuses, buys, placement and
# road, rearranges the pack, sells what it cannot use and rerolls a few times.

## How strong the pack is: a no-dice fight against today's monster and the next boss.
## Win: 2 - share of HP lost (faster is a hair better). Loss: share of the monster's HP removed.
func _pro_value(r: RunState, benches: Array) -> float:
	r.calc()
	var s := 0.0
	for e in benches:
		var cs := CombatSim.new(r, {"k": "preview", "e": e}, true)
		cs.skip_to_end()
		if cs.won:
			s += 2.0 - float(pro_cfg.get("hpw", 1.0)) * maxf(0.0, r.hp - cs.php) / maxf(1.0, r.mhp) - cs.tk / 6000.0
		else:
			s += 1.0 - maxf(0.0, cs.ehp) / maxf(1.0, cs.e.hp)
	return s


func _pro_benches(r: RunState) -> Array:
	var out := [r.with_hazard(r.foe(false))]
	for d in range(r.day, GameData.days + 1):
		var b = r.boss_on(d)
		if b != null:
			out.append(r.boss_foe(b))
			break
	return out


func _pro_rate(rates: Vector2) -> float:
	return rates.x + 0.7 * rates.y


## Best spot for a held item by the drag preview: damage + shield gained, plus fusion links.
func _pro_spot(r: RunState, it: PItem) -> Dictionary:
	var best := {}
	var base := _pro_rate(r.pack_rates())
	var seen_shapes := {}
	var keep_rot := it.rot
	var keep_loc := it.loc
	for rot in 4:
		var key := str(GameData.shape(it.id, rot).c)
		if seen_shapes.has(key):
			continue
		seen_shapes[key] = true
		it.rot = rot
		for y in GameData.H:
			for x in GameData.W:
				if not r.fits(it, x, y):
					continue
				it.loc = "grid"
				it.x = x
				it.y = y
				var g := _pro_rate(r.pack_rates()) - base
				if r.links().any(func(l): return l.a == it or l.b == it or l.get("c") == it):
					g += 4.0
				elif _pro_mw_parts(r).has(it.id):
					# Masterwork pieces: keep them together so the third one can join
					for nb in r.neighbours(it):
						if nb.id != it.id and _pro_mw_parts(r).has(nb.id):
							g += 2.0
				it.loc = keep_loc
				if best.is_empty() or g > best.g:
					best = {"x": x, "y": y, "rot": rot, "g": g}
	it.rot = keep_rot
	it.loc = keep_loc
	r.calc()
	return best


func _pro_put(it: PItem, s: Dictionary) -> void:
	it.loc = "grid"
	it.x = s.x
	it.y = s.y
	it.rot = s.rot


## What one pack item adds (rates with it minus without it).
func _pro_contrib(r: RunState, it: PItem) -> float:
	var with_it := _pro_rate(r.pack_rates())
	var prev := it.loc
	it.loc = "storage"
	var without := _pro_rate(r.pack_rates())
	it.loc = prev
	r.calc()
	return with_it - without


func _pro_morning(r: RunState) -> void:
	var benches := _pro_benches(r)
	if tr_on:
		tr_day = {"day": r.day, "gold0": r.gold, "hp0": snappedf(r.hp, 0.1), "mhp0": snappedf(r.mhp, 0.1), "lv": r.lv, "hearts": r.res, "steps": [], "bench": benches.map(func(e): return e.n)}
	# path: try both, keep the stronger pack
	if r.needs_path():
		var best_p := ""
		var best_v := -1.0
		for p in r.cls_def().paths:
			r.choose_path(p)
			var relic: PItem = r.items[r.items.size() - 1]
			relic.loc = "held"
			var s := _pro_spot(r, relic)
			if not s.is_empty():
				_pro_put(relic, s)
			var v := _pro_value(r, benches)
			r.items.erase(relic)
			r.path = ""
			if tr_on:
				tr_day["path_opts"] = tr_day.get("path_opts", []) + [{"p": p, "v": snappedf(v, 0.01)}]
			if v > best_v:
				best_v = v
				best_p = p
		r.choose_path(best_p)
		if tr_on:
			tr_day["path"] = best_p
	# level-up bonuses: try each of the 3, keep the best
	while not r.picks.is_empty():
		var best_i := 0
		var best_v := -1.0
		var hp0 := r.hp
		for i in r.picks[0].size():
			var pd := r.pick_def(r.picks[0][i])
			r.lvl_bonus[pd.k] = r.lvl_bonus.get(pd.k, 0.0) + float(pd.v)
			r.sync_hp()
			var v := _pro_value(r, benches)
			r.lvl_bonus[pd.k] -= float(pd.v)
			r.sync_hp()
			r.hp = hp0
			if tr_on:
				tr_day["lv_opts"] = tr_day.get("lv_opts", []) + [{"id": pd.id, "v": snappedf(v, 0.01)}]
			if v > best_v:
				best_v = v
				best_i = i
		if tr_on:
			tr_day["lv_pick"] = r.picks[0][best_i]
		r.pick_level(best_i)
	# bags: when the pack is nearly full, or when gold is piling up (up to 2 a day)
	for _b in 2:
		if not (_free_tiles(r) < 4 or r.gold > 22):
			break
		var bought := false
		for i in r.shop.size():
			if r.shop[i].has("bag") and r.shop[i].price + 4 <= r.gold:
				if tr_on:
					tr_day["steps"].append({"a": "bag", "n": r.shop[i].n, "price": r.shop[i].price})
				r.buy_bag(i)
				bought = true
				break
		if not bought:
			break
	_unlock_all(r)
	# relics and storage items into their best spots
	for it in r.storage_items():
		it.loc = "held"
		var s := _pro_spot(r, it)
		if not s.is_empty() and (s.g > 0.05 or it.def().relic):
			_pro_put(it, s)
		else:
			it.loc = "storage"
	# rearrange: every pack item moves to its best spot (a few passes, kept only if the fight agrees)
	var passes := int(pro_cfg.get("place", 1.0))
	var snap := r.grid_items().map(func(g): return [g, g.x, g.y, g.rot])
	var pv0 := _pro_value(r, benches) if passes > 1 else 0.0
	for _pass in passes:
		_pro_rearrange(r)
	if passes > 1 and _pro_value(r, benches) < pv0 - 0.001:
		for sn in snap:
			sn[0].loc = "held"
		for sn in snap:
			sn[0].loc = "grid"
			sn[0].x = sn[1]
			sn[0].y = sn[2]
			sn[0].rot = sn[3]
		r.calc()
	_pro_shop(r, benches)


func _pro_rearrange(r: RunState) -> void:
	for it in r.grid_items():
		var ox: int = it.x
		var oy: int = it.y
		var orot: int = it.rot
		it.loc = "held"
		var s := _pro_spot(r, it)
		if s.is_empty():
			it.loc = "grid"
			it.x = ox
			it.y = oy
			it.rot = orot
		else:
			_pro_put(it, s)


func _pro_shop(r: RunState, benches: Array) -> void:
	# shopping, build-aware: every affordable card is tried in its best spot (swapping out the weakest
	# item when the pack is full), scored by the damage/shield it adds plus build bonuses (class
	# resource tags, the path's Masterwork ingredients, fusion partners); the top few are then checked
	# with a real fight simulation before buying.
	var rerolls := 0
	var build := _pro_build_tags(r)
	var planning := float(pro_cfg.get("plan", 1.0)) > 0.0
	# gold expected tomorrow morning (to judge what can be saved for)
	var income_next: int = 5 + int((r.day + 1) / 2) + r.income()
	for _step in 12:
		var cands := []
		# saving target: a fusion / evolution / Masterwork piece in the shop that is not affordable yet
		var target := {}
		if planning:
			for i in r.shop.size():
				var e0: Dictionary = r.shop[i]
				if e0.has("bag") or e0.price <= r.gold or e0.price > r.gold + income_next:
					continue
				var fv0 := _pro_fusion_value(r, e0.id)
				if fv0 > 0.5 and (target.is_empty() or fv0 / e0.price > target.score):
					target = {"i": i, "id": e0.id, "price": e0.price, "score": fv0 / e0.price, "fv": fv0}
		for i in r.shop.size():
			var e: Dictionary = r.shop[i]
			if e.has("bag") or e.price > r.gold:
				continue
			var tmp := r.make_item(e.id, "held")
			r.items.append(tmp)
			var s := _pro_spot(r, tmp)
			var gain: float = s.g if not s.is_empty() else -99.0
			var out: PItem = null
			if s.is_empty() or gain < 0.2:
				# full pack: would it beat the weakest item?
				var weak: PItem = null
				var wv := 99.0
				for g in r.grid_items():
					if g.def().relic or g == tmp:
						continue
					var c := _pro_contrib(r, g)
					if c < wv:
						wv = c
						weak = g
				if weak != null:
					weak.loc = "storage"
					var s2 := _pro_spot(r, tmp)
					weak.loc = "grid"
					if not s2.is_empty() and s2.g - wv > gain:
						gain = s2.g - wv
						s = s2
						out = weak
			r.items.erase(tmp)
			r.calc()
			gain += _pro_build_bonus(r, e.id, build)
			# what it becomes after tonight's fusion / evolution / Masterwork
			var fv := _pro_fusion_value(r, e.id) if planning else 0.0
			if fv > 0.0:
				gain = maxf(gain, 0.85 * fv + _pro_build_bonus(r, e.id, build))
			if s.is_empty() and gain < 2.0:
				continue
			cands.append({"i": i, "s": s, "out": out, "gain": gain, "h": snappedf(gain, 0.01), "fv": snappedf(fv, 0.01), "price": float(e.price), "id": e.id})
		cands.sort_custom(func(a, b): return a.gain / maxf(1.0, a.price) > b.gain / maxf(1.0, b.price))
		# simall: every affordable card goes to the fight check (heals and Max HP do not show in damage/shield rates)
		var simall := float(pro_cfg.get("simall", 1.0)) > 0.0
		if not simall:
			cands = cands.filter(func(c): return c.gain > float(pro_cfg.get("min_gain", 0.3)))
		# fight-check the best few: value gained in a no-dice fight, per gold
		var n_check := int(pro_cfg.get("verify", 3)) if not simall else 10
		if n_check > 0 and (cands.size() > 1 or simall):
			var v0 := _pro_value(r, benches)
			for c in cands.slice(0, n_check):
				var tmp2 := r.make_item(c.id, "held")
				r.items.append(tmp2)
				if c.out != null:
					c.out.loc = "storage"
				if not c.s.is_empty():
					_pro_put(tmp2, c.s)
				var dv := _pro_value(r, benches) - v0
				if c.out != null:
					c.out.loc = "grid"
				r.items.erase(tmp2)
				c.gain += float(pro_cfg.get("sim_w", 25.0)) * dv
				c["dv"] = snappedf(dv, 0.001)
			r.calc()
			if simall:
				cands = cands.filter(func(c): return c.gain > float(pro_cfg.get("min_gain", 0.3)))
			cands.sort_custom(func(a, b): return a.gain / maxf(1.0, a.price) > b.gain / maxf(1.0, b.price))
		# save for the target: lock it and only buy what still leaves enough gold for it tomorrow
		var reserve := 0
		if not target.is_empty():
			var best_aff: float = cands[0].gain / maxf(1.0, cands[0].price) if not cands.is_empty() else 0.0
			if target.score >= best_aff * 1.2:
				if not r.shop[target.i].get("lock", false):
					r.toggle_lock(target.i)
					if tr_on:
						tr_day["steps"].append({"a": "lock", "id": target.id, "price": target.price, "fv": snappedf(target.fv, 0.01)})
				reserve = maxi(0, int(target.price) - income_next)
				cands = cands.filter(func(c): return r.gold - c.price >= reserve or c.gain / maxf(1.0, c.price) >= target.score * 1.5)
		var pick: Dictionary = cands[0] if not cands.is_empty() and cands[0].gain > 0.3 else {}
		if tr_on:
			var step := {"a": "look", "gold": r.gold, "shop": r.shop.filter(func(e): return not e.has("bag")).map(func(e): return {"id": e.id, "price": e.price}),
				"cands": cands.slice(0, 5).map(func(c): return {"id": c.id, "price": c.price, "h": c.h, "fv": c.get("fv", 0.0), "dv": c.get("dv", null), "score": snappedf(c.gain / maxf(1.0, c.price), 0.001), "out": c.out.id if c.out != null else ""})}
			if not pick.is_empty():
				step["buy"] = pick.id
				step["swap"] = pick.out.id if pick.out != null else ""
			tr_day["steps"].append(step)
		if not pick.is_empty():
			if pick.out != null:
				pick.out.loc = "storage"
			var it := r.buy_item(pick.i)
			if it == null:
				break
			if not pick.s.is_empty() and r.fits(it, pick.s.x, pick.s.y, pick.s.rot):
				_pro_put(it, pick.s)
			else:
				it.loc = "storage"
			continue
		if rerolls < int(pro_cfg.get("rr", 3)) + (2 if planning and _pro_hunting(r) else 0) and r.gold - r.reroll_cost() >= 4 + reserve:
			if tr_on:
				tr_day["steps"].append({"a": "reroll", "cost": r.reroll_cost()})
			r.reroll()
			rerolls += 1
			continue
		break
	# storage: sell what cannot help (keep fusion partners, starters and relics)
	for it in r.storage_items():
		if it.def().relic or it.starter:
			continue
		if not it.def().tags.has("Treasure") and _pro_seed_bonus(r, it.id) > 0.0 and r.storage_items().filter(func(q): return _pro_seed_bonus(r, q.id) > 0.0).size() <= 2:
			continue
		if it.def().tags.has("Treasure") or not r.recipe_partner_owned(it.id, true):
			if tr_on:
				tr_day["sold"] = tr_day.get("sold", []) + [it.id]
			r.sell(it)
	r.calc()
	if tr_on:
		tr_day["pack"] = _tr_pack(r)
		tr_day["rates"] = [snappedf(r.pack_rates().x, 0.1), snappedf(r.pack_rates().y, 0.1)]
		tr_day["gold1"] = r.gold
		tr_day["storage"] = r.storage_items().map(func(i): return i.id)


## Road: forecast every fight; take Elites when they look safe, rest when hurt, avoid losing fights.
func _pro_node(r: RunState) -> int:
	var best := 0
	var best_s := -99.0
	# boss prep: a boss tomorrow (or the day after) is judged with the HP each choice leaves
	var prep := float(pro_cfg.get("prep", 0.0))
	var boss_e = null
	var dtb := 99
	if prep > 0.0:
		for d in range(r.day + 1, mini(r.day + 2, GameData.days) + 1):
			var b = r.boss_on(d)
			if b != null:
				boss_e = r.boss_foe(b)
				dtb = d - r.day
				break
	for i in r.nodes.size():
		var n: Dictionary = r.nodes[i]
		var s := 0.0
		var h_after := r.hp
		if n.has("e"):
			r.calc()
			var cs := CombatSim.new(r, {"k": "preview", "e": r.with_hazard(n.e)}, true)
			cs.skip_to_end()
			var lost := maxf(0.0, r.hp - cs.php) / maxf(1.0, r.mhp)
			if tr_on:
				tr_day["fc"] = tr_day.get("fc", []) + [{"i": i, "won": cs.won, "lost": snappedf(lost, 0.01), "left": snappedf(maxf(0.0, cs.ehp) / maxf(1.0, cs.e.hp), 0.01), "secs": cs.tk / 10.0}]
			h_after = cs.php if cs.won else r.mhp * 0.5
			if cs.won:
				s = (float(pro_cfg.get("elite", 3.0)) if n.k in ["elite", "ambush", "boss", "mini"] else 2.2) - 1.5 * lost
			else:
				s = -5.0 + (1.0 - maxf(0.0, cs.ehp) / maxf(1.0, cs.e.hp))
		else:
			if n.k != "camp" and float(pro_cfg.get("events", 1.0)) > 0.0:
				s = _pro_event_score(r, n.k)
			else:
				match n.k:
					"camp": s = 2.6 if r.hp < r.mhp * 0.55 else 0.4
					"smith": s = 1.6
					"chest": s = 1.5
					"merchant": s = 1.2
					"roulette": s = 1.0
					"cauldron": s = 1.0
					"altar": s = 0.6
					_: s = 0.8
		if n.k == "camp":
			h_after = minf(r.mhp, r.hp + roundf(r.mhp * 0.5))
		if boss_e != null:
			s += prep * (1.0 if dtb == 1 else 0.5) * _pro_boss_at(r, boss_e, h_after)
		if tr_on:
			var o := {"k": n.k, "score": snappedf(s, 0.01)}
			if n.has("e"):
				o["foe"] = n.e.n
				o["tr"] = n.e.get("tr", "")
				o["pet"] = n.e.get("pet", "")
				o["mech"] = n.e.get("mech", {}).get("n", "")
			tr_day["road"] = tr_day.get("road", []) + [o]
		if s > best_s:
			best_s = s
			best = i
	if tr_on:
		tr_day["pick"] = best
	return best


## How the boss fight goes (no dice) if the hero walks in with h HP: 2 - share of HP lost on a win, share of the boss beaten on a loss.
func _pro_boss_at(r: RunState, e: Dictionary, h: float) -> float:
	var keep := r.hp
	r.hp = maxf(1.0, h)
	r.calc()
	var cs := CombatSim.new(r, {"k": "preview", "e": e}, true)
	cs.skip_to_end()
	var v := (2.0 - maxf(0.0, r.hp - cs.php) / maxf(1.0, r.mhp)) if cs.won else (1.0 - maxf(0.0, cs.ehp) / maxf(1.0, cs.e.hp))
	r.hp = keep
	r.calc()
	return v


## Tags the build cares about: the class resource's tags and every tag of the path's Masterwork recipe.
func _pro_build_tags(r: RunState) -> Dictionary:
	var tags := {}
	var rd: Dictionary = r.cls_def().res
	for k in ["tag", "etag"]:
		if str(rd.get(k, "")) != "":
			tags[str(rd[k])] = true
	var parts := {}
	for rc in GameData.recipes:
		if r.path != "" and str(rc.get("path", "")) == r.path:
			parts[rc.a] = true
			parts[rc.b] = true
			if rc.get("c", "") != "":
				parts[rc.c] = true
	# ingredients of those ingredients (e.g. Dire Wolf <- Wolf Pup + Raw Meat)
	for rc in GameData.recipes:
		if parts.has(rc.r):
			parts[rc.a] = true
			parts[rc.b] = true
	for id in parts:
		if GameData.items.has(id):
			for t in GameData.items[id].tags:
				if t != "Weapon":
					tags[t] = true
	return {"tags": tags, "parts": parts}


## Future value of an item for this build (on top of what it adds today).
func _pro_build_bonus(r: RunState, id: String, build: Dictionary) -> float:
	var d: Dictionary = GameData.items[id]
	var b := 0.0
	var w := float(pro_cfg.get("aff", 1.5))
	for t in d.tags:
		if build.tags.has(t):
			b += w
			break
	if build.parts.has(id):
		b += float(pro_cfg.get("cap", 3.0))
	if r.recipe_partner_owned(id):
		b += float(pro_cfg.get("fuse", 3.0))
	else:
		b += _pro_seed_bonus(r, id)
	# ⭐ growth: worth more the more fights are left to grow in
	var gr: Dictionary = d.get("grow", {})
	if not gr.is_empty():
		var left := mini(int(gr.get("max", 12)), maxi(0, GameData.days - r.day))
		b += float(pro_cfg.get("grow", 0.35)) * float(gr.get("v", 1.0)) * left * (2.0 if gr.get("adj", false) else 1.0)
	return b


## Half a recipe: worth buying early when the other half can still show up in the shop and the result
## is rarer (the way players buy toward a fusion). Fewer new seeds once a few are already waiting.
func _pro_seed_bonus(r: RunState, id: String) -> float:
	var w := float(pro_cfg.get("seed", 0.0))
	if w <= 0.0 or r.day > 12:
		return 0.0
	var best := 0.0
	var t0: int = GameData.items[id].tier
	for rc in GameData.recipes:
		if str(rc.get("c", "")) != "" or not r.recipe_ok(rc) or (rc.a != id and rc.b != id):
			continue
		var other: String = rc.b if rc.a == id else rc.a
		if not GameData.items.has(other) or not r.in_class_pool(other) or int(GameData.items[other].tier) > 3:
			continue
		best = maxf(best, float(int(GameData.items[rc.r].tier) - t0))
	if best <= 0.0:
		return 0.0
	return w * best / (1.0 + 0.5 * _pro_seeds_waiting(r))


## Owned items waiting for their recipe partner.
func _pro_seeds_waiting(r: RunState) -> int:
	var n := 0
	for it in r.items:
		if it.loc == "held" or it.def().relic or r.recipe_partner_owned(it.id, true):
			continue
		for rc in GameData.recipes:
			if str(rc.get("c", "")) == "" and r.recipe_ok(rc) and (rc.a == it.id or rc.b == it.id):
				n += 1
				break
	return n


## Ingredients of the chosen path's Masterwork (empty before the path or after it was made).
func _pro_mw_parts(r: RunState) -> Dictionary:
	var out := {}
	if r.path == "" or r.mw_done:
		return out
	for rc in GameData.recipes:
		if rc.get("c", "") != "" and rc.path == r.path:
			out[rc.a] = true
			out[rc.b] = true
			out[rc.c] = true
	return out


# =============================================================== one traced run (--mode=one --cls=x --seed=n --pet=p)
func _one_run() -> void:
	tr_on = true
	tr_days = []
	tr_day = {}
	var pet := "pup"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pet="):
			pet = a.substr(6)
	var res := play_run(cls_filter, pet, "pro", repro_seed, false)
	for d in tr_days.slice(0, 3):
		print("day %s node=%s foe=%s won=%s foe_hp=%s hp %s->%s road=%s" % [d.get("day"), d.get("node"), d.get("foe", ""), d.get("won"), d.get("foe_hp"), d.get("hp0"), d.get("hp1"), JSON.stringify(d.get("road", []))])
		print("   pack: ", d.get("pack", {}).get("items", []).map(func(i): return i.id), " fc=", JSON.stringify(d.get("fc", [])))
	print("win=", res.win)


# =============================================================== class stats (--mode=cstats)
# Real numbers behind the class picker: the starting kit on the training dummy, and the pro bot's pack
# on days 5 / 10 / 15 (its damage, shield and healing per second, Max HP) plus its win rate.
# Writes one JSON line per class: CSTATS|{...}

func _class_stats() -> void:
	cs_on = true
	var classes: Array = [cls_filter] if cls_filter != "" else GameData.class_keys
	for cls in classes:
		var r0 := RunState.new(cls, "", diff)
		r0.mod = {"id": "", "n": "", "d": ""}
		var out := {"cls": cls, "start": r0.bench_rates(12.0), "days": {}, "wins": 0, "n": 0}
		for k in count:
			cs_marks = {}
			var pet: String = GameData.pet_keys[k % GameData.pet_keys.size()]
			var res := play_run(cls, pet, "pro", 5000000 + k * 7919 + GameData.class_keys.find(cls) * 131, false)
			out.n += 1
			if res.win:
				out.wins += 1
			for d in cs_marks:
				var acc: Dictionary = out.days.get(str(d), {"dps": 0.0, "sps": 0.0, "hps": 0.0, "hp": 0.0, "n": 0})
				for key in ["dps", "sps", "hps", "hp"]:
					acc[key] += cs_marks[d][key]
				acc.n += 1
				out.days[str(d)] = acc
		print("CSTATS|" + JSON.stringify(out))


# =============================================================== trace (--mode=trace)

func _tr_pack(r: RunState) -> Dictionary:
	var its := []
	for it in r.grid_items():
		var d: Dictionary = it.def()
		its.append({"id": it.id, "n": d.n, "ic": d.ic, "t": d.tier, "cells": it.cells().map(func(c): return [c.x, c.y]), "gc": it.gc, "pd": snappedf(it.pd, 0.1), "mw": d.tier >= 6})
	return {"tiles": (r.tiles.keys() if r.tiles is Dictionary else r.tiles).map(func(c): return [c.x, c.y]), "items": its}


func _tr_end_day(r: RunState, n: Dictionary, cs) -> void:
	tr_day["node"] = n.k
	if n.has("e"):
		tr_day["foe"] = n.e.n
	if cs != null:
		tr_day["won"] = cs.won
		tr_day["secs"] = cs.tk / 10.0
		tr_day["dealt"] = roundi(cs.e.hp - maxf(0.0, cs.ehp))
		tr_day["foe_hp"] = roundi(cs.e.hp)
		var top := []
		for x in cs.items:
			top.append({"id": x.d.n, "ic": x.d.ic, "dmg": roundi(x.st.dmg + x.st.dot.values().reduce(func(a, b): return a + b, 0.0)), "sh": roundi(x.st.shield), "heal": roundi(x.st.heal)})
		top.sort_custom(func(a, b): return a.dmg + a.sh + a.heal > b.dmg + b.sh + b.heal)
		tr_day["top"] = top.slice(0, 4)
		tr_day["ults"] = cs.ults
	tr_day["hp1"] = snappedf(r.hp, 0.1)
	tr_day["mhp1"] = snappedf(r.mhp, 0.1)
	tr_day["hearts1"] = r.res
	tr_day["rew"] = r.result.get("rew", []).map(func(w):
		var o := {"k": w.k}
		for key in ["v", "id", "r", "a", "b", "c", "mw", "evo"]:
			if w.has(key):
				o[key] = w[key]
		return o)
	tr_days.append(tr_day)
	tr_day = {}


## One recorded run per class: the first winning seed (or the last tried), every decision kept.
func _trace_runs() -> void:
	tr_on = true
	var out := []
	var classes: Array = [cls_filter] if cls_filter != "" else GameData.class_keys
	for cls in classes:
		var best := {}
		for k in 6:
			var s: int = 777 + k * 131 + GameData.class_keys.find(cls) * 17
			var pet: String = GameData.pet_keys[(k + GameData.class_keys.find(cls)) % GameData.pet_keys.size()]
			tr_days = []
			tr_day = {}
			var res := play_run(cls, pet, "pro", s, false)
			best = {"cls": cls, "pet": pet, "seed": s, "diff": diff, "win": res.win, "path": res.path, "lv": res.lv, "days": tr_days.duplicate(true)}
			print("trace %s seed %d win=%s days=%d" % [cls, s, res.win, tr_days.size()])
			if res.win:
				break
		out.append(best)
	var f := FileAccess.open(tr_out, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("TRACE DONE: %d runs -> %s" % [out.size(), tr_out])


## How much the pack gains once buying `id` completes a fusion, an evolution or the Masterwork tonight:
## the pack with the result in place of the owned pieces, minus the pack now. 0 if nothing completes.
func _pro_fusion_value(r: RunState, id: String) -> float:
	var best := 0.0
	for rc in GameData.recipes:
		if not r.recipe_ok(rc):
			continue
		var parts: Array = [rc.a, rc.b] + ([rc.c] if str(rc.get("c", "")) != "" else [])
		if not parts.has(id):
			continue
		var need := parts.duplicate()
		need.erase(id)
		var owned: Array = []
		var ok := true
		for q in need:
			var found = null
			for it in r.items:
				if it.id == q and it.loc != "held" and not owned.has(it):
					found = it
					break
			if found == null:
				ok = false
				break
			owned.append(found)
		if not ok:
			continue
		var before := _pro_rate(r.pack_rates())
		var keep := owned.map(func(o): return [o.loc, o.x, o.y, o.rot])
		for o in owned:
			o.loc = "storage"
		var res := r.make_item(rc.r, "held")
		r.items.append(res)
		var s := _pro_spot(r, res)
		var after := before
		if not s.is_empty():
			_pro_put(res, s)
			after = _pro_rate(r.pack_rates())
		r.items.erase(res)
		for k in owned.size():
			owned[k].loc = keep[k][0]
			owned[k].x = keep[k][1]
			owned[k].y = keep[k][2]
			owned[k].rot = keep[k][3]
		r.calc()
		# a Masterwork also carries the path relic: count it a bit higher than its raw numbers
		best = maxf(best, (after - before) * (1.3 if rc.get("mw", false) else 1.0))
	return best


## True while the bot owns half of a valuable recipe (worth a few extra rerolls to find the other half).
func _pro_hunting(r: RunState) -> bool:
	for it in r.items:
		if it.loc == "held" or it.def().relic:
			continue
		for rc in GameData.recipes:
			if r.recipe_ok(rc) and (rc.a == it.id or rc.b == it.id) and GameData.items[rc.r].tier >= 3:
				return true
	return false


# =============================================================== pro bot: events
# Plays each event the way a strong player would, judging every option with the same no-dice
# fight value it uses for buying (today's monster + the next boss).

## Value of the pack if `it` sat in its best spot (it is put back where it was afterwards).
func _pro_value_with(r: RunState, it: PItem, benches: Array) -> float:
	var keep := [it.loc, it.x, it.y, it.rot]
	if not r.items.has(it):
		r.items.append(it)
	it.loc = "held"
	var s := _pro_spot(r, it)
	var v := -99.0
	if not s.is_empty():
		_pro_put(it, s)
		v = _pro_value(r, benches)
	it.loc = keep[0]
	it.x = keep[1]
	it.y = keep[2]
	it.rot = keep[3]
	r.calc()
	return v


func _pro_event(r: RunState) -> void:
	var ev: Dictionary = r.event
	var benches := _pro_benches(r)
	var v0 := _pro_value(r, benches)
	var note := {"k": ev.k}
	match ev.k:
		"smith":
			# evolve whatever gains the most (pack or storage)
			var best: PItem = null
			var best_v := v0 + 0.02
			if r.gold >= r.smith_cost():
				for it in r.items.duplicate():
					if it.def().evo == "" or it.loc == "held":
						continue
					var old: String = it.id
					it.id = it.def().evo
					var v: float = _pro_value_with(r, it, benches) if it.loc != "grid" or not r.fits(it, it.x, it.y, it.rot, it) else _pro_value(r, benches)
					it.id = old
					r.calc()
					if v > best_v:
						best_v = v
						best = it
			if best != null:
				note["evolve"] = best.id
				r.ev_smith(best)
				# the reforged item may have moved to storage: give it a spot
				if best.loc == "storage":
					best.loc = "held"
					var s := _pro_spot(r, best)
					if s.is_empty():
						best.loc = "storage"
					else:
						_pro_put(best, s)
		"merchant":
			# sell what is only gathering dust, then buy the stock that adds most per gold
			for it in r.storage_items():
				if not it.starter and not it.def().relic and not r.recipe_partner_owned(it.id, true):
					r.ev_sell_full(it)
			for _n in 3:
				var pick := -1
				var pick_s := 0.0
				for i in ev.stock.size():
					var s: Dictionary = ev.stock[i]
					if s.get("sold", false) or s.price > r.gold:
						continue
					var tmp := r.make_item(s.id, "held")
					var v := _pro_value_with(r, tmp, benches)
					r.items.erase(tmp)
					var score := (v - v0) / maxf(1.0, s.price) + (0.05 if r.recipe_partner_owned(s.id) else 0.0)
					if v > v0 + 0.02 and score > pick_s:
						pick_s = score
						pick = i
				if pick < 0:
					break
				r.ev_buy(pick)
				note["bought"] = note.get("bought", []) + [ev.stock[pick].id]
				var got: PItem = r.items[r.items.size() - 1]
				got.loc = "held"
				var sp := _pro_spot(r, got)
				if sp.is_empty():
					got.loc = "storage"
				else:
					_pro_put(got, sp)
				v0 = _pro_value(r, benches)
		"cauldron":
			# two items that do little become one item a rarity higher
			var junk := r.items.filter(func(it): return not it.starter and not it.def().relic and it.loc != "held" and not r.recipe_partner_owned(it.id, true))
			junk.sort_custom(func(a, b): return (_pro_contrib(r, a) if a.loc == "grid" else -1.0) < (_pro_contrib(r, b) if b.loc == "grid" else -1.0))
			if junk.size() >= 2 and junk[0].def().tier <= 2 and junk[1].def().tier <= 2:
				var a: PItem = junk[0]
				var b: PItem = junk[1]
				var a_c := _pro_contrib(r, a) if a.loc == "grid" else 0.0
				var b_c := _pro_contrib(r, b) if b.loc == "grid" else 0.0
				if a_c + b_c < 3.0:
					var id := r.ev_brew(a, b)
					note["brew"] = [a.id, b.id, id]
					if id != "":
						var got2: PItem = r.items[r.items.size() - 1]
						got2.loc = "held"
						var sp2 := _pro_spot(r, got2)
						if sp2.is_empty():
							got2.loc = "storage"
						else:
							_pro_put(got2, sp2)
		"altar":
			# a Legendary for a Heart, only with Hearts full (a boss win refills one) and a real gain
			if r.res >= r.max_hearts():
				var best_i := -1
				var best_v2 := v0 + 0.15
				for i in ev.offer.size():
					var tmp2 := r.make_item(ev.offer[i], "held")
					var v := _pro_value_with(r, tmp2, benches)
					r.items.erase(tmp2)
					if v > best_v2:
						best_v2 = v
						best_i = i
				if best_i >= 0:
					note["legendary"] = ev.offer[best_i]
					r.ev_altar(best_i, "heart")
					var got3: PItem = r.items[r.items.size() - 1]
					got3.loc = "held"
					var sp3 := _pro_spot(r, got3)
					if sp3.is_empty():
						got3.loc = "storage"
					else:
						_pro_put(got3, sp3)
		"roulette":
			# two empty clicks is the sweet spot while healthy; walk away otherwise
			var pulls := 2 if r.hp > r.mhp * 0.6 else (1 if r.hp > r.mhp * 0.4 else 0)
			for _p in pulls:
				if r.ev_pull() != "click":
					break
			note["pulls"] = ev.get("pulls", 0)
		"chest":
			r.ev_chest(randi() % 3)
	if tr_on:
		tr_day["event"] = note
	r.calc()
	r.ev_leave()


## How much an event is worth to this run right now (for the road choice).
func _pro_event_score(r: RunState, k: String) -> float:
	match k:
		"smith":
			if r.gold < r.smith_cost():
				return 0.4
			for it in r.grid_items():
				if it.def().evo != "" and it.def().tier >= 1:
					return 2.4
			return 1.0
		"merchant":
			return 1.8 if r.gold >= 12 else 0.8
		"cauldron":
			var junk := r.items.filter(func(it): return not it.starter and not it.def().relic and it.def().tier <= 2 and not r.recipe_partner_owned(it.id, true))
			return 1.6 if junk.size() >= 2 else 0.5
		"altar":
			return 1.8 if r.res >= r.max_hearts() else 0.0
		"chest":
			return 1.5
		"roulette":
			return 1.3 if r.hp > r.mhp * 0.6 else 0.4
	return 0.8
