extends CanvasLayer
## The chat part of the screen: short lines in the bottom left corner that fade after ten
## seconds. For now it carries what friends do (reaching a level); text messages will use it too.

const SHOWN_SECONDS := 10.0
const MAX_LINES := 6

var _column: VBoxContainer

func _ready() -> void:
	layer = 3
	_column = VBoxContainer.new()
	_column.name = "Lines"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", 3)
	add_child(_column)
	_column.anchor_left = 0.0
	_column.anchor_top = 1.0
	_column.anchor_right = 0.0
	_column.anchor_bottom = 1.0
	_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_column.offset_left = 14.0
	_column.offset_bottom = -210.0
	_column.custom_minimum_size.x = 360.0

func line_count() -> int:
	return _column.get_child_count() if is_instance_valid(_column) else 0

func lines() -> Array[String]:
	var texts: Array[String] = []
	for child in _column.get_children():
		if child is Label:
			texts.append(child.text)
	return texts

## Adds a line that stays for `seconds` and then fades.
func add_line(text: String, color := Color(0.95, 0.9, 0.7), seconds := SHOWN_SECONDS) -> void:
	if text.is_empty():
		return
	while _column.get_child_count() >= MAX_LINES:
		var oldest := _column.get_child(0)
		_column.remove_child(oldest)
		oldest.queue_free()
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 340.0
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	_column.add_child(label)
	var tween := create_tween()
	tween.tween_interval(maxf(seconds - 0.8, 0.0))
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func() -> void:
		if is_instance_valid(label):
			label.queue_free()
	)

func clear() -> void:
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
