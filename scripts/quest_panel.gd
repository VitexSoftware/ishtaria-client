extends CanvasLayer
## The quest log: every quest the player has, with the stage they are at.

var panel: PanelContainer
var list: VBoxContainer
var story: Node
var _quests: Array = []

func _ready() -> void:
	layer = 4
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.6)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	panel = PanelContainer.new()
	add_child(panel)
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/kenney/ui-rpg/PNG/panelInset_blue.png")
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_texture_margin(side, 10.0)
		style.set_content_margin(side, 24.0)
	style.modulate_color = Color(0.12, 0.13, 0.14)
	panel.add_theme_stylebox_override("panel", style)
	var frame := NinePatchRect.new()
	frame.texture = load("res://assets/kenney/fantasy-ui-borders/PNG/Default/Border/panel-border-000.png")
	for margin in ["left", "right", "top", "bottom"]:
		frame.set("patch_margin_" + margin, 16)
	frame.modulate = Color(0.95, 0.75, 0.35, 0.9)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.top_level = false
	panel.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	var close := Button.new()
	close.name = "Close"
	close.pressed.connect(hide)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list = VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()
	_update_texts()

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var dimensions := Vector2(minf(560, screen.x - 24), minf(480, screen.y - 24))
	panel.position = (screen - dimensions) / 2
	panel.size = dimensions

func open() -> void:
	show()
	_update_texts()
	_render()

func set_quests(quests: Array) -> void:
	_quests = quests.duplicate(true)
	_render()

func _update_texts() -> void:
	panel.find_child("Title", true, false).text = tr("Quest log")
	panel.find_child("Close", true, false).text = tr("Close")

func _text(key: String) -> String:
	return story.text(key) if story != null else key

func _render() -> void:
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if _quests.is_empty():
		var none := Label.new()
		none.text = tr("No quests yet")
		list.add_child(none)
		return
	for quest: Dictionary in _quests:
		var heading := Label.new()
		heading.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		heading.text = _text(quest.title_key) + (" (" + tr("Finished") + ")" if quest.final else "")
		heading.add_theme_font_size_override("font_size", 17)
		heading.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6) if quest.final else Color(1.0, 0.85, 0.5))
		list.add_child(heading)
		var step := Label.new()
		step.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		step.text = _text(quest.text_key)
		step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(step)
