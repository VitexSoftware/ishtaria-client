extends SceneTree

const SURFACE := preload("res://scripts/surface_environment.gd")
const SHADER := preload("res://scripts/planet_surface.gdshader")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _fixture(size: int) -> Dictionary:
	var count := size * size * 6
	var data := {"version":1,"heightmap_sha256":"fixture","seed":"18446744073709551615","face_size":size,"elevation_m":[],"water_m":[],"biomes":[],"downstream":[],"flow":[]}
	for index in count:
		data.elevation_m.append(1000)
		data.water_m.append(-8001)
		data.biomes.append(5)
		data.downstream.append(-1)
		data.flow.append(1)
	return data

func _object_fixture(surface: Node3D, biome: int = 5) -> Dictionary:
	var data := {"version":1,"heightmap_sha256":surface.environment.heightmap_sha256,"seed":surface.environment.seed,"objects":[]}
	var available: Array = surface.catalog.filter(func(entry: Dictionary) -> bool: return surface.BIOMES[biome] in entry.biomes)
	if available.is_empty():
		return data
	for index in 160:
		var direction: Vector3 = (Vector3.FORWARD * surface.RADIUS + Vector3((index % 16 - 8) * 0.012, (int(index / 16) - 5) * 0.012, 0)).normalized()
		var point: Vector3 = direction * (surface.RADIUS + surface.elevation(direction))
		var selected: Dictionary = available[index % available.size()]
		data.objects.append({"id":"%s:fixture:%d" % [data.seed,index],"model":selected.id,"position":[point.x*1000.0,point.y*1000.0,point.z*1000.0],"scale_m":selected.scale_m,"yaw":0.4,"collision_radius_m":0.5,"biome":biome})
	return data

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var surface := SURFACE.new()
	surface.land_material = ShaderMaterial.new()
	surface.land_material.shader = SHADER
	surface.water_material = ShaderMaterial.new()
	surface.water_material.shader = SHADER
	surface.water_material.set_shader_parameter("water_pass", true)
	world.add_child(surface)
	_check(surface.catalog.size() == 248, "All original Nature variants and the other three packs have validated entries")
	_check(surface.catalog.filter(func(entry: Dictionary) -> bool: return entry.id.begins_with("nature.")).size() == 161, "All 161 natural Nature Kit variants are integrated")
	for entry in surface.catalog:
		var scene := load(entry.scene) as PackedScene
		_check(scene != null, entry.id + " loads as a PackedScene")
		var model := scene.instantiate()
		_check(model is Node3D and not model.find_children("*", "MeshInstance3D", true, false).is_empty(), entry.id + " contains real 3D meshes")
		model.free()
	for face in 6:
		for position in [Vector2(-0.7, -0.4), Vector2(0.8, 0.6), Vector2.ZERO]:
			var mapped := surface.coordinates(surface.cube_point(face, position.x, position.y))
			_check(int(mapped.x) == face and absf(mapped.y - (position.x + 1) * 0.5) < 0.00001 and absf(mapped.z - (1 - position.y) * 0.5) < 0.00001, "Cube-sphere inverse preserves face, coordinates and north-up rows")
	var image := Image.create(96, 16, false, Image.FORMAT_L8)
	image.fill(Color(0.5625, 0.5625, 0.5625))
	surface.heightmap = image
	var texture := ImageTexture.create_from_image(image)
	for material in [surface.land_material, surface.water_material]:
		material.set_shader_parameter("heightmap", texture)
		material.set_shader_parameter("has_heightmap", true)
	var data := _fixture(16)
	_check(not surface.apply_environment(data, "another-map", data.seed), "Foreign heightmap checksum is rejected")
	_check(not surface.apply_environment(data, "fixture", "42"), "Foreign seed is rejected without integer precision loss")
	var invalid := data.duplicate(true)
	invalid.biomes[0] = 99
	_check(not surface.apply_environment(invalid, "fixture", data.seed), "Unknown biomes are rejected")
	invalid = data.duplicate(true)
	invalid.downstream[0] = data.biomes.size()
	_check(not surface.apply_environment(invalid, "fixture", data.seed), "Out-of-bounds drainage is rejected")
	_check(surface.apply_environment(data, "fixture", data.seed), "Valid server environment is accepted")
	surface.show_region(Vector3.FORWARD)
	_check(surface.placements.is_empty() and not surface.objects_loaded, "Missing backend objects are not replaced by invented local obstacles")
	var objects := _object_fixture(surface)
	_check(surface.apply_objects(objects), "Authoritative object region is accepted")
	_check(surface.placements.size() == 160 and surface.objects_loaded, "Forest streams the server's bounded populated region")
	var original := surface.placements.duplicate(true)
	surface.show_region(Vector3.FORWARD)
	_check(original == surface.placements, "Region refresh retains visible obstacles until their replacement arrives")
	_check(surface.apply_objects(objects) and original == surface.placements, "Repeated server data preserves model, identity, position, scale and rotation")
	var invalid_objects := objects.duplicate(true)
	invalid_objects.seed = "wrong"
	_check(not surface.apply_objects(invalid_objects) and surface.placements == original, "Foreign object identity cannot replace the current scene")
	invalid_objects = objects.duplicate(true)
	invalid_objects.objects[0].model = "unknown"
	_check(not surface.apply_objects(invalid_objects), "Unknown object models are rejected")
	invalid_objects = objects.duplicate(true)
	invalid_objects.objects[0].position[0] = INF
	_check(not surface.apply_objects(invalid_objects), "Non-finite object coordinates are rejected")
	invalid_objects = objects.duplicate(true)
	invalid_objects.objects[1].id = invalid_objects.objects[0].id
	_check(not surface.apply_objects(invalid_objects), "Duplicate obstacle identities are rejected")
	var precise: Array = objects.objects[0].position.duplicate()
	precise[0] -= 0.4
	surface.set_render_origin(precise)
	_check(absf(surface.objects.get_child(0).position.x - 0.0004) < 0.0000001, "Obstacle positioning preserves forty centimetres at planet-scale coordinates")
	var vertices: PackedVector3Array = surface.detail.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(vertices.size() == 129 * 129 and surface.detail.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 128 * 128 * 6, "Fine detail shares vertices without duplicate height calculations")
	_check(surface.detail.top_level and surface.detail.get_child(0).material_override.get_shader_parameter("is_detail"), "Detail uses local coordinates without a second planet-scale transform")
	_check(vertices[0].length() < 2.0, "Detail vertices are local, not planet-scale")
	var shifted := precise.duplicate()
	shifted[0] += 0.01
	surface.set_render_origin(shifted)
	var rebased: PackedVector3Array = surface.detail.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(absf((vertices[0].x - rebased[0].x) - 0.00001) < 0.0000001, "Terrain rebase preserves one centimetre without moving its absolute surface")
	surface.set_render_origin([])
	for placement in surface.placements:
		_check(placement.position.is_finite() and absf(placement.position.length() - (surface.RADIUS + surface.elevation(placement.position) + 0.0005)) < 0.002, "Objects stand on actual terrain")
	for sample in [
		[[1.0, 0.0, 0.0], "42", -7.595497428807521],
		[[1.0, 1.0, 0.0], "42", 4.106134823054352],
		[[1.0, 2.0, 3.0], "18446744073709551615", -1.7645037024417682],
		[[6371000.0, 0.01, 0.0], "42", -7.594750622916318],
	]:
		_check(absf(surface.relief64(sample[0], 1000.0, sample[1]) - sample[2]) < 0.000001, "Relief matches Rust's metre-scale reference, including seams and u64 seed")
	data.version = 2
	_check(surface.apply_environment(data, "fixture", data.seed), "Version two explicitly enables shared relief")
	_check(surface.apply_environment(JSON.parse_string(JSON.stringify(data)), "fixture", data.seed), "Version two is accepted after real JSON numeric decoding")
	var minimum := INF
	var maximum := -INF
	for metre in 1000:
		var point: Array = [6371000.0, float(metre), 0.0]
		var height: float = surface.elevation64(point)
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		point[1] += 0.01
		_check(absf(height - surface.elevation64(point)) < 0.000003, "Terrain height remains continuous during centimeter movement")
	_check(maximum - minimum > 0.01, "Walkable landscape has more than ten metres of local relief")
	data.seed = "43"
	_check(surface.apply_environment(data, "fixture", "43"), "Another seed is accepted with its matching identity")
	surface.show_region(Vector3.FORWARD)
	_check(surface.apply_objects(_object_fixture(surface)), "Object descriptors follow the new server identity")
	_check(original != surface.placements, "Seed changes object placement")
	if DisplayServer.get_name() != "headless":
		await _capture(world, surface, data)
	var lake := data.duplicate(true)
	lake.biomes.fill(1)
	lake.water_m.fill(2000)
	_check(surface.apply_environment(lake, "fixture", "43"), "Lake levels are accepted")
	surface.show_region(Vector3.FORWARD)
	_check(surface.placements.is_empty(), "No objects spawn underwater")
	var test_url := OS.get_environment("ISHTARIA_ENVIRONMENT_TEST_URL")
	if not test_url.is_empty():
		await _test_http(surface, test_url)
	surface.clear_world()
	_check(surface.environment.is_empty() and surface.heightmap == null and surface.objects.get_child_count() == 0, "Disconnect clears the entire former world")
	world.queue_free()
	await process_frame
	print("Surface environment: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _test_http(surface: Node3D, url: String) -> void:
	var loader := HTTPRequest.new()
	loader.timeout = 8.0
	loader.max_redirects = 0
	loader.body_size_limit = 16 * 1024 * 1024
	root.add_child(loader)
	var responses := {}
	for endpoint in ["/world", "/world/heightmap.png", "/world/environment"]:
		_check(loader.request(url + endpoint) == OK, "Environment HTTP request starts")
		var result: Array = await loader.request_completed
		_check(result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200, "Environment HTTP response succeeds: " + endpoint)
		if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
			loader.queue_free()
			return
		responses[endpoint] = result[3]
	loader.queue_free()
	var metadata: Dictionary = JSON.parse_string(responses["/world"].get_string_from_utf8())
	var data: Dictionary = JSON.parse_string(responses["/world/environment"].get_string_from_utf8())
	var image := Image.new()
	_check(image.load_png_from_buffer(responses["/world/heightmap.png"]) == OK, "HTTP terrain image decodes")
	_check(image.get_height() == metadata.face_size and image.get_width() == metadata.face_size * 6, "HTTP terrain dimensions match identity")
	surface.clear_world()
	surface.heightmap = image
	var texture := ImageTexture.create_from_image(image)
	for material in [surface.land_material, surface.water_material]:
		material.set_shader_parameter("heightmap", texture)
	_check(surface.apply_environment(data, metadata.sha256, metadata.seed), "Real persisted HTTP environment is accepted by the renderer")
	for biome in 8:
		_check(data.biomes.has(float(biome)), "Generated world contains " + surface.BIOMES[biome])
	var forest: int = data.biomes.find(5.0)
	if forest >= 0:
		surface.server_url = url
		surface.show_region(surface._cell_direction(forest))
		for frame in 240:
			if surface.objects_loaded:
				break
			await process_frame
		_check(not surface.placements.is_empty(), "HTTP-generated forest contains actual Kenney objects")
		var maximum_error := 0.0
		for placement in surface.placements:
			var point: Array = placement.coordinates
			var radius := sqrt(float(point[0]) * point[0] + float(point[1]) * point[1] + float(point[2]) * point[2])
			maximum_error = maxf(maximum_error, absf(radius - surface.RADIUS * 1000.0 - surface.elevation64(point) * 1000.0))
		_check(maximum_error < 0.001, "All live server object heights match client scalar terrain within one millimetre")
	_check(surface.get_node_or_null("Rivers") != null, "HTTP drainage generates a river mesh")

func _capture(world: Node3D, surface: Node3D, data: Dictionary) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(35, 140, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 0.5
	world.add_child(sun)
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.background_mode = Environment.BG_COLOR
	sky.environment.background_color = Color(0.55, 0.72, 0.82)
	sky.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.environment.ambient_light_color = Color.WHITE
	sky.environment.ambient_light_energy = 0.65
	world.add_child(sky)
	var camera := Camera3D.new()
	camera.near = 0.001
	camera.far = 20.0
	world.add_child(camera)
	camera.make_current()
	for biome in [5, 7, 6, 1]:
		data.biomes.fill(biome)
		data.water_m.fill(2000 if biome == 1 else -8001)
		_check(surface.apply_environment(data, "fixture", "43"), "Visual fixture applies")
		surface.show_region(Vector3.FORWARD)
		_check(surface.apply_objects(_object_fixture(surface, biome)), "Visual fixture uses authoritative-format object descriptors")
		var height: float = 2.0 if biome == 1 else surface.elevation(Vector3.FORWARD)
		var anchor: Array = [0.0, 0.0, -(surface.RADIUS + height) * 1000.0]
		surface.set_render_origin(anchor)
		var center := Vector3.ZERO
		camera.position = center + Vector3(0.07, 0.0, -0.055)
		camera.look_at(center, Vector3.FORWARD)
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
			root.get_window().size = dimensions
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			screenshot.save_png("/tmp/ishtaria-environment-%s-%dx%d.png" % [surface.BIOMES[biome], dimensions.x, dimensions.y])
			var colors := {}
			for row in range(0, screenshot.get_height(), 8):
				for column in range(0, screenshot.get_width(), 8):
					colors[screenshot.get_pixel(column, row).to_html()] = true
			_check(colors.size() > 20, "Native %s renders nonblank assets/water at %s" % [surface.BIOMES[biome], dimensions])