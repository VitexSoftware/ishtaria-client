extends CanvasLayer
## Cover images of the story datadisks a server announces in GET /world `datadisks`.
## Shown once when the client connects to a server; a click, Escape or a few seconds
## move on to the next cover. Covers are public media, so no sign-in is needed.
## Disk names and the artwork belong to the disk, so they are not translated.

signal finished

const MAX_IMAGE_BYTES := 2097152
const MAX_DISKS := 8
const SHOW_SECONDS := 7.0

var server_url := ""
var _generation := 0
var _queue: Array = []
var _shown := false
var _backdrop: ColorRect
var _picture: TextureRect
var _caption: Label
var _hint: Label
var _timer: Timer

func _ready() -> void:
	layer = 15
	visible = false
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.02, 0.02, 0.03, 0.94)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(_on_gui_input)
	_picture = TextureRect.new()
	_picture.name = "Cover"
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_backdrop.add_child(_picture)
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture.offset_bottom = -64.0
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 22)
	_backdrop.add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -62.0
	_caption.offset_bottom = -34.0
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.modulate = Color(1, 1, 1, 0.6)
	_backdrop.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -30.0
	_hint.offset_bottom = -8.0
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_next)
	add_child(_timer)
	_update_hint()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_hint()

func _update_hint() -> void:
	if is_instance_valid(_hint):
		_hint.text = tr("Click to continue")

## Whether `url` is a cover path the server may announce.
static func valid_cover_url(url: Variant) -> bool:
	return url is String and url.begins_with("/story/media/") and url.length() <= 220 \
		and not (url.contains("..") or url.contains("//") or url.contains("?") or url.contains("#") or url.contains("%") or url.contains("\\")) \
		and (url.ends_with(".png") or url.ends_with(".jpg"))

## The announced disks that have a well-formed id, name and cover, in order.
static func covered_disks(disks: Variant) -> Array:
	var result: Array = []
	if not disks is Array:
		return result
	for disk in disks:
		if result.size() >= MAX_DISKS:
			break
		if disk is Dictionary and disk.get("id") is String and disk.get("name") is String and valid_cover_url(disk.get("cover")):
			result.append({"id": disk.id, "name": String(disk.name).left(80), "version": String(disk.get("version", "")).left(32), "cover": disk.cover})
	return result

## Shows the covers of a freshly connected server. Does nothing when no disk has one.
func present(url: String, disks: Variant) -> void:
	dismiss()
	server_url = url
	_queue = covered_disks(disks)
	_next()

## Hides the cover and forgets the queue (used when the connection is dropped).
func dismiss() -> void:
	_generation += 1
	_queue = []
	_shown = false
	_timer.stop()
	for child in get_children():
		if child is HTTPRequest:
			child.queue_free()
	visible = false

func is_showing() -> bool:
	return visible

func _next() -> void:
	_timer.stop()
	visible = false
	if _queue.is_empty():
		if _shown:
			_shown = false
			finished.emit()
		return
	var disk: Dictionary = _queue.pop_front()
	_fetch(disk)

func _fetch(disk: Dictionary) -> void:
	var generation := _generation
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.max_redirects = 0
	request.body_size_limit = MAX_IMAGE_BYTES
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if generation != _generation:
			return
		var texture := _decode(disk.cover, body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
		if texture == null:
			_next()
			return
		_show(disk, texture)
	)
	if request.request(server_url + disk.cover) != OK:
		request.queue_free()
		_next()

static func _decode(url: String, body: PackedByteArray) -> Texture2D:
	var image := Image.new()
	var error := image.load_png_from_buffer(body) if url.ends_with(".png") else image.load_jpg_from_buffer(body)
	if error != OK or image.get_width() < 1 or image.get_height() < 1 or image.get_width() > 4096 or image.get_height() > 4096:
		return null
	return ImageTexture.create_from_image(image)

func _show(disk: Dictionary, texture: Texture2D) -> void:
	_picture.texture = texture
	_caption.text = disk.name if disk.version.is_empty() else "%s %s" % [disk.name, disk.version]
	_shown = true
	visible = true
	_timer.start(SHOW_SECONDS)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_next()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_next()
