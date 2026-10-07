extends Node
## Magic: the spells the character knows (fetched), reading scrolls and casting. The server decides
## mana, cooldowns, targets and every effect; the client only sends intentions and shows answers.

signal spells_loaded(known: Dictionary)
## A spell was cast: the validated reply (`spell`, `effect`, `strike`, `target`, `player`).
signal cast_done(reply: Dictionary)
signal learned(spell_id: String)
signal failed(message: String)

var server_url := ""
var _token := ""
var _generation := 0

func start(url: String, token: String) -> void:
	stop()
	server_url = url
	_token = token
	refresh()

func stop() -> void:
	_generation += 1
	_token = ""
	spells_loaded.emit({"mana": 0, "mana_max": 100, "spells": []})

func is_running() -> bool:
	return not _token.is_empty()

# --- validation ---

static func valid_spell(spell: Variant) -> bool:
	if not spell is Dictionary or not spell.get("id") is String or spell.id.is_empty() or spell.id.length() > 40:
		return false
	if not spell.get("name") is String or spell.name.length() > 60 or not spell.get("effect") in ["heal", "refresh", "ward", "bolt"]:
		return false
	for key in ["mana", "cooldown_ms", "range_m", "ready_in_ms"]:
		if not (spell.get(key) is float or spell.get(key) is int) or not is_finite(float(spell[key])) or spell[key] < 0:
			return false
	return spell.mana <= 1000 and spell.range_m <= 100

static func valid_known(data: Variant) -> bool:
	if not data is Dictionary or not data.get("spells") is Array or data.spells.size() > 20:
		return false
	for key in ["mana", "mana_max"]:
		if not (data.get(key) is float or data.get(key) is int) or data[key] < 0 or data[key] > 1000:
			return false
	for spell: Variant in data.spells:
		if not valid_spell(spell):
			return false
	return true

static func valid_cast(data: Variant) -> bool:
	if not data is Dictionary or not data.get("spell") is String or not data.get("effect") in ["heal", "refresh", "ward", "bolt"] or not data.get("player") is Dictionary:
		return false
	var strike: Variant = data.get("strike")
	if strike == null:
		return true
	if not strike is Dictionary or not strike.get("state") in ["hit", "depleted"] or not strike.get("items") is Array or strike.items.size() > 16:
		return false
	for key in ["hits", "hits_required"]:
		if not (strike.get(key) is float or strike.get(key) is int) or strike[key] < 0 or strike[key] > 1000:
			return false
	for item: Variant in strike.items:
		if not item is Dictionary or not item.get("item_id") is String or not item.get("name") is String or not item.get("quantity") is String or not item.quantity.is_valid_int():
			return false
	return preload("res://scripts/player_session.gd").valid_counter(strike.get("counter"))

## Message key for a refused action; fixed keys, never the server text.
static func error_key(code: int, text: String) -> String:
	match text.strip_edges():
		"not enough mana":
			return "Not enough mana"
		"the spell is resting":
			return "The spell is still resting"
		"spell not known":
			return "You do not know that spell"
		"target is out of range", "this spell needs a target":
			return "No target in range"
		"level too low":
			return "Your level is too low for this scroll"
		"spell already known":
			return "You already know this spell"
		"this is not a scroll":
			return "This is not a scroll"
		"animal not found", "animal cannot be hit":
			return "No target in range"
		"not enough to pay":
			return "You do not have that"
	return "" if code == 429 else "Magic unavailable"

# --- requests ---

func refresh() -> void:
	_send("/players/me/spells", HTTPClient.METHOD_GET, "", func(result: int, code: int, reply: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
		if valid_known(data):
			spells_loaded.emit(data)
	)

## Reads a scroll of the inventory.
func learn(item_id: String) -> void:
	var pattern := RegEx.new()
	pattern.compile("^scroll_[a-z0-9_]{1,30}$")
	if pattern.search(item_id) == null:
		return
	_send("/players/me/learn", HTTPClient.METHOD_POST, JSON.stringify({"item_id": item_id}), func(result: int, code: int, reply: PackedByteArray) -> void:
		if not _ok(result, code, reply):
			return
		var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
		if data is Dictionary and data.get("spell") is String:
			learned.emit(data.spell)
			refresh()
	)

## Casts a known spell; a bolt names the animal it is aimed at.
func cast(spell_id: String, object_id := "") -> void:
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]{1,40}$")
	if pattern.search(spell_id) == null or object_id.length() > 100:
		return
	var body := {"spell": spell_id}
	if not object_id.is_empty():
		body["object_id"] = object_id
	_send("/players/me/cast", HTTPClient.METHOD_POST, JSON.stringify(body), func(result: int, code: int, reply: PackedByteArray) -> void:
		if not _ok(result, code, reply):
			refresh()
			return
		var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
		if valid_cast(data):
			cast_done.emit(data)
			refresh()
	)

func _ok(result: int, code: int, reply: PackedByteArray) -> bool:
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Magic unavailable")
		return false
	if code >= 400:
		var key := error_key(code, reply.get_string_from_utf8())
		if not key.is_empty():
			failed.emit(key)
		return false
	return true

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
