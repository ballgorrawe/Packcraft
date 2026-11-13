extends SceneTree
## Gambling den: each visit is one of three games; high-low dice and the roulette wheel pay and
## punish as their screens say, and leaving settles the game.
## Run: godot --headless --path . --script res://tests/gamble_test.gd

var fails := 0


func _initialize() -> void:
	GameData.ensure_loaded()
	seed(9)
	var seen := {}
	for i in 40:
		var r := _den()
		seen[r.event.game] = true
	_check(seen.size() == 3, "all three games come up (%s)" % str(seen.keys()))
	# dice: a right guess grows the pot, a wrong one costs HP and the pot
	var d := _den("dice")
	var hp0 := d.hp
	var res := ""
	for _i in 60:
		var hi: bool = d.event.die <= 3
		res = d.ev_dice(hi)
		if res in ["lose", "max"]:
			break
	_check(res in ["lose", "max"], "dice ends in a loss or five right guesses")
	if res == "lose":
		_check(d.hp < hp0 and d.event.done, "a wrong guess costs HP and ends the game")
	var d2 := _den("dice")
	d2.event.die = 1
	var g0 := d2.gold
	while d2.ev_dice(true) == "same":
		d2.event.die = 1
	_check(d2.event.wins == 1 and d2.event.pot > 0, "from a 1, higher always wins")
	var pot2: int = d2.event.pot
	d2.ev_leave()
	_check(d2.gold == g0 + pot2, "leaving takes the pot (%d -> %d, pot %d)" % [g0, d2.gold, pot2])
	# wheel: the stake leaves, a win pays 2x or 12x, three spins at most
	var w := _den("wheel")
	w.gold = 100
	var slot := w.ev_spin("red", 10)
	var won := RunState.wheel_color(slot) == "red"
	_check(w.gold == (110 if won else 90), "a red bet pays 2x or loses the stake (slot %d, gold %d)" % [slot, w.gold])
	w.ev_spin("green", 5)
	w.ev_spin("black", 5)
	_check(w.event.done and w.ev_spin("red", 5) == -1, "three spins, then the wheel is done")
	_check(w.gold == 100 + w.event.net, "the wheel's net matches the gold")
	_check(_den("wheel").ev_spin("red", 9999) == -1, "no bet above your gold")
	print("GAMBLE TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _den(game := "") -> RunState:
	var r := RunState.new("ember", "", "normal")
	r.day = 8
	r.nodes = [{"k": "roulette"}]
	r.travel()
	r.choose(0)
	if game != "":
		r.event.game = game
		r.event.merge({"die": 3, "wins": 0, "spins": 0, "net": 0, "bullet": 3, "pulls": 0}, false)
	return r


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		fails += 1
