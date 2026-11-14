extends SceneTree
## Pixel art (not emoji) in the recipe book, fusion card, reward tile, event item card and hero start bag.
## Run: godot --path . --resolution 720x1280 --script res://tests/shot_art_icons.gd -- --out=C:/path/icons

var out := "user://icons"


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
	r.shop = []
	r.fill_shop()
	main.run = r
	main.show_book = true
	main.book_page = 3
	main.render()
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "_book.png")
	main.show_book = false
	main.render()
	var rc: Dictionary = GameData.recipes[0]
	var box := VBoxContainer.new()
	box.position = Vector2(40, 200)
	box.custom_minimum_size = Vector2(640, 0)
	box.z_index = 100
	main.add_child(box)
	box.add_child(main._fusion_card({"a": rc.a, "b": rc.b, "r": rc.r, "evo": false}, 0.0))
	var row := HBoxContainer.new()
	row.add_child(main._reward_tile({"k": "loot", "id": rc.r}, 0.0))
	row.add_child(main._item_pick_card(r.items[0], "", false, func(): pass))
	box.add_child(row)
	await create_timer(2.5).timeout
	root.get_texture().get_image().save_png(out + "_fx.png")
	box.queue_free()
	main.run = null
	main._splash = false
	main.title_step = 1
	main.render()
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png(out + "_hero.png")
	print("shots done")
	quit()
