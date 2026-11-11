extends SceneTree
## Day 1-4 monsters side by side per mode (same seeds): HP, damage, skills, pet, Ultimate, items.
## Run: godot --headless --path . --script res://tests/early_foes.gd


func _initialize() -> void:
	GameData.ensure_loaded()
	I18n.setup("en")
	for diff in ["normal", "hard", "vhard", "abyss"]:
		for d in [1, 2, 3, 4]:
			var line := []
			for k in 4:
				seed(100 + k)
				var r := RunState.new("rogue", "cat", diff)
				r.day = d
				var e := r.foe(false)
				var sim := CombatSim.new(r, {"k": "preview", "e": e}, true)
				sim.skip_to_end()
				line.append("%s hp%d dps%.1f tr[%s] pet[%s] ult[%s] %s" % [e.tier.substr(0, 1), e.hp, e.dps, e.get("tr", ""), e.get("pet", ""), "y" if not e.get("ult", {}).is_empty() else "", "W" if sim.won else "L"])
			print("%-6s d%d  %s" % [diff, d, " | ".join(line)])
	quit()
