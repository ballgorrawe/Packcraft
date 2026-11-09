extends SceneTree
## Drives the real main scene: start a run, let it autosave, return to title, press Continue.
## Run: godot --headless --path . --script res://tests/ui_save_test.gd
## Backs up and restores any existing save.

var main: Control


func _initialize() -> void:
	_run()


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and n.text.begins_with(prefix):
		return n
	for c in n.get_children():
		var b := _find_button(c, prefix)
		if b:
			return b
	return null


func _run() -> void:
	var backup := ""
	if SaveGame.has_run():
		backup = FileAccess.get_file_as_string(SaveGame.RUN_PATH)
	SaveGame.clear_run()
	var ok := true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.run = RunState.new("ward", "bear")
	main.run.gold = 99
	main.run.travel()
	main._choose(0)            # into a fight (combat or event)
	await process_frame
	var phase_saved: String = main.run.phase
	var day_saved: int = main.run.day
	var gold_saved: int = main.run.gold
	if not SaveGame.has_run():
		print("FAIL: no autosave written")
		ok = false
	# back to title, as if the app restarted
	main.run = null
	main._pending_sim = null
	main.render()
	await process_frame
	var cb := _find_button(main, "▶ CONTINUE")
	if cb == null:
		print("FAIL: Continue button missing")
		ok = false
	else:
		print("Continue button: ", cb.text)
		cb.pressed.emit()
		await process_frame
		if main.run == null or main.run.day != day_saved or main.run.gold != gold_saved or main.run.phase != phase_saved:
			print("FAIL: resumed state differs")
			ok = false
		else:
			print("resumed: day %d, phase %s, gold %d, fight resumed: %s" % [main.run.day, main.run.phase, main.run.gold, main._pending_sim != null])
		if phase_saved == "evening" and main._pending_sim == null:
			print("FAIL: fight not resumed")
			ok = false
	# finishing a run clears the save
	main.run.end_state = "over"
	main.render()
	if SaveGame.has_run():
		print("FAIL: finished run did not clear the save")
		ok = false
	SaveGame.clear_run()
	if backup != "":
		var f := FileAccess.open(SaveGame.RUN_PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	print("UI SAVE TEST: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
