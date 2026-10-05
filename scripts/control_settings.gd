extends Window

signal closed

var controls: Node3D
## Whether closing the dialog gives the mouse back to the game; off when the ESC menu opened it.
var recapture := true
var _fullscreen: CheckBox
var _buttons: Array[Button] = []
var _waiting := -1
var _feedback: Label
var _sensitivity: HSlider
var _invert: CheckBox

func _ready() -> void:
	title = tr("Settings")
	size = Vector2i(360, 450)
	min_size = Vector2i(300, 420)
	transient = true
	exclusive = true
	close_requested.connect(_close)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_fullscreen = CheckBox.new()
	_fullscreen.name = "Fullscreen"
	_fullscreen.text = tr("Fullscreen")
	_fullscreen.toggled.connect(func(enabled: bool) -> void:
		apply_fullscreen(enabled)
		_feedback.text = "" if save_fullscreen(enabled) else tr("Could not save controls")
	)
	column.add_child(_fullscreen)
	for index in controls.ACTIONS.size():
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := Label.new()
		label.text = controls.LABELS[index]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 32)
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.pressed.connect(_begin_binding.bind(index))
		row.add_child(button)
		_buttons.append(button)
	var label := Label.new()
	label.text = "Mouse sensitivity"
	column.add_child(label)
	_sensitivity = HSlider.new()
	_sensitivity.min_value = 0.0005
	_sensitivity.max_value = 0.01
	_sensitivity.step = 0.0001
	_sensitivity.value = controls.sensitivity
	_sensitivity.value_changed.connect(func(value: float) -> void:
		controls.sensitivity = value
		_save()
	)
	column.add_child(_sensitivity)
	_invert = CheckBox.new()
	_invert.text = "Invert mouse Y"
	_invert.button_pressed = controls.invert_y
	_invert.toggled.connect(func(enabled: bool) -> void:
		controls.invert_y = enabled
		_save()
	)
	column.add_child(_invert)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.y = 24
	column.add_child(_feedback)
	var row := HBoxContainer.new()
	column.add_child(row)
	var reset := Button.new()
	reset.text = "Restore defaults"
	reset.pressed.connect(func() -> void:
		controls.reset_keys()
		controls.sensitivity = 0.002
		controls.invert_y = false
		_sensitivity.set_value_no_signal(controls.sensitivity)
		_invert.set_pressed_no_signal(false)
		_waiting = -1
		_save()
		_refresh()
	)
	row.add_child(reset)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close)
	row.add_child(close)
	_refresh()
	hide()

func open() -> void:
	controls.release_mouse()
	_waiting = -1
	_feedback.text = ""
	_fullscreen.set_pressed_no_signal(is_fullscreen())
	_refresh()
	popup_centered(Vector2i(mini(360, get_tree().root.size.x - 16), mini(450, get_tree().root.size.y - 32)))

static func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

static func apply_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

## The display preference is the client's own and shares the file of the other preferences.
func save_fullscreen(enabled: bool) -> bool:
	var config := ConfigFile.new()
	config.load(controls.settings_path)
	config.set_value("display", "fullscreen", enabled)
	return config.save(controls.settings_path) == OK

func _begin_binding(index: int) -> void:
	_waiting = index
	_refresh()

func _refresh() -> void:
	for index in _buttons.size():
		_buttons[index].text = tr("Press a key") if index == _waiting else OS.get_keycode_string(controls.key_for(index))

func _save() -> void:
	_feedback.text = "" if controls.save_preferences() else tr("Could not save controls")

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _waiting >= 0:
			if event.physical_keycode != KEY_ESCAPE and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
				_feedback.text = "" if controls.rebind(_waiting, event.physical_keycode) else tr("Could not save controls")
			_waiting = -1
			_refresh()
			set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_close()
			set_input_as_handled()

func _close() -> void:
	_waiting = -1
	hide()
	if recapture:
		controls.capture_mouse()
	closed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		title = tr("Settings")
		if is_instance_valid(_fullscreen):
			_fullscreen.text = tr("Fullscreen")
		_refresh()