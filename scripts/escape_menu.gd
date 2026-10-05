extends CanvasLayer
## The menu of the ESC key: the name of the game, settings, quitting and the hall of fame
## of the server (its ten most successful characters).

signal settings_requested
signal quit_requested
signal friends_requested

const RPG := "res://assets/kenney/ui-rpg/PNG/"
const BORDER := "res://assets/kenney/fantasy-ui-borders/PNG/Default/Border/panel-border-000.png"
const GOLD := Color(1.0, 0.83, 0.35)
const MAX_ENTRIES := 10
const HEADSTONE := "res://assets/icons/ui/headstone.png"

var server_url := ""
var title_label: Label
var settings_button: Button
var quit_button: Button
var friends_button: Button
var hall_title: Label
var hall_status: Label
var hall_grid: GridContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _request: HTTPRequest
var _entries: Array = []
var _status_key := ""

func _ready() -> void:
	layer = 30
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.04, 0.88)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	center.add_child(_content)
	_build_title()
	_build_buttons()
	_build_hall()
	get_viewport().size_changed.connect(_fit)
	_fit()
	_update_texts()
	hide()

## A framed panel with a dark fill and the gold border of the interface kit. The border
## covers the whole panel; the content sits inside it with its own margin.
func _framed(parent: Node, fill: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxTexture.new()
	style.texture = load(RPG + "panelInset_blue.png")
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_texture_margin(side, 10.0)
		style.set_content_margin(side, 0.0)
	style.modulate_color = fill
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var frame := NinePatchRect.new()
	frame.texture = load(BORDER)
	for margin in ["left", "right", "top", "bottom"]:
		frame.set("patch_margin_" + margin, 16)
	frame.modulate = Color(0.95, 0.75, 0.35, 0.9)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	panel.add_child(margin)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	margin.add_child(inner)
	return inner

func _build_title() -> void:
	var inner := _framed(_content, Color(0.16, 0.1, 0.05, 0.96))
	var top := _ornament(inner)
	title_label = Label.new()
	title_label.name = "Title"
	title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_label.text = "Ishtaria"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", GOLD)
	title_label.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0))
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	title_label.add_theme_constant_override("outline_size", 14)
	title_label.add_theme_constant_override("shadow_offset_x", 5)
	title_label.add_theme_constant_override("shadow_offset_y", 6)
	inner.add_child(title_label)
	_ornament(inner)
	top.name = "OrnamentTop"

## A line of gold diamonds and bars that ornaments the title.
func _ornament(parent: Node) -> Label:
	var line := Label.new()
	line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	line.text = "◆ ━━━━━━━ ❖ ━━━━━━━ ◆"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_color_override("font_color", Color(0.85, 0.65, 0.28))
	line.add_theme_font_size_override("font_size", 18)
	parent.add_child(line)
	return line

func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_content.add_child(row)
	settings_button = _button(row, "SettingsButton")
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	friends_button = _button(row, "FriendsButton")
	friends_button.pressed.connect(func() -> void: friends_requested.emit())
	quit_button = _button(row, "QuitButton")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())

func _button(row: Node, name: String) -> Button:
	var button := Button.new()
	button.name = name
	button.custom_minimum_size = Vector2(220, 52)
	button.add_theme_font_size_override("font_size", 20)
	row.add_child(button)
	return button

func _build_hall() -> void:
	var inner := _framed(_content, Color(0.08, 0.1, 0.16, 0.96))
	hall_title = Label.new()
	hall_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hall_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hall_title.add_theme_font_size_override("font_size", 28)
	hall_title.add_theme_color_override("font_color", GOLD)
	inner.add_child(hall_title)
	hall_status = Label.new()
	hall_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	hall_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hall_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(hall_status)
	hall_grid = GridContainer.new()
	hall_grid.name = "Hall"
	hall_grid.columns = 6
	hall_grid.add_theme_constant_override("h_separation", 22)
	hall_grid.add_theme_constant_override("v_separation", 6)
	inner.add_child(hall_grid)

func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	_content.custom_minimum_size.x = clampf(screen.x - 32.0, 280.0, 760.0)
	var size := int(clampf(screen.x / 9.0, 44.0, 104.0))
	if is_instance_valid(title_label):
		title_label.add_theme_font_size_override("font_size", size)

func is_open() -> bool:
	return visible

func open(url: String) -> void:
	server_url = url
	show()
	_update_texts()
	_fetch()
	settings_button.grab_focus()

func close() -> void:
	_cancel()
	hide()

func _cancel() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null

func _fetch() -> void:
	_cancel()
	_entries = []
	if server_url.is_empty():
		_set_status("Connect to a server first")
		_render()
		return
	_set_status("Loading")
	_render()
	_request = HTTPRequest.new()
	_request.timeout = 4.0
	_request.max_redirects = 0
	_request.body_size_limit = 65536
	add_child(_request)
	var request := _request
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if request != _request:
			return
		_request = null
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_set_status("Hall of fame unavailable")
			return
		show_hall(JSON.parse_string(body.get_string_from_utf8()))
	)
	if request.request(server_url + "/hall-of-fame") != OK:
		_request = null
		request.queue_free()
		_set_status("Hall of fame unavailable")

## Shows the entries sent by the server; malformed answers are not shown.
func show_hall(data: Variant) -> bool:
	var valid := valid_hall(data)
	_entries = data if valid else []
	_set_status("" if valid and not _entries.is_empty() else ("No characters yet" if valid else "Hall of fame unavailable"))
	_render()
	return valid

static func valid_hall(data: Variant) -> bool:
	if not data is Array or data.size() > MAX_ENTRIES:
		return false
	var pattern := RegEx.new()
	pattern.compile("^(0|[1-9][0-9]{0,18})$")
	for entry: Variant in data:
		if not entry is Dictionary or not entry.get("name") is String or entry.name.is_empty() or entry.name.length() > 64 or not entry.get("alive") is bool:
			return false
		if not (entry.get("level") is float or entry.get("level") is int) or entry.level < 1 or entry.level > 100000 or entry.level != floor(entry.level):
			return false
		for key in ["wealth", "lived_days", "score"]:
			if not entry.get(key) is String or pattern.search(entry[key]) == null:
				return false
	return true

## Groups the digits of a decimal string in threes: "1234567" becomes "1 234 567".
static func group_digits(number: String) -> String:
	var out := ""
	for index in number.length():
		if index > 0 and (number.length() - index) % 3 == 0:
			out += " "
		out += number[index]
	return out

func _set_status(key: String) -> void:
	_status_key = key
	if is_instance_valid(hall_status):
		hall_status.text = tr(key) if not key.is_empty() else ""
		hall_status.visible = not key.is_empty()

func _cell(text: String, color := Color(0.9, 0.9, 0.92), align := HORIZONTAL_ALIGNMENT_LEFT, expand := true) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_FILL
	hall_grid.add_child(label)
	return label

## The name of a character; a small headstone marks one who has died.
func _name_cell(name: String, color: Color, dead: bool) -> void:
	var row := HBoxContainer.new()
	row.name = "Name_" + name
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hall_grid.add_child(row)
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = name
	label.add_theme_color_override("font_color", color)
	row.add_child(label)
	if dead:
		var icon := TextureRect.new()
		icon.name = "Headstone"
		icon.texture = load(HEADSTONE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(22, 22)
		icon.tooltip_text = tr("Deceased")
		row.add_child(icon)

func _render() -> void:
	if not is_instance_valid(hall_grid):
		return
	for child in hall_grid.get_children():
		hall_grid.remove_child(child)
		child.queue_free()
	if _entries.is_empty():
		return
	var head := Color(0.85, 0.65, 0.28)
	_cell("#", head, HORIZONTAL_ALIGNMENT_LEFT, false)
	_cell(tr("Name"), head)
	_cell(tr("Level"), head, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell(tr("Score"), head, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell(tr("Life"), head, HORIZONTAL_ALIGNMENT_RIGHT)
	_cell(tr("Wealth"), head, HORIZONTAL_ALIGNMENT_RIGHT)
	var rank := 0
	for entry: Dictionary in _entries:
		rank += 1
		var color := Color(0.62, 0.95, 0.62) if entry.alive else Color(0.78, 0.78, 0.8)
		_cell(str(rank), color, HORIZONTAL_ALIGNMENT_LEFT, false)
		_name_cell(entry.name, color, not entry.alive)
		_cell(str(int(entry.level)), color, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(group_digits(entry.score), Color(1.0, 0.92, 0.62), HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(tr("%s d") % group_digits(entry.lived_days), color, HORIZONTAL_ALIGNMENT_RIGHT)
		_cell(group_digits(entry.wealth), GOLD if entry.wealth != "0" else Color(0.55, 0.55, 0.58), HORIZONTAL_ALIGNMENT_RIGHT)

func _update_texts() -> void:
	if not is_instance_valid(settings_button):
		return
	settings_button.text = tr("Settings")
	friends_button.text = tr("Friends")
	quit_button.text = tr("Quit game")
	hall_title.text = tr("Hall of fame")
	_set_status(_status_key)
	_render()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_texts()
