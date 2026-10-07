extends CanvasLayer
## The chat part of the screen: short lines in the bottom left corner that fade after ten
## seconds. For now it carries what friends do (reaching a level); text messages will use it too.

const SHOWN_SECONDS := 10.0
const MAX_LINES := 6
const MAX_CHARACTERS := 500

## The player pressed Enter on a line they wrote.
signal submitted(text: String)

var _column: VBoxContainer
var _line: LineEdit

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
	_line = LineEdit.new()
	_line.name = "Input"
	_line.visible = false
	_line.max_length = MAX_CHARACTERS
	_line.placeholder_text = tr("Say something (/w name text whispers to a friend)")
	_line.anchor_top = 1.0
	_line.anchor_bottom = 1.0
	_line.offset_left = 14.0
	_line.offset_top = -200.0
	_line.offset_bottom = -170.0
	_line.offset_right = 380.0
	_line.text_submitted.connect(_on_submitted)
	add_child(_line)

func is_typing() -> bool:
	return is_instance_valid(_line) and _line.visible

## Shows the line to write in and gives it the keyboard.
func open_input() -> void:
	_line.text = ""
	_line.placeholder_text = tr("Say something (/w name text whispers to a friend)")
	_line.show()
	_line.grab_focus()

func close_input() -> void:
	if is_instance_valid(_line) and _line.visible:
		_line.release_focus()
		_line.hide()

func _on_submitted(text: String) -> void:
	close_input()
	text = text.strip_edges()
	if not text.is_empty():
		submitted.emit(text)

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
	close_input()
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
