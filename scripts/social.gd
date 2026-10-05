extends Node
## Friends and the short-lived events of friends. Polling `/events` also tells the server that
## the player is online. Nothing is stored here: the server forgets what it delivered.

signal friends_changed(friends: Array)
signal requests_changed(incoming: Array, outgoing: Array)
signal event_received(event: Dictionary)
signal failed(message: String)

const POLL_SECONDS := 3.0

var server_url := ""
var _token := ""
var _generation := 0
var _last_event := 0
var _timer: Timer
var _polling := false

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.timeout.connect(poll)
	add_child(_timer)

func is_running() -> bool:
	return not _token.is_empty()

func start(url: String, token: String) -> void:
	stop()
	server_url = url
	_token = token
	_last_event = 0
	_timer.start()
	poll()
	refresh()

func stop() -> void:
	_generation += 1
	_token = ""
	_polling = false
	if is_instance_valid(_timer):
		_timer.stop()
	friends_changed.emit([])
	requests_changed.emit([], [])

## Loads the friends and the open requests.
func refresh() -> void:
	_fetch("/friends", _on_friends)
	_fetch("/friends/requests", _on_requests)

func poll() -> void:
	if _polling or _token.is_empty():
		return
	_polling = true
	_fetch("/events?after=%d" % _last_event, _on_events)

func request_friend(name: String) -> void:
	if valid_name(name):
		_send("/friends/requests", HTTPClient.METHOD_POST, JSON.stringify({"username": name}), _after_change)

func accept(id: int) -> void:
	if id > 0:
		_send("/friends/requests/%d/accept" % id, HTTPClient.METHOD_POST, "{}", _after_change)

func decline(id: int) -> void:
	if id > 0:
		_send("/friends/requests/%d" % id, HTTPClient.METHOD_DELETE, "", _after_change)

func remove(name: String) -> void:
	if valid_name(name):
		_send("/friends/" + name.uri_encode(), HTTPClient.METHOD_DELETE, "", _after_change)

static func valid_name(name: String) -> bool:
	return not name.is_empty() and name.length() <= 32 and not name.contains("/") and not name.contains("?")

## Message key for a refused friend action; fixed keys, never the server text.
static func error_key(code: int, text: String) -> String:
	match text.strip_edges():
		"player not found":
			return "Player not found"
		"you cannot befriend yourself":
			return "You cannot befriend yourself"
		"already friends":
			return "Already friends"
		"too many friends":
			return "Too many friends"
		"too many pending requests":
			return "Too many pending requests"
	return "Too many actions" if code == 429 else "Friend action unavailable"

static func valid_friend(data: Variant) -> bool:
	return data is Dictionary and data.get("name") is String and not data.name.is_empty() and data.name.length() <= 64 and data.get("online") is bool and data.get("world") is String and data.world.length() <= 253 and (data.get("level") is float or data.get("level") is int)

static func valid_request(data: Variant) -> bool:
	return data is Dictionary and (data.get("id") is float or data.get("id") is int) and data.id > 0 and data.get("name") is String and not data.name.is_empty() and data.name.length() <= 64

static func valid_event(data: Variant) -> bool:
	return data is Dictionary and (data.get("id") is float or data.get("id") is int) and data.id > 0 and data.get("kind") == "level_up" and data.get("subject") is String and not data.subject.is_empty() and data.subject.length() <= 64 and (data.get("level") is float or data.get("level") is int) and data.level >= 1

func _fetch(path: String, handler: Callable) -> void:
	_send(path, HTTPClient.METHOD_GET, "", handler)

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
		if path.begins_with("/events"):
			_polling = false

func _on_friends(result: int, code: int, reply: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
	if not data is Array or data.size() > 64:
		return
	var friends: Array = []
	for friend: Variant in data:
		if valid_friend(friend):
			friends.append(friend)
	friends_changed.emit(friends)

func _on_requests(result: int, code: int, reply: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
	if not data is Dictionary or not data.get("incoming") is Array or not data.get("outgoing") is Array:
		return
	var lists: Array = []
	for key in ["incoming", "outgoing"]:
		var valid: Array = []
		for request: Variant in data[key]:
			if valid_request(request) and valid.size() < 50:
				valid.append(request)
		lists.append(valid)
	requests_changed.emit(lists[0], lists[1])

func _on_events(result: int, code: int, reply: PackedByteArray) -> void:
	_polling = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(reply.get_string_from_utf8())
	if not data is Dictionary or not data.get("events") is Array or not (data.get("last") is float or data.get("last") is int):
		return
	for event: Variant in data.events:
		if valid_event(event):
			event_received.emit(event)
	_last_event = maxi(_last_event, int(data.last))

func _after_change(result: int, code: int, reply: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Friend action unavailable")
	elif code >= 400:
		failed.emit(error_key(code, reply.get_string_from_utf8()))
	refresh()
