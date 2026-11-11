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


## Frame-time spikes over secs: average, worst frame, and how many frames took longer than 16.7 ms.
func _spikes(secs: float) -> String:
	var ts: Array = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < int(secs * 1e6):
		await process_frame
		var now := Time.get_ticks_usec()
		ts.append((now - last) / 1000.0)
		last = now
	var worst := 0.0
	var slow := 0
	var sum := 0.0
	for x in ts:
		worst = maxf(worst, x)
		sum += x
		if x > 16.7:
			slow += 1
	return "avg %.1f ms, worst %.1f ms, %d of %d frames over 16.7 ms" % [sum / ts.size(), worst, slow, ts.size()]


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
	await process_frame
	await process_frame
	var tap := 0.0
	for k in 10:
		var t9 := Time.get_ticks_usec()
		main.render()
		await process_frame
		tap += (Time.get_ticks_usec() - t9) / 1000.0
	print("one tap (rebuild + the next frame): %.1f ms" % (tap / 10.0))
	main._memo_nodes.clear()
	tap = 0.0
	for k in 10:
		main._memo_nodes.clear()
		var t8 := Time.get_ticks_usec()
		main.render()
		await process_frame
		tap += (Time.get_ticks_usec() - t8) / 1000.0
	print("one tap without reuse: %.1f ms" % (tap / 10.0))
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
	# what each part of the shop screen costs once it is on screen (build + add + first frame)
	main.screen.visible = false
	for part in ["_hud", "_ribbon", "_shop_panel", "_run_screen"]:
		if not main.has_method(part):
			continue
		var tot := 0.0
		for k in 5:
			var t1 := Time.get_ticks_usec()
			var node: Control = main.call(part, false) if part in ["_shop_panel", "_run_screen"] else main.call(part)
			main.add_child(node)
			await process_frame
			tot += (Time.get_ticks_usec() - t1) / 1000.0
			node.free()
			await process_frame
		print("  part %s: %.1f ms (build+add+frame)" % [part, tot / 5.0])
	for kind in ["rich", "label", "shape"]:
		var tot2 := 0.0
		for k in 5:
			var t3 := Time.get_ticks_usec()
			var box := VBoxContainer.new()
			for id in ["blessed_blade", "storm_rune", "mana_crystal", "iron_sword", "health_potion"]:
				if kind == "rich":
					box.add_child(UI.rich(GameData.stats_bb(id), 15))
				elif kind == "label":
					box.add_child(UI.wrap_lbl("4 ดาเมจ +2 ฮีล ทุก 2 วิ", 15))
				else:
					box.add_child(ShapeView.new().setup(id, 0, 28.0, true))
			main.add_child(box)
			await process_frame
			tot2 += (Time.get_ticks_usec() - t3) / 1000.0
			box.free()
			await process_frame
		print("  5x %s: %.1f ms" % [kind, tot2 / 5.0])
	var tb := 0.0
	for k in 5:
		var t2 := Time.get_ticks_usec()
		await process_frame
		tb += (Time.get_ticks_usec() - t2) / 1000.0
	print("  empty frame: %.1f ms" % (tb / 5.0))
	main.screen.visible = true
	# a fight
	r.travel()
	main.render()
	await process_frame
	SaveGame.set_setting("fight_speed", 4.0)
	main._choose(0)
	print("fight frames (vsync off): ", await _spikes(5.0))
	main._bg.visible = false
	print("fight, no background: %.0f fps" % await _fps(3.0))
	quit()
