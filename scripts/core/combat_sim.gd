class_name CombatSim
extends RefCounted
## Real-time auto-battle at 0.1 s ticks. step() advances one tick and queues
## visual events in `events` for the combat view to animate.
##
## Statuses are data-driven (GameData.statuses): every status with a `tick` deals
## stacks × dmg on that interval and loses `decay` stacks; hero statuses with
## `reflect` hit back when you are struck. New statuses of that shape need no code.
## Item specials (`sp`) are the only hand-written hooks.

const TICK := 0.1
const FATIGUE_TICK := 250   # 25 s
const HP_STRIKE_TICKS := 40

var run: RunState
var node: Dictionary
var preview := false        # forecast mode: average crits, no dice, no events kept
var e: Dictionary
var ehp := 0.0
var php := 0.0
var mhp := 60.0
var shield := 0.0
var blocked := 0.0
var tk := 0
var fi: Array = []          # the monster's items: {id, d, x, y, rot, p, cd, uid, st}
var fshield := 0.0
var enraged := false        # bosses rage once at half HP: their items charge 25% faster
var fhastes: Array = []
var hd := {}                # statuses the monster put on you: id -> stacks
var rg := 0.0
var fs := {}                # foe statuses: id -> stacks
var hs := {}                # hero statuses: id -> stacks
var hastes: Array = []      # [{v, t}] ticks left
var resv := 0               # class resource (Heat, Toxin, Gears, Guard)
var res_acc := 0.0
var ult := 0                # ultimate meter (item triggers)
var ult_need := 24
var ults := 0
var sp := {}                # specials present in the pack
var turrets := 0
var gold_mult := 1.0
var hero_dmg := 1.0         # level-ups: +damage on everything you deal (hits, DoTs, reflect)
var evade := 0.0            # chance to dodge a monster hit (Phantom Marksman)
var dodge := 0              # monster hits that will surely miss (Shadowstep)
var next_crit := false      # Shadowstep: the next weapon hit crits for 250% and Bleeds
var freeze_t := 0           # ticks the monster's items stay frozen (Supernova, Maelstrom Call)
var empty_tiles := 0        # unlocked pack tiles with nothing on them
var dmg_phys := 0.0         # Physical / Magic damage dealt this fight (Judgement Strike)
var dmg_mag := 0.0
var _last_cat := -1         # 0 Physical, 1 Magic: the kind of your last hit (Equilibrium)
var stat_dmg := {}          # status id -> damage dealt
var dot_src := {}           # status id -> {item uid: stacks it applied}, to credit DoT damage to items
var _by_uid := {}           # item uid -> combat item dict
var done := false
var won := false
var log_lines: Array = []
var items: Array = []       # {i, d, f, p (progress s), cd, used, ramp, nb: Array[int], st:{dmg, heal, shield, hits}}
var events: Array = []
var _rng := RandomNumberGenerator.new()


func _init(r: RunState, n: Dictionary, is_preview := false) -> void:
	run = r
	node = n
	preview = is_preview
	if preview:
		_rng.seed = 12345
	else:
		_rng.randomize()
	e = r.with_hazard(n.e)
	if not e.has("items"):
		e.merge(r.build_pack(str(e.get("fam", "Goblin")), e.get("tier", "") == "elite"), true)
		r._tune_pack(e)
	ehp = e.hp
	var fidx := 0
	for it in e.items:
		var fd: Dictionary = GameData.items[it[0]]
		fi.append({"id": it[0], "d": fd, "x": int(it[1]), "y": int(it[2]), "rot": int(it[3]) if it.size() > 3 else 0, "p": 0.0, "cd": fd.cd * e.get("cd_mult", 1.0), "uid": -100 - fidx, "st": {"dmg": 0.0, "hits": 0}})
		fidx += 1
	php = r.hp
	mhp = r.mhp
	rg = r.regen()
	ult_need = maxi(5, roundi(r.cls_def().ult.need * (1.0 - r.pv("ult"))))
	shield = r.pv("shield")   # pet: start the fight shielded
	for k in GameData.statuses:
		var s: Dictionary = GameData.statuses[k]
		if s.side == "foe":
			fs[k] = 0.0
		else:
			hs[k] = 0.0
		stat_dmg[k] = 0.0
	var g := r.calc()
	for i in g:
		var d: Dictionary = i.def()
		if d.sp != "":
			for s_ in d.sp.split(","):   # a relic may carry several specials
				sp[s_.strip_edges()] = true
		if d.tags.has("Turret"):
			turrets += 1
		hs["thorns"] = hs.get("thorns", 0.0) + d.pass.thorns
		shield += d.pass.shield
	# class passives that are not a resource (e.g. Equilibrium, High Tide)
	for s_ in str(r.cls_def().get("sp", "")).split(","):
		if s_.strip_edges() != "":
			sp[s_.strip_edges()] = true
	var used := 0
	for i in g:
		used += i.cells().size()
	empty_tiles = maxi(0, r.tiles.size() - used)
	if sp.has("empty_evasion"):
		evade = minf(0.3, empty_tiles * 0.03)
	hero_dmg = 1.0 + r.pv("dmg")
	if sp.has("gold_power"):
		gold_mult += minf(0.4, r.gold * 0.005)
	if sp.has("gold_engine"):
		gold_mult += 0.05 * floorf(r.gold / 10.0)
	for i in g:
		var d: Dictionary = i.def()
		if d.cd > 0 or d.once:
			var f := r.eff(i)
			items.append({"i": i, "d": d, "f": f, "p": 0.0, "cd": f.cd, "used": false, "ramp": 0.0, "nb": [], "st": {"dmg": 0.0, "heal": 0.0, "shield": 0.0, "hits": 0, "el": f.el, "dot": {}}})
	for x in items:
		_by_uid[x.i.uid] = x
	# neighbour lists (item indices) for Charge
	for a in items.size():
		for b in items.size():
			if a != b and r.adj(items[a].i, items[b].i):
				items[a].nb.append(b)


func _ev(ev: Dictionary) -> void:
	if not preview:
		events.append(ev)


func _log(t: String) -> void:
	if preview:
		return
	log_lines.push_front(t)
	if log_lines.size() > 6:
		log_lines.resize(6)


## kind: "" (plain number), "shield", "dot" (a status tick) or "status" (stacks applied); key = status id.
func _num(side: String, text: String, col: Color, big := false, uid := -1, kind := "", key := "") -> void:
	_ev({"t": "num", "side": side, "text": text, "col": col, "big": big, "uid": uid, "kind": kind, "key": key})


## Damage one status tick deals right now. side "foe" = statuses on the monster (your DoTs),
## "hero" = statuses the monster put on you. Poison crits (Venom special) are left out.
func dot_tick(side: String, k: String) -> float:
	var s: Dictionary = GameData.statuses[k]
	if s.tick <= 0:
		return 0.0
	if side == "hero":
		return hd.get(k, 0.0) * s.dmg
	var dot_mult := 1.0
	var rd := res_def()
	if rd.eff == "dot_pct":
		dot_mult += rd.v * resv
	var v: float = fs.get(k, 0.0) * s.dmg * dot_mult * RunState.elem_mult(e, s.el) * gold_mult * hero_dmg
	return v * _defense_mult(GameData.is_magic(s.el), 0.0)


## How much damage the DoTs on one side will deal over the next `secs` seconds if nothing changes.
func dot_forecast(side: String, secs := 3) -> float:
	var st: Dictionary = hd if side == "hero" else fs
	var tot := 0.0
	for k in st:
		var s: Dictionary = GameData.statuses[k]
		var n: float = st[k]
		if s.tick <= 0 or n <= 0:
			continue
		var per := dot_tick(side, k) / n
		var decay: float = s.decay
		if side == "foe" and k == "burn" and sp.has("burn_nodecay"):
			decay = 0.0
		for t in secs:
			tot += maxf(0.0, n - decay * t) * per
	return tot


func _heal_mult() -> float:
	return 0.5 if run.mod.id == "blood" else 1.0


func _shield_cap() -> float:
	return 40.0 + run.day * 4


func res_def() -> Dictionary:
	return run.cls_def().res


func haste() -> float:
	var h := 0.0
	for x in hastes:
		h += x.v
	var rd := res_def()
	if rd.eff == "haste_pct":
		h += minf(rd.cap, rd.v * resv)
	return minf(1.5, h)


func _gain_res(kind: String, amount: float) -> void:
	var rd := res_def()
	if rd.gain != kind:
		return
	var per: float = rd.per * (0.5 if sp.has("fast_toxin") and kind == "poison_applied" else 1.0)
	res_acc += amount
	while res_acc >= per:
		res_acc -= per
		resv += 1
		_ev({"t": "res", "v": resv})
		if sp.has("tide_soak") and resv % 5 == 0:
			add_status("soaked", 2)   # High Tide: every 5 Tide soaks the enemy


func _crit(chance: float, mult: float) -> float:
	if chance <= 0:
		return 1.0
	if preview:
		return 1.0 + chance * (mult - 1.0)
	return mult if _rng.randf() < chance else 1.0


## Bleed: when the bleeding side uses an item it takes `trig` damage per stack (ignores Armor and
## Shield), then the Bleed drops by its decay. side "foe" = Bleed on the monster, "hero" = on you.
func _bleed_trigger(side: String) -> void:
	if not GameData.statuses.has("bleed"):
		return
	var s: Dictionary = GameData.statuses.bleed
	var st: Dictionary = fs if side == "foe" else hd
	var n: float = st.get("bleed", 0.0)
	if n <= 0:
		return
	var v: float = n * s.trig
	if side == "foe":
		v *= gold_mult * hero_dmg
		ehp -= v
		stat_dmg["bleed"] = stat_dmg.get("bleed", 0.0) + v
		_credit_dot("bleed", v)
		if sp.has("bleed_heal"):
			heal(v * 0.3)
	else:
		php -= v
	_num(side, "-" + GameData._num(roundf(v * 10) / 10.0), s.col, false, -1, "dot", "bleed" if side == "foe" else "hd:bleed")
	st["bleed"] = maxf(0.0, n - maxf(1.0, s.decay))


## Soaked slows the side's items: each stack takes `slow` off their charge speed.
func _soak_slow(st: Dictionary) -> float:
	var s: Dictionary = GameData.statuses.get("soaked", {})
	return 1.0 - minf(0.9, st.get("soaked", 0.0) * s.get("slow", 0.0))


## What the monster's defenses and your debuffs leave of a hit: Armored cuts Physical (less with
## Armor Pierce), Warded cuts Magic, Soaked makes it take more Magic.
func _defense_mult(is_mag: bool, pierce: float) -> float:
	var m := 1.0
	if is_mag:
		if e.get("tr", "") == "warded":
			m *= 1.0 - GameData.WARD_CUT
		m *= 1.0 + fs.get("soaked", 0.0) * GameData.statuses.get("soaked", {}).get("magic_amp", 0.0)
	elif e.get("tr", "") == "armored":
		m *= 1.0 - GameData.ARMOR_CUT * (1.0 - clampf(pierce, 0.0, 1.0))
	return m


## Armor Pierce of a hit: the item's own, Arsenal turrets (all of it), Forgeblade Heat.
func _pierce(x) -> float:
	var p := 0.5 if sp.has("colossus_pierce") else 0.0   # Colossus: every Physical hit, Titan strikes too
	if x == null:
		return p
	p += x.f.get("pierce", 0.0)
	if sp.has("turret_pierce") and x.d.tags.has("Turret"):
		p = 1.0
	if sp.has("heat_pierce") and x.d.tags.has("Weapon"):
		p += 0.04 * resv
	if sp.has("apex") and x.d.tags.has("Beast"):
		p += 0.3
	return minf(1.0, p)


## Deals direct damage to the foe. Returns the damage dealt.
## magic: -1 = from the element, 0 = Physical, 1 = Magic (Thorns reflect is Magic without an element).
func damage(x, base: float, el: String, crit := 0.0, critx := 2.0, src := "", magic := -1) -> float:
	var is_mag: bool = GameData.is_magic(el) if magic < 0 else magic == 1
	var m := RunState.elem_mult(e, el)
	var rd := res_def()
	var shadow := false
	if x != null:
		# Momentum (Rogue): crit chance and crit damage per stack on the tagged items
		if rd.eff == "crit_tag" and x.d.tags.has(rd.etag):
			crit += minf(float(rd.get("cap", 0.45)), rd.v * resv)
			critx += float(rd.get("v2", 0.0)) * resv
		if next_crit and x.d.tags.has("Weapon"):
			next_crit = false
			shadow = true
			crit = 1.0
			critx = maxf(critx, 2.5)
	var cm := _crit(crit, critx)
	var v := base * m * cm * gold_mult * hero_dmg
	if rd.eff == "magic_pct" and is_mag:
		v *= 1.0 + minf(float(rd.get("cap", 1.0)), rd.v * resv)
	if rd.eff == "dmg_all_pct":
		v *= 1.0 + minf(float(rd.get("cap", 1.0)), rd.v * resv)
	if sp.has("siren") and is_mag and (el == "Water" or el == "Shock"):
		v *= 1.0 + 0.03 * fs.get("soaked", 0.0)
	if x != null:
		if rd.eff == "dmg_pct_tag" and x.d.tags.has(rd.etag):
			v *= 1.0 + rd.v * resv
		if sp.has("void_mana") and x.d.tags.has("Spell"):
			v *= 1.4
		if sp.has("empty_evasion") and x.d.tags.has("Ranged"):
			v *= 1.0 + 0.03 * empty_tiles
		if x.d.sp == "execute" and ehp < e.hp * 0.3:
			v *= 2.0
	v *= _defense_mult(is_mag, _pierce(x))
	v = maxf(1.0, roundf(v))
	if fshield > 0:
		var ab := minf(fshield, v)
		fshield -= ab
		ehp -= v - ab
	else:
		ehp -= v
	var uid: int = x.i.uid if x != null else -1
	if x != null:
		x.st.dmg += v
	if is_mag:
		dmg_mag += v
	else:
		dmg_phys += v
	if x != null:
		if cm > 1.0:
			_gain_res("crit_hit", 1.0)
		var cat := 1 if is_mag else 0
		if _last_cat >= 0 and cat != _last_cat:
			_gain_res("alternate", 1.0)   # Equilibrium: switching between Physical and Magic
		_last_cat = cat
		if sp.has("dusk_lifesteal") and not is_mag and x.d.tags.has("Weapon"):
			heal(v * 0.1)
		if shadow:
			add_status("bleed", 10, x.i.uid)
	var is_crit := cm > 1.0 and not preview
	_ev({"t": "hit", "uid": uid, "v": v, "el": el, "m": m, "crit": is_crit, "melee": x != null and x.d.tags.has("Melee"), "icon": x.d.ic if x != null else src})
	var who: String = (x.d.ic + " " + I18n.t(x.d.n)) if x != null else src
	if m < 1:
		_log(I18n.t("%s hits for %d — %s resisted") % [who, roundi(v), I18n.t(el)])
	elif is_crit:
		_log(I18n.t("%s CRITS for %d!") % [who, roundi(v)])
	return v


## Adds stacks under the status cap. max -1 = no cap (Burn and Poison: same rule for you and the monster).
func _stack(s: Dictionary, cur: float, n: float) -> float:
	return cur + n if s.max < 0 else minf(s.max, cur + n)


func add_status(k: String, n: float, uid := -1) -> void:
	if n <= 0 or not GameData.statuses.has(k):
		return
	var s: Dictionary = GameData.statuses[k]
	if s.side == "foe":
		fs[k] = _stack(s, fs.get(k, 0.0), n)
		if uid >= 0:
			if not dot_src.has(k):
				dot_src[k] = {}
			dot_src[k][uid] = dot_src[k].get(uid, 0.0) + n
		if k == "poison":
			_gain_res("poison_applied", n)
		_num("foe", "%s+%s" % [s.ic, GameData._num(n)], s.col, false, uid, "status", k)
		if k == "burn" and sp.has("burn_burst") and fs.burn >= 15:
			var v := damage(null, fs.burn, "Fire", 0, 2, "💥")
			stat_dmg["burn"] += v
			fs.burn = 5.0
			_ev({"t": "burst", "v": v})
			_log(I18n.t("💥 Burn explodes for %d!") % roundi(v))
	else:
		hs[k] = _stack(s, hs.get(k, 0.0), n)
		_num("hero", "%s+%s" % [s.ic, GameData._num(n)], s.col, false, uid, "status", k)


func gain_shield(v: float, uid := -1) -> void:
	if v <= 0:
		return
	var before := shield
	shield = minf(_shield_cap(), shield + v)
	_gain_res("shield_gained", v)
	_num("hero", "🛡+" + GameData._num(shield - before if shield - before > 0 else v), Color("#7dd3fc"), false, uid, "shield")


func heal(v: float, uid := -1) -> float:
	var h := minf(v * _heal_mult(), mhp - php)
	if h > 0:
		php += h
		_num("hero", "+" + GameData._num(roundf(h)), Color("#4ade80"), false, uid)
	return h


## Runs one item's trigger.
func fire(idx: int) -> void:
	var x: Dictionary = items[idx]
	var d: Dictionary = x.d
	var f: Dictionary = x.f
	x.st.hits += 1
	_ev({"t": "trigger", "uid": x.i.uid})
	_bleed_trigger("hero")
	var dmg: float = f.dmg + x.ramp
	if sp.has("turret_count") and d.tags.has("Turret"):
		dmg += turrets * 2
	if sp.has("weapon_ramp") and d.tags.has("Weapon"):
		x.ramp += 1.0
	if f.ramp > 0:
		x.ramp += f.ramp
	if d.sp == "shield_dmg":
		dmg += shield * 0.25
	if d.sp == "gold_shot":
		dmg += floorf(run.gold / 8.0)
	if d.sp == "hp_strike_big":
		dmg += mhp * 0.10
	if dmg > 0:
		damage(x, dmg, f.el if f.el != "" else "Physical", f.crit, f.critx)
	if x.get("bonus", 0.0) > 0:
		# Equilibrium: a Magic item next to this weapon charged it with bonus Magic damage
		damage(x, x["bonus"], "Arcane", 0, 2, "", 1)
		x["bonus"] = 0.0
	_class_trigger(idx, x)
	for k in f.st:
		add_status(k, f.st[k], x.i.uid)
	if f.shield > 0:
		var before := shield
		gain_shield(f.shield, x.i.uid)
		x.st.shield += shield - before
	if f.heal > 0:
		x.st.heal += heal(f.heal, x.i.uid)
	if not f.haste.is_empty():
		hastes.append({"v": f.haste[0], "t": roundi(f.haste[1] * 10)})
		_num("hero", "💨+%d%%" % roundi(f.haste[0] * 100), Color("#ffe14a"), false, x.i.uid)
	if f.charge > 0:
		for b in x.nb:
			_charge(b, f.charge)
	# pack-wide chain specials
	if sp.has("charge_chain"):
		for b in x.nb:
			if items[b].d.tags.has("Mech"):
				_charge(b, 0.2)
	if sp.has("perpetual"):
		for c in items.size():
			if items[c].d.sp == "perpetual" and c != idx:
				for b in items[c].nb:
					if b != idx:
						_charge(b, items[b].cd * 0.2)
	var rd := res_def()
	if rd.gain == "trigger_tag" and d.tags.has(rd.tag):
		_gain_res("trigger_tag", 1.0)
	ult += 1
	if ult >= ult_need:
		ult = 0
		fire_ult()


## Class and path effects that react to one of your items firing.
func _class_trigger(idx: int, x: Dictionary) -> void:
	var d: Dictionary = x.d
	var mag: bool = GameData.is_magic(x.f.el)
	if sp.has("chill") and d.tags.has("Spell"):
		add_status("soaked", 1, x.i.uid)
		gain_shield(3, x.i.uid)
	if sp.has("void_mana") and d.tags.has("Spell"):
		php = maxf(1.0, php - 2.0)
	if sp.has("tempest") and mag:
		gain_shield(2, x.i.uid)
	if sp.has("apex") and d.tags.has("Beast"):
		add_status("bleed", 1, x.i.uid)
	if sp.has("shaman") and d.tags.has("Beast"):
		heal(2, x.i.uid)
	if sp.has("equilibrium") and x.f.dmg > 0:
		for b in x.nb:
			var y: Dictionary = items[b]
			if not mag and GameData.is_magic(y.f.el):
				_charge(b, y.cd * 0.15)
			elif mag and y.d.tags.has("Weapon") and not GameData.is_magic(y.f.el):
				y["bonus"] = 6.0


## Per-item charge speed: Pack Hunt (Beasts), Bloodwater Frenzy (Sea creatures vs a bleeding foe).
func _item_speed(x: Dictionary) -> float:
	var s := 1.0
	var rd := res_def()
	if rd.eff == "haste_tag" and x.d.tags.has(rd.etag):
		s += minf(float(rd.get("cap", 0.4)), rd.v * resv)
	if sp.has("frenzy") and x.d.tags.has("Sea") and fs.get("bleed", 0.0) > 0:
		s += 0.3
	return s


func _charge(idx: int, sec: float) -> void:
	var y: Dictionary = items[idx]
	if y.d.once:
		return
	y.p = minf(y.cd, y.p + sec)


func fire_ult() -> void:
	var u: Dictionary = run.cls_def().ult
	ults += 1
	_ev({"t": "ult", "n": u.n, "ic": u.ic})
	_log(I18n.t("%s %s!") % [u.ic, I18n.t(u.n)])
	var on: Dictionary = u.on
	var dmg: float = on.dmg + on.dmg_per_res * resv
	match u.sp:
		"shield_slam":
			dmg += shield * 2.0
		"double_poison":
			if fs.get("poison", 0.0) > 0:
				add_status("poison", fs.poison * 0.5)
		"full_charge":
			for y in items:
				if not y.d.once:
					y.p = y.cd
		"shadowstep":
			dodge += 1
			next_crit = true
		"supernova":
			resv = 0   # all Mana spent (the damage above already counted it)
			freeze_t = 20
		"maelstrom":
			freeze_t = 15
			if resv > 0:
				damage(null, 4.0 * resv, "Water", 0, 2, u.ic)
		"judgement":
			var hi := maxf(dmg_phys, dmg_mag)
			var balanced := hi > 0 and minf(dmg_phys, dmg_mag) >= hi * 0.7
			var k := 2.0 if balanced else 1.0
			damage(null, 20.0 * k, "Physical", 0, 2, u.ic)
			damage(null, 20.0 * k, "Arcane", 0, 2, u.ic)
			if balanced:
				heal(20)
				_log(I18n.t("⚖️ Perfect balance: Judgement strikes twice as hard!"))
		"alpha_roar":
			var beasts := 0
			for bi in items.size():
				if items[bi].d.tags.has("Beast"):
					beasts += 1
					items[bi].p = items[bi].cd   # fires on the next tick
			if beasts > 0:
				gain_shield(3.0 * beasts)
	if dmg > 0:
		var v := damage(null, dmg, on.el if on.el != "" else "Physical", 0, 2, u.ic)
		_num("foe", u.ic + " " + GameData._num(v), Color("#ffe14a"), true)
	for k in on.st:
		add_status(k, on.st[k])
	if on.heal > 0:
		heal(on.heal)
	if not on.haste.is_empty():
		hastes.append({"v": on.haste[0], "t": roundi(on.haste[1] * 10)})


func step() -> void:
	if done:
		return
	tk += 1
	var speed := (1.0 + haste()) * _soak_slow(hd)
	for idx in items.size():
		var x: Dictionary = items[idx]
		var d: Dictionary = x.d
		if d.once:
			if not x.used and php < mhp * 0.5:
				x.used = true
				x.st.hits += 1
				_ev({"t": "trigger", "uid": x.i.uid})
				x.st.heal += heal(x.f.heal, x.i.uid)
				if x.f.shield > 0:
					gain_shield(x.f.shield, x.i.uid)
				_log(I18n.t("🧪 %s healed you") % I18n.t(d.n))
			continue
		x.p += TICK * speed * _item_speed(x)
		if x.p >= x.cd:
			x.p -= x.cd
			fire(idx)
	# relic timer
	if sp.has("hp_strike") and tk % HP_STRIKE_TICKS == 0:
		damage(null, mhp * 0.05, "Physical", 0, 2, "🌲")
	# once per second: regen and status ticks
	if tk % 10 == 0:
		if rg > 0 and php < mhp:
			heal(rg)
		for k in fs:
			var s: Dictionary = GameData.statuses[k]
			if s.tick <= 0 or fs[k] <= 0 or tk % roundi(s.tick * 10) != 0:
				continue
			var v: float = dot_tick("foe", k)
			if k == "poison" and sp.has("poison_crit"):
				v *= _crit(0.25, 3.0)
			if v > 0:
				ehp -= v
				stat_dmg[k] += v
				_credit_dot(k, v)
				_num("foe", "-" + GameData._num(roundf(v * 10) / 10.0), s.col, false, -1, "dot", k)
			if s.decay > 0 and not (k == "burn" and sp.has("burn_nodecay")):
				fs[k] = maxf(0.0, fs[k] - s.decay)
		# poison / burn the monster put on you
		for k in hd:
			var s: Dictionary = GameData.statuses[k]
			if s.tick <= 0 or hd[k] <= 0 or tk % roundi(s.tick * 10) != 0:
				continue
			var v: float = dot_tick("hero", k)
			php -= v
			_num("hero", "-" + GameData._num(roundf(v * 10) / 10.0), s.col, false, -1, "dot", "hd:" + k)
			if s.decay > 0:
				hd[k] = maxf(0.0, hd[k] - s.decay)
		if e.tr == "regen" and ehp < e.hp:
			var v := maxf(1.0, roundf(e.hp * 0.015))
			ehp = minf(e.hp, ehp + v)
			_num("foe", "+%d" % roundi(v), Color("#4ade80"))
	for x in hastes:
		x.t -= 1
	hastes = hastes.filter(func(x): return x.t > 0)
	# the monster's items charge and fire
	var fspeed := (1.0 + _foe_haste()) * _soak_slow(fs)
	if freeze_t > 0:
		freeze_t -= 1
		fspeed = 0.0
	for fx in fi:
		if fx.cd <= 0:
			continue
		fx.p += TICK * fspeed
		if fx.p >= fx.cd:
			fx.p -= fx.cd
			foe_fire(fx)
	for x in fhastes:
		x.t -= 1
	fhastes = fhastes.filter(func(x): return x.t > 0)
	# boss rage at half HP
	if not enraged and node.get("k", "") == "boss" and ehp <= e.hp * 0.5 and ehp > 0:
		enraged = true
		for fx in fi:
			fx.cd *= 0.8
		_ev({"t": "enrage"})
		_log(I18n.t("💢 %s is ENRAGED!") % I18n.t(e.n))
	# sudden-death fatigue
	if tk > FATIGUE_TICK and tk % 10 == 0:
		var fd := (tk - FATIGUE_TICK) / 10.0
		php -= fd
		ehp -= fd
		_ev({"t": "fatigue"})
		_log(I18n.t("☠️ Fatigue: %d true damage to both") % roundi(fd))
	if ehp <= 0:
		_finish(true)
	elif php <= 0:
		_finish(false)



func _foe_haste() -> float:
	var h := 0.0
	for x in fhastes:
		h += x.v
	return minf(1.0, h)


## One monster item fires: hits you (through your Shield), puts statuses on you, or shields / heals / hastes the monster.
func foe_fire(fx: Dictionary) -> void:
	var on: Dictionary = fx.d.on
	var dm_mult: float = e.get("dmg_mult", 1.0)
	var sup: float = e.get("sup_mult", 1.0)
	fx.st.hits += 1
	_ev({"t": "foe_trigger", "uid": fx.uid})
	_bleed_trigger("foe")
	if on.dmg > 0:
		var dm: float = roundf(on.dmg * dm_mult * _crit(on.crit, on.critx) * 10.0) / 10.0
		if dodge > 0 or (evade > 0 and _rng.randf() < evade):
			# Shadowstep / Phantom evasion: the hit misses completely
			if dodge > 0:
				dodge -= 1
			_num("hero", "💨 " + I18n.t("EVADE"), Color("#c4b5fd"), true)
			dm = 0.0
		var ab := minf(shield, dm)
		shield -= ab
		blocked += ab
		php -= dm - ab
		fx.st.dmg += dm
		_ev({"t": "foe_atk", "dm": dm, "ab": ab, "uid": fx.uid, "icon": fx.d.ic})
		_reflect()
	for k in on.st:
		var s: Dictionary = GameData.statuses[k]
		var n: float = snappedf(on.st[k] * dm_mult, 0.1)   # scaled like the hits, no rounding up
		hd[k] = _stack(s, hd.get(k, 0.0), n)
		_num("hero", "%s+%s" % [s.ic, GameData._num(n)], s.col, false, -1, "status", "hd:" + k)
	if on.shield > 0:
		fshield += roundf(on.shield * sup)
		_num("foe", "🛡️+" + GameData._num(roundf(on.shield * sup)), Color("#7dd3fc"), false, -1, "shield")
	if on.heal > 0 and ehp < e.hp:
		var h := minf(e.hp - ehp, roundf(on.heal * sup))
		ehp += h
		_num("foe", "+" + GameData._num(h), Color("#4ade80"))
	if not on.haste.is_empty():
		fhastes.append({"v": on.haste[0], "t": roundi(on.haste[1] * 10)})
		_num("foe", "💨+%d%%" % roundi(on.haste[0] * 100), Color("#ffe14a"))

## Thorns-style hero statuses and the Guard resource hit back when you are struck.
func _reflect() -> void:
	var total := 0.0
	for k in hs:
		var s: Dictionary = GameData.statuses[k]
		if s.reflect > 0 and hs[k] > 0:
			total += hs[k] * s.reflect
	var rd := res_def()
	if rd.eff == "reflect":
		total += rd.v * resv
	if sp.has("thorn_grow"):
		add_status("thorns", 1)
	if total <= 0:
		return
	var times := 2 if sp.has("thorns_double") else 1
	for _t in times:
		var v := damage(null, total, GameData.statuses.thorns.el, 0, 2, "🌵", 1)   # Thorns hit back with Magic
		stat_dmg["thorns"] = stat_dmg.get("thorns", 0.0) + v


func _finish(w: bool) -> void:
	done = true
	won = w
	_ev({"t": "end", "win": w})


func skip_to_end() -> void:
	var guard := 0
	while not done and guard < 4000:
		step()
		guard += 1
	events.clear()


func take_events() -> Array:
	var out := events
	events = []
	return out


## Splits a status tick's damage between the items that applied that status (by stacks applied).
func _credit_dot(k: String, v: float) -> void:
	var src: Dictionary = dot_src.get(k, {})
	var tot := 0.0
	for u in src:
		tot += src[u]
	if tot <= 0:
		return
	for u in src:
		var x = _by_uid.get(u)
		if x != null:
			x.st.dot[k] = x.st.dot.get(k, 0.0) + v * src[u] / tot
