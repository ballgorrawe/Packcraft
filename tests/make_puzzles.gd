extends SceneTree
## Makes data/puzzles.json: chapter 1 = hand-made lessons, chapter 2 = packs the bot really won a boss
## fight with. Each puzzle's foe is tuned so a good layout wins with stars to spare while a careless
## one (items dropped in order) loses; a puzzle that can't be tuned that way is left out.
## Run: godot --headless --path . --script res://tests/make_puzzles.gd -- --boards=<dir with f_*/pro_*.out>

const LESSONS := [
	{"id": "l01", "n": "Touching items help", "d": "Whetstones sharpen the weapons they touch. Put each one between blades.", "cls": "rogue", "w": 4, "h": 3, "items": ["rogue_dagger", "rogue_dagger", "bloodied_shiv", "whetstone", "whetstone", "whetstone"], "foe": {"fam": "Goblin", "day": 5}},
	{"id": "l02", "n": "Not everything goes in", "d": "There is more than the pack can hold. Leave out what does not help this fight.", "cls": "inquisitor", "w": 3, "h": 2, "items": ["coin_purse", "leather_vest", "oath_blade", "rune_sword", "whetstone", "spark_rune"], "foe": {"fam": "Bandit", "day": 6}},
	{"id": "l03", "n": "Shields and thorns", "d": "A fast monster hits often: Shield soaks the hits and Thorns punish each one.", "cls": "warden", "w": 4, "h": 3, "items": ["bark_skin", "bark_skin", "granite_shield", "stone_fist", "thorn_whip"], "foe": {"fam": "Bandit", "day": 7, "tr": "swift"}},
	{"id": "l04", "n": "Stack the Burn", "d": "A Fire Gem turns the weapons it touches into Fire. Burn keeps hurting a monster that heals.", "cls": "ember", "w": 4, "h": 3, "items": ["fire_gem", "kindling_blade", "kindling_blade", "fire_whip", "iron_sword"], "foe": {"fam": "Slime", "day": 7, "tr": "regen"}},
	{"id": "l05", "n": "It shrugs off Fire", "d": "This monster resists Fire. Pick the weapons that hit it for full damage.", "cls": "ember", "w": 3, "h": 2, "items": ["ember_sword", "fire_whip", "iron_sword", "serrated_cleaver", "whetstone"], "foe": {"fam": "Skeleton", "day": 6, "imm": "Fire"}},
	{"id": "l06", "n": "Break the armor", "d": "Armored monsters take less Physical damage. An Armor Breaker lets the weapons it touches pierce it.", "cls": "warden", "w": 4, "h": 3, "items": ["armor_breaker", "stone_fist", "stone_fist", "rock_club", "pebble_sling"], "foe": {"fam": "Skeleton", "day": 7, "tr": "armored"}},
	{"id": "l07", "n": "Charge them up", "d": "A Battery charges the items it touches. Put it where it reaches the most weapons.", "cls": "tinker", "w": 4, "h": 3, "items": ["battery", "spark_pistol", "spark_pistol", "scrap_golem", "static_coil"], "foe": {"fam": "Cave Rat", "day": 7}},
	{"id": "l08", "n": "Spell support", "d": "The Mana Prism makes the Spells it touches faster and stronger.", "cls": "weaver", "w": 4, "h": 3, "items": ["mana_prism", "arcane_bolt", "arcane_bolt", "shooting_star", "apprentice_wand"], "foe": {"fam": "Goblin", "day": 7}},
	{"id": "l09", "n": "Lead the pack", "d": "A Spirit Totem makes the Beasts it touches hit harder. Two totems, three beasts: make every beast touch both.", "cls": "beast", "w": 4, "h": 3, "items": ["spirit_totem", "spirit_totem", "wolf_pup", "fox_kit", "stray_kitten"], "foe": {"fam": "Bandit", "day": 7}},
	{"id": "l10", "n": "A signature item", "d": "The Twin-Fang Ring strikes again when a Weapon touching it crits. Surround it with crit weapons.", "cls": "rogue", "w": 4, "h": 3, "items": ["fang_ring", "shadow_dagger", "executioners_blade", "lucky_clover", "bloodied_shiv"], "foe": {"fam": "Goblin", "day": 8}},
]

const MIN_GAP := 0.1   # the good layout keeps at least this much more HP than the careless one

var out := []
var boards_dir := ""


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boards="):
			boards_dir = a.substr(9)
	for spec in LESSONS:
		var tiles := []
		for y in spec.h:
			for x in spec.w:
				tiles.append([3 + x, 2 + y])
		var p := {"id": spec.id, "ch": 1, "n": spec.n, "d": spec.d, "cls": spec.cls, "day": spec.foe.day, "tiles": tiles, "items": spec.items}
		_tune(p, _lesson_foe(spec))
	_challenges()
	var f := FileAccess.open("res://data/puzzles.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"_doc": "Made by tests/make_puzzles.gd. Each foe is tuned so `best` wins with stars and a careless layout loses.", "puzzles": out}, " "))
	f.close()
	print("PUZZLES MADE: %d (lessons %d)" % [out.size(), out.filter(func(q): return q.ch == 1).size()])
	quit()


func _lesson_foe(spec: Dictionary) -> Dictionary:
	seed(7)
	var r := RunState.new(spec.cls, "", "normal")
	r.day = spec.foe.day
	var e := r.foe_base(false)
	e.fam = spec.foe.fam
	e.n = spec.foe.fam
	e.tier = "normal"
	e.tr = spec.foe.get("tr", "")
	e.imm = spec.foe.get("imm", "")
	e.merge(r.build_pack(e.fam, false), true)
	return e


## Chapter 2: winning packs from the last bot batch, against the boss they beat (floor 10).
func _challenges() -> void:
	if boards_dir == "":
		return
	var picked := {}
	for mode in ["f_normal", "f_hard"]:
		var d := DirAccess.open(boards_dir + "/" + mode)
		if d == null:
			continue
		for fn in d.get_files():
			if not fn.ends_with(".out"):
				continue
			for line in FileAccess.get_file_as_string(boards_dir + "/" + mode + "/" + fn).split("\n"):
				var x := line.split("|")
				if x.size() < 23 or x[6] != "1":
					continue
				var cls := x[3]
				if picked.get(cls, 0) >= 2:
					continue
				var bosses := x[21].split(",")
				for snap in x[22].split("~"):
					var parts := snap.split("#")
					if parts.size() < 3 or parts[0] != "10" or bosses.size() < 2:
						continue
					var boss_name := bosses[1].split(":")[0]
					var p := _board_puzzle(cls, parts[1], parts[2], boss_name, "c_%s_%d" % [cls, picked.get(cls, 0) + 1])
					if p.is_empty():
						continue
					var before := out.size()
					var r := RunState.new(cls, "", "normal")
					r.day = 10
					r.boss_pick[10] = boss_name
					_tune(p, r.boss_foe(r.boss_on(10)))
					if out.size() > before:
						picked[cls] = picked.get(cls, 0) + 1


func _board_puzzle(cls: String, tiles_s: String, items_s: String, boss_name: String, id: String) -> Dictionary:
	var tiles := Array(tiles_s.split(";")).map(func(t): return [int(t.split(".")[0]), int(t.split(".")[1])])
	var items := Array(items_s.split(";")).map(func(t): return t.split(":")[0])
	if items.size() < 5 or items.size() > 20:
		return {}
	return {"id": id, "ch": 2, "n": "%s vs %s" % [GameData.classes[cls].n, boss_name], "d": "The bot beat this boss with these items. Can you?", "cls": cls, "day": 10, "tiles": tiles, "items": items}


## Tunes the foe where a good layout stands out most from a careless one (the most HP left between
## them, the good one winning), and sets the puzzle's own star marks from those two: the careless
## layout earns 1 star, the good one 3. A puzzle where layout barely matters is left out.
func _tune(p: Dictionary, base: Dictionary) -> void:
	var best := _best_layout(p, base)
	if best.is_empty():
		print("skip %s: no layout fits" % p.id)
		return
	var pick := {}
	var k := 0.1
	while k <= 2.0:
		var b := _fight(p, base, k, best)
		var c := _fight(p, base, k, [])
		var c_left: float = maxf(0.0, c.left) if c.win else 0.0
		# a lesson keeps a comfortable win (40% HP or more); a challenge may be tight
		var easy_enough: bool = p.ch != 1 or b.left >= 0.4
		if b.win and easy_enough and b.left - c_left > float(pick.get("gap", 0.0)):
			pick = {"k": k, "gap": b.left - c_left, "b": b.left, "c": c_left, "c_win": c.win}
		k += 0.05
	if pick.is_empty() or pick.gap < MIN_GAP:
		print("skip %s: layout changes little (%d%% HP)" % [p.id, roundi(float(pick.get("gap", 0.0)) * 100)])
		return
	p.foe = _scaled(base, pick.k)
	p.best = best
	# 2 stars a third of the way from careless to good, 3 stars just short of good
	p.stars = [snappedf(maxf(0.02, pick.c + pick.gap * 0.35), 0.01), snappedf(maxf(0.05, pick.c + pick.gap * 0.85), 0.01)]
	out.append(p)
	print("ok   %s (%s): foe x%.2f, good keeps %d%% HP, careless %s, stars at %s" % [p.id, p.n, pick.k, roundi(pick.b * 100), ("keeps %d%%" % roundi(pick.c * 100)) if pick.c_win else "loses", str(p.stars)])


func _scaled(base: Dictionary, k: float) -> Dictionary:
	var e := base.duplicate(true)
	e.hp = float(roundi(float(base.hp) * k))
	e.dps = float(base.dps) * k
	var r := RunState.new("warden", "", "normal")
	r._tune_pack(e)
	if str(e.get("tier", "")) == "boss":
		e.sup_mult = 1.0
	return e


## Fights one layout: [] = the careless one (items dropped in order into the first spot that fits).
func _fight(p: Dictionary, base: Dictionary, k: float, layout: Array) -> Dictionary:
	var r := RunState.new(p.cls, "", "normal")
	var q := p.duplicate(true)
	q.foe = _scaled(base, k)
	r.start_puzzle(q)
	if layout.is_empty():
		_careless(r)
	else:
		_apply(r, layout)
	r.travel()
	var cs := r.choose(0)
	var guard := 0
	while not cs.done and guard < 900:
		cs.step()
		guard += 1
	return {"win": cs.won, "left": cs.php / maxf(1.0, cs.mhp)}


## A careless player: every item, in the order given, dropped on a random spot that fits (the same
## spots every time for a puzzle).
func _careless(r: RunState) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(r.puzzle.get("id", "")))
	for it in r.items:
		var spots := []
		for rot in 4:
			for y in GameData.H:
				for x in GameData.W:
					if r.fits(it, x, y, rot):
						spots.append([x, y, rot])
		if spots.is_empty():
			continue
		var s: Array = spots[rng.randi() % spots.size()]
		it.loc = "grid"
		it.x = s[0]
		it.y = s[1]
		it.rot = s[2]


func _apply(r: RunState, layout: Array) -> void:
	var left := r.items.duplicate()
	for e in layout:
		for it in left:
			if it.id == e[0]:
				it.loc = "grid"
				it.x = int(e[1])
				it.y = int(e[2])
				it.rot = int(e[3])
				left.erase(it)
				break


## The best layout the arranger finds, starting from the careless one.
func _best_layout(p: Dictionary, base: Dictionary) -> Array:
	var r := RunState.new(p.cls, "", "normal")
	var q := p.duplicate(true)
	q.foe = base
	r.start_puzzle(q)
	_careless(r)
	var plan := r.plan_arrange()
	if not plan.is_empty():
		r.apply_arrange(plan.moves)
	return r.grid_items().map(func(i): return [i.id, i.x, i.y, i.rot])
