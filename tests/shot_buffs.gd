extends SceneTree
## Visual check of "In your pack now": Twin Daggers (20% crit) touching a Lucky Clover (+10% crit), a
## Whetstone and an item whose buff does nothing on daggers. Phone: the inspector card; PC: the hover card.
## Run: godot --path . --resolution 720x1280 --script res://tests/shot_buffs.gd -- --out=C:/path/buffs

var out := "user://buffs"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run()


func _place(r: RunState, id: String, x: int, y: int) -> PItem:
	var it := r.make_item(id, "grid", x, y)
	r.items.append(it)
	return it


func _run() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	I18n.set_lang("th")
	var r := RunState.new("rogue", "cat", "normal")
	r.day = 6
	for _u in 30:
		r.expand += 1
		r.unlock(Vector2i(randi() % GameData.W, randi() % GameData.H))
	r.items = r.items.filter(func(i): return false)
	var dag := _place(r, "twin_daggers", 3, 3)
	_place(r, "lucky_clover", 5, 3)
	_place(r, "whetstone", 3, 2)
	# a Fire Gem: its "Fire damage" buff only works on the Inferno path, so it shows as no effect
	_place(r, "fire_gem", 4, 4)
	r.path = "crimson"
	dag.pd = 2.4
	dag.gc = 4
	r.calc()
	main.run = r
	main.selected = dag
	main.render()
	if main._wide:
		# PC shows the same read-out in the hover card
		var card: Control = main._item_info_card({"id": dag.id, "rot": dag.rot, "item": dag, "shop": {}})
		card.position = Vector2(900, 120)
		main.screen.add_child(card)
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png(out + ".png")
	print("saved ", out, ".png  crit now ", r.eff(dag).crit)
	quit()
