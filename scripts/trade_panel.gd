extends CanvasLayer
## The window of a merchant (buy and sell for gold) and of an exchange between two players
## (each puts items on the table, both accept). It only shows what the server says and sends
## the player's intentions; prices, limits and the swap itself are the server's.

signal buy_requested(item_id: String, quantity: int)
signal sell_requested(item_id: String, quantity: int)
## The whole offer of the player: `[{item_id, quantity}]`.
signal offer_requested(items: Array)
signal accept_requested
signal cancel_requested
signal closed

const ITEM_ICONS := preload("res://scripts/item_icons.gd")

var panel: PanelContainer
var title: Label
var summary: Label
var feedback: Label
var list: VBoxContainer
var accept_button: Button
## `shop`, `exchange` or empty while closed.
var mode := ""
var _goods: Dictionary = {}
var _view: Dictionary = {}
var _profile: Dictionary = {}
var _merchant_name := ""
var _feedback_key := ""

func _ready() -> void:
	layer = 4
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.7)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	panel = PanelContainer.new()
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.14)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	title = Label.new()
	title.name = "Title"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.text = tr("Close")
	close.pressed.connect(close_window)
	header.add_child(close)
	summary = Label.new()
	summary.name = "Summary"
	summary.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	accept_button = Button.new()
	accept_button.name = "Accept"
	accept_button.custom_minimum_size.y = 40
	accept_button.pressed.connect(func() -> void:
		set_feedback("")
		accept_requested.emit()
	)
	column.add_child(accept_button)
	feedback = Label.new()
	feedback.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	column.add_child(feedback)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var dimensions := Vector2(minf(660, screen.x - 24), minf(620, screen.y - 24))
	panel.position = (screen - dimensions) / 2
	panel.size = dimensions

func set_profile(profile: Dictionary) -> void:
	_profile = profile.duplicate(true)
	if visible:
		_render()

func set_feedback(key: String) -> void:
	_feedback_key = key
	feedback.text = tr(key) if not key.is_empty() else ""

func is_open() -> bool:
	return visible

## Closing a window ends an open exchange (the other player is told by the server's answer).
func close_window() -> void:
	var was := mode
	mode = ""
	hide()
	if was == "exchange":
		cancel_requested.emit()
	closed.emit()

func show_goods(goods: Dictionary, merchant_name: String) -> void:
	_goods = goods.duplicate(true)
	_merchant_name = merchant_name
	mode = "shop"
	show()
	_render()

func show_exchange(view: Dictionary) -> void:
	_view = view.duplicate(true)
	mode = "exchange"
	show()
	_render()

## The exchange is over (done or cancelled by the other side).
func end_exchange(done: bool) -> void:
	if mode != "exchange":
		return
	mode = ""
	hide()
	closed.emit()

# --- rendering ---

func _owned() -> Array:
	var items: Array = []
	var gold := str(_profile.get("stats", {}).get("gold", "0"))
	if gold.is_valid_int() and int(gold) > 0:
		items.append({"item_id": "gold", "name": "Gold", "quantity": gold})
	for item: Variant in _profile.get("inventory", {}).get("items", []):
		if item is Dictionary and item.get("item_id") is String and str(item.get("quantity", "0")).is_valid_int():
			items.append(item)
	return items

func _quantity_of(item_id: String) -> int:
	for item: Dictionary in _owned():
		if item.item_id == item_id:
			return int(item.quantity)
	return 0

func _clear() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

func _heading(text: String) -> void:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.35))
	label.add_theme_font_size_override("font_size", 17)
	list.add_child(label)

func _row(item_id: String, text: String, buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_" + item_id
	row.add_theme_constant_override("separation", 8)
	list.add_child(row)
	var picture := ITEM_ICONS.texture(item_id)
	var icon := TextureRect.new()
	icon.texture = picture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(36, 36)
	row.add_child(icon)
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	for entry: Dictionary in buttons:
		var button := Button.new()
		button.name = entry.name
		button.text = entry.text
		button.custom_minimum_size = Vector2(72, 34)
		button.pressed.connect(func() -> void:
			set_feedback("")
			entry.action.call()
		)
		row.add_child(button)

func _render() -> void:
	if not is_instance_valid(list):
		return
	_clear()
	accept_button.visible = mode == "exchange"
	if mode == "shop":
		_render_shop()
	elif mode == "exchange":
		_render_exchange()

func _render_shop() -> void:
	title.text = _merchant_name
	var gold := str(_profile.get("stats", {}).get("gold", "0"))
	summary.text = tr("Gold: %s") % gold + "  ·  " + tr("Sold today: %s / %s") % [_goods.get("sold_today", "0"), _goods.get("daily_limit", "0")]
	_heading(tr("Buy"))
	for good: Dictionary in _goods.get("sells", []):
		var id: String = good.item_id
		_row(id, "%s — %s %s" % [tr(good.name), good.price, tr("gold")], [
			{"name": "Buy1", "text": tr("Buy 1"), "action": func() -> void: buy_requested.emit(id, 1)},
			{"name": "Buy5", "text": tr("Buy 5"), "action": func() -> void: buy_requested.emit(id, 5)},
		])
	_heading(tr("Sell"))
	var any := false
	for good: Dictionary in _goods.get("buys", []):
		var id: String = good.item_id
		var owned := _quantity_of(id)
		if owned <= 0:
			continue
		any = true
		_row(id, "%s x %s — %s %s" % [tr(good.name), owned, good.price, tr("gold")], [
			{"name": "Sell1", "text": tr("Sell 1"), "action": func() -> void: sell_requested.emit(id, 1)},
			{"name": "SellAll", "text": tr("Sell all"), "action": func() -> void: sell_requested.emit(id, mini(owned, 1000))},
		])
	if not any:
		_heading(tr("You have nothing this merchant buys."))

func _render_exchange() -> void:
	title.text = tr("Trade with %s") % _view.get("with", "")
	summary.text = tr("Both must accept; changing an offer withdraws the acceptance.")
	var offered := {}
	for stack: Dictionary in _view.get("mine", []):
		offered[stack.item_id] = int(stack.quantity)
	_heading(tr("Your offer"))
	for stack: Dictionary in _view.get("mine", []):
		var id: String = stack.item_id
		_row(id, "%s x %s" % [tr(stack.name), stack.quantity], [
			{"name": "Remove", "text": tr("Remove"), "action": func() -> void: _change(id, -int(offered.get(id, 0)))},
		])
	_heading(tr("Their offer"))
	for stack: Dictionary in _view.get("theirs", []):
		_row(stack.item_id, "%s x %s" % [tr(stack.name), stack.quantity], [])
	_heading(tr("Your things"))
	for item: Dictionary in _owned():
		var id: String = item.item_id
		var free := int(item.quantity) - int(offered.get(id, 0))
		if free <= 0:
			continue
		_row(id, "%s x %s" % [tr(item.name), free], [
			{"name": "Add1", "text": "+1", "action": func() -> void: _change(id, 1)},
			{"name": "Add10", "text": "+10", "action": func() -> void: _change(id, mini(10, free))},
		])
	accept_button.text = tr("Accepted — waiting for them") if _view.get("i_accepted", false) else tr("Accept")
	accept_button.disabled = _view.get("i_accepted", false)
	if _view.get("they_accepted", false):
		summary.text += "\n" + tr("%s has accepted.") % _view.get("with", "")

## Changes the offer of `item_id` by `delta` and sends the whole offer.
func _change(item_id: String, delta: int) -> void:
	var offer := {}
	for stack: Dictionary in _view.get("mine", []):
		offer[stack.item_id] = int(stack.quantity)
	offer[item_id] = maxi(0, int(offer.get(item_id, 0)) + delta)
	var items: Array = []
	for id: String in offer:
		if offer[id] > 0:
			items.append({"item_id": id, "quantity": offer[id]})
	offer_requested.emit(items)
