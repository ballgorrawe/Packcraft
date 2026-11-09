extends SceneTree
## Loot tier check: what an Elite/boss/normal fight drops by day (2000 rolls each).
## Run: godot --headless --path . --script res://tests/loot_test.gd

func _init() -> void:
	GameData.ensure_loaded()
	var r := RunState.new("pyro", "drake")
	for k in ["combat", "elite", "boss"]:
		for d in [2, 5, 9, 13]:
			r.day = d
			var cnt := [0, 0, 0, 0, 0]
			var none := 0
			for i in 2000:
				var id := r.loot_for(k)
				if id == "":
					none += 1
				else:
					cnt[GameData.items[id].tier] += 1
			var s := ""
			for t in 5:
				s += "%s %4.1f%%  " % [GameData.tier_names[t].substr(0, 4), 100.0 * cnt[t] / 2000.0]
			print("%-6s day %2d: %s none %4.1f%%" % [k, d, s, 100.0 * none / 2000.0])
	quit()
