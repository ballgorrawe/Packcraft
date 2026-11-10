extends SceneTree
## Checks that path relic specials really change a fight: the same seeded fight with and without the
## relic in the pack must deal different damage.
## Run: godot --headless --path . --script res://tests/path_effect_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	for path in GameData.paths:
		var p: Dictionary = GameData.paths[path]
		var a := _fight(p.cl, path, true)
		var b := _fight(p.cl, path, false)
		var same: bool = is_equal_approx(a.dealt, b.dealt) and is_equal_approx(a.taken, b.taken)
		print("%s %-12s with relic: dealt %.0f taken %.0f | without: dealt %.0f taken %.0f%s" % ["SAME" if same else "ok  ", path, a.dealt, a.taken, b.dealt, b.taken, "   <-- relic did nothing" if same else ""])
		if same:
			fails += 1
	print("PATH EFFECT TEST: %d relics with no effect" % fails)
	quit()


func _fight(cls: String, path: String, with_relic: bool) -> Dictionary:
	seed(7)
	var r := RunState.new(cls, "pup", "normal")
	r.day = 6
	r.path = path
	if with_relic:
		var relic := r.make_item(GameData.paths[path].relic, "storage")
		r.items.append(relic)
		# first free unlocked tile
		for c in r.tiles:
			if r.fits(relic, c.x, c.y):
				relic.loc = "grid"
				relic.x = c.x
				relic.y = c.y
				break
	r.travel()
	var n: Dictionary = {"k": "combat", "e": r.foe(false)}
	var cs := CombatSim.new(r, n)
	cs._rng.seed = 11
	var start_hp: float = cs.ehp
	var hero_hp: float = cs.php
	var guard := 0
	while not cs.done and guard < 600:
		cs.step()
		guard += 1
	return {"dealt": start_hp - cs.ehp, "taken": hero_hp - cs.php}
