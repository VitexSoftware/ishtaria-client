extends SceneTree

var checks := 0
var failures := 0

class FlatSurface extends Node:
	func elevation(_direction: Vector3) -> float:
		return 1.0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var config := ConfigFile.new()
	var path := "user://test-controls-%d.cfg" % OS.get_process_id()
	config.set_value("connection", "server_url", "https://example.invalid")
	config.set_value("interface", "language", "cs")
	config.save(path)
	var controls := preload("res://scripts/character_controls.gd").new()
	controls.settings_path = path
	root.add_child(controls)
	check(controls.key_for(0) == KEY_W, "Default physical forward key is W")
	check(controls.rebind(0, KEY_D), "Forward can be remapped")
	check(controls.key_for(3) == KEY_W, "Conflicting binding swaps instead of duplicating")
	check(not controls.rebind(0, KEY_ESCAPE), "Escape remains available to release the mouse")
	check(not controls.rebind(0, KEY_SPACE), "Space remains reserved for jumping")
	check(not controls.rebind(0, KEY_SHIFT), "Shift remains reserved for running")
	check(not controls.rebind(0, KEY_I), "I remains reserved for inventory")
	config.load(path)
	check(config.get_value("interface", "language") == "cs" and config.get_value("connection", "server_url") == "https://example.invalid", "Saving controls preserves other settings")
	controls.load_preferences()
	check(controls.key_for(0) == KEY_D, "Remapping persists across reload")
	controls.look(Vector2(300, 10000))
	check(controls.pitch >= -1.35 and controls.pitch <= 1.25 and controls.yaw != 0, "Mouse changes yaw and clamps pitch")
	controls.zoom(100)
	check(controls.distance_m == 30, "Zoom out is bounded")
	controls.zoom(-100)
	check(controls.distance_m == 2, "Zoom in is bounded")
	controls.direction = Vector3.RIGHT
	controls._forward = Vector3.FORWARD
	check(absf(controls.heading().dot(controls.direction)) < 0.0001, "Heading remains tangent to the planet")
	check(controls.intent() == Vector3.ZERO, "Inactive controls cannot move")
	var memorial_surface := preload("res://scripts/surface_environment.gd").new()
	root.add_child(memorial_surface)
	memorial_surface.target = Vector3.RIGHT
	memorial_surface._origin_metres = [6371001.0, 0.0, 0.0]
	var memorial_data := [{"id": "1", "player_name": "Fixture", "kind": "headstone", "position": [6371001.0, 0.0, 0.0]}]
	check(memorial_surface.apply_memorials(memorial_data), "Valid server memorial descriptors are accepted")
	check(memorial_surface.memorials.get_child_count() == 1 and memorial_surface.memorials.get_child(0).position == Vector3.ZERO, "Memorial uses exact origin subtraction at planet scale")
	var first_memorial: Node = memorial_surface.memorials.get_child(0)
	check(memorial_surface.apply_memorials(memorial_data) and memorial_surface.memorials.get_child(0) == first_memorial, "Unchanged polling preserves memorial instances")
	var invalid_memorials := memorial_data.duplicate(true)
	invalid_memorials[0].kind = "unknown"
	check(not memorial_surface.apply_memorials(invalid_memorials) and memorial_surface.memorials.get_child(0) == first_memorial, "Invalid memorials cannot replace validated geometry")
	invalid_memorials = memorial_data.duplicate(true)
	invalid_memorials[0].position[0] = NAN
	check(not memorial_surface.apply_memorials(invalid_memorials), "Non-finite memorial coordinates are rejected")
	check(not memorial_surface.apply_memorials(memorial_data + memorial_data), "Duplicate memorial IDs are rejected")
	var memorial_catalog := preload("res://scripts/survival_panel.gd")
	for kind: String in memorial_catalog.MODELS:
		var memorial: Node3D = memorial_catalog.create_memorial(kind)
		root.add_child(memorial)
		check(memorial.find_children("*", "MeshInstance3D", true, false).size() > 0, "Original Kenney memorial model loads: " + kind)
		check(memorial_catalog._bounds(memorial).size.y > 0, "Memorial has valid assembled bounds: " + kind)
		memorial.queue_free()
	memorial_surface.queue_free()
	Input.action_press("run")
	check(not controls.running(), "Inactive controls cannot run")
	Input.action_release("run")
	var catalog := preload("res://scripts/character_catalog.gd")
	for pack in catalog.PACKS:
		for entry in catalog.CHARACTERS[pack]:
			var model: Node3D = catalog.create_model(pack + "/" + entry[0])
			root.add_child(model)
			var animation: AnimationPlayer = model.get_node("CharacterAnimation")
			check(animation.has_animation("walk") and animation.has_animation("idle"), "Selected character has both original idle and locomotion " + entry[0])
			var walk := animation.get_animation("walk")
			check(walk.loop_mode == Animation.LOOP_LINEAR and walk.get_track_count() > 10, "Locomotion is retargeted to the original skeleton " + entry[0])
			if DisplayServer.get_name() != "headless":
				animation.advance(0.0)
				await process_frame
				var minimum := INF
				for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
					var baked := mesh.bake_mesh_from_current_skeleton_pose()
					for surface_index in baked.get_surface_count():
						for vertex: Vector3 in baked.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]:
							minimum = minf(minimum, (model.global_transform.affine_inverse() * mesh.global_transform * vertex).y)
				check(absf(minimum) < 0.05, "Animated soles match model ground origin %s (%.3f m)" % [entry[0], minimum])
			model.queue_free()
	var flat := FlatSurface.new()
	controls.add_child(flat)
	controls.camera = Camera3D.new()
	controls.add_child(controls.camera)
	controls.avatar = Node3D.new()
	controls.add_child(controls.avatar)
	controls.active = true
	controls.origin = Vector3(6372.00017, 0, 0)
	controls._anchor_metres = [6372000.17, 0.0, 0.0]
	controls.pitch = 1.2
	for step in 60:
		controls.avatar.position.x = step * 0.00001
		controls.update_camera(flat)
		check(absf(controls.camera.position.x - 0.00033) < 0.0000001, "Camera floor remains stable during centimetre steps at planet-scale coordinates")
	controls.reset_keys()
	check(absf(controls.avatar.position.x + 0.00017) < 0.0000001, "Idle avatar is grounded even when its saved position is above terrain")
	controls._ground_surface = null
	controls.avatar.position = Vector3.ZERO
	controls._position_target = Vector3.ZERO
	check(controls.apply_position({"x":6372000.57,"y":0.0,"z":0.0,"sequence":"1"}, true), "Confirmed centimetre position is accepted for visual interpolation")
	check(controls.avatar.position == Vector3.ZERO and absf(controls._position_target.x - 0.0004) < 0.0000001, "Network acknowledgement does not instantly jump the displayed avatar")
	controls._process(0.016)
	check(controls.avatar.position.x > 0.0 and controls.avatar.position.x < controls._position_target.x, "A frame interpolates towards, never beyond, the authoritative target")
	controls._process(1.0)
	check(controls.avatar.position.distance_to(controls._position_target) < 0.0000001, "Visual interpolation settles on the server position")
	controls._ground_surface = flat
	check(controls.apply_position({"x":6372001.17,"y":0.0,"z":0.0,"sequence":"2","airborne":true,"on_object":false}, true), "Server confirms airborne motion")
	controls._process(1.0)
	check(absf(controls.avatar.position.x - 0.001) < 0.0000001, "Grounding does not erase an acknowledged jump")
	controls.queue_jump()
	check(not controls.jump_pending, "Airborne controls cannot queue a second jump")
	check(controls.apply_position({"x":6372001.17,"y":0.0,"z":0.0,"sequence":"3","airborne":false,"on_object":true}, false), "Server confirms a landing on an elevated object")
	controls._process(1.0)
	check(absf(controls.avatar.position.x - 0.001) < 0.0000001, "Standing on an object does not snap back to terrain")
	check(not controls.apply_position({"x":6372001.17,"y":0.0,"z":0.0,"sequence":"4","airborne":"true"}, true), "Malformed airborne state is rejected")
	controls.release_mouse()
	check(not controls.jump_pending, "Releasing input cancels an unsent jump")
	controls.queue_free()
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await native_scene(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Character controls: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check_ground_contact(client: Node, description: String) -> void:
	var surface: Node3D = client._environment
	var point: Vector3 = client._controls.avatar.position
	var up: Vector3 = client._controls.direction
	var mesh: Mesh = surface.detail.get_child(0).mesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var clearance := INF
	for triangle_index in range(0, indices.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(point + up * 0.002, -up, vertices[indices[triangle_index]], vertices[indices[triangle_index + 1]], vertices[indices[triangle_index + 2]])
		if hit is Vector3:
			clearance = minf(clearance, point.distance_to(hit) * 1000.0)
	check(clearance < 0.001, "%s: contact with rendered triangle (%.6f m)" % [description, clearance])

func native_scene(path: String) -> void:
	root.gui_embed_subwindows = true
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("connection", "server_url", "http://127.0.0.1:7400")
	config.save(path)
	var client := preload("res://scenes/main.tscn").instantiate()
	client._settings_path = path
	root.add_child(client)
	client._audio.set_enabled(false)
	client._startup_pending = false
	client.set_process(false)
	for frame in 240:
		if not client._environment.environment.is_empty():
			break
		await process_frame
	if client._environment.environment.is_empty():
		check(false, "Native controls fixture requires the running local world server")
		client.queue_free()
		await process_frame
		return
	var surface: Node3D = client._environment
	var index: int = surface.environment.biomes.find(4.0)
	if index < 0:
		index = surface.environment.biomes.find(5.0)
	check(index >= 0, "Native fixture uses real land from the server")
	var direction: Vector3 = surface._cell_direction(index)
	var point: Vector3 = direction * (client.PLANET_RADIUS + surface.elevation(direction))
	var profile := {"username": "CameraFixture", "character": "retro/humanMaleA", "stats": {"gold": "100", "health": 100, "stamina": 100, "food": 100, "water": 100, "level": 1, "experience": 0}, "position": {"x": point.x * 1000.0, "y": point.y * 1000.0, "z": point.z * 1000.0, "sequence": "0"}}
	client._on_player_profile(profile)
	await process_frame
	for frame in 240:
		if surface.objects_loaded:
			break
		await process_frame
	check(surface.objects_loaded, "Native fixture waits for authoritative obstacle geometry")
	root.grab_focus()
	await process_frame
	await process_frame
	client._process(4.0)
	client._process(0.016)
	client._sky.clear_solar()
	client._sky.environment.ambient_light_energy = 0.8
	check(client._controls.active and client._controls.origin != Vector3.ZERO, "Arrival enables controls and a local render origin")
	var anchor: Array = client._controls._anchor_metres
	var local: Vector3 = client._controls.avatar.position
	var absolute: Array = [anchor[0] + float(local.x) * 1000.0, anchor[1] + float(local.y) * 1000.0, anchor[2] + float(local.z) * 1000.0]
	var radius := sqrt(float(absolute[0]) * absolute[0] + float(absolute[1]) * absolute[1] + float(absolute[2]) * absolute[2])
	var clearance: float = radius - client.PLANET_RADIUS * 1000.0 - surface.elevation64(absolute) * 1000.0
	check(absf(clearance) < 0.05, "Avatar root stands on terrain after arrival (%.3f m)" % clearance)
	check_ground_contact(client, "Arrival")
	var updated_stats: Dictionary = profile.stats.duplicate(true)
	updated_stats.health = 73
	updated_stats.stamina = 0
	updated_stats.water = 22
	var previous_avatar: Node3D = client._controls.avatar
	client._session.stats_changed.emit(updated_stats)
	check(client._hud.meters.health.value == 73 and client._hud.meters.stamina.value == 0 and client._hud.meters.water.value == 22, "Movement acknowledgements update survival HUD values")
	check(client._controls.avatar == previous_avatar and client._controls.active, "Stat changes do not restart arrival or replace the selected avatar")
	client._session.stats_changed.emit(profile.stats)
	var saved_memorials: Array = surface._memorial_entries.duplicate(true)
	surface._cancel_objects()
	surface.set_process(false)
	var displayed_memorials: Array = []
	var forward: Vector3 = client._controls.heading()
	var right: Vector3 = forward.cross(direction).normalized()
	var kinds := ["headstone", "monument", "mausoleum"]
	var lateral_offsets := [-5.0, -2.0, 5.0]
	for memorial_index in kinds.size():
		var coordinates: Array = []
		for axis in 3:
			coordinates.append(float(client._controls._anchor_metres[axis]) + forward[axis] * 6.0 + right[axis] * lateral_offsets[memorial_index])
		var size := sqrt(float(coordinates[0]) * coordinates[0] + float(coordinates[1]) * coordinates[1] + float(coordinates[2]) * coordinates[2])
		var height: float = surface.elevation64(coordinates) * 1000.0
		for axis in 3:
			coordinates[axis] = float(coordinates[axis]) / size * (client.PLANET_RADIUS * 1000.0 + height)
		displayed_memorials.append({"id": str(memorial_index + 1), "player_name": "Fixture", "kind": kinds[memorial_index], "position": coordinates})
	check(surface.apply_memorials(displayed_memorials) and surface.memorials.get_child_count() == 3, "All three server-selected memorial kinds appear on the surface")
	var saved_distance: float = client._controls.distance_m
	client._controls.distance_m = 22.0
	client._controls.update_camera(surface)
	for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
		root.size = dimensions
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/ishtaria-survival-memorials-%dx%d.png" % [dimensions.x, dimensions.y])
		check(surface.memorials.get_child_count() == 3, "Surface memorials remain loaded at " + str(dimensions))
	root.size = Vector2i(1600, 900)
	client._controls.distance_m = saved_distance
	client._controls.update_camera(surface)
	surface.apply_memorials(saved_memorials)
	surface.set_process(true)
	var saved_target: Vector3 = client._controls._position_target
	client._controls._position_target += direction * 0.0076
	client._controls._process(1.0)
	check_ground_contact(client, "Standing with a legacy position 7.6 metres above terrain")
	check(client._controls._position_target.is_equal_approx(saved_target + direction * 0.0076), "Grounding does not overwrite the authoritative position target")
	client._controls._position_target = saved_target
	client._controls.capture_mouse()
	Input.action_press("walk_forward")
	Input.action_press("walk_right")
	var shift := InputEventKey.new()
	shift.pressed = true
	shift.physical_keycode = KEY_SHIFT
	shift.keycode = KEY_SHIFT
	Input.parse_input_event(shift)
	await process_frame
	check(client._controls.running(), "Physical Shift enables running while moving")
	var intent: Vector3 = client._controls.intent()
	check(is_equal_approx(intent.length(), 1.0) and absf(intent.dot(direction)) < 0.0001, "Diagonal input is normalized and tangent")
	var space := InputEventKey.new()
	space.pressed = true
	space.physical_keycode = KEY_SPACE
	space.keycode = KEY_SPACE
	var focused_button: BaseButton = client._hud.panel.find_children("*", "BaseButton", true, false)[0]
	focused_button.grab_focus()
	check(root.gui_get_focus_owner() == focused_button, "Jump input fixture includes a focused HUD button")
	Input.parse_input_event(space)
	await process_frame
	check(client._controls.jump_pending and client._controls.jump_direction.is_equal_approx(intent), "Space queues one jump in the pressed diagonal direction")
	check(client._controls.jump_running, "A queued running jump retains its launch mode")
	shift.pressed = false
	Input.parse_input_event(shift)
	await process_frame
	check(not client._controls.running() and client._controls.jump_running, "Releasing Shift stops running without altering a queued launch")
	space.echo = true
	client._controls.yaw += 0.1
	Input.parse_input_event(space)
	await process_frame
	check(client._controls.jump_direction.is_equal_approx(intent), "Key repeat cannot change or duplicate the queued jump")
	space.echo = false
	space.pressed = false
	Input.parse_input_event(space)
	await process_frame
	check(not client._game_ui_open(), "Captured Space cannot activate a focused HUD button")
	client._controls.yaw -= 0.1
	client._controls.release_mouse()
	check(client._controls.intent() == Vector3.ZERO, "Released cursor stops walking immediately")
	check(not client._controls.jump_pending, "Opening UI or releasing cursor cancels an unsent jump")
	client._controls.capture_mouse()
	Input.action_press("run")
	var inventory_key := InputEventKey.new()
	inventory_key.pressed = true
	inventory_key.physical_keycode = KEY_I
	inventory_key.keycode = KEY_I
	focused_button.grab_focus()
	Input.parse_input_event(inventory_key)
	await process_frame
	check(client._survival.visible, "I opens the existing inventory even with a focused HUD button")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not client._controls.running(), "Inventory immediately releases the cursor and stops running")
	for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var panel: Control = client._survival.panel
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(panel.get_global_rect()), "Keyboard-opened inventory fits at " + str(dimensions))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/ishtaria-controls-inventory-%dx%d.png" % [dimensions.x, dimensions.y])
	root.size = Vector2i(1600, 900)
	await process_frame
	client._survival.hide()
	inventory_key.echo = true
	Input.parse_input_event(inventory_key)
	await process_frame
	check(not client._survival.visible, "Key repeat does not reopen the inventory")
	inventory_key.echo = false
	inventory_key.pressed = false
	Input.parse_input_event(inventory_key)
	await process_frame
	var before: Basis = client._camera.basis
	client._controls.capture_mouse()
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, -50)
	client._unhandled_input(motion)
	client._controls.update_camera(surface, client._hud.panel)
	check(not before.is_equal_approx(client._camera.basis), "Mouse-look changes the actual camera")
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	var distance: float = client._controls.distance_m
	client._unhandled_input(wheel)
	check(client._controls.distance_m < distance, "Mouse wheel zooms the actual scene")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	client._input(escape)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases the cursor through scene input")
	client._controls.distance_m = distance
	var position: Dictionary = profile.position.duplicate()
	position.sequence = "1"
	check(client._controls.apply_position(position, false), "Authoritative position is accepted")
	check(not client._controls.apply_position(position, false), "Replayed position cannot rewind the avatar")
	var delta: Vector3 = client._controls.heading() * 0.4
	position.x += delta.x
	position.y += delta.y
	position.z += delta.z
	position.sequence = "2"
	check(client._controls.apply_position(position, true) and client._controls._position_target.distance_to(delta / 1000.0) < 0.0000001, "Sub-metre server movement survives planet-scale coordinates")
	client._controls.capture_mouse()
	Input.action_press("walk_forward")
	client._controls._process(0.016)
	check(client._controls._animation.current_animation == "walk", "Confirmed displacement starts locomotion on the selected avatar")
	check_ground_contact(client, "Interpolated walking")
	var skeleton: Skeleton3D = client._controls.avatar.find_children("*", "Skeleton3D", true, false)[0]
	client._controls._animation.advance(0.2)
	var poses: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_pose(bone))
	client._controls._animation.advance(0.2)
	var changed := 0
	for bone in skeleton.get_bone_count():
		if not poses[bone].is_equal_approx(skeleton.get_bone_pose(bone)):
			changed += 1
	check(changed > 5, "Native locomotion actually changes the character's skeletal pose")
	position.sequence = "3"
	position.x += client._controls.heading().x * 0.6
	position.y += client._controls.heading().y * 0.6
	position.z += client._controls.heading().z * 0.6
	client._controls._last_position_ms = Time.get_ticks_msec() - 100
	check(client._controls.apply_position(position, true), "An acknowledged running step is accepted")
	check(client._controls._animation.speed_scale > 1.1 and client._controls._animation.speed_scale <= 1.5, "Running accelerates the original locomotion clip according to acknowledged speed")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/ishtaria-controls-walking.png")
	position.sequence = "4"
	client._controls.apply_position(position, false)
	check(client._controls._animation.current_animation == "idle", "Blocked movement stops the locomotion animation")
	client._controls.release_mouse()
	check(client._controls._animation.current_animation == "idle", "Releasing the cursor preserves the idle pose")
	client._controls._process(0.016)
	check_ground_contact(client, "Stopping")
	var ground_position: Dictionary = position.duplicate()
	var rock_base: Vector3 = client._controls.avatar.position + client._controls.heading() * 0.0015
	var rock_coordinates := [anchor[0] + float(rock_base.x) * 1000.0, anchor[1] + float(rock_base.y) * 1000.0, anchor[2] + float(rock_base.z) * 1000.0]
	surface._place_object({"id":"native-jump-fixture","model":"nature.rock","position":rock_coordinates,"scale_m":2.0,"yaw":0.3,"collision_radius_m":0.8,"biome":4})
	var rock: Node3D = surface.objects.get_child(surface.objects.get_child_count() - 1)
	var rock_top := Vector3.ZERO
	var shortest := INF
	for mesh_instance: MeshInstance3D in rock.find_children("*", "MeshInstance3D", true, false):
		for surface_index in mesh_instance.mesh.get_surface_count():
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices = PackedInt32Array(range(vertices.size()))
			for triangle in range(0, indices.size(), 3):
				var start := (rock_base + direction * 0.003) * 1000.0
				var hit: Variant = Geometry3D.ray_intersects_triangle(start, -direction, (mesh_instance.global_transform * vertices[indices[triangle]]) * 1000.0, (mesh_instance.global_transform * vertices[indices[triangle + 1]]) * 1000.0, (mesh_instance.global_transform * vertices[indices[triangle + 2]]) * 1000.0)
				if hit is Vector3 and start.distance_to(hit) < shortest:
					shortest = start.distance_to(hit)
					rock_top = hit / 1000.0
	check(is_finite(shortest), "Native rock support comes from original rendered triangles")
	for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
		root.size = dimensions
		await process_frame
		await process_frame
		client._controls.update_camera(surface, client._hud.panel)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("/tmp/ishtaria-controls-%dx%d.png" % [dimensions.x, dimensions.y])
		var colors := {}
		for row in range(0, image.get_height(), 8):
			for column in range(0, image.get_width(), 8):
				colors[image.get_pixel(column, row).to_html()] = true
		check(colors.size() > 30, "Native character and terrain are nonblank at " + str(dimensions))
		position.sequence = str(int(position.sequence) + 1)
		position.airborne = true
		position.on_object = false
		position.x = ground_position.x + float(direction.x) * 2.0
		position.y = ground_position.y + float(direction.y) * 2.0
		position.z = ground_position.z + float(direction.z) * 2.0
		check(client._controls.apply_position(position, true), "Native scene accepts acknowledged flight at " + str(dimensions))
		client._controls._process(1.0)
		client._controls.update_camera(surface, client._hud.panel)
		check(client._controls.avatar.position.distance_to(saved_target) > 0.0015, "Avatar remains visibly airborne at " + str(dimensions))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/ishtaria-controls-jump-%dx%d.png" % [dimensions.x, dimensions.y])
		position.sequence = str(int(position.sequence) + 1)
		position.airborne = false
		position.on_object = true
		position.x = anchor[0] + float(rock_top.x) * 1000.0
		position.y = anchor[1] + float(rock_top.y) * 1000.0
		position.z = anchor[2] + float(rock_top.z) * 1000.0
		check(client._controls.apply_position(position, false), "Native scene accepts acknowledged elevated support")
		client._controls._process(1.0)
		client._controls.update_camera(surface, client._hud.panel)
		check(client._controls.avatar.position.distance_to(rock_top) < 0.000001, "Avatar stands on the original rock triangle at " + str(dimensions))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/ishtaria-controls-rock-%dx%d.png" % [dimensions.x, dimensions.y])
		position.sequence = str(int(position.sequence) + 1)
		position.airborne = false
		position.on_object = false
		for axis in ["x", "y", "z"]:
			position[axis] = ground_position[axis]
		client._controls.apply_position(position, false)
		client._controls._process(1.0)
		check_ground_contact(client, "Returning from a jump to terrain")
		TranslationServer.set_locale("cs")
		client._control_settings.open()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var settings: Window = client._control_settings
		root.get_texture().get_image().save_png("/tmp/ishtaria-controls-settings-%dx%d.png" % [dimensions.x, dimensions.y])
		check(settings.size.x <= dimensions.x and settings.size.y <= dimensions.y, "Control settings fit at " + str(dimensions))
		for button in settings._buttons:
			check(button.size.x >= button.get_minimum_size().x, "Binding labels fit their buttons")
		settings._close()
		client._controls.release_mouse()
	if not OS.get_environment("ISHTARIA_SLIDE_CAPTURE").is_empty():
		await native_slide_capture(client, profile)
	client._on_player_failed("Movement unavailable")
	check(client._connection_panel.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Movement failure shows visible feedback and releases the cursor")
	client._on_player_failed("Surface objects unavailable")
	check(not surface.objects_loaded and client._connection_panel.visible and client._controls.intent() == Vector3.ZERO, "Missing obstacle geometry stops movement with visible feedback")
	client._connection_panel.hide()
	var recapture := InputEventMouseButton.new()
	recapture.pressed = true
	recapture.button_index = MOUSE_BUTTON_LEFT
	client._unhandled_input(recapture)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Hiding feedback cannot resume walking without obstacle geometry")
	client._on_player_profile({})
	check(not client._controls.active and client._controls.origin == Vector3.ZERO and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Sign-out stops walking and restores orbital coordinates")
	client.queue_free()
	await process_frame
	await process_frame

func native_slide_capture(client: Node, profile: Dictionary) -> void:
	var capture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ISHTARIA_SLIDE_CAPTURE")))
	var surface: Node3D = client._environment
	var object: Dictionary = capture.object.duplicate(true)
	var source: Array = object.position
	var radius := sqrt(float(source[0]) * source[0] + float(source[1]) * source[1] + float(source[2]) * source[2])
	var ground: float = (client.PLANET_RADIUS + surface.elevation64(source)) * 1000.0
	var center := [float(source[0]) * ground / radius, float(source[1]) * ground / radius, float(source[2]) * ground / radius]
	var initial: Array = capture.trajectory[0].offset
	profile = profile.duplicate(true)
	profile.username = "SlideFixture"
	profile.position = {"x": center[0] + initial[0], "y": center[1] + initial[1], "z": center[2] + initial[2], "sequence": "0", "airborne": true, "on_object": false}
	client._on_player_profile(profile)
	await process_frame
	for frame in 240:
		if surface.objects_loaded:
			break
		await process_frame
	check(surface.objects_loaded, "Slide capture has loaded the original world geometry")
	client._process(4.0)
	client._process(0.016)
	client._controls.distance_m = 8.0
	var up := Vector3(center[0], center[1], center[2]).normalized()
	var outward := Vector3(initial[0], initial[1], initial[2])
	outward = (outward - up * outward.dot(up)).normalized()
	client._controls._forward = -outward
	for existing: Node3D in surface.objects.get_children():
		existing.hide()
	object.id = "native-slide-fixture"
	object.position = center
	surface._place_object(object)
	for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
		root.size = dimensions
		await process_frame
		await process_frame
		for phase in ["trajectory", "recovery"]:
			var samples: Array = capture[phase]
			for sample_index in samples.size():
				var sample: Dictionary = samples[sample_index]
				var offset: Array = sample.offset
				var position := {"x": center[0] + offset[0], "y": center[1] + offset[1], "z": center[2] + offset[2], "sequence": str(client._controls.sequence + 1), "airborne": sample.airborne, "on_object": sample.on_object}
				check(client._controls.apply_position(position, true), "Server slide sample is accepted: %s %d" % [phase, sample_index])
				if sample_index == 0:
					client._controls.avatar.position = client._controls._position_target
				client._controls._process(0.05)
				client._controls.update_camera(surface, client._hud.panel)
				await process_frame
				if sample_index in [0, 8, 14, 40]:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("/tmp/ishtaria-slide-%s-%d-%dx%d.png" % [phase, sample_index, dimensions.x, dimensions.y])
			client._controls._process(1.0)
			check(not client._controls.airborne, "Slide and recovery both finish grounded")
			if client._controls.on_object:
				check(client._controls.avatar.position.distance_to(client._controls._position_target) < 0.000001, "Rendering settles on the nonpenetrating server support")
			else:
				check_ground_contact(client, "Slide capture settles on rendered terrain")
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var colors := {}
		for row in range(0, image.get_height(), 8):
			for column in range(0, image.get_width(), 8):
				colors[image.get_pixel(column, row).to_html()] = true
		check(colors.size() > 30, "Native slide scene is nonblank at " + str(dimensions))