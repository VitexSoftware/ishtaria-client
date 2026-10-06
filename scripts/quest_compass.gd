extends CanvasLayer
## A strip at the top of the screen that shows in which direction the places lie where the
## player's quests expect them (the server only names them once the player holds the aetherglass).
## It never takes the mouse.

const RPG := "res://assets/kenney/ui-rpg/PNG/"
const ARROW := "res://assets/kenney/game-icons/arrowLeft.png"
const STRIP_WIDTH := 560.0
const STRIP_HEIGHT := 72.0
const AREA_HEIGHT := 46.0
## Half of the strip stands for this many radians to each side of the way the player faces.
const VISIBLE_HALF_ANGLE := PI / 2.0
const MAX_MARKERS := 16
const NEXT_COLOR := Color(1.0, 0.85, 0.5)
const ACTIVE_COLOR := Color(0.6, 0.9, 1.0)

var story: Node
var _markers: Array = []
var _strip: PanelContainer
var _area: Control
var _items: Array[Control] = []

func _ready() -> void:
	layer = 2
	_strip = PanelContainer.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxTexture.new()
	style.texture = load(RPG + "panelInset_blue.png")
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_texture_margin(side, 10.0)
	style.modulate_color = Color(0.45, 0.5, 0.65)
	_strip.add_theme_stylebox_override("panel", style)
	_strip.custom_minimum_size = Vector2(STRIP_WIDTH, STRIP_HEIGHT)
	_strip.anchor_left = 0.5
	_strip.anchor_right = 0.5
	_strip.offset_top = 8.0
	_strip.hide()
	add_child(_strip)
	_area = Control.new()
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.clip_contents = true
	# The label hangs below the arrow: the area must be tall enough for both.
	_area.custom_minimum_size = Vector2(0, AREA_HEIGHT)
	_strip.add_child(_area)
	get_viewport().size_changed.connect(_fit)
	_fit()

## The strip is as wide as it can be on a small window.
func _fit() -> void:
	var width := minf(STRIP_WIDTH, get_viewport().get_visible_rect().size.x - 16.0)
	_strip.custom_minimum_size.x = maxf(width, 120.0)
	_strip.offset_left = -_strip.custom_minimum_size.x / 2.0
	_strip.offset_right = _strip.custom_minimum_size.x / 2.0

static func valid_markers(data: Variant) -> bool:
	if not data is Array or data.size() > 64:
		return false
	for entry: Variant in data:
		if not entry is Dictionary:
			return false
		for key in ["id", "quest", "name_key", "kind"]:
			if not entry.get(key) is String:
				return false
		if not entry.get("next") is bool or not entry.get("position") is Array or entry.position.size() != 3:
			return false
		for axis: Variant in entry.position:
			if not (axis is float or axis is int) or not is_finite(float(axis)):
				return false
	return true

func set_markers(markers: Array) -> void:
	_markers = markers.slice(0, MAX_MARKERS)
	for item in _items:
		item.queue_free()
	_items.clear()
	for marker: Dictionary in _markers:
		var item := Control.new()
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var color: Color = NEXT_COLOR if marker.next else ACTIVE_COLOR
		var arrow := TextureRect.new()
		arrow.name = "Arrow"
		arrow.texture = load(ARROW)
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arrow.size = Vector2(18, 18)
		arrow.pivot_offset = Vector2(9, 9)
		arrow.modulate = color
		item.add_child(arrow)
		var label := Label.new()
		label.name = "Text"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", color)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 5)
		item.add_child(label)
		_area.add_child(item)
		_items.append(item)
	_strip.visible = not _items.is_empty()

## Bearing of a target, positive to the right of `heading`, on the tangent plane at `direction`.
static func bearing(player: Vector3, target: Vector3, direction: Vector3, heading: Vector3) -> float:
	var offset := target - player
	offset -= direction * offset.dot(direction)
	return atan2(offset.dot(heading.cross(direction)), offset.dot(heading))

## Moves the marks; `player` and the markers are in metres from the planet's centre.
func update_view(player: Vector3, direction: Vector3, heading: Vector3) -> void:
	if not _strip.visible:
		return
	var width := _area.size.x
	var half := width / 2.0
	for index in _items.size():
		var marker: Dictionary = _markers[index]
		var target := Vector3(marker.position[0], marker.position[1], marker.position[2])
		var angle := bearing(player, target, direction, heading)
		var clamped := clampf(angle, -VISIBLE_HALF_ANGLE, VISIBLE_HALF_ANGLE)
		var x := half + clamped / VISIBLE_HALF_ANGLE * (half - 14.0)
		var item := _items[index]
		var arrow: TextureRect = item.get_node("Arrow")
		var label: Label = item.get_node("Text")
		arrow.position = Vector2(x - 9.0, 0.0)
		# The arrow of the pack points left: down while the place is ahead, sideways at the edges.
		if absf(angle) <= VISIBLE_HALF_ANGLE:
			arrow.rotation = -PI / 2.0
		else:
			arrow.rotation = 0.0 if angle < 0.0 else PI
		label.size = Vector2(150, 26)
		label.position = Vector2(clampf(x - 75.0, 0.0, maxf(0.0, width - 150.0)), 18.0)
		label.text = "%s · %d m" % [story.text(marker.name_key) if story != null else marker.name_key, roundi((target - player).length())]
