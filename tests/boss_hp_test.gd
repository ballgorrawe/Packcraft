extends SceneTree
## Bosses outweigh the floors before them: every boss has 20% (Endless: 10%) more HP than a
## normal monster of the floor before, and more than the mini-boss before it. Run: godot --headless --path . --script res://tests/boss_hp_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	for diff in ["normal", "abyss"]:
		var r := RunState.new("warden", "", diff)
		r.endless = true
		var mini_hp := 0.0
		for d in range(1, 41):
			r.day = d
			var b = r.boss_on(d)
			if RunState.MINI_DAYS.has(d):
				seed(d)
				mini_hp = r.foe(true, Vector2(0.7, 0.9)).hp
			if b == null:
				continue
			var bhp: float = r.boss_foe(b).hp
			var most := 0.0
			r.day = d - 1   # the floor you just came from
			for _i in 20:
				most = maxf(most, r.foe_base(false).hp)
			r.day = d
			_check(bhp > most * (1.2 if d <= GameData.days else 1.1), "%s floor %d: boss %d HP > normal monster %d HP" % [diff, d, bhp, most])
			if d <= GameData.days and d > 5:
				_check(bhp > mini_hp, "%s floor %d: boss %d HP > the mini-boss before it %d HP" % [diff, d, bhp, mini_hp])
	print("BOSS HP TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
