extends SceneTree
## Monsters: each floor band draws its own families, every family can field a weapon on its first
## floor, unique Elites carry their name, skills and signature item, and every monster has a sprite.
## Run: godot --headless --path . --script res://tests/monster_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	seed(5)
	var r := RunState.new("warden", "", "normal")
	for band in GameData.foe_bands:
		var start := int(band)
		for fam in GameData.foe_bands[band]:
			_check(GameData.families.has(fam) and GameData.foe_styles.has(fam), "%s has items and a style" % fam)
			_check(GameData.elites.has(fam), "%s has a unique Elite" % fam)
			r.day = start
			var max_t := mini(3, r.rank())
			var hitters: Array = GameData.families[fam].filter(func(id): return GameData.items[id].tier <= max_t and r.m_dps(id) > 0)
			_check(not hitters.is_empty(), "%s can hit on floor %d" % [fam, start])
			_check(Sprites.foe(fam) != null, "%s has a sprite" % fam)
			_check(Sprites.foe(GameData.elites[fam].n) != null, "%s has a sprite" % GameData.elites[fam].n)
	for d in [2, 7, 13]:
		r.day = d
		var band: Array = GameData.foe_names(d)
		for _i in 20:
			var e := r.foe(false)
			_check(band.has(e.fam), "floor %d draws from its band (%s)" % [d, e.fam])
	r.day = 9
	var el := r.foe(true)
	var def: Dictionary = GameData.elites[el.fam]
	_check(el.n == def.n, "an Elite is its family's unique one (%s)" % el.n)
	_check(el.items.any(func(p): return p[0] == def.item), "%s brings its signature item" % el.n)
	for k in str(def.tr).split(","):
		_check(str(el.tr).split(",").has(k), "%s has its skill %s" % [el.n, k])
	_check(GameData.foe_names(20, true).size() == GameData.families.size(), "Endless meets every family")
	print("MONSTER TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
