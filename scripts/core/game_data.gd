class_name GameData
extends RefCounted
## Static game content loaded from res://data/game_data.json.
## Items, recipes, heroes, companions, bosses, modifiers and sets all live there,
## so content can be balanced without touching code.

const DATA_PATH := "res://data/game_data.json"
const ELEMENTS := ["Fire", "Ice", "Physical", "Arcane", "Nature"]
const FOE_NAMES := ["Cave Rat", "Goblin", "Bandit", "Slime", "Skeleton"]

static var loaded := false
static var items := {}
static var recipes: Array = []          # [ingredient_a, ingredient_b, result]
static var classes := {}
static var class_keys: Array = []
static var pets := {}
static var bosses: Array = []
static var mods: Array = []
static var sets: Array = []
static var traits := {}
static var hazards: Array = []
static var rarity_table: Array = []
static var tier_names: Array = []
static var tier_colors: Array = []
static var atk_curve: Array = []
static var foe_icons := {}
static var elem_colors := {}
static var elem_icons := {}
static var days := 15
static var base_hp := 60.0
static var W := 9
static var H := 7
static var _shape_cache := {}


static func ensure_loaded() -> void:
	if loaded:
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	assert(f != null, "Missing " + DATA_PATH)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	for k in d.items:
		items[k] = _norm_item(d.items[k])
	for r in d.recipes:
		recipes.append([str(r[0]), str(r[1]), str(r[2])])
	for k in d.classes:
		var c: Dictionary = d.classes[k]
		var bag: Dictionary = c.bag
		classes[k] = {
			"n": c.n, "ic": c.ic, "d": c.d,
			"st": [str(c.st[0]), int(c.st[1]), int(c.st[2])],
			"bag": {
				"t": _cells(bag.t), "tag": bag.tag, "label": bag.label,
				"cd": float(bag.get("cd", 1.0)), "dmg": float(bag.get("dmg", 1.0)), "blk": float(bag.get("blk", 1.0)),
			},
			"pets": c.pets,
		}
		class_keys.append(k)
	for k in d.pets:
		var p: Dictionary = d.pets[k]
		pets[k] = {"ic": p.ic, "n": p.n, "d": p.d, "k": p.k, "v": float(p.v), "cd": float(p.get("cd", 0.0)), "dt": str(p.get("dt", ""))}
	for b in d.bosses:
		bosses.append({"d": int(b.d), "n": b.n, "hp": float(b.hp), "atk": float(b.atk), "cd": float(b.cd), "imm": b.imm, "weak": b.weak, "tier": "boss", "tr": ""})
	mods = d.mods
	for s in d.sets:
		var each := {}
		for k in s.each:
			each[k] = float(s.each[k])
		sets.append({"id": s.id, "n": s.n, "parts": s.parts, "txt": s.txt, "hp": float(s.get("hp", 0.0)), "rg": float(s.get("rg", 0.0)), "each": each})
	traits = d.traits
	for h in d.hazards:
		hazards.append({"id": h.id, "ic": h.ic, "n": h.n, "d": h.d, "hp": float(h.get("hp", 1.0)), "cd": float(h.get("cd", 1.0)), "atk": float(h.get("atk", 1.0))})
	for row in d.rarity_table:
		rarity_table.append(row.map(func(v): return float(v)))
	tier_names = d.tier_names
	for c in d.tier_colors:
		tier_colors.append(Color(c))
	atk_curve = d.atk_curve
	foe_icons = d.foe_icons
	for k in d.elem_colors:
		elem_colors[k] = Color(d.elem_colors[k])
	elem_icons = d.elem_icons
	days = int(d.days)
	base_hp = float(d.base_hp)
	W = int(d.grid_w)
	H = int(d.grid_h)
	loaded = true


static func _cells(arr) -> Array:
	var out := []
	for p in arr:
		out.append(Vector2i(int(p[0]), int(p[1])))
	return out


static func _norm_item(src: Dictionary) -> Dictionary:
	var it := {
		"n": src.n, "ic": src.ic, "tier": int(src.tier), "cost": int(src.cost),
		"shop": src.has("s"), "c": _cells(src.c), "tags": src.tags, "type": src.type,
		"dt": str(src.get("dt", "")), "dmg": float(src.get("dmg", 0.0)), "cd": float(src.get("cd", 0.0)),
		"blk": float(src.get("blk", 0.0)), "heal": float(src.get("heal", 0.0)), "hp": float(src.get("hp", 0.0)),
		"rg": float(src.get("rg", 0.0)), "ls": float(src.get("ls", 0.0)), "cl": str(src.get("cl", "")),
		"fx": {}, "st": [],
	}
	var fx: Dictionary = src.get("fx", {})
	for k in fx:
		if k == "haste":
			it.fx[k] = [float(fx[k][0]), float(fx[k][1])]
		else:
			it.fx[k] = float(fx[k])
	for s in src.get("st", []):
		it.st.append({"p": Vector2i(int(s[0]), int(s[1])), "tag": s[2], "key": s[3], "val": float(s[4])})
	return it


## Item shape after `rot` quarter turns clockwise, normalised so the top-left cell is (0,0).
## Returns {"c": Array[Vector2i] occupied cells, "s": Array of star slots {p, tag, key, val}}.
static func shape(id: String, rot: int) -> Dictionary:
	var key := id + ":" + str(rot)
	if _shape_cache.has(key):
		return _shape_cache[key]
	var d: Dictionary = items[id]
	var c: Array = d.c.duplicate()
	var s: Array = []
	for st in d.st:
		s.append(st.duplicate())
	for _r in rot:
		c = c.map(func(p): return Vector2i(-p.y, p.x))
		for st in s:
			st.p = Vector2i(-st.p.y, st.p.x)
	var mx := 999
	var my := 999
	for p in c:
		mx = mini(mx, p.x)
		my = mini(my, p.y)
	var off := Vector2i(mx, my)
	c = c.map(func(p): return p - off)
	for st in s:
		st.p -= off
	var res := {"c": c, "s": s}
	_shape_cache[key] = res
	return res


## The cell of a shape that sits under the pointer when dragging (the "middle" cell).
static func mid_cell(id: String, rot: int) -> Vector2i:
	var cs: Array = shape(id, rot).c
	return cs[int((cs.size() - 1) / 2)]


static func tier_color(id: String) -> Color:
	return tier_colors[items[id].tier]


static func stat_text(tag: String, key: String, v: float) -> String:
	var n := _num(v)
	match key:
		"dmg": return tag + " +" + n + " dmg"
		"blk": return tag + " +" + n + " block"
		"cdr": return tag + " −" + n + "s cooldown"
		"burn": return tag + " +" + n + " 🔥Burn"
		"pois": return tag + " +" + n + " ☠️Poison"
		"chill": return tag + " +" + n + "s ❄️Chill"
	return tag


static func fx_text(f: Dictionary) -> String:
	var parts := []
	if f.has("burn"): parts.append("🔥Burn " + _num(f.burn))
	if f.has("pois"): parts.append("☠️Poison " + _num(f.pois))
	if f.has("chill"): parts.append("❄️Chill " + _num(f.chill) + "s")
	if f.has("frz"): parts.append("🧊Freeze " + _num(f.frz) + "s")
	if f.has("haste"): parts.append("⚡Haste +" + str(roundi(f.haste[0] * 100)) + "% for " + _num(f.haste[1]) + "s")
	return " · ".join(parts)


static func fx_icons(f: Dictionary) -> String:
	var parts := []
	if f.has("burn"): parts.append("🔥" + _num(f.burn))
	if f.has("pois"): parts.append("☠️" + _num(f.pois))
	if f.has("chill"): parts.append("❄️")
	if f.has("frz"): parts.append("🧊")
	if f.has("haste"): parts.append("⚡")
	return " ".join(parts)


static func describe(id: String) -> String:
	var d: Dictionary = items[id]
	var s := ""
	match d.type:
		"atk": s = "%s %s dmg · %ss" % [d.dt, _num(d.dmg), _num(d.cd)]
		"def": s = "+%s block · %ss" % [_num(d.blk), _num(d.cd)]
		"heal": s = "Heals %s below 50%% HP, used up" % _num(d.heal)
		_: s = "Passive"
	if d.st.size() > 0:
		s += " · ✦ " + stat_text(d.st[0].tag, d.st[0].key, d.st[0].val)
	if not d.fx.is_empty():
		s += " · " + fx_text(d.fx)
	return s


static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return str(snappedf(v, 0.01))


static func foe_icon(name: String) -> String:
	var base := name.replace("Elite ", "").replace("Ambusher ", "")
	return foe_icons.get(base, "👾")
