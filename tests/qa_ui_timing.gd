extends SceneTree
## QA: delayed UI callbacks must not touch nodes that were already freed.
## Opens the night screen with rewards, then moves on at once (like a fast tap on "Next day").
## Watch the output for "freed" errors.
## Run: godot --headless --path . --script res://tests/qa_ui_timing.gd

var main: Control


func _initialize() -> void:
	_run()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	var r := RunState.new("ember", "pup", "normal")
	main.run = r
	r.travel()
	var cs := r.choose(0)
	cs.skip_to_end()
	r.go_night(r.nodes[0], true, cs)
	r.result.rew.append({"k": "gold", "v": 9})
	r.result.rew.append({"k": "loot", "id": "fire_gem"})
	main.render()
	await process_frame
	# tap "Next day" right away, before the tiles' delayed effects fire
	r.next_day()
	main.render()
	await create_timer(1.5).timeout
	# same for the victory screen confetti
	r.end_state = "win"
	main.render()
	await process_frame
	main.run = null
	main.render()
	await create_timer(2.5).timeout
	print("UI TIMING TEST DONE")
	quit()
