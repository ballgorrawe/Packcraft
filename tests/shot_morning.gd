extends SceneTree
## Visual check of the morning shop (item shapes on the cards), the road card of a styled monster,
## and a fight against it a few seconds in. Not headless (needs rendering).
## Run: godot --path . --resolution 720x1280 --script res://tests/shot_morning.gd -- --out=C:/path/morning [--fam=Slime]

var out := "user://morning"
var fam := "Slime"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--fam="):
			fam = a.substr(6)
	_run()


func _run() -> void:
	I18n.set_lang("en")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	seed(5)
	var r := RunState.new("rogue", "pup", "normal")
	r.day = 8
	r.gold = 30
	r.path = "crimson"
	r.shop = []
	r.fill_shop()
	main.run = r
	main.render()
	await create_timer(1.2).timeout
	root.get_texture().get_image().save_png(out + "_shop.png")
	print("saved ", out, "_shop.png")
	# a styled monster on the road, then the fight
	r.phase = "afternoon"
	var e := r.foe(false)
	while e.fam != fam:
		e = r.foe(false)
	r.nodes = [{"k": "combat", "e": e}]
	main.render()
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png(out + "_road.png")
	print("saved ", out, "_road.png")
	main._choose(0)
	await create_timer(7.0).timeout
	root.get_texture().get_image().save_png(out + "_fight.png")
	print("saved ", out, "_fight.png")
	var cv = main.find_children("*", "CombatView", true, false)
	if not cv.is_empty():
		cv[0]._show_ult_info(true)
		await create_timer(0.6).timeout
		root.get_texture().get_image().save_png(out + "_ult.png")
		print("saved ", out, "_ult.png")
	quit()
