extends Node
## The story of the connected world: dialogues with characters, the translations the
## server hands out for every language, and the portraits and music of a conversation.
## The server decides everything; this node sends the player's choice and shows the answer.
## The language is the client's own: the server only ever sees translation keys.

signal dialogue_changed(reply: Dictionary)
signal failed(message: String)
signal strings_changed
## The player's quests, each {quest, title_key, stage, text_key, final}; sent when they change.
signal quests_changed(quests: Array)
## A portrait (Texture2D) or a track (AudioStream) finished loading.
signal media_ready(url: String, resource: Resource)

const MAX_STRINGS_BYTES := 4194304
const MAX_IMAGE_BYTES := 2097152
const MAX_AUDIO_BYTES := 10485760
const MAX_CACHED_MEDIA := 32
const MAX_MODEL_BYTES := 4194304
const QUEST_POLL_SECONDS := 6.0

var server_url := ""
var _token := ""
var _generation := 0
var _strings: Dictionary = {}
var _media: Dictionary = {}
var _pending_media: Dictionary = {}
var _busy := false
var _quests: Array = []
var _quests_loaded := false
var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = QUEST_POLL_SECONDS
	_timer.timeout.connect(load_quests)
	add_child(_timer)

func is_running() -> bool:
	return not _token.is_empty()

func start_session(url: String, token: String) -> void:
	stop()
	server_url = url
	_token = token
	_quests = []
	_quests_loaded = false
	load_strings()
	load_quests()
	_timer.start()

func stop() -> void:
	_generation += 1
	_token = ""
	_busy = false
	_quests = []
	_quests_loaded = false
	if is_instance_valid(_timer):
		_timer.stop()
	_strings = {}
	_pending_media.clear()
	_media.clear()
	for child in get_children():
		if child != _timer:
			child.queue_free()

## Text for a translation key in the player's language (English when missing, the key
## itself when unknown). `args` are substituted for `%s` after translation.
func text(key: String, args: Array = []) -> String:
	var language := TranslationServer.get_locale().substr(0, 2)
	var table: Variant = _strings.get(language, _strings.get("en", {}))
	var found: String = key
	if table is Dictionary and table.get(key) is String:
		found = table[key]
	elif _strings.get("en") is Dictionary and _strings.en.get(key) is String:
		found = _strings.en[key]
	# The name is data and goes in last, after any `%s` of the text has been filled.
	return substitute_player(found % args if not args.is_empty() else found, player_name)

## The name the player chose when creating the character; `{player}` in a story text becomes it.
var player_name := ""

static func substitute_player(text: String, name: String) -> String:
	if not text.contains("{player}"):
		return text
	return text.replace("{player}", name if not name.is_empty() else "…")

static func valid_strings(data: Variant) -> bool:
	if not data is Dictionary or not data.get("languages") is Dictionary or data.languages.size() > 8:
		return false
	for language: Variant in data.languages:
		if not language is String or language.length() != 2 or not data.languages[language] is Dictionary:
			return false
		for key: Variant in data.languages[language]:
			if not key is String or key.length() > 160 or not data.languages[language][key] is String or data.languages[language][key].length() > 2000:
				return false
	return true

static func valid_media_url(url: Variant) -> bool:
	if not url is String or not url.begins_with("/story/media/") or url.length() > 220 or url.contains("..") or url.contains("//") or url.contains("?") or url.contains("#") or url.contains("%") or url.contains("\\"):
		return false
	return url.ends_with(".png") or url.ends_with(".jpg") or url.ends_with(".ogg") or url.ends_with(".glb")

## A dialogue answer the server sent, or false when anything is missing or malformed.
static func valid_reply(data: Variant) -> bool:
	if not data is Dictionary or not data.get("npc_id") is String or not data.get("name_key") is String or not data.get("open") is bool:
		return false
	if not (data.get("seq") is float or data.get("seq") is int):
		return false
	if data.get("portrait") != null and not valid_media_url(data.portrait):
		return false
	if data.get("music") != null:
		if not data.music is Dictionary or not valid_media_url(data.music.get("url")) or not data.music.get("title_key") is String or not data.music.get("loop") is bool:
			return false
	if not data.open:
		return true
	var node: Variant = data.get("node")
	if not node is Dictionary or not node.get("node") is String or not node.get("text_key") is String or not node.get("choices") is Array or node.choices.size() > 8:
		return false
	if node.get("voice") != null and (not node.voice is String or not valid_media_url(node.voice)):
		return false
	for choice: Variant in node.choices:
		if not choice is Dictionary or not (choice.get("index") is float or choice.get("index") is int) or not choice.get("text_key") is String:
			return false
	return true

func load_strings() -> void:
	_send("/story/strings", HTTPClient.METHOD_GET, "", _on_strings, MAX_STRINGS_BYTES)

## Asks for the quest log; the server also moves on quests that wait for the player to reach a place.
func load_quests() -> void:
	_send("/story/quests", HTTPClient.METHOD_GET, "", _on_quests)

static func valid_quests(data: Variant) -> bool:
	if not data is Array or data.size() > 64:
		return false
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("quest") is String or not entry.get("title_key") is String or not entry.get("stage") is String or not entry.get("text_key") is String or not entry.get("final") is bool:
			return false
	return true

func _on_quests(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if valid_quests(data) and (data != _quests or not _quests_loaded):
		_quests = data
		_quests_loaded = true
		quests_changed.emit(_quests)

## The language of the interface, sent with a dialogue request only so the server can pick the
## spoken line; it is never stored there.
static func _language() -> String:
	return TranslationServer.get_locale().substr(0, 2)

func start(npc_id: String) -> void:
	if _busy:
		return
	_busy = true
	_send("/story/dialogue/start", HTTPClient.METHOD_POST, JSON.stringify({"npc_id": npc_id, "lang": _language()}), _on_reply)

func choose(npc_id: String, seq: int, choice: int) -> void:
	if _busy:
		return
	_busy = true
	_send("/story/dialogue/choose", HTTPClient.METHOD_POST, JSON.stringify({"npc_id": npc_id, "seq": seq, "choice": choice, "lang": _language()}), _on_reply)

## Ends the open conversation (the player pressed escape or walked away).
func leave() -> void:
	if not _token.is_empty():
		_send("/story/dialogue", HTTPClient.METHOD_DELETE, "", func(_result: int, _code: int, _body: PackedByteArray) -> void: pass)

## Message key for a refused dialogue request; fixed keys, never the server text.
static func error_key(code: int, text: String) -> String:
	match text.strip_edges():
		"character is out of reach":
			return "Too far away to talk"
		"not enough to pay":
			return "Not enough gold"
		"inventory is full", "stack is full":
			return "Inventory is full"
	return "Conversation unavailable"

func _on_reply(result: int, code: int, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit(error_key(code, body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else "Conversation unavailable")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not valid_reply(data):
		failed.emit("Conversation unavailable")
		return
	dialogue_changed.emit(data)

func _on_strings(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not valid_strings(data):
		return
	_strings = data.languages
	strings_changed.emit()

## Fetches a portrait or a track once; later calls answer from memory. A missing or
## broken file is simply never announced, so a conversation never waits for its media.
func fetch_media(url: String) -> void:
	if not valid_media_url(url):
		return
	if _media.has(url):
		media_ready.emit(url, _media[url])
		return
	if _pending_media.has(url) or _token.is_empty():
		return
	_pending_media[url] = true
	var limit := MAX_MODEL_BYTES if url.ends_with(".glb") else (MAX_AUDIO_BYTES if url.ends_with(".ogg") else MAX_IMAGE_BYTES)
	var generation := _generation
	var request := HTTPRequest.new()
	request.timeout = 15.0
	request.max_redirects = 0
	request.body_size_limit = limit
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if generation != _generation:
			return
		_pending_media.erase(url)
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var resource := decode_media(url, body)
		if resource == null:
			return
		if _media.size() >= MAX_CACHED_MEDIA:
			_media.erase(_media.keys()[0])
		_media[url] = resource
		media_ready.emit(url, resource)
	)
	if request.request(server_url + url) != OK:
		request.queue_free()
		_pending_media.erase(url)

static func decode_media(url: String, body: PackedByteArray) -> Resource:
	if url.ends_with(".glb"):
		return decode_model(body)
	if url.ends_with(".ogg"):
		var stream := AudioStreamOggVorbis.load_from_buffer(body)
		return stream
	var image := Image.new()
	var error := image.load_png_from_buffer(body) if url.ends_with(".png") else image.load_jpg_from_buffer(body)
	if error != OK or image.get_width() > 2048 or image.get_height() > 2048:
		return null
	return ImageTexture.create_from_image(image)

## A character model (a self-contained glTF binary) as a scene to instantiate, or null when
## it is broken. Nothing outside the buffer is ever read.
static func decode_model(body: PackedByteArray) -> PackedScene:
	if body.size() < 20 or body.slice(0, 4).get_string_from_ascii() != "glTF":
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(body, "", state) != OK:
		return null
	var root := document.generate_scene(state)
	if root == null:
		return null
	var scene := PackedScene.new()
	var packed := scene.pack(root) == OK
	root.free()
	return scene if packed else null

func _send(path: String, method: HTTPClient.Method, body: String, handler: Callable, limit := 262144) -> void:
	if _token.is_empty():
		_busy = false
		return
	var request := HTTPRequest.new()
	request.timeout = 8.0
	request.max_redirects = 0
	request.body_size_limit = limit
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
		_busy = false
