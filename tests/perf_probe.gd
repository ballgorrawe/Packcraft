extends SceneTree
## Where does the frame time go? Measures (vsync off) frames per second on the busy screens, with and
## without the animated background, how long a full screen rebuild takes, and what the pack recomputes.
## Not headless (needs rendering). Run:
##   godot --path . --resolution 720x1280 --script res://tests/perf_probe.gd

var main: Control


func _initialize() -> void:
	_run()


func _fps(secs: float) -> float:
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_frames_drawn()
	while Time.get_ticks_usec() - t0 < int(secs * 1e6):
		await process_frame
	return float(Engine.get_frames_drawn() - f0) / ((Time.get_ticks_usec() - t0) / 1e6)


func _ms(c: Callable, n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		c.call()
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	var lang := "th"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			lang = a.substr(7)
	I18n.set_lang(lang)
	# a run with a well-filled pack
	seed(3)
	var r := RunState.new("inquisitor", "bee", "hard")
	r.day = 9
	r.gold = 40
	for _u in 40:
		r.expand += 1
		r.unlock(Vector2i(randi() % GameData.W, randi() % GameData.H))
	var ids := ["blessed_blade", "storm_rune", "mana_crystal", "iron_sword", "wooden_shield", "health_potion", "spark_rune", "rune_sword", "greatsword", "holy_shield", "blood_rune", "prayer_beads"]
	for id in ids:
		var it := r.make_item(id, "storage")
		r.items.append(it)
		for y in GameData.H:
			for x in GameData.W:
				if it.loc == "storage" and r.fits(it, x, y):
					it.loc = "grid"
					it.x = x
					it.y = y
	print("pack items: %d" % r.grid_items().size())
	main.run = r
	main.render()
	await _fps(1.0)
	print("morning: %.0f fps" % await _fps(3.0))
	main._bg.visible = false
	print("morning, no background: %.0f fps" % await _fps(3.0))
	main._bg.visible = true
	print("full screen rebuild (render): %.1f ms" % _ms(func(): main.render(), 10))
	for part in ["_hud", "_ribbon", "_storage_panel"]:
		if main.has_method(part):
			print("  %s: %.1f ms" % [part, _ms(func(): main.call(part).free(), 10)])
	print("  _shop_panel: %.1f ms" % _ms(func(): main._shop_panel(false).free(), 10))
	print("  _run_screen: %.1f ms" % _ms(func(): main._run_screen(false).free(), 10))
	var sc: Control = main._run_screen(false)
	var t0 := Time.get_ticks_usec()
	main.add_child(sc)
	sc.get_combined_minimum_size()
	print("  add to tree: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	await process_frame
	print("  first frame after adding (layout + text): %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	sc.queue_free()
	await process_frame
	# again, now that every glyph is cached
	var sc2: Control = main._run_screen(false)
	main.add_child(sc2)
	t0 = Time.get_ticks_usec()
	await process_frame
	print("  same again (warm): %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var counts := {}
	var stack: Array = [sc2]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		counts[nd.get_class()] = counts.get(nd.get_class(), 0) + 1
		stack.append_array(nd.get_children())
	print("  nodes: ", counts)
	sc2.queue_free()
	# a late-run save: 15 days of play log
	r.plog_on = true
	for d in 15:
		r._plog_morning()
	print("  save size %d KB, SaveGame.save_run: %.1f ms" % [JSON.stringify(r.to_dict()).length() / 1024, _ms(func(): SaveGame.save_run(r), 5)])
	r.plog_on = false
	r.plog = []
	print("  Timeline: %.1f ms" % _ms(func(): Timeline.new().setup(r).free(), 10))
	print("  a Thai label: %.2f ms" % _ms(func(): UI.title("ทดสอบภาษาไทย", 24).free(), 50))
	print("  a pixel card: %.2f ms" % _ms(func(): UI.card(UI.PN, UI.BD, 18, 6).free(), 50))
	await process_frame
	print("pack: run.calc(): %.2f ms" % _ms(func(): r.calc(), 50))
	print("pack: run.links(): %.2f ms" % _ms(func(): r.links(), 50))
	print("pack: run.pack_rates(): %.2f ms" % _ms(func(): r.pack_rates(), 50))
	if main.grid != null:
		main.grid.set_process(false)
		print("morning, pack not redrawn every frame: %.0f fps" % await _fps(3.0))
		main.grid.set_process(true)
	# a fight
	r.travel()
	main.render()
	await process_frame
	main._choose(0)
	await _fps(1.0)
	print("fight: %.0f fps" % await _fps(4.0))
	main._bg.visible = false
	print("fight, no background: %.0f fps" % await _fps(3.0))
	quit()
