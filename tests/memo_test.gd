extends SceneTree
## Screen part reuse (main._memo): a part is kept only while what it shows is unchanged, and rebuilt as
## soon as anything it shows changes (no stale gold, shop, storage or HUD).
## Run: godot --path . --resolution 720x1280 --script res://tests/memo_test.gd

var fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main._dev = true
	root.add_child(main)
	await process_frame
	seed(4)
	var r := RunState.new("rogue", "cat", "normal")
	r.gold = 40
	main.run = r
	main.render()
	await process_frame
	var shop0: Control = main._memo_nodes.shop.node
	var hud0: Control = main._memo_nodes.hud.node
	var store0: Control = main._memo_nodes.storage.node
	# a tap in the pack: select an item -> HUD and shop are reused
	main.selected = r.grid_items()[0]
	main.render()
	await process_frame
	_check(main._memo_nodes.shop.node == shop0 and is_instance_valid(shop0), "selecting in the pack keeps the shop")
	_check(main._memo_nodes.hud.node == hud0, "selecting in the pack keeps the HUD")
	_check(main._memo_nodes.storage.node != store0, "the storage box follows the selection")
	_check(main.sell_zone == shop0 and main.sell_lbl != null, "the shop's drop zone still points at the shop")
	# gold changes -> shop and HUD rebuilt
	r.gold -= 5
	main.render()
	await process_frame
	_check(main._memo_nodes.shop.node != shop0, "gold changed: the shop is rebuilt")
	_check(main._memo_nodes.hud.node != hud0, "gold changed: the HUD is rebuilt")
	# buying moves an item: the storage box and the shop change
	var shop1: Control = main._memo_nodes.shop.node
	var store1: Control = main._memo_nodes.storage.node
	for i in r.shop.size():
		if not r.shop[i].has("bag") and r.shop[i].price <= r.gold:
			var it := r.buy_item(i)
			it.loc = "storage"
			break
	main.render()
	await process_frame
	_check(main._memo_nodes.shop.node != shop1, "bought: the shop is rebuilt")
	_check(main._memo_nodes.storage.node != store1, "bought into storage: the storage box is rebuilt")
	# locking a card changes the shop
	var shop2: Control = main._memo_nodes.shop.node
	r.toggle_lock(0)
	main.render()
	await process_frame
	_check(main._memo_nodes.shop.node != shop2, "locking a card rebuilds the shop")
	print("MEMO TEST: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1
