extends SceneTree
## Drag-onto-item rules: swap into the dragged item's old spot, else step aside, else storage.
## Run: godot --headless --path . --script res://tests/swap_test.gd

func _init() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	var ok := true
	# Ember Knight starts with Ember Sword (2 tall) at (3,2) and Fire Gem at (4,2) in a 3x3 bag.
	var r := RunState.new("ember")
	var sword: PItem = r.grid_items().filter(func(i): return i.id == "ember_sword")[0]
	var gem: PItem = r.grid_items().filter(func(i): return i.id == "fire_gem")[0]
	# 1) drag the gem onto the sword's top cell: the sword should swap toward the gem's old spot
	var origin := {"x": gem.x, "y": gem.y, "rot": gem.rot}
	gem.loc = "held"
	var res := r.place_with_bump(gem, Vector2i(sword.x, sword.y), origin)
	if gem.loc != "grid" or sword.loc != "grid" or res.stored != 0:
		print("FAIL swap: gem %s sword %s stored %d" % [gem.loc, sword.loc, res.stored])
		ok = false
	if gem.cells().any(func(c): return sword.cells().has(c)):
		print("FAIL overlap after swap")
		ok = false
	# 2) fill the bag so nothing can step aside: the blocker must go to storage
	var r2 := RunState.new("ember")
	for y in range(2, 5):
		for x in range(3, 6):
			if r2.occ().has(Vector2i(x, y)):
				continue
			var f := r2.make_item("fire_gem", "grid", x, y)
			r2.items.append(f)
	var big := r2.make_item("ash_plate", "held")   # 2x2
	r2.items.append(big)
	var res2 := r2.place_with_bump(big, Vector2i(4, 3), {})
	if big.loc != "grid" or res2.stored == 0:
		print("FAIL full bag: big %s stored %d" % [big.loc, res2.stored])
		ok = false
	var cells := {}
	for it in r2.grid_items():
		for c in it.cells():
			if cells.has(c):
				print("FAIL overlap in full bag at ", c)
				ok = false
			cells[c] = true
	print("SWAP TEST: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
