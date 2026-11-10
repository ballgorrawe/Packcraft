extends SceneTree
## Visual check of the fight screen: runs a real fight for a few seconds in a window and saves
## screenshots. Not headless (needs rendering).
## Run: godot --path . --script res://tests/shot_fight.gd -- --out=C:/path/shot
## Extra statuses are put on both sides so every chip / bar state is visible.

var out := "user://shot"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run()


func _run() -> void:
	I18n.set_lang("en")
	var r := RunState.new("venom", "turtle", "normal")
	r.travel()
	var cs: CombatSim = r.choose(0)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	var cv := CombatView.new().setup(r, cs)
	cv.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(cv)
	# a monster that poisons and burns you, a monster shield, and Thorns on you
	cs.hd["burn"] = 7.0
	cs.hd["poison"] = 4.0
	cs.fs["burn"] = 9.0
	cs.fshield = 18.0
	cs.add_status("thorns", 5, -1)
	for i in 3:
		await create_timer(1.2).timeout
		cs.gain_shield(6)
		var img := root.get_texture().get_image()
		img.save_png("%s_%d.png" % [out, i])
		print("saved ", "%s_%d.png" % [out, i])
	quit()
