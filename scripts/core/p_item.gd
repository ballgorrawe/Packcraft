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
var b := {}     # buffs from stars and sets, recomputed by RunState.calc()


func def() -> Dictionary:
	return GameData.items[id]


func cells() -> Array:
	var out := []
	for c in GameData.shape(id, rot).c:
		out.append(Vector2i(x, y) + c)
	return out
