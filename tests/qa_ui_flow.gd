extends SceneTree
## QA: walks the real UI (start -> hero -> pet -> difficulty -> run -> road -> fight -> night)
## by pressing the actual buttons, and prints every step so errors in the log can be placed.
## Run: godot --headless --path . --script res://tests/qa_ui_flow.gd

var main: Control


func _initialize() -> void:
	_run()


func _press(prefix: String) -> bool:
	var b := _find(main, prefix)
	if b == null:
		print("  (no button starting with '%s')" % prefix)
		return false
	b.pressed.emit()
	return true


func _find(n: Node, prefix: String) -> Button:
	if n is Button and n.visible and n.text.begins_with(prefix):
		return n
	for c in n.get_children():
		var r := _find(c, prefix)
		if r:
			return r
	return null


func _step(label: String) -> void:
	print("STEP ", label)
	for _i in 30:
		await process_frame


func _run() -> void:
	I18n.set_lang("en")
	main = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await _step("title")
	_press("⚔️ NEW GAME")
	await _step("hero")
	_press("▶️")
	await _step("hero next")
	_press("◀️ Back")
	await _step("back to title")
	_press("⚔️ NEW GAME")
	await _step("hero again")
	_press("Next")
	await _step("pet")
	_press("Next")
	await _step("difficulty")
	_press("⚔️ START RUN")
	await _step("run started")
	main.selected = main.run.grid_items()[0]
	main.render()
	await _step("inspector open")
	main._clear_sel()
	main.render()
	_press("🎲")
	await _step("reroll")
	_press("Depart")
	await _step("road")
	_press("⚔️ FIGHT!")
	await _step("fight")
	_press("Skip")
	await create_timer(3.0).timeout
	await _step("night")
	_press("Next day")
	await _step("next day")
	print("UI FLOW DONE day=%d phase=%s" % [main.run.day, main.run.phase])
	quit()
