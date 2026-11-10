extends SceneTree
## Visual check of the PC hover cards: points at a pack item and at a shop card, saves screenshots.
## Not headless. Run: godot --path . --resolution 1600x900 --script res://tests/shot_hover.gd -- --out=C:/path/hover

var out := "user://hover"


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
	main.run = RunState.new("ember", "pup", "normal")
	main.render()
	await create_timer(1.0).timeout
	var it: PItem = main.run.grid_items()[0]
	Input.warp_mouse(Vector2(500, 450))
	main._set_hover({"kind": "grid", "uid": it.uid})
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out + "_pack.png")
	main._set_hover({"kind": "shop", "idx": 1})
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out + "_shop.png")
	print("saved hover shots, landscape=", main._landscape, " wide=", main._wide)
	quit()
