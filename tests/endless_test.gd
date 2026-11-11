extends SceneTree
## Endless mode: after the day-15 boss you can keep going. +2 Hearts (max 5), a boss every 5 days that
## gets stronger, Endless bosses give a Heart back only some of the time, and it survives save/load.
## Run: godot --headless --path . --script res://tests/endless_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	seed(9)
	var r := RunState.new("warden", "pup", "normal")
	r.day = GameData.days
	r.res = 2
	r.result = {"n": {"k": "boss"}, "win": true, "lines": [], "over": false, "victory": true, "rew": [], "fused": []}
	_check(r.max_hearts() == 3, "3 Hearts max before Endless")
	r.go_endless()
	_check(r.endless and r.res == 4 and r.max_hearts() == 5, "Endless: +2 Hearts, max 5 (have %d)" % r.res)
	r.next_day()
	_check(r.end_state == "" and r.day == GameData.days + 1, "the run goes on to day %d (state '%s')" % [r.day, r.end_state])
	# bosses every 5 days, none in between, growing
	_check(r.boss_on(16) == null and r.boss_on(19) == null, "no boss on days 16-19")
	var b15 = r.boss_on(GameData.days)
	var b20 = r.boss_on(20)
	var b25 = r.boss_on(25)
	_check(b20 != null and b25 != null, "bosses on day 20 and 25")
	if b20 != null and b25 != null:
		_check(b20.hp > b15.hp and b25.hp > b20.hp, "Endless bosses get tougher (%d -> %d -> %d HP)" % [b15.hp, b20.hp, b25.hp])
		_check(b20.n != b25.n, "a different boss each round (%s, %s)" % [b20.n, b25.n])
		var e := r.boss_foe(b20)
		_check(e.has("items") and e.items.size() > 0 and e.get("mech", {}).size() > 0, "Endless boss has a pack and its move")
	# normal monsters keep scaling past day 15
	r.day = 15
	var hp15: float = r.foe_base(false).hp
	r.day = 25
	var hp25: float = r.foe_base(false).hp
	_check(hp25 > hp15 * 1.3, "monsters keep getting tougher (%d -> %d HP)" % [hp15, hp25])
	# Endless bosses give a Heart back only some of the time
	var gave := 0
	for k in 40:
		var rr := RunState.new("warden", "pup", "normal")
		rr.endless = true
		rr.day = 20
		rr.res = 2
		var n := {"k": "boss", "e": rr.boss_foe(rr.boss_on(20))}
		rr.go_night(n, true, null)
		if rr.res > 2:
			gave += 1
	_check(gave > 5 and gave < 35, "Endless boss heart drop is a chance (%d/40)" % gave)
	# save / load keeps it
	r.day = 22
	var d := r.to_dict()
	var r2 := RunState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_check(r2 != null and r2.endless and r2.max_hearts() == 5 and r2.day == 22, "save/load keeps Endless")
	print("ENDLESS TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1
