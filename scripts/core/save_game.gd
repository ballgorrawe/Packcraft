class_name SaveGame
extends RefCounted
## Single-slot run save plus player settings, stored in user:// (AppData on PC, app storage on phones).

const RUN_PATH := "user://run_save.json"
const SETTINGS_PATH := "user://settings.cfg"


static func save_run(r: RunState) -> void:
	if r == null:
		return
	if r.end_state != "":
		clear_run()
		return
	var tmp := RUN_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(r.to_dict()))
	f.close()
	# write-then-rename so a crash mid-write never corrupts the old save
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(RUN_PATH))


static func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)


static func load_run() -> RunState:
	if not has_run():
		return null
	var f := FileAccess.open(RUN_PATH, FileAccess.READ)
	if f == null:
		return null
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return null
	return RunState.from_dict(d)


## Short description for the Continue button, or "" if there is no usable save.
static func run_summary() -> String:
	if not has_run():
		return ""
	var f := FileAccess.open(RUN_PATH, FileAccess.READ)
	if f == null:
		return ""
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary or not GameData.classes.has(d.get("cls", "")):
		return ""
	var c: Dictionary = GameData.classes[d.cls]
	var df := GameData.diff_def(str(d.get("diff", "normal")))
	var pt: Dictionary = GameData.pets.get(str(d.get("pet", "")), {})
	return "%s %s %s · %s · Day %d · ❤️ %d" % [c.ic, I18n.t(c.n), pt.get("ic", ""), df.ic + " " + I18n.t(df.n), int(d.day), int(d.res)]


static func clear_run() -> void:
	if has_run():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))


static func get_setting(key: String, default):
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) != OK:
		return default
	return c.get_value("settings", key, default)


static func set_setting(key: String, value) -> void:
	var c := ConfigFile.new()
	c.load(SETTINGS_PATH)
	c.set_value("settings", key, value)
	c.save(SETTINGS_PATH)
