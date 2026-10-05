extends Node3D

const ACTIONS := ["walk_forward", "walk_backward", "walk_left", "walk_right"]
const DEFAULT_KEYS := [KEY_W, KEY_S, KEY_A, KEY_D]
const LABELS := ["Forward", "Backward", "Left", "Right"]
const RESERVED_KEYS := [KEY_ESCAPE, KEY_SPACE, KEY_SHIFT, KEY_I]
const RADIUS := 6371.0

var camera: Camera3D
var settings_path := "user://client.cfg"
var sensitivity := 0.002
var invert_y := false
var distance_m := 5.0
var yaw := 0.0
var pitch := -0.25
var active := false
var moving := false
var direction := Vector3.ZERO
var sequence := -1
var avatar: Node3D
var origin := Vector3.ZERO
var _anchor_metres: Array = []
var _forward := Vector3.FORWARD
var _character := ""
var _animation: AnimationPlayer
var _motion_until := 0
var _last_position_ms := 0
var _walk_speed := 1.0
var _position_target := Vector3.ZERO
var _ground_surface: Node
var airborne := false
var on_object := false
var jump_pending := false
var jump_direction := Vector3.ZERO
var jump_running := false

func _ready() -> void:
	load_preferences()

func load_preferences() -> void:
	if not InputMap.has_action("run"):
		InputMap.add_action("run")
		var run_key := InputEventKey.new()
		run_key.physical_keycode = KEY_SHIFT
		InputMap.action_add_event("run", run_key)
	var config := ConfigFile.new()
	config.load(settings_path)
	var used := []
	for index in ACTIONS.size():
		var key: Variant = config.get_value("controls", ACTIONS[index], DEFAULT_KEYS[index])
		if not key is int or key <= 0 or key in RESERVED_KEYS or key in used:
			key = DEFAULT_KEYS[index]
		if key in used:
			reset_keys()
			break
		_set_key(index, key)
		used.append(key)
	var saved: Variant = config.get_value("controls", "sensitivity", 0.002)
	if (saved is float or saved is int) and is_finite(float(saved)):
		sensitivity = clampf(saved, 0.0005, 0.01)
	var inverted: Variant = config.get_value("controls", "invert_y", false)
	invert_y = inverted if inverted is bool else false

func _set_key(index: int, key: int) -> void:
	if not InputMap.has_action(ACTIONS[index]):
		InputMap.add_action(ACTIONS[index])
	InputMap.action_erase_events(ACTIONS[index])
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(ACTIONS[index], event)

func key_for(index: int) -> int:
	return InputMap.action_get_events(ACTIONS[index])[0].physical_keycode

func rebind(index: int, key: int) -> bool:
	if index < 0 or index >= ACTIONS.size() or key <= 0 or key in RESERVED_KEYS:
		return false
	var previous := key_for(index)
	for other in ACTIONS.size():
		if other != index and key_for(other) == key:
			_set_key(other, previous)
	_set_key(index, key)
	return save_preferences()

func reset_keys() -> void:
	for index in ACTIONS.size():
		_set_key(index, DEFAULT_KEYS[index])

func save_preferences() -> bool:
	var config := ConfigFile.new()
	config.load(settings_path)
	for index in ACTIONS.size():
		config.set_value("controls", ACTIONS[index], key_for(index))
	config.set_value("controls", "sensitivity", sensitivity)
	config.set_value("controls", "invert_y", invert_y)
	return config.save(settings_path) == OK

func start(character: String, point: Vector3, coordinates: Dictionary = {}) -> void:
	stop()
	if point.length_squared() < 1.0:
		return
	direction = point.normalized()
	var reference := Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT
	_forward = reference.cross(direction).normalized()
	if _character != character or not is_instance_valid(avatar):
		if is_instance_valid(avatar):
			avatar.free()
		avatar = preload("res://scripts/character_catalog.gd").create_model(character)
		if avatar == null:
			return
		_character = character
		avatar.scale = Vector3.ONE * 0.001
		add_child(avatar)
		_animation = avatar.get_node_or_null("CharacterAnimation")
	avatar.position = point
	_position_target = point
	_anchor_metres = [coordinates.get("x", point.x * 1000.0), coordinates.get("y", point.y * 1000.0), coordinates.get("z", point.z * 1000.0)]
	airborne = coordinates.get("airborne", false) == true
	on_object = coordinates.get("on_object", false) == true
	avatar.basis = Basis.looking_at(-_forward, direction).scaled(Vector3.ONE * 0.001)
	avatar.show()
	yaw = 0.0
	pitch = -0.25
	sequence = -1
	_last_position_ms = Time.get_ticks_msec()

func stop() -> void:
	active = false
	moving = false
	_ground_surface = null
	airborne = false
	on_object = false
	direction = Vector3.ZERO
	if is_instance_valid(avatar):
		avatar.hide()
	release_mouse()

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	moving = false
	jump_pending = false
	jump_running = false
	Input.action_release("run")
	_play_animation(false)
	for action in ACTIONS:
		Input.action_release(action)

func capture_mouse() -> void:
	if active and get_window().has_focus():
		get_viewport().gui_release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func look(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * sensitivity, -PI, PI)
	pitch = clampf(pitch - relative.y * sensitivity * (-1.0 if invert_y else 1.0), -1.35, 1.25)

func zoom(steps: float) -> void:
	distance_m = clampf(distance_m * pow(1.15, steps), 2.0, 30.0)

func heading() -> Vector3:
	var tangent := (_forward - direction * _forward.dot(direction)).normalized()
	return tangent.rotated(direction, yaw)

func intent() -> Vector3:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return Vector3.ZERO
	var axes := Input.get_vector(ACTIONS[2], ACTIONS[3], ACTIONS[0], ACTIONS[1])
	return (heading() * -axes.y + heading().cross(direction) * axes.x).limit_length(1.0)

func queue_jump() -> void:
	if active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not airborne and not jump_pending:
		jump_direction = intent()
		jump_running = running()
		jump_pending = true

func running() -> bool:
	return active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("run")

func apply_position(data: Variant, is_moving: bool) -> bool:
	if not data is Dictionary or not data.get("sequence") is String or not data.sequence.is_valid_int():
		return false
	for axis in ["x", "y", "z"]:
		var value: Variant = data.get(axis)
		if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
			return false
	var received := int(data.sequence)
	if received < 0 or received <= sequence:
		return false
	for state in ["airborne", "on_object"]:
		if data.has(state) and not data[state] is bool:
			return false
	var point := Vector3(data.x / 1000.0, data.y / 1000.0, data.z / 1000.0)
	if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
		return false
	sequence = received
	airborne = data.get("airborne", false)
	on_object = data.get("on_object", false)
	direction = point.normalized()
	var previous := _position_target
	_position_target = Vector3((float(data.x) - _anchor_metres[0]) / 1000.0, (float(data.y) - _anchor_metres[1]) / 1000.0, (float(data.z) - _anchor_metres[2]) / 1000.0) if origin != Vector3.ZERO else point
	var now := Time.get_ticks_msec()
	var travelled := _position_target.distance_to(previous) * 1000.0
	moving = is_moving and travelled > 0.0001
	if moving:
		_walk_speed = clampf(travelled / maxf((now - _last_position_ms) / 1000.0, 0.04) / 4.0, 0.2, 1.5)
		_motion_until = now + 350
	_last_position_ms = now
	_play_animation(moving and active and intent().length_squared() > 0.0001)
	return true

func _process(delta: float) -> void:
	if active and is_instance_valid(avatar):
		avatar.position = avatar.position.lerp(_position_target, 1.0 - exp(-18.0 * delta))
		_ground_avatar(_ground_surface)
	_play_animation(active and moving and Time.get_ticks_msec() < _motion_until and intent().length_squared() > 0.0001)

func _ground_avatar(surface: Node) -> void:
	if airborne or on_object or not is_instance_valid(surface) or not is_instance_valid(avatar) or origin == Vector3.ZERO:
		return
	var absolute: Array = []
	for axis in 3:
		absolute.append(float(_anchor_metres[axis]) + float(avatar.position[axis]) * 1000.0)
	if surface.has_method("ground_position64"):
		avatar.position = surface.ground_position64(absolute)
	else:
		var radius := sqrt(float(absolute[0]) * absolute[0] + float(absolute[1]) * absolute[1] + float(absolute[2]) * absolute[2])
		var up := Vector3(absolute[0] / radius, absolute[1] / radius, absolute[2] / radius)
		var height: float = surface.elevation64(absolute) if surface.has_method("elevation64") else surface.elevation(up)
		avatar.position += up * (RADIUS + height - radius / 1000.0)

func _play_animation(walking: bool) -> void:
	if not is_instance_valid(_animation):
		return
	var action := "walk" if walking else "idle"
	_animation.speed_scale = _walk_speed if walking else 1.0
	if _animation.current_animation != action:
		_animation.play(action, 0.15)

func update_camera(surface: Node, hud: Control = null) -> void:
	if not active or not is_instance_valid(avatar):
		return
	_ground_surface = surface
	_ground_avatar(surface)
	var visible_fraction := 1.0
	if is_instance_valid(hud) and hud.is_visible_in_tree():
		visible_fraction = clampf(hud.global_position.y / get_viewport().get_visible_rect().size.y, 0.25, 1.0)
	var forward := heading()
	var target := avatar.position + direction * 0.0015
	var view := forward * cos(pitch) + direction * sin(pitch)
	camera.position = target - view * (distance_m / (1000.0 * visible_fraction))
	var coordinates: Array = _anchor_metres if origin != Vector3.ZERO else [0.0, 0.0, 0.0]
	var absolute: Array[float] = []
	for axis in 3:
		absolute.append(float(coordinates[axis]) + float(camera.position[axis]) * 1000.0)
	var radius := sqrt(absolute[0] * absolute[0] + absolute[1] * absolute[1] + absolute[2] * absolute[2]) / 1000.0
	var point := Vector3(absolute[0], absolute[1], absolute[2]).normalized()
	var height: float = maxf(0.0, surface.elevation64(absolute) if surface.has_method("elevation64") else surface.elevation(point.normalized()))
	if radius < RADIUS + height + 0.0005:
		camera.position += point * (RADIUS + height + 0.0005 - radius)
	camera.near = 0.0002
	camera.far = 5.0
	camera.look_at(target, direction)
	camera.rotate_object_local(Vector3.RIGHT, -atan((1.0 - visible_fraction) * tan(deg_to_rad(camera.fov) * 0.5)))
	if moving:
		var desired := intent()
		if desired.length_squared() > 0.01:
			avatar.basis = Basis.looking_at(-desired.normalized(), direction).scaled(Vector3.ONE * 0.001)

func _exit_tree() -> void:
	release_mouse()