extends SceneTree
## Save round-trip test: plays a few days, saves at each phase, reloads and compares.
## Run: godot --headless --path . --script res://tests/save_test.gd

func _init() -> void:
	GameData.ensure_loaded()
	var fails := 0
	var checks := 0
	for cls in GameData.class_keys:
		var r := RunState.new(cls)
		for day in 6:
			for phase_step in 3:
				var a := JSON.stringify(r.to_dict())
				var b := RunState.from_dict(JSON.parse_string(a))
				checks += 1
				if b == null:
					fails += 1
					print("FAIL load null ", cls, " day ", r.day)
					continue
				var a2 := JSON.stringify(b.to_dict())
				if a != a2:
					fails += 1
					print("FAIL mismatch ", cls, " day ", r.day, " phase ", r.phase)
					for i in a.length():
						if a[i] != a2[i]:
							print("   A: ", a.substr(maxi(0, i - 60), 120))
							print("   B: ", a2.substr(maxi(0, i - 60), 120))
							break
				# make sure derived numbers match too
				if not is_equal_approx(r.pack_rates().x, b.pack_rates().x) or r.links().size() != b.links().size():
					fails += 1
					print("FAIL derived ", cls, " day ", r.day)
				if r.needs_path():
					r.choose_path(r.cls_def().paths[1])
				match phase_step:
					0:
						r.gold += 10
						var it := r.buy_item(0) if not r.shop[0].has("bag") else null
						if it: it.loc = "storage"
						r.travel()
					1:
						var cs := r.choose(0)
						if cs:
							var resumed := RunState.from_dict(JSON.parse_string(JSON.stringify(r.to_dict()))).resume_combat()
							checks += 1
							if resumed == null:
								fails += 1
								print("FAIL resume_combat ", cls)
							cs.skip_to_end()
							r.go_night(r.nodes[0], cs.won, cs)
					2:
						r.next_day()
			if r.end_state != "":
				break
	print("save checks: %d, failures: %d" % [checks, fails])
	quit(1 if fails > 0 else 0)
