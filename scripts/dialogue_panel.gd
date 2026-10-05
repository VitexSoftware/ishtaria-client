extends CanvasLayer
## A conversation with a character: the portrait, what they say and what the player can
## answer. It only shows what the server sent; choosing sends the choice back.

signal choice_made(npc_id: String, seq: int, choice: int)
signal closed

const MUSIC_DB := -14.0

var panel: PanelContainer
var portrait: TextureRect
var name_label: Label
var speech: Label
var choices_box: VBoxContainer
var music_enabled := true
var story: Node
var _npc_id := ""
var _seq := 0
var _music: AudioStreamPlayer
var _music_url := ""
var _portrait_url := ""
var _loop := true
var _reply: Dictionary = {}

func _ready() -> void:
	layer = 4
	panel = PanelContainer.new()
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.94)
	style.border_color = Color(0.75, 0.6, 0.3)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_border_width(side, 2)
		style.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(160, 200)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	row.add_child(column)
	name_label = Label.new()
	name_label.name = "Speaker"
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	column.add_child(name_label)
	speech = Label.new()
	speech.name = "Speech"
	speech.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(speech)
	choices_box = VBoxContainer.new()
	choices_box.name = "Choices"
	choices_box.add_theme_constant_override("separation", 4)
	column.add_child(choices_box)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.volume_db = MUSIC_DB
	add_child(_music)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var width := minf(760.0, screen.x - 24.0)
	var height := minf(300.0, screen.y - 24.0)
	panel.size = Vector2(width, height)
	# Above the HUD bar when the screen is tall enough for both.
	var margin := 176.0 if screen.y >= 760.0 else 16.0
	panel.position = Vector2((screen.x - width) / 2.0, screen.y - height - margin)
	portrait.custom_minimum_size = Vector2(minf(160.0, width * 0.25), minf(200.0, height - 24.0))

func is_open() -> bool:
	return visible

## Shows the server's answer. A closed conversation (`open` false) hides the panel.
func show_reply(reply: Dictionary) -> void:
	if not reply.open:
		close()
		return
	var first: bool = not visible or reply.npc_id != _npc_id
	_reply = reply
	_npc_id = reply.npc_id
	_seq = int(reply.seq)
	name_label.text = _text(reply.name_key)
	speech.text = _text(reply.node.text_key)
	for child in choices_box.get_children():
		choices_box.remove_child(child)
		child.queue_free()
	for choice: Dictionary in reply.node.choices:
		var button := Button.new()
		button.text = _text(choice.text_key)
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_choose.bind(int(choice.index)))
		choices_box.add_child(button)
	if reply.node.choices.is_empty():
		var leave := Button.new()
		leave.text = tr("Leave")
		leave.name = "Leave"
		leave.pressed.connect(close)
		choices_box.add_child(leave)
	show()
	if first:
		_start_media(reply)
	if choices_box.get_child_count() > 0:
		(choices_box.get_child(0) as Button).grab_focus()

func _choose(index: int) -> void:
	choice_made.emit(_npc_id, _seq, index)

func _text(key: String) -> String:
	return story.text(key) if story != null else key

func _start_media(reply: Dictionary) -> void:
	portrait.texture = null
	_portrait_url = reply.get("portrait", "") if reply.get("portrait") != null else ""
	if not _portrait_url.is_empty() and story != null:
		story.fetch_media(_portrait_url)
	_loop = true
	if reply.get("music") != null and story != null and music_enabled:
		_music_url = reply.music.url
		_loop = reply.music.loop
		story.fetch_media(_music_url)

## A portrait or track arrived; it is used only if the conversation still wants it.
func media_ready(url: String, resource: Resource) -> void:
	if not visible:
		return
	if url == _portrait_url and resource is Texture2D:
		portrait.texture = resource
	elif url == _music_url and resource is AudioStream and music_enabled:
		if resource is AudioStreamOggVorbis:
			resource.loop = _loop
		_music.stream = resource
		_music.play()

func set_music_enabled(value: bool) -> void:
	music_enabled = value
	if not value:
		_music.stop()

func close() -> void:
	if not visible and _npc_id.is_empty():
		return
	_music.stop()
	_music.stream = null
	_music_url = ""
	_portrait_url = ""
	_npc_id = ""
	hide()
	closed.emit()
