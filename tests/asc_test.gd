extends SceneTree
## Ascension: level 0 changes nothing, level 10 turns every rule on, and a saved run keeps its level.
## Run: godot --headless --path . --script res://tests/asc_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	seed(7)
	var a := RunState.new("warden", "", "normal", 0)
	seed(7)
	var b := RunState.new("warden", "", "normal", GameData.ascension.size())
	_check(a.av("foe_hp") == 0.0, "level 0: no rule on")
	_check(b.max_hearts() == a.max_hearts() - 1 and b.res == b.max_hearts(), "one Heart less, and the run starts with it")
	_check(absf(b.mhp - a.mhp * 0.9) < 0.6, "Max HP -10%% (%.1f vs %.1f)" % [b.mhp, a.mhp])
	_check(b.reroll_cost() == a.reroll_cost() + 1, "reroll +1 gold")
	var price := func(r: RunState) -> float:
		var s := 0.0
		for e in r.shop:
			if not e.has("bag"):
				s += float(e.price) / GameData.items[e.id].cost
		return s
	_check(price.call(b) > price.call(a), "shop prices higher")
	b.day = 6
	a.day = 6
	seed(1)
	var fa := a.foe_base(false)
	seed(1)
	var fb := b.foe_base(false)
	_check(fb.hp > fa.hp and fb.dps > fa.dps, "monsters tougher (%d vs %d HP)" % [fb.hp, fa.hp])
	var back := RunState.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	_check(back != null and back.asc == b.asc, "a saved run keeps its level")
	# Endless gives +2 Hearts, but never past the (Ascension-lowered) cap
	var e := RunState.new("warden", "", "normal", GameData.ascension.size())
	e.res = e.max_hearts()
	e.result = {"victory": true}
	e.go_endless()
	_check(e.res <= e.max_hearts(), "Endless Hearts stay within the cap (%d of %d)" % [e.res, e.max_hearts()])
	print("ASC TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1
