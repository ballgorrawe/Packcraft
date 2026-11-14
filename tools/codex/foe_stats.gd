extends SceneTree
## Monster numbers for the Codex, straight from the game's own formulas: for every difficulty and floor,
## a normal monster's and an Elite's Max HP and damage per second, the floor 3/8/13 mini-boss, and every boss.
## godot --headless --path . --script res://tools/codex/foe_stats.gd -- <out.json>
## (tools/codex/build.js runs it when it finds Godot, else it uses the saved tools/codex/foe_stats.json)


func _initialize() -> void:
	GameData.ensure_loaded()
	seed(1)
	var out := {"floors": {}, "bosses": {}}
	for dd in GameData.difficulties:
		var diff: String = dd.id
		var rows := []
		for day in range(1, GameData.days + 1):
			var r := RunState.new("ember", "", diff)
			r.day = day
			var n := _avg(r, false)
			var el := _avg(r, true)
			var row := {"f": day, "hp": n.x, "dps": n.y, "ehp": el.x, "edps": el.y}
			if day in [3, 8, 13]:
				var m := r.mini_foe()
				row["mhp"] = roundi(m.hp)
				row["mdps"] = snappedf(m.dps, 0.1)
			rows.append(row)
		out.floors[diff] = rows
		var bs := {}
		for b in GameData.bosses:
			var r := RunState.new("ember", "", diff)
			r.day = int(b.d)
			var e := r.boss_foe(b)
			bs[b.n] = {"hp": roundi(e.hp), "dps": snappedf(float(e.get("dps", 0.0)), 0.1)}
		out.bosses[diff] = bs
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("foe stats written")
	quit()


## Average Max HP and damage per second over 30 rolls (family and skills vary).
func _avg(r: RunState, elite: bool) -> Vector2:
	var hp := 0.0
	var dps := 0.0
	for _i in 30:
		var e := r.foe_base(elite)
		hp += e.hp
		dps += e.dps
	return Vector2(roundi(hp / 30.0), snappedf(dps / 30.0, 0.1))
