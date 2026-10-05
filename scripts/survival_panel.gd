extends CanvasLayer

signal eat_requested(item_id: String)
signal new_character_requested
signal loot_requested(id: String, item_id: String)

const FOOD := "res://assets/kenney/food-kit/"
const GRAVES := "res://assets/kenney/graveyard-kit/"
const MODELS := {"headstone": ["gravestone-round"], "monument": ["pillar-obelisk"], "mausoleum": ["crypt-large", "crypt-large-roof", "crypt-large-door"]}
var panel: PanelContainer
var content: VBoxContainer
var summary: Label
var inventory_list: VBoxContainer
var grave_list: VBoxContainer
var feedback: Label
var preview: SubViewport
var preview_container: SubViewportContainer
var _model: Node3D
var _profile: Dictionary = {}
var _obituary: Dictionary = {}
var _grave: Dictionary = {}
var _busy := false
var _feedback_key := ""
var _buttons: Array[Button] = []

func _ready() -> void:
	layer = 4
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.7)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	panel = PanelContainer.new()
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.14)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	summary = Label.new()
	summary.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(summary)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide)
	header.add_child(close)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	inventory_list = _list()
	grave_list = _list()
	feedback = Label.new()
	feedback.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(feedback)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func _list() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var dimensions := Vector2(minf(760, screen.x - 24), minf(680, screen.y - 24))
	panel.position = (screen - dimensions) / 2
	panel.size = dimensions

func open() -> void:
	_grave = {}
	_obituary = {}
	show()
	_render()

func set_profile(profile: Dictionary) -> void:
	_profile = profile.duplicate(true)
	if profile.is_empty():
		_obituary = {}
		_grave = {}
		hide()
	_render()

func set_busy(value: bool) -> void:
	_busy = value
	for button in _buttons:
		if is_instance_valid(button):
			button.disabled = value or not _alive()

func set_feedback(message: String) -> void:
	_feedback_key = message
	feedback.text = tr(message)

func show_obituary(data: Dictionary) -> void:
	_obituary = data.duplicate(true)
	_grave = {}
	set_feedback("")
	show()
	_render()

func set_grave(data: Dictionary) -> void:
	_obituary = {}
	_grave = data.duplicate(true)
	show()
	_render()

func _alive() -> bool:
	return _profile.get("life", {}).get("alive", false) == true

func _clear(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

func _label(list: Node, text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(label)
	return label

func _item(list: VBoxContainer, item: Dictionary, grave_id := "") -> void:
	var row := HBoxContainer.new()
	list.add_child(row)
	var id: String = item.get("item_id", "")
	if id in ["apple", "bread", "cheese", "carrot"]:
		var icon := TextureRect.new()
		icon.texture = load(FOOD + id + ".png")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(48, 48)
		row.add_child(icon)
	var name_text := tr(item.get("name", id)) + " x " + str(item.get("quantity", "0"))
	var calories: int = int(item.get("calories", 0))
	if calories > 0:
		name_text += "\n" + tr("%s kcal") % calories
	_label(row, name_text)
	if not grave_id.is_empty() or calories > 0:
		var button := Button.new()
		button.name = "Take" if not grave_id.is_empty() else "Eat"
		button.text = tr("Take" if not grave_id.is_empty() else "Eat")
		button.custom_minimum_size = Vector2(72, 44)
		button.disabled = _busy or not _alive()
		button.pressed.connect(func() -> void:
			set_feedback("")
			if grave_id.is_empty():
				eat_requested.emit(id)
			else:
				loot_requested.emit(grave_id, id)
		)
		row.add_child(button)
		_buttons.append(button)

func _render() -> void:
	if not is_instance_valid(inventory_list):
		return
	_buttons.clear()
	_clear(inventory_list)
	_clear(grave_list)
	preview = null
	var memorial := not _grave.is_empty() or not _obituary.is_empty()
	inventory_list.get_parent().visible = not memorial
	grave_list.get_parent().visible = memorial
	var inventory: Dictionary = _profile.get("inventory", {})
	summary.text = tr("Inventory %s / %s") % [inventory.get("used", "-"), inventory.get("capacity", "-")]
	if not _profile.is_empty() and not _alive():
		summary.text += "\n" + tr("Deceased")
	if _profile.get("stats", {}).get("gold", "0") != "0":
		_item(inventory_list, {"item_id": "gold", "name": "Gold", "quantity": _profile.stats.gold})
	for item in inventory.get("items", []):
		if item is Dictionary:
			_item(inventory_list, item)
	if memorial:
		summary.text = tr("In Memoriam")
		var notice: Dictionary = _grave.get("obituary", _obituary)
		var name_label := _label(grave_list, notice.get("name", ""))
		name_label.name = "MemorialName"
		name_label.add_theme_font_size_override("font_size", 28)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preview(_grave.get("kind", "headstone"))
		for entry in [["Born: %s", "born_at"], ["Lived days: %s", "lived_days"], ["Lifetime wealth: %s gold", "lifetime_gold"], ["Friends: %s", "friends_count"]]:
			var value := str(notice.get(entry[1], "-"))
			if entry[1] == "born_at" and value != "-":
				value = value.replace("T", " ").trim_suffix("Z") + " UTC"
			var statistic := _label(grave_list, tr(entry[0]) % value)
			statistic.name = entry[1]
			statistic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not _obituary.is_empty():
		var create := Button.new()
		create.name = "NewCharacter"
		create.text = "New character"
		create.custom_minimum_size.y = 44
		create.pressed.connect(func() -> void: hide(); new_character_requested.emit())
		grave_list.add_child(create)
	elif not _grave.is_empty():
		if _grave.get("gold", "0") != "0":
			_item(grave_list, {"item_id": "gold", "name": "Gold", "quantity": _grave.gold}, _grave.id)
		for item in _grave.get("items", []):
			if item is Dictionary:
				_item(grave_list, item, _grave.id)
	_resize.call_deferred()

static func _bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var relative: Transform3D = mesh.transform
		var ancestor: Node = mesh.get_parent()
		while ancestor != model:
			if ancestor is Node3D:
				relative = ancestor.transform * relative
			ancestor = ancestor.get_parent()
		var box: AABB = relative * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

static func create_memorial(kind: String) -> Node3D:
	var model := Node3D.new()
	if not MODELS.has(kind):
		return model
	for filename in MODELS[kind]:
		var scene: PackedScene = load(GRAVES + filename + ".glb")
		var part: Node3D = scene.instantiate()
		model.add_child(part)
		if filename == "crypt-large-roof":
			part.position.y = _bounds(model.get_child(0)).end.y - _bounds(part).position.y
		elif filename == "crypt-large-door":
			part.position.z = _bounds(model.get_child(0)).end.z
	return model

func _preview(kind: String) -> void:
	if not MODELS.has(kind):
		return
	preview_container = SubViewportContainer.new()
	preview_container.custom_minimum_size.y = 180
	preview_container.stretch = true
	grave_list.add_child(preview_container)
	preview = SubViewport.new()
	preview.size = Vector2i(360, 180)
	preview.own_world_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(preview)
	_model = create_memorial(kind)
	preview.add_child(_model)
	var bounds := _bounds(_model)
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length(), 0.5)
	var camera := Camera3D.new()
	preview.add_child(camera)
	camera.position = center + Vector3(1, 0.7, 1.4).normalized() * radius
	camera.look_at(center)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	preview.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.22, 0.24)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	preview.add_child(environment)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(panel):
		_render()
		feedback.text = tr(_feedback_key)