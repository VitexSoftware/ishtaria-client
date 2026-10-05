extends CanvasLayer
## Server system messages (`kind: "system"` in GET /world `messages`).
## They are visually distinct from player messages and cannot be dismissed:
## the panel ignores the mouse and has no close control.

const RPG := "res://assets/kenney/ui-rpg/PNG/"
const BORDER := "res://assets/kenney/fantasy-ui-borders/PNG/Default/Border/panel-border-000.png"

var _panel: PanelContainer
var _frame: NinePatchRect
var _label: Label
var _shutdown_text := ""
var _shutdown_left := -1.0
var _announced_shutdown := false
var _gone := false

func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.name = "SystemMessages"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = 12.0
	var style := StyleBoxTexture.new()
	style.texture = load(RPG + "panelInset_blue.png")
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_texture_margin(side, 10.0)
		style.set_content_margin(side, 14.0)
	style.modulate_color = Color(0.55, 0.16, 0.12, 0.96)
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.62))
	_panel.add_child(_label)
	_frame = NinePatchRect.new()
	_frame.texture = load(BORDER)
	for margin in ["left", "right", "top", "bottom"]:
		_frame.set("patch_margin_" + margin, 16)
	_frame.modulate = Color(0.95, 0.75, 0.35, 0.85)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_panel.resized.connect(_sync_frame)
	_panel.hide()
	_frame.hide()
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()

func _fit_viewport() -> void:
	var width := minf(680.0, maxf(28.0, get_viewport().get_visible_rect().size.x - 24.0))
	_panel.custom_minimum_size.x = width
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.reset_size()
	_sync_frame.call_deferred()

func _sync_frame() -> void:
	_frame.position = _panel.position
	_frame.size = _panel.size

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_label):
		_refresh()

func _process(delta: float) -> void:
	if _shutdown_left > 0.0:
		_shutdown_left = maxf(0.0, _shutdown_left - delta)
		_refresh()

## Applies the `messages` array of a successful /world response.
func apply(messages: Variant) -> void:
	_gone = false
	_shutdown_left = -1.0
	_shutdown_text = ""
	_announced_shutdown = false
	if messages is Array:
		for message in messages:
			if message is Dictionary and message.get("kind") == "system" and message.get("code") == "shutdown":
				var left: Variant = message.get("seconds_left")
				if left is int or left is float:
					_shutdown_left = float(left)
					_announced_shutdown = true
				var text: Variant = message.get("text")
				_shutdown_text = text if text is String else ""
	_refresh()

## Called when the server stops answering. After an announced shutdown the
## outage is explained instead of being shown only as a connection error.
func server_unreachable() -> void:
	if _announced_shutdown and _shutdown_left >= 0.0 and _shutdown_left <= 10.0:
		_gone = true
		_shutdown_left = -1.0
		_refresh()

func _refresh() -> void:
	var lines: PackedStringArray = []
	if _gone:
		lines.append(tr("The server was shut down by its administrator."))
	elif _shutdown_left >= 0.0:
		lines.append(tr("The server will shut down in %s") % _format(_shutdown_left))
		if not _shutdown_text.is_empty():
			lines.append(_shutdown_text)
	_label.text = "\n".join(lines)
	_panel.visible = not lines.is_empty()
	_frame.visible = _panel.visible
	_sync_frame.call_deferred()

func _format(seconds: float) -> String:
	var total := int(ceil(seconds))
	return "%d:%02d" % [total / 60, total % 60]
