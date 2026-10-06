extends CanvasLayer
## A conversation with a character: the portrait, what they say and what the player can
## answer. It only shows what the server sent; choosing sends the choice back.

signal choice_made(npc_id: String, seq: int, choice: int)
signal closed
## The character speaking starts or stops: while its voice plays, or its words are on screen for a
## time proportional to their length when there is no voice.
signal speaking_changed(npc_id: String, speaking: bool)

const MUSIC_DB := -10.0
const VOICE_DB := 0.0
const MAX_VOLUME := 2.0

var panel: PanelContainer
var portrait: TextureRect
var name_label: Label
var speech: Label
var choices_box: VBoxContainer
var music_enabled := true
## Spoken lines follow the same sound setting as the music.
var voice_enabled := true
## Playback levels chosen in the settings (1.0 = the default level, up to MAX_VOLUME).
var music_volume := 1.0
var voice_volume := 1.0
var story: Node
## The area music; a dialogue whose track is already playing there does not start it a second time.
var area_music: Node
var _npc_id := ""
var _seq := 0
var _music: Node
var _music_url := ""
var _voice: AudioStreamPlayer
var _voice_url := ""
var _portrait_url := ""
var _loop := true
var _reply: Dictionary = {}
var _speaking := false
var _speak_until_ms := 0

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
	_music = _new_music_channel()
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.volume_db = _db(VOICE_DB, voice_volume)
	add_child(_voice)
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
	_start_voice(reply.node)
	_speak_until_ms = Time.get_ticks_msec() + int(clampf(speech.text.length() * 55.0, 1200.0, 9000.0))
	if choices_box.get_child_count() > 0:
		(choices_box.get_child(0) as Button).grab_focus()

func _choose(index: int) -> void:
	_voice.stop()
	choice_made.emit(_npc_id, _seq, index)

func _text(key: String) -> String:
	return story.text(key) if story != null else key

func _start_media(reply: Dictionary) -> void:
	portrait.texture = null
	_portrait_url = reply.get("portrait", "") if reply.get("portrait") != null else ""
	if not _portrait_url.is_empty() and story != null:
		story.fetch_media(_portrait_url)
	_loop = true
	if reply.get("music") != null and story != null and music_enabled and not (area_music != null and area_music.current_url == reply.music.url and area_music.gain > 0.3):
		_music_url = reply.music.url
		_loop = reply.music.loop
		story.fetch_media(_music_url)

## Plays the spoken line of the node, if the server sent one for the interface language.
func _start_voice(node: Dictionary) -> void:
	_voice.stop()
	_voice.stream = null
	_voice_url = ""
	if node.get("voice") != null and story != null and voice_enabled:
		_voice_url = node.voice
		story.fetch_media(_voice_url)

## A portrait or track arrived; it is used only if the conversation still wants it.
func media_ready(url: String, resource: Resource) -> void:
	if not visible:
		return
	if url == _portrait_url and resource is Texture2D:
		portrait.texture = resource
	elif url == _voice_url and resource is AudioStream and voice_enabled:
		_voice.stream = resource
		_voice.play()
	elif url == _music_url and resource is AudioStream and music_enabled:
		if resource is AudioStreamOggVorbis:
			resource.loop = _loop
		# A track still fading out from an earlier conversation keeps going; this one starts beside it.
		if _music.stream != null:
			_retire_music()
		_music.start(resource, _loop, 1.0, url)

func _new_music_channel() -> Node:
	var channel := preload("res://scripts/music_channel.gd").new()
	channel.name = "Music"
	channel.base_db = MUSIC_DB
	channel.volume = music_volume
	add_child(channel)
	return channel

## The track of the conversation is not cut off: it fades out to the end and then goes away.
func _retire_music() -> void:
	if _music.stream != null:
		_music.free_when_done = true
		_music.fade_out()
		_music = _new_music_channel()

## Whether the dialogue plays a track of its own that the area music has to give way to.
func has_own_music() -> bool:
	return _music != null and _music.stream != null and _music.target > 0.0

func set_music_enabled(value: bool) -> void:
	music_enabled = value
	if not value:
		_music.stop_now()

static func _db(base: float, volume: float) -> float:
	return -80.0 if volume <= 0.001 else base + linear_to_db(clampf(volume, 0.0, MAX_VOLUME))

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, MAX_VOLUME)
	if _music != null:
		_music.volume = music_volume

func set_voice_volume(value: float) -> void:
	voice_volume = clampf(value, 0.0, MAX_VOLUME)
	if _voice != null:
		_voice.volume_db = _db(VOICE_DB, voice_volume)

func set_voice_enabled(value: bool) -> void:
	voice_enabled = value
	if not value:
		_voice.stop()

func _process(_delta: float) -> void:
	_set_speaking(visible and not _npc_id.is_empty() and (_voice.playing or Time.get_ticks_msec() < _speak_until_ms))

func _set_speaking(value: bool) -> void:
	if value != _speaking:
		_speaking = value
		speaking_changed.emit(_npc_id, value)

func close() -> void:
	if not visible and _npc_id.is_empty():
		return
	_speak_until_ms = 0
	_set_speaking(false)
	_retire_music()
	_music_url = ""
	_voice.stop()
	_voice.stream = null
	_voice_url = ""
	_portrait_url = ""
	_npc_id = ""
	hide()
	closed.emit()
