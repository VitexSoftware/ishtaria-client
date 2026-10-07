extends Node3D
## Other players standing near the player. The server lists them (`/players/nearby`, about
## once a second); between two answers they are moved smoothly from where they were drawn to
## where the server says they are. Nothing is trusted beyond looks: a malformed entry is skipped.

const CHARACTERS := preload("res://scripts/character_catalog.gd")
const POLL_SECONDS := 1.0
const MAX_PLAYERS := 50
const MAX_COORDINATE := 7000000.0
## A player that moved less than this (metres) between two answers is standing.
const WALKING_METRES := 0.3
## Farther than this (metres) a player is placed at once instead of gliding there.
const TELEPORT_METRES := 40.0

## Set by the owner: the surface environment turns metres into scene positions.
var environment: Node3D
var server_url := ""
var _token := ""
var _generation := 0
var _polling := false
var _timer: Timer
var _players := {}
var _own_name := ""

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.timeout.connect(poll)
	add_child(_timer)

func start(url: String, token: String, own_name: String) -> void:
	stop()
	server_url = url
	_token = token
	_own_name = own_name
	_timer.start()
	poll()

func stop() -> void:
	_generation += 1
	_token = ""
	_polling = false
	if is_instance_valid(_timer):
		_timer.stop()
	_clear()

func is_running() -> bool:
	return not _token.is_empty()

func names() -> Array:
	var result := _players.keys()
	result.sort()
	return result

## Whether `data` is a player the server may list: a name, a known character and a finite position.
static func valid_player(data: Variant) -> bool:
	if not data is Dictionary or not data.get("name") is String or data.name.is_empty() or data.name.length() > 32:
		return false
	if not data.get("character") is String or not CHARACTERS.is_valid(data.character):
		return false
	if not (data.get("level") is float or data.get("level") is int):
		return false
	for key in ["x", "y", "z"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > MAX_COORDINATE:
			return false
	return true

func poll() -> void:
	if _polling or _token.is_empty():
		return
	_polling = true
	var request := HTTPRequest.new()
	request.timeout = 5.0
	request.max_redirects = 0
	request.body_size_limit = 262144
	add_child(request)
	var generation := _generation
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, reply: PackedByteArray) -> void:
		request.queue_free()
		if generation != _generation:
			return
		_polling = false
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			apply(JSON.parse_string(reply.get_string_from_utf8()))
	)
	var headers := PackedStringArray(["Authorization: Bearer " + _token])
	if request.request(server_url + "/players/nearby", headers) != OK:
		request.queue_free()
		_polling = false

## Shows exactly the valid players of the answer; those who left disappear.
func apply(data: Variant) -> void:
	if not data is Array or data.size() > MAX_PLAYERS:
		return
	var seen := {}
	for entry: Variant in data:
		if not valid_player(entry) or entry.name == _own_name or seen.has(entry.name):
			continue
		seen[entry.name] = true
		var target := Vector3(entry.x, entry.y, entry.z)
		if _players.has(entry.name) and _players[entry.name].character == entry.character:
			_move_to(_players[entry.name], target)
		else:
			_remove(entry.name)
			_add(entry, target)
	for name: String in _players.keys():
		if not seen.has(name):
			_remove(name)

func _add(entry: Dictionary, target: Vector3) -> void:
	var model := CHARACTERS.create_model(entry.character)
	if model == null:
		return
	var placement := Node3D.new()
	placement.name = ("Player" + entry.name).validate_node_name()
	model.scale = Vector3.ONE * 0.001
	placement.add_child(model)
	var label := Label3D.new()
	label.name = "Name"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.font_size = 40
	label.outline_size = 12
	label.position = Vector3(0, CHARACTERS.head_height(model) * 0.001 * 1.08, 0)
	label.text = entry.name
	placement.add_child(label)
	add_child(placement)
	_players[entry.name] = {
		"node": placement, "model": model, "character": entry.character,
		"from": target, "to": target, "elapsed": POLL_SECONDS, "facing": Vector3.ZERO,
		"animation": model.get_node_or_null("CharacterAnimation"), "walking": false,
	}
	_place(_players[entry.name], target)

func _move_to(player: Dictionary, target: Vector3) -> void:
	var shown: Vector3 = player.from.lerp(player.to, clampf(player.elapsed / POLL_SECONDS, 0.0, 1.0))
	var step: Vector3 = target - player.to
	player.from = shown if shown.distance_to(target) < TELEPORT_METRES else target
	player.to = target
	player.elapsed = 0.0
	if step.length() > 0.001:
		player.facing = step
	_set_walking(player, step.length() > WALKING_METRES)

func _set_walking(player: Dictionary, walking: bool) -> void:
	if player.walking == walking:
		return
	player.walking = walking
	var animation: AnimationPlayer = player.animation
	if is_instance_valid(animation) and animation.has_animation("walk" if walking else "idle"):
		animation.play("walk" if walking else "idle", 0.15)

func _remove(name: String) -> void:
	if not _players.has(name):
		return
	var node: Node = _players[name].node
	_players.erase(name)
	if is_instance_valid(node):
		remove_child(node)
		node.queue_free()

func _clear() -> void:
	for name: String in _players.keys():
		_remove(name)

func _process(delta: float) -> void:
	for player: Dictionary in _players.values():
		player.elapsed += delta
		var shown: Vector3 = player.from.lerp(player.to, clampf(player.elapsed / POLL_SECONDS, 0.0, 1.0))
		_place(player, shown)

## Puts a player at `metres` (from the planet's centre), standing on the surface, facing where they went.
func _place(player: Dictionary, metres: Vector3) -> void:
	var node: Node3D = player.node
	if not is_instance_valid(node) or not is_instance_valid(environment):
		return
	node.position = environment.render_position([metres.x, metres.y, metres.z])
	var up := metres.normalized()
	if up == Vector3.ZERO:
		return
	var facing: Vector3 = player.facing - up * player.facing.dot(up)
	if facing.length() < 0.001:
		facing = (Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).cross(up)
	node.basis = Basis.looking_at(-facing.normalized(), up)
