class_name RunState
extends RefCounted
## All rules for one run: day loop, shop, backpack grid, adjacency buffs, evolutions and recipes,
## class paths, nodes and night resolution. Pure logic, no UI, so it can be tested headless.

const RESIST := 0.2          # damage multiplier when the foe resists that element (80% less)
const MAX_HEARTS := 3
const ENDLESS_HEARTS := 5
const COMBAT_DROP := 0.25       # chance a normal fight drops an item
const LOOT_PARTNER_BIAS := 0.35 # chance loot is a recipe partner of something you own
const ELITE_FROM_DAY := 2       # no Elite nodes on day 1
const EVENTS_FROM_DAY := 3      # days 1-2 are fights only (events come later and scale with the day)
const MINI_DAYS := [3, 8, 13]   # a mini-boss guards these floors (the climb before each boss)
const SAVE_VERSION := 2

var cls := ""
var path := ""                  # chosen class path id, "" until path day
var pet := ""                   # companion id (a simple always-on buff), "" for none
var diff := "normal"            # difficulty mode id
static var locked := {}         # signature item ids not unlocked yet (the game fills it; bots and tests see all)
var mode := ""                  # "" a normal run, "trial" a class trial, "puzzle" a puzzle (neither is saved)
var rush: Array = []            # Boss Rush: the 5 bosses (names) of floors 11-15, easiest first
var mst := {}                   # class mastery perks for this run (Mastery.perks): shop lean, head start, free reroll
var cos := {}                   # class mastery look for this run (Mastery.look): skin, pack theme, effects, frame, title
var boss_wins := 0              # bosses and mini-bosses beaten this run (mastery XP)
var mini_wins := 0
var _dress := {}
var trial := {}                 # the trial's plan (trial_plan): what the shop sells each day and the day's steps
var puzzle := {}                # the puzzle being played (data/puzzles.json entry)
var puzzle_hint := false        # the hint was used: this try earns at most 2 stars
var day := 1
var gold := 8
var res := MAX_HEARTS
var hp := 60.0
var mhp := 60.0
var phase := "morning"          # morning | afternoon | evening | night
var items: Array = []           # Array[PItem]
var uid_ctr := 1
var tiles := {}                 # Vector2i -> true (unlocked tiles)
var start := {}                 # Vector2i -> true (hero's starting bag tiles)
var shop: Array = []            # {id, price, lock, sale} or {bag, n, price}
var rr := 0
var expand := 2                 # tiles waiting to be unlocked
var bags := 0
var mod: Dictionary = {}
var hz: Dictionary = {}         # today's hazard, empty if none
var off := {}                   # link key -> true when a Golden Link is toggled off
var nodes: Array = []
var result: Dictionary = {}     # night result
var cur_node := -1              # index of the node chosen this afternoon
var end_state := ""             # "", "win", "over"
var endless := false             # kept playing after the day-15 boss: bosses every 5 days, up to 5 Hearts
var msg := ""
var seen := {}                  # item ids the player has owned (unlocks recipe book entries)
var event := {}                 # the event being played this afternoon (see start_event)
var mhp_mod := 0.0              # permanent Max HP changes (Cursed Altar)
var lv := 1                      # hero level (fights give EXP)
var xp := 0                      # EXP toward the next level
var lvl_bonus := {}              # buffs chosen at level-up picks: key -> total (same keys as pets)
var picks: Array = []            # level-up offers waiting for a choice: each is 3 pick ids
var mw_done := false             # a Masterwork was made this run (only one per run)
var boss_pick := {}              # boss day -> the boss met this run (one of that day's pool)
var plog_on := false             # record the player's decisions (real players only; bots and tests leave it off)
var plog: Array = []             # one entry per day: {"d": day, "m": morning snapshot, "a": [actions]}


func _init(c: String, p := "", df := "normal") -> void:
	GameData.ensure_loaded()
	cls = c
	pet = p if GameData.pets.has(p) else ""
	diff = GameData.diff_def(df).id
	res = max_hearts()
	mhp = max_hp()
	hp = mhp
	mod = GameData.mods.pick_random()
	pick_bosses()
	for t in cls_def().bag:
		tiles[t] = true
		start[t] = true
	for st in cls_def().st:
		items.append(make_item(st[0], "grid", st[1], st[2], true))
	begin_day()


func cls_def() -> Dictionary:
	return GameData.classes[cls]


func pet_def() -> Dictionary:
	return GameData.pets.get(pet, {})


## A hero buff: the pet, the level-up picks, and the stats every level gives (hp, dmg).
func pv(key: String) -> float:
	var v: float = GameData.pets.get(pet, {}).get(key, 0.0) + lvl_bonus.get(key, 0.0)
	if key == "hp" or key == "dmg":
		v += (lv - 1) * float(GameData.leveling.get(key, 0.0))
	return v


## EXP needed to go from level l to l + 1.
func xp_need(l := -1) -> int:
	if l < 0:
		l = lv
	var L: Dictionary = GameData.leveling
	return int(L.get("need_base", 2)) + int((l - 1) / maxi(1, int(L.get("need_step", 3))))


## Adds EXP, levels up as often as it fills, and queues a pick every pick_every levels.
func gain_xp(n: int, rew: Array, lines: Array) -> void:
	if n <= 0:
		return
	xp += n
	rew.append({"k": "xp", "v": n})
	while xp >= xp_need():
		xp -= xp_need()
		lv += 1
		rew.append({"k": "level", "v": lv})
		lines.append(I18n.t("⭐ Level up! You are now level %d.") % lv)
		var every := int(GameData.leveling.get("pick_every", 5))
		if every > 0 and lv % every == 0:
			var ids: Array = GameData.leveling.get("picks", []).map(func(p): return p.id)
			ids.shuffle()
			picks.append(ids.slice(0, 3))
	sync_hp()


func pick_def(id: String) -> Dictionary:
	for p in GameData.leveling.get("picks", []):
		if p.id == id:
			return p
	return {}


## Takes choice i of the oldest waiting level-up offer.
func pick_level(i: int) -> bool:
	if picks.is_empty() or i < 0 or i >= picks[0].size():
		return false
	var p := pick_def(picks[0][i])
	picks.pop_front()
	if p.is_empty():
		return false
	_pl({"a": "lvl", "id": p.id})
	lvl_bonus[p.k] = lvl_bonus.get(p.k, 0.0) + float(p.v)
	sync_hp()
	return true


func diff_def() -> Dictionary:
	return GameData.diff_def(diff)


func path_def() -> Dictionary:
	return GameData.paths.get(path, {})


## True on the path day until the player has picked one of the two class paths.
func needs_path() -> bool:
	return mode in ["", "rush"] and path == "" and day >= GameData.path_day and phase == "morning"   # trials pick theirs, puzzles have none


func choose_path(id: String) -> void:
	if path != "" or not cls_def().paths.has(id):
		return
	path = id
	_pl({"a": "path", "id": id})
	var relic: String = GameData.paths[id].relic
	items.append(make_item(relic, "storage"))
	msg = I18n.t("Path chosen: %s. %s is in your storage — put it in your pack.") % [I18n.t(GameData.paths[id].n), I18n.t(GameData.items[relic].n)]


func make_item(id: String, loc: String, x := 0, y := 0, starter := false) -> PItem:
	var it := PItem.new()
	it.uid = uid_ctr
	uid_ctr += 1
	it.id = id
	it.loc = loc
	it.x = x
	it.y = y
	it.starter = starter
	it.b = _zero_b()
	seen[id] = true
	return it


func _zero_b() -> Dictionary:
	var b := {}
	for k in GameData.BUFF_KEYS:
		b[k] = 0.0
	return b


func grid_items() -> Array:
	return items.filter(func(i): return i.loc == "grid")


func storage_items() -> Array:
	return items.filter(func(i): return i.loc == "storage")


func owns(id: String) -> bool:
	return items.any(func(i): return i.id == id)


func count_owned(id: String) -> int:
	return items.filter(func(i): return i.id == id).size()


## A new story run takes the class's mastery: perks and look.
func apply_mastery(perks: Dictionary, look: Dictionary) -> void:
	mst = perks
	cos = look
	_dress = {}
	for p in mst.get("head", []):
		var pool := Mastery.path_items(p).filter(func(id): return int(GameData.items[id].tier) <= 1)
		if not pool.is_empty():
			items.append(make_item(pool.pick_random(), "storage"))   # Head start


## What this run looks like (Mastery.dress): hero emoji, pack colours, effect colours, frame, title.
func dress() -> Dictionary:
	if _dress.is_empty():
		_dress = Mastery.dress(cls, cos)
	return _dress


func in_class_pool(id: String) -> bool:
	var c: String = GameData.items[id].cl
	return c == "" or c == cls


## Specials ("sp") active in the pack right now.
func has_sp(sp: String) -> bool:
	return grid_items().any(func(i): return sp in i.def().sp.split(","))


# ---------------------------------------------------------------- grid

func occ(exclude: PItem = null) -> Dictionary:
	var o := {}
	for i in grid_items():
		if i == exclude:
			continue
		for c in i.cells():
			o[c] = i
	return o


func fits(it: PItem, x: int, y: int, rot: int = -1, exclude: PItem = null) -> bool:
	if rot < 0:
		rot = it.rot
	var o := occ(exclude)
	for c in GameData.shape(it.id, rot).c:
		var k: Vector2i = Vector2i(x, y) + c
		if not tiles.has(k) or o.has(k):
			return false
	return true


## Cells of `id` at rotation `rot` with anchor `a` are all unlocked tiles (ignores other items).
func on_tiles(id: String, rot: int, a: Vector2i) -> bool:
	for c in GameData.shape(id, rot).c:
		if not tiles.has(a + c):
			return false
	return true


## Nearest anchor/rotation where `it` fits, avoiding `blocked` cells too. Returns {} if none.
func nearest_spot(it: PItem, near: Vector2i, blocked := {}, rots := [0, 1, 2, 3]) -> Dictionary:
	var best := {}
	var bd := 1e9
	for rot in rots:
		for y in range(-3, GameData.H):
			for x in range(-3, GameData.W):
				if not fits(it, x, y, rot, it):
					continue
				var clash := false
				for c in GameData.shape(it.id, rot).c:
					if blocked.has(Vector2i(x, y) + c):
						clash = true
						break
				if clash:
					continue
				var dist: float = absi(x - near.x) + absi(y - near.y) + (0.0 if rot == it.rot else 0.2)
				if dist < bd:
					bd = dist
					best = {"x": x, "y": y, "rot": rot}
	return best


## Rotates a placed item and never just refuses: it tries the spot in place, then nearby spots
## that still cover the tapped cell, and finally pushes the items in the way to free space
## (or to storage). Returns a message ("" when nothing else moved), or "x" if it truly can't.
func rotate_in_pack(it: PItem, d: int) -> String:
	var nr := (it.rot + d + 4) % 4
	var pivot := Vector2i(it.x, it.y) + GameData.mid_cell(it.id, it.rot)
	var home := pivot - GameData.mid_cell(it.id, nr)
	if fits(it, home.x, home.y, nr, it):
		it.rot = nr
		it.x = home.x
		it.y = home.y
		return ""
	# kick: any placement of the rotated shape that still covers the pivot cell
	var best := {}
	var bd := 1e9
	for c in GameData.shape(it.id, nr).c:
		var a: Vector2i = pivot - c
		if fits(it, a.x, a.y, nr, it):
			var dist: float = absi(a.x - home.x) + absi(a.y - home.y)
			if dist < bd:
				bd = dist
				best = {"x": a.x, "y": a.y}
	if best.is_empty():
		var s := nearest_spot(it, home, {}, [nr])
		if not s.is_empty() and absi(s.x - home.x) + absi(s.y - home.y) <= 2:
			best = s
	if not best.is_empty():
		it.rot = nr
		it.x = best.x
		it.y = best.y
		return ""
	# push: put the rotated item down and move whatever is in the way
	var anchor := Vector2i(-99, -99)
	if on_tiles(it.id, nr, home):
		anchor = home
	else:
		for c in GameData.shape(it.id, nr).c:
			if on_tiles(it.id, nr, pivot - c):
				anchor = pivot - c
				break
	if anchor.x == -99:
		return "x"
	var mine := {}
	for c in GameData.shape(it.id, nr).c:
		mine[anchor + c] = true
	var movers := []
	for o in grid_items():
		if o != it and o.cells().any(func(c): return mine.has(c)):
			movers.append(o)
	it.rot = nr
	it.x = anchor.x
	it.y = anchor.y
	var stored := 0
	for o in movers:
		o.loc = "held"
		var s := nearest_spot(o, Vector2i(o.x, o.y), mine)
		if s.is_empty():
			o.loc = "storage"
			stored += 1
		else:
			o.loc = "grid"
			o.x = s.x
			o.y = s.y
			o.rot = s.rot
	if stored > 0:
		return I18n.t("Rotated. %d item(s) in the way went to storage.") % stored
	return I18n.t("Rotated. Items in the way were moved over.")


## Drops `it` at anchor `a` even if items are in the way (all its cells must be unlocked tiles).
## Each item in the way first tries the spot the dragged item came from (`origin`, a swap),
## then a free spot right next to the drop; if neither has room it goes to storage.
## Returns {"moved": [uids moved in the pack], "stored": count}.
func place_with_bump(it: PItem, a: Vector2i, origin: Dictionary) -> Dictionary:
	var out := {"moved": [], "stored": 0}
	if not on_tiles(it.id, it.rot, a):
		return out
	var mine := {}
	for c in GameData.shape(it.id, it.rot).c:
		mine[a + c] = true
	var movers := grid_items().filter(func(o): return o != it and o.cells().any(func(c): return mine.has(c)))
	it.loc = "grid"
	it.x = a.x
	it.y = a.y
	for o in movers:
		o.loc = "held"
		var spot := {}
		if not origin.is_empty():
			var s := nearest_spot(o, Vector2i(origin.x, origin.y))
			if not s.is_empty() and absi(s.x - origin.x) + absi(s.y - origin.y) <= 2:
				spot = s
		if spot.is_empty():
			var s2 := nearest_spot(o, Vector2i(o.x, o.y))
			if not s2.is_empty() and absi(s2.x - o.x) + absi(s2.y - o.y) <= 2:
				spot = s2
		if spot.is_empty():
			o.loc = "storage"
			out.stored += 1
		else:
			o.loc = "grid"
			o.x = spot.x
			o.y = spot.y
			o.rot = spot.rot
			out.moved.append(o.uid)
	return out


func anchor_for(it: PItem, cell: Vector2i) -> Vector2i:
	return cell - GameData.mid_cell(it.id, it.rot)


func adj(a: PItem, b: PItem) -> bool:
	var bc := b.cells()
	for p in a.cells():
		for q in bc:
			if absi(p.x - q.x) + absi(p.y - q.y) == 1:
				return true
	return false


## Items in the pack touching `it`.
func neighbours(it: PItem) -> Array:
	return grid_items().filter(func(o): return o != it and adj(it, o))


func can_unlock(cell: Vector2i) -> bool:
	if expand <= 0 or tiles.has(cell):
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= GameData.W or cell.y >= GameData.H:
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if tiles.has(cell + d):
			return true
	return false


func unlock(cell: Vector2i) -> bool:
	if not can_unlock(cell):
		return false
	tiles[cell] = true
	expand -= 1
	return true


## Recompute adjacency (adj) and whole-pack (all) buffs on every grid item.
func calc() -> Array:
	var g := grid_items()
	for i in g:
		i.b = _zero_b()
	for i in g:
		var d: Dictionary = i.def()
		if not d.adj.is_empty():
			for t in g:
				if t != i and adj(i, t):
					for bf in d.adj:
						if t.def().tags.has(bf.tag):
							t.b[bf.k] += bf.v
		for bf in d.all:
			for t in g:
				if t != i and t.def().tags.has(bf.tag):
					t.b[bf.k] += bf.v
	return g


func max_hp() -> float:
	var m := GameData.base_hp + float(cls_def().get("hp", 0)) + mhp_mod + pv("hp")
	var pct := pv("hp_pct")
	for i in grid_items():
		m += i.def().pass.hp
		pct += i.def().pass.hp_pct
	return maxf(10.0, m * (1.0 + pct / 100.0))


func regen() -> float:
	var r := pv("regen")
	for i in grid_items():
		r += i.def().pass.regen
	return r


func income() -> int:
	var g := int(pv("income"))
	for i in grid_items():
		g += i.def().pass.income
	return g


func sync_hp() -> void:
	var m := max_hp()
	if mhp > 0 and not is_equal_approx(mhp, m):
		hp = hp * m / mhp
	mhp = m
	hp = minf(hp, m)


## What a pack item's numbers are right now and where every change comes from (for its card / tooltip).
## rows: [icon, label, base, now, lower_is_better, pct]; src: [icon, text, applies, why_not].
func buff_report(it: PItem) -> Dictionary:
	calc()
	var d := it.def()
	var on: Dictionary = d.on
	var f := eff(it)
	var rows := []
	if on.dmg > 0:
		rows.append(["⚔️", "Damage", on.dmg, f.dmg, false, false])
	if on.dmg > 0:
		rows.append(["🎯", "Crit", on.crit, f.crit, false, true])
	if on.shield > 0:
		rows.append(["🛡️", "Shield", on.shield, f.shield, false, false])
	if on.heal > 0:
		rows.append(["💚", "Heal", on.heal, f.heal, false, false])
	for k in f.st:
		rows.append([GameData.statuses[k].ic, GameData.statuses[k].n, on.st.get(k, 0.0), f.st[k], false, false])
	if d.cd > 0:
		rows.append(["⏱️", "Every", d.cd, f.cd, true, false])
	var src := []
	for n in grid_items():
		if n == it:
			continue
		var nd: Dictionary = n.def()
		if adj(n, it):
			for bf in nd.adj:
				if d.tags.has(bf.tag):
					var why := _buff_why_not(it, bf)
					src.append([nd.ic, I18n.t(nd.n) + " (" + I18n.t("touching") + ")", GameData._buff_short(bf), why == "", why])
		for bf in nd.all:
			if d.tags.has(bf.tag):
				var why2 := _buff_why_not(it, bf)
				src.append([nd.ic, I18n.t(nd.n) + " (" + I18n.t("whole pack") + ")", GameData._buff_short(bf), why2 == "", why2])
	if it.pd > 0 and on.dmg > 0:
		src.append(["⭐", I18n.t("Permanent upgrades (growth / forge)"), "+%s %s" % [GameData._num(snappedf(it.pd, 0.1)), I18n.t("dmg")], true, ""])
	if it.gs > 0:
		src.append(["⭐", I18n.t("Permanent upgrades (growth / forge)"), "+%s %s" % [GameData._num(snappedf(it.gs, 0.1)), I18n.t("shield")], true, ""])
	if it.gh > 0:
		src.append(["⭐", I18n.t("Permanent upgrades (growth / forge)"), "+%s %s" % [GameData._num(snappedf(it.gh, 0.1)), I18n.t("heal")], true, ""])
	for k in it.gst:
		src.append(["⭐", I18n.t("Permanent upgrades (growth / forge)"), "+%s %s" % [GameData._num(snappedf(it.gst[k], 0.1)), I18n.t(GameData.statuses[k].n).to_lower()], true, ""])
	if it.pc > 0 and d.cd > 0:
		src.append(["🔥", I18n.t("Campfire polish"), "+%d%% %s" % [roundi(it.pc * 100), I18n.t("speed")], true, ""])
	if pv("crit") > 0 and on.dmg > 0:
		src.append(["⭐", I18n.t("Level-up bonus / pet"), "+%d%% %s" % [roundi(pv("crit") * 100), I18n.t("crit")], true, ""])
	if pv("haste") > 0 and d.cd > 0:
		src.append(["⭐", I18n.t("Level-up bonus / pet"), "+%d%% %s" % [roundi(pv("haste") * 100), I18n.t("speed")], true, ""])
	if pv("dmg") > 0 and on.dmg > 0:
		src.append(["⭐", I18n.t("Level-up bonus / pet (in fights)"), "+%d%% %s" % [roundi(pv("dmg") * 100), I18n.t("dmg")], true, ""])
	if mod.id == "blood" and on.dmg > 0:
		src.append(["🌐", I18n.t(mod.n), "+15%% %s" % I18n.t("dmg"), true, ""])
	if mod.id == "storm":
		if on.dmg > 0 and on.el == "Shock":
			src.append(["🌐", I18n.t(mod.n), "+30%% %s" % I18n.t("dmg"), true, ""])
		if d.cd > 0:
			src.append(["🌐", I18n.t(mod.n), "-10%% %s" % I18n.t("speed"), true, ""])
	return {"rows": rows, "src": src}


## Why an aura buff does nothing on this item ("" when it works).
func _buff_why_not(it: PItem, bf: Dictionary) -> String:
	var d := it.def()
	var on: Dictionary = d.on
	match bf.k:
		"dmg", "crit", "pierce":
			return "" if on.dmg > 0 else I18n.t("this item deals no damage")
		"shield":
			return "" if on.shield > 0 else I18n.t("this item gives no Shield")
		"heal":
			return "" if on.heal > 0 else I18n.t("this item does not heal")
		"cdr":
			return "" if d.cd > 0 else I18n.t("this item never triggers")
		"to_fire":
			return "" if on.dmg > 0 and has_sp("fire_convert") else I18n.t("needs the Inferno path")
		_:
			if GameData.statuses.has(bf.k):
				return "" if d.cd > 0 and (on.dmg > 0 or not on.st.is_empty()) else I18n.t("only items that hit or apply statuses")
	return ""


## Effective numbers for an item after buffs, modifier and permanent upgrades.
func eff(i: PItem) -> Dictionary:
	var d := i.def()
	var on: Dictionary = d.on
	var dmg: float = 0.0
	if on.dmg > 0:
		dmg = on.dmg + i.b.dmg + i.pd
		if mod.id == "storm" and on.el == "Shock":
			dmg *= 1.3
		if mod.id == "blood":
			dmg *= 1.15
	var cd: float = d.cd * (1.0 - minf(0.6, i.b.cdr)) * (1.0 - i.pc) * (1.0 - pv("haste"))
	if mod.id == "storm":
		cd *= 1.1
	var st := {}
	for k in on.st:
		st[k] = on.st[k]
	# status buffs only land on items that already hit or apply statuses
	if d.cd > 0 and (on.dmg > 0 or not on.st.is_empty()):
		for k in GameData.statuses:
			if i.b.get(k, 0.0) > 0:
				st[k] = st.get(k, 0.0) + i.b[k]
	for k in i.gst:
		st[k] = st.get(k, 0.0) + i.gst[k]
	return {
		"dmg": snappedf(dmg, 0.1), "cd": maxf(0.3, cd), "crit": minf(1.0, on.crit + i.b.crit + (pv("crit") if on.dmg > 0 else 0.0)), "critx": on.critx,
		"shield": on.shield + (i.b.shield if on.shield > 0 else 0.0) + i.gs, "heal": on.heal + (i.b.heal if on.heal > 0 else 0.0) + i.gh,
		"st": st, "charge": on.charge, "haste": on.haste, "ramp": on.ramp,
		# a Fire gem next to a weapon turns its hits into Fire (Magic) damage
		"el": "Fire" if (i.b.get("to_fire", 0.0) > 0 and on.dmg > 0 and has_sp("fire_convert")) else on.el,
		"pierce": minf(1.0, i.b.get("pierce", 0.0)),
	}


func recipe_ok(r: Dictionary) -> bool:
	if r.get("mw", false) and mw_done:
		return false   # only one Masterwork per run
	return r.path == "" or r.path == path


## Golden Links: recipe or evolution pairs that touch and will fuse at night.
func links() -> Array:
	if mode == "puzzle":
		return []   # puzzles never fuse: no Golden Links to show or plan for
	var g := grid_items()
	var out := []
	var used := {}
	for r in GameData.recipes:
		if not recipe_ok(r):
			continue
		for a in g:
			if a.id != r.a or used.has(a.uid):
				continue
			for b in g:
				if b == a or b.id != r.b or used.has(b.uid) or used.has(a.uid):
					continue
				if not adj(a, b):
					continue
				if r.get("c", "") == "":
					used[a.uid] = true
					used[b.uid] = true
					out.append({"a": a, "b": b, "r": r.r, "evo": r.evo, "key": "%d-%d" % [mini(a.uid, b.uid), maxi(a.uid, b.uid)]})
					continue
				# Masterwork: the third piece must touch one of the other two
				for c in g:
					if c == a or c == b or c.id != r.c or used.has(c.uid) or used.has(a.uid):
						continue
					if adj(c, a) or adj(c, b):
						used[a.uid] = true
						used[b.uid] = true
						used[c.uid] = true
						var ks := [a.uid, b.uid, c.uid]
						ks.sort()
						out.append({"a": a, "b": b, "c": c, "r": r.r, "evo": false, "mw": true, "key": "%d-%d-%d" % ks})
	return out


## Where a fused item lands: nearest free spot to ingredient A (any rotation), or null if none.
func fuse_place(l: Dictionary):
	var o := {}
	for i in grid_items():
		if i == l.a or i == l.b or i == l.get("c"):
			continue
		for c in i.cells():
			o[c] = true
	var best = null
	var bd := 1e9
	for rot in 4:
		var sh: Array = GameData.shape(l.r, rot).c
		for y in GameData.H:
			for x in GameData.W:
				var ok := true
				for c in sh:
					var k: Vector2i = Vector2i(x, y) + c
					if not tiles.has(k) or o.has(k):
						ok = false
						break
				if ok:
					var dist: float = absi(x - l.a.x) + absi(y - l.a.y) + rot * 0.1
					if dist < bd:
						bd = dist
						best = {"x": x, "y": y, "rot": rot}
	return best


## True if `id` completes a recipe or evolution with something you own.
## For an item you already own (`owned_self`), an evolution needs a second copy.
func recipe_partner_owned(id: String, owned_self := false) -> bool:
	if mode == "puzzle":
		return false
	for r in GameData.recipes:
		if not recipe_ok(r):
			continue
		if r.evo:
			if r.a == id and count_owned(id) >= (2 if owned_self else 1):
				return true
		elif r.get("c", "") != "":
			# Masterwork: one of the three, and you own at least one of the others
			var parts := [r.a, r.b, r.c]
			if parts.has(id) and parts.any(func(q): return q != id and owns(q)):
				return true
		elif (r.a == id and owns(r.b)) or (r.b == id and owns(r.a)):
			return true
	return false


## Recipes relevant to an item (as ingredient or result) that this class can make, for the inspector.
func recipes_for(id: String) -> Array:
	return GameData.recipes.filter(func(r): return (r.a == id or r.b == id or r.get("c", "") == id or r.r == id) and (r.path == "" or r.path == path or path == "") and in_class_pool(r.r))


# ---------------------------------------------------------------- play log
# Real players' runs are recorded (anonymous: decisions only) and sent when the run ends, to train the
# balance bot on how people actually play. Each morning keeps a full snapshot so a bot can replay it.

func _pl(a: Dictionary) -> void:
	if plog_on and not plog.is_empty():
		plog[plog.size() - 1].a.append(a)


func _plog_morning() -> void:
	if not plog_on:
		return
	var snap := to_dict()
	snap.erase("plog")
	snap.result = {}
	snap.seen = []
	snap.msg = ""
	plog.append({"d": day, "m": snap, "a": []})


## Turns recording on (a real player's run). A fresh run records its first morning now.
func plog_start() -> void:
	plog_on = true
	if plog.is_empty():
		_plog_morning()


## The pack as [id, x, y, rot] per item.
func plog_pack() -> Array:
	return grid_items().map(func(q): return [q.id, q.x, q.y, q.rot])


## The whole run for sending: summary + every day.
func plog_payload() -> Dictionary:
	return {"cls": cls, "pet": pet, "diff": diff, "path": path, "win": end_state == "win", "end": end_state, "day": day, "lv": lv,
		"endless": endless, "hearts": res, "pack": plog_pack(), "days": plog}


# ---------------------------------------------------------------- economy

func rank() -> int:
	return 0 if day <= 3 else 1 if day <= 7 else 2 if day <= 11 else 3 if day <= 15 else 4


func roll_item() -> String:
	return roll_tiered(rank())


## Rolls a shop-pool item using the rarity row `rk` (0..4), never below `min_tier`.
## With `partner_bias`, that chance picks an item that fuses with something you own (same tier).
func roll_tiered(rk: int, min_tier := 0, partner_bias := 0.0) -> String:
	var w: Array = GameData.rarity_table[clampi(rk, 0, GameData.rarity_table.size() - 1)]
	var tot := 0.0
	for x in w:
		tot += x
	var r := randf() * tot
	var t := 0
	while t < w.size() - 1:
		r -= w[t]
		if r < 0:
			break
		t += 1
	t = maxi(t, min_tier)
	while t >= 0:
		var pool := []
		for k in GameData.items:
			var d: Dictionary = GameData.items[k]
			if d.shop and d.tier == t and in_class_pool(k) and not locked.has(k):
				pool.append(k)
		if pool.size() > 0:
			# mastery: a Favoured path's items come up more often
			for p in mst.get("bias", {}):
				if randf() < float(Mastery.cfg("bias_per_rank", 0.08)) * int(mst.bias[p]):
					var mp := pool.filter(func(k): return Mastery.path_items(p).has(k))
					if mp.size() > 0:
						return mp.pick_random()
			if partner_bias > 0.0 and randf() < partner_bias:
				var pp := pool.filter(func(k): return recipe_partner_owned(k))
				if pp.size() > 0:
					return pp.pick_random()
			return pool.pick_random()
		t -= 1
	return "iron_sword"


## Item reward for winning a fight node, or "" for none. Tier follows the day, not a flat pool,
## so an early Elite gives a Rare, not a Legendary.
func loot_for(k: String, e := {}) -> String:
	match k:
		"elite", "ambush", "mini":
			return roll_tiered(rank() + 1, 2, LOOT_PARTNER_BIAS)   # worth the risk: Rare or better
		"boss":
			return boss_drop(str(e.get("n", "")))
		"combat":
			if randf() < COMBAT_DROP:
				return roll_tiered(rank(), 0, LOOT_PARTNER_BIAS)
	return ""


## Price of a bag piece with n tiles: about 1.5 gold a tile, +1 a tile-pair for every 3 bags
## bought (max +2). Bigger pieces are never cheaper than smaller ones.
func bag_price(n: int) -> int:
	return roundi(n * 1.5) + mini(2, int(bags / 3)) * ceili(n / 2.0)


func fill_shop() -> void:
	if mode == "puzzle":
		shop = []   # a puzzle has only the items it gives
		return
	shop = shop.filter(func(e): return not e.has("bag"))
	if mode == "trial":
		for id in trial.days.get(day, {}).get("buy", []):
			if shop.size() < 5:
				shop.append({"id": id, "price": GameData.items[id].cost})
	while shop.size() < 5:
		var id := roll_item()
		shop.append({"id": id, "price": int(GameData.items[id].cost)})
	shop.append({"bag": true, "n": 3 if day >= 8 else 2, "price": bag_price(3 if day >= 8 else 2)})
	shop.append({"bag": true, "n": 4, "price": bag_price(4)})


func reroll_cost() -> int:
	if rr < int(pv("free_reroll")) + int(mst.get("free_rr", 0)):
		return 0
	return 1 + int(rr / 2) + (1 if mod.id == "guild" else 0)


func reroll() -> bool:
	var c := reroll_cost()
	if gold < c:
		msg = I18n.t("Not enough gold.")
		return false
	gold -= c
	rr += 1
	_pl({"a": "rr", "cost": c, "shop": shop.map(func(e): return e.get("id", "bag"))})
	shop = shop.filter(func(e): return e.get("lock", false))
	fill_shop()
	return true


func toggle_lock(i: int) -> void:
	shop[i].lock = not shop[i].get("lock", false)
	_pl({"a": "lock" if shop[i].lock else "unlock", "id": shop[i].get("id", "bag")})


func buy_bag(i: int) -> bool:
	var e: Dictionary = shop[i]
	if gold < e.price:
		msg = I18n.t("Not enough gold.")
		return false
	gold -= e.price
	_pl({"a": "bag", "n": e.n, "price": e.price})
	expand += e.n
	bags += 1
	# spec: a bag card is gone once bought (a fresh one comes with the next reroll or day)
	shop.remove_at(i)
	for x in shop:
		if x.has("bag"):
			x.price = bag_price(x.n)
	msg = I18n.t("Bag bought: tap the glowing tiles next to your pack to unlock %d tiles.") % e.n
	return true


## Buys a shop item and returns it with loc "held"; the caller places or stores it.
func buy_item(i: int) -> PItem:
	var e: Dictionary = shop[i]
	if gold < e.price:
		msg = I18n.t("Not enough gold.")
		return null
	gold -= e.price
	_pl({"a": "buy", "id": e.id, "price": e.price})
	shop.remove_at(i)
	var it := make_item(e.id, "held")
	it.paid = int(e.price)
	items.append(it)
	return it


func sell_price(it: PItem) -> int:
	return ceili(it.def().cost / 2.0)


func sell(it: PItem) -> bool:
	if it.starter or it.def().relic:
		return false
	_pl({"a": "sell", "id": it.id, "loc": it.loc})
	gold += sell_price(it)
	items.erase(it)
	return true


## Moves every item in the pack into the (unlimited) storage box. Returns how many moved.
func clear_pack() -> int:
	var g := grid_items()
	for it in g:
		it.loc = "storage"
	return g.size()


# ---------------------------------------------------------------- enemies

func enemy_hp(d: int) -> int:
	var base := 4.0 + 4.6 * d if d <= 5 else 27.0 + 3.5 * (d - 5)
	return roundi(base * minf(6.0, 3.8 + 0.5 * d) * GameData.foe_hp_mult)


func enemy_atk(d: int) -> float:
	var am: Array = GameData.atk_curve
	var m: float = am[am.size() - 1][1]
	for i in range(1, am.size()):
		if d <= am[i][0]:
			var a: float = am[i - 1][0]
			var x: float = am[i - 1][1]
			var b: float = am[i][0]
			var y: float = am[i][1]
			m = x + (y - x) * (d - a) / (b - a)
			break
	return (3.0 + 0.55 * d + 0.01 * d * d) * m * GameData.foe_atk_mult


## Damage per second a normal foe should deal today (the pack is scaled to hit this).
## Later days ramp a little faster than the base curve.
func foe_dps(d: int) -> float:
	var ramp := 1.0 + maxf(0.0, d - 8) * GameData.late_ramp
	return enemy_atk(d) / 1.7 * ramp


func foe_base(elite: bool) -> Dictionary:
	var fam: String = GameData.FOE_NAMES.pick_random()
	var e := {"n": fam, "fam": fam, "hp": float(roundi(enemy_hp(day) * diff_def().hp * endless_mult(day, 0.03))), "dps": foe_dps(day) * diff_def().dps * endless_mult(day, 0.01), "imm": "", "weak": "", "tier": "", "tr": "", "dmg_mult": 1.0, "cd_mult": 1.0}
	# monsters follow the player's power curve: weak on the first floors, strong once core items
	# come together after the first boss (data: foe_curve; a mode may override floors 1-4 with early_ease)
	var curve: Array = GameData.foe_curve
	if not curve.is_empty() and day >= 1:
		var f: float = float(curve[mini(day, curve.size()) - 1])
		var dc: Array = GameData.foe_dps_curve if not GameData.foe_dps_curve.is_empty() else curve
		var fd: float = float(dc[mini(day, dc.size()) - 1])
		var early: Array = diff_def().get("early_ease", [])
		if day <= early.size():
			f = float(early[day - 1])
			fd = f
		e.hp = float(roundi(e.hp * f))
		e.dps *= fd
	if elite:
		e.n = "Elite " + fam
		e.hp = float(roundi(e.hp * 1.5))
		e.dps *= 1.3
		if randf() < 0.5:
			e.imm = GameData.ELEMENTS.pick_random()
	return e


func foe(elite: bool, boost := Vector2.ONE) -> Dictionary:
	var e := foe_base(elite)
	e.hp = float(roundi(e.hp * boost.x))
	e.dps *= boost.y
	var r := randf()
	if elite:
		e.tier = "elite"
	elif r < (0.35 if day < 4 else 0.25 if day < 9 else 0.15):
		e.tier = "easy"
	elif r > (0.9 if day < 4 else 0.75 if day < 9 else 0.6):
		e.tier = "tough"
	else:
		e.tier = "normal"
	if e.tier == "easy":
		e.hp = float(roundi(e.hp * 0.65))
		e.dps *= 0.7
	if e.tier == "tough":
		e.hp = float(roundi(e.hp * 1.3))
		e.dps *= 1.25
	_add_skills(e)
	_add_mode_extras(e)
	e.merge(build_pack(e.fam, elite), true)
	_tune_pack(e)
	return e


## The floor 3/8/13 mini-boss: an Elite, tougher after the first boss (floor 3 stays fair), that
## guarantees a Rare-or-better item.
func mini_foe() -> Dictionary:
	var boost := Vector2(0.5, 0.45) if day < 5 else Vector2(0.7, 0.9)   # stays under the next boss
	var e := foe(true, boost)
	if day < 5:
		e.imm = ""   # floor 3 stays fair: no element it shrugs off
	e.n = "Champion " + e.fam
	return e


## Skills (Armored, Vampiric...) by mode and tier: difficulties[].skills = {tier: n or [min, max]}.
## Normal: bosses 1 · Hard: Elites and bosses 1 · Very Hard: all 1, bosses 2 · Abyss: all 2+, bosses 3+.
## A boss keeps its own skill (e.g. the Titan is Armored) and it counts.
func _add_skills(e: Dictionary) -> void:
	if day < int(diff_def().get("extras_from", 5)) and str(e.get("tier", "")) != "boss":
		return   # no monster skills before the first boss (Abyss: from floor 3)
	var spec = diff_def().get("skills", {}).get(str(e.get("tier", "normal")), 0)
	var want: int = randi_range(int(spec[0]), int(spec[1])) if spec is Array else int(spec)
	if str(e.get("tier", "")) == "boss":
		if endless and day > GameData.days:
			want += mini(2, int(maxf(0, day - GameData.days - 5) / 15))   # +1 skill from floor 35, +2 from 50
	var got: Array = str(e.get("tr", "")).split(",", false)
	if want <= got.size():
		return
	# late skills (Vampiric, Spiked, Berserk, Purifier) from day 7, likelier from day 10
	var pool := []
	for k in GameData.traits:
		if got.has(k):
			continue
		if GameData.traits[k].get("late", false):
			if day >= 7:
				pool.append(k)
				if day >= 10:
					pool.append(k)
		else:
			pool.append(k)
	while got.size() < want and not pool.is_empty():
		var k: String = pool.pick_random()
		pool = pool.filter(func(x): return x != k)
		if (k == "armored" and got.has("warded")) or (k == "warded" and got.has("armored")):
			continue
		got.append(k)
		match k:
			"swift":
				e.cd_mult *= 0.7
				e.dps *= 0.85
			"brute":
				e.hp = float(roundi(e.hp * 1.4))
				e.dps *= 1.4
				e.cd_mult *= 1.3
			"regen":
				e.hp = float(roundi(e.hp * 1.1))
	e.tr = ",".join(got)


## Hard and up: the monster brings a pet buff. Very Hard and up: monsters (not bosses) get an Ultimate.
## Statuses from pets and Ultimates grow with the day (st_mult).
func _add_mode_extras(e: Dictionary) -> void:
	e["st_mult"] = 1.0 + day * 0.1
	if day < int(diff_def().get("extras_from", 5)) and str(e.get("tier", "")) != "boss":
		return   # no monster pets or Ultimates before the first boss (Abyss: from floor 3)
	if diff_def().get("pet", false) and not GameData.foe_pets.is_empty():
		var pid: String = GameData.foe_pets.keys().pick_random()
		e["pet"] = pid
		e.hp = float(roundi(e.hp * (1.0 + float(GameData.foe_pets[pid].get("hp", 0.0)))))
	if diff_def().get("ult", false) and e.get("tier", "") != "boss" and GameData.foe_ults.has(str(e.get("fam", ""))):
		e["ult"] = GameData.foe_ults[e.fam]


## Expected damage per second of a monster item before scaling (hits + rough status value).
static func m_dps(id: String) -> float:
	var d: Dictionary = GameData.items[id]
	var on: Dictionary = d.on
	if d.cd <= 0:
		return 0.0
	var v: float = on.dmg * (1.0 + on.crit) + on.st.get("poison", 0.0) * 4.0 + on.st.get("burn", 0.0) * 3.0 + on.st.get("bleed", 0.0) * 2.5
	return v / d.cd


## A random pack for a monster family: bigger, with more and better items on later days.
func build_pack(fam: String, elite: bool) -> Dictionary:
	var gw := 4 if day <= 3 else 5 if day <= 10 else 6
	var gh := 3 if day <= 6 else 4
	if elite:
		gw = mini(6, gw + 1)
	var max_t := mini(3, rank() + (1 if elite else 0))
	var pool: Array = GameData.families.get(fam, []).filter(func(id): return GameData.items[id].tier <= max_t)
	var hitters := pool.filter(func(id): return m_dps(id) > 0)
	var want := mini(8, 2 + int(day / 3) + (1 if elite else 0))
	var picks := [hitters.pick_random()]
	while picks.size() < want and not pool.is_empty():
		# better items are likelier, but every tier keeps a chance
		var tot := 0.0
		for id in pool:
			tot += 1.0 + GameData.items[id].tier
		var roll := randf() * tot
		for id in pool:
			roll -= 1.0 + GameData.items[id].tier
			if roll <= 0:
				picks.append(id)
				break
	var placed := []
	var occ_m := {}
	for id in picks:
		var done := false
		for _try in 40:
			var rot := randi() % 4
			var cs: Array = GameData.shape(id, rot).c
			var x := randi() % gw
			var y := randi() % gh
			var ok := true
			for c in cs:
				var k: Vector2i = Vector2i(x, y) + c
				if k.x >= gw or k.y >= gh or occ_m.has(k):
					ok = false
					break
			if ok:
				for c in cs:
					occ_m[Vector2i(x, y) + c] = true
				placed.append([id, x, y, rot])
				done = true
				break
		if not done and placed.is_empty():
			placed.append([id, 0, 0, 0])
	return {"gw": gw, "gh": gh, "items": placed}


## Boss pack from data, tuned to the boss's attack numbers.
func boss_foe(b: Dictionary) -> Dictionary:
	var e: Dictionary = b.duplicate()
	var bp: Dictionary = GameData.boss_packs.get(b.n, {})
	e["fam"] = b.n
	e["dps"] = b.atk / b.cd * (1.0 + maxf(0.0, b.d - 8) * GameData.late_ramp) * diff_def().dps
	e["hp"] = float(roundi(b.hp * diff_def().hp))
	if int(b.d) == 5 and not endless:
		# the first boss is a little gentler (data: first_boss)
		e.hp = float(roundi(e.hp * float(GameData.first_boss.get("hp", 1.0))))
		e.dps *= float(GameData.first_boss.get("dps", 1.0))
	if endless and int(b.d) > GameData.days:
		var dc: Array = GameData.foe_dps_curve
		var normal_dps: float = foe_dps(b.d) * diff_def().dps * endless_mult(b.d, 0.01) * (float(dc[dc.size() - 1]) if not dc.is_empty() else 1.0)
		e.dps = maxf(e.dps, normal_dps * 0.95)
	e["dmg_mult"] = 1.0
	e["cd_mult"] = 1.0
	e["gw"] = bp.get("w", 4)
	e["gh"] = bp.get("h", 3)
	e["items"] = bp.get("items", []).map(func(it): return [it[0], it[1], it[2], 0])
	_add_skills(e)
	_tune_pack(e)
	e.sup_mult = 1.0   # boss heals/shields are tuned by hand in the data
	_add_mode_extras(e)
	return e


## Scales the pack so its hits add up to the foe's target dps, and its shields/heals to its HP.
func _tune_pack(e: Dictionary) -> void:
	var est := 0.0
	for it in e.items:
		est += m_dps(it[0])
	e.dmg_mult = clampf(e.dps / maxf(0.1, est), 0.2, 6.0)
	e.sup_mult = maxf(1.0, e.hp / 220.0)


## Applies today's hazard to an enemy (returns a copy).
func with_hazard(e: Dictionary) -> Dictionary:
	var o := e.duplicate()
	if hz.is_empty():
		return o
	o.hp = float(roundi(e.hp * hz.hp))
	o.dmg_mult = e.get("dmg_mult", 1.0) * hz.atk
	o.cd_mult = e.get("cd_mult", 1.0) * hz.cd
	return o


## Picks this run's boss for every boss day from that day's pool.
func pick_bosses() -> void:
	boss_pick = {}
	var pools := {}
	for b in GameData.bosses:
		if not pools.has(b.d):
			pools[b.d] = []
		pools[b.d].append(b.n)
	for d in pools:
		boss_pick[d] = pools[d].pick_random()


# ---------------------------------------------------------------- class trials
# A short guided run per path: the shop sells what the path's Masterwork is made of, on the days it
# has to be bought, and each day lists its steps (buy, put two items together, fuse). Floor 5 is a
# training boss. The plan is worked out from the recipes, so every path gets one without a script.

const TRIAL_DAYS := 5
const TRIAL_MW_NIGHT := 3        # the Masterwork fuses this night, so floor 4 and the boss have it


## How an item is made from shop items: {id, kids: [...], evo} (no kids = buy it).
static func _trial_tree(id: String) -> Dictionary:
	var d: Dictionary = GameData.items[id]
	if d.shop and d.tier <= 2:
		return {"id": id, "kids": []}
	for k in GameData.items:
		if GameData.items[k].evo == id and GameData.items[k].shop:
			return {"id": id, "kids": [_trial_tree(k), _trial_tree(k)], "evo": true}
	for r in GameData.recipes:
		if r.r == id and str(r.get("c", "")) == "" and not r.evo:
			return {"id": id, "kids": [_trial_tree(r.a), _trial_tree(r.b)], "evo": false}
	return {"id": id, "kids": []}


## A trial's plan: {path, mw: {r, ids}, days: {day: {buy: [ids], steps: [...]}}}. Steps are
## {t: "buy", id, n} · {t: "link", ids, r, evo} · {t: "mw", ids, r} · {t: "tip", k}.
static func trial_plan(path_id: String) -> Dictionary:
	var mw := {}
	for r in GameData.recipes:
		if r.path == path_id and str(r.get("c", "")) != "":
			mw = r
	if mw.is_empty():
		return {}
	var days := {}
	for d in range(1, TRIAL_DAYS + 1):
		days[d] = {"buy": [], "steps": []}
	# a part made with k more fusions is bought on night (MW night - k), so it is ready in time
	var walk := func(self_ref: Callable, node: Dictionary, ready: int) -> void:
		if node.kids.is_empty():
			days[maxi(1, ready)].buy.append(node.id)
			return
		for kid in node.kids:
			self_ref.call(self_ref, kid, ready - 1)
		days[maxi(1, ready - 1)].steps.append({"t": "link", "ids": node.kids.map(func(k): return k.id), "r": node.id, "evo": node.get("evo", false)})
	# the Legendary part is built first (bought day 1), the other part on day 2: one new thing a day
	walk.call(walk, _trial_tree(mw.a), TRIAL_MW_NIGHT - 1)
	walk.call(walk, _trial_tree(mw.b), TRIAL_MW_NIGHT)
	# buy steps first in each day, then the joins; the Masterwork, then tips
	for d in days:
		var counts := {}
		for id in days[d].buy:
			counts[id] = counts.get(id, 0) + 1
		var buys := counts.keys().map(func(id): return {"t": "buy", "id": id, "n": counts[id]})
		days[d].steps = buys + days[d].steps
	days[TRIAL_MW_NIGHT].steps.append({"t": "mw", "ids": [mw.a, mw.b, mw.c], "r": mw.r})
	days[1].steps.push_front({"t": "tip", "k": "start"})
	days[TRIAL_MW_NIGHT + 1].steps.append({"t": "tip", "k": "arrange"})
	days[TRIAL_DAYS].steps.append({"t": "tip", "k": "boss"})
	return {"path": path_id, "mw": {"r": mw.r, "ids": [mw.a, mw.b, mw.c]}, "days": days}


## Turns this new run into the trial of one of its class's paths.
func start_trial(path_id: String) -> void:
	mode = "trial"
	trial = trial_plan(path_id)
	mod = {"id": "", "n": ""}   # no world modifier: the trial teaches the path as it is
	choose_path(path_id)   # its relic comes now
	msg = ""
	for x in range(2, 7):
		for y in range(1, 6):
			tiles[Vector2i(x, y)] = true   # room for the whole build from the start
	expand = 0
	shop = []
	_trial_gold()
	fill_shop()
	_trial_day()


## Enough gold for the day's planned buys (and a little to try something else).
func _trial_gold() -> void:
	var need := 4
	for id in trial.days.get(day, {}).get("buy", []):
		need += int(GameData.items[id].cost)
	gold = maxi(gold, need)


func _trial_day() -> void:
	_trial_gold()
	if day >= TRIAL_DAYS:
		boss_pick[5] = "Goblin Warlord"   # no spawns or tricks: the training boss tests the build
		var b = boss_on(5)
		var e := boss_foe(b)
		# a training boss sized to your pack: about 20 s of your damage to beat, about 25 s to beat you
		var bench := bench_rates(12.0)
		e.hp = float(roundi(clampf(float(bench.get("dps", 10.0)) * 20.0, 120.0, e.hp * 0.4)))
		e.dps = minf(e.dps * 0.4, mhp / 25.0)
		e.items = e.items.slice(0, 1)   # one weapon: a small pack its tuning can scale down that far
		_tune_pack(e)
		e.sup_mult = 1.0
		nodes = [{"k": "boss", "e": e}]
	else:
		nodes = [{"k": "combat", "e": foe(false, Vector2(0.7, 0.7))}]   # a gentle road: the trial is about the build
		if hp < mhp * 0.5:
			nodes.append({"k": "camp"})


## Today's trial steps with whether each is done: [{step, done}].
func trial_steps() -> Array:
	var out := []
	var made := func(r: String) -> bool: return owns(r) or links().any(func(l): return l.r == r and not off.has(l.key))
	for s in trial.get("days", {}).get(day, {}).get("steps", []):
		var done := false
		match s.t:
			"buy":
				done = count_owned(s.id) >= s.n or made.call(_trial_parent(s.id))
			"link", "mw":
				done = made.call(s.r)
			"tip":
				done = true
		out.append({"step": s, "done": done})
	return out


## The item a bought part goes into (so a part already joined counts as bought).
func _trial_parent(id: String) -> String:
	for d in trial.get("days", {}):
		for s in trial.days[d].steps:
			if s.t == "link" and s.ids.has(id):
				return s.r
	return ""


# ---------------------------------------------------------------- puzzles
# A fixed pack shape and item set against one foe (data/puzzles.json, made by tests/make_puzzles.gd).
# Arrange, fight once, earn stars by the HP left. No shop, no fusing, no saving.

const PUZZLE_SEED := 4242
const PUZZLE_STARS := [0.5, 0.8]   # HP left for the 2nd and 3rd star when a puzzle names none


## Stars for a puzzle fight: a win is 1, more with HP left; a used hint caps it at 2.
func puzzle_stars(win: bool, hp_left: float) -> int:
	if not win:
		return 0
	var marks: Array = puzzle.get("stars", PUZZLE_STARS)   # each puzzle has its own (tests/make_puzzles.gd)
	var s := 1 + (1 if hp_left >= float(marks[0]) else 0) + (1 if hp_left >= float(marks[1]) else 0)
	return mini(s, 2) if puzzle_hint else s


## Turns this new run into a puzzle: its tiles, its items (all in storage) and its foe.
func start_puzzle(p: Dictionary) -> void:
	mode = "puzzle"
	puzzle = p
	mod = {"id": "", "n": ""}   # no world modifier or hazard: a puzzle is the same every time
	hz = {}
	items = []
	tiles = {}
	for t in p.tiles:
		tiles[Vector2i(int(t[0]), int(t[1]))] = true
	start = tiles.duplicate()
	for id in p.items:
		items.append(make_item(str(id), "storage"))
	expand = 0
	gold = 0
	shop = []
	day = int(p.get("day", 6))
	mhp = max_hp()
	hp = mhp
	var e: Dictionary = p.foe.duplicate(true)
	_fix_foe(e)
	nodes = [{"k": "boss" if str(e.get("tier", "")) == "boss" else "combat", "e": e}]
	phase = "morning"
	msg = ""


## Most Hearts you can hold (5 in Endless).
func max_hearts() -> int:
	return (ENDLESS_HEARTS if endless else MAX_HEARTS)


## Endless: beat the day-15 boss and keep going. +2 Hearts (max 5) and a new boss every 5 days.
func go_endless() -> void:
	_pl({"a": "endless"})
	if endless or mode != "":
		return
	endless = true
	res = mini(ENDLESS_HEARTS, res + 2)
	result.victory = false
	msg = I18n.t("♾️ Endless! +2 Hearts. A boss waits every 5 days.")


## How much harder Endless gets per day past day 15.
func endless_mult(d: int, per_day: float) -> float:
	return 1.0 + maxf(0.0, d - GameData.days) * per_day


func boss_on(d: int):
	if mode == "rush":
		var i := d - (GameData.days - RUSH_BOSSES) - 1
		if i < 0 or i >= rush.size():
			return null
		var src: Dictionary = GameData.bosses.filter(func(x): return x.n == rush[i])[0]
		var b := src.duplicate()
		b.d = d
		b.hp = roundf(src.hp * float(enemy_hp(d)) / enemy_hp(int(src.d)) * RUSH_HP)
		b.atk = snappedf(src.atk * foe_dps(d) / foe_dps(int(src.d)) * RUSH_DPS, 0.1)
		return b
	if d > GameData.days:
		if not endless or d % 5 != 0:
			return null
		# Endless bosses: every boss in turn, all with day-15 strength that grows each round
		var order: Array = GameData.bosses.map(func(x): return x.n)
		var first := GameData.bosses.filter(func(x): return x.d == GameData.days)
		var base: Dictionary = first[0] if not first.is_empty() else GameData.bosses[0]
		var pick_n: String = order[(d / 5 + str(boss_pick.get(GameData.days, "")).length()) % order.size()]
		var src: Dictionary = GameData.bosses.filter(func(x): return x.n == pick_n)[0]
		var b := src.duplicate()
		b.d = d
		var avg_hp := 0.0
		var avg_atk := 0.0
		for x in first:
			avg_hp += x.hp / first.size()
			avg_atk += x.atk / x.cd * src.cd / first.size()
		b.hp = roundf(avg_hp * endless_mult(d, 0.03))
		# never below 1.1x a normal monster of that floor (their HP keeps climbing with the floor)
		var curve: Array = GameData.foe_curve
		var normal_hp: float = enemy_hp(d) * (float(curve[curve.size() - 1]) if not curve.is_empty() else 1.0) * endless_mult(d, 0.03)
		b.hp = maxf(b.hp, roundf(normal_hp * 1.1))
		b.atk = snappedf(avg_atk * endless_mult(d, 0.01), 0.1)
		return b
	var want: String = boss_pick.get(d, "")
	var first = null
	for b in GameData.bosses:
		if b.d == d:
			if b.n == want:
				return b
			if first == null:
				first = b
	return first


const EVENTS := ["smith", "merchant", "roulette", "cauldron", "altar", "chest"]


# ---------------------------------------------------------------- Boss Rush
# Floors 1-10 are events only (shop every morning, EXP as if you had fought), then five bosses in a
# row on floors 11-15, chosen at the start and shown from floor 1. No shop and only a little healing
# between bosses; losing one ends the run.

const RUSH_BOSSES := 5
const RUSH_HP := 0.65       # boss HP on top of scaling to the floor (balance knobs: tests/qa_harness --rush=1)
const RUSH_DPS := 0.75
const RUSH_HEAL := 0.25     # share of Max HP healed before each boss after the first


func start_rush() -> void:
	mode = "rush"
	var by_d := {}
	for b in GameData.bosses:
		by_d[int(b.d)] = by_d.get(int(b.d), []) + [b.n]
	var tiers: Array = by_d.keys()
	tiers.sort()
	rush = []
	# easiest first: one early boss, two mid, two late (each tier shuffled, no repeats)
	for t in [tiers[0], tiers[1], tiers[1], tiers[-1], tiers[-1]]:
		var left: Array = by_d[t].filter(func(n): return not rush.has(n))
		rush.append(left.pick_random())
	begin_day()


func _rush_day() -> void:
	var b = boss_on(day)
	if b != null:
		shop = []   # no shopping between bosses: what you built is what you bring
		if day > GameData.days - RUSH_BOSSES + 1:
			hp = minf(mhp, hp + roundf(mhp * RUSH_HEAL))
		nodes = [{"k": "boss", "e": boss_foe(b)}]
		return
	var evs := EVENTS.filter(func(k): return event_ok(k))
	evs.shuffle()
	nodes = evs.slice(0, 3).map(func(k): return {"k": k})
	if hp < mhp * 0.5:
		nodes[nodes.size() - 1] = {"k": "camp"}


func event_ok(k: String) -> bool:
	match k:
		"smith":
			return day >= 2
		"roulette":
			return day >= 4   # a big gold swing: not in the first days
		"altar":
			return day >= 6 and res > 0   # a Legendary item: not before the first boss
		"cauldron":
			return items.filter(func(i): return not i.starter).size() >= 2
	return true


# ---------------------------------------------------------------- day flow

func begin_day() -> void:
	if day > 1:
		gold += maxi(1, 5 + int(day / 2) + income())
	phase = "morning"
	rr = 0
	msg = ""
	hz = {}
	event = {}
	if mode == "" and day >= 3 and boss_on(day) == null and randf() < 0.4:   # trials keep the rules plain
		hz = GameData.hazards.pick_random()
	shop = shop.filter(func(e): return e.get("lock", false))
	fill_shop()
	if randf() < 0.25:
		var c := shop.filter(func(e): return not e.has("bag") and not e.get("lock", false))
		if c.size() > 0:
			var e: Dictionary = c.pick_random()
			e.price = ceili(e.price / 2.0)
			e.sale = true
	if mode == "trial":
		_trial_day()
		return
	if mode == "rush":
		_rush_day()
		_plog_morning()
		return
	var b = boss_on(day)
	if b != null:
		nodes = [{"k": "boss", "e": boss_foe(b)}]
		_plog_morning()
		return
	if MINI_DAYS.has(day):
		nodes = [{"k": "mini", "e": mini_foe()}]
		if hp < mhp * 0.5:
			nodes.append({"k": "camp"})   # hurt: rest instead (no loot), same rule as other days
		_plog_morning()
		return
	nodes = [{"k": "combat", "e": foe(false)}]
	var evs := EVENTS.filter(func(k): return event_ok(k))
	evs.shuffle()
	if day < EVENTS_FROM_DAY:
		# the first days are fights only: two monsters to pick from (no free loot or gold skip)
		nodes.append({"k": "combat", "e": foe(false)})
		evs = []
	else:
		nodes.append({"k": evs[0]})
	if randf() < 0.65:
		var extra := [{"k": "camp"}, {"k": evs[1] if evs.size() > 1 else "camp"}] if not evs.is_empty() else []
		if day >= ELITE_FROM_DAY:
			extra.append({"k": "elite", "e": foe(true)})
		if day >= 3:
			var am := foe(true)
			am.n = "Ambusher " + am.fam
			am.hp = float(roundi(am.hp * 1.15))
			extra.append({"k": "ambush", "e": am})
		if not extra.is_empty():
			nodes.append(extra.pick_random())
	# harder modes throw an extra Elite road at you more often
	if randf() < diff_def().elite and day >= ELITE_FROM_DAY and nodes.size() < 3:
		nodes.append({"k": "elite", "e": foe(true)})
	# under half HP there is always a campfire: it takes the place of an event (never of every fight)
	if hp < mhp * 0.5 and not nodes.any(func(n): return n.k == "camp"):
		var slot := -1
		for i in range(nodes.size() - 1, -1, -1):
			if EVENTS.has(nodes[i].k):
				slot = i
				break
		if slot < 0:
			slot = nodes.size() - 1 if nodes.size() > 1 else -1   # days 1-2: the second fight
		if slot >= 0:
			nodes[slot] = {"k": "camp"}
	_plog_morning()


func travel() -> bool:
	if items.any(func(i): return i.loc == "held"):
		msg = I18n.t("Place the item you are holding first.")
		return false
	if needs_path():
		msg = I18n.t("Choose your path first.")
		return false
	phase = "afternoon"
	return true


## Returns a CombatSim for fights, or null when the node resolves straight to night.
func choose(i: int) -> CombatSim:
	var n: Dictionary = nodes[i]
	cur_node = i
	_pl({"a": "go", "i": i, "k": n.k, "hp": hp, "gold": gold, "pack": plog_pack(), "store": storage_items().map(func(q): return q.id)})
	if n.has("e"):
		calc()
		sync_hp()
		phase = "evening"
		var cs := CombatSim.new(self, n)
		if mode == "puzzle":
			cs._rng.seed = PUZZLE_SEED   # the same layout always fights the same way
			seed(PUZZLE_SEED)            # (some fight rolls use the global dice)
		return cs
	if EVENTS.has(n.k):
		start_event(n.k)
		return null
	go_night(n, true, null)
	return null


## Weighted pick from the boss's drop table (treasure keeps the strong items rare).
func boss_drop(boss: String) -> String:
	var table: Array = GameData.boss_drops.get(boss, [])
	if table.is_empty():
		return roll_tiered(rank() + 1, 2, LOOT_PARTNER_BIAS)
	var tot := 0.0
	for e in table:
		tot += e[1]
	var r := randf() * tot
	for e in table:
		r -= e[1]
		if r <= 0:
			return e[0]
	return table[0][0]


# ---------------------------------------------------------------- events
# Each event is a small screen: start_event() sets it up, the ev_* calls are the player's
# choices, and ev_leave() ends the afternoon (its lines/rewards show at night).

func smith_cost() -> int:
	return 6 + 2 * day


## Item rarity events hand out: today's shop rank, one higher only from day 8.
func _event_rank() -> int:
	return rank() + (1 if day >= 8 else 0)


func start_event(k: String) -> void:
	phase = "event"
	event = {"k": k, "lines": [], "rew": [], "done": false}
	match k:
		"merchant":
			var stock := []
			for _i in 3:
				var id := roll_tiered(_event_rank(), 2)
				stock.append({"id": id, "price": roundi(GameData.items[id].cost * 1.3)})
			event.stock = stock
		"roulette":   # the gambling den: one of three games
			event.game = ["russian", "dice", "wheel"].pick_random()
			event.pot = 0
			match event.game:
				"russian":
					event.bullet = randi() % 6
					event.pulls = 0
				"dice":
					event.die = randi_range(1, 6)
					event.wins = 0
				"wheel":
					event.spins = 0
					event.net = 0
		"altar":
			var pool := GameData.items.keys().filter(func(id): return GameData.items[id].tier == 4 and in_class_pool(id) and not GameData.items[id].relic and not GameData.items[id].tags.has("Treasure"))
			pool.shuffle()
			event.offer = pool.slice(0, 3)
		"chest":
			var item_id := roll_tiered(_event_rank(), 1)
			var box := [{"k": "item", "id": item_id}, {"k": "gold", "v": 4 + 2 * day}, {"k": "curse", "v": 5 + day} if randf() < 0.6 else {"k": "gold", "v": 3 + day}]
			box.shuffle()
			event.box = box


## Blacksmith: evolve one item right away for gold, no duplicate needed.
func ev_smith(it: PItem) -> bool:
	if event.get("done", false) or it.def().evo == "" or gold < smith_cost():
		return false
	gold -= smith_cost()
	var old := it.id
	it.id = it.def().evo
	seen[it.id] = true
	if it.loc == "grid" and not fits(it, it.x, it.y, it.rot, it):
		var s := nearest_spot(it, Vector2i(it.x, it.y))
		if s.is_empty():
			it.loc = "storage"
		else:
			it.x = s.x
			it.y = s.y
			it.rot = s.rot
	_pl({"a": "ev", "k": "smith", "id": old})
	event.rew.append({"k": "fusion", "a": old, "b": old, "r": it.id, "evo": true, "stored": it.loc == "storage"})
	event.lines.append(I18n.t("🔨 The blacksmith reforges %s into %s.") % [I18n.t(GameData.items[old].n), I18n.t(it.def().n)])
	event.done = true
	return true


## Wandering merchant: rare stock; sells your items at full price.
func ev_buy(i: int) -> bool:
	var s: Dictionary = event.stock[i]
	if s.get("sold", false) or gold < s.price:
		return false
	gold -= s.price
	_pl({"a": "ev", "k": "m_buy", "id": s.id, "price": s.price})
	s.sold = true
	items.append(make_item(s.id, "storage"))
	event.rew.append({"k": "loot", "id": s.id})
	return true


## What the merchant pays: full list price, but never more than was paid in the shop
## (no buy-at-discount, sell-at-full loop) and treasure only at its stated value.
func merchant_price(it: PItem) -> int:
	if it.def().tags.has("Treasure"):
		return sell_price(it)
	var p: int = it.def().cost
	if it.paid >= 0:
		p = mini(p, it.paid)
	return p


func ev_sell_full(it: PItem) -> bool:
	if it.starter or it.def().relic or not items.has(it):
		return false
	_pl({"a": "ev", "k": "m_sell", "id": it.id})
	gold += merchant_price(it)
	items.erase(it)
	return true


func roulette_pot(pulls: int) -> int:
	var p := 0
	for k in range(1, pulls + 1):
		p += roundi((1.0 + day * 0.5) * k)   # grows with the day: ~45 gold max on day 4, ~125 on day 15
	return p


## Russian roulette: each empty chamber grows the pot; the bullet costs 35% of your Max HP and the pot.
## Returns "click", "bang" or "max" (five empty pulls: the sixth must be the bullet, so you're done).
func ev_pull() -> String:
	if event.get("done", false) or event.get("game", "russian") != "russian":
		return ""
	_pl({"a": "ev", "k": "pull", "n": event.pulls + 1})
	if event.pulls == event.bullet:
		var dmg := roundf(mhp * 0.35)
		hp = maxf(1.0, hp - dmg)
		event.done = true
		event.lines.append(I18n.t("💥 BANG! You lose %d HP and the pot.") % roundi(dmg))
		event.rew.append({"k": "hp", "v": -roundi(dmg)})
		return "bang"
	event.pulls += 1
	event.pot = roulette_pot(event.pulls)
	if event.pulls >= 5:
		ev_cash_out()
		return "max"
	return "click"


func ev_cash_out() -> void:
	var n := int(event.get("wins", 0) if event.get("game", "") == "dice" else event.get("pulls", 0))
	if event.get("done", false) or n == 0:
		return
	event.done = true
	gold += event.pot
	event.rew.append({"k": "gold", "v": event.pot})
	if event.get("game", "") == "dice":
		event.lines.append(I18n.t("🎲 You walk away with %d gold after %d right guesses.") % [event.pot, n])
	else:
		event.lines.append(I18n.t("🎲 You walk away with %d gold after %d empty chambers.") % [event.pot, n])
	if n >= 4:
		var id := roll_tiered(_event_rank(), 1)
		items.append(make_item(id, "storage"))
		event.rew.append({"k": "loot", "id": id})


## High-low dice: guess whether the next roll is higher or lower. Right: the pot grows (like the
## roulette pot); same number: roll again; wrong: lose the pot and 15% of Max HP. Five right: done.
## Returns "win", "same", "lose" or "max".
func ev_dice(higher: bool) -> String:
	if event.get("done", false) or event.get("game", "") != "dice":
		return ""
	var roll := randi_range(1, 6)
	_pl({"a": "ev", "k": "dice", "hi": higher, "from": event.die, "to": roll})
	var was: int = event.die
	event.die = roll
	if roll == was:
		return "same"
	if (roll > was) != higher:
		var dmg := roundf(mhp * DICE_HP)
		hp = maxf(1.0, hp - dmg)
		event.done = true
		event.lines.append(I18n.t("🎲 Wrong guess: you lose %d HP and the pot.") % roundi(dmg))
		event.rew.append({"k": "hp", "v": -roundi(dmg)})
		return "lose"
	event.wins += 1
	event.pot = roulette_pot(event.wins)
	if event.wins >= 5:
		ev_cash_out()
		return "max"
	return "win"


const DICE_HP := 0.15
const WHEEL_SLOTS := 13          # slot 0 is green, then red and black in turn
const WHEEL_SPINS := 3


## The colour of a wheel slot: "green", "red" or "black".
static func wheel_color(slot: int) -> String:
	return "green" if slot == 0 else ("red" if slot % 2 == 1 else "black")


## Roulette wheel: bet gold on a colour. Red or black pays 2x, green 12x; three spins at most.
## Returns the slot it landed on, or -1 when the bet is not allowed.
func ev_spin(color: String, stake: int) -> int:
	if event.get("done", false) or event.get("game", "") != "wheel" or stake <= 0 or stake > gold:
		return -1
	var slot := randi() % WHEEL_SLOTS
	var won := wheel_color(slot) == color
	var back := stake * (12 if color == "green" else 2) if won else 0
	gold += back - stake
	event.net += back - stake
	event.spins += 1
	event.last = {"slot": slot, "color": color, "won": won}
	_pl({"a": "ev", "k": "spin", "c": color, "bet": stake, "slot": slot})
	if event.spins >= WHEEL_SPINS:
		_wheel_done()
	return slot


func _wheel_done() -> void:
	if event.get("done", false):
		return
	event.done = true
	if event.net != 0:
		event.rew.append({"k": "gold", "v": event.net})
	event.lines.append((I18n.t("🎯 You leave the wheel %d gold up.") if event.net >= 0 else I18n.t("🎯 You leave the wheel %d gold down.")) % absi(event.net))


## Alchemist's cauldron: two of your items in, one better item out.
func ev_brew(a: PItem, b: PItem) -> String:
	if event.get("done", false) or a == b or a.starter or b.starter or a.def().relic or b.def().relic or not items.has(a) or not items.has(b):
		return ""
	var top := maxi(a.def().tier, b.def().tier)
	# one rarity step up. The shop pool tops out at Epic, so from Epic and above pick straight
	# from the next rarity (never lower than the best input).
	var id := roll_tiered(4, top + 1) if top + 1 <= 3 else _brew_high(top)
	_pl({"a": "ev", "k": "brew", "ids": [a.id, b.id], "r": id})
	items.erase(a)
	items.erase(b)
	items.append(make_item(id, "storage"))
	event.done = true
	event.rew.append({"k": "fusion", "a": a.id, "b": b.id, "r": id, "evo": false, "stored": true})
	event.lines.append(I18n.t("⚗️ The cauldron turns %s and %s into %s.") % [I18n.t(a.def().n), I18n.t(b.def().n), I18n.t(GameData.items[id].n)])
	return id


## Cauldron result for Epic+ inputs: a random non-relic, non-treasure item one rarity higher
## (capped at the top rarity that exists), falling back to the same rarity.
func _brew_high(top: int) -> String:
	for t in [mini(top + 1, 6), top]:
		var pool := GameData.items.keys().filter(func(id): return GameData.items[id].tier == t and in_class_pool(id) and not GameData.items[id].relic and not GameData.items[id].tags.has("Treasure"))
		if pool.size() > 0:
			return pool[randi() % pool.size()]
	return roll_tiered(4, 3)


func ev_altar(i: int, pay: String) -> bool:
	if event.get("done", false) or i < 0 or i >= event.offer.size():
		return false
	# the only price is a Heart (paying with Max HP was removed)
	if pay != "heart" or res <= 0:
		return false
	res -= 1
	event.rew.append({"k": "heart", "v": -1})
	var id: String = event.offer[i]
	_pl({"a": "ev", "k": "altar", "id": id, "offer": event.offer})
	items.append(make_item(id, "storage"))
	event.rew.append({"k": "loot", "id": id})
	event.lines.append(I18n.t("🗿 The altar takes its price and leaves %s.") % I18n.t(GameData.items[id].n))
	event.done = true
	return true


## Mystery chests: open one of three.
func ev_chest(i: int) -> Dictionary:
	if event.get("done", false):
		return {}
	var c: Dictionary = event.box[i]
	_pl({"a": "ev", "k": "chest", "i": i, "got": c.k})
	event.done = true
	event.picked = i
	match c.k:
		"item":
			items.append(make_item(c.id, "storage"))
			event.rew.append({"k": "loot", "id": c.id})
		"gold":
			gold += c.v
			event.rew.append({"k": "gold", "v": c.v})
		"curse":
			hp = maxf(1.0, hp - c.v)
			event.rew.append({"k": "hp", "v": -c.v})
			event.lines.append(I18n.t("📦 A trap! The chest bites for %d HP.") % c.v)
	return c


## Ends the event; its lines and rewards are shown at night.
func ev_leave() -> void:
	if phase != "event":
		return
	_pl({"a": "ev", "k": "leave", "ev": event.k})
	if event.k == "roulette" and not event.done:
		if event.get("game", "russian") == "wheel":
			if event.spins > 0:
				_wheel_done()
		else:
			ev_cash_out()
	go_night(nodes[cur_node], true, null)


## Simple choices for the balance bot.
func auto_event() -> void:
	match event.k:
		"smith":
			for it in grid_items():
				if it.def().evo != "" and gold >= smith_cost():
					ev_smith(it)
					break
		"roulette":
			match event.get("game", "russian"):
				"russian":
					for _i in 2:
						if ev_pull() != "click":
							break
				"dice":
					for _i in 2:
						if event.get("done", false) or ev_dice(event.die <= 3) == "lose":
							break
				# the wheel: walk past it
		"chest":
			ev_chest(randi() % 3)
	ev_leave()


## Rebuilds the fight for a run that was saved mid-combat (the fight restarts from the start).
func resume_combat() -> CombatSim:
	if phase != "evening" or cur_node < 0 or cur_node >= nodes.size():
		return null
	calc()
	sync_hp()
	return CombatSim.new(self, nodes[cur_node])


# ---------------------------------------------------------------- save / load

static func _v2a(v: Vector2i) -> Array:
	return [v.x, v.y]


func to_dict() -> Dictionary:
	var its := []
	for i in items:
		if i.uid < 0:
			continue  # temporary shop drag ghost
		var loc: String = i.loc
		if loc == "held":
			loc = "storage"
		its.append({"uid": i.uid, "id": i.id, "loc": loc, "x": i.x, "y": i.y, "rot": i.rot, "starter": i.starter, "pd": i.pd, "pc": i.pc, "paid": i.paid, "gs": i.gs, "gh": i.gh, "gst": i.gst, "gc": i.gc})
	var res_d := {}
	if not result.is_empty():
		res_d = {"n": result.n, "win": result.win, "lines": result.lines, "over": result.over, "victory": result.victory, "rew": result.get("rew", []), "fused": result.get("fused", [])}
	return {
		"v": SAVE_VERSION, "cls": cls, "path": path, "pet": pet, "diff": diff, "day": day, "gold": gold, "res": res, "hp": hp, "mhp": mhp,
		"phase": phase, "items": its, "uid_ctr": uid_ctr,
		"tiles": tiles.keys().map(_v2a), "start": start.keys().map(_v2a),
		"shop": shop, "rr": rr, "expand": expand, "bags": bags, "mod": mod.id, "hz": hz.get("id", ""),
		"off": off.keys(), "nodes": nodes, "cur_node": cur_node, "result": res_d, "end_state": end_state,
		"msg": msg, "seen": seen.keys(), "event": event, "mhp_mod": mhp_mod,
		"lv": lv, "xp": xp, "lvl_bonus": lvl_bonus, "picks": picks, "mw_done": mw_done, "endless": endless,
		"boss_pick": boss_pick, "plog": plog, "mst": mst, "cos": cos, "bw": boss_wins, "mnw": mini_wins, "mode": mode, "rush": rush,
	}


## JSON turns ints into floats; put back the ones the game compares or indexes with.
static func _fix_foe(e: Dictionary) -> void:
	for k in ["d", "gw", "gh"]:
		if e.has(k):
			e[k] = int(e[k])
	if e.has("items"):
		e.items = e.items.map(func(it): return [str(it[0]), int(it[1]), int(it[2]), int(it[3]) if it.size() > 3 else 0])


static func from_dict(d: Dictionary) -> RunState:
	GameData.ensure_loaded()
	if int(d.get("v", 0)) != SAVE_VERSION or not GameData.classes.has(d.get("cls", "")):
		return null
	var r := RunState.new(d.cls, str(d.get("pet", "")), str(d.get("diff", "normal")))
	r.path = str(d.get("path", ""))
	r.mhp_mod = float(d.get("mhp_mod", 0.0))
	r.lv = int(d.get("lv", 1))
	r.mw_done = bool(d.get("mw_done", false))
	r.endless = bool(d.get("endless", false))
	r.xp = int(d.get("xp", 0))
	r.lvl_bonus = d.get("lvl_bonus", {})
	r.picks = d.get("picks", [])
	if d.has("boss_pick"):
		r.boss_pick = {}
		for k in d.boss_pick:
			r.boss_pick[int(k)] = str(d.boss_pick[k])
	r.event = d.get("event", {})
	for s in r.event.get("stock", []):
		s.price = int(s.price)
	for c in r.event.get("box", []):
		if c.has("v"):
			c.v = int(c.v)
	if r.event.has("picked"):
		r.event.picked = int(r.event.picked)
	for k in ["die", "wins", "spins", "net"]:
		if r.event.has(k):
			r.event[k] = int(r.event[k])
	if r.event.has("bullet"):
		r.event.bullet = int(r.event.bullet)
		r.event.pulls = int(r.event.pulls)
		r.event.pot = int(r.event.pot)
	r.day = int(d.day)
	r.gold = int(d.gold)
	r.res = int(d.res)
	r.hp = float(d.hp)
	r.mhp = float(d.mhp)
	r.phase = d.phase
	r.uid_ctr = int(d.uid_ctr)
	r.items = []
	for s in d.items:
		if not GameData.items.has(s.id):
			continue
		var it := PItem.new()
		it.uid = int(s.uid)
		it.id = s.id
		it.loc = s.loc
		it.x = int(s.x)
		it.y = int(s.y)
		it.rot = int(s.rot)
		it.starter = bool(s.starter)
		it.pd = float(s.pd)
		it.gs = float(s.get("gs", 0.0))
		it.gh = float(s.get("gh", 0.0))
		it.gst = s.get("gst", {})
		it.gc = int(s.get("gc", 0))
		it.pc = float(s.pc)
		it.paid = int(s.get("paid", -1))
		it.b = r._zero_b()
		r.items.append(it)
	r.tiles = {}
	for p in d.tiles:
		r.tiles[Vector2i(int(p[0]), int(p[1]))] = true
	r.start = {}
	for p in d.start:
		r.start[Vector2i(int(p[0]), int(p[1]))] = true
	r.shop = []
	for e in d.shop:
		var c: Dictionary = e.duplicate()
		c.price = int(c.price)
		if c.has("n"):
			c.n = int(c.n)
		if c.has("id") and not GameData.items.has(c.id):
			continue
		r.shop.append(c)
	r.rr = int(d.rr)
	r.expand = int(d.expand)
	r.bags = int(d.bags)
	for m in GameData.mods:
		if m.id == d.mod:
			r.mod = m
	r.hz = {}
	for h in GameData.hazards:
		if h.id == d.hz:
			r.hz = h
	r.off = {}
	for k in d.off:
		r.off[k] = true
	r.nodes = d.nodes
	for n in r.nodes:
		if n.has("e"):
			_fix_foe(n.e)
	r.cur_node = int(d.get("cur_node", -1))
	r.result = {}
	if not d.result.is_empty():
		r.result = {"n": d.result.n, "win": d.result.win, "lines": d.result.lines, "over": d.result.over, "victory": d.result.victory, "cs": null, "rew": d.result.get("rew", []), "fused": d.result.get("fused", [])}
		for w in r.result.rew:
			if w.has("v"):
				w.v = int(w.v)
		r.result.fused = r.result.fused.map(func(u): return int(u))
		if r.result.n.has("e"):
			_fix_foe(r.result.n.e)
	elif r.phase == "night":
		r.phase = "morning"
	r.end_state = d.end_state
	r.plog = d.get("plog", [])
	r.mst = d.get("mst", {})
	for p in r.mst.get("bias", {}):
		r.mst.bias[p] = int(r.mst.bias[p])
	r.cos = d.get("cos", {})
	for k in r.cos:
		r.cos[k] = int(r.cos[k])
	r.boss_wins = int(d.get("bw", 0))
	r.mode = str(d.get("mode", ""))
	r.rush = d.get("rush", [])
	r.mini_wins = int(d.get("mnw", 0))
	r.msg = d.msg
	r.seen = {}
	for k in d.seen:
		r.seen[k] = true
	return r


# ---------------------------------------------------------------- night

func go_night(n: Dictionary, win: bool, cs: CombatSim) -> void:
	phase = "night"
	var r := {"n": n, "win": win, "cs": cs, "lines": [], "over": false, "victory": false, "rew": [], "fused": []}
	if mode == "puzzle":
		var left := cs.php / maxf(1.0, cs.mhp) if cs != null else 0.0
		r.stars = puzzle_stars(win, left)
		r.victory = win
		r.over = not win
		r.lines.append(I18n.t("⭐ %d of 3 stars") % r.stars if win else I18n.t("Not this time: try another layout."))
		result = r
		randomize()   # the puzzle seeded the global dice: free them again for whatever comes next
		return
	result = r
	if cs != null:
		hp = maxf(1.0, roundf(cs.php)) if win else 0.0
		for x in cs.items:
			if x.d.once and x.used:
				items.erase(x.i)
				r.lines.append(I18n.t("🧪 %s was used up.") % I18n.t(x.d.n))
	var ws := grid_items().filter(func(i): return i.def().tags.has("Weapon"))
	if EVENTS.has(n.k):
		r.lines.append_array(event.get("lines", []))
		r.rew.append_array(event.get("rew", []))
		event = {}
	match n.k:
		"forge":
			if ws.size() > 0:
				var t: PItem = ws.pick_random()
				t.pd += 3
				r.lines.append(I18n.t("🔨 The forge sharpens %s: +3 damage for the rest of the run.") % I18n.t(t.def().n))
				r.rew.append({"k": "forge", "id": t.id})
			else:
				r.lines.append(I18n.t("🔨 You had no weapon in the pack to forge."))
		"tailor":
			expand += 3
			r.lines.append(I18n.t("🧵 The tailor sews 3 extra tiles onto your pack. Place them next morning."))
			r.rew.append({"k": "tiles", "v": 3})
		"shrine":
			var id := roll_tiered(rank() + 1, 2, LOOT_PARTNER_BIAS)
			items.append(make_item(id, "storage"))
			hp = maxf(1.0, hp - 15)
			r.lines.append(I18n.t("🗿 The shrine drains 15 HP and gives you %s %s (in storage).") % [GameData.items[id].ic, I18n.t(GameData.items[id].n)])
			r.rew.append({"k": "loot", "id": id})
			r.rew.append({"k": "hp", "v": -15})
		"camp":
			if hp < mhp:
				var h := minf(mhp - hp, roundf(mhp * 0.5))
				hp += h
				r.lines.append(I18n.t("🔥 You rest by the fire and recover %d HP.") % roundi(h))
				r.rew.append({"k": "heal", "v": roundi(h)})
			else:
				for w in ws:
					w.pc = minf(0.5, w.pc + 0.05)
				r.lines.append(I18n.t("🔥 You are at full HP, so every weapon polishes to 5% faster."))
		"smith", "merchant", "roulette", "cauldron", "altar", "chest":
			if mode == "rush":   # no fights before the bosses: events give the EXP a fight would
				gain_xp(int(GameData.leveling.get("xp", {}).get("combat", 0)), r.rew, r.lines)
		_:
			if win:
				var g := roundi((4 + ceili(day / 2.0)) * (2.5 if n.k in ["elite", "ambush", "mini"] else 1.0)) + (10 if n.k == "boss" else 0)
				if mod.id == "guild":
					g = roundi(g * 1.4)
				if has_sp("gold_engine"):
					g += 5
				gold += g
				r.lines.append(I18n.t("🏆 Victory! +%d gold.") % g)
				r.rew.append({"k": "gold", "v": g})
				# bosses give a Heart back; Endless bosses only half the time
				if n.k == "boss" and res < max_hearts() and (day <= GameData.days or randf() < 0.5):
					res += 1
					r.lines.append(I18n.t("❤️ Boss reward: +1 Heart."))
					r.rew.append({"k": "heart", "v": 1})
				if n.k == "boss":
					boss_wins += 1
				elif n.k == "mini":
					mini_wins += 1
				if n.k == "boss" and day > GameData.days:
					var ids: Array = GameData.leveling.get("picks", []).map(func(p): return p.id)
					ids.shuffle()
					picks.append(ids.slice(0, 3))
					r.lines.append(I18n.t("♾️ Endless reward: pick a lasting buff."))
				if n.k == "boss":
					expand += 4
					r.lines.append(I18n.t("🎒 Boss reward: +4 pack tiles."))
					r.rew.append({"k": "tiles", "v": 4})
				if n.k in ["elite", "ambush", "mini"]:
					expand += 1
					r.lines.append(I18n.t("🎒 Spoils: +1 pack tile."))
					r.rew.append({"k": "tiles", "v": 1})
				gain_xp(int(GameData.leveling.get("xp", {}).get(n.k, 0)), r.rew, r.lines)
				_grow_items(r.lines)
				var id := loot_for(n.k, n.get("e", {}))
				if id != "":
					items.append(make_item(id, "storage"))
					r.lines.append(I18n.t("🎁 Loot added to storage: %s %s (%s)") % [GameData.items[id].ic, I18n.t(GameData.items[id].n), I18n.t(GameData.tier_names[GameData.items[id].tier])])
					r.rew.append({"k": "loot", "id": id})
			else:
				# Losing a fight you picked for its loot pays nothing: hearts keep the run alive, not the reward.
				var c := 0 if n.k in ["elite", "ambush", "mini"] else 2 + int(day / 3)
				gold += c
				if mode == "rush":
					res = 0   # Boss Rush: a lost boss ends the run
				if res > 0:
					res -= 1
					hp = roundf(mhp * 0.5)
				var how := I18n.t("You spend a Heart and revive at 50% HP, ") if hp > 0 else I18n.t("No Hearts left, ")
				r.lines.append(I18n.t("💔 Defeated! %ssalvaging %d gold.") % [how, c])
				r.rew.append({"k": "gold", "v": c})
	# Night: Golden Links (recipes and evolutions) fuse
	for l in links():
		if off.has(l.key):
			continue
		var pl = fuse_place(l)
		items.erase(l.a)
		items.erase(l.b)
		var lc: PItem = l.get("c")
		if lc != null:
			items.erase(lc)
			mw_done = true
		var f := make_item(l.r, "grid" if pl != null else "storage")
		if pl != null:
			f.x = pl.x
			f.y = pl.y
			f.rot = pl.rot
		# growth carries over into what they fuse into
		var parts := [l.a, l.b] + ([lc] if lc != null else [])
		for q in parts:
			f.absorb(q)
		f.pc = maxf(l.a.pc, l.b.pc)
		f.starter = l.a.starter and l.b.starter
		items.append(f)
		var a: Dictionary = GameData.items[l.a.id]
		var rd: Dictionary = GameData.items[l.r]
		var tail := "" if pl != null else I18n.t(" (sent to storage — no room in pack)")
		r.rew.append({"k": "fusion", "a": l.a.id, "b": l.b.id, "c": lc.id if lc != null else "", "r": l.r, "evo": l.evo, "mw": lc != null, "stored": pl == null})
		r.fused.append(f.uid)
		if lc != null:
			r.lines.append(I18n.t("👑 Masterwork! %s + %s + %s » %s %s!") % [a.ic, GameData.items[l.b.id].ic, GameData.items[lc.id].ic, rd.ic, I18n.t(rd.n)] + tail)
		elif l.evo:
			r.lines.append(I18n.t("✨ Evolution! Two %s %s became %s %s!") % [a.ic, I18n.t(a.n), rd.ic, I18n.t(rd.n)] + tail)
		else:
			r.lines.append(I18n.t("✨ Fusion! %s + %s » %s %s!") % [a.ic, GameData.items[l.b.id].ic, rd.ic, I18n.t(rd.n)] + tail)
	_pl({"a": "night", "win": win, "hp": hp, "mhp": mhp, "res": res, "lv": lv, "fused": r.rew.filter(func(w): return w.k == "fusion").map(func(w): return w.r), "loot": r.rew.filter(func(w): return w.k == "loot").map(func(w): return w.id)})
	if not win and hp <= 0:
		r.over = true
	elif n.k == "boss" and win and (day == GameData.days or mode == "trial"):
		r.victory = true


## ⭐ growth after a won fight: growing items in the pack get one step (up to their max);
## aura growers give the step to every item touching them. One summary line for the night.
func _grow_items(lines: Array) -> void:
	var parts := []
	for it in grid_items():
		var gr: Dictionary = it.def().get("grow", {})
		if gr.is_empty() or it.gc >= int(gr.get("max", 12)):
			continue
		it.gc += 1
		var v := float(gr.get("v", 1.0))
		if gr.get("adj", false):
			for nb in neighbours(it):
				if nb.def().cd > 0:
					nb.grow_main(v)
			parts.append("%s %d/%d" % [it.def().ic, it.gc, int(gr.get("max", 12))])
		else:
			var k := str(gr.get("k", ""))
			var icon := ""
			match k:
				"dmg": it.pd += v
				"shield": it.gs += v
				"heal": it.gh += v
				"": icon = it.grow_main(v)
				_: it.gst[k] = it.gst.get(k, 0.0) + v
			parts.append("%s %d/%d" % [it.def().ic, it.gc, int(gr.get("max", 12))])
	if not parts.is_empty():
		lines.append("🌱 " + I18n.t("Grew: %s") % ", ".join(parts))


func next_day() -> void:
	# a level-up nobody chose (bots, old saves) takes the first offer so the run never stalls
	while not picks.is_empty():
		pick_level(0)
	if result.over:
		end_state = "over"
		return
	if result.victory:
		end_state = "win"
		return
	# a lost final boss (story) or training boss (trial) is fought again the next morning
	if not ((day == GameData.days or (mode == "trial" and day == TRIAL_DAYS)) and not result.win):
		day += 1
	begin_day()


# ---------------------------------------------------------------- forecasts

static func elem_mult(e: Dictionary, dt: String) -> float:
	if dt != "" and dt == e.imm:
		return RESIST
	if dt != "" and dt == e.weak:
		return 1.5
	return 1.0


## Rough damage / shield per second of the current pack (for drag previews and the stats line).
func pack_rates() -> Vector2:
	var r := arrange_rates()
	return Vector2(r.x, r.y)


## Training-dummy read-out: damage, shield and healing per second over `secs` of a real fight (average
## crits) against a target that never hits back. HP is held at half and the shield emptied every tick, so
## every heal and shield counts in full. Used by the class picker and the balance tools.
func bench_rates(secs := 30.0) -> Dictionary:
	calc()
	sync_hp()
	var e0 := {"n": "Dummy", "fam": "Goblin", "hp": 1.0e7, "dps": 0.0, "items": [], "imm": "", "weak": "", "tier": "", "tr": "", "dmg_mult": 1.0, "cd_mult": 1.0}
	var keep_hz := hz
	hz = {}
	var cs := CombatSim.new(self, {"k": "preview", "e": e0}, true)
	hz = keep_hz
	var half := cs.mhp * 0.5
	var healed := 0.0
	var shielded := 0.0
	for _t in roundi(secs * 10.0):
		cs.php = half
		cs.shield = 0.0
		cs.step()
		healed += maxf(0.0, cs.php - half)
		shielded += cs.shield
		if cs.done:
			break
	return {"dps": (1.0e7 - cs.ehp) / secs, "sps": shielded / secs, "hps": healed / secs, "hp": mhp}


## Fight forecast: runs the real combat once with average crits (no dice).
func forecast(e0: Dictionary) -> Dictionary:
	calc()
	sync_hp()
	var cs := CombatSim.new(self, {"k": "preview", "e": e0}, true)
	cs.skip_to_end()
	var taken := maxf(0.0, hp - cs.php)
	var T := cs.tk / 10.0
	var tag := ["Deadly", Color("#e5484d")]
	if cs.won:
		var ratio := taken / maxf(1.0, hp)
		if ratio < 0.5:
			tag = ["Safe", Color("#3ec46d")]
		else:
			tag = ["Risky", Color("#f59e0b")]
	return {"T": T, "taken": taken, "tag": tag[0], "color": tag[1], "won": cs.won}


## Preview for placing `h` with anchor (x, y): fit, damage/shield delta, link and buffed items.
func preview(h: PItem, x: int, y: int) -> Dictionary:
	var ok := fits(h, x, y)
	var d := Vector2.ZERO
	var lk := false
	var bf := {}
	if ok:
		var prev_loc := h.loc
		var px := h.x
		var py := h.y
		var before := pack_rates()
		h.loc = "grid"
		h.x = x
		h.y = y
		var after := pack_rates()
		lk = links().any(func(l): return l.a == h or l.b == h)
		if not h.def().adj.is_empty():
			for t in neighbours(h):
				for b in h.def().adj:
					if t.def().tags.has(b.tag):
						bf[t.uid] = true
		h.loc = prev_loc
		h.x = px
		h.y = py
		d = after - before
		calc()
	return {"ok": ok, "d": d, "lk": lk, "bf": bf}


# ---------------------------------------------------------------- auto-arrange
# The 🪄 button: plans the best pack it can find from the pack AND storage (it may swap a weaker pack
# item out to storage), always lets recipe pairs touch so they fuse tonight, and is shown as a preview
# first (plan_arrange), then applied (apply_arrange). Never loses an item and never offers a weaker pack.

const ARR_LINK := 30.0     # a Golden Link counts like this much damage/s: pairs always end up touching
const ARR_MW := 6.0        # each touch between two pieces of the same Masterwork
const ARR_PULL := 8        # storage items tried (best tiers first), keeps the button quick


## Damage/s, shield/s and heal/s of the pack (average crits).
func arrange_rates() -> Vector3:
	var out := Vector3.ZERO
	for i in calc():
		if i.def().cd <= 0:
			continue
		var f := eff(i)
		out.x += (f.dmg * (1.0 + f.crit * (f.critx - 1.0)) + f.st.get("burn", 0.0) * 3.0 + f.st.get("poison", 0.0) * 3.0) / f.cd
		out.y += f.shield / f.cd
		out.z += f.heal / f.cd
	return out


## How good the pack is: damage/s + 0.7 x shield/s + 0.6 x heal/s, plus a lot per Golden Link.
func arrange_score() -> float:
	var r := arrange_rates()
	var n := 0
	for l in links():
		if not off.has(l.key):
			n += 1
	return r.x + 0.7 * r.y + 0.6 * r.z + ARR_LINK * n


## The best layout found, without changing anything. Empty when the pack is already the best it can find.
## {"moves": [[item, loc, x, y, rot]...], "before"/"after": Vector3 rates, "in"/"out": item ids moved
## from/to storage, "combos": what touches what in the new layout (see arrange_combos)}
func plan_arrange() -> Dictionary:
	var all := items.filter(func(i): return i.loc == "grid" or i.loc == "storage")
	var old := _arr_snap(all)
	var pack := grid_items()
	if pack.is_empty() and storage_items().is_empty():
		return {}
	var r0 := arrange_rates()
	var best_score := arrange_score()
	var best: Array = []
	# two placing orders for the pack's own items: recipe pieces and big shapes first, or best tiers first
	var orders := [
		func(a: PItem, b: PItem) -> bool: return _arr_key(a, true) > _arr_key(b, true),
		func(a: PItem, b: PItem) -> bool: return _arr_key(a, false) > _arr_key(b, false),
	]
	for order in orders:
		_arr_load(old)
		for it in pack:
			it.loc = "held"
		var todo := pack.duplicate()
		todo.sort_custom(order)
		var ok := true
		for it in todo:
			var s := _arrange_spot(it)
			if s.is_empty():
				ok = false
				break
			_arr_put(it, s)
		if not ok:
			continue
		_arr_pull()
		var sc := arrange_score()
		if sc > best_score + 0.05:
			best_score = sc
			best = _arr_snap(all)
	var plan := {}
	if not best.is_empty():
		_arr_load(best)
		var ins := []
		var outs := []
		for i in old.size():
			if old[i][1] == "storage" and best[i][1] == "grid":
				ins.append(old[i][0].id)
			elif old[i][1] == "grid" and best[i][1] == "storage":
				outs.append(old[i][0].id)
		for id in ins.duplicate():
			if outs.has(id):   # two copies traded places: not worth listing
				ins.erase(id)
				outs.erase(id)
		plan = {"moves": best, "undo": old, "before": r0, "after": arrange_rates(), "in": ins, "out": outs, "combos": arrange_combos()}
	_arr_load(old)
	return plan


## Puts a planned layout (plan.moves) or the old one (plan.undo) in place (🪄 in runs, ↩️ undo, tests).
func apply_arrange(snap: Array) -> void:
	_arr_load(snap)


## What works together in the current layout: Golden Links (fuse tonight) and touching buffs.
## [{"k": "link", "ids": [a, b(, c)], "r": result id, "mw": bool}, {"k": "buff", "id": source, "to": [ids], "bf": buff}]
func arrange_combos() -> Array:
	var out := []
	for l in links():
		if off.has(l.key):
			continue   # toggled off: it will not fuse tonight
		var ids := [l.a.id, l.b.id]
		if l.get("c") != null:
			ids.append(l.c.id)
		out.append({"k": "link", "ids": ids, "r": l.r, "mw": l.get("mw", false), "evo": l.get("evo", false)})
	var g := grid_items()
	for it in g:
		var d: Dictionary = it.def()
		for bf in d.adj:
			var to := []
			for t in g:
				if t != it and adj(it, t) and t.def().tags.has(bf.tag):
					to.append(t.id)
			if not to.is_empty():
				out.append({"k": "buff", "id": it.id, "to": to, "bf": bf})
	return out


func _arr_snap(all: Array) -> Array:
	return all.map(func(i): return [i, i.loc, i.x, i.y, i.rot])


func _arr_load(snap: Array) -> void:
	for e in snap:
		e[0].loc = "held"
	for e in snap:
		var it: PItem = e[0]
		it.loc = e[1]
		it.x = e[2]
		it.y = e[3]
		it.rot = e[4]
	calc()


func _arr_put(it: PItem, s: Dictionary) -> void:
	it.loc = "grid"
	it.x = s.x
	it.y = s.y
	it.rot = s.rot


## Placing order: recipe pieces first (when `pairs`), then size or tier.
func _arr_key(it: PItem, pairs: bool) -> int:
	var k := 0
	if pairs:
		k += 1000 if recipe_partner_owned(it.id, true) else 0
		return k + it.cells().size() * 10 + it.def().tier
	return it.def().tier * 10 + it.cells().size()


## Items the planner never takes out of the pack: their worth isn't in damage/shield/heal numbers
## (relics, specials, ⭐ growers, charge/haste/ramp items, treasure).
func _arr_keep(it: PItem) -> bool:
	var d: Dictionary = it.def()
	var on: Dictionary = d.on
	if d.cd <= 0 and d.adj.is_empty() and d.all.is_empty():
		return true   # potions, gold makers, Max HP / regen passives
	return d.relic or d.sp != "" or not d.grow.is_empty() or on.charge > 0 or not on.haste.is_empty() or on.ramp > 0 or d.tags.has("Treasure")


## Storage into the pack: into free room when it helps, else in place of a weaker pack item.
func _arr_pull() -> void:
	var cands := storage_items()
	cands.sort_custom(func(a: PItem, b: PItem) -> bool: return _arr_key(a, true) > _arr_key(b, true))
	var linked := {}
	for l in links():
		for p in [l.a, l.b, l.get("c")]:
			if p != null:
				linked[p] = true
	var queue := cands.slice(0, ARR_PULL)
	var swapped := []
	for s in queue:
		var base := arrange_score()
		s.loc = "held"
		var spot := _arrange_spot(s)
		if not spot.is_empty():
			_arr_put(s, spot)
			if arrange_score() > base + 0.3:
				_arr_mark_links(linked)
				continue
			s.loc = "held"
		# swap: the pack item whose place it takes for the biggest gain
		var best_v := base + 0.5
		var best_sw: Array = []
		for p in grid_items():
			if _arr_keep(p) or linked.has(p) or p.def().tier > s.def().tier:
				continue
			p.loc = "storage"
			var sp2 := _arrange_spot(s)
			if not sp2.is_empty():
				_arr_put(s, sp2)
				var v := arrange_score()
				if v > best_v:
					best_v = v
					best_sw = [p, sp2]
				s.loc = "held"
			p.loc = "grid"
		if best_sw.is_empty():
			s.loc = "storage"
		else:
			best_sw[0].loc = "storage"
			_arr_put(s, best_sw[1])
			swapped.append(best_sw[0])
			_arr_mark_links(linked)
		calc()
	# a swapped-out item may still fit somewhere else
	for p in swapped:
		var base := arrange_score()
		p.loc = "held"
		var spot := _arrange_spot(p)
		if not spot.is_empty():
			_arr_put(p, spot)
			if arrange_score() > base + 0.3:
				continue
		p.loc = "storage"
		calc()


func _arr_mark_links(linked: Dictionary) -> void:
	for l in links():
		for p in [l.a, l.b, l.get("c")]:
			if p != null:
				linked[p] = true


## Best free spot for a held item: the most damage + shield + heal it adds there, plus a lot for a
## Golden Link it completes and a bonus for touching another piece of the same Masterwork.
func _arrange_spot(it: PItem) -> Dictionary:
	var best := {}
	var b0 := arrange_rates()
	var base := b0.x + 0.7 * b0.y + 0.6 * b0.z
	var partner := recipe_partner_owned(it.id, true)
	var mw_parts := {}
	for rc in GameData.recipes:
		if str(rc.get("c", "")) != "" and recipe_ok(rc) and [rc.a, rc.b, rc.c].has(it.id):
			for q in [rc.a, rc.b, rc.c]:
				if q != it.id:
					mw_parts[q] = true
	var keep_rot := it.rot
	var seen_shapes := {}
	var lone_g := {}   # rotation -> gain at a spot that touches nothing
	for rot in 4:
		var key := str(GameData.shape(it.id, rot).c)
		if seen_shapes.has(key):
			continue
		seen_shapes[key] = true
		it.rot = rot
		for y in GameData.H:
			for x in GameData.W:
				if not fits(it, x, y):
					continue
				it.loc = "grid"
				it.x = x
				it.y = y
				var lone := neighbours(it).is_empty()
				var g: float
				if lone and lone_g.has(rot):
					g = lone_g[rot]
				else:
					var r := arrange_rates()
					g = r.x + 0.7 * r.y + 0.6 * r.z - base
					if lone:
						lone_g[rot] = g
				if partner and links().any(func(l): return l.a == it or l.b == it or l.get("c") == it):
					g += ARR_LINK
				if not mw_parts.is_empty():
					for nb in neighbours(it):
						if mw_parts.has(nb.id):
							g += ARR_MW
				it.loc = "held"
				if best.is_empty() or g > best.g:
					best = {"x": x, "y": y, "rot": rot, "g": g}
	it.rot = keep_rot
	calc()
	return best
