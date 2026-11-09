class_name CombatSim
extends RefCounted
## Real-time auto-battle at 0.1 s ticks. step() advances one tick and queues
## visual events in `events` for the combat view to animate.

const TICK := 0.1
const FATIGUE_TICK := 250   # 25 s

var run: RunState
var node: Dictionary
var e: Dictionary
var ehp := 0.0
var php := 0.0
var mhp := 60.0
var blk := 0.0
var blocked := 0.0
var tk := 0
var pet_dmg := 0.0
var et := 0.0
var hv := 0.0   # haste value
var ht := 0     # haste ticks left
var fzc := 0    # freeze cooldown ticks
var rg := 0.0
var s := {"burn": 0.0, "pois": 0.0, "chill": 0, "frz": 0}
var stat_dmg := {"burn": 0.0, "pois": 0.0}
var done := false
var won := false
var log_lines: Array = []
var items: Array = []    # {i: PItem, d, f, t, cdT, used, st:{dmg, heal, hits}}
var events: Array = []


func _init(r: RunState, n: Dictionary) -> void:
	run = r
	node = n
	e = r.with_hazard(n.e)
	ehp = e.hp
	php = r.hp
	mhp = r.mhp
	rg = r.regen()
	for i in r.grid_items():
		var d: Dictionary = i.def()
		if d.type in ["atk", "def", "heal"]:
			var f := r.eff(i)
			items.append({"i": i, "d": d, "f": f, "t": 0.0, "cdT": roundi(f.cd * 10), "used": false, "st": {"dmg": 0.0, "heal": 0.0, "hits": 0}})


func _ev(ev: Dictionary) -> void:
	events.append(ev)


func _log(t: String) -> void:
	log_lines.push_front(t)
	if log_lines.size() > 6:
		log_lines.resize(6)


func _num(side: String, text: String, col: Color, big := false) -> void:
	_ev({"t": "num", "side": side, "text": text, "col": col, "big": big})


func _heal_mult() -> float:
	return 0.5 if run.mod.id == "blood" else 1.0


func _block_cap() -> float:
	return 30.0 + run.day * 3


func apply_fx(x: Dictionary) -> void:
	var f: Dictionary = x.d.fx
	var b: Dictionary = x.i.b
	var bs := 0.5 if node.k == "boss" else 1.0
	var t := []
	var bn: float = f.get("burn", 0.0) + b.get("burn", 0.0)
	var pn: float = f.get("pois", 0.0) + b.get("pois", 0.0)
	var cs: float = f.get("chill", 0.0) + b.get("chill", 0.0)
	if bn > 0:
		s.burn = minf(30.0, s.burn + bn)
		t.append("🔥+" + GameData._num(bn))
	if pn > 0:
		s.pois = minf(40.0, s.pois + pn)
		t.append("☠️+" + GameData._num(pn))
	if cs > 0:
		s.chill = maxi(s.chill, roundi(cs * 10 * bs))
		t.append("❄️")
	if f.has("frz") and s.frz <= 0 and fzc <= 0:
		s.frz = roundi(f.frz * 10 * bs)
		fzc = 60
		t.append("🧊")
	if f.has("haste"):
		hv = maxf(hv, f.haste[0])
		ht = maxi(ht, roundi(f.haste[1] * 10))
		_num("hero", "⚡+%d%%" % roundi(f.haste[0] * 100), Color("#ffe14a"))
	if t.size() > 0:
		_num("foe", " ".join(t), Color.WHITE)


func hit(x, dmg: float, dt: String, src: String) -> void:
	var m := RunState.elem_mult(e, dt)
	var v := 0.0
	if m > 0:
		v = maxf(1.0, roundf(dmg * m) - (3.0 if e.tr == "armored" else 0.0))
	ehp -= v
	if x != null:
		x.st.dmg += v
	else:
		pet_dmg += v
	_ev({"t": "hit", "uid": x.i.uid if x != null else -1, "melee": x != null and x.d.tags.has("Melee"), "icon": x.d.ic if x != null else run.pet_def().ic, "v": v, "dt": dt, "m": m})
	if x != null and m > 0:
		apply_fx(x)
	if x != null and m > 0 and x.d.ls > 0:
		php = minf(mhp, php + v * x.d.ls * _heal_mult())
	var who: String = (x.d.ic + " " + x.d.n) if x != null else src
	if m < 1:
		_log("%s hits for %d — %s resisted" % [who, roundi(v), dt])
	else:
		_log("%s hits for %d%s" % [who, roundi(v), " — weakness!" if m > 1 else ""])


func step() -> void:
	if done:
		return
	tk += 1
	for x in items:
		var d: Dictionary = x.d
		if d.type == "heal":
			if not x.used and php < mhp * 0.5:
				x.used = true
				var h := minf(d.heal * _heal_mult(), mhp - php)
				php += h
				x.st.heal += h
				x.st.hits += 1
				_ev({"t": "pulse", "uid": x.i.uid})
				_num("hero", "+%d" % roundi(h), Color("#4ade80"))
				apply_fx(x)
				_log("🧪 healed %d" % roundi(h))
			continue
		x.t += 1.0 + (hv if ht > 0 else 0.0)
		if x.t >= x.cdT:
			x.t = 0.0
			x.st.hits += 1
			_ev({"t": "pulse", "uid": x.i.uid})
			if d.type == "atk":
				hit(x, x.f.dmg, d.dt, "")
			else:
				blk = minf(_block_cap(), blk + x.f.blk)
				apply_fx(x)
				_num("hero", "+" + GameData._num(x.f.blk), Color("#7dd3fc"))
				_log("🛡️ +%s block" % GameData._num(x.f.blk))
	# companion
	var p := run.pet_def()
	if p.cd > 0 and tk % roundi(p.cd * 10) == 0:
		match p.k:
			"dmg":
				hit(null, p.v, p.dt, p.ic + " " + p.n)
			"blk":
				blk = minf(_block_cap(), blk + p.v)
				_num("hero", "+" + GameData._num(p.v), Color("#7dd3fc"))
			"heal":
				var h := minf(p.v * _heal_mult(), mhp - php)
				php += h
				_num("hero", "+" + GameData._num(h), Color("#4ade80"))
	# once per second: regen, burn, poison, enemy regen
	if tk % 10 == 0:
		if rg > 0 and php < mhp:
			var h := minf(rg * _heal_mult(), mhp - php)
			php += h
			if h >= 1:
				_num("hero", "+%d" % roundi(h), Color("#4ade80"))
		if s.burn > 0:
			var v: float = s.burn * (RunState.RESIST if e.imm == "Fire" else 1.0)
			ehp -= v
			stat_dmg.burn += v
			_num("foe", "🔥" + GameData._num(v), Color("#ff8a3d"))
		if s.pois > 0:
			var v: float = s.pois * 0.5 * (RunState.RESIST if e.imm == "Nature" else 1.0)
			ehp -= v
			stat_dmg.pois += v
			_num("foe", "☠️" + GameData._num(v), Color("#86efac"))
		if e.tr == "regen" and ehp < e.hp:
			var v := maxf(1.0, roundf(e.hp * 0.015))
			ehp = minf(e.hp, ehp + v)
			_num("foe", "+%d" % roundi(v), Color("#4ade80"))
		if tk % 20 == 0 and s.burn > 0:
			s.burn -= 1
	if s.chill > 0: s.chill -= 1
	if s.frz > 0: s.frz -= 1
	if ht > 0: ht -= 1
	if fzc > 0: fzc -= 1
	# enemy attack
	if s.frz <= 0:
		et += 0.7 if s.chill > 0 else 1.0
	if et >= roundi(e.cd * 10):
		et = 0.0
		var dm: float = e.atk
		var ab := minf(blk, dm * 0.75)
		blk -= ab
		blocked += ab
		php -= dm - ab
		_ev({"t": "foe_atk", "dm": dm, "ab": ab})
	# sudden-death fatigue
	if tk > FATIGUE_TICK and tk % 10 == 0:
		var fd := (tk - FATIGUE_TICK) / 10.0
		php -= fd
		ehp -= fd
		_ev({"t": "fatigue"})
		_log("☠️ Fatigue: %d true damage to both" % roundi(fd))
	if ehp <= 0:
		_finish(true)
	elif php <= 0:
		_finish(false)


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
