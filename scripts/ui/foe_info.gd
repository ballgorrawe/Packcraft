class_name FoeInfo
extends RefCounted
## "What does this monster do?" — the full read-out behind a monster's short badges: its numbers,
## style, pet, Ultimate, skills, boss move, and every item in its pack with the real (scaled) stats.
## Used by the road card's Details button and by tapping the monster in a fight.


## Short chips for a card / the fight header: style, pet, Ultimate, skills, boss move (icon + name only).
static func chips(e: Dictionary) -> Array:
	var out := []
	var st: Dictionary = GameData.foe_styles.get(str(e.get("fam", "")), {})
	if not st.is_empty() and e.get("tier", "") != "boss":
		out.append(st.ic + " " + I18n.t(st.n))
	if GameData.foe_pets.has(str(e.get("pet", ""))):
		var pd: Dictionary = GameData.foe_pets[e.pet]
		out.append(pd.ic + " " + I18n.t(pd.n))
	if not e.get("ult", {}).is_empty():
		out.append("⭐ " + I18n.t(e.ult.n))
	for k in str(e.get("tr", "")).split(",", false):
		if GameData.traits.has(k):
			out.append(GameData.traits[k].ic + " " + I18n.t(GameData.traits[k].n))
	if not e.get("mech", {}).is_empty():
		out.append("⚠️ " + e.mech.ic + " " + I18n.t(e.mech.n))
	return out


## The full panel. `e` should already have today's hazard applied (RunState.with_hazard).
static func build(e: Dictionary, width: float) -> Control:
	var p := UI.panel(Color("#1a1511", 0.98), Color("#c084fc"), 3, 18, 16)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE   # a tap on it reaches whatever closes it
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.custom_minimum_size.x = width - 32.0
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_font_size_override("bold_font_size", 19)
	rt.text = text(e)
	p.add_child(rt)
	return p


static func text(e: Dictionary) -> String:
	var t := "[b][font_size=26]%s %s[/font_size][/b]\n" % [GameData.foe_icon(e.n), I18n.t(e.n)]
	var top := ["❤️ %d" % roundi(e.hp), "⚔️ %.1f/%s" % [float(e.get("dps", 0.0)) * float(e.get("dmg_mult_hz", 1.0)), I18n.t("s")]]
	if e.get("imm", "") != "":
		top.append("🛡️ " + I18n.t("resists %s") % (GameData.elem_icon(e.imm) + I18n.t(e.imm)) + " -80%")
	if e.get("weak", "") != "":
		top.append("💥 " + I18n.t("weak to %s") % (GameData.elem_icon(e.weak) + I18n.t(e.weak)) + " +50%")
	t += "[color=#e9e4ff]" + "   ".join(top) + "[/color]\n"
	var st: Dictionary = GameData.foe_styles.get(str(e.get("fam", "")), {})
	if not st.is_empty() and e.get("tier", "") != "boss":
		t += "\n[b][color=#d8b4fe]%s %s[/color][/b] — %s" % [st.ic, I18n.t(st.n), I18n.t(st.d)]
	if not e.get("mech", {}).is_empty():
		t += "\n[b][color=#ffb86b]⚠️ %s %s[/color][/b] — %s" % [e.mech.ic, I18n.t(e.mech.n), I18n.t(e.mech.d)]
	if GameData.foe_pets.has(str(e.get("pet", ""))):
		var pd: Dictionary = GameData.foe_pets[e.pet]
		t += "\n[b][color=#86efac]%s %s[/color][/b] — %s" % [pd.ic, I18n.t(pd.n), I18n.t(pd.d)]
	if not e.get("ult", {}).is_empty():
		var u: Dictionary = e.ult
		t += "\n[b][color=#ffe14a]⭐ %s %s[/color][/b] (%d ⚡) — %s" % [u.ic, I18n.t(u.n), int(u.need), I18n.t(u.d)]
	for k in str(e.get("tr", "")).split(",", false):
		if GameData.traits.has(k):
			var td: Dictionary = GameData.traits[k]
			t += "\n[b][color=#fca5a5]%s %s[/color][/b]%s" % [td.ic, I18n.t(td.n), (" — " + I18n.t(td.d)) if td.has("d") else _trait_extra(k)]
	# its pack, with the numbers it really hits for today
	var dm: float = float(e.get("dmg_mult", 1.0)) * (1.0 + float(GameData.foe_pets.get(str(e.get("pet", "")), {}).get("dmg", 0.0)))
	var sup: float = float(e.get("sup_mult", 1.0))
	var cdm: float = float(e.get("cd_mult", 1.0))
	var seen := {}
	var lines := []
	for it in e.get("items", []):
		var id: String = it[0]
		if seen.has(id):
			seen[id] += 1
			continue
		seen[id] = 1
		lines.append(id)
	if not lines.is_empty():
		t += "\n\n[b][color=#fde68a]🎒 %s[/color][/b]" % I18n.t("Its pack")
		for id in lines:
			var d: Dictionary = GameData.items[id]
			var on: Dictionary = d.on
			var parts := []
			if on.dmg > 0:
				parts.append("[color=#ff9b5e]⚔️ %s[/color]" % GameData._num(snappedf(on.dmg * dm, 0.1)))
			if on.crit > 0:
				parts.append("🎯 %d%%" % roundi(on.crit * 100))
			for k in on.st:
				var s: Dictionary = GameData.statuses[k]
				parts.append("[color=%s]%s %s[/color]" % [s.col, s.ic, GameData._num(snappedf(on.st[k] * float(e.get("dmg_mult", 1.0)), 0.1))])
			if on.shield > 0:
				parts.append("[color=#7dd3fc]🛡️ %s[/color]" % GameData._num(roundf(on.shield * sup)))
			if on.heal > 0:
				parts.append("[color=#4ade80]💚 %s[/color]" % GameData._num(roundf(on.heal * sup)))
			if not on.haste.is_empty():
				parts.append("💨 +%d%%" % roundi(on.haste[0] * 100))
			var every := ("⏱ " + I18n.t("every %ss") % GameData._num(snappedf(d.cd * cdm, 0.1))) if d.cd > 0 else ""
			t += "\n%s %s%s  %s  [color=#9ca3af]%s[/color]" % [d.ic, I18n.t(d.n), (" ×%d" % seen[id]) if seen[id] > 1 else "", "  ".join(parts), every]
	return t


## Skills without a description line in the data (their effect is on the numbers).
static func _trait_extra(k: String) -> String:
	match k:
		"swift": return " — " + I18n.t("its items charge 30% faster, but hit a bit softer")
		"brute": return " — " + I18n.t("+40% HP and +40% damage, but slower")
		"regen": return " — " + I18n.t("heals 1.5% of its Max HP every second")
	return ""
