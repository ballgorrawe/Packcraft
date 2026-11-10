class_name RunState
extends RefCounted
## All rules for one run: day loop, shop, backpack grid, adjacency buffs, evolutions and recipes,
## class paths, nodes and night resolution. Pure logic, no UI, so it can be tested headless.

const RESIST := 0.2          # damage multiplier when the foe resists that element (80% less)
const MAX_HEARTS := 3
const COMBAT_DROP := 0.25       # chance a normal fight drops an item
const LOOT_PARTNER_BIAS := 0.35 # chance loot is a recipe partner of something you own
const ELITE_FROM_DAY := 2       # no Elite nodes on day 1
const SAVE_VERSION := 2

var cls := ""
var path := ""                  # chosen class path id, "" until path day
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
var msg := ""
var seen := {}                  # item ids the player has owned (unlocks recipe book entries)


func _init(c: String) -> void:
	GameData.ensure_loaded()
	cls = c
	mhp = GameData.base_hp
	hp = mhp
	mod = GameData.mods.pick_random()
	for t in cls_def().bag:
		tiles[t] = true
		start[t] = true
	for st in cls_def().st:
		items.append(make_item(st[0], "grid", st[1], st[2], true))
	begin_day()


func cls_def() -> Dictionary:
	return GameData.classes[cls]


func path_def() -> Dictionary:
	return GameData.paths.get(path, {})


## True on the path day until the player has picked one of the two class paths.
func needs_path() -> bool:
	return path == "" and day >= GameData.path_day and phase == "morning"


func choose_path(id: String) -> void:
	if path != "" or not cls_def().paths.has(id):
		return
	path = id
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


func in_class_pool(id: String) -> bool:
	var c: String = GameData.items[id].cl
	return c == "" or c == cls


## Specials ("sp") active in the pack right now.
func has_sp(sp: String) -> bool:
	return grid_items().any(func(i): return i.def().sp == sp)


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
	var m := GameData.base_hp
	for i in grid_items():
		m += i.def().pass.hp
	return m


func regen() -> float:
	var r := 0.0
	for i in grid_items():
		r += i.def().pass.regen
	return r


func income() -> int:
	var g := 0
	for i in grid_items():
		g += i.def().pass.income
	return g


func sync_hp() -> void:
	var m := max_hp()
	if mhp > 0 and not is_equal_approx(mhp, m):
		hp = hp * m / mhp
	mhp = m
	hp = minf(hp, m)


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
	var cd: float = d.cd * (1.0 - minf(0.6, i.b.cdr)) * (1.0 - i.pc)
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
	return {
		"dmg": snappedf(dmg, 0.1), "cd": maxf(0.3, cd), "crit": minf(1.0, on.crit + i.b.crit), "critx": on.critx,
		"shield": on.shield + (i.b.shield if on.shield > 0 else 0.0), "heal": on.heal + (i.b.heal if on.heal > 0 else 0.0),
		"st": st, "charge": on.charge, "haste": on.haste, "ramp": on.ramp, "el": on.el,
	}


func recipe_ok(r: Dictionary) -> bool:
	return r.path == "" or r.path == path


## Golden Links: recipe or evolution pairs that touch and will fuse at night.
func links() -> Array:
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
				if adj(a, b):
					used[a.uid] = true
					used[b.uid] = true
					out.append({"a": a, "b": b, "r": r.r, "evo": r.evo, "key": "%d-%d" % [mini(a.uid, b.uid), maxi(a.uid, b.uid)]})
	return out


## Where a fused item lands: nearest free spot to ingredient A (any rotation), or null if none.
func fuse_place(l: Dictionary):
	var o := {}
	for i in grid_items():
		if i == l.a or i == l.b:
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
	for r in GameData.recipes:
		if not recipe_ok(r):
			continue
		if r.evo:
			if r.a == id and count_owned(id) >= (2 if owned_self else 1):
				return true
		elif (r.a == id and owns(r.b)) or (r.b == id and owns(r.a)):
			return true
	return false


## Recipes relevant to an item (as ingredient or result), for the inspector.
func recipes_for(id: String) -> Array:
	return GameData.recipes.filter(func(r): return (r.a == id or r.b == id or r.r == id) and (r.path == "" or r.path == path or path == ""))


# ---------------------------------------------------------------- economy

func rank() -> int:
	return 0 if day <= 3 else 1 if day <= 7 else 2 if day <= 11 else 3 if day <= 15 else 4


func roll_item() -> String:
	return roll_tiered(rank())


## Rolls a shop-pool item using the rarity row `rk` (0..4), never below `min_tier`.
## With `partner_bias`, that chance picks an item that fuses with something you own (same tier).
func roll_tiered(rk: int, min_tier := 0, partner_bias := 0.0) -> String:
	var w: Array = GameData.rarity_table[clampi(rk, 0, 4)]
	var r := randf() * 100.0
	var t := 0
	while t < 4:
		r -= w[t]
		if r < 0:
			break
		t += 1
	t = maxi(t, min_tier)
	while t >= 0:
		var pool := []
		for k in GameData.items:
			var d: Dictionary = GameData.items[k]
			if d.shop and d.tier == t and in_class_pool(k):
				pool.append(k)
		if pool.size() > 0:
			if partner_bias > 0.0 and randf() < partner_bias:
				var pp := pool.filter(func(k): return recipe_partner_owned(k))
				if pp.size() > 0:
					return pp.pick_random()
			return pool.pick_random()
		t -= 1
	return "iron_sword"


## Item reward for winning a fight node, or "" for none. Tier follows the day, not a flat pool,
## so an early Elite gives a Rare, not a Legendary.
func loot_for(k: String) -> String:
	match k:
		"elite", "ambush":
			return roll_tiered(rank() + 1, 1, LOOT_PARTNER_BIAS)
		"boss":
			return roll_tiered(rank() + 1, 2, LOOT_PARTNER_BIAS)
		"combat":
			if randf() < COMBAT_DROP:
				return roll_tiered(rank(), 0, LOOT_PARTNER_BIAS)
	return ""


func bag_price(n: int) -> int:
	return roundi(n * 1.5) + mini(2, int(bags / 3)) * int(n / 2)


func fill_shop() -> void:
	shop = shop.filter(func(e): return not e.has("bag"))
	while shop.size() < 5:
		var id := roll_item()
		shop.append({"id": id, "price": GameData.items[id].cost})
	shop.append({"bag": true, "n": 3 if day >= 8 else 2, "price": bag_price(2)})
	shop.append({"bag": true, "n": 4, "price": bag_price(4)})


func reroll_cost() -> int:
	return 1 + int(rr / 2) + (1 if mod.id == "guild" else 0)


func reroll() -> bool:
	var c := reroll_cost()
	if gold < c:
		msg = I18n.t("Not enough gold.")
		return false
	gold -= c
	rr += 1
	shop = shop.filter(func(e): return e.get("lock", false))
	fill_shop()
	return true


func toggle_lock(i: int) -> void:
	shop[i].lock = not shop[i].get("lock", false)


func buy_bag(i: int) -> bool:
	var e: Dictionary = shop[i]
	if gold < e.price:
		msg = I18n.t("Not enough gold.")
		return false
	gold -= e.price
	expand += e.n
	bags += 1
	for x in shop:
		if x.has("bag"):
			x.price = bag_price(2 if x.n == 3 else x.n)
	msg = I18n.t("Bag bought: tap the glowing tiles next to your pack to unlock %d tiles.") % e.n
	return true


## Buys a shop item and returns it with loc "held"; the caller places or stores it.
func buy_item(i: int) -> PItem:
	var e: Dictionary = shop[i]
	if gold < e.price:
		msg = I18n.t("Not enough gold.")
		return null
	gold -= e.price
	shop.remove_at(i)
	var it := make_item(e.id, "held")
	items.append(it)
	return it


func sell_price(it: PItem) -> int:
	return ceili(it.def().cost / 2.0)


func sell(it: PItem) -> bool:
	if it.starter:
		return false
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


func foe_base(elite: bool) -> Dictionary:
	var hp0 := enemy_hp(day)
	var atk := enemy_atk(day)
	var e := {"n": GameData.FOE_NAMES.pick_random(), "hp": float(hp0), "atk": snappedf(atk, 0.1), "cd": 1.7, "imm": "", "weak": "", "tier": "", "tr": ""}
	if elite:
		e.n = "Elite " + e.n
		e.hp = float(roundi(hp0 * 1.5))
		e.atk = snappedf(atk * 1.3, 0.1)
		if randf() < 0.5:
			e.imm = GameData.ELEMENTS.pick_random()
	return e


func foe(elite: bool) -> Dictionary:
	var e := foe_base(elite)
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
		e.atk = snappedf(e.atk * 0.7, 0.1)
	if e.tier == "tough":
		e.hp = float(roundi(e.hp * 1.3))
		e.atk = snappedf(e.atk * 1.25, 0.1)
	if e.tier == "elite" or e.tier == "tough" or (e.tier == "normal" and day >= 4 and randf() < 0.2):
		e.tr = GameData.traits.keys().pick_random()
		match e.tr:
			"swift":
				e.cd = 1.0
				e.atk = snappedf(e.atk * 0.6, 0.1)
			"brute":
				e.hp = float(roundi(e.hp * 1.4))
				e.atk = snappedf(e.atk * 1.8, 0.1)
				e.cd = 2.4
			"regen":
				e.hp = float(roundi(e.hp * 1.1))
	return e


## Applies today's hazard to an enemy (returns a copy).
func with_hazard(e: Dictionary) -> Dictionary:
	var o := e.duplicate()
	if hz.is_empty():
		return o
	o.hp = float(roundi(e.hp * hz.hp))
	o.atk = snappedf(e.atk * hz.atk, 0.1)
	o.cd = snappedf(e.cd * hz.cd, 0.01)
	return o


func boss_on(d: int):
	for b in GameData.bosses:
		if b.d == d:
			return b
	return null


# ---------------------------------------------------------------- day flow

func begin_day() -> void:
	if day > 1:
		gold += 5 + int(day / 2) + income()
	phase = "morning"
	rr = 0
	msg = ""
	hz = {}
	if day >= 3 and boss_on(day) == null and randf() < 0.4:
		hz = GameData.hazards.pick_random()
	shop = shop.filter(func(e): return e.get("lock", false))
	fill_shop()
	if randf() < 0.25:
		var c := shop.filter(func(e): return not e.has("bag") and not e.get("lock", false))
		if c.size() > 0:
			var e: Dictionary = c.pick_random()
			e.price = ceili(e.price / 2.0)
			e.sale = true
	var b = boss_on(day)
	if b != null:
		nodes = [{"k": "boss", "e": b.duplicate()}]
	else:
		var am := foe(true)
		am.n = "Ambusher " + am.n.replace("Elite ", "")
		am.hp = float(roundi(am.hp * 1.15))
		var pool := [{"k": "forge"}, {"k": "camp"}, {"k": "combat", "e": foe(false)}]
		if day >= ELITE_FROM_DAY:
			pool.append({"k": "elite", "e": foe(true)})
		if day >= 3:
			pool.append({"k": "ambush", "e": am})
		if hp > 25 and day >= 3:
			pool.append({"k": "shrine"})
		if day >= 2:
			pool.append({"k": "tailor"})
		pool.shuffle()
		nodes = [{"k": "combat", "e": foe(false)}]
		nodes.append_array(pool.slice(0, 1 + randi() % 2))
		if hp < mhp * 0.4 and not nodes.any(func(n): return n.k == "camp"):
			nodes[nodes.size() - 1] = {"k": "camp"}


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
	if n.has("e"):
		calc()
		sync_hp()
		phase = "evening"
		return CombatSim.new(self, n)
	go_night(n, true, null)
	return null


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
		its.append({"uid": i.uid, "id": i.id, "loc": loc, "x": i.x, "y": i.y, "rot": i.rot, "starter": i.starter, "pd": i.pd, "pc": i.pc})
	var res_d := {}
	if not result.is_empty():
		res_d = {"n": result.n, "win": result.win, "lines": result.lines, "over": result.over, "victory": result.victory}
	return {
		"v": SAVE_VERSION, "cls": cls, "path": path, "day": day, "gold": gold, "res": res, "hp": hp, "mhp": mhp,
		"phase": phase, "items": its, "uid_ctr": uid_ctr,
		"tiles": tiles.keys().map(_v2a), "start": start.keys().map(_v2a),
		"shop": shop, "rr": rr, "expand": expand, "bags": bags, "mod": mod.id, "hz": hz.get("id", ""),
		"off": off.keys(), "nodes": nodes, "cur_node": cur_node, "result": res_d, "end_state": end_state,
		"msg": msg, "seen": seen.keys(),
	}


static func from_dict(d: Dictionary) -> RunState:
	GameData.ensure_loaded()
	if int(d.get("v", 0)) != SAVE_VERSION or not GameData.classes.has(d.get("cls", "")):
		return null
	var r := RunState.new(d.cls)
	r.path = str(d.get("path", ""))
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
		it.pc = float(s.pc)
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
		if n.has("e") and n.e.has("d"):
			n.e.d = int(n.e.d)   # JSON turns ints into floats
	r.cur_node = int(d.get("cur_node", -1))
	r.result = {}
	if not d.result.is_empty():
		r.result = {"n": d.result.n, "win": d.result.win, "lines": d.result.lines, "over": d.result.over, "victory": d.result.victory, "cs": null}
		if r.result.n.has("e") and r.result.n.e.has("d"):
			r.result.n.e.d = int(r.result.n.e.d)
	elif r.phase == "night":
		r.phase = "morning"
	r.end_state = d.end_state
	r.msg = d.msg
	r.seen = {}
	for k in d.seen:
		r.seen[k] = true
	return r


# ---------------------------------------------------------------- night

func go_night(n: Dictionary, win: bool, cs: CombatSim) -> void:
	phase = "night"
	var r := {"n": n, "win": win, "cs": cs, "lines": [], "over": false, "victory": false}
	result = r
	if cs != null:
		hp = maxf(1.0, roundf(cs.php)) if win else 0.0
		for x in cs.items:
			if x.d.once and x.used:
				items.erase(x.i)
				r.lines.append(I18n.t("🧪 %s was used up.") % I18n.t(x.d.n))
	var ws := grid_items().filter(func(i): return i.def().tags.has("Weapon"))
	match n.k:
		"forge":
			if ws.size() > 0:
				var t: PItem = ws.pick_random()
				t.pd += 3
				r.lines.append(I18n.t("🔨 The forge sharpens %s: +3 damage for the rest of the run.") % I18n.t(t.def().n))
			else:
				r.lines.append(I18n.t("🔨 You had no weapon in the pack to forge."))
		"tailor":
			expand += 3
			r.lines.append(I18n.t("🧵 The tailor sews 3 extra tiles onto your pack. Place them next morning."))
		"shrine":
			var id := roll_tiered(rank() + 1, 2, LOOT_PARTNER_BIAS)
			items.append(make_item(id, "storage"))
			hp = maxf(1.0, hp - 15)
			r.lines.append(I18n.t("🗿 The shrine drains 15 HP and gives you %s %s (in storage).") % [GameData.items[id].ic, I18n.t(GameData.items[id].n)])
		"camp":
			if hp < mhp:
				var h := minf(mhp - hp, roundf(mhp * 0.5))
				hp += h
				r.lines.append(I18n.t("🔥 You rest by the fire and recover %d HP.") % roundi(h))
			else:
				for w in ws:
					w.pc = minf(0.5, w.pc + 0.05)
				r.lines.append(I18n.t("🔥 You are at full HP, so every weapon polishes to 5% faster."))
		_:
			if win:
				var g := (4 + ceili(day / 2.0)) * (2 if n.k == "elite" or n.k == "ambush" else 1) + (10 if n.k == "boss" else 0)
				if mod.id == "guild":
					g = roundi(g * 1.4)
				if has_sp("gold_engine"):
					g += 5
				gold += g
				r.lines.append(I18n.t("🏆 Victory! +%d gold.") % g)
				if n.k == "boss" and res < MAX_HEARTS:
					res += 1
					r.lines.append(I18n.t("❤️ Boss reward: +1 Heart."))
				if n.k == "boss":
					expand += 4
					r.lines.append(I18n.t("🎒 Boss reward: +4 pack tiles."))
				if n.k == "elite" or n.k == "ambush":
					expand += 1
					r.lines.append(I18n.t("🎒 Spoils: +1 pack tile."))
				var id := loot_for(n.k)
				if id != "":
					items.append(make_item(id, "storage"))
					r.lines.append(I18n.t("🎁 Loot added to storage: %s %s (%s)") % [GameData.items[id].ic, I18n.t(GameData.items[id].n), I18n.t(GameData.tier_names[GameData.items[id].tier])])
			else:
				# Losing a fight you picked for its loot pays nothing: hearts keep the run alive, not the reward.
				var c := 0 if n.k == "elite" or n.k == "ambush" else 2 + int(day / 3)
				gold += c
				if res > 0:
					res -= 1
					hp = roundf(mhp * 0.5)
				var how := I18n.t("You spend a Heart and revive at 50% HP, ") if hp > 0 else I18n.t("No Hearts left, ")
				r.lines.append(I18n.t("💔 Defeated! %ssalvaging %d gold.") % [how, c])
	# Night: Golden Links (recipes and evolutions) fuse
	for l in links():
		if off.has(l.key):
			continue
		var pl = fuse_place(l)
		items.erase(l.a)
		items.erase(l.b)
		var f := make_item(l.r, "grid" if pl != null else "storage")
		if pl != null:
			f.x = pl.x
			f.y = pl.y
			f.rot = pl.rot
		f.pd = l.a.pd + l.b.pd
		f.pc = maxf(l.a.pc, l.b.pc)
		f.starter = l.a.starter and l.b.starter
		items.append(f)
		var a: Dictionary = GameData.items[l.a.id]
		var rd: Dictionary = GameData.items[l.r]
		var tail := "" if pl != null else I18n.t(" (sent to storage — no room in pack)")
		if l.evo:
			r.lines.append(I18n.t("✨ Evolution! Two %s %s became %s %s!") % [a.ic, I18n.t(a.n), rd.ic, I18n.t(rd.n)] + tail)
		else:
			r.lines.append(I18n.t("✨ Fusion! %s + %s ➡️ %s %s!") % [a.ic, GameData.items[l.b.id].ic, rd.ic, I18n.t(rd.n)] + tail)
	if not win and hp <= 0:
		r.over = true
	elif n.k == "boss" and win and day == GameData.days:
		r.victory = true


func next_day() -> void:
	if result.over:
		end_state = "over"
		return
	if result.victory:
		end_state = "win"
		return
	if not (day == GameData.days and not result.win):
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
	calc()
	var d := 0.0
	var b := 0.0
	for i in grid_items():
		var t: Dictionary = i.def()
		if t.cd <= 0:
			continue
		var f := eff(i)
		var hit: float = f.dmg * (1.0 + f.crit * (f.critx - 1.0))
		hit += f.st.get("burn", 0.0) * 3.0 + f.st.get("poison", 0.0) * 3.0
		d += hit / f.cd
		b += f.shield / f.cd
	return Vector2(d, b)


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
