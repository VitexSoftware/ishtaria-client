extends Node
## Merchants and exchanges between players. Only requests and validated answers live here:
## the server decides every price, every swap and every refusal.

signal goods_loaded(goods: Dictionary)
signal exchange_changed(view: Dictionary)
signal exchange_ended(done: bool)
## Something was bought, sold or swapped: the player's profile changed.
signal changed
signal failed(message: String)

const POLL_SECONDS := 2.0

var server_url := ""
var _token := ""
var _generation := 0
var _npc_id := ""
var _timer: Timer
var _polling := false
var _open := false

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.timeout.connect(poll_exchange)
	add_child(_timer)

func start(url: String, token: String) -> void:
	stop()
	server_url = url
	_token = token

func stop() -> void:
	_generation += 1
	_token = ""
	_npc_id = ""
	_open = false
	_polling = false
	if is_instance_valid(_timer):
		_timer.stop()

func is_running() -> bool:
	return not _token.is_empty()

# --- merchants ---

static func valid_npc_id(id: Variant) -> bool:
	return id is String and not id.is_empty() and id.length() <= 100 and id.to_utf8_buffer().size() == id.length() and not id.contains("/") and not id.contains("?")

static func valid_good(good: Variant) -> bool:
	return good is Dictionary and good.get("item_id") is String and good.item_id.length() <= 64 and good.get("name") is String and good.get("price") is String and good.price.is_valid_int() and int(good.price) > 0

static func valid_goods(data: Variant) -> bool:
	if not data is Dictionary or not data.get("sells") is Array or not data.get("buys") is Array or data.sells.size() > 100 or data.buys.size() > 100:
		return false
	for key in ["sells", "buys"]:
		for good: Variant in data[key]:
			if not valid_good(good):
				return false
	return data.get("daily_limit") is String and data.daily_limit.is_valid_int() and data.get("sold_today") is String and data.sold_today.is_valid_int()

func open_shop(npc_id: String) -> void:
	if valid_npc_id(npc_id):
		_npc_id = npc_id
		_send("/shops/" + npc_id, HTTPClient.METHOD_GET, "", _on_goods)

func buy(item_id: String, quantity: int) -> void:
	_deal("buy", item_id, quantity)

func sell(item_id: String, quantity: int) -> void:
	_deal("sell", item_id, quantity)

func _deal(kind: String, item_id: String, quantity: int) -> void:
	if _npc_id.is_empty() or item_id.is_empty() or item_id.length() > 64 or quantity < 1 or quantity > 1000:
		return
	_send("/shops/%s/%s" % [_npc_id, kind], HTTPClient.METHOD_POST, JSON.stringify({"item_id": item_id, "quantity": quantity}), _after_deal)

func close_shop() -> void:
	_npc_id = ""

func _on_goods(result: int, code: int, reply: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit(shop_error_key(code, reply.get_string_from_utf8()))
		return
	var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
	if valid_goods(data):
		data["npc_id"] = _npc_id
		goods_loaded.emit(data)

func _after_deal(result: int, code: int, reply: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		failed.emit(shop_error_key(code, reply.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else "Trade unavailable")
		return
	changed.emit()
	if not _npc_id.is_empty():
		open_shop(_npc_id)

## Message key for a refused shop action; fixed keys, never the server text.
static func shop_error_key(code: int, text: String) -> String:
	match text.strip_edges():
		"merchant is out of reach":
			return "The merchant is out of reach"
		"not enough to pay":
			return "Not enough gold or items"
		"the merchant pays no more today":
			return "The merchant pays no more today"
		"inventory is full", "stack is full":
			return "Inventory is full"
		"the merchant does not sell this", "the merchant does not buy this":
			return "The merchant does not trade this"
		"invalid quantity":
			return "Invalid quantity"
	return "Too many actions" if code == 429 else "Trade unavailable"

# --- exchanges between players ---

static func valid_stack(stack: Variant) -> bool:
	return stack is Dictionary and stack.get("item_id") is String and stack.item_id.length() <= 64 and stack.get("name") is String and stack.get("quantity") is String and stack.quantity.is_valid_int() and int(stack.quantity) > 0

static func valid_view(data: Variant) -> bool:
	if not data is Dictionary or not data.get("with") is String or data.with.is_empty() or data.with.length() > 32:
		return false
	if not data.get("i_accepted") is bool or not data.get("they_accepted") is bool:
		return false
	for key in ["mine", "theirs"]:
		if not data.get(key) is Array or data[key].size() > 10:
			return false
		for stack: Variant in data[key]:
			if not valid_stack(stack):
				return false
	return true

## Starts an exchange with a player nearby, or shows the one that player started.
func trade_with(name: String) -> void:
	if not preload("res://scripts/social.gd").valid_name(name):
		return
	_send("/trades/current", HTTPClient.METHOD_GET, "", func(result: int, code: int, reply: PackedByteArray) -> void:
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			_on_view(result, code, reply)
		else:
			_send("/trades", HTTPClient.METHOD_POST, JSON.stringify({"with": name}), _on_view)
	)

## Puts exactly these stacks on the table: `[{item_id, quantity}]`.
func offer(items: Array) -> void:
	var clean: Array = []
	for stack: Variant in items:
		if stack is Dictionary and stack.get("item_id") is String and (stack.get("quantity") is int or stack.get("quantity") is float) and stack.quantity >= 1:
			clean.append({"item_id": stack.item_id, "quantity": int(stack.quantity)})
	if clean.size() <= 10:
		_send("/trades/current/offer", HTTPClient.METHOD_PUT, JSON.stringify({"items": clean}), _on_view)

func accept() -> void:
	_send("/trades/current/accept", HTTPClient.METHOD_POST, "{}", _on_accepted)

func cancel() -> void:
	_open = false
	_timer.stop()
	_send("/trades/current", HTTPClient.METHOD_DELETE, "", func(_r: int, _c: int, _b: PackedByteArray) -> void: exchange_ended.emit(false))

func poll_exchange() -> void:
	if _polling or not _open:
		return
	_polling = true
	_send("/trades/current", HTTPClient.METHOD_GET, "", func(result: int, code: int, reply: PackedByteArray) -> void:
		_polling = false
		if result == HTTPRequest.RESULT_SUCCESS and code == 404:
			_end(false)
		else:
			_on_view(result, code, reply, true)
	)

func _end(done: bool) -> void:
	_open = false
	_timer.stop()
	exchange_ended.emit(done)

func _on_view(result: int, code: int, reply: PackedByteArray, quiet := false) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		if not quiet:
			failed.emit(trade_error_key(code, reply.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else "Trade unavailable")
		return
	var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
	if valid_view(data):
		_open = true
		if _timer.is_stopped():
			_timer.start()
		exchange_changed.emit(data)

func _on_accepted(result: int, code: int, reply: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		failed.emit(trade_error_key(code, reply.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else "Trade unavailable")
		poll_exchange()
		return
	var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
	if not data is Dictionary or not data.get("done") is bool:
		return
	if data.done:
		_end(true)
		changed.emit()
	elif valid_view(data.get("trade")):
		exchange_changed.emit(data.trade)

## Message key for a refused exchange action; fixed keys, never the server text.
static func trade_error_key(code: int, text: String) -> String:
	match text.strip_edges():
		"the player is too far away":
			return "That player is too far away"
		"already trading":
			return "Already trading"
		"player not found":
			return "Player not found"
		"you cannot trade with yourself":
			return "You cannot trade with yourself"
		"not enough to offer":
			return "You do not have that much"
		"a worn item cannot be traded":
			return "A worn item cannot be traded"
		"no exchange":
			return "No open exchange"
		"a trader is gone":
			return "The other trader is gone"
		"inventory is full", "stack is full":
			return "Inventory is full"
	return "Too many actions" if code == 429 else "Trade unavailable"

func _send(path: String, method: HTTPClient.Method, body: String, handler: Callable) -> void:
	if _token.is_empty():
		return
	var request := HTTPRequest.new()
	request.timeout = 6.0
	request.max_redirects = 0
	request.body_size_limit = 262144
	add_child(request)
	var generation := _generation
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, reply: PackedByteArray) -> void:
		request.queue_free()
		if generation != _generation:
			return
		handler.call(result, code, reply)
	)
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _token])
	if request.request(server_url + path, headers, method, body) != OK:
		request.queue_free()
		_polling = false
