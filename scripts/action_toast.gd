extends CanvasLayer
## Short messages about the player's own actions (harvesting, crafting) and a
## prompt naming what the interaction key would do. It never takes the mouse.

const SHOWN_SECONDS := 3.0

var _toast: Label
var _prompt: Label
var _tween: Tween

func _ready() -> void:
	layer = 3
	_toast = _make_label(-190, 20)
	_prompt = _make_label(-150, 18)
	_toast.hide()
	_prompt.hide()

func _make_label(offset: int, size: int) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.anchor_left = 0.2
	label.anchor_right = 0.8
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_top = offset
	label.offset_bottom = offset + 36
	add_child(label)
	return label

func show_toast(text: String, seconds := SHOWN_SECONDS) -> void:
	if text.is_empty():
		return
	_toast.text = text
	_toast.modulate = Color.WHITE
	_toast.show()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(seconds)
	_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)
	_tween.tween_callback(_toast.hide)

func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = not text.is_empty()
