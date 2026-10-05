extends Node3D

signal objects_failed(message: String)

const RADIUS := 6371.0
const BIOMES := ["ocean", "lake", "river", "beach", "grassland", "forest", "mountain", "snow"]
const MAX_OBJECTS := 512
const DETAIL_RADIUS := 0.7
const DETAIL_SEGMENTS := 128
const MEMORIALS := preload("res://scripts/survival_panel.gd")

var heightmap: Image
var environment: Dictionary = {}
var catalog: Array[Dictionary] = []
var placements: Array[Dictionary] = []
var land_material: ShaderMaterial
var water_material: ShaderMaterial
var detail: Node3D
var objects: Node3D
var memorials: Node3D
var target := Vector3.ZERO
var server_url := ""
var objects_loaded := false
var _origin_metres: Array = []
var _models: Dictionary = {}
var _objects_request: HTTPRequest
var _region_generation := 0
var _scenes: Dictionary = {}
var _detail_vertices := PackedVector3Array()
var _memorial_entries: Array = []
var _memorial_request: HTTPRequest
var _memorial_elapsed := 0.0

func _ready() -> void:
	load_catalog("res://assets/world_objects.json")
	detail = Node3D.new()
	add_child(detail)
	detail.top_level = true
	objects = Node3D.new()
	add_child(objects)
	objects.top_level = true
	memorials = Node3D.new()
	add_child(memorials)
	memorials.top_level = true

func _process(delta: float) -> void:
	_memorial_elapsed += delta
	if _memorial_elapsed >= 5.0:
		_memorial_elapsed = 0.0
		_request_memorials()

func load_catalog(path: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("objects") is Array:
		return false
	var validated: Array[Dictionary] = []
	var identifiers := {}
	for entry: Variant in parsed.objects:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("scene") is String or not entry.get("biomes") is Array:
			return false
		if entry.id.is_empty() or identifiers.has(entry.id) or not entry.scene.begins_with("res://") or not ResourceLoader.exists(entry.scene, "PackedScene"):
			return false
		for biome: Variant in entry.biomes:
			if not biome is String or not biome in BIOMES:
				return false
		for key in ["weight", "scale_m", "max_slope"]:
			var value: Variant = entry.get(key)
			if not (value is float or value is int) or not is_finite(float(value)) or value <= 0 or value > 1000:
				return false
		identifiers[entry.id] = entry
		if entry.has("metallic"):
			var metallic: Variant = entry.metallic
			if not (metallic is float or metallic is int) or not is_finite(float(metallic)) or metallic < 0 or metallic > 1:
				return false
		validated.append(entry)
	if validated.is_empty() or validated.size() > 256:
		return false
	catalog = validated
	_models = identifiers
	_scenes.clear()
	return true

func apply_environment(data: Variant, expected_sha256: String, expected_seed: String) -> bool:
	if not data is Dictionary or (data.get("version") != 1 and data.get("version") != 2) or data.get("heightmap_sha256") != expected_sha256 or data.get("seed") != expected_seed:
		return false
	var size: Variant = data.get("face_size")
	if not (size is float or size is int) or size < 1 or size > 64 or float(size) != floorf(float(size)):
		return false
	var count := int(size) * int(size) * 6
	for key in ["elevation_m", "water_m", "downstream", "flow", "biomes"]:
		if not data.get(key) is Array or data[key].size() != count:
			return false
		for value: Variant in data[key]:
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) != floorf(float(value)):
				return false
	for index in count:
		if data.biomes[index] < 0 or data.biomes[index] > 7 or data.elevation_m[index] < -8000 or data.elevation_m[index] > 8000 or data.water_m[index] < -8001 or data.water_m[index] > 8000 or data.downstream[index] < -1 or data.downstream[index] >= count or data.downstream[index] == index or data.flow[index] < 1 or data.flow[index] > count:
			return false
	environment = data.duplicate(true)
	_clear_objects()
	var atlas := Image.create(int(size) * 6, int(size), false, Image.FORMAT_RGBAF)
	for face in 6:
		for row in int(size):
			for column in int(size):
				var index := face * int(size) * int(size) + row * int(size) + column
				atlas.set_pixel(face * int(size) + column, row, Color((data.water_m[index] + 8000.0) / 16000.0, data.biomes[index] / 7.0, 0, 1))
	var texture := ImageTexture.create_from_image(atlas)
	for material in [land_material, water_material]:
		material.set_shader_parameter("environment_map", texture)
		material.set_shader_parameter("has_environment", true)
	_build_rivers()
	show_region(target)
	return true

func clear_world() -> void:
	environment.clear()
	heightmap = null
	target = Vector3.ZERO
	server_url = ""
	_origin_metres.clear()
	placements.clear()
	for child in get_children():
		if child != detail and child != objects and child != memorials:
			remove_child(child)
			child.queue_free()
	_clear_region()
	for material in [land_material, water_material]:
		material.set_shader_parameter("has_environment", false)
		material.set_shader_parameter("detail_direction", Vector3.ZERO)

func cube_point(face: int, horizontal: float, vertical: float) -> Vector3:
	var point: Vector3
	match face:
		0: point = Vector3(1, vertical, -horizontal)
		1: point = Vector3(-1, vertical, horizontal)
		2: point = Vector3(horizontal, 1, -vertical)
		3: point = Vector3(horizontal, -1, vertical)
		4: point = Vector3(horizontal, vertical, 1)
		_: point = Vector3(-horizontal, vertical, -1)
	return Vector3(
		point.x * sqrt(1.0 - point.y * point.y / 2.0 - point.z * point.z / 2.0 + point.y * point.y * point.z * point.z / 3.0),
		point.y * sqrt(1.0 - point.x * point.x / 2.0 - point.z * point.z / 2.0 + point.x * point.x * point.z * point.z / 3.0),
		point.z * sqrt(1.0 - point.x * point.x / 2.0 - point.y * point.y / 2.0 + point.x * point.x * point.y * point.y / 3.0))

func coordinates(direction: Vector3) -> Vector3:
	var mapped := _coordinates64([direction.x, direction.y, direction.z])
	return Vector3(mapped[0], mapped[1], mapped[2])

func _coordinates64(direction: Array) -> Array:
	var radius := sqrt(float(direction[0]) * direction[0] + float(direction[1]) * direction[1] + float(direction[2]) * direction[2])
	var point: Array = [float(direction[0]) / radius, float(direction[1]) / radius, float(direction[2]) / radius]
	var magnitude: Array = [absf(point[0]), absf(point[1]), absf(point[2])]
	var face: int
	var pair: Array
	if magnitude[0] >= magnitude[1] and magnitude[0] >= magnitude[2]:
		face = 0 if point[0] >= 0 else 1
		pair = [-point[2] if face == 0 else point[2], point[1]]
	elif magnitude[1] >= magnitude[2]:
		face = 2 if point[1] >= 0 else 3
		pair = [point[0], -point[2] if face == 2 else point[2]]
	else:
		face = 4 if point[2] >= 0 else 5
		pair = [point[0] if face == 4 else -point[0], point[1]]
	var squared: Array = [float(pair[0]) * pair[0], float(pair[1]) * pair[1]]
	var result: Array = [0.0, 0.0]
	for axis in 2:
		var coefficient: float = 3.0 + 2.0 * (squared[axis] - squared[1 - axis])
		result[axis] = signf(pair[axis]) * sqrt(maxf(0.5 * (coefficient - sqrt(maxf(coefficient * coefficient - 24.0 * squared[axis], 0.0))), 0.0))
	return [face, clampf((result[0] + 1.0) * 0.5, 0, 1), clampf((1.0 - result[1]) * 0.5, 0, 1)]

func elevation(direction: Vector3) -> float:
	return elevation64([direction.x, direction.y, direction.z])

func relief64(direction: Array, base_metres: float, seed: String) -> float:
	var radius := sqrt(float(direction[0]) * direction[0] + float(direction[1]) * direction[1] + float(direction[2]) * direction[2])
	var point: Array = [float(direction[0]) / radius * 6371000.0, float(direction[1]) / radius * 6371000.0, float(direction[2]) / radius * 6371000.0]
	var hash := 0
	for byte in seed.to_utf8_buffer():
		hash = (hash * 31 + byte) % 997
	var phase := float(hash) * TAU / 997.0
	var coast := clampf(base_metres / 150.0, 0.0, 1.0)
	var fade := coast * coast * (3.0 - 2.0 * coast)
	return fade * (9.0 * sin((point[0] * 0.73 + point[1] * 0.41 + point[2] * 0.55) / 93.0 + phase) * sin((point[0] * -0.38 + point[1] * 0.87 + point[2] * 0.31) / 127.0 - phase) + 3.0 * sin((point[0] * 0.21 + point[1] * -0.52 + point[2] * 0.83) / 37.0 + phase))

func elevation64(direction: Array) -> float:
	if heightmap == null:
		return 0.0
	var mapped := _coordinates64(direction)
	var size := heightmap.get_height()
	var horizontal := clampf(mapped[1] * size - 0.5, 0, size - 1)
	var vertical := clampf(mapped[2] * size - 0.5, 0, size - 1)
	var column := int(horizontal)
	var row := int(vertical)
	var offset := int(mapped[0]) * size
	var upper := lerpf(roundf(heightmap.get_pixel(offset + column, row).r * 255.0), roundf(heightmap.get_pixel(offset + mini(column + 1, size - 1), row).r * 255.0), horizontal - column)
	var lower := lerpf(roundf(heightmap.get_pixel(offset + column, mini(row + 1, size - 1)).r * 255.0), roundf(heightmap.get_pixel(offset + mini(column + 1, size - 1), mini(row + 1, size - 1)).r * 255.0), horizontal - column)
	var base := lerpf(upper, lower, vertical - row) * 16000.0 / 255.0 - 8000.0
	return (base + (relief64(direction, base, environment.seed) if environment.get("version") == 2 else 0.0)) / 1000.0

func environment_index(direction: Vector3) -> int:
	var mapped := coordinates(direction)
	var size := int(environment.face_size)
	return int(mapped.x) * size * size + mini(int(mapped.z * size), size - 1) * size + mini(int(mapped.y * size), size - 1)

func _cell_direction(index: int) -> Vector3:
	var size := int(environment.face_size)
	return cube_point(index / (size * size), (index % size + 0.5) * 2.0 / size - 1.0, 1.0 - (int(index / size) % size + 0.5) * 2.0 / size)

func _build_rivers() -> void:
	for child in get_children():
		if child.name == "Rivers":
			remove_child(child)
			child.queue_free()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := 0
	for index in environment.biomes.size():
		var destination := int(environment.downstream[index])
		if int(environment.biomes[index]) != 2 or destination < 0:
			continue
		var start := _cell_direction(index)
		var end := _cell_direction(destination)
		var sideways := start.cross(end).normalized()
		var width := minf(0.00015, 0.00002 * sqrt(float(environment.flow[index])))
		for step in 16:
			var first := start.slerp(end, step / 16.0).normalized()
			var second := start.slerp(end, (step + 1.0) / 16.0).normalized()
			var corners: Array[Vector3] = []
			for direction in [first - sideways * width, first + sideways * width, second - sideways * width, second + sideways * width]:
				var unit: Vector3 = direction.normalized()
				var water := maxf(elevation(unit), 0.0)
				var sample_index := environment_index(unit)
				if int(environment.biomes[sample_index]) == 1:
					water = maxf(water, environment.water_m[sample_index] / 1000.0)
				corners.append(unit * (RADIUS + water + 0.003))
			for corner in [0, 2, 1, 1, 2, 3]:
				tool.set_normal(corners[corner].normalized())
				tool.add_vertex(corners[corner])
				vertices += 1
	if vertices == 0:
		return
	var rivers := MeshInstance3D.new()
	rivers.name = "Rivers"
	rivers.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.035, 0.25, 0.38)
	material.roughness = 0.28
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rivers.material_override = material
	add_child(rivers)

func _cancel_objects() -> void:
	_region_generation += 1
	if is_instance_valid(_objects_request):
		_objects_request.cancel_request()
		_objects_request.queue_free()
	_objects_request = null
	if is_instance_valid(_memorial_request):
		_memorial_request.cancel_request()
		_memorial_request.queue_free()
	_memorial_request = null

func _clear_objects() -> void:
	placements.clear()
	objects_loaded = false
	_memorial_entries.clear()
	for child in memorials.get_children():
		memorials.remove_child(child)
		child.queue_free()
	for child in objects.get_children():
		objects.remove_child(child)
		child.queue_free()

func _clear_region(clear_objects: bool = true) -> void:
	_cancel_objects()
	_detail_vertices.clear()
	if clear_objects:
		_clear_objects()
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	land_material.set_shader_parameter("detail_direction", Vector3.ZERO)
	water_material.set_shader_parameter("detail_direction", Vector3.ZERO)

func show_region(direction: Vector3) -> void:
	target = direction
	_clear_region(direction == Vector3.ZERO or heightmap == null or environment.is_empty())
	if direction == Vector3.ZERO or heightmap == null or environment.is_empty():
		return
	_build_detail()
	_request_objects(direction.normalized())

func _build_detail() -> void:
	_detail_vertices.clear()
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	if target == Vector3.ZERO or heightmap == null or environment.is_empty():
		return
	var unit := target.normalized()
	var reference := Vector3.UP if absf(unit.y) < 0.9 else Vector3.RIGHT
	var tangent := reference.cross(unit).normalized()
	var forward := unit.cross(tangent).normalized()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water_tool := SurfaceTool.new()
	water_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in DETAIL_SEGMENTS + 1:
		for column in DETAIL_SEGMENTS + 1:
			var horizontal: float = (float(column) / DETAIL_SEGMENTS * 2.0 - 1.0) * DETAIL_RADIUS
			var vertical: float = (float(row) / DETAIL_SEGMENTS * 2.0 - 1.0) * DETAIL_RADIUS
			var direction: Array = []
			for axis in 3:
				direction.append(float(unit[axis]) * RADIUS + float(tangent[axis]) * horizontal + float(forward[axis]) * vertical)
			var length64 := sqrt(float(direction[0]) * direction[0] + float(direction[1]) * direction[1] + float(direction[2]) * direction[2])
			for axis in 3:
				direction[axis] /= length64
			var point := Vector3(direction[0], direction[1], direction[2])
			var height := elevation64(direction)
			var water := float(environment.water_m[environment_index(point)]) / 1000.0 + 0.001
			tool.set_normal(point)
			tool.set_uv2(Vector2(height, 0))
			tool.add_vertex(_render_position([direction[0] * (RADIUS + height) * 1000.0, direction[1] * (RADIUS + height) * 1000.0, direction[2] * (RADIUS + height) * 1000.0]))
			water_tool.set_normal(point)
			water_tool.set_uv2(Vector2(height, 0))
			water_tool.add_vertex(_render_position([direction[0] * (RADIUS + water) * 1000.0, direction[1] * (RADIUS + water) * 1000.0, direction[2] * (RADIUS + water) * 1000.0]))
	for row in DETAIL_SEGMENTS:
		for column in DETAIL_SEGMENTS:
			var first := row * (DETAIL_SEGMENTS + 1) + column
			for index in [first, first + DETAIL_SEGMENTS + 1, first + 1, first + 1, first + DETAIL_SEGMENTS + 1, first + DETAIL_SEGMENTS + 2]:
				tool.add_index(index)
				water_tool.add_index(index)
	var mesh := tool.commit()
	_detail_vertices = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var local_land := MeshInstance3D.new()
	local_land.mesh = mesh
	var material := land_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("is_detail", true)
	local_land.material_override = material
	detail.add_child(local_land)
	var local_water := MeshInstance3D.new()
	local_water.mesh = water_tool.commit()
	var water_detail := water_material.duplicate() as ShaderMaterial
	water_detail.set_shader_parameter("is_detail", true)
	var anchor: Array = _origin_metres if _origin_metres.size() == 3 else [0.0, 0.0, 0.0]
	water_detail.set_shader_parameter("wave_phase", Vector2(fposmod((anchor[0] + anchor[1] * 0.7 + anchor[2] * 0.3) * 0.65, TAU), fposmod((anchor[0] * 0.2 + anchor[1] * 0.5 + anchor[2]) * 0.7, TAU)))
	local_water.material_override = water_detail
	detail.add_child(local_water)
	land_material.set_shader_parameter("detail_direction", unit)
	water_material.set_shader_parameter("detail_direction", unit)

func ground_position64(coordinates_metres: Array) -> Vector3:
	var radius := sqrt(float(coordinates_metres[0]) * coordinates_metres[0] + float(coordinates_metres[1]) * coordinates_metres[1] + float(coordinates_metres[2]) * coordinates_metres[2])
	var direction: Array = [float(coordinates_metres[0]) / radius, float(coordinates_metres[1]) / radius, float(coordinates_metres[2]) / radius]
	var height := elevation64(direction)
	var projected: Array = []
	for axis in 3:
		projected.append(direction[axis] * (RADIUS + height) * 1000.0)
	var point := _render_position(projected)
	if _detail_vertices.is_empty() or target == Vector3.ZERO:
		return point
	var up := Vector3(direction[0], direction[1], direction[2])
	var unit := target.normalized()
	var reference := Vector3.UP if absf(unit.y) < 0.9 else Vector3.RIGHT
	var tangent := reference.cross(unit).normalized()
	var forward := unit.cross(tangent).normalized()
	var denominator := up.dot(unit)
	if denominator <= 0:
		return point
	var column := int(floor((up.dot(tangent) * RADIUS / denominator / DETAIL_RADIUS + 1.0) * 0.5 * DETAIL_SEGMENTS))
	var row := int(floor((up.dot(forward) * RADIUS / denominator / DETAIL_RADIUS + 1.0) * 0.5 * DETAIL_SEGMENTS))
	for sample_row in range(maxi(0, row - 1), mini(DETAIL_SEGMENTS, row + 2)):
		for sample_column in range(maxi(0, column - 1), mini(DETAIL_SEGMENTS, column + 2)):
			var first := sample_row * (DETAIL_SEGMENTS + 1) + sample_column
			for triangle in [[first, first + DETAIL_SEGMENTS + 1, first + 1], [first + 1, first + DETAIL_SEGMENTS + 1, first + DETAIL_SEGMENTS + 2]]:
				var hit: Variant = Geometry3D.ray_intersects_triangle(point + up * 0.002, -up, _detail_vertices[triangle[0]], _detail_vertices[triangle[1]], _detail_vertices[triangle[2]])
				if hit is Vector3 and hit.distance_to(point) < 0.002:
					return hit
	return point

func _request_objects(unit: Vector3) -> void:
	if server_url.is_empty():
		return
	_objects_request = HTTPRequest.new()
	_objects_request.timeout = 8.0
	_objects_request.max_redirects = 0
	_objects_request.body_size_limit = 2 * 1024 * 1024
	_objects_request.request_completed.connect(_on_objects_received.bind(_region_generation))
	add_child(_objects_request)
	var point := unit * RADIUS * 1000.0
	if _objects_request.request(server_url + "/world/objects?x=%.9f&y=%.9f&z=%.9f" % [point.x, point.y, point.z]) != OK:
		_cancel_objects()
		objects_failed.emit("Surface objects unavailable")

func _on_objects_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if generation != _region_generation:
		return
	if is_instance_valid(_objects_request):
		_objects_request.queue_free()
	_objects_request = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not apply_objects(JSON.parse_string(body.get_string_from_utf8())):
		objects_failed.emit("Surface objects unavailable")

func apply_objects(data: Variant) -> bool:
	if environment.is_empty() or not data is Dictionary or data.get("version") != 1 or data.get("heightmap_sha256") != environment.heightmap_sha256 or data.get("seed") != environment.seed:
		return false
	if not data.get("objects") is Array or data.objects.size() > MAX_OBJECTS:
		return false
	var identities := {}
	for entry: Variant in data.objects:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or identities.has(entry.id) or not entry.get("model") is String or not _models.has(entry.model):
			return false
		identities[entry.id] = true
		if not entry.get("position") is Array or entry.position.size() != 3:
			return false
		for value: Variant in entry.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
				return false
		var point := Vector3(entry.position[0] / 1000.0, entry.position[1] / 1000.0, entry.position[2] / 1000.0)
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1 or (target != Vector3.ZERO and point.normalized().distance_to(target.normalized()) * RADIUS > DETAIL_RADIUS * 1.2):
			return false
		for key in ["scale_m", "yaw", "collision_radius_m", "biome"]:
			var value: Variant = entry.get(key)
			if not (value is float or value is int) or not is_finite(float(value)):
				return false
		if entry.scale_m <= 0 or entry.scale_m > 20 or entry.yaw < 0 or entry.yaw > TAU or entry.collision_radius_m < 0 or entry.collision_radius_m > 20 or entry.biome < 0 or entry.biome > 7 or entry.biome != floor(entry.biome):
			return false
		if not BIOMES[int(entry.biome)] in _models[entry.model].biomes:
			return false
	_clear_objects()
	for entry: Dictionary in data.objects:
		_place_object(entry)
	if not apply_memorials(data.get("memorials", [])):
		return false
	objects_loaded = true
	return true

func _request_memorials() -> void:
	if server_url.is_empty() or target == Vector3.ZERO or not objects_loaded or is_instance_valid(_memorial_request):
		return
	_memorial_request = HTTPRequest.new()
	_memorial_request.timeout = 4.0
	_memorial_request.max_redirects = 0
	_memorial_request.body_size_limit = 65536
	_memorial_request.request_completed.connect(_on_memorials_received.bind(_region_generation))
	add_child(_memorial_request)
	var point := target.normalized() * RADIUS * 1000.0
	if _memorial_request.request(server_url + "/world/memorials?x=%.9f&y=%.9f&z=%.9f" % [point.x, point.y, point.z]) != OK:
		_memorial_request.queue_free()
		_memorial_request = null

func _on_memorials_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if generation != _region_generation:
		return
	if is_instance_valid(_memorial_request):
		_memorial_request.queue_free()
	_memorial_request = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		apply_memorials(JSON.parse_string(body.get_string_from_utf8()))

func apply_memorials(data: Variant) -> bool:
	if not data is Array or data.size() > 128:
		return false
	var identities := {}
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String or not entry.id.is_valid_int() or int(entry.id) <= 0 or identities.has(entry.id) or not entry.get("player_name") is String or not MEMORIALS.MODELS.has(entry.get("kind")):
			return false
		identities[entry.id] = true
		if not entry.get("position") is Array or entry.position.size() != 3:
			return false
		for value: Variant in entry.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
				return false
		var point := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1 or (target != Vector3.ZERO and point.normalized().distance_to(target.normalized()) * RADIUS > DETAIL_RADIUS * 1.02):
			return false
	if data == _memorial_entries:
		return true
	for child in memorials.get_children():
		memorials.remove_child(child)
		child.queue_free()
	_memorial_entries = data.duplicate(true)
	for entry: Dictionary in data:
		var placement := Node3D.new()
		placement.name = "Grave" + entry.id
		placement.position = _render_position(entry.position)
		var up := Vector3(entry.position[0], entry.position[1], entry.position[2]).normalized()
		placement.quaternion = Quaternion(Vector3.UP, up)
		placement.scale = Vector3.ONE / 1000.0
		placement.add_child(MEMORIALS.create_memorial(entry.kind))
		memorials.add_child(placement)
	return true

func set_render_origin(coordinates_metres: Array) -> void:
	_origin_metres = coordinates_metres.duplicate()
	for index in placements.size():
		objects.get_child(index).position = _render_position(placements[index].coordinates)
	for index in _memorial_entries.size():
		memorials.get_child(index).position = _render_position(_memorial_entries[index].position)
	_build_detail()

func _render_position(metres: Array) -> Vector3:
	var anchor: Array = _origin_metres if _origin_metres.size() == 3 else [0.0, 0.0, 0.0]
	return Vector3((float(metres[0]) - anchor[0]) / 1000.0, (float(metres[1]) - anchor[1]) / 1000.0, (float(metres[2]) - anchor[2]) / 1000.0)

func _place_object(entry: Dictionary) -> void:
	var selected: Dictionary = _models[entry.model]
	if not _scenes.has(selected.id):
		_scenes[selected.id] = load(selected.scene)
	var model: Node = _scenes[selected.id].instantiate()
	if not model is Node3D:
		model.free()
		return
	if selected.has("metallic"):
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if model is MeshInstance3D:
			meshes.append(model)
		for mesh_instance: MeshInstance3D in meshes:
			for surface in mesh_instance.mesh.get_surface_count():
				var source := mesh_instance.get_active_material(surface)
				if source is StandardMaterial3D:
					var material := source.duplicate() as StandardMaterial3D
					material.metallic = selected.metallic
					mesh_instance.set_surface_override_material(surface, material)
	var placement := Node3D.new()
	placement.name = entry.id.validate_node_name()
	placement.position = _render_position(entry.position)
	var point := Vector3(entry.position[0] / 1000.0, entry.position[1] / 1000.0, entry.position[2] / 1000.0)
	placement.quaternion = Quaternion(Vector3.UP, point.normalized()) * Quaternion(Vector3.UP, entry.yaw)
	placement.scale = Vector3.ONE * entry.scale_m / 1000.0
	placement.add_child(model)
	objects.add_child(placement)
	placements.append({"id":entry.id,"model":selected.id,"position":point,"coordinates":entry.position.duplicate(),"scale":placement.scale,"rotation":placement.quaternion,"biome":BIOMES[int(entry.biome)],"collision_radius_m":entry.collision_radius_m})