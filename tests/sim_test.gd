extends SceneTree
## Headless smoke test: plays full runs with a greedy bot for every hero.
## Run: godot --headless --path . --script res://tests/sim_test.gd
## Add `-- --greedy` to make the bot take Elite/Ambush fights whenever offered (snowball check).

func _init() -> void:
	GameData.ensure_loaded()
	var greedy := OS.get_cmdline_user_args().has("--greedy")
	var wins := 0
	var total := 0
	var el_take := 0
	var el_win := 0
	var hearts_used := 0
	for cls in GameData.class_keys:
		for trial in 4:
			var pet: String = GameData.classes[cls].pets[trial % 2]
			var r := RunState.new(cls, pet)
			var guard := 0
			while r.end_state == "" and guard < 60:
				guard += 1
				_bot_morning(r)
				r.travel()
				var best := 0
				for i in r.nodes.size():
					if greedy and (r.nodes[i].k == "elite" or r.nodes[i].k == "ambush"):
						best = i
				for i in r.nodes.size():
					if r.nodes[i].k == "camp" and r.hp < r.mhp * 0.5:
						best = i
				var cs := r.choose(best)
				if cs != null:
					cs.skip_to_end()
					assert(cs.done, "combat did not finish")
					if r.nodes[best].k == "elite" or r.nodes[best].k == "ambush":
						el_take += 1
						el_win += 1 if cs.won else 0
					var res0 := r.res
					r.go_night(r.nodes[best], cs.won, cs)
					hearts_used += res0 - r.res
				r.next_day()
			total += 1
			if r.end_state == "win":
				wins += 1
			print("%-6s %-8s -> %-4s day %2d  gold %3d  items %2d  tiles %2d" % [cls, pet, r.end_state, r.day, r.gold, r.items.size(), r.tiles.size()])
	print("bot wins: %d / %d" % [wins, total])
	print("elite/ambush fights: %d, won %d  ·  hearts spent: %d" % [el_take, el_win, hearts_used])
	quit()


func _bot_morning(r: RunState) -> void:
	# unlock tiles
	var tries := 0
	while r.expand > 0 and tries < 200:
		tries += 1
		var c := Vector2i(randi() % GameData.W, randi() % GameData.H)
		r.unlock(c)
	# buy what we can afford and try to place it
	for _n in 4:
		var idx := -1
		for i in r.shop.size():
			var e: Dictionary = r.shop[i]
			if e.has("bag"):
				continue
			if e.price <= r.gold:
				idx = i
				break
		if idx < 0:
			break
		var it := r.buy_item(idx)
		if not _place_anywhere(r, it):
			it.loc = "storage"
	# move storage items into the pack where possible
	for it in r.storage_items():
		it.loc = "held"
		if not _place_anywhere(r, it):
			it.loc = "storage"
	if r.gold >= 8:
		for i in r.shop.size():
			if r.shop[i].has("bag") and r.shop[i].price <= r.gold:
				r.buy_bag(i)
				break


func _place_anywhere(r: RunState, it: PItem) -> bool:
	for rot in 4:
		it.rot = rot
		for y in GameData.H:
			for x in GameData.W:
				if r.fits(it, x, y):
					it.loc = "grid"
					it.x = x
					it.y = y
					return true
	it.rot = 0
	return false
