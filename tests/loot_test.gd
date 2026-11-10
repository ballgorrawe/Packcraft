extends SceneTree
## Loot tier check: what an Elite/boss/normal fight drops by day (2000 rolls each).
## Run: godot --headless --path . --script res://tests/loot_test.gd

func _init() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	var r := RunState.new("ember")
	for k in ["combat", "elite", "boss"]:
		for d in [2, 5, 9, 13]:
			r.day = d
			var cnt := []
			cnt.resize(GameData.tier_names.size())
			cnt.fill(0)
			var none := 0
			for i in 2000:
				var id := r.loot_for(k, {"n": "Magma Golem"} if k == "boss" else {})
				if id == "":
					none += 1
				else:
					cnt[GameData.items[id].tier] += 1
			var s := ""
			for t in GameData.tier_names.size():
				s += "%s %4.1f%%  " % [GameData.tier_names[t].substr(0, 4), 100.0 * cnt[t] / 2000.0]
			print("%-6s day %2d: %s none %4.1f%%" % [k, d, s, 100.0 * none / 2000.0])
	quit()
