extends SceneTree
## Path items (data "pth", 2 per path): each has pixel art, counts as its path's item, and the shop
## leans to them once the path is chosen. Each one with a special changes a fight against a sturdy dummy
## (same pack with and without the special). Run: godot --headless --path . --script res://tests/path_item_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	var per_path := {}
	for id in GameData.items:
		var d: Dictionary = GameData.items[id]
		if d.pth == "":
			continue
		per_path[d.pth] = per_path.get(d.pth, 0) + 1
		_check(Sprites.item(id) != null, "%s has pixel art" % id)
		_check(Mastery.path_items(d.pth).has(id), "%s counts as a %s item" % [id, d.pth])
		_check(d.shop and d.cl == GameData.paths[d.pth].cl, "%s sells in its class's shop" % id)
		if d.sp != "":
			var a := _fight(id, true)
			var b := _fight(id, false)
			_check(a > b, "%s: its special changes the fight (%.0f vs %.0f)" % [id, a, b])
	for p in GameData.paths:
		_check(per_path.get(p, 0) == 2, "%s has 2 path items" % p)
	# the shop leans to the chosen path's items
	var r := RunState.new("ember", "", "normal")
	r.day = 5
	var off := _share(r)
	r.path = "inferno"
	var on := _share(r)
	_check(on > off + 0.1, "the shop leans to the chosen path (%.2f vs %.2f)" % [on, off])
	print("PATH ITEM TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


## Share of shop rolls that are Inferno path items.
func _share(r: RunState) -> float:
	seed(5)
	var n := 0
	for _i in 600:
		if GameData.items[r.roll_item()].pth == "inferno":
			n += 1
	return n / 600.0


## 20 seconds against a 5000 HP dummy with the class's shop items around the item (as in sig_test).
func _fight(id: String, special: bool) -> float:
	seed(11)
	var d: Dictionary = GameData.items[id]
	var r := RunState.new(d.cl, "", "normal")
	r.day = 8
	r.hp = 20.0
	for y in GameData.H:
		for x in GameData.W:
			r.tiles[Vector2i(x, y)] = true
	r.items = [r.make_item(id, "grid", 3, 3)]
	var pool := GameData.items.keys().filter(func(k): return GameData.items[k].cl == d.cl and GameData.items[k].shop and GameData.items[k].sig == 0 and GameData.items[k].cd > 0 and k != id)
	pool.sort()
	for k in pool.slice(0, 10):
		var p := r.make_item(k, "storage")
		r.items.append(p)
		var s := r.nearest_spot(p, Vector2i(3, 3))
		if s.is_empty():
			r.items.erase(p)
			continue
		p.loc = "grid"
		p.x = s.x
		p.y = s.y
		p.rot = s.rot
	var keep: String = d.sp
	if not special:
		d.sp = ""
	var bands: Dictionary = GameData.foe_bands
	GameData.foe_bands = {"1": bands["1"]}
	var e := r.foe(false)
	GameData.foe_bands = bands
	e.hp = 5000.0
	var cs := CombatSim.new(r, {"k": "combat", "e": e}, true)
	if keep == "execute_low":
		cs.ehp = 1200.0   # already below 30%
	var start := cs.ehp
	var guard := 0
	while not cs.done and guard < 200:
		cs.step()
		guard += 1
	d.sp = keep
	return (start - cs.ehp) + cs.shield + cs.blocked * 0.5 + cs.php


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
