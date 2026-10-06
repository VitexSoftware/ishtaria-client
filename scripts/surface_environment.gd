extends Node3D

signal objects_failed(message: String)

const RADIUS := 6371.0
const BIOMES := ["ocean", "lake", "river", "beach", "grassland", "forest", "mountain", "snow"]
const MAX_OBJECTS := 512
const PORTAL_MODEL := "res://assets/kenney/survival-kit/Models/GLB format/structure-metal-doorway.glb"
const PORTAL_STATES := ["building", "open", "closed"]
## Scale of the gate model: the model is half a metre tall, so the portal is four metres tall.
const PORTAL_SCALE_M := 8.0
const DETAIL_RADIUS := 0.7
const DETAIL_SEGMENTS := 128
const MEMORIALS := preload("res://scripts/survival_panel.gd")
const CHARACTERS := preload("res://scripts/character_catalog.gd")
const FACE := preload("res://scripts/character_face.gd")
const MAX_NPCS := 64
const MAX_PROPS := 3000
## Kenney kits whose models the server's generated places are built from.
## Models with a light: where the lamp hangs (model units, scaled like the model).
const LAMP_MODELS := {"graveyard.lightpost-single": [0.0, 1.1, 0.25]}
## Gas lamps: a dim, warm, slightly flickering flame; halogen-strong lights blow out the pale gravestones.
const LAMP_RANGE_M := 7.0
## The scene is in kilometres and Godot's omni falloff is pow(distance, -attenuation) in scene units, so the
## energy is tiny: 3e-6 = intensity 3.0 at one metre (0.75 at two, 0.08 at six) with attenuation 2.
const LAMP_ENERGY := 3.0e-6
const LAMP_FLICKER := 0.07
const PROP_KITS := {"graveyard": "graveyard-kit", "town": "fantasy-town-kit", "castle": "castle-kit", "retro": "retro-fantasy-kit", "pirate": "pirate-kit", "quaternius": ""}

var heightmap: Image
var environment: Dictionary = {}
var catalog: Array[Dictionary] = []
var placements: Array[Dictionary] = []
## Fish circling around their place: {"node", "radius", "speed", "phase"} with the radius in model units.
var _swimmers: Array[Dictionary] = []
var land_material: ShaderMaterial
var water_material: ShaderMaterial
var detail: Node3D
var objects: Node3D
var memorials: Node3D
## Characters of story datadisks, standing near the player.
var npcs: Node3D
## Buildings, fences, ships and other props of towns, graveyards and harbours.
var props: Node3D
## Lamps of the generated places: warm lights (and glowing bulbs) that burn at night.
var lamps: Node3D
var _prop_entries: Array = []
var _lamp_positions: Array = []
var _night := 0.0
var _lamp_time := 0.0
var _prop_scenes: Dictionary = {}
## Turns a translation key into text (set by the game once the story is loaded).
var npc_text := Callable()
## Asks the story client for a media file (a character model); answered through `media_ready`.
var fetch_media := Callable()
var _npc_entries: Array = []
var portals: Node3D
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
var _portal_entries: Array = []
var _portal_request: HTTPRequest
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
	npcs = Node3D.new()
	add_child(npcs)
	npcs.top_level = true
	props = Node3D.new()
	add_child(props)
	props.top_level = true
	lamps = Node3D.new()
	add_child(lamps)
	lamps.top_level = true
	portals = Node3D.new()
	add_child(portals)
	portals.top_level = true

func _process(delta: float) -> void:
	_swim()
	_flicker_lamps(delta)
	_memorial_elapsed += delta
	if _memorial_elapsed >= 5.0:
		_memorial_elapsed = 0.0
		_request_memorials()
		refresh_portals()

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
		if entry.has("animation") and (not entry.animation is String or entry.animation.is_empty() or entry.animation.length() > 40):
			return false
		if entry.has("swim_radius_m"):
			var radius: Variant = entry.swim_radius_m
			if not (radius is float or radius is int) or not is_finite(float(radius)) or radius <= 0 or radius > 50:
				return false
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
		if child != detail and child != objects and child != memorials and child != portals and child != npcs and child != props and child != lamps:
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
	if is_instance_valid(_portal_request):
		_portal_request.cancel_request()
		_portal_request.queue_free()
	_portal_request = null

## Portals stay while the objects are replaced; they are cleared with the region.
func _clear_portals() -> void:
	_portal_entries.clear()
	for child in portals.get_children():
		portals.remove_child(child)
		child.queue_free()

func _clear_objects() -> void:
	placements.clear()
	_swimmers.clear()
	objects_loaded = false
	_memorial_entries.clear()
	_clear_npcs()
	_clear_props()
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
		_clear_portals()
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
	apply_npcs(data.get("npcs", []))
	apply_props(data.get("props", []))
	apply_areas(data.get("areas", []))
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

## Requests the portals near the region; also called when a pact changes.
func refresh_portals() -> void:
	if server_url.is_empty() or target == Vector3.ZERO or not objects_loaded or is_instance_valid(_portal_request):
		return
	_portal_request = HTTPRequest.new()
	_portal_request.timeout = 4.0
	_portal_request.max_redirects = 0
	_portal_request.body_size_limit = 65536
	_portal_request.request_completed.connect(_on_portals_received.bind(_region_generation))
	add_child(_portal_request)
	var point := target.normalized() * RADIUS * 1000.0
	if _portal_request.request(server_url + "/world/portals?x=%.9f&y=%.9f&z=%.9f" % [point.x, point.y, point.z]) != OK:
		_portal_request.queue_free()
		_portal_request = null

func _on_portals_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if generation != _region_generation:
		return
	if is_instance_valid(_portal_request):
		_portal_request.queue_free()
	_portal_request = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		apply_portals(JSON.parse_string(body.get_string_from_utf8()))

## Draws the portals the server reports: under construction, open and closed ruins.
func apply_portals(data: Variant) -> bool:
	if not data is Array or data.size() > 64:
		return false
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("name") is String or not entry.get("peer") is String or not entry.get("state") in PORTAL_STATES or not entry.get("position") is Array or entry.position.size() != 3:
			return false
		for value: Variant in entry.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
				return false
		var point := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
			return false
	if data == _portal_entries:
		return true
	for child in portals.get_children():
		portals.remove_child(child)
		child.queue_free()
	_portal_entries = data.duplicate(true)
	var scene: PackedScene = load(PORTAL_MODEL)
	for entry: Dictionary in data:
		var placement := Node3D.new()
		placement.name = "Portal_" + String(entry.name).validate_node_name()
		placement.position = _render_position(entry.position)
		var up := Vector3(entry.position[0], entry.position[1], entry.position[2]).normalized()
		placement.quaternion = Quaternion(Vector3.UP, up) * Quaternion(Vector3.UP, float(String(entry.name).hash() % 628) / 100.0)
		placement.scale = Vector3.ONE * PORTAL_SCALE_M / 1000.0
		var model: Node3D = scene.instantiate()
		_tint_portal(model, entry.state)
		placement.add_child(model)
		portals.add_child(placement)
	return true

## Open portals glow, portals under construction are plain metal and ruins are dark.
func _tint_portal(model: Node, state: String) -> void:
	for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
			var source := instance.get_active_material(surface)
			if not source is StandardMaterial3D:
				continue
			var material := source.duplicate() as StandardMaterial3D
			match state:
				"open":
					material.emission_enabled = true
					material.emission = Color(0.2, 0.8, 1.0)
					material.emission_energy_multiplier = 1.4
				"closed":
					material.albedo_color = Color(0.35, 0.35, 0.38)
			instance.set_surface_override_material(surface, material)

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

## Characters of the story. A malformed entry is skipped; it never spoils the region.
func apply_npcs(data: Variant) -> bool:
	_clear_npcs()
	if not data is Array or data.size() > MAX_NPCS:
		return false
	var identities := {}
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or identities.has(entry.id) or not entry.get("name_key") is String:
			continue
		if not entry.get("character") is String or not CHARACTERS.is_valid(entry.character) or not entry.get("position") is Array or entry.position.size() != 3:
			continue
		var finite := true
		for value: Variant in entry.position:
			finite = finite and (value is float or value is int) and is_finite(float(value)) and absf(value) <= 7000000.0
		for key in ["yaw", "scale_m"]:
			finite = finite and (entry.get(key) is float or entry.get(key) is int) and is_finite(float(entry[key]))
		if not finite or entry.scale_m <= 0 or entry.scale_m > 6 or entry.yaw < 0 or entry.yaw > TAU:
			continue
		var point := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
			continue
		identities[entry.id] = true
		var model := CHARACTERS.create_model(entry.character)
		if model == null:
			continue
		var placement := Node3D.new()
		placement.name = ("Npc" + entry.id).validate_node_name()
		placement.position = _render_position(entry.position)
		placement.quaternion = Quaternion(Vector3.UP, point.normalized()) * Quaternion(Vector3.UP, entry.yaw)
		placement.scale = Vector3.ONE * (float(entry.scale_m) / 1.8) / 1000.0
		placement.add_child(model)
		_attach_face(model)
		var label := Label3D.new()
		label.name = "Name"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.006
		label.font_size = 40
		label.outline_size = 12
		# Just above the head, whatever the character pack's proportions.
		var head := CHARACTERS.head_height(model)
		label.position = Vector3(0, head * 1.08, 0)
		label.no_depth_test = false
		label.text = _npc_name(entry.name_key)
		placement.add_child(label)
		npcs.add_child(placement)
		_npc_entries.append(entry.duplicate(true))
		if entry.get("model") != null and fetch_media.is_valid() and preload("res://scripts/story_client.gd").valid_media_url(entry.model) and entry.model.ends_with(".glb"):
			fetch_media.call(entry.model)
	return true

## A character model arrived: it replaces the pack character of the NPCs that name it.
## Only the NPCs of the current region are looked at, so a late answer cannot change anything else.
func media_ready(url: String, resource: Resource) -> void:
	if not resource is PackedScene or not url.ends_with(".glb"):
		return
	for index in _npc_entries.size():
		if _npc_entries[index].get("model") != url:
			continue
		var placement := npcs.get_child(index)
		var model := (resource as PackedScene).instantiate() as Node3D
		if model == null:
			continue
		for child in placement.get_children():
			if child is Node3D and not child is Label3D:
				placement.remove_child(child)
				child.queue_free()
		# A datadisk's model is authored in metres; the pack characters are larger in client units.
		model.scale *= CHARACTERS.GLTF_UNITS_PER_METRE
		placement.add_child(model)
		_attach_face(model)
		var label := placement.get_node_or_null("Name") as Label3D
		if label != null:
			label.position = Vector3(0, CHARACTERS.head_height(model) * model.scale.y * 1.08, 0)

## A model with blend shapes for the eyes and the mouth blinks and talks.
func _attach_face(model: Node3D) -> void:
	var face := FACE.new()
	face.name = "Face"
	model.add_child(face)
	if not face.setup(model):
		model.remove_child(face)
		face.free()

## The character of a conversation starts or stops talking (it has a face to move, or nothing happens).
func set_npc_talking(npc_id: String, talking: bool) -> void:
	for index in _npc_entries.size():
		if _npc_entries[index].id != npc_id:
			continue
		var face := npcs.get_child(index).find_child("Face", true, false)
		if face != null:
			face.talking = talking

## The path of a generated place's model, or an empty string when it is not bundled.
static func prop_path(model: Variant) -> String:
	if not model is String or model.length() > 60:
		return ""
	var parts: PackedStringArray = model.split(".")
	if parts.size() != 2 or not PROP_KITS.has(parts[0]) or not parts[1].is_valid_filename() or parts[1].contains("/") or parts[1].contains("."):
		return ""
	var path := "res://assets/kenney/%s/%s.glb" % [PROP_KITS[parts[0]], parts[1]]
	if parts[0] == "quaternius":
		# A model has a folder of its own, or is one of the ready-made buildings.
		path = "res://assets/quaternius/%s/Models/%s.glb" % [parts[1], parts[1]]
		if not ResourceLoader.exists(path):
			path = "res://assets/quaternius/buildings/Models/%s.glb" % parts[1]
	return path if ResourceLoader.exists(path) else ""

## Buildings and props of the places nearby. A malformed or unknown entry is skipped.
## Places with background music near the player: id, centre (metres), radius and track.
var areas: Array = []

func apply_areas(data: Variant) -> bool:
	areas = []
	if not data is Array or data.size() > 16:
		return false
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("position") is Array or entry.position.size() != 3:
			return false
		var radius: Variant = entry.get("radius_m")
		var music: Variant = entry.get("music")
		if not (radius is float or radius is int) or radius <= 0 or radius > 6000 or not music is Dictionary or not music.get("loop") is bool or not music.get("title_key") is String or not preload("res://scripts/story_client.gd").valid_media_url(music.get("url")):
			return false
		for value: Variant in entry.position:
			if not (value is float or value is int) or not is_finite(float(value)) or absf(value) > 7000000.0:
				return false
	areas = data.duplicate(true)
	return true

## The area whose music is loudest at a point (metres) with its hearing level, or an empty dictionary.
func area_at(metres: Vector3) -> Dictionary:
	var best := {}
	var best_level := 0.0
	for area: Dictionary in areas:
		var centre := Vector3(area.position[0], area.position[1], area.position[2])
		var level: float = preload("res://scripts/area_music.gd").level_for(centre.distance_to(metres), float(area.radius_m))
		if level > best_level:
			best_level = level
			best = {"area": area, "level": level}
	return best

func apply_props(data: Variant) -> bool:
	_clear_props()
	if not data is Array or data.size() > MAX_PROPS:
		return false
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("position") is Array or entry.position.size() != 3:
			continue
		var path := prop_path(entry.get("model"))
		var finite := not path.is_empty()
		for value: Variant in entry.get("position", []):
			finite = finite and (value is float or value is int) and is_finite(float(value)) and absf(value) <= 7000000.0
		for key in ["yaw", "scale_m"]:
			finite = finite and (entry.get(key) is float or entry.get(key) is int) and is_finite(float(entry[key]))
		if not finite or entry.scale_m <= 0.05 or entry.scale_m > 20:
			continue
		var point := Vector3(entry.position[0], entry.position[1], entry.position[2]) / 1000.0
		if point.length() < RADIUS - 8.1 or point.length() > RADIUS + 8.1:
			continue
		if not _prop_scenes.has(path):
			_prop_scenes[path] = load(path)
		var model: Node = (_prop_scenes[path] as PackedScene).instantiate()
		if not model is Node3D:
			model.free()
			continue
		var placement := Node3D.new()
		placement.position = _render_position(entry.position)
		placement.quaternion = Quaternion(Vector3.UP, point.normalized()) * Quaternion(Vector3.UP, entry.yaw)
		placement.scale = Vector3.ONE * float(entry.scale_m) / 1000.0
		placement.add_child(model)
		props.add_child(placement)
		_prop_entries.append(entry.duplicate(true))
		if LAMP_MODELS.has(entry.model):
			_add_lamp(entry)
	return true

## A lamp post gets a light at its head; it only burns while it is night.
func _add_lamp(entry: Dictionary) -> void:
	var head: Array = LAMP_MODELS[entry.model]
	var scale_m := float(entry.scale_m)
	var point := Vector3(entry.position[0], entry.position[1], entry.position[2])
	var up := point.normalized()
	var turn := Quaternion(Vector3.UP, up) * Quaternion(Vector3.UP, entry.yaw)
	var offset := turn * Vector3(head[0], head[1], head[2]) * scale_m
	var position := [point.x + offset.x, point.y + offset.y, point.z + offset.z]
	var light := OmniLight3D.new()
	light.omni_range = LAMP_RANGE_M / 1000.0
	light.omni_attenuation = 2.0
	light.light_color = Color(1.0, 0.6, 0.26)
	light.set_meta("phase", float(_lamp_positions.size()) * 1.7)
	light.shadow_enabled = false
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07 * scale_m / 1000.0
	sphere.height = sphere.radius * 2.0
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.66, 0.3)
	sphere.material = glow
	bulb.mesh = sphere
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light.add_child(bulb)
	light.position = _render_position(position)
	lamps.add_child(light)
	_lamp_positions.append(position)
	_apply_night(light)

## How dark it is (0 = day, 1 = night); the lamps fade in with the dusk.
func set_night(amount: float) -> void:
	var clamped := clampf(amount, 0.0, 1.0)
	if is_equal_approx(clamped, _night):
		return
	_night = clamped
	for light in lamps.get_children():
		_apply_night(light)

## The flame of a gas lamp wavers a little; each lamp has its own phase.
func _flicker_lamps(delta: float) -> void:
	_lamp_time += delta
	if _night <= 0.02:
		return
	for light: OmniLight3D in lamps.get_children():
		var phase: float = light.get_meta("phase", 0.0)
		var wave := sin(_lamp_time * 7.0 + phase) * 0.6 + sin(_lamp_time * 13.0 + phase * 2.0) * 0.4
		light.light_energy = LAMP_ENERGY * _night * (1.0 + LAMP_FLICKER * wave)

func _apply_night(light: Node) -> void:
	(light as OmniLight3D).light_energy = LAMP_ENERGY * _night
	(light as OmniLight3D).visible = _night > 0.02

func _clear_props() -> void:
	_prop_entries.clear()
	_lamp_positions.clear()
	for lamp in lamps.get_children():
		lamps.remove_child(lamp)
		lamp.queue_free()
	for child in props.get_children():
		props.remove_child(child)
		child.queue_free()

func _npc_name(key: String) -> String:
	return str(npc_text.call(key)) if npc_text.is_valid() else key

## Names are translated when the story strings arrive or the language changes.
func refresh_npc_names() -> void:
	for index in _npc_entries.size():
		var label := npcs.get_child(index).get_node_or_null("Name") as Label3D
		if label != null:
			label.text = _npc_name(_npc_entries[index].name_key)

func _clear_npcs() -> void:
	_npc_entries.clear()
	for child in npcs.get_children():
		npcs.remove_child(child)
		child.queue_free()

## The nearest character within reach of a server position in metres.
func nearest_npc(player_metres: Vector3, reach_m: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for entry: Dictionary in _npc_entries:
		var distance := player_metres.distance_to(Vector3(entry.position[0], entry.position[1], entry.position[2]))
		if distance <= reach_m and distance < best_distance:
			best = entry
			best_distance = distance
	return best

func set_render_origin(coordinates_metres: Array) -> void:
	_origin_metres = coordinates_metres.duplicate()
	for index in placements.size():
		objects.get_child(index).position = _render_position(placements[index].coordinates)
	for index in _memorial_entries.size():
		memorials.get_child(index).position = _render_position(_memorial_entries[index].position)
	for index in _portal_entries.size():
		portals.get_child(index).position = _render_position(_portal_entries[index].position)
	for index in _npc_entries.size():
		npcs.get_child(index).position = _render_position(_npc_entries[index].position)
	for index in _prop_entries.size():
		props.get_child(index).position = _render_position(_prop_entries[index].position)
	for index in _lamp_positions.size():
		lamps.get_child(index).position = _render_position(_lamp_positions[index])
	_build_detail()

func _render_position(metres: Array) -> Vector3:
	var anchor: Array = _origin_metres if _origin_metres.size() == 3 else [0.0, 0.0, 0.0]
	return Vector3((float(metres[0]) - anchor[0]) / 1000.0, (float(metres[1]) - anchor[1]) / 1000.0, (float(metres[2]) - anchor[2]) / 1000.0)

## Plays the looping animation `name` (with or without the armature prefix) of an animated model.
## Every object starts at its own moment so a herd or a shoal does not move in step.
func _animate(model: Node, animation_name: String, identity: String) -> void:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player: AnimationPlayer = players[0]
	for candidate in player.get_animation_list():
		if candidate == animation_name or candidate.ends_with("|" + animation_name):
			var animation := player.get_animation(candidate)
			animation.loop_mode = Animation.LOOP_LINEAR
			player.play(candidate)
			var hash := identity.hash()
			player.seek(float(hash % 1000) / 1000.0 * animation.length, true)
			player.speed_scale = 0.9 + float(hash % 21) / 100.0
			return

## Moves fish around their anchor and turns them along their path.
func _swim() -> void:
	if _swimmers.is_empty():
		return
	var seconds := Time.get_ticks_msec() / 1000.0
	for swimmer in _swimmers:
		var node: Node3D = swimmer.node
		if not is_instance_valid(node):
			continue
		var radius: float = swimmer.radius
		var angle: float = swimmer.phase + seconds * swimmer.speed / radius
		node.position = Vector3(cos(angle), 0.0, sin(angle)) * radius
		node.rotation.y = atan2(-sin(angle), cos(angle))

## What an object can be harvested for, or an empty dictionary for scenery.
func _harvest_info(data: Variant) -> Dictionary:
	if data is Dictionary and data.get("kind") in ["tree", "rock"] and data.get("tool") is String and (data.get("hits") is int or data.get("hits") is float):
		return {"kind": data.kind, "tool": data.tool, "hits": int(data.hits)}
	return {}

## The nearest harvestable object within reach of a server position in metres.
func nearest_harvestable(player_metres: Vector3, reach_m: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for placement: Dictionary in placements:
		if placement.harvest.is_empty():
			continue
		var coordinates: Array = placement.coordinates
		var distance := player_metres.distance_to(Vector3(coordinates[0], coordinates[1], coordinates[2]))
		if distance <= reach_m + float(placement.collision_radius_m) and distance < best_distance:
			best = placement
			best_distance = distance
	return best

## Requests the objects again, for example after a tree was felled.
func refresh_objects() -> void:
	if not server_url.is_empty() and target != Vector3.ZERO and not is_instance_valid(_objects_request):
		_request_objects(target.normalized())

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
	var swimmer: Node3D = null
	if selected.has("animation"):
		_animate(model, selected.animation, entry.id)
		if selected.has("swim_radius_m"):
			swimmer = Node3D.new()
			swimmer.name = "Swimmer"
	var placement := Node3D.new()
	placement.name = entry.id.validate_node_name()
	placement.position = _render_position(entry.position)
	var point := Vector3(entry.position[0] / 1000.0, entry.position[1] / 1000.0, entry.position[2] / 1000.0)
	placement.quaternion = Quaternion(Vector3.UP, point.normalized()) * Quaternion(Vector3.UP, entry.yaw)
	placement.scale = Vector3.ONE * entry.scale_m / 1000.0
	if swimmer != null:
		swimmer.add_child(model)
		placement.add_child(swimmer)
		var hash: int = String(entry.id).hash()
		# Fish swim at 0.3 to 0.9 metres per second on a circle; the radius is in model units.
		var speed := 0.3 + float(hash % 7) * 0.1
		_swimmers.append({"node": swimmer, "radius": float(selected.swim_radius_m) / float(entry.scale_m), "speed": speed / float(entry.scale_m), "phase": float(hash % 628) / 100.0})
	else:
		placement.add_child(model)
	objects.add_child(placement)
	placements.append({"id":entry.id,"model":selected.id,"position":point,"coordinates":entry.position.duplicate(),"scale":placement.scale,"rotation":placement.quaternion,"biome":BIOMES[int(entry.biome)],"collision_radius_m":entry.collision_radius_m,"harvest":_harvest_info(entry.get("harvest"))})