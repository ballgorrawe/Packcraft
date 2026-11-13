extends SceneTree
## Class mastery: XP to levels, the tree's limits and reset, its perks in a run (shop lean, head start,
## free reroll), cosmetics by level, and a saved run keeping its mastery. Restores the settings it touches.
## Run: godot --headless --path . --script res://tests/mastery_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	var cls := "ember"
	var keep := {}
	for k in ["mst_" + cls, "mst_tree_" + cls, "cos_" + cls]:
		keep[k] = SaveGame.get_setting(k, null)
	SaveGame.set_setting("mst_" + cls, 0)
	SaveGame.set_setting("mst_tree_" + cls, {})
	SaveGame.set_setting("cos_" + cls, {})
	# levels
	_check(Mastery.level(cls) == 0, "starts at level 0")
	var total := 0
	for n in range(1, Mastery.max_level() + 1):
		total += Mastery.level_cost(n)
	_check(total >= 2500 and total <= 3200, "about 17 runs to max (%d XP)" % total)
	var up := Mastery.award(cls, Mastery.level_cost(1) + Mastery.level_cost(2) + Mastery.level_cost(3))
	_check(up.from == 0 and up.to == 3 and Mastery.points_left(cls) == 3, "XP for 3 levels gives 3 points")
	# a run's XP: floors, bosses, win
	var r := RunState.new(cls, "", "normal")
	r.day = 10
	r.boss_wins = 1
	_check(Mastery.gain(r) == 125, "floor 10 + one boss = 125 XP (got %d)" % Mastery.gain(r))
	# tree
	var p: String = GameData.classes[cls].paths[0]
	_check(Mastery.add_point(cls, "fav_" + p) and Mastery.add_point(cls, "fav_" + p) and Mastery.add_point(cls, "head_" + p), "spend 3 points")
	_check(not Mastery.add_point(cls, "free_rr"), "no point left")
	var pk := Mastery.perks(cls)
	_check(int(pk.bias.get(p, 0)) == 2 and pk.head.has(p), "perks: favoured x2 and head start")
	Mastery.reset(cls)
	_check(Mastery.points_left(cls) == 3 and Mastery.perks(cls).bias.is_empty(), "reset gives the points back")
	# perks in a run
	var items := Mastery.path_items(p)
	_check(not items.is_empty(), "%s has path items" % p)
	seed(11)
	var plain := _share(RunState.new(cls, "", "normal"), items)
	seed(11)
	var leaned_run := RunState.new(cls, "", "normal")
	leaned_run.apply_mastery({"bias": {p: 3}, "head": [p], "free_rr": 1}, {})
	_check(leaned_run.storage_items().any(func(i): return items.has(i.id)), "head start puts a path item in storage")
	_check(leaned_run.reroll_cost() == 0, "the first reroll is free")
	var leaned := _share(leaned_run, items)
	_check(leaned > plain + 0.1, "favoured x3 leans the shop (%.2f -> %.2f)" % [plain, leaned])
	# cosmetics follow the level
	var lk := Mastery.look(cls)
	_check(lk.title == 0 and lk.theme == 1 and lk.skin == 0, "level 3 wears its newest unlocks")
	_check(not Mastery.choices("frame", 3).has(1), "the bronze frame waits for level 5")
	Mastery.equip(cls, "skin", -1)
	_check(Mastery.look(cls).skin == -1, "the plain hero can be picked again")
	# save keeps it
	var back := RunState.from_dict(JSON.parse_string(JSON.stringify(leaned_run.to_dict())))
	_check(back != null and int(back.mst.bias[p]) == 3 and back.reroll_cost() == 0, "a saved run keeps its mastery")
	for k in keep:
		SaveGame.set_setting(k, keep[k] if keep[k] != null else ({} if k != "mst_" + cls else 0))
	print("MASTERY TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


## Share of shop rolls that are the path's items, over many rolls in the class's mid game.
func _share(r: RunState, items: Array) -> float:
	r.day = 6
	var hit := 0
	for i in 600:
		if items.has(r.roll_item()):
			hit += 1
	return hit / 600.0


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
