extends SceneTree
## Masterwork goal: the 👑 chip and panel, the path choice with each path's Ultimate, 👑 parts in the shop.
## Run: godot --path . --resolution 720x1280 --script res://tests/shot_goal.gd -- --out=C:/path/goal

var out := "user://goal"


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
	seed(3)
	var r := RunState.new("rogue", "", "normal")
	r.day = GameData.path_day
	main.run = r
	main.render()
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png(out + "_path.png")
	r.choose_path("crimson")
	r.items.append(r.make_item("twin_daggers", "storage"))
	r.shop = []
	r.fill_shop()
	main.render()
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "_shop.png")
	main.show_goal = true
	main.render()
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "_panel.png")
	var g: Dictionary = r.mw_goal()
	print("goal steps=", g.steps.size(), " need=", g.need, " shop=", r.shop.map(func(e): return e.get("id", "bag")))
	quit()
