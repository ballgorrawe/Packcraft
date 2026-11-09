class_name RunState
extends RefCounted
## All rules for one run: day loop, shop, backpack grid, stars, sets, Golden Link fusion, nodes and night resolution.
## Pure logic, no UI, so it can be tested headless.

const RESIST := 0.2          # damage multiplier when the foe resists that element (80% less)
const MAX_HEARTS := 3
const COMBAT_DROP := 0.25       # chance a normal fight drops an item
const LOOT_PARTNER_BIAS := 0.35 # chance loot is a recipe partner of something you own
const ELITE_FROM_DAY := 2       # no Elite nodes on day 1

var cls := ""
var pet := ""
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
var active_sets: Array = []


func _init(c: String, p: String) -> void:
	GameData.ensure_loaded()
	cls = c
	pet = p
	mhp = GameData.base_hp
	hp = mhp
	mod = GameData.mods.pick_random()
	for t in cls_def().bag.t:
		tiles[t] = true
		start[t] = true
	var st: Array = cls_def().st
	items.append(make_item(st[0], "grid", st[1], st[2], true))
	begin_day()


func cls_def() -> Dictionary:
	return GameData.classes[cls]


func pet_def() -> Dictionary:
	return GameData.pets[pet]


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
	return {"dmg": 0.0, "cdr": 0.0, "blk": 0.0, "burn": 0.0, "pois": 0.0, "chill": 0.0}


func grid_items() -> Array:
	return items.filter(func(i): return i.loc == "grid")


func storage_items() -> Array:
	return items.filter(func(i): return i.loc == "storage")


func owns(id: String) -> bool:
	return items.any(func(i): return i.id == id)


func in_class_pool(id: String) -> bool:
	var c: String = GameData.items[id].cl
	return c == "" or c == cls


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


func anchor_for(it: PItem, cell: Vector2i) -> Vector2i:
	return cell - GameData.mid_cell(it.id, it.rot)


func adj(a: PItem, b: PItem) -> bool:
	var bc := b.cells()
	for p in a.cells():
		for q in bc:
			if absi(p.x - q.x) + absi(p.y - q.y) == 1:
				return true
	return false


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


## Recompute star and set buffs on every grid item.
func calc() -> Array:
	var o := occ()
	var g := grid_items()
	for i in g:
		i.b = _zero_b()
	for i in g:
		for s in GameData.shape(i.id, i.rot).s:
			var t: PItem = o.get(Vector2i(i.x, i.y) + s.p)
			if t != null and t != i and t.def().tags.has(s.tag):
				t.b[s.key] += s.val
	active_sets = act_sets()
	for x in active_sets:
		for i in x.insts:
			for k in x.st.each:
				i.b[k] = i.b.get(k, 0.0) + x.st.each[k]
	return g


func set_inst(st: Dictionary) -> Dictionary:
	var g := grid_items()
	var insts := []
	for id in st.parts:
		var found = null
		for i in g:
			if i.id == id:
				found = i
				break
		insts.append(found)
	if insts.has(null):
		return {"ok": false, "insts": insts.filter(func(v): return v != null)}
	var seen_set := [insts[0]]
	var q := [insts[0]]
	while q.size() > 0:
		var a: PItem = q.pop_back()
		for b in insts:
			if not seen_set.has(b) and adj(a, b):
				seen_set.append(b)
				q.append(b)
	return {"ok": seen_set.size() == insts.size(), "insts": insts}


func act_sets() -> Array:
	var out := []
	for st in GameData.sets:
		var r := set_inst(st)
		if r.ok:
			out.append({"st": st, "insts": r.insts})
	return out


func max_hp() -> float:
	var m := GameData.base_hp
	for i in grid_items():
		m += i.def().hp
	for x in act_sets():
		m += x.st.hp
	return m


func regen() -> float:
	var r := 0.0
	for i in grid_items():
		r += i.def().rg
	for x in act_sets():
		r += x.st.rg
	return r


func sync_hp() -> void:
	var m := max_hp()
	if mhp > 0 and not is_equal_approx(mhp, m):
		hp = hp * m / mhp
	mhp = m
	hp = minf(hp, m)


## Effective numbers for an item after stars, sets, bag passive, pet, modifier and permanent upgrades.
func eff(i: PItem) -> Dictionary:
	var d := i.def()
	var dmg: float = d.dmg + i.b.dmg + i.pd
	var cd: float = d.cd - i.b.cdr
	if mod.id == "frost" and d.dt == "Ice":
		dmg *= 1.3
	if mod.id == "blood":
		dmg *= 1.15
	var bg: Dictionary = cls_def().bag
	var inb := false
	if d.tags.has(bg.tag):
		for c in i.cells():
			if start.has(c):
				inb = true
				break
	if inb:
		cd *= bg.cd
		dmg *= bg.dmg
	cd *= (1.0 - i.pc) * (1.0 - pet_def().v if pet_def().k == "haste" else 1.0)
	if mod.id == "frost":
		cd *= 1.1
	var blk: float = (d.blk + i.b.blk) * (bg.blk if inb else 1.0)
	return {"dmg": snappedf(dmg, 0.1), "cd": maxf(0.4, cd), "blk": snappedf(blk, 0.1)}


func links() -> Array:
	var g := grid_items()
	var out := []
	var used := {}
	for r in GameData.recipes:
		for a in g:
			if a.id != r[0]:
				continue
			for b in g:
				if b.id == r[1] and not used.has(a.uid) and not used.has(b.uid) and adj(a, b):
					used[a.uid] = true
					used[b.uid] = true
					out.append({"a": a, "b": b, "r": r[2], "key": "%d-%d" % [a.uid, b.uid]})
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


func recipe_partner_owned(id: String) -> bool:
	for r in GameData.recipes:
		if (r[0] == id and owns(r[1])) or (r[1] == id and owns(r[0])):
			return true
	return false


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
	return "rusty_dagger"


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
		msg = "Not enough gold."
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
		msg = "Not enough gold."
		return false
	gold -= e.price
	expand += e.n
	bags += 1
	for x in shop:
		if x.has("bag"):
			x.price = bag_price(2 if x.n == 3 else x.n)
	msg = "Bag bought: tap the dark tiles next to your pack to unlock %d tiles." % e.n
	return true


## Buys a shop item and returns it with loc "held"; the caller places or stores it.
func buy_item(i: int) -> PItem:
	var e: Dictionary = shop[i]
	if gold < e.price:
		msg = "Not enough gold."
		return null
	gold -= e.price
	shop.remove_at(i)
	var it := make_item(e.id, "held")
	items.append(it)
	return it


## Moves every item in the pack into the (unlimited) storage box. Returns how many moved.
func clear_pack() -> int:
	var g := grid_items()
	for it in g:
		it.loc = "storage"
	return g.size()


func sell(it: PItem) -> bool:
	if it.starter:
		return false
	gold += ceili(it.def().cost / 2.0)
	items.erase(it)
	return true


# ---------------------------------------------------------------- enemies

func enemy_hp(d: int) -> int:
	var base := 4.0 + 4.6 * d if d <= 5 else 27.0 + 3.5 * (d - 5)
	return roundi(base * minf(6.0, 3.8 + 0.5 * d))


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
	return (3.0 + 0.55 * d + 0.01 * d * d) * m


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
		gold += 5 + int(day / 2)
	if pet_def().k == "gold":
		gold += int(pet_def().v)
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
		msg = "Place the item you are holding first."
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

const SAVE_VERSION := 1


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
		"v": SAVE_VERSION, "cls": cls, "pet": pet, "day": day, "gold": gold, "res": res, "hp": hp, "mhp": mhp,
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
	var r := RunState.new(d.cls, d.pet)
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


func go_night(n: Dictionary, win: bool, cs: CombatSim) -> void:
	phase = "night"
	var r := {"n": n, "win": win, "cs": cs, "lines": [], "over": false, "victory": false}
	result = r
	if cs != null:
		hp = maxf(1.0, roundf(cs.php)) if win else 0.0
		for x in cs.items:
			if x.d.type == "heal" and x.used:
				items.erase(x.i)
				r.lines.append("🧪 %s was used up." % x.d.n)
	var ws := grid_items().filter(func(i): return i.def().tags.has("Weapon"))
	match n.k:
		"forge":
			if ws.size() > 0:
				var t: PItem = ws.pick_random()
				t.pd += 3
				r.lines.append("🔨 The forge sharpens %s: +3 damage for the rest of the run." % t.def().n)
			else:
				r.lines.append("🔨 You had no weapon in the pack to forge.")
		"tailor":
			expand += 3
			r.lines.append("🧵 The tailor sews 3 extra tiles onto your pack. Place them next morning.")
		"shrine":
			var id := roll_tiered(rank() + 1, 2, LOOT_PARTNER_BIAS)
			items.append(make_item(id, "storage"))
			hp = maxf(1.0, hp - 15)
			r.lines.append("🗿 The shrine drains 15 HP and gives you %s %s (in storage)." % [GameData.items[id].ic, GameData.items[id].n])
		"camp":
			if hp < mhp:
				var h := minf(mhp - hp, roundf(mhp * 0.5))
				hp += h
				r.lines.append("🔥 You rest by the fire and recover %d HP." % roundi(h))
			else:
				for w in ws:
					w.pc = minf(0.5, w.pc + 0.05)
				r.lines.append("🔥 You are at full HP, so every weapon polishes to 5% faster.")
		_:
			if win:
				var g := (4 + ceili(day / 2.0)) * (2 if n.k == "elite" or n.k == "ambush" else 1) + (10 if n.k == "boss" else 0)
				if mod.id == "guild":
					g = roundi(g * 1.4)
				gold += g
				r.lines.append("🏆 Victory! +%d gold." % g)
				if n.k == "boss" and res < MAX_HEARTS:
					res += 1
					r.lines.append("❤️ Boss reward: +1 Heart.")
				if n.k == "boss":
					expand += 4
					r.lines.append("🎒 Boss reward: +4 pack tiles.")
				if n.k == "elite" or n.k == "ambush":
					expand += 2
					r.lines.append("🎒 Spoils: +2 pack tiles.")
				var id := loot_for(n.k)
				if id != "":
					items.append(make_item(id, "storage"))
					r.lines.append("🎁 Loot added to storage: %s %s (%s)" % [GameData.items[id].ic, GameData.items[id].n, GameData.tier_names[GameData.items[id].tier]])
			else:
				# Losing a fight you picked for its loot pays nothing: hearts keep the run alive, not the reward.
				var c := 0 if n.k == "elite" or n.k == "ambush" else 2 + int(day / 3)
				gold += c
				if res > 0:
					res -= 1
					hp = roundf(mhp * 0.5)
				r.lines.append("💔 Defeated! %ssalvaging %d gold." % ["You spend a Heart and revive at 50% HP, " if hp > 0 else "No Hearts left, ", c])
	# Night: Golden Link fusion
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
		items.append(f)
		r.lines.append("✨ Fusion! %s + %s ➜ %s %s!%s" % [GameData.items[l.a.id].ic, GameData.items[l.b.id].ic, GameData.items[l.r].ic, GameData.items[l.r].n, "" if pl != null else " (sent to storage — no room in pack)"])
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
	if dt == e.weak:
		return 1.5
	return 1.0


## Rough DPS / block per second of the current pack.
func pack_rates() -> Vector2:
	calc()
	var d := 0.0
	var b := 0.0
	for i in grid_items():
		var t: Dictionary = i.def()
		var f := eff(i)
		if t.type == "atk":
			d += f.dmg / f.cd
		elif t.type == "def":
			b += f.blk / f.cd
	return Vector2(d, b)


## Fight forecast: estimated time to kill, damage taken and a Safe/Risky/Deadly tag.
func forecast(e0: Dictionary) -> Dictionary:
	var e := with_hazard(e0)
	calc()
	var dps := 0.0
	var blk := regen()
	var heal := 0.0
	var rb := 0.0
	var rp := 0.0
	var ch := false
	var hs := 0.0
	for i in grid_items():
		var d: Dictionary = i.def()
		var f := eff(i)
		var q: Dictionary = d.fx
		var m2 := elem_mult(e, d.dt) if d.type == "atk" else 1.0
		rb += (q.get("burn", 0.0) + i.b.burn) / f.cd * m2
		rp += (q.get("pois", 0.0) + i.b.pois) / f.cd * m2
		if q.has("chill") or i.b.chill > 0:
			ch = true
		if q.has("haste"):
			hs += 0.05
		if d.type == "atk":
			dps += maxf(1.0, f.dmg - (3.0 if e.tr == "armored" else 0.0)) / f.cd * elem_mult(e, d.dt)
		elif d.type == "def":
			blk += f.blk / f.cd
		elif d.type == "heal":
			heal += d.heal * (0.5 if mod.id == "blood" else 1.0)
	var p := pet_def()
	if p.k == "dmg":
		dps += p.v / p.cd * elem_mult(e, p.dt)
	elif p.k == "blk":
		blk += p.v / p.cd
	dps += minf(30.0, 2.0 * rb) * (RESIST if e.imm == "Fire" else 1.0)
	dps += minf(20.0, 0.25 * rp * (e.hp / maxf(dps, 1.0))) * (RESIST if e.imm == "Nature" else 1.0)
	if e.tr == "regen":
		dps -= e.hp * 0.015
	dps = maxf(0.0, dps * (1.0 + hs))
	var T: float = e.hp / dps if dps > 0 else 99.0
	var inc: float = e.atk / e.cd * (0.8 if ch else 1.0)
	var taken: float = maxf(inc * 0.25, inc - blk) * T
	var ratio: float = taken / (hp + heal)
	var tag := ["Deadly", Color("#e5484d")]
	if T < 40:
		if ratio < 0.5:
			tag = ["Safe", Color("#3ec46d")]
		elif ratio < 1.0:
			tag = ["Risky", Color("#f59e0b")]
	return {"T": T, "taken": taken, "tag": tag[0], "color": tag[1]}


## Preview for placing `h` with anchor (x, y): fit, DPS/block delta, link, star cells and buffed items.
func preview(h: PItem, x: int, y: int) -> Dictionary:
	var sh := GameData.shape(h.id, h.rot)
	var o := occ()
	var ok := fits(h, x, y)
	var sc := {}
	var bf := {}
	for s in sh.s:
		var k: Vector2i = Vector2i(x, y) + s.p
		sc[k] = true
		var t: PItem = o.get(k)
		if t != null and t.def().tags.has(s.tag):
			bf[t.uid] = true
	var d := Vector2.ZERO
	var lk := false
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
		h.loc = prev_loc
		h.x = px
		h.y = py
		d = after - before
		calc()
	return {"ok": ok, "d": d, "lk": lk, "sc": sc, "bf": bf}
