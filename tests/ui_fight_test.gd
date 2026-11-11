extends SceneTree
## Plays the first fight of a fresh run through the real game screen (main.gd + CombatView), the way a
## player does: start a run, depart with the starting items, pick the first monster, let the fight play.
## Prints who won and the HP left, for every class and mode.
## Run (not headless): godot --path . --resolution 720x1280 --script res://tests/ui_fight_test.gd

var main: Control


func _initialize() -> void:
	_run()


func _fight(cls: String, diff: String) -> String:
	seed(hash(cls + diff))
	var r := RunState.new(cls, "cat", diff)
	main.run = r
	main._pending_sim = null
	main.render()
	await process_frame
	var hp0 := r.hp
	var foe_hp: float = r.nodes[0].e.hp
	r.travel()
	main.render()
	await process_frame
	main._choose(0)
	var t0 := Time.get_ticks_msec()
	while r.phase != "night" and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
	var res: Dictionary = r.result
	return "%-10s %-6s foe HP %4d  ->  %s  hero HP %d -> %d  (%.1fs)" % [cls, diff, foe_hp, "WIN " if res.get("win", false) else "LOSS", hp0, r.hp, (Time.get_ticks_msec() - t0) / 1000.0]


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	SaveGame.set_setting("speed", 4.0)
	for diff in ["normal", "abyss"]:
		for cls in ["rogue", "warden", "tinker", "beast"]:
			print(await _fight(cls, diff))
	quit()
