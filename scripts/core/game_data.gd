class_name GameData
extends RefCounted
## Static game content loaded from res://data/game_data.json.
## Items, recipes, classes, paths, statuses, bosses and modifiers all live there,
## so content can be balanced (or new statuses added) without touching code.

const DATA_PATH := "res://data/game_data.json"
const ELEMENTS := ["Fire", "Nature", "Physical", "Shock"]
const FOE_NAMES := ["Cave Rat", "Goblin", "Bandit", "Slime", "Skeleton"]
## Buff keys an `adj` / `all` entry may use.
const BUFF_KEYS := ["dmg", "cdr", "crit", "shield", "heal", "burn", "poison", "thorns"]

static var loaded := false
static var items := {}
static var recipes: Array = []          # {a, b, r, path}; evolutions are added as {a: x, b: x, r: evo, evo: true}
static var classes := {}
static var class_keys: Array = []
static var paths := {}
static var monster_items: Array = []   # ids of enemy-only items (also stored in `items`)
static var families := {}              # foe name -> monster item ids
static var boss_packs := {}            # boss name -> {w, h, items: [[id, x, y]]}
static var boss_drops := {}            # boss name -> [[item id, weight]]
static var statuses := {}
static var path_day := 4
static var foe_hp_mult := 1.0       # global difficulty knobs (enemies and bosses)
static var foe_atk_mult := 1.0
static var late_ramp := 0.0          # extra enemy damage per day after day 8
static var bosses: Array = []
static var mods: Array = []
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
	for k in d.statuses:
		var s: Dictionary = d.statuses[k]
		statuses[k] = {
			"n": s.n, "ic": s.ic, "col": Color(s.col), "side": s.side, "el": str(s.get("el", "")),
			"tick": float(s.get("tick", 0.0)), "dmg": float(s.get("dmg", 0.0)), "decay": int(s.get("decay", 0)),
			"max": int(s.get("max", 99)), "reflect": float(s.get("reflect", 0.0)), "d": s.get("d", ""),
		}
	for k in d.items:
		items[k] = _norm_item(d.items[k])
	# monster items share the item format (and shape code); cl "monster" keeps them out of every player pool
	for k in d.get("monster_items", {}):
		var m: Dictionary = d.monster_items[k].duplicate()
		m["cost"] = 0
		m["cl"] = "monster"
		m["tags"] = ["Monster"]
		items[k] = _norm_item(m)
		monster_items.append(k)
	families = d.get("families", {})
	for k in d.get("boss_packs", {}):
		var bp: Dictionary = d.boss_packs[k]
		boss_packs[k] = {"w": int(bp.w), "h": int(bp.h), "items": bp.items.map(func(e): return [str(e[0]), int(e[1]), int(e[2])])}
	for k in d.get("boss_drops", {}):
		boss_drops[k] = d.boss_drops[k].map(func(e): return [str(e[0]), float(e[1])])
	for r in d.recipes:
		recipes.append({"a": str(r.a), "b": str(r.b), "r": str(r.r), "path": str(r.get("path", "")), "evo": false})
	for k in items:
		if items[k].evo != "":
			recipes.append({"a": k, "b": k, "r": items[k].evo, "path": "", "evo": true})
	for k in d.classes:
		var c: Dictionary = d.classes[k]
		var st := []
		for s in c.st:
			st.append([str(s[0]), int(s[1]), int(s[2])])
		var res: Dictionary = c.res
		classes[k] = {
			"n": c.n, "ic": c.ic, "hero": c.hero, "d": c.d, "st": st, "bag": _cells(c.bag),
			"res": {
				"id": res.id, "n": res.n, "ic": res.ic, "gain": res.gain, "tag": str(res.get("tag", "")),
				"per": float(res.per), "eff": res.eff, "etag": str(res.get("etag", "")), "v": float(res.v),
				"cap": float(res.get("cap", 99.0)), "d": res.d,
			},
			"ult": {"n": c.ult.n, "ic": c.ult.ic, "need": int(c.ult.need), "on": _norm_on(c.ult.get("on", {})), "sp": str(c.ult.get("sp", "")), "d": c.ult.d},
			"paths": c.paths,
		}
		class_keys.append(k)
	for k in d.paths:
		paths[k] = d.paths[k]
	path_day = int(d.get("path_day", 4))
	foe_hp_mult = float(d.get("foe_hp_mult", 1.0))
	foe_atk_mult = float(d.get("foe_atk_mult", 1.0))
	late_ramp = float(d.get("late_ramp", 0.0))
	for b in d.bosses:
		bosses.append({"d": int(b.d), "n": b.n, "hp": roundf(float(b.hp) * float(d.get("foe_hp_mult", 1.0))), "atk": snappedf(float(b.atk) * float(d.get("foe_atk_mult", 1.0)), 0.1), "cd": float(b.cd), "imm": b.imm, "weak": b.weak, "tier": "boss", "tr": ""})
	mods = d.mods
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


static func _norm_on(src: Dictionary) -> Dictionary:
	var on := {
		"dmg": float(src.get("dmg", 0.0)), "el": str(src.get("el", "")), "crit": float(src.get("crit", 0.0)),
		"critx": float(src.get("critx", 2.0)), "shield": float(src.get("shield", 0.0)), "heal": float(src.get("heal", 0.0)),
		"charge": float(src.get("charge", 0.0)), "ramp": float(src.get("ramp", 0.0)),
		"dmg_per_res": float(src.get("dmg_per_res", 0.0)), "haste": [], "st": {},
	}
	if src.has("haste"):
		on.haste = [float(src.haste[0]), float(src.haste[1])]
	var st: Dictionary = src.get("st", {})
	for k in st:
		on.st[k] = float(st[k])
	return on


static func _buffs(arr) -> Array:
	var out := []
	for b in arr:
		assert(BUFF_KEYS.has(b.k), "Unknown buff key: " + str(b.k))
		out.append({"tag": str(b.tag), "k": str(b.k), "v": float(b.v)})
	return out


static func _norm_item(src: Dictionary) -> Dictionary:
	var ps: Dictionary = src.get("pass", {})
	return {
		"n": src.n, "ic": src.ic, "tier": int(src.t), "lv": int(src.get("lv", 1)), "cost": int(src.cost),
		"cl": str(src.get("cl", "")), "shop": int(src.get("shop", 0)) == 1, "relic": int(src.get("relic", 0)) == 1,
		"c": _cells(src.c), "tags": src.tags, "cd": float(src.get("cd", 0.0)), "once": int(src.get("once", 0)) == 1,
		"on": _norm_on(src.get("on", {})), "adj": _buffs(src.get("adj", [])), "all": _buffs(src.get("all", [])),
		"pass": {
			"hp": float(ps.get("hp", 0.0)), "regen": float(ps.get("regen", 0.0)), "thorns": float(ps.get("thorns", 0.0)),
			"shield": float(ps.get("shield", 0.0)), "income": int(ps.get("income", 0)),
		},
		"sp": str(src.get("sp", "")), "evo": str(src.get("evo", "")), "d": str(src.get("d", "")),
	}


## Item shape after `rot` quarter turns clockwise, normalised so the top-left cell is (0,0).
## Returns {"c": Array[Vector2i] occupied cells}.
static func shape(id: String, rot: int) -> Dictionary:
	var key := id + ":" + str(rot)
	if _shape_cache.has(key):
		return _shape_cache[key]
	var c: Array = items[id].c.duplicate()
	for _r in rot:
		c = c.map(func(p): return Vector2i(-p.y, p.x))
	var mx := 999
	var my := 999
	for p in c:
		mx = mini(mx, p.x)
		my = mini(my, p.y)
	var off := Vector2i(mx, my)
	c = c.map(func(p): return p - off)
	var res := {"c": c}
	_shape_cache[key] = res
	return res


## The cell of a shape that sits under the pointer when dragging (the "middle" cell).
static func mid_cell(id: String, rot: int) -> Vector2i:
	var cs: Array = shape(id, rot).c
	return cs[int((cs.size() - 1) / 2)]


static func tier_color(id: String) -> Color:
	return tier_colors[items[id].tier]


static func elem_icon(el: String) -> String:
	return elem_icons.get(el, "")


## Short one-line stats for cards: "⚔ 5 ⏱ 2s 🔥1".
static func short_stats(id: String) -> String:
	var d: Dictionary = items[id]
	var on: Dictionary = d.on
	var p := []
	if on.dmg > 0:
		p.append("%s%s" % [elem_icon(on.el) if on.el != "" else "⚔", _num(on.dmg)])
	if on.shield > 0:
		p.append("🛡%s" % _num(on.shield))
	if on.heal > 0:
		p.append("💚%s" % _num(on.heal))
	for k in on.st:
		p.append(statuses[k].ic + _num(on.st[k]))
	if on.charge > 0:
		p.append("🔋%ss" % _num(on.charge))
	if not on.haste.is_empty():
		p.append("💨%d%%" % roundi(on.haste[0] * 100))
	if d.cd > 0:
		p.append("⏱%ss" % _num(d.cd))
	elif d.once:
		p.append(I18n.t("once"))
	if p.is_empty() or d.cd == 0 and not d.once:
		if not d.adj.is_empty():
			p.append("✨ " + I18n.t("aura"))
		elif d.pass.hp > 0:
			p.append("❤️+%s" % _num(d.pass.hp))
		elif d.pass.income > 0:
			p.append("🪙+%d" % d.pass.income)
		elif p.is_empty():
			p.append("✨ " + I18n.t("passive"))
	return " ".join(p)


static func buff_text(b: Dictionary) -> String:
	var tag := I18n.t(b.tag)
	var v: String = _num(b.v)
	match b.k:
		"dmg": return I18n.t("%s items +%s damage") % [tag, v]
		"cdr": return I18n.t("%s items charge %d%% faster") % [tag, roundi(b.v * 100)]
		"crit": return I18n.t("%s items +%d%% crit") % [tag, roundi(b.v * 100)]
		"shield": return I18n.t("%s items +%s Shield") % [tag, v]
		"heal": return I18n.t("%s items +%s heal") % [tag, v]
	if statuses.has(b.k):
		return I18n.t("%s items +%s %s") % [tag, v, I18n.t(statuses[b.k].n)]
	return tag


## Full description lines for the inspector.
static func describe_lines(id: String) -> Array:
	var d: Dictionary = items[id]
	var on: Dictionary = d.on
	var out := []
	var when := ""
	if d.once:
		when = I18n.t("Once, below 50% HP:")
	elif d.cd > 0:
		when = I18n.t("Every %ss:") % _num(d.cd)
	var acts := []
	if on.dmg > 0:
		acts.append(I18n.t("deal %s %s damage") % [_num(on.dmg), I18n.t(on.el)])
	if on.shield > 0:
		acts.append(I18n.t("gain %s Shield") % _num(on.shield))
	if on.heal > 0:
		acts.append(I18n.t("heal %s") % _num(on.heal))
	for k in on.st:
		acts.append(I18n.t("apply %s %s") % [_num(on.st[k]), I18n.t(statuses[k].n)] if statuses[k].side == "foe" else I18n.t("gain %s %s") % [_num(on.st[k]), I18n.t(statuses[k].n)])
	if on.charge > 0:
		acts.append(I18n.t("charge touching items by %ss") % _num(on.charge))
	if not on.haste.is_empty():
		acts.append(I18n.t("+%d%% Haste for %ss") % [roundi(on.haste[0] * 100), _num(on.haste[1])])
	if not acts.is_empty():
		out.append((when + " " if when != "" else "") + ", ".join(acts) + ".")
	if on.crit > 0:
		out.append(I18n.t("%d%% crit chance (×%s damage).") % [roundi(on.crit * 100), _num(on.critx)])
	if on.ramp > 0:
		out.append(I18n.t("+%s damage after every hit this fight.") % _num(on.ramp))
	for b in d.adj:
		out.append("✨ " + I18n.t("Touching: ") + buff_text(b))
	for b in d.all:
		out.append("🌐 " + I18n.t("Whole pack: ") + buff_text(b))
	var ps: Dictionary = d.pass
	if ps.hp > 0:
		out.append("❤️ " + I18n.t("+%s Max HP") % _num(ps.hp))
	if ps.regen > 0:
		out.append("💚 " + I18n.t("Regenerate %s HP per second") % _num(ps.regen))
	if ps.thorns > 0:
		out.append("🌵 " + I18n.t("Start fights with %s Thorns") % _num(ps.thorns))
	if ps.income > 0:
		out.append("🪙 " + I18n.t("+%d gold every morning") % ps.income)
	if d.d != "":
		out.append("⭐ " + I18n.t(d.d))
	if out.is_empty():
		out.append(I18n.t("No effect on its own."))
	return out


static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return str(snappedf(v, 0.01))


static func foe_icon(name: String) -> String:
	var base := name.replace("Elite ", "").replace("Ambusher ", "")
	return foe_icons.get(base, "👾")
