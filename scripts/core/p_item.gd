class_name PItem
extends RefCounted
## One owned item instance. loc is "grid" (active backpack), "storage" (sideboard) or "held" (being dragged).

var uid := 0
var id := ""
var loc := "storage"
var x := 0
var y := 0
var rot := 0
var starter := false
var pd := 0.0   # permanent bonus damage (forge)
var pc := 0.0   # permanent cooldown reduction fraction (campfire polish)
var paid := -1  # gold paid in the shop (-1 = not bought, e.g. loot or starter)
var gs := 0.0   # permanent bonus Shield (⭐ growth)
var gh := 0.0   # permanent bonus Heal (⭐ growth)
var gst := {}   # permanent bonus statuses per hit (⭐ growth): status -> stacks
var gc := 0     # how many times this ⭐ item has grown (capped by its grow.max)
var b := {}     # buffs from stars and sets, recomputed by RunState.calc()


func def() -> Dictionary:
	return GameData.items[id]


func cells() -> Array:
	var out := []
	for c in GameData.shape(id, rot).c:
		out.append(Vector2i(x, y) + c)
	return out


## Takes over another item's permanent upgrades (fusions and evolutions keep the growth).
func absorb(q: PItem) -> void:
	pd += q.pd
	gs += q.gs
	gh += q.gh
	for k in q.gst:
		gst[k] = gst.get(k, 0.0) + q.gst[k]
	gc = maxi(gc, q.gc)


## Adds one growth step (v) to this item's main number (damage, else Shield, else Heal, else its status).
func grow_main(v: float) -> String:
	var on: Dictionary = def().on
	if on.dmg > 0:
		pd += v
		return "⚔️"
	if on.shield > 0:
		gs += v
		return "🛡️"
	if on.heal > 0:
		gh += v
		return "💚"
	for k in on.st:
		gst[k] = gst.get(k, 0.0) + v
		return GameData.statuses[k].ic
	return ""
