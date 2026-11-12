extends SceneTree
## Recipe data: every ingredient and result exists, a recipe never mixes two classes, no two recipes share the same ingredients, and every item has a Thai name.
## Run: godot --headless --path . --script res://tests/data_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("th")
	var seen := {}
	for r in GameData.recipes:
		var parts: Array = [r.a, r.b] + ([r.c] if r.c != "" else [])
		var key: String = ("evo:" + r.a) if r.evo else "+".join(_sorted(parts))
		_check(not seen.has(key), "one recipe per ingredient set: " + key)
		seen[key] = true
		for q in parts + [r.r]:
			_check(GameData.items.has(q), "item exists: " + q)
		var cls := {}
		for q in parts:
			if GameData.items.has(q) and GameData.items[q].cl != "":
				cls[GameData.items[q].cl] = true
		_check(cls.size() <= 1, "one class per recipe: " + key)
	for id in GameData.items:
		var n: String = GameData.items[id].n
		_check(I18n.t(n) != n or n == "PACKCRAFT", "Thai name for " + n)
	print("DATA TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _sorted(a: Array) -> Array:
	var b := a.duplicate()
	b.sort()
	return b


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
