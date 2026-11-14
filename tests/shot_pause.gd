extends SceneTree
## Pause menu check: ⏸️ in the top bar opens it, Main menu keeps the save, Give up clears it.
## Run: godot --path . --resolution 720x1280 --script res://tests/shot_pause.gd -- --out=C:/path/pause

var out := "user://pause"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run()


func _run() -> void:
	I18n.set_lang("th")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	var r := RunState.new("rogue", "pup", "normal")
	r.day = 4
	r.shop = []
	r.fill_shop()
	main.run = r
	main.render()
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "_bar.png")
	main.show_pause = true
	main.render()
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "_menu.png")
	main._pause_quit = true
	main.render()
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "_quit.png")
	main._leave_run()
	var ok: bool = main.run == null and main.title_step == 0 and not main.show_pause
	# over a popup (the road) the button floats
	var r2 := RunState.new("ember", "", "normal")
	r2.phase = "afternoon"
	r2.nodes = [{"k": "combat", "e": r2.foe(false)}]
	main.run = r2
	main.render()
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "_road.png")
	print("PASS pause" if ok else "FAIL pause")
	quit()
