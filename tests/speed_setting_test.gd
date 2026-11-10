extends SceneTree
## The fight speed you pick is saved and used by the next fight.
## Run: godot --headless --path . --script res://tests/speed_setting_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	var before = SaveGame.get_setting("combat_speed", 1)
	SaveGame.set_setting("combat_speed", 4)
	var cv := _view()
	_check(cv.speed == 4, "saved 4x is used by a new fight")
	var b4 := _btn(cv, "4×")
	_check(b4 != null and b4.theme_type_variation == "Btn_blue", "4x button is highlighted")
	_btn(cv, "2×").pressed.emit()
	_check(cv.speed == 2 and int(SaveGame.get_setting("combat_speed", 0)) == 2, "pressing 2x saves it")
	_check(_btn(cv, "2×").theme_type_variation == "Btn_blue" and b4.theme_type_variation == "Btn_gray", "highlight moves to 2x")
	_check(_view().speed == 2, "next fight starts at 2x")
	SaveGame.set_setting("combat_speed", before)
	print("SPEED SETTING TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _view() -> CombatView:
	var r := RunState.new("venom", "turtle", "normal")
	r.travel()
	var cs: CombatSim = r.choose(0)
	var cv := CombatView.new().setup(r, cs)
	root.add_child(cv)
	return cv


func _btn(n: Node, text: String) -> Button:
	if n is Button and n.text == text:
		return n
	for c in n.get_children():
		var b := _btn(c, text)
		if b:
			return b
	return null


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1
