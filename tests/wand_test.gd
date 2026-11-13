extends SceneTree
## 🪄 in a run arranges the pack itself and offers ↩️ undo while the pack is as it left it;
## in a puzzle it only draws the outlines (and caps the stars).
## Run: godot --path . --resolution 720x1280 --script res://tests/wand_test.gd

var fails := 0


func _initialize() -> void:
	_run()


func _btn(n: Node, text: String) -> Button:
	if n is Button and n.text == text:
		return n
	for c in n.get_children():
		var b := _btn(c, text)
		if b != null:
			return b
	return null


func _run() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	seed(7)
	var r := RunState.new("warden", "", "normal")
	# a pack with room to improve: everything in storage
	for id in ["stone_fist", "rock_club", "armor_breaker", "bark_skin"]:
		r.items.append(r.make_item(id, "storage"))
	for it in r.grid_items():
		it.loc = "storage"
	r.calc()
	main.run = r
	main.render()
	await process_frame
	var before := r.pack_rates().x
	var wand := _btn(main, "🪄")
	_check(wand != null, "the 🪄 button is there")
	wand.pressed.emit()
	for i in 4:
		await process_frame
	_check(not r.grid_items().is_empty() and r.pack_rates().x > before, "🪄 put items in the pack (%.1f -> %.1f)" % [before, r.pack_rates().x])
	_check(main.arr_plan.is_empty(), "no hint outlines in a run")
	var undo := _btn(main, "↩️")
	_check(undo != null, "↩️ appears after 🪄")
	if undo != null:
		undo.pressed.emit()
		await process_frame
		_check(r.grid_items().is_empty(), "↩️ puts the pack back as it was")
		_check(_btn(main, "↩️") == null, "↩️ is gone after use")
	# after 🪄, a change to the items ends the undo
	_btn(main, "🪄").pressed.emit()
	for i in 4:
		await process_frame
	r.items.append(r.make_item("whetstone", "storage"))
	main.render()
	await process_frame
	_check(_btn(main, "↩️") == null, "a new item ends the undo")
	# puzzles: outlines only
	var p: Dictionary = GameData.puzzles[0]
	var q := RunState.new(str(p.cls), "", "normal")
	q.start_puzzle(p)
	main.run = q
	main.render()
	await process_frame
	_btn(main, "🪄").pressed.emit()
	for i in 4:
		await process_frame
	_check(q.grid_items().is_empty() and not main.arr_plan.is_empty() and q.puzzle_hint, "in a puzzle 🪄 only draws the outlines")
	print("WAND TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
