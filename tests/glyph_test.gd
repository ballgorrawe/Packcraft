extends SceneTree
## Every character the game shows has a glyph in a font the web build carries (browsers give Godot no
## system fonts, so a symbol only Windows has shows as a box there).
## Run: godot --headless --path . --script res://tests/glyph_test.gd
var fails := 0


func _initialize() -> void:
	var fonts := [ThemeDB.fallback_font, load("res://assets/fonts/NotoSansThai.ttf"), load("res://assets/fonts/NotoColorEmoji.ttf"), load("res://assets/fonts/PixelifySans.ttf"), load("res://assets/fonts/Sriracha-Regular.ttf")]
	var txt := ""
	for p in ["res://data/i18n.json", "res://data/game_data.json", "res://data/puzzles.json"]:
		txt += FileAccess.get_file_as_string(p)
	for d in ["res://scripts/", "res://scripts/ui/", "res://scripts/core/"]:
		for fn in DirAccess.get_files_at(d):
			if fn.ends_with(".gd"):
				txt += FileAccess.get_file_as_string(d + fn)
	var seen := {}
	for i in txt.length():
		var c := txt.unicode_at(i)
		if c < 128 or (c >= 0x0E00 and c <= 0x0E7F) or c in [0xFE0F, 0x200D, 0xFE0E] or (c >= 0x1F3FB and c <= 0x1F3FF) or seen.has(c):
			continue
		seen[c] = true
		var who := []
		for k in fonts.size():
			if fonts[k].has_char(c):
				who.append(k)
		if who.is_empty() or who == [3] or who == [4]:
			fails += 1
			print("MISSING U+%X %s %s" % [c, String.chr(c), str(who)])
	print("GLYPH TEST: %s (%d chars)" % ["PASS" if fails == 0 else "%d FAIL" % fails, seen.size()])
	quit()
