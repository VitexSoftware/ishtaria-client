extends Node3D
## Planet preview with a server heightmap and approach to the player location.
## Surface walking is resolved by the authoritative server.

const PLANET_RADIUS := 6371.0 # scene units = km in this preview
const DEFAULT_SERVER_URL := "http://127.0.0.1:7400"
const APPROACH_SECONDS := 4.0
const SURFACE_ALTITUDE_M := 120.0
## Slightly below the server reach, so a request made at the edge is not refused.
const HARVEST_REACH_M := 3.6
## How close a character must be to talk to them (the server allows a little more).
const TALK_REACH_M := 4.5

var _camera: Camera3D
var _yaw := 0.0
var _status: Label
var _server_input: LineEdit
var _feedback: Label
var _disconnect_button: Button
var _reconnect: Timer
var _request: HTTPRequest
var _request_pending := false
var _connected_world := ""
var _server_url := DEFAULT_SERVER_URL
var _connection_enabled := false
var _connection_generation := 0
var _settings_path := "user://client.cfg"
var _sky: Node
var _language_option: OptionButton
var _language_label: Label
var _address_label: Label
var _connect_button: Button
var _history: Node
var _history_list: ItemList
var _history_test_button: Button
var _history_forget_button: Button
var _status_key := "Disconnected"
var _status_args: Array = []
var _status_reason_key := ""
var _status_reason_args: Array = []
var _feedback_key := ""
var _audio: Node
var _hud: CanvasLayer
var _system_messages: CanvasLayer
var _disk_cover: CanvasLayer
var _session: Node
var _creator: CanvasLayer
var _player_button: Button
var _sign_out_button: Button
var _player_profile: Dictionary = {}
var _toast: Node
var _portals: Node
var _escape_menu: Node
var _social: Node
var _story: Node
var _dialogue: CanvasLayer
var _quest_log: CanvasLayer
var _quest_stages: Dictionary = {}
var _quests_baseline := false
## A tool the player chose to use from the inventory that is still being put in hand.
var _pending_tool := ""
## A drink was requested and its answer has not arrived yet.
var _drinking := false
## Whether the player chose to show their flag to others (the flag follows the chosen language).
var _share_flag := false
var _flag_check: CheckBox
var _blocking := false
var _block_renew := 0.0
var _friends: CanvasLayer
var _chat: CanvasLayer
var _portal_poll := 0.0
var _player_metres := Vector3.ZERO
var _prompt_elapsed := 0.0
var _survival: CanvasLayer
var _startup_pending := true
var _surface_direction := Vector3.ZERO
var _approach_elapsed := 0.0
var _approach_start := Vector3.ZERO
var _approach_up := Vector3.UP
var _approach_rotation := Quaternion.IDENTITY
var _terrain_material: ShaderMaterial
var _terrain_request: HTTPRequest
var _terrain_loaded := false
var _connection_panel: PanelContainer
var _environment: Node3D
var _environment_request: HTTPRequest
var _world_metadata: Dictionary = {}
var _water_material: ShaderMaterial
var _controls: Node3D
var _control_settings: Window
var _area_music: Node
var _area_elapsed := 0.0
var _move_elapsed := 0.0

func _ready() -> void:
	var planet := MeshInstance3D.new()
	planet.name = "Planet"
	var mesh := SphereMesh.new()
	mesh.radius = PLANET_RADIUS
	mesh.height = PLANET_RADIUS * 2.0
	mesh.radial_segments = 512
	mesh.rings = 256
	planet.mesh = mesh
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = preload("res://scripts/planet_surface.gdshader")
	planet.material_override = _terrain_material
	add_child(planet)
	var ocean := MeshInstance3D.new()
	ocean.name = "Ocean"
	var ocean_mesh := SphereMesh.new()
	ocean_mesh.radius = PLANET_RADIUS
	ocean_mesh.height = PLANET_RADIUS * 2.0
	ocean_mesh.radial_segments = 256
	ocean_mesh.rings = 128
	ocean.mesh = ocean_mesh
	_water_material = ShaderMaterial.new()
	_water_material.shader = preload("res://scripts/planet_surface.gdshader")
	_water_material.set_shader_parameter("water_pass", true)
	ocean.material_override = _water_material
	ocean.visible = false
	add_child(ocean)
	_environment = preload("res://scripts/surface_environment.gd").new()
	_environment.land_material = _terrain_material
	_environment.water_material = _water_material
	add_child(_environment)
	_environment.objects_failed.connect(_on_player_failed)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	add_child(sun)
	_sky = preload("res://scripts/planet_sky.gd").new()
	_sky.sun = sun
	add_child(_sky)

	_camera = Camera3D.new()
	_camera.near = 1.0
	_camera.far = PLANET_RADIUS * 10.0
	add_child(_camera)
	_controls = preload("res://scripts/character_controls.gd").new()
	_controls.camera = _camera
	_controls.settings_path = _settings_path
	add_child(_controls)
	_control_settings = preload("res://scripts/control_settings.gd").new()
	_control_settings.controls = _controls
	add_child(_control_settings)

	var settings := ConfigFile.new()
	var language := "en"
	if settings.load(_settings_path) == OK:
		var saved_url: Variant = settings.get_value("connection", "server_url", DEFAULT_SERVER_URL)
		if saved_url is String and not _normalize_server_url(saved_url).is_empty():
			_server_url = _normalize_server_url(saved_url)
		var saved_language: Variant = settings.get_value("interface", "language", "en")
		if saved_language is String and saved_language in ["en", "cs"]:
			language = saved_language
		_share_flag = settings.get_value("interface", "share_flag", false) == true
	TranslationServer.set_locale(language)
	_history = preload("res://scripts/server_history.gd").new()
	_history.settings_path = _settings_path
	_history.url_validator = _normalize_server_url
	_history.load_entries()
	_history.changed.connect(_refresh_history_list)
	add_child(_history)
	_audio = preload("res://scripts/interface_audio.gd").new()
	if settings.get_value("display", "fullscreen", false) == true and DisplayServer.get_name() != "headless":
		_control_settings.apply_fullscreen(true)
	var saved_sound: Variant = settings.get_value("audio", "interface_sounds", true)
	_audio.enabled = saved_sound if saved_sound is bool else true
	add_child(_audio)
	_hud = preload("res://scripts/player_hud.gd").new()
	_hud.sky = _sky
	_hud.sound_enabled = _audio.enabled
	_hud.sound_toggled.connect(_on_sound_toggled)
	add_child(_hud)
	_system_messages = preload("res://scripts/system_messages.gd").new()
	add_child(_system_messages)
	_disk_cover = preload("res://scripts/disk_cover.gd").new()
	add_child(_disk_cover)
	_session = preload("res://scripts/player_session.gd").new()
	_session.profile_changed.connect(_on_player_profile)
	_session.busy_changed.connect(func(busy: bool) -> void:
		if not busy:
			_sync_flag())
	_session.position_changed.connect(_on_player_position)
	_session.stats_changed.connect(_on_player_stats)
	_session.failed.connect(_on_player_failed)
	_session.harvested.connect(_on_harvested)
	_session.crafted.connect(_on_crafted)
	add_child(_session)
	_toast = preload("res://scripts/action_toast.gd").new()
	add_child(_toast)
	_survival = preload("res://scripts/survival_panel.gd").new()
	_survival.eat_requested.connect(_session.eat)
	_survival.new_character_requested.connect(_new_character)
	_survival.loot_requested.connect(_session.loot)
	_survival.craft_requested.connect(_session.craft.bind(1))
	_survival.equip_requested.connect(_session.equip)
	_survival.use_requested.connect(_use_tool)
	_survival.unequip_requested.connect(_session.unequip)
	_survival.unequip_offhand_requested.connect(_session.unequip.bind("offhand"))
	_session.blocked.connect(_on_blocked)
	_survival.recipes_requested.connect(_session.fetch_recipes)
	_session.recipes_received.connect(_survival.set_recipes)
	_session.obituary_received.connect(func(notice: Dictionary) -> void:
		_creator.password_input.clear()
		_creator.hide()
		_survival.show_obituary(notice)
	)
	_session.grave_changed.connect(_survival.set_grave)
	_session.busy_changed.connect(_survival.set_busy)
	_session.failed.connect(_survival.set_feedback)
	_portals = preload("res://scripts/portal_panel.gd").new()
	_portals.build_requested.connect(_session.build_portal)
	_portals.refresh_requested.connect(_session.fetch_portals)
	_portals.details_requested.connect(_session.fetch_portal)
	_portals.deliver_requested.connect(_session.deliver)
	_portals.link_requested.connect(_session.fetch_link)
	_portals.connect_requested.connect(_session.connect_portal)
	_portals.disconnect_requested.connect(_session.disconnect_portal)
	_portals.close_requested.connect(_session.close_portal)
	_session.link_received.connect(_portals.set_link)
	_session.portals_received.connect(_portals.set_portals)
	_session.portal_received.connect(_portals.set_portal)
	_session.portal_received.connect(func(_portal: Dictionary) -> void: _environment.refresh_portals())
	_session.portal_closed.connect(_environment.refresh_portals)
	_session.portal_closed.connect(_session.fetch_portals)
	_session.profile_changed.connect(_portals.set_profile)
	_session.busy_changed.connect(_portals.set_busy)
	_session.failed.connect(_portals.set_feedback)
	add_child(_portals)
	_escape_menu = preload("res://scripts/escape_menu.gd").new()
	_escape_menu.settings_requested.connect(_open_settings_from_menu)
	_escape_menu.quit_requested.connect(func() -> void: get_tree().quit())
	_escape_menu.friends_requested.connect(_open_friends)
	add_child(_escape_menu)
	_social = preload("res://scripts/social.gd").new()
	add_child(_social)
	_chat = preload("res://scripts/chat_feed.gd").new()
	add_child(_chat)
	_friends = preload("res://scripts/friends_panel.gd").new()
	add_child(_friends)
	_friends.add_requested.connect(_social.request_friend)
	_friends.accept_requested.connect(_social.accept)
	_friends.decline_requested.connect(_social.decline)
	_friends.remove_requested.connect(_social.remove)
	_friends.refresh_requested.connect(_social.refresh)
	_social.friends_changed.connect(_friends.set_friends)
	_social.requests_changed.connect(_friends.set_requests)
	_social.failed.connect(_friends.set_feedback)
	_social.event_received.connect(_on_friend_event)
	_story = preload("res://scripts/story_client.gd").new()
	add_child(_story)
	_dialogue = preload("res://scripts/dialogue_panel.gd").new()
	_dialogue.story = _story
	_dialogue.music_enabled = _audio.enabled
	_dialogue.voice_enabled = _audio.enabled
	_area_music = preload("res://scripts/area_music.gd").new()
	_area_music.story = _story
	_area_music.enabled = _audio.enabled
	add_child(_area_music)
	_dialogue.area_music = _area_music
	_story.media_ready.connect(_area_music.media_ready)
	var saved_music: Variant = settings.get_value("audio", "music_volume", 1.0)
	var saved_voice: Variant = settings.get_value("audio", "voice_volume", 1.0)
	_dialogue.set_music_volume(float(saved_music) if saved_music is float or saved_music is int else 1.0)
	_dialogue.set_voice_volume(float(saved_voice) if saved_voice is float or saved_voice is int else 1.0)
	_control_settings.bind_dialogue(_dialogue)
	add_child(_dialogue)
	_dialogue.choice_made.connect(_story.choose)
	_dialogue.closed.connect(_on_dialogue_closed)
	_dialogue.speaking_changed.connect(_environment.set_npc_talking)
	_story.dialogue_changed.connect(_on_dialogue_changed)
	_story.media_ready.connect(_dialogue.media_ready)
	_story.strings_changed.connect(_environment.refresh_npc_names)
	_story.failed.connect(_on_story_failed)
	_environment.npc_text = Callable(_story, "text")
	_environment.fetch_media = Callable(_story, "fetch_media")
	_story.media_ready.connect(_environment.media_ready)
	_quest_log = preload("res://scripts/quest_panel.gd").new()
	_quest_log.story = _story
	add_child(_quest_log)
	_story.quests_changed.connect(_on_quests_changed)
	_hud.inventory_requested.connect(_survival.open)
	_hud.connection_requested.connect(_toggle_connection_panel)
	add_child(_survival)
	_creator = preload("res://scripts/character_creator.gd").new()
	_creator.submitted.connect(_session.submit)
	_creator.language_selected.connect(_on_language_selected)
	_creator.selection_changed.connect(func() -> void: _audio.play("click"))
	_creator.dismissed.connect(_disconnect_server)
	_session.busy_changed.connect(_creator.set_busy)
	add_child(_creator)
	_build_connection_controls()
	var configured_url := OS.get_environment("ISHTARIA_SERVER_URL")
	if not configured_url.is_empty():
		_server_url = configured_url
	_server_input.text = _server_url
	_reconnect = Timer.new()
	_reconnect.wait_time = 5.0
	_reconnect.one_shot = true
	_reconnect.timeout.connect(_refresh_world)
	add_child(_reconnect)
	_connect_server(false)
	var saved_nickname: Variant = settings.get_value("player", "nickname", "")
	var saved_character: Variant = settings.get_value("player", "character", "")
	if saved_nickname is String and not saved_nickname.is_empty() and saved_character is String and preload("res://scripts/character_catalog.gd").is_valid(saved_character):
		_creator.nickname_input.text = saved_nickname
		_creator.set_selection(saved_character)
	_creator.hide()

func _build_connection_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	_connection_panel = panel
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.07, 0.08, 0.09, 0.95)
	panel.add_theme_stylebox_override("panel", background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := Label.new()
	title.text = "Ishtaria"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title_row.add_child(title)
	_language_label = Label.new()
	_language_label.text = "Language"
	title_row.add_child(_language_label)
	_language_option = OptionButton.new()
	_language_option.name = "Language"
	_language_option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_language_option.custom_minimum_size = Vector2(128, 36)
	_language_option.add_icon_item(preload("res://assets/kenney/flag-pack/GB.png"), "English")
	_language_option.add_icon_item(preload("res://assets/kenney/flag-pack/CZ.png"), "Čeština")
	_language_option.select(1 if TranslationServer.get_locale() == "cs" else 0)
	_language_option.item_selected.connect(_on_language_selected)
	title_row.add_child(_language_option)
	_flag_check = CheckBox.new()
	_flag_check.name = "ShareFlag"
	_flag_check.button_pressed = _share_flag
	_flag_check.toggled.connect(_on_share_flag_toggled)
	column.add_child(_flag_check)
	_status = Label.new()
	_status.name = "ConnectionStatus"
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.text = "Disconnected"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 24
	column.add_child(_status)
	var address_row := HBoxContainer.new()
	address_row.add_theme_constant_override("separation", 12)
	column.add_child(address_row)
	var address_label := Label.new()
	_address_label = address_label
	address_label.text = "Server"
	address_row.add_child(address_label)
	_server_input = LineEdit.new()
	_server_input.name = "ServerAddress"
	_server_input.placeholder_text = DEFAULT_SERVER_URL
	_server_input.tooltip_text = "Server URL"
	_server_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_input.custom_minimum_size.y = 36
	_server_input.text_submitted.connect(_on_server_submitted)
	address_row.add_child(_server_input)
	_history_list = ItemList.new()
	_history_list.name = "ServerHistory"
	_history_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_history_list.custom_minimum_size.y = 64
	_history_list.max_text_lines = 1
	_history_list.item_selected.connect(_on_history_selected)
	_history_list.item_activated.connect(func(_index: int) -> void: _connect_server())
	column.add_child(_history_list)
	var history_commands := HBoxContainer.new()
	history_commands.add_theme_constant_override("separation", 8)
	column.add_child(history_commands)
	_history_test_button = Button.new()
	_history_test_button.name = "TestServers"
	_history_test_button.custom_minimum_size = Vector2(104, 32)
	_history_test_button.pressed.connect(_on_history_test_pressed)
	history_commands.add_child(_history_test_button)
	_history_forget_button = Button.new()
	_history_forget_button.name = "ForgetServer"
	_history_forget_button.custom_minimum_size = Vector2(104, 32)
	_history_forget_button.pressed.connect(_on_history_forget_pressed)
	history_commands.add_child(_history_forget_button)
	var commands := HBoxContainer.new()
	commands.add_theme_constant_override("separation", 8)
	column.add_child(commands)
	var connect_button := Button.new()
	_connect_button = connect_button
	connect_button.name = "Connect"
	connect_button.text = "Connect"
	connect_button.custom_minimum_size = Vector2(104, 36)
	connect_button.pressed.connect(_connect_server)
	commands.add_child(connect_button)
	_disconnect_button = Button.new()
	_disconnect_button.name = "Disconnect"
	_disconnect_button.text = "Disconnect"
	_disconnect_button.custom_minimum_size = Vector2(104, 36)
	_disconnect_button.disabled = true
	_disconnect_button.pressed.connect(_on_disconnect_pressed)
	commands.add_child(_disconnect_button)
	_player_button = Button.new()
	_player_button.text = "Player"
	_player_button.custom_minimum_size = Vector2(104, 36)
	_player_button.pressed.connect(_open_player)
	commands.add_child(_player_button)
	_sign_out_button = Button.new()
	_sign_out_button.text = "Sign out"
	_sign_out_button.disabled = true
	_sign_out_button.pressed.connect(_session.sign_out)
	commands.add_child(_sign_out_button)
	var controls_button := Button.new()
	controls_button.text = "Controls"
	controls_button.pressed.connect(_control_settings.open)
	column.add_child(controls_button)
	_feedback = Label.new()
	_feedback.name = "ValidationError"
	_feedback.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.y = 24
	_feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	column.add_child(_feedback)
	_update_translations()

func _on_language_selected(index: int) -> void:
	if index < 0 or index > 1:
		return
	_audio.play("click")
	var language: String = ["en", "cs"][index]
	TranslationServer.set_locale(language)
	var settings := ConfigFile.new()
	settings.load(_settings_path)
	settings.set_value("interface", "language", language)
	if settings.save(_settings_path) != OK:
		_set_feedback("Could not save language preference")
	_update_translations()
	_sync_flag()

## The flag a player shows: none unless they chose to, otherwise that of their language.
func _desired_flag() -> Variant:
	if not _share_flag:
		return null
	return "CZ" if TranslationServer.get_locale() == "cs" else "GB"

func _on_share_flag_toggled(enabled: bool) -> void:
	_share_flag = enabled
	_audio.play("click")
	var settings := ConfigFile.new()
	settings.load(_settings_path)
	settings.set_value("interface", "share_flag", enabled)
	if settings.save(_settings_path) != OK:
		_set_feedback("Could not save language preference")
	_sync_flag()

## Tells the server which flag to show, when it differs from the one it has (opt-in only).
func _sync_flag() -> void:
	if _session == null or _session.token().is_empty() or _session.busy or _player_profile.is_empty():
		return
	if _player_profile.get("flag") == _desired_flag():
		return
	_session.set_flag(_desired_flag())

func _on_sound_toggled(enabled: bool) -> void:
	_audio.set_enabled(enabled)
	_area_music.enabled = enabled
	_dialogue.set_music_enabled(enabled)
	_dialogue.set_voice_enabled(enabled)
	_audio.play("click")
	var settings := ConfigFile.new()
	settings.load(_settings_path)
	settings.set_value("audio", "interface_sounds", enabled)
	if settings.save(_settings_path) != OK:
		_set_feedback("Could not save sound preference")

func _on_disconnect_pressed() -> void:
	_audio.play("back")
	_disconnect_server()

func _open_player() -> void:
	if _connected_world.is_empty():
		_set_feedback("Connect to a server first")
		return
	_audio.play("click")
	var settings := ConfigFile.new()
	settings.load(_settings_path)
	var nickname: Variant = settings.get_value("player", "nickname", "")
	var character: Variant = settings.get_value("player", "character", preload("res://scripts/character_catalog.gd").DEFAULT_CHARACTER)
	_creator.show_setup(nickname if nickname is String else "", character if character is String else "", nickname == "")
	_startup_pending = false

func _new_character() -> void:
	_survival.hide()
	_creator.show_setup("", preload("res://scripts/character_catalog.gd").DEFAULT_CHARACTER, true)

func _on_player_stats(stats: Dictionary) -> void:
	if _player_profile.is_empty():
		return
	var profile := _player_profile.duplicate(true)
	profile.stats = stats
	_on_player_profile(profile)

func _on_player_profile(profile: Dictionary) -> void:
	if _drinking and not profile.is_empty():
		_drinking = false
		_toast.show_toast(tr("You drink fresh water"))
		_audio.play("confirmation")
	if profile.is_empty():
		_set_render_origin(Vector3.ZERO)
		_controls.stop()
		_control_settings.hide()
		_connection_panel.show()
		_surface_direction = Vector3.ZERO
		_environment.show_region(Vector3.ZERO)
		_approach_elapsed = 0.0
		_sky.set_altitude(PLANET_RADIUS * 2000.0)
		var signed_out := not _player_profile.is_empty()
		_player_profile = {}
		if is_instance_valid(_sign_out_button):
			_sign_out_button.disabled = true
		_hud.clear_player()
		_survival.set_profile({})
		_social.stop()
		_story.stop()
		_dialogue.close()
		_quest_log.hide()
		_quest_stages = {}
		_quests_baseline = false
		_chat.clear()
		_friends.hide()
		if signed_out and not _connected_world.is_empty() and not _session.server_url.is_empty():
			_open_player()
		return
	if not _hud.set_player(profile):
		_session.configure(_server_url)
		_on_player_failed("Invalid player profile")
		return
	var changed: bool = _player_profile.is_empty() or profile.get("life", {}).get("uuid", "") != _player_profile.get("life", {}).get("uuid", "") or profile.username != _player_profile.username or profile.character != _player_profile.character
	var previous_level := 0
	if not _player_profile.is_empty() and profile.get("life", {}).get("uuid", "") == _player_profile.get("life", {}).get("uuid", ""):
		previous_level = int(_player_profile.get("stats", {}).get("level", 0))
	_player_profile = profile.duplicate(true)
	_story.player_name = str(profile.get("username", ""))
	_remember_position(profile.get("position"))
	if previous_level > 0 and int(profile.get("stats", {}).get("level", 0)) > previous_level:
		_toast.show_toast(tr("Level %s reached!") % int(profile.stats.level), 4.0)
		_audio.play("fanfare")
		_controls.glow(10.0)
	_survival.set_profile(profile)
	_sync_flag()
	if not _pending_tool.is_empty() and profile.get("equipment", {}).get("hand") == _pending_tool:
		_pending_tool = ""
		_work_with_tool()
	_sign_out_button.disabled = false
	if not _social.is_running() and not _session.token().is_empty():
		_social.start(_session.server_url, _session.token())
	if not _story.is_running() and not _session.token().is_empty():
		_story.start_session(_session.server_url, _session.token())
	if not changed:
		return
	_set_render_origin(Vector3.ZERO)
	_controls.stop()
	if not _start_approach(profile.get("position")):
		_surface_direction = Vector3.ZERO
		_approach_elapsed = 0.0
		_sky.set_altitude(PLANET_RADIUS * 2000.0)
		_connection_panel.show()
		_set_feedback("Player position unavailable")
	else:
		_connection_panel.hide()
		_set_feedback("")
	var settings := ConfigFile.new()
	settings.load(_settings_path)
	settings.set_value("player", "nickname", profile.username)
	settings.set_value("player", "character", profile.character)
	if settings.save(_settings_path) != OK:
		_set_feedback("Could not save player preference")
	_creator.set_selection(profile.character)
	_creator.password_input.clear()
	_creator.hide()
	_audio.play("confirmation")

func _on_player_failed(message: String) -> void:
	_drinking = false
	if _controls.active and not _game_ui_open():
		_toast.show_toast(tr(message))
	_creator.set_feedback(message)
	_set_feedback(message)
	if message == "Surface objects unavailable":
		_environment.objects_loaded = false
	if message in ["Movement unavailable", "Surface objects unavailable"]:
		_connection_panel.show()
		_controls.release_mouse()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_translations()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(_controls):
		_controls.release_mouse()

func _translated(message: String, arguments: Array) -> String:
	return tr(message) if arguments.is_empty() else tr(message) % arguments

func _update_translations() -> void:
	if not is_instance_valid(_feedback):
		return
	_language_label.text = tr("Language")
	_flag_check.text = tr("Show my flag to other players")
	_flag_check.tooltip_text = tr("Only a picture next to your name; the game is translated by your own language choice.")
	_address_label.text = tr("Server")
	_connect_button.text = tr("Connect")
	_disconnect_button.text = tr("Disconnect")
	_player_button.text = tr("Player")
	_sign_out_button.text = tr("Sign out")
	_history_test_button.text = tr("Test servers")
	_history_forget_button.text = tr("Forget server")
	_history_list.tooltip_text = tr("Servers you connected to")
	_refresh_history_list()
	_language_option.select(1 if TranslationServer.get_locale() == "cs" else 0)
	_server_input.tooltip_text = tr("Server URL")
	_language_option.tooltip_text = tr("Language")
	var arguments := _status_args
	if not _status_reason_key.is_empty():
		arguments = [_translated(_status_reason_key, _status_reason_args)]
	_status.text = _translated(_status_key, arguments)
	_feedback.text = tr(_feedback_key) if not _feedback_key.is_empty() else ""

func _set_status(message: String, arguments: Array = []) -> void:
	_status_key = message
	_status_args = arguments
	_status_reason_key = ""
	_status_reason_args = []
	_update_translations()

func _set_feedback(message: String) -> void:
	if not message.is_empty() and message != _feedback_key:
		_audio.play("error")
	_feedback_key = message
	_update_translations()

func _normalize_server_url(address: String) -> String:
	var url := address.strip_edges().trim_suffix("/")
	if url.is_empty():
		return ""
	if not url.contains("://"):
		url = "http://" + url
	var pattern := RegEx.new()
	pattern.compile("^https?://(\\[[0-9a-fA-F:]+\\]|[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?)(?::([0-9]{1,5}))?(/[^\\s?#]*)?$")
	var matched := pattern.search(url)
	if matched == null:
		return ""
	var host := matched.get_string(1)
	if host.begins_with("["):
		var ipv6 := host.trim_prefix("[").trim_suffix("]")
		var groups := ipv6.split(":", false)
		if not ipv6.is_valid_ip_address() or ipv6.contains(":::") or ipv6.count("::") > 1:
			return ""
		if (ipv6.begins_with(":") and not ipv6.begins_with("::")) or (ipv6.ends_with(":") and not ipv6.ends_with("::")):
			return ""
		if (ipv6.contains("::") and groups.size() >= 8) or (not ipv6.contains("::") and groups.size() != 8):
			return ""
		for group in groups:
			if group.length() > 4:
				return ""
	var port := matched.get_string(2)
	if not port.is_empty() and (port.to_int() < 1 or port.to_int() > 65535):
		return ""
	return url

func _on_server_submitted(_text: String) -> void:
	_connect_server()

func _connect_server(save_address := true) -> void:
	if save_address:
		_audio.play("click")
	var url := _normalize_server_url(_server_input.text)
	if url.is_empty():
		_set_feedback("Invalid server address")
		return
	_set_feedback("")
	_disconnect_server()
	_server_url = url
	_session.configure(url)
	_server_input.text = url
	_connection_enabled = true
	_disconnect_button.disabled = false
	_set_status("Connecting to %s", [_server_url])
	_request = HTTPRequest.new()
	_request.timeout = 4.0
	_request.request_completed.connect(_on_world_received.bind(_connection_generation))
	add_child(_request)
	if save_address:
		var settings := ConfigFile.new()
		settings.load(_settings_path)
		settings.set_value("connection", "server_url", _server_url)
		if settings.save(_settings_path) != OK:
			_set_feedback("Could not save server address")
	_refresh_world()

func _toggle_connection_panel() -> void:
	_connection_panel.visible = not _connection_panel.visible
	if _connection_panel.visible:
		_history.probe_all()
	else:
		_history.cancel()

func _history_label(entry: Dictionary) -> String:
	var name: String = entry.server_name if not entry.server_name.is_empty() else entry.url
	var result: Dictionary = _history.result_for(entry.url)
	var state: String = result.get("state", "")
	var parts: Array[String] = [name]
	match state:
		"online":
			parts.append(tr("%d ms") % int(roundf(result.latency_ms)))
		"unreachable":
			parts.append(tr("unreachable"))
		"changed":
			parts.append(tr("different world"))
	if _history.is_unencrypted(entry.url):
		parts.append(tr("unencrypted"))
	return " · ".join(parts)

func _refresh_history_list() -> void:
	if not is_instance_valid(_history_list):
		return
	var selected := ""
	var chosen := _history_list.get_selected_items()
	if not chosen.is_empty():
		selected = _history_list.get_item_metadata(chosen[0])
	_history_list.clear()
	for entry in _history.entries:
		var index: int = _history_list.add_item(_history_label(entry))
		_history_list.set_item_metadata(index, entry.url)
		_history_list.set_item_tooltip(index, entry.url)
		if entry.url == selected:
			_history_list.select(index)
	_history_forget_button.disabled = _history_list.get_selected_items().is_empty()
	_history_test_button.disabled = _history.entries.is_empty()

func _on_history_selected(index: int) -> void:
	_audio.play("click")
	_server_input.text = _history_list.get_item_metadata(index)
	_history_forget_button.disabled = false

func _on_history_test_pressed() -> void:
	_audio.play("click")
	_history.probe_all()

func _on_history_forget_pressed() -> void:
	var chosen := _history_list.get_selected_items()
	if chosen.is_empty():
		return
	_audio.play("click")
	_history.forget(_history_list.get_item_metadata(chosen[0]))

func _disconnect_server() -> void:
	if is_instance_valid(_environment_request):
		_environment_request.cancel_request()
		_environment_request.queue_free()
	_environment_request = null
	_world_metadata.clear()
	_sky.clear_solar()
	_environment.clear_world()
	if is_instance_valid(_terrain_request):
		_terrain_request.cancel_request()
		_terrain_request.queue_free()
	_terrain_request = null
	_terrain_loaded = false
	_terrain_material.set_shader_parameter("has_heightmap", false)
	_water_material.set_shader_parameter("has_heightmap", false)
	get_node("Ocean").hide()
	_connected_world = ""
	_startup_pending = true
	_creator.password_input.clear()
	_creator.hide()
	_player_button.disabled = true
	_session.configure("")
	_hud.clear_player()
	_connection_generation += 1
	_connection_enabled = false
	_reconnect.stop()
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null
	_request_pending = false
	_connected_world = ""
	_disconnect_button.disabled = true
	_system_messages.apply([])
	_disk_cover.dismiss()
	_set_status("Disconnected")

func _refresh_world() -> void:
	if not _connection_enabled or _request_pending:
		return
	_request_pending = true
	var error := _request.request(_server_url + "/world")
	if error != OK:
		_request_pending = false
		_show_disconnected("request error %s", [error])

func _show_disconnected(reason: String, arguments: Array = []) -> void:
	_status_key = "Server unavailable (%s)"
	_status_args = []
	_status_reason_key = reason
	_status_reason_args = arguments
	_update_translations()
	_connected_world = ""
	_system_messages.server_unreachable()
	if _connection_enabled:
		_reconnect.start()

func _on_world_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if generation != _connection_generation or not _connection_enabled:
		return
	_request_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_show_disconnected("network %s / HTTP %s", [result, response_code])
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		_show_disconnected("invalid response")
		return
	var world: Dictionary = json.data
	if not world.get("server_name") is String or not world.get("ruleset") is String:
		_show_disconnected("invalid world identity")
		return
	if not _sky.apply_atmosphere(world.get("atmosphere", {})):
		_show_disconnected("invalid atmosphere")
		return
	if world.has("solar") and not _sky.apply_solar(world.solar):
		_show_disconnected("invalid atmosphere")
		return
	if not world.has("solar"):
		_sky.clear_solar()
	_system_messages.apply(world.get("messages", []))
	_set_status("%s | %s | seed %s", [world.server_name, world.ruleset, world.get("seed", "-")])
	_world_metadata = world.duplicate(true)
	_load_terrain(world)
	if _terrain_loaded:
		_load_environment()
	_player_button.disabled = false
	_reconnect.start()
	if _connected_world != world.server_name:
		_audio.play("confirmation")
		_connected_world = world.server_name
		_disk_cover.present(_server_url, world.get("datadisks", []))
		if _history.record_connection(_server_url, world) != OK:
			_set_feedback("Could not save server history")
		print("Connected to Ishtaria server %s: world %s, ruleset %s, seed %s" % [_server_url, world.server_name, world.ruleset, world.get("seed", "-")])
	if _startup_pending and _player_profile.is_empty():
		_open_player()

func _load_terrain(world: Dictionary) -> void:
	var size: Variant = world.get("face_size")
	if _terrain_loaded or is_instance_valid(_terrain_request) or not (size is int or size is float):
		return
	if size < 1 or size > 1024 or float(size) != floorf(float(size)):
		return
	_terrain_request = HTTPRequest.new()
	_terrain_request.timeout = 4.0
	_terrain_request.max_redirects = 0
	_terrain_request.body_size_limit = 16 * 1024 * 1024
	_terrain_request.request_completed.connect(_on_terrain_received.bind(_connection_generation, int(size)))
	add_child(_terrain_request)
	if _terrain_request.request(_server_url + "/world/heightmap.png") != OK:
		_terrain_request.queue_free()
		_terrain_request = null

func _on_terrain_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, face_size: int) -> void:
	if generation != _connection_generation or not _connection_enabled:
		return
	if is_instance_valid(_terrain_request):
		_terrain_request.queue_free()
	_terrain_request = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	if body.size() < 33 or body.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return
	var header := StreamPeerBuffer.new()
	header.big_endian = true
	header.data_array = body
	header.seek(8)
	if header.get_u32() != 13 or header.get_u32() != 0x49484452 or header.get_u32() != face_size * 6 or header.get_u32() != face_size:
		return
	var image := Image.new()
	if image.load_png_from_buffer(body) != OK or image.get_width() != face_size * 6 or image.get_height() != face_size:
		return
	var texture := ImageTexture.create_from_image(image)
	for material in [_terrain_material, _water_material]:
		material.set_shader_parameter("heightmap", texture)
		material.set_shader_parameter("has_heightmap", true)
	_environment.heightmap = image
	get_node("Ocean").show()
	_terrain_loaded = true
	_load_environment()

func _load_environment() -> void:
	if is_instance_valid(_environment_request) or not _environment.environment.is_empty():
		return
	if not _world_metadata.get("sha256") is String or not _world_metadata.get("seed") is String:
		return
	_environment_request = HTTPRequest.new()
	_environment_request.timeout = 8.0
	_environment_request.max_redirects = 0
	_environment_request.body_size_limit = 2 * 1024 * 1024
	_environment_request.request_completed.connect(_on_environment_received.bind(_connection_generation, _world_metadata.sha256, _world_metadata.seed))
	add_child(_environment_request)
	if _environment_request.request(_server_url + "/world/environment") != OK:
		_environment_request.queue_free()
		_environment_request = null

func _on_environment_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, sha256: String, seed: String) -> void:
	if generation != _connection_generation or not _connection_enabled:
		return
	if is_instance_valid(_environment_request):
		_environment_request.queue_free()
	_environment_request = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	if _world_metadata.get("sha256") != sha256 or _world_metadata.get("seed") != seed:
		return
	_environment.server_url = _server_url
	if _environment.apply_environment(JSON.parse_string(body.get_string_from_utf8()), sha256, seed):
		_environment.show_region(_surface_direction)

func _start_approach(position: Variant) -> bool:
	if not position is Dictionary:
		return false
	for axis in ["x", "y", "z"]:
		var value: Variant = position.get(axis)
		if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value)) > 1e12:
			return false
	var point := Vector3(position.x, position.y, position.z)
	if point.length_squared() < 1.0:
		return false
	_set_render_origin(Vector3.ZERO)
	_approach_start = _camera.position
	if _approach_start.length_squared() < 1.0:
		_approach_start = Vector3(0.0, 0.3, 1.0) * PLANET_RADIUS * 3.0
	_surface_direction = point.normalized()
	_approach_up = _camera.basis.y
	_approach_rotation = Quaternion(_approach_start.normalized(), _surface_direction)
	_approach_elapsed = 0.0
	_environment.show_region(_surface_direction)
	if not _player_profile.is_empty():
		_controls.start(_player_profile.character, Vector3(position.x / 1000.0, position.y / 1000.0, position.z / 1000.0), position)
	return true

func _remember_position(position: Variant) -> void:
	if position is Dictionary and (position.get("x") is float or position.get("x") is int) and (position.get("y") is float or position.get("y") is int) and (position.get("z") is float or position.get("z") is int):
		_player_metres = Vector3(position.x, position.y, position.z)

func _item_name(id: String) -> String:
	for item: Variant in _player_profile.get("inventory", {}).get("items", []):
		if item is Dictionary and item.get("item_id") == id:
			return tr(item.get("name", id))
	return tr(id.capitalize().replace("_", " "))

func _wear_text(reply: Dictionary, id: String) -> String:
	var wear: Variant = reply.get("wear")
	if wear is Dictionary and wear.broken:
		_audio.play("error")
		return "  ·  " + tr("%s broke!") % _item_name(id)
	return ""

## The left mouse button acts with the item in the dominant hand: a swing of the axe or sword,
## a kick of the pickaxe.
func _primary_action() -> void:
	var hand: Variant = _player_profile.get("equipment", {}).get("hand")
	if not hand is String:
		_toast.show_toast(tr("Nothing in hand"), 1.2)
		return
	_controls.swing()
	if hand == "sword":
		_toast.show_toast(tr("Nothing to hit"), 1.0)
		return
	_harvest_nearby()

## "Use" in the inventory: put the tool in hand if it is not, then work with it on whatever is in reach.
func _use_tool(item_id: String) -> void:
	_survival.hide()
	_controls.capture_mouse()
	if _player_profile.get("equipment", {}).get("hand") == item_id:
		_pending_tool = ""
		_work_with_tool()
	else:
		_pending_tool = item_id
		_session.equip(item_id)

func _work_with_tool() -> void:
	_controls.swing()
	_harvest_nearby()

## The right mouse button raises the shield in the other hand while it is held.
func _secondary_action_started() -> void:
	if not _player_profile.get("equipment", {}).get("offhand") is String:
		_toast.show_toast(tr("No shield in hand"), 1.2)
		return
	_blocking = true
	_block_renew = 0.0

func _on_blocked(reply: Dictionary) -> void:
	var offhand: Variant = _player_profile.get("equipment", {}).get("offhand")
	var wear: Variant = reply.get("wear")
	if wear is Dictionary and wear.broken:
		_blocking = false
		_audio.play("error")
		_toast.show_toast(tr("%s broke!") % _item_name(str(offhand)), 2.0)
	elif wear is Dictionary:
		_audio.play("click")

## E talks to a character within reach, otherwise gathers from the nearest tree or rock and,
## with nothing to gather, drinks from fresh water within reach (the server decides).
func _interact() -> void:
	if _player_metres != Vector3.ZERO and not _story.is_running():
		_harvest_nearby()
		return
	var npc: Dictionary = _environment.nearest_npc(_player_metres, TALK_REACH_M) if _player_metres != Vector3.ZERO else {}
	if npc.is_empty():
		_harvest_nearby()
		return
	_controls.release_mouse()
	_story.start(npc.id)

func _on_dialogue_changed(reply: Dictionary) -> void:
	_dialogue.show_reply(reply)
	# Choices can pay or reward gold and items: refresh the HUD and the inventory.
	_session.refresh()
	if reply.open:
		_controls.release_mouse()

## A new quest or a new stage: a short note on screen; the log shows the details.
func _on_quests_changed(quests: Array) -> void:
	_quest_log.set_quests(quests)
	var first_report := not _quests_baseline
	_quests_baseline = true
	for quest: Dictionary in quests:
		if not first_report and _quest_stages.get(quest.quest) != quest.stage:
			_toast.show_toast(tr("Quest updated: %s") % _story.text(quest.title_key), 4.0)
			_audio.play("confirmation")
		_quest_stages[quest.quest] = quest.stage

func _on_dialogue_closed() -> void:
	_story.leave()
	_session.refresh()

func _on_story_failed(message: String) -> void:
	_toast.show_toast(tr(message))
	_audio.play("error")

func _harvest_nearby() -> void:
	if _player_metres == Vector3.ZERO or _session.busy:
		return
	var target: Dictionary = _environment.nearest_harvestable(_player_metres, HARVEST_REACH_M)
	if target.is_empty():
		_drinking = true
		_session.drink()
		return
	_session.harvest(target.id)

func _update_prompt() -> void:
	var text := ""
	if _controls.active and not _game_ui_open() and _environment.objects_loaded and _player_metres != Vector3.ZERO:
		var npc: Dictionary = _environment.nearest_npc(_player_metres, TALK_REACH_M) if _story.is_running() else {}
		var target: Dictionary = _environment.nearest_harvestable(_player_metres, HARVEST_REACH_M)
		if not npc.is_empty():
			text = tr("E: Talk to %s") % _story.text(npc.name_key)
		elif not target.is_empty():
			text = tr("E: Fell tree") if target.harvest.kind == "tree" else tr("E: Mine rock")
	_toast.set_prompt(text)

func _on_harvested(reply: Dictionary) -> void:
	if reply.state == "depleted":
		var parts: Array[String] = []
		for item: Dictionary in reply.items:
			parts.append("%s x %s" % [tr(item.name), item.quantity])
		_toast.show_toast(tr("Harvested: %s") % ", ".join(parts) + _xp_text(reply) + _wear_text(reply, str(reply.get("tool", ""))))
		_audio.play("confirmation")
		_environment.refresh_objects()
	else:
		_toast.show_toast(tr("Hit %s / %s") % [int(reply.hits), int(reply.hits_required)] + _xp_text(reply) + _wear_text(reply, str(reply.get("tool", ""))), 1.2)
		_audio.play("click")

func _xp_text(reply: Dictionary) -> String:
	var xp: Variant = reply.get("xp")
	return "  ·  " + tr("+%s XP") % int(xp) if (xp is float or xp is int) and xp > 0 else ""

func _on_crafted() -> void:
	_survival.set_feedback("Crafted")
	_audio.play("confirmation")

## Background music of the place the player is in, with the level the settings ask for.
func _update_area_music(delta: float) -> void:
	_area_music.volume = _dialogue.music_volume
	_area_elapsed += delta
	if _area_elapsed < 0.25:
		return
	_area_elapsed = 0.0
	_area_music.suppressed = _dialogue.has_own_music()
	if _player_metres == Vector3.ZERO or not _story.is_running():
		_area_music.set_target({}, 0.0)
		return
	var found: Dictionary = _environment.area_at(_player_metres)
	_area_music.set_target(found.get("area", {}), found.get("level", 0.0))

func _on_player_position(position: Dictionary, moving: bool) -> void:
	_remember_position(position)
	if _controls.active and _controls.apply_position(position, moving):
		_surface_direction = _controls.direction
		if _environment.target.distance_to(_surface_direction) * PLANET_RADIUS > 0.10:
			_environment.show_region(_surface_direction)

func _set_render_origin(origin: Vector3) -> void:
	var adjustment: Vector3 = _controls.origin - origin
	_camera.position += adjustment
	if is_instance_valid(_controls.avatar):
		_controls.avatar.position += adjustment
		_controls._position_target += adjustment
	_controls.origin = origin
	for node in [get_node("Planet"), get_node("Ocean"), _environment]:
		node.position = -origin
	_environment.set_render_origin(_controls._anchor_metres if origin != Vector3.ZERO else [])

func _game_ui_open() -> bool:
	return _connection_panel.visible or _creator.visible or _survival.visible or _control_settings.visible or _portals.visible or _friends.visible or _escape_menu.visible or _dialogue.visible or _quest_log.visible

func _open_friends() -> void:
	_escape_menu.close()
	_controls.release_mouse()
	_friends.open()

## A friend reached a new level: a line in the chat part of the screen for ten seconds.
func _on_friend_event(event: Dictionary) -> void:
	if event.kind == "level_up":
		_chat.add_line(tr("%s reached level %s!") % [event.subject, int(event.level)], Color(1.0, 0.88, 0.45))
		_audio.play("confirmation")

func _open_settings_from_menu() -> void:
	_control_settings.recapture = false
	_control_settings.open()

## ESC closes the panel in front, or opens the menu; pressing it again returns to the game.
func _escape_pressed() -> void:
	_controls.release_mouse()
	if _control_settings.visible:
		return # the settings dialog closes itself
	if _escape_menu.visible:
		_escape_menu.close()
	elif _survival.visible:
		_survival.hide()
	elif _portals.visible:
		_portals.hide()
	elif _friends.visible:
		_friends.hide()
	elif _dialogue.visible:
		_dialogue.close()
	elif _quest_log.visible:
		_quest_log.hide()
	else:
		_escape_menu.open(_server_url if _connection_enabled else "")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not event.echo:
			_escape_pressed()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event.physical_keycode == KEY_I or event.keycode == KEY_I) and _controls.active and not _game_ui_open():
		if event.pressed and not event.echo:
			_controls.release_mouse()
			_survival.open()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event.physical_keycode == KEY_J or event.keycode == KEY_J) and _controls.active and not _game_ui_open() and _story.is_running():
		if event.pressed and not event.echo:
			_controls.release_mouse()
			_story.load_quests()
			_quest_log.open()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event.physical_keycode == KEY_F or event.keycode == KEY_F) and _controls.active and not _game_ui_open() and not _session.token().is_empty():
		if event.pressed and not event.echo:
			_controls.release_mouse()
			_friends.open()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event.physical_keycode == KEY_P or event.keycode == KEY_P) and _controls.active and not _game_ui_open():
		if event.pressed and not event.echo:
			_controls.release_mouse()
			_portals.open()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event.physical_keycode == KEY_E or event.keycode == KEY_E) and _controls.active and not _game_ui_open() and _environment.objects_loaded and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.pressed and not event.echo:
			_interact()
		get_viewport().set_input_as_handled()
	elif _controls.is_jump_event(event) and _controls.active and not _game_ui_open() and _environment.objects_loaded and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.pressed and not event.echo:
			_controls.queue_jump()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _controls.active or _game_ui_open() or not _environment.objects_loaded:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_controls.look(event.relative)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_blocking = false
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				_controls.capture_mouse()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				_primary_action()
			else:
				_secondary_action_started()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_controls.zoom(-event.factor)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_controls.zoom(event.factor)

func _process(delta: float) -> void:
	_environment.set_night(1.0 - _sky.daylight)
	if _blocking:
		if not _controls.active or _game_ui_open() or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_blocking = false
		else:
			_block_renew -= delta
			if _block_renew <= 0.0 and not _session.busy:
				_block_renew = 1.5
				_session.block()
	_portal_poll += delta
	if _portal_poll >= 10.0:
		_portal_poll = 0.0
		if _portals.visible and not _session.busy:
			_session.fetch_portals()
	if _controls.active:
		if _game_ui_open() or not _environment.objects_loaded:
			_controls.release_mouse()
		_controls.update_camera(_environment, _hud.panel)
		_sky.set_altitude(((_camera.position + _controls.origin).length() - PLANET_RADIUS) * 1000.0, true)
		_sky.set_observer(_controls.direction)
		_update_area_music(delta)
		_prompt_elapsed += delta
		if _prompt_elapsed >= 0.25:
			_prompt_elapsed = 0.0
			_update_prompt()
		_move_elapsed += delta
		if _move_elapsed >= 0.1:
			_move_elapsed = 0.0
			if _session.move(_controls.jump_direction if _controls.jump_pending else _controls.intent(), _controls.jump_pending, _controls.jump_running if _controls.jump_pending else _controls.running()):
				_controls.jump_pending = false
		return
	_area_music.set_target({}, 0.0)
	if _surface_direction == Vector3.ZERO:
		_camera.near = 1.0
		_camera.far = PLANET_RADIUS * 10.0
		_yaw += delta * 0.1
		_camera.position = Vector3(sin(_yaw), 0.3, cos(_yaw)) * PLANET_RADIUS * 3.0
		_camera.look_at(Vector3.ZERO)
		_sky.set_altitude(PLANET_RADIUS * 2000.0)
		_sky.set_observer(_camera.position.normalized())
		return
	_approach_elapsed = minf(_approach_elapsed + delta, APPROACH_SECONDS)
	var progress := smoothstep(0.0, APPROACH_SECONDS, _approach_elapsed)
	var rotation := Quaternion.IDENTITY.slerp(_approach_rotation, progress)
	var surface_height := maxf(_environment.elevation(_surface_direction), 0.0)
	if not _environment.environment.is_empty():
		var index: int = _environment.environment_index(_surface_direction)
		surface_height = maxf(surface_height, _environment.environment.water_m[index] / 1000.0)
	var distance := lerpf(_approach_start.length(), PLANET_RADIUS + surface_height + SURFACE_ALTITUDE_M / 1000.0, progress)
	var direction := _surface_direction if _approach_elapsed == APPROACH_SECONDS else rotation * _approach_start.normalized()
	_camera.position = direction * distance
	_camera.near = maxf(0.001, (distance - PLANET_RADIUS - surface_height) * 0.01)
	_camera.far = maxf(50.0, (distance - PLANET_RADIUS) * 4.0)
	_camera.look_at(Vector3.ZERO, rotation * _approach_up)
	_sky.set_altitude((distance - PLANET_RADIUS) * 1000.0)
	_sky.set_observer(direction)
	if _approach_elapsed == APPROACH_SECONDS and _terrain_loaded and not _environment.environment.is_empty() and _environment.objects_loaded and is_instance_valid(_controls.avatar):
		_set_render_origin(_controls.avatar.position)
		_controls.active = true
		_controls.capture_mouse()
