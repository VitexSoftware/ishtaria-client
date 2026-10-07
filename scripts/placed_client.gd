extends Node
## Building, farming and fishing: what stands around the player (polled), and the player's
## intentions to place, plant, pick up, harvest and fish. The server decides every outcome.

signal placed_loaded(things: Array)
## An action worked: its kind (`place`, `plant`, `pickup`, `harvest`, `fish`) and the validated reply.
signal done(kind: String, reply: Dictionary)
signal failed(message: String)

const POLL_SECONDS := 4.0

var server_url := ""
## Returns the player's position in metres from the planet's centre, or the zero vector.
var player_metres := Callable()
var _token := ""
var _generation := 0
var _timer: Timer
var _polling := false

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.timeout.connect(poll)
	add_child(_timer)

func start(url: String, token: String) -> void:
	stop()
	server_url = url
	_token = token
	_timer.start()

func stop() -> void:
	_generation += 1
	_token = ""
	_polling = false
	if is_instance_valid(_timer):
		_timer.stop()
	placed_loaded.emit([])

func is_running() -> bool:
	return not _token.is_empty()

# --- validation ---

static func valid_thing(thing: Variant) -> bool:
	if not thing is Dictionary or not (thing.get("id") is float or thing.get("id") is int) or thing.id <= 0:
		return false
	if not thing.get("kind") is String or thing.kind.length() > 40 or not thing.get("model") is String or thing.model.length() > 60:
		return false
	if not thing.get("position") is Array or thing.position.size() != 3:
		return false
	for value: Variant in thing.position:
		if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
			return false
	for key in ["yaw", "scale"]:
		if not (thing.get(key) is float or thing.get(key) is int) or not is_finite(float(thing[key])):
			return false
	if thing.get("owner") != null and (not thing.owner is String or thing.owner.length() > 32):
		return false
	if thing.get("crop") != null:
		var crop: Variant = thing.crop
		if not crop is Dictionary or not (crop.get("growth") is float or crop.get("growth") is int) or crop.growth < 0 or crop.growth > 1 or not crop.get("ripe") is bool:
			return false
	return true

static func valid_things(data: Variant) -> bool:
	if not data is Array or data.size() > 500:
		return false
	for thing: Variant in data:
		if not valid_thing(thing):
			return false
	return true

## An action's reply: a placed thing and a profile, or the items taken and a profile, or a catch.
static func valid_reply(kind: String, data: Variant) -> bool:
	if not data is Dictionary or not data.get("player") is Dictionary:
		return false
	match kind:
		"place", "plant":
			return valid_thing(data.get("object"))
		"pickup", "harvest":
			if not data.get("items") is Array or data.items.size() > 8:
				return false
			for item: Variant in data.items:
				if not item is Dictionary or not item.get("item_id") is String or not item.get("name") is String or not item.get("quantity") is String or not item.quantity.is_valid_int():
					return false
			return true
		"fish":
			return data.get("caught") is bool and data.get("items") is Array and data.items.size() <= 2
	return false

## Message key for a refused action; fixed keys, never the server text.
static func error_key(code: int, text: String) -> String:
	match text.strip_edges():
		"too far to place", "too far away":
			return "Too far away"
		"something is in the way":
			return "Something is in the way"
		"too many placed things":
			return "You have placed too many things"
		"nothing can be placed on water":
			return "Nothing can be placed on water"
		"this is not yours":
			return "This is not yours"
		"not ripe yet":
			return "Not ripe yet"
		"nothing there":
			return "Nothing there"
		"required tool missing":
			return "Hold a fishing rod"
		"no water within reach":
			return "There is no water to fish in"
		"too exhausted":
			return "Too exhausted"
		"inventory is full", "stack is full":
			return "Inventory is full"
		"not enough to pay":
			return "You do not have that"
	return "" if code == 429 else "Action unavailable"

# --- requests ---

func poll() -> void:
	if _polling or _token.is_empty() or not player_metres.is_valid():
		return
	var at: Vector3 = player_metres.call()
	if at == Vector3.ZERO:
		return
	_polling = true
	_send("/world/placed?x=%.2f&y=%.2f&z=%.2f" % [at.x, at.y, at.z], HTTPClient.METHOD_GET, "", func(result: int, code: int, reply: PackedByteArray) -> void:
		_polling = false
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
		if valid_things(data):
			placed_loaded.emit(data)
	)

## Puts a thing from the inventory down at a point in metres from the planet's centre.
func place(item_id: String, at: Vector3, yaw: float) -> void:
	_put("place", item_id, at, yaw)

func plant(seed_id: String, at: Vector3, yaw: float) -> void:
	_put("plant", seed_id, at, yaw)

func _put(kind: String, item_id: String, at: Vector3, yaw: float) -> void:
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]{1,40}$")
	if pattern.search(item_id) == null or not (is_finite(at.x) and is_finite(at.y) and is_finite(at.z) and is_finite(yaw)):
		return
	var body := JSON.stringify({"item_id": item_id, "x": at.x, "y": at.y, "z": at.z, "yaw": fposmod(yaw, TAU)})
	_act(kind, "/players/me/" + kind, body)

func pickup(id: int) -> void:
	if id > 0:
		_act("pickup", "/placed/%d/pickup" % id, "{}")

func harvest(id: int) -> void:
	if id > 0:
		_act("harvest", "/placed/%d/harvest" % id, "{}")

func fish() -> void:
	_act("fish", "/players/me/fish", "{}")

func _act(kind: String, path: String, body: String) -> void:
	_send(path, HTTPClient.METHOD_POST, body, func(result: int, code: int, reply: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS:
			failed.emit("Action unavailable")
			return
		if code >= 400:
			var key := error_key(code, reply.get_string_from_utf8())
			if not key.is_empty():
				failed.emit(key)
			return
		var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
		if valid_reply(kind, data):
			done.emit(kind, data)
			poll()
	)

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
