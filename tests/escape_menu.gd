extends SceneTree

const MENU := preload("res://scripts/escape_menu.gd")

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _entry(name: String, gold: String, days: String, alive: Variant) -> Dictionary:
	return {"name": name, "level": 3, "score": "420", "wealth": gold, "lived_days": days, "alive": alive, "looted": false}

func _run() -> void:
	_check(MENU.group_digits("0") == "0" and MENU.group_digits("999") == "999", "short numbers are not grouped")
	_check(MENU.group_digits("1000") == "1 000" and MENU.group_digits("9000000000000") == "9 000 000 000 000", "digits are grouped in threes")
	_check(MENU.valid_hall([]) and MENU.valid_hall([_entry("a", "100", "0", true)]), "valid hall lists")
	var many := []
	for i in 11:
		many.append(_entry("p%d" % i, "100", "1", true))
	_check(not MENU.valid_hall(many), "more than ten entries are refused")
	for broken in [{"name": "a", "level": 0, "score": "1", "wealth": "1", "lived_days": "1", "alive": true}, {"name": "a", "level": 1, "score": "x", "wealth": "1", "lived_days": "1", "alive": true}, _entry("", "1", "1", true), _entry("a", "-1", "1", true), _entry("a", "1.5", "1", true), _entry("a", "1", "x", true), _entry("a", "1", "1", "yes"), {"name": "a"}, "text"]:
		_check(not MENU.valid_hall([broken] if broken is Dictionary else broken), "malformed entry %s" % [broken])
	_check(not MENU.valid_hall("nonsense") and not MENU.valid_hall(null), "non-lists are refused")

	var menu := MENU.new()
	root.add_child(menu)
	await process_frame
	_check(not menu.visible and not menu.is_open(), "the menu starts closed")
	_check(menu.title_label.text == "Ishtaria", "the title is the name of the game")
	var asked := []
	menu.settings_requested.connect(func() -> void: asked.append("settings"))
	menu.quit_requested.connect(func() -> void: asked.append("quit"))
	menu.open("")
	_check(menu.visible and menu.is_open(), "the menu opens")
	_check(menu.hall_status.text != "" and menu.hall_grid.get_child_count() == 0, "without a server there is no hall")
	menu.settings_button.pressed.emit()
	menu.quit_button.pressed.emit()
	_check(asked == ["settings", "quit"], "the two choices are offered")
	_check(menu.show_hall([_entry("Alice", "9000000000000", "120", true), _entry("Bob", "5000", "3", false)]), "a hall is accepted")
	await process_frame
	_check(menu.hall_grid.get_child_count() == 6 * 3, "a header and two rows of six cells")
	var texts := []
	for cell: Node in menu.hall_grid.get_children():
		texts.append(cell.text if cell is Label else "")
	var bob := menu.hall_grid.find_child("Name_Bob", true, false)
	var alice := menu.hall_grid.find_child("Name_Alice", true, false)
	_check(bob != null and bob.find_child("Headstone", true, false) != null, "a dead character is marked with a headstone")
	_check(alice != null and alice.find_child("Headstone", true, false) == null, "a living character is not")
	_check(ResourceLoader.exists("res://assets/icons/ui/headstone.png"), "the headstone icon is bundled")
	_check("9 000 000 000 000" in texts and "120 d" in texts, "wealth and life are shown: %s" % [texts])
	_check(not menu.hall_status.visible, "the status is hidden while there is a hall")
	_check(not menu.show_hall("junk") and menu.hall_grid.get_child_count() == 0 and menu.hall_status.visible, "a bad answer shows the failure")
	_check(menu.show_hall([]) and menu.hall_status.visible, "an empty hall says so")
	menu.close()
	_check(not menu.visible, "the menu closes")

	# The settings dialog keeps the fullscreen choice with the other preferences.
	var path := "user://menu-test-%d.cfg" % Time.get_ticks_usec()
	var controls := preload("res://scripts/character_controls.gd").new()
	controls.settings_path = path
	root.add_child(controls)
	var settings := preload("res://scripts/control_settings.gd").new()
	settings.controls = controls
	root.add_child(settings)
	await process_frame
	var keep := ConfigFile.new()
	keep.set_value("connection", "server_url", "http://example.org:7400")
	keep.save(path)
	_check(settings.save_fullscreen(true), "the choice is saved")
	var loaded := ConfigFile.new()
	loaded.load(path)
	_check(loaded.get_value("display", "fullscreen") == true and loaded.get_value("connection", "server_url") == "http://example.org:7400", "other preferences are preserved")
	_check(settings.find_child("Fullscreen", true, false) is CheckBox, "the dialog has a fullscreen check box")
	_check(settings.title == "Settings", "the dialog is the settings dialog")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	if _failures > 0:
		push_error("%d escape menu checks failed" % _failures)
	else:
		print("Escape menu checks passed")
	quit(1 if _failures > 0 else 0)
