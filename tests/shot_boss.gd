extends SceneTree
## Visual check of boss fights: one screenshot per boss, a few seconds into the fight.
## Not headless. Run: godot --path . --resolution 1600x900 --script res://tests/shot_boss.gd -- --out=C:/path/boss

var out := "user://boss"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run()


func _run() -> void:
	I18n.set_lang("en")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	for b in GameData.bosses:
		var r := RunState.new("venom", "pup", "normal")
		r.day = b.d
		r.boss_pick[b.d] = b.n
		r.phase = "afternoon"
		r.nodes = [{"k": "boss", "e": r.boss_foe(r.boss_on(b.d))}]
		main.run = r
		main._choose(0)
		await create_timer(4.5).timeout
		var f: String = "%s_%s.png" % [out, String(b.n).replace(" ", "_")]
		root.get_texture().get_image().save_png(f)
		print("saved ", f)
		main._pending_sim = null
	quit()
