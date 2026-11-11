extends SceneTree
## Screen-fit audit: visits every screen and reports what does not fit the window — controls that
## stick out past an edge, and scroll areas whose content is taller than they are (you would have
## to scroll). Saves a screenshot of every screen. Not headless (needs layout + rendering).
## Run once per window size:
##   godot --path . --resolution 720x1280 --script res://tests/ui_overflow.gd -- --out=C:/path/fit
## Options: --lang=th (default en), --only=<screen name part>

var out := "user://fit"
var lang := "en"
var only := ""
var main: Control
var issues := 0
var screens := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--lang="):
			lang = a.substr(7)
		if a.begins_with("--only="):
			only = a.substr(7)
	_run()


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	I18n.set_lang(lang)
	var vs := root.get_visible_rect().size
	print("window %dx%d  wide=%s landscape=%s" % [vs.x, vs.y, main._wide, main._landscape])

	# ---- title, hero, pet, difficulty
	main.run = null
	main._splash = true
	main.render()
	await _check("title_splash")
	main._splash = false
	for st in 4:
		main.title_step = st
		main.sel_cls = "inquisitor"
		main.sel_pet = "bee"
		main.render()
		await _check("title_step%d" % st)

	# ---- a run in progress with a full-ish pack
	seed(3)
	var r := RunState.new("inquisitor", "bee", "abyss")
	r.day = 9
	r.path = "tempest"
	r.gold = 40
	r.lv = 9
	for id in ["blessed_blade", "storm_rune", "mana_crystal", "iron_sword", "wooden_shield", "health_potion"]:
		if GameData.items.has(id):
			r.items.append(r.make_item(id, "storage"))
	r.shop = []
	r.fill_shop()
	main.run = r
	main.render()
	await _check("morning")
	# inspector popup (phone) / tooltip card (PC)
	main.inspect_id = r.shop[0].id
	main.inspect_idx = 0
	main.render()
	await _check("morning_inspect")
	main.inspect_id = ""
	main.inspect_idx = -1
	main.show_book = true
	main.render()
	await _check("book")
	main.show_book = false
	# path choice
	r.path = ""
	r.day = 6
	main.render()
	await _check("path_choice")
	r.path = "tempest"
	r.day = 9
	# road: normal day (3 cards) and a boss day
	r.phase = "afternoon"
	r.nodes = [{"k": "elite", "e": r.foe(true)}, {"k": "combat", "e": r.foe(false)}, {"k": "merchant"}]
	main.render()
	await _check("road_3cards")
	main.foe_info_e = r.with_hazard(r.nodes[0].e)
	main.render()
	await _check("road_details")
	main.foe_info_e = {}
	# every event card on the road (long event lines must wrap)
	var evs := ["smith", "merchant", "roulette", "cauldron", "altar", "chest", "camp"]
	for j in range(0, evs.size(), 2):
		r.nodes = [{"k": "combat", "e": r.foe(false)}]
		for k2 in evs.slice(j, j + 2):
			r.nodes.append({"k": k2})
		main.render()
		await _check("road_events%d" % j)
	r.day = 10
	r.nodes = [{"k": "boss", "e": r.boss_foe(r.boss_on(10))}]
	main.render()
	await _check("road_boss")
	r.day = 9
	# events
	for k in ["smith", "merchant", "roulette", "cauldron", "altar", "chest"]:
		r.phase = "afternoon"
		r.nodes = [{"k": k}]
		main._choose(0)
		await _check("event_" + k)
	# a big pack (long fight stats list), then a boss fight (move bar) and the night
	for _u in 40:
		r.expand += 1
		r.unlock(Vector2i(randi() % GameData.W, randi() % GameData.H))
	for id in ["iron_sword", "wooden_shield", "rune_sword", "storm_rune", "blessed_blade", "mana_crystal", "iron_sword", "wooden_shield", "spark_rune", "whetstone", "health_potion", "iron_sword"]:
		if not GameData.items.has(id):
			continue
		var it := r.make_item(id, "held")
		r.items.append(it)
		var placed := false
		for y in GameData.H:
			for x in GameData.W:
				if not placed and r.fits(it, x, y):
					it.loc = "grid"
					it.x = x
					it.y = y
					placed = true
		if not placed:
			it.loc = "storage"
	r.phase = "afternoon"
	r.day = 10
	r.nodes = [{"k": "boss", "e": r.boss_foe(r.boss_on(10))}]
	main._choose(0)
	await create_timer(3.5).timeout
	await _check("combat_boss")
	var cvs = main.find_children("*", "CombatView", true, false)
	if not cvs.is_empty():
		cvs[0]._toggle_foe_info()
		await _check("combat_info")
		cvs[0]._toggle_foe_info()
	var cs: CombatSim = main._pending_sim
	main._pending_sim = null
	cs.skip_to_end()
	cs.won = true
	cs.php = maxf(cs.php, 10)
	r.lv = 9
	r.xp = 1
	r.go_night(r.nodes[0], true, cs)
	r.result.rew.push_front({"k": "tiles", "v": 4})
	r.result.rew.push_front({"k": "heart", "v": 1})
	r.result.rew.append({"k": "level", "v": r.lv + 1})
	r.result.rew.append({"k": "loot", "id": "iron_sword"})
	for fx in 4:
		r.result.rew.append({"k": "fusion", "a": "wooden_shield", "b": "leather_vest", "r": "brigandine", "evo": false, "stored": false})
	main.render()
	await _check("night_win")
	main._all_stats_cs = r.result.cs
	main.render()
	await _check("night_all_stats")
	main._all_stats_cs = null
	# the next morning opens with the fusions, one at a time
	var rew_fx: Array = r.result.rew.filter(func(w): return w.k == "fusion")
	main._fusion_queue = rew_fx
	main._fusion_seen = 0
	r.picks.clear()
	r.next_day()
	main.render()
	await _check("morning_fusion")
	main._fusion_seen = 3
	main.render()
	await _check("morning_fusion_p2")
	main._fusion_seen = 4
	r.phase = "afternoon"
	# defeat night
	r.phase = "afternoon"
	r.day = 9
	r.nodes = [{"k": "combat", "e": r.foe(false)}]
	var cs2 := r.choose(0)
	cs2.skip_to_end()
	r.go_night(r.nodes[0], false, cs2)
	main.render()
	await _check("night_loss")
	# Endless: the day-15 victory night (Claim / Keep going), then an Endless morning and road
	r.phase = "afternoon"
	r.day = GameData.days
	r.picks.clear()
	r.nodes = [{"k": "boss", "e": r.boss_foe(r.boss_on(GameData.days))}]
	var cs3 := r.choose(0)
	cs3.skip_to_end()
	cs3.won = true
	cs3.php = maxf(cs3.php, 10)
	r.go_night(r.nodes[0], true, cs3)
	r.result.victory = true
	main.render()
	await _check("night_victory")
	r.go_endless()
	r.next_day()
	r.day = 19
	main.render()
	await _check("morning_endless")
	r.phase = "afternoon"
	r.day = 20
	r.nodes = [{"k": "boss", "e": r.boss_foe(r.boss_on(20))}]
	main.render()
	await _check("road_endless_boss")
	r.end_state = "over"
	main.render()
	await _check("end_endless")
	r.endless = false
	# end screens
	r.end_state = "win"
	main.render()
	await _check("end_win")
	r.end_state = "over"
	main.render()
	await _check("end_over")
	# phone: the buffs tab of the end screen (a few level-ups so the list is full)
	r.lvl_bonus = {"dmg": 0.3, "hp_pct": 30.0, "haste": 0.16, "crit": 0.12}
	main._end_tab = 1
	main.render()
	await _check("end_buffs")
	main._end_tab = 0
	print("FIT DONE: %d screens, %d problems" % [screens, issues])
	quit()


## Waits for layout, saves a screenshot and reports anything that does not fit.
func _check(name: String) -> void:
	await create_timer(2.6 if name.begins_with("night") or name.begins_with("morning_f") else 0.9).timeout
	if only != "" and not name.contains(only):
		return
	screens += 1
	var vr := root.get_visible_rect()
	var found: Array = []
	_walk(main, vr, found)
	root.get_texture().get_image().save_png("%s_%s.png" % [out, name])
	for f in found:
		print("  [%s] %s" % [name, f])
	issues += found.size()
	print("%s: %s" % [name, "ok" if found.is_empty() else "%d problem(s)" % found.size()])


func _walk(n: Node, vr: Rect2, found: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control:
		var c := n as Control
		# floating numbers / particles / the drag ghost / tooltips move around on purpose
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE and (c is Label) and c.get_parent() is Control and (c.get_parent() as Control).name.begins_with("@Control") and c.get_parent().get_child_count() > 20:
			return
		var gs := c.get_global_transform().get_scale()
		if absf(gs.x - 1.0) > 0.02 or absf(gs.y - 1.0) > 0.02:
			return   # mid pop / breathe animation: its rect is scaled for a moment
		var g := c.get_global_rect()
		if g.size.x > 1 and g.size.y > 1 and c.modulate.a > 0.05:
			var over := g.end.x > vr.end.x + 3 or g.end.y > vr.end.y + 3 or g.position.x < vr.position.x - 3 or g.position.y < vr.position.y - 3
			if over and not _clipped(c, vr):
				found.append("OFF-SCREEN %s %s rect=%s view=%s" % [c.get_class(), _desc(c), _r(g), _r(vr)])
				return   # report the outermost control only
		if c is ScrollContainer:
			var sc := c as ScrollContainer
			if sc.get_child_count() > 0 and sc.get_child(0) is Control:
				var inner := (sc.get_child(0) as Control).get_combined_minimum_size()
				if (sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and inner.y > sc.size.y + 4) or (sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and inner.x > sc.size.x + 4):
					found.append("NEEDS SCROLL %s content=%s box=%s" % [_desc(c), _r(Rect2(Vector2.ZERO, inner)), _r(Rect2(Vector2.ZERO, sc.size))])
	for ch in n.get_children():
		_walk(ch, vr, found)


## True when an ancestor clips this control and that ancestor itself is on screen.
func _clipped(c: Control, vr: Rect2) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is Control and ((p as Control).clip_contents or p is ScrollContainer):
			var pg := (p as Control).get_global_rect()
			return pg.end.x <= vr.end.x + 3 and pg.end.y <= vr.end.y + 3 and pg.position.x >= -3 and pg.position.y >= -3
		p = p.get_parent()
	return false


func _desc(c: Control) -> String:
	var t := ""
	var probe: Node = c
	for _i in 4:
		if probe is Label:
			t = (probe as Label).text
			break
		if probe is Button:
			t = (probe as Button).text
			break
		if probe is RichTextLabel:
			t = (probe as RichTextLabel).get_parsed_text()
			break
		if probe.get_child_count() == 0:
			break
		probe = probe.get_child(0)
	return "'%s' (%s)" % [t.substr(0, 40).replace("\n", " "), str(c.get_path()).get_slice("/", -1)]


func _r(r: Rect2) -> String:
	return "[%d,%d %dx%d]" % [r.position.x, r.position.y, r.size.x, r.size.y]
