extends CanvasLayer
## Minimap showing a top-down view of the area around the player.
## Displays the player position, direction, NPCs, places, and objects with icons and names.

const RPG := "res://assets/kenney/ui-rpg/PNG/"

# Minimap size in pixels
const MINIMAP_SIZE := 256
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const ZOOM_STEP := 0.25

# Colors with good contrast
const PLAYER_COLOR := Color(1.0, 0.3, 0.3)
const NORTH_COLOR := Color(1.0, 1.0, 1.0)
const BACKGROUND_COLOR := Color(0.12, 0.12, 0.12)
const NPC_COLOR := Color(1.0, 0.65, 0.0)
const PLACE_COLOR := Color(0.2, 0.8, 1.0)
const OBJECT_COLOR := Color(0.4, 1.0, 0.4)
const QUEST_COLOR := Color(1.0, 0.4, 0.8)
const LABEL_COLOR := Color(1.0, 1.0, 1.0)

# View radius in meters
const VIEW_RADIUS_M := 200.0

# Icon and label sizes
const ICON_SIZE := 14
const LABEL_SIZE := 10

var environment: Node3D
var player_position: Vector3 = Vector3.ZERO
var player_direction: Vector3 = Vector3.FORWARD
var player_heading: Vector3 = Vector3.RIGHT
var _zoom_level: float = 1.0

# Entity data: Array of {id: String, name: String, kind: String, position: Vector3, is_quest: bool}
var _entities: Array[Dictionary] = []

var _minimap_panel: PanelContainer
var _minimap_viewport: SubViewport
var _render_node: Node2D
var _background: Sprite2D
var _player_marker: Sprite2D
var _north_marker: Sprite2D

# Entity markers: Dictionary of entity_id -> {marker: Sprite2D, label: Sprite2D, position: Vector3, kind: String, name: String}
var _entity_markers: Dictionary = {}

# Texture caches to avoid recreating textures every frame
var _icon_texture_cache: Dictionary = {}
var _letter_texture_cache: Dictionary = {}

func _ready() -> void:
	layer = 3
	
	# Create minimap panel
	_minimap_panel = PanelContainer.new()
	_minimap_panel.name = "MinimapPanel"
	_minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_panel.anchor_right = 1.0
	_minimap_panel.anchor_bottom = 1.0
	_minimap_panel.offset_right = -16.0
	_minimap_panel.offset_bottom = -16.0
	_minimap_panel.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	
	# Style the panel
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = load(RPG + "panelInset_blue.png")
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_texture_margin(side, 8.0)
	style.modulate_color = Color(0.45, 0.5, 0.65, 0.9)
	_minimap_panel.add_theme_stylebox_override("panel", style)
	
	add_child(_minimap_panel)
	
	# Create SubViewport for rendering
	_minimap_viewport = SubViewport.new()
	_minimap_viewport.name = "MinimapViewport"
	_minimap_viewport.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	_minimap_panel.add_child(_minimap_viewport)
	
	# Create 2D scene for minimap
	_render_node = Node2D.new()
	_render_node.name = "MinimapScene"
	_minimap_viewport.add_child(_render_node)
	
	# Background
	_background = Sprite2D.new()
	_background.name = "Background"
	_background.texture = _create_solid_color_texture(BACKGROUND_COLOR, MINIMAP_SIZE, MINIMAP_SIZE)
	_background.position = Vector2(MINIMAP_SIZE / 2, MINIMAP_SIZE / 2)
	_background.z_index = -10
	_render_node.add_child(_background)
	
	# Player marker (arrow with better visibility)
	_player_marker = Sprite2D.new()
	_player_marker.name = "PlayerMarker"
	_player_marker.texture = _create_player_arrow()
	_player_marker.position = Vector2(MINIMAP_SIZE / 2, MINIMAP_SIZE / 2)
	_player_marker.z_index = 10
	_render_node.add_child(_player_marker)
	
	# North direction marker (N)
	_north_marker = Sprite2D.new()
	_north_marker.name = "NorthMarker"
	_north_marker.texture = _create_letter_texture("N", NORTH_COLOR)
	_north_marker.position = Vector2(MINIMAP_SIZE / 2, 16)
	_north_marker.z_index = 5
	_render_node.add_child(_north_marker)
	
	# Create texture for display
	var texture_rect: TextureRect = TextureRect.new()
	texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	texture_rect.texture = _minimap_viewport.get_texture()
	_minimap_panel.add_child(texture_rect)
	
	# Add border
	var border: ColorRect = ColorRect.new()
	border.name = "Border"
	border.color = Color(0.2, 0.2, 0.2, 0.8)
	border.custom_minimum_size = Vector2(MINIMAP_SIZE + 4, MINIMAP_SIZE + 4)
	border.position = Vector2(-2, -2)
	border.z_index = -1
	_minimap_panel.add_child(border)
	
	# Initially hidden
	_minimap_panel.hide()


func _process(delta: float) -> void:
	if _minimap_panel.visible:
		_update_minimap()


func set_environment(env: Node3D) -> void:
	environment = env


func set_player_position(pos: Vector3) -> void:
	player_position = pos


func set_player_orientation(direction: Vector3, heading: Vector3) -> void:
	player_direction = direction
	player_heading = heading


func set_entities(entities: Array[Dictionary]) -> void:
	# Only rebuild markers if entities actually changed
	var entities_changed := false
	if _entities.size() != entities.size():
		entities_changed = true
	else:
		for i in range(_entities.size()):
			if not _entities[i] == entities[i]:
				entities_changed = true
				break
	
	if entities_changed:
		_entities = entities.duplicate()
		_update_entity_markers()


func show_minimap() -> void:
	_minimap_panel.show()


func hide_minimap() -> void:
	_minimap_panel.hide()


func toggle_visibility() -> void:
	if _minimap_panel.visible:
		hide_minimap()
	else:
		show_minimap()


func zoom_in() -> void:
	_zoom_level = min(_zoom_level + ZOOM_STEP, MAX_ZOOM)
	_update_zoom()


func zoom_out() -> void:
	_zoom_level = max(_zoom_level - ZOOM_STEP, MIN_ZOOM)
	_update_zoom()


func _update_zoom() -> void:
	if _render_node != null:
		_render_node.scale = Vector2(_zoom_level, _zoom_level)


func _update_entity_markers() -> void:
	# Clear existing entity markers that are no longer present
	var current_ids: Array = []
	for entity: Dictionary in _entities:
		current_ids.append(entity.get("id", ""))
	
	for entity_id: String in _entity_markers:
		if not current_ids.has(entity_id):
			var entry: Dictionary = _entity_markers[entity_id]
			if entry.has("marker") and entry["marker"] != null:
				entry["marker"].queue_free()
			if entry.has("label") and entry["label"] != null:
				entry["label"].queue_free()
			_entity_markers.erase(entity_id)
	
	# Create or update markers for each entity
	for entity: Dictionary in _entities:
		var entity_id: String = entity.get("id", "")
		var name: String = entity.get("name", "")
		var kind: String = entity.get("kind", "object")
		var position: Vector3 = entity.get("position", Vector3.ZERO)
		
		# If marker already exists, just update its data
		if _entity_markers.has(entity_id):
			var entry: Dictionary = _entity_markers[entity_id]
			entry["position"] = position
			# Update icon if kind changed
			if entry.get("kind") != kind:
				entry["kind"] = kind
				entry["name"] = name
				entry["marker"].texture = _get_entity_icon_texture(kind)
				entry["label"].texture = _get_letter_texture(name.substr(0, 1).to_upper())
			continue
		
		# Create new marker
		var marker: Sprite2D = Sprite2D.new()
		marker.name = "EntityIcon_" + entity_id
		marker.texture = _get_entity_icon_texture(kind)
		marker.z_index = 1
		_render_node.add_child(marker)
		
		# Create name label as a Sprite2D with pre-rendered text
		var label: Sprite2D = Sprite2D.new()
		label.name = "EntityLabel_" + entity_id
		var label_char: String = name.substr(0, 1).to_upper() if not name.is_empty() else "?"
		label.texture = _get_letter_texture(label_char)
		label.z_index = 2
		label.visible = _zoom_level >= 0.75
		_render_node.add_child(label)
		
		_entity_markers[entity_id] = {
			"marker": marker,
			"label": label,
			"position": position,
			"kind": kind,
			"name": name
		}


func _update_minimap() -> void:
	# Update player marker rotation based on heading
	if player_direction.length() > 0.1 and _player_marker != null:
		var angle: float = atan2(player_direction.x, -player_direction.z)
		_player_marker.rotation = angle
	
	# Update north marker rotation based on player heading
	if player_heading.length() > 0.1 and _north_marker != null:
		_north_marker.rotation = -player_heading.signed_angle_to(Vector3.RIGHT, Vector3.UP)
	
	# Update entity marker positions
	if player_position.length() > 0:
		for entity_id: String in _entity_markers:
			var entry: Dictionary = _entity_markers[entity_id]
			var marker: Sprite2D = entry["marker"]
			var label: Sprite2D = entry["label"]
			var entity_pos: Vector3 = entry["position"]
			
			# Calculate relative position from player (in meters)
			var relative_pos: Vector3 = entity_pos - player_position
			
			# Only show entities within the view radius
			if relative_pos.length() > VIEW_RADIUS_M:
				marker.visible = false
				label.visible = false
				continue
			
			marker.visible = true
			# Show labels only when zoomed in enough
			label.visible = _zoom_level >= 0.75
			
			# Convert world coordinates to minimap coordinates
			# X axis on minimap: right = east (positive X in world)
			# Y axis on minimap: down = north (positive Z in world)
			var map_x: float = relative_pos.x / VIEW_RADIUS_M * (MINIMAP_SIZE / 2) * _zoom_level
			var map_y: float = -relative_pos.z / VIEW_RADIUS_M * (MINIMAP_SIZE / 2) * _zoom_level
			
			# Center on player
			marker.position = Vector2(MINIMAP_SIZE / 2 + map_x, MINIMAP_SIZE / 2 + map_y)
			
			# Position label below the icon
			label.position = Vector2(MINIMAP_SIZE / 2 + map_x, MINIMAP_SIZE / 2 + map_y + 10)


# Texture getter functions with caching

func _get_entity_icon_texture(kind: String) -> Texture2D:
	var cache_key: String = "icon_" + kind.to_lower()
	if _icon_texture_cache.has(cache_key):
		return _icon_texture_cache[cache_key]
	
	var texture: Texture2D = _create_entity_icon(kind, _get_kind_color(kind))
	_icon_texture_cache[cache_key] = texture
	return texture


func _get_letter_texture(letter: String) -> Texture2D:
	if letter.length() == 0:
		letter = "?"
	letter = letter.to_upper()
	
	var cache_key: String = "letter_" + letter
	if _letter_texture_cache.has(cache_key):
		return _letter_texture_cache[cache_key]
	
	var texture: Texture2D = _create_letter_texture(letter, LABEL_COLOR)
	_letter_texture_cache[cache_key] = texture
	return texture


func _get_kind_color(kind: String) -> Color:
	match kind.to_lower():
		"npc", "character":
			return NPC_COLOR
		"place", "landmark", "building":
			return PLACE_COLOR
		"quest":
			return QUEST_COLOR
		_:
			return OBJECT_COLOR


# Texture creation functions

func _create_player_arrow() -> Texture2D:
	var width: int = 16
	var height: int = 32
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	var center: int = width / 2
	
	# Arrow head - filled triangle at top (pointing up in 2D = north in world)
	for y in range(0, 10):
		var half_width: int = 7 - y * 0.6
		if half_width < 1:
			half_width = 1
		for x in range(center - half_width, center + half_width + 1):
			if x >= 0 and x < width and y >= 0 and y < height:
				image.set_pixel(x, y, PLAYER_COLOR)
	
	# Arrow shaft
	for y in range(10, 24):
		for x in range(center - 2, center + 3):
			if x >= 0 and x < width and y >= 0 and y < height:
				image.set_pixel(x, y, PLAYER_COLOR)
	
	# Arrow base
	for y in range(24, height):
		for x in range(center - 1, center + 2):
			if x >= 0 and x < width and y >= 0 and y < height:
				image.set_pixel(x, y, PLAYER_COLOR)
	
	return ImageTexture.create_from_image(image)


func _create_solid_color_texture(color: Color, width: int, height: int) -> Texture2D:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _create_letter_texture(letter: String, color: Color) -> Texture2D:
	var size: int = LABEL_SIZE
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	if letter.length() == 0:
		letter = "?"
	
	# Use simple but recognizable letter shapes
	# Each letter is drawn with filled pixels in a 10x10 grid
	var first_char: String = letter.to_upper().substr(0, 1)
	
	# Simple letter patterns - each is a series of pixel coordinates
	var pixels: Array[Vector2] = []
	
	match first_char:
		"A":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(8,2),
				Vector2(1,3), Vector2(8,3),
				Vector2(1,4), Vector2(8,4),
				Vector2(1,5), Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), 
				Vector2(6,5), Vector2(7,5), Vector2(8,5),
				Vector2(1,6), Vector2(8,6),
				Vector2(1,7), Vector2(8,7),
				Vector2(1,8), Vector2(8,8)
			]
		"B":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(1,7), Vector2(7,7),
				Vector2(1,8), Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8)
			]
		"C":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), Vector2(1,6), Vector2(1,7),
				Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8), Vector2(7,8)
			]
		"D":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(7,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(1,7), Vector2(7,7),
				Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8)
			]
		"E":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5),
				Vector2(1,6), Vector2(2,6), Vector2(3,6), Vector2(4,6), Vector2(5,6), Vector2(6,6),
				Vector2(1,7), Vector2(1,8), Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8)
			]
		"F":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5),
				Vector2(1,6), Vector2(2,6), Vector2(3,6), Vector2(4,6), Vector2(5,6), Vector2(6,6),
				Vector2(1,7), Vector2(1,8)
			]
		"G":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), Vector2(1,6), Vector2(1,7),
				Vector2(1,8), Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8),
				Vector2(7,5), Vector2(8,5)
			]
		"H":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), 
				Vector2(1,6), Vector2(1,7), Vector2(1,8),
				Vector2(7,1), Vector2(7,2), Vector2(7,3), Vector2(7,4), Vector2(7,5),
				Vector2(7,6), Vector2(7,7), Vector2(7,8),
				Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5)
			]
		"I":
			pixels = [
				Vector2(4,1), Vector2(5,1),
				Vector2(4,2), Vector2(5,2),
				Vector2(4,3), Vector2(5,3),
				Vector2(4,4), Vector2(5,4),
				Vector2(4,5), Vector2(5,5),
				Vector2(4,6), Vector2(5,6),
				Vector2(4,7), Vector2(5,7),
				Vector2(4,8), Vector2(5,8)
			]
		"J":
			pixels = [
				Vector2(5,1), Vector2(5,2), Vector2(5,3), Vector2(5,4), Vector2(5,5), 
				Vector2(5,6), Vector2(5,7),
				Vector2(4,8), Vector2(5,8), Vector2(6,8),
				Vector2(4,9), Vector2(5,9)
			]
		"K":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), 
				Vector2(1,6), Vector2(1,7), Vector2(1,8),
				Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5),
				Vector2(6,6), Vector2(7,7), Vector2(8,8)
			]
		"L":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5), 
				Vector2(1,6), Vector2(1,7), Vector2(1,8),
				Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8),
				Vector2(7,8), Vector2(8,8)
			]
		"M":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1),
				Vector2(6,1), Vector2(7,1), Vector2(8,1),
				Vector2(1,2), Vector2(8,2),
				Vector2(1,3), Vector2(8,3),
				Vector2(1,4), Vector2(2,4), Vector2(3,4), Vector2(4,4),
				Vector2(5,4), Vector2(6,4), Vector2(7,4), Vector2(8,4)
			]
		"N":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1),
				Vector2(6,1), Vector2(7,1), Vector2(8,1),
				Vector2(1,2), Vector2(8,2),
				Vector2(1,3), Vector2(5,3), Vector2(8,3),
				Vector2(1,4), Vector2(6,4), Vector2(8,4),
				Vector2(1,5), Vector2(7,5), Vector2(8,5),
				Vector2(1,6), Vector2(8,6),
				Vector2(1,7), Vector2(8,7),
				Vector2(1,8), Vector2(8,8)
			]
		"O":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(7,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(2,7), Vector2(3,7), Vector2(4,7), Vector2(5,7), Vector2(6,7)
			]
		"P":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5)
			]
		"Q":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(7,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(2,7), Vector2(3,7), Vector2(4,7), Vector2(5,7), Vector2(6,7),
				Vector2(7,8), Vector2(8,8)
			]
		"R":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(1,7), Vector2(8,7),
				Vector2(1,8), Vector2(9,8)
			]
		"S":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1), Vector2(7,1),
				Vector2(1,2), Vector2(1,3), Vector2(1,4),
				Vector2(2,5), Vector2(3,5), Vector2(4,5), Vector2(5,5), Vector2(6,5),
				Vector2(7,6), Vector2(8,7), Vector2(8,8),
				Vector2(7,8), Vector2(6,8), Vector2(5,8), Vector2(4,8), Vector2(3,8)
			]
		"T":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1),
				Vector2(6,1), Vector2(7,1), Vector2(8,1), Vector2(9,1),
				Vector2(5,2), Vector2(5,3), Vector2(5,4), Vector2(5,5),
				Vector2(5,6), Vector2(5,7), Vector2(5,8), Vector2(5,9)
			]
		"U":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5),
				Vector2(1,6), Vector2(1,7),
				Vector2(8,1), Vector2(8,2), Vector2(8,3), Vector2(8,4), Vector2(8,5),
				Vector2(8,6), Vector2(8,7),
				Vector2(2,8), Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8)
			]
		"V":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(7,1), Vector2(8,1),
				Vector2(2,2), Vector2(7,2),
				Vector2(3,3), Vector2(6,3),
				Vector2(4,4), Vector2(5,4),
				Vector2(4,5), Vector2(5,5),
				Vector2(4,6), Vector2(5,6),
				Vector2(4,7), Vector2(5,7),
				Vector2(4,8), Vector2(5,8)
			]
		"W":
			pixels = [
				Vector2(1,1), Vector2(1,2), Vector2(1,3), Vector2(1,4), Vector2(1,5),
				Vector2(1,6), Vector2(1,7), Vector2(1,8),
				Vector2(8,1), Vector2(8,2), Vector2(8,3), Vector2(8,4), Vector2(8,5),
				Vector2(8,6), Vector2(8,7), Vector2(8,8),
				Vector2(1,9), Vector2(2,9), Vector2(3,9), Vector2(4,9), Vector2(5,9),
				Vector2(6,9), Vector2(7,9), Vector2(8,9)
			]
		"X":
			pixels = [
				Vector2(1,1), Vector2(8,1),
				Vector2(2,2), Vector2(7,2),
				Vector2(3,3), Vector2(6,3),
				Vector2(4,4), Vector2(5,4),
				Vector2(3,5), Vector2(6,5),
				Vector2(2,6), Vector2(7,6),
				Vector2(1,7), Vector2(8,7),
				Vector2(1,8), Vector2(8,8)
			]
		"Y":
			pixels = [
				Vector2(1,1), Vector2(8,1),
				Vector2(2,2), Vector2(7,2),
				Vector2(3,3), Vector2(6,3),
				Vector2(4,4), Vector2(5,4),
				Vector2(5,5), Vector2(5,6), Vector2(5,7), Vector2(5,8)
			]
		"Z":
			pixels = [
				Vector2(1,1), Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1),
				Vector2(6,1), Vector2(7,1), Vector2(8,1), Vector2(9,1),
				Vector2(7,2), Vector2(6,3), Vector2(5,4), Vector2(4,5),
				Vector2(3,6), Vector2(2,7), Vector2(1,8), Vector2(2,8), 
				Vector2(3,8), Vector2(4,8), Vector2(5,8), Vector2(6,8), 
				Vector2(7,8), Vector2(8,8)
			]
		"0":
			pixels = [
				Vector2(2,1), Vector2(3,1), Vector2(4,1), Vector2(5,1), Vector2(6,1),
				Vector2(1,2), Vector2(7,2),
				Vector2(1,3), Vector2(7,3),
				Vector2(1,4), Vector2(7,4),
				Vector2(1,5), Vector2(7,5),
				Vector2(1,6), Vector2(7,6),
				Vector2(2,7), Vector2(3,7), Vector2(4,7), Vector2(5,7), Vector2(6,7)
			]
		"1":
			pixels = [
				Vector2(5,1), Vector2(4,2), Vector2(5,2), Vector2(6,2),
				Vector2(3,3), Vector2(4,3), Vector2(5,3), Vector2(6,3), Vector2(7,3),
				Vector2(4,4), Vector2(5,4), Vector2(6,4),
				Vector2(5,5), Vector2(5,6), Vector2(5,7), Vector2(5,8)
			]
		_:
			# Default for unknown characters - simple cross
			pixels = [
				Vector2(4,3), Vector2(5,3), Vector2(6,3),
				Vector2(4,4), Vector2(5,4), Vector2(6,4),
				Vector2(4,5), Vector2(5,5), Vector2(6,5),
				Vector2(5,2), Vector2(5,6)
			]
	
	# Draw the pixels
	for pixel: Vector2 in pixels:
		var x: int = int(pixel.x) - 1  # Convert to 0-indexed
		var y: int = int(pixel.y) - 1  # Convert to 0-indexed
		if x >= 0 and x < size and y >= 0 and y < size:
			image.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(image)


func _create_entity_icon(kind: String, color: Color) -> Texture2D:
	var size: int = ICON_SIZE
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	# Add dark outline for better visibility
	var outline_color: Color = Color(0.15, 0.15, 0.15, 0.8)
	
	match kind.to_lower():
		"npc", "character":
			# Diamond shape for NPCs with outline
			for y in range(size):
				for x in range(size):
					var dist: float = sqrt(pow(x - size/2, 2) + pow(y - size/2, 2))
					if dist <= size/2 - 0.5:
						image.set_pixel(x, y, color)
					elif dist <= size/2 + 0.5:
						image.set_pixel(x, y, outline_color)
			
		"place", "building", "landmark":
			# Square for places with outline
			for y in range(1, size - 1):
				for x in range(1, size - 1):
					image.set_pixel(x, y, color)
			# Outline
			for x in range(size):
				image.set_pixel(x, 0, outline_color)
				image.set_pixel(x, size - 1, outline_color)
			for y in range(1, size - 1):
				image.set_pixel(0, y, outline_color)
				image.set_pixel(size - 1, y, outline_color)
			
		"quest":
			# Star for quest markers with outline
			for y in range(size):
				for x in range(size):
					var dx: float = x - size/2
					var dy: float = y - size/2
					if abs(dx) + abs(dy) <= size/2 - 0.5:
						image.set_pixel(x, y, color)
					elif abs(dx) + abs(dy) <= size/2 + 0.5:
						image.set_pixel(x, y, outline_color)
			
		_:  # Default circle for objects with outline
			for y in range(size):
				for x in range(size):
					var dist: float = sqrt(pow(x - size/2, 2) + pow(y - size/2, 2))
					if dist <= size/2 - 1:
						image.set_pixel(x, y, color)
					elif dist <= size/2 - 0.5:
						image.set_pixel(x, y, outline_color)
	
	return ImageTexture.create_from_image(image)
