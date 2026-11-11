extends SceneTree
## Charge-loop guard: rebuilds a real player's Abyss Tinker pack (two Perpetual Cores, Storm Cannon,
## Volt Rifles, Tesla Core, Doom Turret, batteries...) against an Abyss Stone Titan. Before the guard
## every item fired every tick and the Ultimate went off 8 times in 1.3s. Now no item may fire much
## faster than its own cooldown allows, and the Ultimate at most once per 3s.
## Run: godot --headless --path . --script res://tests/loop_guard_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	seed(4)
	var r := RunState.new("tinker", "bee", "abyss")
	r.day = 15
	r.path = "overclock"
	# a big pack, like the screenshot
	for _u in 80:
		r.expand += 1
		r.unlock(Vector2i(randi() % GameData.W, randi() % GameData.H))
	var ids := ["perpetual_core", "perpetual_core", "storm_cannon", "volt_rifle", "volt_rifle", "tesla_core", "doom_turret",
		"capacitor", "battery", "battery", "overclock_chip", "gear_box", "oil_can", "flux_coil"]
	var placed := 0
	for id in ids:
		var it := r.make_item(id, "held")
		r.items.append(it)
		var ok := false
		for rot in 4:
			for y in GameData.H:
				for x in GameData.W:
					if not ok and r.fits(it, x, y, rot):
						it.loc = "grid"
						it.x = x
						it.y = y
						it.rot = rot
						ok = true
		if ok:
			placed += 1
		else:
			it.loc = "storage"
	r.calc()
	var e := r.boss_foe(r.boss_on(15))
	var cs := CombatSim.new(r, {"k": "boss", "e": e})
	var guard := 0
	while not cs.done and guard < 4000:
		cs.step()
		guard += 1
	var secs := cs.tk / 10.0
	print("placed %d items, fight %.1fs, won=%s, ultimates %d" % [placed, secs, cs.won, cs.ults])
	_check(cs.ults <= int(secs / 3.0) + 1, "Ultimate at most once per 3s (%d in %.1fs)" % [cs.ults, secs])
	for x in cs.items:
		if x.d.once or x.d.cd <= 0:
			continue
		# own speed (haste counted) can make it ~2.5x faster than its listed cooldown; charge cannot add more
		var allowed := secs / maxf(0.3, x.d.cd * 0.4) + 2.0
		if x.st.hits > allowed:
			_check(false, "%s fired %d times in %.1fs (allowed %d)" % [x.d.n, x.st.hits, secs, int(allowed)])
	_check(not cs.won or secs >= 4.0, "a 1000+ HP Abyss boss is not deleted in a blink (%.1fs, dealt %d)" % [secs, roundi(cs.e.hp - maxf(0.0, cs.ehp))])
	print("LOOP GUARD TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1
