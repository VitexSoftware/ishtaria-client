extends CanvasLayer
## Minimap showing a top-down view of the area around the player.
## Displays the player position, direction, NPCs, places, and objects with icons and names.

const RPG := "res://assets/kenney/ui-rpg/PNG/"

# Minimap size in pixels
const MINIMAP_SIZE := 256
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const ZOOM_STEP := 0.25

const PLAYER_COLOR := Color(1.0, 0.0, 0.0)
const NORTH_COLOR := Color(1.0, 1.0, 1.0)
const BACKGROUND_COLOR := Color(0.15, 0.15, 0.15)
const NPC_COLOR := Color(1.0, 0.5, 0.0)
const PLACE_COLOR := Color(0.0, 0.8, 1.0)
const OBJECT_COLOR := Color(0.5, 1.0, 0.5)
const QUEST_COLOR := Color(1.0, 0.0, 1.0)

# View radius in meters
const VIEW_RADIUS_M := 200.0

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

# Cache for text textures to avoid recreating them
var _text_texture_cache: Dictionary = {}

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
	
	# Background - use Sprite2D instead of ColorRect (Control nodes cannot be children of Node2D)
	_background = Sprite2D.new()
	_background.name = "Background"
	_background.texture = _create_solid_color_texture(BACKGROUND_COLOR, MINIMAP_SIZE, MINIMAP_SIZE)
	_background.position = Vector2(MINIMAP_SIZE / 2, MINIMAP_SIZE / 2)
	_background.z_index = -10
	_render_node.add_child(_background)
	
	# Player marker (arrow)
	_player_marker = Sprite2D.new()
	_player_marker.name = "PlayerMarker"
	_player_marker.texture = _create_arrow_texture(Color.WHITE, 12, 24)
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
	_entities = entities
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
	# Clear existing entity markers
	for entry in _entity_markers.values():
		if entry.has("marker") and entry["marker"] != null:
			entry["marker"].queue_free()
		if entry.has("label") and entry["label"] != null:
			entry["label"].queue_free()
	_entity_markers.clear()
	
	# Create new markers for each entity
	for entity: Dictionary in _entities:
		var entity_id: String = entity.get("id", "")
		var name: String = entity.get("name", "")
		var kind: String = entity.get("kind", "object")
		var position: Vector3 = entity.get("position", Vector3.ZERO)
		
		# Choose color based on kind
		var color: Color = OBJECT_COLOR
		match kind.to_lower():
			"npc", "character":
				color = NPC_COLOR
			"place", "landmark", "building":
				color = PLACE_COLOR
			"quest":
				color = QUEST_COLOR
			_:
				color = OBJECT_COLOR
		
		# Create icon marker
		var marker: Sprite2D = Sprite2D.new()
		marker.name = "EntityIcon_" + entity_id
		marker.texture = _create_entity_icon(kind, color)
		marker.z_index = 1
		_render_node.add_child(marker)
		
		# Create name label as a Sprite2D with pre-rendered text
		# Use first character of name for small minimap readability
		var label: Sprite2D = Sprite2D.new()
		label.name = "EntityLabel_" + entity_id
		var label_char: String = name.substr(0, 1).to_upper() if not name.is_empty() else "?"
		label.texture = _create_letter_texture(label_char, Color.WHITE)
		label.z_index = 2
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
		# Calculate rotation: player faces in direction of player_direction
		# In 2D, forward is -Y, right is +X
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
			label.visible = true
			
			# Convert world coordinates to minimap coordinates
			# X axis on minimap: right = east (positive X in world)
			# Y axis on minimap: down = north (positive Z in world)
			var map_x: float = relative_pos.x / VIEW_RADIUS_M * (MINIMAP_SIZE / 2) * _zoom_level
			var map_y: float = -relative_pos.z / VIEW_RADIUS_M * (MINIMAP_SIZE / 2) * _zoom_level
			
			# Center on player
			marker.position = Vector2(MINIMAP_SIZE / 2 + map_x, MINIMAP_SIZE / 2 + map_y)
			
			# Position label below the icon
			label.position = Vector2(MINIMAP_SIZE / 2 + map_x, MINIMAP_SIZE / 2 + map_y + 8)

func _create_arrow_texture(color: Color, width: int, height: int) -> Texture2D:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	# Arrow shaft
	var center: int = width / 2
	for y in range(height / 3, height * 2 / 3):
		for x in range(center - 1, center + 2):
			if x >= 0 and x < width and y >= 0 and y < height:
				image.set_pixel(x, y, color)
	
	# Arrow head - triangle at top
	for y in range(0, height / 3):
		var head_width_at_y: float = 3 - y * 2.0 / (height / 3.0)
		if head_width_at_y < 1:
			head_width_at_y = 1
		for x in range(center - int(floor(head_width_at_y / 2.0)), center + int(ceil(head_width_at_y / 2.0)) + 1):
			if x >= 0 and x < width and y >= 0 and y < height:
				image.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(image)

func _create_solid_color_texture(color: Color, width: int, height: int) -> Texture2D:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _create_letter_texture(letter: String, color: Color) -> Texture2D:
	var size: int = 12
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	# Simple single-pixel representation for letters on minimap
	# For a minimap, we just need a small indicator, not full text
	if letter.length() == 0:
		letter = "?"
	
	# Just render the first letter as a simple dot or small marker
	# For better visuals, use different patterns for different letter groups
	var first_char: String = letter.to_upper().substr(0, 1)
	
	# Simple approach: render a small plus sign or cross for the first character
	# This is much simpler and more maintainable
	var center: int = size / 2
	
	# Cross pattern for the label
	for i in range(-1, 2):
		image.set_pixel(center + i, center, color)
		image.set_pixel(center, center + i, color)
	
	# Add a small indicator based on the letter to help distinguish
	var hash: int = first_char.to_upper().hash()
	var offset: int = (hash % 3) - 1  # -1, 0, or 1
	if offset != 0:
		image.set_pixel(center + offset, center - 1, color)
		image.set_pixel(center - offset, center + 1, color)
	
	return ImageTexture.create_from_image(image)

func _create_entity_icon(kind: String, color: Color) -> Texture2D:
	var size: int = 10
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	
	match kind.to_lower():
		"npc", "character":
			# Diamond shape for NPCs
			for y in range(size):
				for x in range(size):
					var dist: float = sqrt(pow(x - size/2, 2) + pow(y - size/2, 2))
					if dist <= size/2:
						image.set_pixel(x, y, color)
			
		"place", "building", "landmark":
			# Square for places
			for y in range(2, 8):
				for x in range(2, 8):
					image.set_pixel(x, y, color)
			
		"quest":
			# Star for quest markers
			for y in range(size):
				for x in range(size):
					var dx: float = x - size/2
					var dy: float = y - size/2
					if abs(dx) + abs(dy) <= size/2:
						image.set_pixel(x, y, color)
			
		_:  # Default circle for objects
			for y in range(size):
				for x in range(size):
					var dist: float = sqrt(pow(x - size/2, 2) + pow(y - size/2, 2))
					if dist <= size/2 - 1:
						image.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(image)
