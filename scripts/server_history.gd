extends Node
## Local history of visited servers with on-demand availability and latency checks.
## Stored only in the client settings file; never contains credentials or tokens.

signal changed
signal probed(url: String)

const SECTION := "servers"
const MAX_ENTRIES := 20
const MAX_PARALLEL := 4
const SAMPLES := 3
const TIMEOUT_SECONDS := 3.0
const MAX_TEXT := 200
const MIN_SERVER_VERSION := "0.1.0"

## Parses a version string into an array of non-negative integers (e.g. "0.1.0" -> [0, 1, 0]).
## Ignores metadata prefixes like -alpha, +build, ~local. Returns empty array on invalid format.
static func parse_version(text: String) -> Array[int]:
	var clean := text.strip_edges()
	if clean.is_empty():
		return []
	for sep in ["-", "+", "~"]:
		if sep in clean:
			clean = clean.split(sep)[0]
	var parts := clean.split(".")
	if parts.is_empty():
		return []
	var numbers: Array[int] = []
	for part in parts:
		if not part.is_valid_int():
			return []
		var val := int(part)
		if val < 0:
			return []
		numbers.append(val)
	return numbers

## Compares two version strings numerically. Returns -1 if a < b, 1 if a > b, 0 if a == b, or -2 if invalid.
static func compare_versions(a_str: String, b_str: String) -> int:
	var a := parse_version(a_str)
	var b := parse_version(b_str)
	if a.is_empty() or b.is_empty():
		return -2
	var count := maxi(a.size(), b.size())
	for i in count:
		var va := a[i] if i < a.size() else 0
		var vb := b[i] if i < b.size() else 0
		if va < vb:
			return -1
		elif va > vb:
			return 1
	return 0

## Checks whether the server version meets the minimum required version.
static func is_server_version_compatible(server_ver: String, min_ver: String = MIN_SERVER_VERSION) -> bool:
	var parsed_server := parse_version(server_ver)
	var parsed_min := parse_version(min_ver)
	if parsed_server.is_empty() or parsed_min.is_empty():
		return false
	if compare_versions(server_ver, min_ver) < 0:
		return false
	if parsed_min[0] > 0 and parsed_server[0] != parsed_min[0]:
		return false
	return true

var settings_path := ""
## Returns the normalized URL, or an empty string when the address is invalid.
var url_validator := Callable()
var entries: Array[Dictionary] = []

var _results := {}
var _generation := 0
var _queue: Array[String] = []

func load_entries() -> void:
	entries.clear()
	var settings := ConfigFile.new()
	if settings.load(settings_path) != OK:
		return
	var stored: Variant = settings.get_value(SECTION, "entries", [])
	if not stored is Array:
		return
	for item in stored:
		var entry := _sanitize(item)
		if not entry.is_empty() and _index_of(entry.url) < 0:
			entries.append(entry)
	_sort_and_trim()

func save() -> int:
	var settings := ConfigFile.new()
	settings.load(settings_path)
	settings.set_value(SECTION, "entries", entries)
	return settings.save(settings_path)

func identity_of(world: Dictionary) -> String:
	var seed_value: Variant = world.get("seed", "")
	if seed_value is float and seed_value == floorf(seed_value):
		seed_value = int(seed_value) # JSON numbers parse as floats
	return "%s|%s|%s" % [world.get("server_name", ""), world.get("ruleset", ""), str(seed_value)]

## Records a successful connection and returns the save result.
func record_connection(url: String, world: Dictionary, source := "manual") -> int:
	var now := int(Time.get_unix_time_from_system())
	var index := _index_of(url)
	var entry: Dictionary
	if index < 0:
		entry = {"url": url, "source": source, "first_seen": now, "last_ok": 0, "latency_ms": -1}
		entries.append(entry)
	else:
		entry = entries[index]
	entry.server_name = _clip(str(world.get("server_name", "")))
	var version_val: Variant = world.get("server_version", world.get("version"))
	if version_val is String and not String(version_val).is_empty():
		entry.server_version = _clip(String(version_val).strip_edges())
	entry.identity = _clip(identity_of(world))
	entry.last_connected = now
	entry.last_ok = now
	_sort_and_trim()
	changed.emit()
	return save()

func forget(url: String) -> void:
	var index := _index_of(url)
	if index < 0:
		return
	entries.remove_at(index)
	_results.erase(url)
	changed.emit()
	save()

func has_entry(url: String) -> bool:
	return _index_of(url) >= 0

## Latest probe result of this session: {"state": "online"|"unreachable"|"changed", "latency_ms": float}.
func result_for(url: String) -> Dictionary:
	return _results.get(url, {})

func is_unencrypted(url: String) -> bool:
	if not url.begins_with("http://"):
		return false
	var host := url.trim_prefix("http://").split("/")[0]
	return not (host.begins_with("127.") or host.begins_with("localhost") or host.begins_with("[::1]"))

## Checks every history entry. Starting a new run supersedes the previous one.
func probe_all() -> void:
	cancel()
	for entry in entries:
		_queue.append(entry.url)
		_results.erase(entry.url)
	changed.emit()
	var generation := _generation
	for i in mini(MAX_PARALLEL, _queue.size()):
		_worker(generation)

## Ignores outstanding probe results; in-flight requests end by their own timeout.
func cancel() -> void:
	_generation += 1
	_queue.clear()

func _worker(generation: int) -> void:
	while generation == _generation and not _queue.is_empty():
		var url: String = _queue.pop_front()
		var result := await _probe(url, generation)
		if generation != _generation:
			return
		_apply_result(url, result)

func _probe(url: String, generation: int) -> Dictionary:
	var samples: Array[float] = []
	for i in SAMPLES:
		var started := Time.get_ticks_usec()
		var reply := await _fetch(url + "/health", 4096)
		if generation != _generation:
			return {}
		if reply.result != HTTPRequest.RESULT_SUCCESS or reply.code != 200:
			return {"state": "unreachable"}
		samples.append((Time.get_ticks_usec() - started) / 1000.0)
	samples.sort()
	var outcome := {"state": "online", "latency_ms": samples[samples.size() / 2]}
	var world_reply := await _fetch(url + "/world", 1024 * 1024)
	if generation != _generation:
		return {}
	if world_reply.result == HTTPRequest.RESULT_SUCCESS and world_reply.code == 200:
		var json := JSON.new()
		if json.parse(world_reply.body.get_string_from_utf8()) == OK and json.data is Dictionary:
			outcome.identity = identity_of(json.data)
			outcome.server_name = str(json.data.get("server_name", ""))
			var version_val: Variant = json.data.get("server_version", json.data.get("version"))
			if version_val is String and not String(version_val).is_empty():
				outcome.server_version = String(version_val).strip_edges()
	return outcome

func _apply_result(url: String, result: Dictionary) -> void:
	var index := _index_of(url)
	if index < 0 or result.is_empty():
		return
	var entry := entries[index]
	if result.state == "online":
		var known: String = entry.get("identity", "")
		if result.has("identity") and not known.is_empty() and result.identity != known:
			result.state = "changed"
		elif result.has("server_version") and not is_server_version_compatible(result.server_version):
			result.state = "incompatible"
		entry.last_ok = int(Time.get_unix_time_from_system())
		entry.latency_ms = roundf(result.latency_ms)
		save()
	_results[url] = result
	probed.emit(url)
	changed.emit()

func _fetch(url: String, size_limit: int) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT_SECONDS
	request.max_redirects = 0
	request.body_size_limit = size_limit
	add_child(request)
	if request.request(url) != OK:
		request.queue_free()
		return {"result": HTTPRequest.RESULT_CANT_CONNECT, "code": 0, "body": PackedByteArray()}
	var completed: Array = await request.request_completed
	request.queue_free()
	return {"result": completed[0], "code": completed[1], "body": completed[3]}

func _index_of(url: String) -> int:
	for i in entries.size():
		if entries[i].url == url:
			return i
	return -1

func _sort_and_trim() -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.last_connected > b.last_connected)
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)

func _clip(text: String) -> String:
	return text.substr(0, MAX_TEXT)

func _sanitize(item: Variant) -> Dictionary:
	if not item is Dictionary or not item.get("url") is String:
		return {}
	var url: String = item.url
	if url_validator.is_valid() and url_validator.call(url) != url:
		return {}
	var source: Variant = item.get("source", "manual")
	return {
		"url": url,
		"server_name": _clip(str(item.get("server_name", ""))),
		"identity": _clip(str(item.get("identity", ""))),
		"source": source if source in ["manual", "invite", "portal", "obituary"] else "manual",
		"first_seen": int(item.get("first_seen", 0)),
		"last_connected": int(item.get("last_connected", 0)),
		"last_ok": int(item.get("last_ok", 0)),
		"latency_ms": float(item.get("latency_ms", -1)),
	}
