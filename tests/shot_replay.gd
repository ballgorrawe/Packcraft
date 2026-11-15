extends SceneTree
## The night screen's replay button and the fight's speed row (0.5× to 4×).
## Run: godot --path . --resolution 720x1280 --script res://tests/shot_replay.gd -- --out=C:/path/rp

var out := "user://rp"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run()


func _run() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	var r := RunState.new("ember", "", "normal")
	r.day = 2
	r.travel()
	main.run = r
	main._choose(0)
	await create_timer(1.5).timeout
	root.get_texture().get_image().save_png(out + "_fight.png")
	var cv = main.find_children("*", "CombatView", true, false)
	if not cv.is_empty():
		cv[0]._skip()
	await create_timer(3.0).timeout
	root.get_texture().get_image().save_png(out + "_night.png")
	main._replay_sim = r.replay_sim()
	main.render()
	await create_timer(1.5).timeout
	root.get_texture().get_image().save_png(out + "_replay.png")
	print("phase=", r.phase, " replay=", main._replay_sim != null)
	quit()
