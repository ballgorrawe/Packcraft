extends SceneTree
## Signature items: each one, placed next to items of its class, plays a full fight and does its thing
## without errors (more damage, shield or HP left than the same pack without its effect). Also: locked items never show
## up in the shop. Run: godot --headless --path . --script res://tests/sig_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	for id in GameData.items:
		var d: Dictionary = GameData.items[id]
		if d.sig <= 0:
			continue
		var with_it := _fight(id, true)
		var without := _fight(id, false)
		_check(with_it.score > without.score, "%s: it changes the fight (%.0f vs %.0f)" % [id, with_it.score, without.score])
	# locked items stay out of the shop
	var r := RunState.new("rogue", "", "normal")
	for id in GameData.items:
		if GameData.items[id].sig > 0:
			RunState.locked[id] = true
	var seen := false
	for _i in 300:
		r.shop = []
		r.fill_shop()
		for e in r.shop:
			if e.has("id") and RunState.locked.has(e.id):
				seen = true
	_check(not seen, "locked signature items never roll in the shop")
	RunState.locked = {}
	print("SIG TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


## One 20-second fight against a sturdy dummy: the item plus class items around it. Without its
## special the item keeps its stats, so the difference is the mechanic alone.
func _fight(id: String, special: bool) -> Dictionary:
	seed(11)
	var d: Dictionary = GameData.items[id]
	var r := RunState.new(d.cl, "", "normal")
	r.day = 8
	r.hp = 20.0   # hurt, so heals, shields and low-HP effects all show
	for y in GameData.H:
		for x in GameData.W:
			r.tiles[Vector2i(x, y)] = true
	r.items = []
	var it := r.make_item(id, "grid", 3, 3)
	r.items.append(it)
	# the class's own shop items with damage, around it (Spells, Beasts, Sea creatures, Mech...)
	var pool := GameData.items.keys().filter(func(k): return GameData.items[k].cl == d.cl and GameData.items[k].shop and GameData.items[k].sig == 0 and GameData.items[k].pth == "" and GameData.items[k].cd > 0)   # path items left out: the marks were set without them
	pool.sort()
	for k in pool:
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
	GameData.foe_bands = {"1": bands["1"]}   # the floor 1-5 families: the marks below were set against them
	var e := r.foe(false)
	GameData.foe_bands = bands
	e.hp = 5000.0
	var cs := CombatSim.new(r, {"k": "combat", "e": e}, true)
	var guard := 0
	while not cs.done and guard < 200:   # 20 seconds
		cs.step()
		guard += 1
	d.sp = keep
	var dealt := 5000.0 - cs.ehp
	return {"score": dealt + cs.shield + cs.blocked * 0.5 + cs.php}


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1
