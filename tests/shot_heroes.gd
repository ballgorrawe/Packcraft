extends SceneTree
## Visual check of the hero select card for every class. Not headless.
## Run: godot --path . --resolution 1600x900 --script res://tests/shot_heroes.gd -- --out=C:/path/hero

var out := "user://hero"


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
	for c in GameData.class_keys:
		main.sel_cls = c
		main.title_step = 1
		main.render()
		await create_timer(0.8).timeout
		var f: String = "%s_%s.png" % [out, c]
		root.get_texture().get_image().save_png(f)
		print("saved ", f)
	quit()
