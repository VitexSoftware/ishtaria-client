extends CanvasLayer

signal sound_toggled(enabled: bool)
signal inventory_requested
signal connection_requested

const ASSETS := "res://assets/kenney/ui-adventure/PNG/Default/"
const ICONS := "res://assets/kenney/game-icons/"
const RPG := "res://assets/kenney/ui-rpg/PNG/"
const BORDER := "res://assets/kenney/fantasy-ui-borders/PNG/Default/Border/panel-border-000.png"
const METERS := {"health": ["Health", "red"], "stamina": ["Stamina", "green"], "food": ["Food", "white"], "water": ["Water", "blue"]}

var sound_enabled := true
var sky: Node
var clock_label: Label
var _clock_elapsed := 1.0
var panel: PanelContainer
var grid: GridContainer
var meters: Dictionary = {}
var player_name: Label
var level_label: Label
var age_label: Label
var experience_label: Label
var gold_label: Label
var inventory_button: Button
var connection_button: Button
var sound_checkbox: Button
var _frame: NinePatchRect
var _labels: Dictionary = {}
var _values: Dictionary = {}
var _player: Dictionary = {}

func _ready() -> void:
	layer = 2
	panel = PanelContainer.new()
	panel.name = "PlayerHUD"
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -8.0
	panel.offset_top = -120.0
	panel.theme = Theme.new()
	panel.theme.default_font_size = 12
	var style := _texture_style(RPG + "panelInset_blue.png", 10.0)
	style.modulate_color = Color(0.24, 0.30, 0.31, 0.96)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 10.0)
	panel.add_theme_stylebox_override("panel", style)
	_frame = NinePatchRect.new()
	_frame.texture = load(BORDER)
	_frame.patch_margin_left = 16
	_frame.patch_margin_right = 16
	_frame.patch_margin_top = 16
	_frame.patch_margin_bottom = 16
	_frame.modulate = Color(0.72, 0.65, 0.44, 0.65)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	panel.resized.connect(_sync_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)
	player_name = Label.new()
	player_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_name.add_theme_font_size_override("font_size", 15)
	header.add_child(player_name)
	level_label = Label.new()
	level_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	level_label.add_theme_color_override("font_color", Color(0.86, 0.78, 0.56))
	header.add_child(level_label)
	inventory_button = Button.new()
	inventory_button.name = "Inventory"
	inventory_button.icon = load(ICONS + "basket.png")
	inventory_button.expand_icon = true
	inventory_button.pressed.connect(func() -> void: inventory_requested.emit())
	header.add_child(inventory_button)
	connection_button = Button.new()
	connection_button.name = "ConnectionSettings"
	connection_button.icon = load(ICONS + "gear.png")
	connection_button.expand_icon = true
	connection_button.pressed.connect(func() -> void: connection_requested.emit())
	header.add_child(connection_button)
	sound_checkbox = Button.new()
	sound_checkbox.name = "InterfaceSounds"
	sound_checkbox.toggle_mode = true
	sound_checkbox.button_pressed = sound_enabled
	sound_checkbox.toggled.connect(_on_sound_toggled)
	header.add_child(sound_checkbox)
	for button in [inventory_button, connection_button, sound_checkbox]:
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 16)
		button.custom_minimum_size = Vector2(28, 28)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var surface := _texture_style(RPG + ("buttonSquare_grey_pressed.png" if state in ["pressed", "hover_pressed"] else "buttonSquare_grey.png"), 8.0)
			surface.modulate_color = Color(0.40, 0.45, 0.46) if state in ["hover", "hover_pressed"] else Color(0.28, 0.32, 0.33)
			for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
				surface.set_content_margin(side, 5.0)
			button.add_theme_stylebox_override(state, surface)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	column.add_child(grid)
	for key in METERS:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		grid.add_child(cell)
		var heading := HBoxContainer.new()
		cell.add_child(heading)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(label)
		_labels[key] = label
		var value := Label.new()
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value.custom_minimum_size.x = 44.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		heading.add_child(value)
		_values[key] = value
		var meter := ProgressBar.new()
		meter.custom_minimum_size = Vector2(90.0, 10.0)
		meter.show_percentage = false
		meter.add_theme_stylebox_override("background", _style("progress_transparent.png", 4.0))
		var fill := _style("progress_%s.png" % METERS[key][1], 4.0)
		if key == "food":
			fill.modulate_color = Color(0.95, 0.73, 0.3)
		meter.add_theme_stylebox_override("fill", fill)
		cell.add_child(meter)
		meters[key] = meter
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	clock_label = Label.new()
	clock_label.name = "SolarClock"
	clock_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	clock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_label.custom_minimum_size.y = 42.0
	clock_label.add_theme_color_override("font_color", Color(0.82, 0.87, 0.86))
	footer.add_child(clock_label)
	var progression := VBoxContainer.new()
	progression.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progression.add_theme_constant_override("separation", 0)
	footer.add_child(progression)
	age_label = Label.new()
	age_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	age_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progression.add_child(age_label)
	experience_label = Label.new()
	experience_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	experience_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progression.add_child(experience_label)
	for label in [age_label, experience_label]:
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(0.65, 0.73, 0.73))
	gold_label = Label.new()
	gold_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.35))
	gold_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progression.add_child(gold_label)
	get_viewport().size_changed.connect(_resize)
	_resize()
	clear_player()

func _style(filename: String, border: float) -> StyleBoxTexture:
	return _texture_style(ASSETS + filename, border)

func _texture_style(path: String, border: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(path)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_texture_margin(side, border)
	return style

func _resize() -> void:
	var width := get_viewport().get_visible_rect().size.x
	var margin := maxf(8.0, (width - 920.0) / 2.0)
	panel.offset_left = margin
	panel.offset_right = -margin
	grid.columns = 4 if width >= 600.0 else 2
	panel.offset_top = -maxf(120.0, panel.get_combined_minimum_size().y)
	_sync_frame.call_deferred()

func _sync_frame() -> void:
	_frame.position = panel.position
	_frame.size = panel.size
	_frame.visible = panel.visible

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(grid):
		_update_labels()

func _process(delta: float) -> void:
	_frame.visible = panel.visible
	_clock_elapsed += delta
	if _clock_elapsed >= 1.0:
		_clock_elapsed = 0.0
		_update_clock()

func _update_clock() -> void:
	var state: Dictionary = sky.clock_state() if is_instance_valid(sky) else {}
	clock_label.tooltip_text = tr("Local solar time; sunrise and sunset use the astronomical horizon")
	if state.is_empty():
		clock_label.text = tr("Time unavailable")
		return
	var local_minutes := int(state.local_seconds / 60.0)
	var time := "%02d:%02d" % [local_minutes / 60, local_minutes % 60]
	var event: String
	if state.remaining_seconds < 0.0:
		event = tr("Sunset beyond 24 h" if state.day else "Sunrise beyond 24 h")
	else:
		var minutes := int(ceil(state.remaining_seconds / 60.0))
		var remaining := "%02d:%02d" % [minutes / 60, minutes % 60]
		event = tr("Sunset in %s" if state.day else "Sunrise in %s") % remaining
	clock_label.text = tr("Solar time %s") % time + "\n" + event

func _on_sound_toggled(value: bool) -> void:
	sound_enabled = value
	sound_checkbox.icon = load(ICONS + ("audioOn.png" if value else "audioOff.png"))
	sound_toggled.emit(value)

func clear_player() -> void:
	_player = {}
	for key in meters:
		meters[key].value = 0.0
		meters[key].modulate.a = 0.45
		_values[key].text = "-"
	_update_labels()

func set_player(profile: Dictionary) -> bool:
	if not profile.get("username") is String or not profile.get("stats") is Dictionary:
		return false
	var stats: Dictionary = profile.stats
	var gold: Variant = stats.get("gold")
	if not gold is String:
		return false
	var gold_pattern := RegEx.new()
	gold_pattern.compile("^(0|[1-9][0-9]{0,18})$")
	if gold_pattern.search(gold) == null or (gold.length() == 19 and gold > "9223372036854775807"):
		return false
	var life: Variant = profile.get("life", {})
	if not life is Dictionary:
		return false
	if life.has("age_days"):
		var age: Variant = life.age_days
		if not age is String or gold_pattern.search(age) == null or (age.length() == 19 and age > "9223372036854775807"):
			return false
	for key in METERS:
		var value: Variant = stats.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0 or value > 100:
			return false
	for key in ["level", "experience"]:
		var value: Variant = stats.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or value != floor(value) or value < (1 if key == "level" else 0):
			return false
	_player = profile.duplicate(true)
	for key in meters:
		meters[key].value = stats[key]
		meters[key].modulate.a = 1.0
		_values[key].text = "%s/100" % int(stats[key])
	_update_labels()
	return true

func _update_labels() -> void:
	_update_clock()
	connection_button.tooltip_text = tr("Connection settings")
	inventory_button.tooltip_text = tr("Inventory")
	sound_checkbox.icon = load(ICONS + ("audioOn.png" if sound_enabled else "audioOff.png"))
	sound_checkbox.tooltip_text = tr("Interface sounds")
	for key in _labels:
		_labels[key].text = tr(METERS[key][0])
		meters[key].tooltip_text = tr(METERS[key][0])
	player_name.text = _player.username if not _player.is_empty() else tr("Not signed in")
	player_name.tooltip_text = player_name.text
	level_label.text = tr("Level %s") % (_player.stats.level if not _player.is_empty() else "-")
	level_label.tooltip_text = level_label.text
	age_label.text = tr("Age: %s days") % _player.get("life", {}).get("age_days", "-")
	age_label.tooltip_text = age_label.text
	experience_label.text = tr("Experience %s") % (_player.stats.experience if not _player.is_empty() else "-")
	experience_label.tooltip_text = experience_label.text
	gold_label.text = tr("Gold %s") % (_player.stats.gold if not _player.is_empty() else "-")
	gold_label.tooltip_text = gold_label.text
	_resize.call_deferred()