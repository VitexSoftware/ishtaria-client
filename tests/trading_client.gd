extends SceneTree
## Checks of the trading client: validation of what the server says, fixed error keys, and the
## windows of a merchant and of an exchange.

var failures := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAILED: " + what)

func _init() -> void:
	var trading := preload("res://scripts/trading.gd")
	_check(trading.valid_npc_id("play:trader") and not trading.valid_npc_id("") and not trading.valid_npc_id("a/b") and not trading.valid_npc_id("a?b") and not trading.valid_npc_id(7), "npc ids")

	var goods := {"npc_id": "x", "sells": [{"item_id": "apple", "name": "Apple", "price": "4"}], "buys": [{"item_id": "hide", "name": "Hide", "price": "5"}], "daily_limit": "400", "sold_today": "20"}
	_check(trading.valid_goods(goods), "goods shape")
	for broken in [{"sells": "no"}, {"daily_limit": "many"}, {"sells": [{"item_id": "a", "name": "A", "price": "0"}]}, {"buys": [{"item_id": "a", "name": "A", "price": 5}]}, {"sold_today": 20}]:
		var copy := goods.duplicate(true)
		copy.merge(broken, true)
		_check(not trading.valid_goods(copy), "malformed goods %s" % broken)
	_check(not trading.valid_goods("text"), "goods must be a dictionary")

	var view := {"with": "boris", "mine": [{"item_id": "hide", "name": "Hide", "quantity": "5"}], "theirs": [], "i_accepted": false, "they_accepted": true}
	_check(trading.valid_view(view), "exchange shape")
	for broken in [{"with": ""}, {"mine": [{"item_id": "hide", "name": "Hide", "quantity": "0"}]}, {"theirs": "x"}, {"i_accepted": 1}, {"mine": [{"item_id": "a", "name": "A", "quantity": "x"}]}]:
		var copy := view.duplicate(true)
		copy.merge(broken, true)
		_check(not trading.valid_view(copy), "malformed exchange %s" % broken)

	_check(trading.shop_error_key(409, "not enough to pay") == "Not enough gold or items" and trading.shop_error_key(500, "SQL boom") == "Trade unavailable" and trading.shop_error_key(429, "") == "Too many actions", "shop error keys never echo server text")
	_check(trading.trade_error_key(403, "the player is too far away") == "That player is too far away" and trading.trade_error_key(500, "<script>") == "Trade unavailable", "trade error keys never echo server text")
	_check(preload("res://scripts/social.gd").valid_event({"id": 4, "kind": "trade", "subject": "anna"}), "a trade invitation event")

	var panel: CanvasLayer = preload("res://scripts/trade_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var bought := []
	var sold := []
	panel.buy_requested.connect(func(id: String, quantity: int) -> void: bought.append([id, quantity]))
	panel.sell_requested.connect(func(id: String, quantity: int) -> void: sold.append([id, quantity]))
	panel.set_profile({"stats": {"gold": "80"}, "inventory": {"items": [{"item_id": "hide", "name": "Hide", "quantity": "6"}, {"item_id": "axe", "name": "Axe", "quantity": "1"}]}})
	panel.show_goods(goods, "Trader")
	_check(panel.visible and panel.mode == "shop", "the shop opens")
	_check(panel.list.find_child("Row_apple", true, false) != null, "goods for sale are listed")
	var owned_row: Node = panel.list.find_child("Row_hide", true, false)
	_check(owned_row != null, "what the player owns and the merchant buys is listed")
	_check(panel.list.find_child("Row_axe", true, false) == null, "what the merchant does not buy is not offered")
	panel.list.find_child("Buy5", true, false).pressed.emit()
	owned_row.find_child("SellAll", true, false).pressed.emit()
	_check(bought == [["apple", 5]] and sold == [["hide", 6]], "buying and selling send the player's intention")
	_check(not panel.accept_button.visible, "no accept button in a shop")

	var offers := []
	var accepted := [0]
	var cancelled := [0]
	panel.offer_requested.connect(func(items: Array) -> void: offers.append(items))
	panel.accept_requested.connect(func() -> void: accepted[0] += 1)
	panel.cancel_requested.connect(func() -> void: cancelled[0] += 1)
	panel.set_profile({"stats": {"gold": "100"}, "inventory": {"items": [{"item_id": "hide", "name": "Hide", "quantity": "8"}]}})
	panel.show_exchange(view)
	_check(panel.mode == "exchange" and panel.accept_button.visible and not panel.accept_button.disabled, "the exchange opens")
	_check(panel.summary.text.contains("boris"), "it says that the other side accepted")
	# Hides 5 of 8 are on the table, three are free; gold is free in full.
	panel.list.find_child("Add10", true, false).pressed.emit()
	_check(offers.size() == 1 and offers[0].has({"item_id": "hide", "quantity": 5}), "the offer is sent whole")
	var hide_row: Node = panel.list.find_child("Row_hide", true, false)
	_check(hide_row != null, "rows exist")
	panel.accept_button.pressed.emit()
	_check(accepted[0] == 1, "accepting is sent")
	view["i_accepted"] = true
	panel.show_exchange(view)
	_check(panel.accept_button.disabled, "after accepting the button waits")
	panel.close_window()
	_check(cancelled[0] == 1 and not panel.visible, "closing the window cancels the exchange")

	print("Trading client checks %s" % ("failed" if failures > 0 else "passed"))
	quit(1 if failures > 0 else 0)
