extends SceneTree
## Visual check of the night screen with a level-up: wins a fight, gets enough EXP for level 5,
## and saves a screenshot of the reward tiles and the pick card. Not headless (needs rendering).
## Run: godot --path . --resolution 720x1280 --script res://tests/shot_night.gd -- --out=C:/path/night

var out := "user://night"


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
	var r := RunState.new("warden", "pup", "normal")
	main.run = r
	r.lv = 4
	r.xp = 2
	r.travel()
	var cs := r.choose(0)
	cs.skip_to_end()
	cs.won = true
	cs.php = maxf(cs.php, 10)
	r.go_night(r.nodes[0], true, cs)
	# a full row like a real boss-day win: gold, heart, pack tiles, EXP, level
	r.result.rew.push_front({"k": "tiles", "v": 4})
	r.result.rew.push_front({"k": "heart", "v": 1})
	main.render()
	await create_timer(2.5).timeout
	root.get_texture().get_image().save_png(out + "_0.png")
	print("saved ", out, "_0.png  lv=", r.lv, " picks=", r.picks)
	r.pick_level(0)
	main.render()
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png(out + "_1.png")
	print("saved ", out, "_1.png  lv=", r.lv, " bonus=", r.lvl_bonus, " mhp=", r.mhp)
	quit()
