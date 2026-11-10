extends SceneTree
## Lists every non-ASCII character used in the scripts and data that none of the bundled fonts
## (Thai, colour emoji) can draw. On the web there are no system fonts, so these show as boxes.
## Run: godot --headless --path . --script res://tests/glyph_check.gd


func _initialize() -> void:
	var fonts: Array[Font] = [load("res://assets/fonts/NotoSansThai.ttf"), load("res://assets/fonts/NotoColorEmoji.ttf")]
	var extra := ThemeDB.fallback_font
	var files := ["res://data/game_data.json", "res://data/i18n.json"]
	for d in ["res://scripts", "res://scripts/core", "res://scripts/ui"]:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				files.append(d + "/" + f)
	var missing := {}
	for path in files:
		var t := FileAccess.get_file_as_string(path)
		for i in t.length():
			var c := t.unicode_at(i)
			if c < 128 or c == 0xFE0F or c == 0x200D or (c >= 0x0E00 and c <= 0x0E7F):
				continue
			var ok := false
			for f in fonts:
				if f.has_char(c):
					ok = true
					break
			if not ok:
				var key := "%s U+%04X" % [String.chr(c), c]
				if not missing.has(key):
					missing[key] = {"files": {}, "default_font": extra.has_char(c)}
				missing[key].files[path.get_file()] = true
	for k in missing:
		print("MISSING ", k, "  default font has it: ", missing[k].default_font, "  in: ", ", ".join(missing[k].files.keys()))
	print("GLYPH CHECK DONE: ", missing.size(), " missing")
	quit()
