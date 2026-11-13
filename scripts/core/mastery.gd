class_name Mastery
extends RefCounted
## Class mastery (docs/design_v0.14.md): XP and a level per class, a small skill tree that leans the
## shop toward a path, and a cosmetic for every level. Kept in the settings file:
## mst_<cls> = XP, mst_tree_<cls> = {node id: rank}, cos_<cls> = {slot: choice}.

static var _path_items := {}


static func cfg(k: String, d = 0):
	return GameData.mastery.get(k, d)


# ---------------------------------------------------------------- XP and levels

static func xp(cls: String) -> int:
	return int(SaveGame.get_setting("mst_" + cls, 0))


## XP to go from level n - 1 to level n.
static func level_cost(n: int) -> int:
	return int(cfg("level_base", 150)) + int(cfg("level_step", 25)) * n


static func max_level() -> int:
	return int(cfg("max_level", 10))


## [level, XP into the next level, XP that level needs] (need 0 at max level).
static func progress(x: int) -> Array:
	var lv := 0
	while lv < max_level() and x >= level_cost(lv + 1):
		x -= level_cost(lv + 1)
		lv += 1
	return [lv, x, 0 if lv >= max_level() else level_cost(lv + 1)]


static func level(cls: String) -> int:
	return int(progress(xp(cls))[0])


## XP a finished story run earns (a loss earns too; quits, trials and puzzles do not come here).
static func gain(r: RunState) -> int:
	var x: Dictionary = cfg("xp", {})
	var g := mini(r.day, int(x.get("floor_cap", 30))) * int(x.get("floor", 10))
	g += r.boss_wins * int(x.get("boss", 25)) + r.mini_wins * int(x.get("mini", 10))
	if r.end_state == "win" or r.endless:
		g += int(x.get("win", 50))
	return g


## Adds XP to a class. Returns {"from": level before, "to": level after}.
static func award(cls: String, amount: int) -> Dictionary:
	var before := level(cls)
	SaveGame.set_setting("mst_" + cls, xp(cls) + amount)
	return {"from": before, "to": level(cls)}


# ---------------------------------------------------------------- skill tree

## The class's nodes: per path a "Favoured" node (ranks) and a "Head start", plus a shared free reroll.
static func nodes(cls: String) -> Array:
	var out := []
	for p in GameData.classes[cls].paths:
		out.append({"id": "fav_" + p, "k": "fav", "path": p, "max": int(cfg("bias_ranks", 3))})
		out.append({"id": "head_" + p, "k": "head", "path": p, "max": 1})
	out.append({"id": "free_rr", "k": "free_rr", "path": "", "max": 1})
	return out


static func tree(cls: String) -> Dictionary:
	var t = SaveGame.get_setting("mst_tree_" + cls, {})
	return t if t is Dictionary else {}


static func points_left(cls: String) -> int:
	var spent := 0
	for k in tree(cls):
		spent += int(tree(cls)[k])
	return level(cls) - spent


static func add_point(cls: String, id: String) -> bool:
	var n: Array = nodes(cls).filter(func(e): return e.id == id)
	var t := tree(cls)
	if n.is_empty() or points_left(cls) <= 0 or int(t.get(id, 0)) >= int(n[0].max):
		return false
	t[id] = int(t.get(id, 0)) + 1
	SaveGame.set_setting("mst_tree_" + cls, t)
	return true


static func reset(cls: String) -> void:
	SaveGame.set_setting("mst_tree_" + cls, {})


## What the tree gives a new run: {"bias": {path: ranks}, "head": [paths], "free_rr": 0/1}.
static func perks(cls: String) -> Dictionary:
	var t := tree(cls)
	var bias := {}
	var head := []
	for n in nodes(cls):
		var rk := int(t.get(n.id, 0))
		if rk <= 0:
			continue
		match n.k:
			"fav": bias[n.path] = rk
			"head": head.append(n.path)
	return {"bias": bias, "head": head, "free_rr": int(t.get("free_rr", 0))}


## The shop items that build a path's Masterwork (what its class trial buys).
static func path_items(path: String) -> Array:
	if not _path_items.has(path):
		var r := RunState.new(GameData.paths[path].cl, "", "normal")
		var ids := {}
		for d in r.trial_plan(path).days.values():
			for id in d.get("buy", []):
				ids[id] = true
		_path_items[path] = ids.keys()
	return _path_items[path]


# ---------------------------------------------------------------- cosmetics

## The cosmetic a level unlocks: {"k": slot, "v": choice}.
static func reward(lv: int) -> Dictionary:
	return [{}, {"k": "title", "v": 0}, {"k": "theme", "v": 1}, {"k": "skin", "v": 0}, {"k": "spark", "v": 1},
		{"k": "frame", "v": 1}, {"k": "title", "v": 1}, {"k": "theme", "v": 2}, {"k": "skin", "v": 1},
		{"k": "fuse", "v": 1}, {"k": "frame", "v": 2}][clampi(lv, 0, 10)]


## The choices unlocked in a slot at this level, always starting with the plain look (-1 / 0).
static func choices(slot: String, lv: int, cls := "") -> Array:
	var out := [-1] if slot in ["title", "skin"] else [0]
	for l in range(1, lv + 1):
		var w := reward(l)
		if w.k == slot:
			out.append(w.v)
	if slot == "title" and lv >= max_level():
		out.append(2)   # level 10 also gives the third title
	if slot in ["title", "frame"] and cls != "" and bool(SaveGame.get_setting("rush_clear_" + cls, false)):
		out.append(3)   # Boss Rush cleared: Boss Slayer title and crimson frame
	return out


## What a class wears: the saved choice per slot, else the newest unlocked.
static func look(cls: String) -> Dictionary:
	var lv := level(cls)
	var saved = SaveGame.get_setting("cos_" + cls, {})
	var out := {}
	for slot in ["skin", "theme", "spark", "fuse", "frame", "title"]:
		var ch := choices(slot, lv, cls)
		var v = saved.get(slot, ch[-1]) if saved is Dictionary else ch[-1]
		out[slot] = int(v) if ch.has(int(v)) else ch[-1]
	return out


static func equip(cls: String, slot: String, v: int) -> void:
	var saved = SaveGame.get_setting("cos_" + cls, {})
	if not saved is Dictionary:
		saved = {}
	saved[slot] = v
	SaveGame.set_setting("cos_" + cls, saved)


## A look turned into what the screens draw: hero emoji, pack colours, effect colours, frame, title.
static func dress(cls: String, lk: Dictionary) -> Dictionary:
	var c: Dictionary = GameData.classes[cls]
	var col := Color(c.col)
	var skins: Array = cfg("skins", {}).get(cls, [])
	var titles: Array = cfg("titles", {}).get(cls, [])
	var th := int(lk.get("theme", 0))
	var fr := int(lk.get("frame", 0))
	return {
		"hero": skins[lk.skin] if int(lk.get("skin", -1)) >= 0 and int(lk.skin) < skins.size() else c.hero,
		"slot_bg": [Color("#130e0a"), col.darkened(0.82), col.darkened(0.6)][th],
		"slot_bd": [Color("#5a4630"), col.darkened(0.25), col.lightened(0.35)][th],
		"spark": col.lightened(0.2) if int(lk.get("spark", 0)) > 0 else Color(0, 0, 0, 0),   # alpha 0 = not worn
		"fuse": col if int(lk.get("fuse", 0)) > 0 else Color(0, 0, 0, 0),
		"frame": Color(cfg("frames", ["", "#cd7f32", "#ffd34d", "#e5484d"])[fr]) if fr > 0 else Color(0, 0, 0, 0),
		"title": "Boss Slayer" if int(lk.get("title", -1)) == 3 else titles[lk.title] if int(lk.get("title", -1)) >= 0 and int(lk.title) < titles.size() else "",
	}
