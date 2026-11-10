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
var stat_dmg := {}          # status id -> damage dealt
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
			sp[d.sp] = true
		if d.tags.has("Turret"):
			turrets += 1
		hs["thorns"] = hs.get("thorns", 0.0) + d.pass.thorns
		shield += d.pass.shield
	if sp.has("gold_power"):
		gold_mult += minf(0.4, r.gold * 0.005)
	if sp.has("gold_engine"):
		gold_mult += 0.05 * floorf(r.gold / 10.0)
	for i in g:
		var d: Dictionary = i.def()
		if d.cd > 0 or d.once:
			var f := r.eff(i)
			items.append({"i": i, "d": d, "f": f, "p": 0.0, "cd": f.cd, "used": false, "ramp": 0.0, "nb": [], "st": {"dmg": 0.0, "heal": 0.0, "shield": 0.0, "hits": 0}})
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


func _num(side: String, text: String, col: Color, big := false, uid := -1) -> void:
	_ev({"t": "num", "side": side, "text": text, "col": col, "big": big, "uid": uid})


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


func _crit(chance: float, mult: float) -> float:
	if chance <= 0:
		return 1.0
	if preview:
		return 1.0 + chance * (mult - 1.0)
	return mult if _rng.randf() < chance else 1.0


## Deals direct damage to the foe. Returns the damage dealt.
func damage(x, base: float, el: String, crit := 0.0, critx := 2.0, src := "") -> float:
	var m := RunState.elem_mult(e, el)
	var cm := _crit(crit, critx)
	var v := base * m * cm * gold_mult
	if x != null:
		var rd := res_def()
		if rd.eff == "dmg_pct_tag" and x.d.tags.has(rd.etag):
			v *= 1.0 + rd.v * resv
		if x.d.sp == "execute" and ehp < e.hp * 0.3:
			v *= 2.0
	v = maxf(1.0, roundf(v) - (3.0 if e.tr == "armored" else 0.0))
	if fshield > 0:
		var ab := minf(fshield, v)
		fshield -= ab
		ehp -= v - ab
	else:
		ehp -= v
	var uid: int = x.i.uid if x != null else -1
	if x != null:
		x.st.dmg += v
	var is_crit := cm > 1.0 and not preview
	_ev({"t": "hit", "uid": uid, "v": v, "el": el, "m": m, "crit": is_crit, "melee": x != null and x.d.tags.has("Melee"), "icon": x.d.ic if x != null else src})
	var who: String = (x.d.ic + " " + I18n.t(x.d.n)) if x != null else src
	if m < 1:
		_log(I18n.t("%s hits for %d — %s resisted") % [who, roundi(v), I18n.t(el)])
	elif is_crit:
		_log(I18n.t("%s CRITS for %d!") % [who, roundi(v)])
	return v


func add_status(k: String, n: float, uid := -1) -> void:
	if n <= 0 or not GameData.statuses.has(k):
		return
	var s: Dictionary = GameData.statuses[k]
	if s.side == "foe":
		fs[k] = minf(s.max, fs.get(k, 0.0) + n)
		if k == "poison":
			_gain_res("poison_applied", n)
		_num("foe", "%s+%s" % [s.ic, GameData._num(n)], s.col, false, uid)
		if k == "burn" and sp.has("burn_burst") and fs.burn >= 20:
			var v := damage(null, fs.burn, "Fire", 0, 2, "💥")
			stat_dmg["burn"] += v
			fs.burn = 5.0
			_ev({"t": "burst", "v": v})
			_log(I18n.t("💥 Burn explodes for %d!") % roundi(v))
	else:
		hs[k] = minf(s.max, hs.get(k, 0.0) + n)
		_num("hero", "%s+%s" % [s.ic, GameData._num(n)], s.col, false, uid)


func gain_shield(v: float, uid := -1) -> void:
	if v <= 0:
		return
	var before := shield
	shield = minf(_shield_cap(), shield + v)
	_gain_res("shield_gained", v)
	_num("hero", "🛡+" + GameData._num(shield - before if shield - before > 0 else v), Color("#7dd3fc"), false, uid)


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
	var dmg: float = f.dmg + x.ramp
	if sp.has("turret_count") and d.tags.has("Turret"):
		dmg += turrets
	if sp.has("weapon_ramp") and d.tags.has("Weapon"):
		x.ramp += 1.0
	if f.ramp > 0:
		x.ramp += f.ramp
	if d.sp == "shield_dmg":
		dmg += shield * 0.25
	if d.sp == "hp_strike_big":
		dmg += mhp * 0.10
	if dmg > 0:
		damage(x, dmg, f.el if f.el != "" else "Physical", f.crit, f.critx)
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
				add_status("poison", fs.poison)
		"full_charge":
			for y in items:
				if not y.d.once:
					y.p = y.cd
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
	var speed := 1.0 + haste()
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
		x.p += TICK * speed
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
		var dot_mult := 1.0
		var rd := res_def()
		if rd.eff == "dot_pct":
			dot_mult += rd.v * resv
		for k in fs:
			var s: Dictionary = GameData.statuses[k]
			if s.tick <= 0 or fs[k] <= 0 or tk % roundi(s.tick * 10) != 0:
				continue
			var v: float = fs[k] * s.dmg * dot_mult * RunState.elem_mult(e, s.el) * gold_mult
			if k == "poison" and sp.has("poison_crit"):
				v *= _crit(0.25, 3.0)
			if v > 0:
				ehp -= v
				stat_dmg[k] += v
				_num("foe", s.ic + GameData._num(roundf(v * 10) / 10.0), s.col)
			if s.decay > 0 and not (k == "burn" and sp.has("burn_nodecay")):
				fs[k] = maxf(0.0, fs[k] - s.decay)
		# poison / burn the monster put on you
		for k in hd:
			var s: Dictionary = GameData.statuses[k]
			if s.tick <= 0 or hd[k] <= 0 or tk % roundi(s.tick * 10) != 0:
				continue
			var v: float = hd[k] * s.dmg
			php -= v
			_num("hero", s.ic + "-" + GameData._num(roundf(v * 10) / 10.0), s.col)
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
	var fspeed := 1.0 + _foe_haste()
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
	if on.dmg > 0:
		var dm: float = roundf(on.dmg * dm_mult * _crit(on.crit, on.critx) * 10.0) / 10.0
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
		hd[k] = minf(s.max, hd.get(k, 0.0) + n)
		_num("hero", "%s+%s" % [s.ic, GameData._num(n)], s.col)
	if on.shield > 0:
		fshield += roundf(on.shield * sup)
		_num("foe", "🛡️+" + GameData._num(roundf(on.shield * sup)), Color("#7dd3fc"))
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
		var v := damage(null, total, GameData.statuses.thorns.el, 0, 2, "🌵")
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
