extends CanvasLayer

signal submitted(nickname: String, password: String, character: String, create: bool)
signal dismissed
signal selection_changed
signal language_selected(index: int)

const CATALOG := preload("res://scripts/character_catalog.gd")
var nickname_input: LineEdit
var password_input: LineEdit
var packs: OptionButton
var characters: OptionButton
var mode: TabBar
var submit_button: Button
var back_button: Button
var feedback: Label
var rotation_slider: HSlider
var language_choice: OptionButton
var model: Node3D
var character := CATALOG.NEW_CHARACTER_DEFAULT
var _listed: Array = []
var _screen: Control
var _preview: SubViewportContainer
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _form: MarginContainer
var _band: ColorRect
var _appearance: VBoxContainer
var _heading: Label
var _feedback_key := ""
var _rotating := false

func _ready() -> void:
	layer = 10
	visibility_changed.connect(func() -> void: _rotating = false)
	_screen = Control.new()
	add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview = SubViewportContainer.new()
	_preview.stretch = true
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_preview.gui_input.connect(_on_preview_input)
	_screen.add_child(_preview)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_preview.add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.7, 0.79, 0.77)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	world_environment.environment = environment
	_stage.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	_stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.49, 0.59, 0.53)
	floor_mesh.material_override = floor_material
	_stage.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	_stage.add_child(_camera)
	_band = ColorRect.new()
	_band.color = Color(0.065, 0.08, 0.075)
	_screen.add_child(_band)
	_form = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		_form.add_theme_constant_override("margin_" + side, 16)
	_screen.add_child(_form)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_form.add_child(column)
	var heading_row := HBoxContainer.new()
	column.add_child(heading_row)
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 24)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(_heading)
	language_choice = OptionButton.new()
	language_choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language_choice.add_icon_item(preload("res://assets/kenney/flag-pack/GB.png"), "English")
	language_choice.add_icon_item(preload("res://assets/kenney/flag-pack/CZ.png"), "Čeština")
	language_choice.item_selected.connect(func(index: int) -> void: language_selected.emit(index))
	heading_row.add_child(language_choice)
	mode = TabBar.new()
	mode.add_tab("New player")
	mode.add_tab("Sign in")
	mode.tab_changed.connect(_on_mode_changed)
	column.add_child(mode)
	var credentials := HBoxContainer.new()
	credentials.add_theme_constant_override("separation", 12)
	column.add_child(credentials)
	var nickname_column := VBoxContainer.new()
	nickname_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credentials.add_child(nickname_column)
	_label(nickname_column, "Nickname")
	nickname_input = LineEdit.new()
	nickname_input.max_length = 32
	nickname_input.custom_minimum_size.y = 36
	nickname_column.add_child(nickname_input)
	var password_column := VBoxContainer.new()
	password_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credentials.add_child(password_column)
	_label(password_column, "Password")
	password_input = LineEdit.new()
	password_input.secret = true
	password_input.max_length = 128
	password_input.placeholder_text = tr("Optional password")
	password_input.custom_minimum_size.y = 36
	password_column.add_child(password_input)
	_appearance = VBoxContainer.new()
	column.add_child(_appearance)
	packs = OptionButton.new()
	packs.custom_minimum_size.y = 36
	for pack in ["Protagonists", "Retro", "Survivors", "Quaternius"]:
		packs.add_item(pack)
	packs.item_selected.connect(_on_pack_changed)
	_appearance.add_child(packs)
	characters = OptionButton.new()
	characters.custom_minimum_size.y = 36
	characters.item_selected.connect(_on_character_selected)
	_appearance.add_child(characters)
	rotation_slider = HSlider.new()
	rotation_slider.min_value = -180.0
	rotation_slider.max_value = 180.0
	rotation_slider.step = 0.0
	rotation_slider.value_changed.connect(_on_rotation_changed)
	_appearance.add_child(rotation_slider)
	var commands := HBoxContainer.new()
	column.add_child(commands)
	submit_button = Button.new()
	submit_button.custom_minimum_size.y = 36
	submit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit_button.pressed.connect(_submit)
	commands.add_child(submit_button)
	back_button = Button.new()
	back_button.text = "Later"
	back_button.custom_minimum_size.y = 36
	back_button.pressed.connect(func() -> void: password_input.clear(); hide(); dismissed.emit())
	commands.add_child(back_button)
	feedback = Label.new()
	feedback.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_color_override("font_color", Color(1.0, 0.58, 0.5))
	feedback.custom_minimum_size.y = 40
	column.add_child(feedback)
	_screen.resized.connect(_resize)
	set_selection(CATALOG.NEW_CHARACTER_DEFAULT)
	_update_labels()
	_resize()

func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)

func show_setup(nickname: String, selected: String, create := true) -> void:
	nickname_input.text = nickname
	password_input.clear()
	mode.current_tab = 0 if create else 1
	set_selection(selected if CATALOG.is_valid(selected) else CATALOG.NEW_CHARACTER_DEFAULT)
	set_feedback("")
	show()
	_on_mode_changed(mode.current_tab)
	if not create and not nickname.is_empty():
		password_input.grab_focus()
	else:
		nickname_input.grab_focus()

func set_selection(selected: String) -> void:
	if not CATALOG.is_valid(selected):
		return
	character = selected
	var parts := character.split("/")
	packs.select(CATALOG.PACKS.find(parts[0]))
	_fill_characters()
	for index in _listed.size():
		if _listed[index][0] == parts[1]:
			characters.select(index)
	_show_model()

func _fill_characters() -> void:
	characters.clear()
	_listed = CATALOG.selectable(CATALOG.PACKS[packs.selected], character)
	for entry in _listed:
		characters.add_item(tr(entry[1]))

func _on_pack_changed(index: int) -> void:
	character = ""
	_fill_characters()
	character = CATALOG.PACKS[index] + "/" + _listed[0][0]
	characters.select(0)
	_show_model()
	selection_changed.emit()

func _on_character_selected(index: int) -> void:
	character = CATALOG.PACKS[packs.selected] + "/" + _listed[index][0]
	_show_model()
	selection_changed.emit()

func _show_model() -> void:
	if is_instance_valid(model):
		model.free()
	model = CATALOG.create_model(character)
	_stage.add_child(model)
	var height := 0.1
	if character.begins_with("quaternius/"):
		# A skinned glTF mesh is drawn by its skeleton, so its mesh bounds say nothing about its size, and
		# the head bone of a few models is off. All of them are scaled to a person of 1.8 metres.
		height = 1.8 * CATALOG.GLTF_UNITS_PER_METRE
	else:
		var bounds := AABB()
		var first := true
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_bounds: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
			first = false
		model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
		height = maxf(bounds.size.y, 0.1)
	_camera.near = height * 0.01
	_camera.position = Vector3(0, height * 0.65, height * 2.5)
	_camera.look_at(Vector3(0, height * 0.5, 0))
	_on_rotation_changed(rotation_slider.value)

func _on_rotation_changed(value: float) -> void:
	if is_instance_valid(model):
		model.rotation_degrees.y = value

func _on_preview_input(event: InputEvent) -> void:
	if mode.current_tab != 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_rotating = event.pressed
		_preview.accept_event()
	elif event is InputEventMouseMotion and _rotating:
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_rotating = false
			return
		rotation_slider.value = wrapf(rotation_slider.value + event.relative.x * 0.5, -180.0, 180.0)
		_preview.accept_event()

func _on_mode_changed(index: int) -> void:
	_rotating = false
	_appearance.visible = index == 0
	_update_labels()
	_resize()

func _submit() -> void:
	set_feedback("")
	var password := password_input.text
	password_input.clear()
	submitted.emit(nickname_input.text.strip_edges(), password, character, mode.current_tab == 0)

func set_busy(value: bool) -> void:
	submit_button.disabled = value
	for index in mode.tab_count:
		mode.set_tab_disabled(index, value)
	packs.disabled = value
	characters.disabled = value

func set_feedback(message: String) -> void:
	_feedback_key = message
	feedback.text = tr(message) if not message.is_empty() else ""
	_resize()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(feedback):
		_update_labels()

func _update_labels() -> void:
	language_choice.select(1 if TranslationServer.get_locale() == "cs" else 0)
	language_choice.tooltip_text = tr("Language")
	_heading.text = tr("New player" if mode.current_tab == 0 else "Sign in")
	mode.set_tab_title(0, tr("New player"))
	mode.set_tab_title(1, tr("Sign in"))
	submit_button.text = tr("Create player" if mode.current_tab == 0 else "Sign in")
	back_button.text = tr("Change server")
	rotation_slider.tooltip_text = tr("Rotation")
	nickname_input.tooltip_text = tr("Nickname")
	password_input.tooltip_text = tr("Password")
	password_input.placeholder_text = tr("Optional password")
	var selected := characters.selected
	_fill_characters()
	characters.select(maxi(selected, 0))
	feedback.text = tr(_feedback_key) if not _feedback_key.is_empty() else ""

func _resize() -> void:
	if not is_instance_valid(_form):
		return
	var dimensions := _screen.size
	var compact := dimensions.x < 600.0
	var height := _form.get_combined_minimum_size().y
	_form.position = Vector2(0, maxf(dimensions.y - height, 0)) if compact else Vector2(dimensions.x - 360.0, 0)
	_form.size = Vector2(dimensions.x, height) if compact else Vector2(360.0, dimensions.y)
	_band.position = _form.position
	_band.size = _form.size
	_preview.size = Vector2(dimensions.x, maxf(dimensions.y - height, 1)) if compact else Vector2(dimensions.x - 360.0, dimensions.y)