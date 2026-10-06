extends SceneTree

const CATALOG := preload("res://scripts/character_catalog.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const SESSION := preload("res://scripts/player_session.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)

func _run() -> void:
	_check(not CATALOG.is_valid("../../unexpected"), "Unknown character path is rejected")
	for pack in CATALOG.PACKS:
		for entry in CATALOG.CHARACTERS[pack]:
			var character: String = pack + "/" + entry[0]
			var model := CATALOG.create_model(character)
			root.add_child(model)
			var meshes := model.find_children("*", "MeshInstance3D", true, false)
			_check(not meshes.is_empty(), character + " has an actual mesh")
			for mesh in meshes:
				if pack == "quaternius":
					# The glTF characters carry their own materials instead of a Kenney skin.
					_check(mesh.mesh.get_surface_count() > 0 and mesh.mesh.surface_get_material(0) != null, character + " has its own material")
				else:
					_check(mesh.material_override.albedo_texture != null, character + " has its selected skin")
			var player: AnimationPlayer = model.get_node_or_null("CharacterAnimation")
			_check(player != null and player.is_playing() and player.get_animation("idle").get_track_count() > 0, character + " has a bound idle animation")
			if player != null:
				var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
				player.advance(0.2)
				await process_frame
				var poses: Array = []
				for bone in skeleton.get_bone_count():
					poses.append(skeleton.get_bone_pose(bone))
				player.advance(0.5)
				await process_frame
				var changed := false
				for bone in skeleton.get_bone_count():
					changed = changed or poses[bone] != skeleton.get_bone_pose(bone)
				_check(changed, character + " animation moves bones")
			model.free()
	await _test_creation()
	await process_frame
	await process_frame
	print("Character creation: %s checks, %s failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _world_ready(client: Node) -> void:
	client._connection_enabled = true
	client._on_world_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"server_name": "ishtaria.example.org", "ruleset": "core-rules@1.0", "seed": 42}).to_utf8_buffer(), client._connection_generation)
	client._reconnect.stop()

func _drag_preview(creator: Node, delta: Vector2) -> void:
	var start: Vector2 = creator._preview.get_global_rect().get_center()
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	button.position = start
	button.global_position = start
	root.push_input(button, true)
	var motion := InputEventMouseMotion.new()
	motion.position = start + delta
	motion.global_position = motion.position
	motion.relative = delta
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	button = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.position = motion.position
	button.global_position = motion.position
	root.push_input(button, true)
	await process_frame

func _test_creation() -> void:
	var path := "user://character-test-%s.cfg" % Time.get_ticks_usec()
	var client := MAIN_SCENE.instantiate()
	client._settings_path = path
	root.add_child(client)
	client._audio.set_enabled(false)
	client._disconnect_server()
	await process_frame
	_check(not client._creator.visible and client._player_button.disabled, "First launch waits for a server before showing character creation")
	client._open_player()
	_check(not client._creator.visible, "Offline Player action cannot open an unusable account form")
	_world_ready(client)
	_check(client._creator.visible and client._creator.mode.current_tab == 0, "First successful connection opens new character creation")
	_world_ready(client)
	_check(client._creator.visible and client._creator.mode.current_tab == 0, "World refresh does not restart the creation flow")
	_check(client._hud.gold_label.text == "Gold -", "Guest has no fabricated gold")
	client._creator.packs.select(2)
	client._creator.packs.item_selected.emit(2)
	var survivors: Array = CATALOG.selectable("survivors")
	_check(survivors.size() == 3 and not survivors.any(func(entry): return entry[0] == "survivorMaleB"), "NPC looks are not offered to a new character")
	client._creator.characters.select(1)
	client._creator.characters.item_selected.emit(1)
	_check(client._creator.character == "survivors/" + survivors[1][0], "Pack and appearance choose the actual character ID")
	var offered := 0
	for pack in CATALOG.PACKS:
		offered += CATALOG.selectable(pack).size()
	_check(offered == 22, "All looks not worn by NPCs are offered (%d)" % offered)
	client._creator.packs.select(3)
	client._creator.packs.item_selected.emit(3)
	_check(client._creator.characters.item_count == 14 and client._creator.character.begins_with("quaternius/"), "The Quaternius characters are selectable")
	var chosen: String = client._creator.character
	_check(client._creator.model != null, "Selected model is instantiated in the preview")
	client._creator.rotation_slider.value = 90
	_check(is_equal_approx(client._creator.model.rotation_degrees.y, 90), "Rotation slider rotates the preview")
	var preview_motion := InputEventMouseMotion.new()
	preview_motion.relative = Vector2(40, 12)
	preview_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	client._creator._preview.gui_input.emit(preview_motion)
	_check(is_equal_approx(client._creator.rotation_slider.value, 90), "A drag must begin in the preview before it rotates the model")
	var preview_button := InputEventMouseButton.new()
	preview_button.button_index = MOUSE_BUTTON_LEFT
	preview_button.pressed = true
	client._creator._preview.gui_input.emit(preview_button)
	client._creator._preview.gui_input.emit(preview_motion)
	_check(is_equal_approx(client._creator.rotation_slider.value, 110) and is_equal_approx(client._creator.model.rotation_degrees.y, 110), "Left drag rotates the preview and synchronizes the slider")
	preview_motion.relative = Vector2(-800, 0)
	client._creator._preview.gui_input.emit(preview_motion)
	_check(is_equal_approx(client._creator.model.rotation_degrees.y, 70), "Mouse rotation wraps through a full turn without stopping at slider limits")
	preview_button.pressed = false
	client._creator._preview.gui_input.emit(preview_button)
	client._creator._preview.gui_input.emit(preview_motion)
	_check(is_equal_approx(client._creator.model.rotation_degrees.y, 70), "Releasing the button stops rotation")
	preview_button.button_index = MOUSE_BUTTON_RIGHT
	preview_button.pressed = true
	client._creator._preview.gui_input.emit(preview_button)
	client._creator._preview.gui_input.emit(preview_motion)
	_check(is_equal_approx(client._creator.model.rotation_degrees.y, 70), "Right clicks do not start preview rotation")
	preview_button.button_index = MOUSE_BUTTON_LEFT
	client._creator._preview.gui_input.emit(preview_button)
	client._creator.hide()
	client._creator.show()
	client._creator._preview.gui_input.emit(preview_motion)
	_check(is_equal_approx(client._creator.model.rotation_degrees.y, 70), "Hiding the creator clears a pending drag")
	client._creator.mode.current_tab = 1
	client._creator._preview.gui_input.emit(preview_button)
	client._creator._preview.gui_input.emit(preview_motion)
	_check(is_equal_approx(client._creator.model.rotation_degrees.y, 70), "Sign-in preview does not change character rotation")
	client._creator.mode.current_tab = 0
	client._creator.language_choice.select(1)
	client._creator.language_choice.item_selected.emit(1)
	_check(client._creator.submit_button.text == "Vytvořit hráče" and TranslationServer.get_locale() == "cs", "First-run language selection changes local UI")
	_check(client._creator.character == chosen, "Language selection preserves character")
	_check(client._hud.inventory_button.icon != null and client._hud.inventory_button.text.is_empty() and client._hud.inventory_button.tooltip_text == "Inventář", "Kenney inventory icon has a translated tooltip")
	_check(client._hud.sound_checkbox.icon.resource_path.ends_with("game-icons/audioOn.png") and client._hud.sound_checkbox.toggle_mode, "Sound toggle uses the requested Kenney game icon")
	client._hud.sound_checkbox.button_pressed = false
	_check(not client._hud.sound_enabled and client._hud.sound_checkbox.icon.resource_path.ends_with("game-icons/audioOff.png"), "Muted sound uses the matching icon and toggle state")
	client._hud.sound_checkbox.button_pressed = true
	_check(client._hud.sound_enabled and client._hud.sound_checkbox.icon.resource_path.ends_with("game-icons/audioOn.png"), "Sound can be restored with the compact toggle")
	var profile := {"username": "PlayerOne", "character": "survivors/survivorMaleB", "stats": {"gold": "100", "health": 100, "stamina": 100, "food": 100, "water": 100, "level": 1, "experience": 0}}
	profile.position = {"x": 6371000.0, "y": 0.0, "z": 0.0}
	client._on_player_profile(profile)
	client.set_process(false)
	var orbit_distance: float = client._camera.position.length()
	client._process(1.0)
	_check(client._camera.position.length() < orbit_distance and client._surface_direction.is_equal_approx(Vector3.RIGHT), "Login starts approaching the authoritative surface location")
	_check(not client._connection_panel.visible, "Successful approach hides server controls so the planet remains visible")
	client._hud.connection_button.pressed.emit()
	_check(client._connection_panel.visible and client._surface_direction != Vector3.ZERO, "Kenney settings icon opens server controls without interrupting approach")
	client._hud.connection_button.pressed.emit()
	var elapsed: float = client._approach_elapsed
	client._on_player_profile(profile)
	_check(client._approach_elapsed == elapsed, "Profile refresh does not restart the approach")
	client._process(10.0)
	_check(client._camera.position.is_equal_approx(Vector3.RIGHT * (client.PLANET_RADIUS + client.SURFACE_ALTITUDE_M / 1000.0)), "Approach stops above the stored position")
	_check(client._sky.surface_blend > 0.8, "Approach transitions from the space sky to the server's surface sky")
	var arrived: Vector3 = client._camera.position
	client._process(10.0)
	_check(client._camera.position.is_equal_approx(arrived), "Arrived camera stays over the player instead of orbiting")
	for height in [6371000.0, -6371000.0]:
		_check(client._start_approach({"x": 0.0, "y": height, "z": 0.0}), "Polar location is accepted")
		client._process(10.0)
		_check(client._camera.transform.is_finite() and (-client._camera.basis.z).dot(-client._surface_direction) > 0.99, "Polar and antipodal approaches retain a valid camera orientation")
	_check(not client._start_approach({"x": 0, "y": 0, "z": 0}) and not client._start_approach({"x": "6371000", "y": 0, "z": 0}) and not client._start_approach({"x": NAN, "y": 0, "z": 0}), "Missing, zero and nonnumeric positions cannot produce a fabricated landing")
	var unavailable_profile := profile.duplicate(true)
	unavailable_profile.life = {"uuid": "581fae1a-d3e1-4378-a32d-b18e5bf0fb12"}
	unavailable_profile.position = null
	client._on_player_profile(unavailable_profile)
	_check(client._surface_direction == Vector3.ZERO and client._connection_panel.visible, "Another character without a position cannot inherit the previous approach target")
	client._on_player_profile(profile)
	client._process(10.0)
	client.set_process(true)
	_check(not client._creator.visible and client._hud.player_name.text == "PlayerOne" and client._hud.gold_label.text == "Zlato 100", "Server profile completes creation and populates HUD")
	var settings := ConfigFile.new()
	_check(settings.load(path) == OK and settings.get_value("player", "nickname") == "PlayerOne" and settings.get_value("player", "character") == profile.character, "Successful identity is saved locally")
	_check(not settings.has_section_key("player", "password") and not settings.has_section_key("player", "token") and not settings.has_section_key("player", "gold"), "Client preferences contain no secrets or authoritative gold")
	client._open_player()
	profile.stats.gold = "73"
	client._on_player_profile(profile)
	_check(client._creator.visible and client._hud.gold_label.text == "Zlato 73", "Profile refresh updates gold without closing an open form")
	profile.stats.gold = "9223372036854775807"
	_check(client._hud.set_player(profile) and client._hud.gold_label.text == "Zlato 9223372036854775807", "Gold is displayed exactly without JSON float rounding")
	profile.stats.gold = "9223372036854775808"
	_check(not client._hud.set_player(profile), "Out-of-range gold is rejected")
	profile.stats.gold = "100"
	profile.life = {"uuid": "1c8f7318-6dba-440e-8c8c-134a3811840c", "alive": true, "age_days": "12"}
	_check(client._hud.set_player(profile) and client._hud.age_label.text == "Věk: 12 dní", "HUD displays authoritative age in completed days")
	profile.life.age_days = "9223372036854775808"
	_check(not client._hud.set_player(profile), "HUD rejects out-of-range age")
	profile.life.age_days = "12"
	profile.inventory = {"capacity": 100, "used": 3, "items": [{"item_id": "apple", "name": "Apple", "quantity": "3", "calories": 95}, {"item_id": "bag", "name": "Bag", "quantity": "1", "calories": 0}]}
	client._survival.set_profile(profile)
	client._survival.open()
	_check(client._survival.summary.text == "Inventář 3 / 100", "Inventory capacity is displayed from the server in Czech")
	var eaten: Array = []
	client._survival.eat_requested.connect(func(id: String) -> void: eaten.append(id))
	var eat_buttons: Array[Node] = client._survival.inventory_list.find_children("Eat", "Button", true, false)
	_check(eat_buttons.size() == 1 and eat_buttons[0].text == "Sníst", "Only edible items offer Eat")
	eat_buttons[0].pressed.emit()
	_check(eaten == ["apple"], "Eat sends an item intention rather than calories or a new balance")
	client._survival.set_busy(true)
	_check(eat_buttons[0].disabled, "Pending actions cannot be repeated")
	client._survival.set_busy(false)
	profile.life.alive = false
	client._survival.set_profile(profile)
	_check(client._survival.inventory_list.find_children("Eat", "Button", true, false)[0].disabled, "Dead players cannot eat")
	profile.life.alive = true
	client._survival.set_profile(profile)
	client._survival.hide()
	client._session.configure("http://example.org")
	client._session.submit("PlayerOne", "test-password", profile.character, true)
	_check(not client._session.busy and client._creator.feedback.text.contains("HTTPS"), "Remote plaintext credentials are never sent")
	client._session.configure("http://127.0.0.1:17400")
	client._session.submit("..", "test-password", profile.character, true)
	_check(not client._session.busy and client._creator.feedback.text == "Neplatná přezdívka", "Invalid nickname is rejected before sending")
	client._session.submit("PlayerOne", "short", profile.character, true)
	_check(not client._session.busy and client._creator.feedback.text == "Neplatné heslo", "Invalid password is rejected before sending")
	client._session.submit("PlayerOne", "", profile.character, true)
	_check(client._session.busy, "Empty password is allowed through client validation")
	client._session.configure("http://127.0.0.1:17400")
	var old_generation: int = client._session._generation
	client._session.configure("http://localhost:17400")
	client._session._received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"token": "a".repeat(64), "player": profile}).to_utf8_buffer(), old_generation, null, "/players/login")
	_check(client._player_profile.is_empty(), "Old server response cannot restore a stale player")
	_check(client._surface_direction == Vector3.ZERO and client._sky.surface_blend == 0.0, "Clearing the session cancels approach and returns to space")
	client._session._received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(profile).to_utf8_buffer(), client._session._generation, null, "/players/me/eat")
	_check(client._player_profile.get("inventory", {}).get("capacity") == 100 and client._session._token.is_empty(), "Eating returns a profile without replacing the session token")
	var notice := {"name": "DeceasedPlayer", "born_at": "2000-01-02T03:04:05.000006Z", "lived_days": "12", "lifetime_gold": "9223372036854775807", "friends_count": "2"}
	_check(SESSION.valid_obituary(notice) and not SESSION.valid_obituary({"name": "DeceasedPlayer", "lived_days": 12, "lifetime_gold": "100", "friends_count": "0"}), "Obituary statistics use exact decimal strings")
	var invalid_birth := notice.duplicate()
	invalid_birth.born_at = "2000-02-31T03:04:05.000006Z"
	_check(not SESSION.valid_obituary(invalid_birth), "Invalid calendar birth date is rejected")
	var overflow := notice.duplicate()
	overflow.lifetime_gold = "9223372036854775808"
	_check(not SESSION.valid_obituary(overflow), "Out-of-range obituary wealth is rejected")
	var notice_body := JSON.stringify({"obituary": notice}).to_utf8_buffer()
	client._session._received(HTTPRequest.RESULT_SUCCESS, 410, PackedStringArray(), notice_body, old_generation, null, "/players/login")
	_check(client._survival._obituary.is_empty(), "Stale obituary cannot overwrite the selected server")
	client._session._token = "a".repeat(64)
	client._session._received(HTTPRequest.RESULT_SUCCESS, 410, PackedStringArray(), notice_body, client._session._generation, null, "/players/login")
	_check(client._player_profile.is_empty() and client._session._token.is_empty() and client._session._timer.is_stopped(), "Obituary never authenticates the deceased player")
	_check(client._survival.visible and not client._creator.visible and client._creator.password_input.text.is_empty(), "Dead-character login opens an obituary and clears credentials")
	_check(client._survival.summary.text == "Parte" and client._survival.grave_list.get_node("MemorialName").text == notice.name, "Obituary displays the deceased name in Czech")
	_check(client._survival.grave_list.get_node("born_at").text == "Narození: 2000-01-02 03:04:05.000006 UTC", "Obituary displays the immutable birth timestamp")
	_check(client._survival.grave_list.get_node("lived_days").text == "Prožité dny: 12" and client._survival.grave_list.get_node("friends_count").text == "Přátelé: 2", "Obituary displays lived days and friends")
	_check(client._survival.grave_list.get_node("lifetime_gold").text.contains("9223372036854775807"), "Lifetime wealth is displayed without float rounding")
	_check(client._survival.find_children("*", "TabContainer", true, false).is_empty(), "Inventory has no global Graves tab")
	client._survival.grave_list.get_node("NewCharacter").pressed.emit()
	_check(client._creator.visible and client._creator.mode.current_tab == 0 and client._creator.nickname_input.text.is_empty() and client._creator.password_input.text.is_empty(), "New character starts a fresh registration rather than reviving the deceased")
	client._creator.hide()
	client._survival.set_profile(profile)
	client._survival.set_grave({"id": "1", "player_name": notice.name, "kind": "headstone", "gold": "0", "items": [], "obituary": notice})
	_check(client._survival.visible and client._survival.grave_list.get_node("MemorialName").text == notice.name and client._survival.grave_list.get_node("lived_days").text == "Prožité dny: 12", "An empty nearby grave still displays the same obituary")
	_check(client._survival.grave_list.get_node("born_at").text.contains("2000-01-02"), "Empty grave preserves the same birth date")
	_check(client._survival.grave_list.find_children("Take", "Button", true, false).is_empty() and not client._survival.grave_list.has_node("NewCharacter"), "Empty graves retain a memorial without loot or resurrection actions")
	client._survival.hide()
	for address in ["http://127.0.0.1:17400", "http://localhost:7400/base", "http://[::1]:7400", "https://example.org"]:
		_check(SESSION.safe_transport(address), "Safe account transport " + address)
	for address in ["http://localhost.example.org", "http://127.0.0.1.evil", "http://example.org", "ftp://localhost", ""]:
		_check(not SESSION.safe_transport(address), "Unsafe account transport " + address)
	if DisplayServer.get_name() != "headless":
		await _test_surface_preview(client, profile)
		client._hud.set_player(profile)
		client._creator.show_setup("PlayerOne", "survivors/survivorMaleB")
		client._creator.rotation_slider.value = 0
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
			root.size = dimensions
			client._creator.rotation_slider.value = 0
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			_check(bounds.encloses(client._creator.submit_button.get_global_rect()) and bounds.encloses(client._creator.password_input.get_global_rect()) and bounds.encloses(client._creator.packs.get_global_rect()), "Creation controls fit viewport %s" % dimensions)
			var image := root.get_texture().get_image()
			image.save_png("/tmp/ishtaria-character-cs-%sx%s.png" % [dimensions.x, dimensions.y])
			var preview_image: Image = client._creator._viewport.get_texture().get_image()
			var first_pixel := preview_image.get_pixel(preview_image.get_width() / 2, preview_image.get_height() / 2)
			var nonblank := false
			for position in [Vector2(0.3, 0.3), Vector2(0.5, 0.2), Vector2(0.7, 0.7)]:
				nonblank = nonblank or preview_image.get_pixel(int(preview_image.get_width() * position.x), int(preview_image.get_height() * position.y)) != first_pixel
			_check(nonblank, "3D preview renders nonblank pixels %s" % dimensions)
			var selected_avatar: Node3D = client._creator.model
			for drag_index in 9:
				await _drag_preview(client._creator, Vector2(40, 0))
			_check(is_equal_approx(client._creator.rotation_slider.value, -180) and is_equal_approx(selected_avatar.rotation_degrees.y, -180), "Actual viewport mouse events rotate the preview to its back at %s" % dimensions)
			_check(client._creator.model == selected_avatar and client._creator.character == "survivors/survivorMaleB", "Mouse rotation preserves the selected model and skin %s" % dimensions)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/ishtaria-character-mouse-back-%sx%s.png" % [dimensions.x, dimensions.y])
		client._creator.hide()
		client._survival.set_profile(profile)
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
			root.size = dimensions
			client._survival.hide()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			_check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(client._hud.panel.get_global_rect()) and client._hud.panel.get_global_rect().encloses(client._hud.age_label.get_global_rect()), "HUD and age fit viewport %s" % dimensions)
			_check(client._hud.panel.size.x <= 920.0 and client._hud.panel.size.y <= 180.0, "HUD stays compact instead of filling the screen %s" % dimensions)
			_check(client._hud._frame.get_global_rect() == client._hud.panel.get_global_rect() and client._hud._frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Fantasy border follows the panel without blocking controls %s" % dimensions)
			for meter in client._hud.meters.values():
				_check(meter.size.y <= 12.0, "HUD uses slim status bars %s" % dimensions)
			root.get_texture().get_image().save_png("/tmp/ishtaria-hud-age-cs-%sx%s.png" % [dimensions.x, dimensions.y])
			var long_profile: Dictionary = profile.duplicate(true)
			long_profile.username = "Player_" + "LongNickname".repeat(4)
			long_profile.stats.gold = "9223372036854775807"
			for locale in ["en", "cs"]:
				TranslationServer.set_locale(locale)
				client._hud.set_player(long_profile)
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				for label in [client._hud.player_name, client._hud.gold_label, client._hud.level_label, client._hud.clock_label]:
					_check(client._hud.panel.get_global_rect().encloses(label.get_global_rect()), "Long HUD values fit %s %s" % [locale, dimensions])
				_check(client._hud.gold_label.tooltip_text.ends_with("9223372036854775807") and client._hud.player_name.tooltip_text == long_profile.username, "Truncated HUD values retain their exact full tooltips %s %s" % [locale, dimensions])
				root.get_texture().get_image().save_png("/tmp/ishtaria-hud-long-%s-%sx%s.png" % [locale, dimensions.x, dimensions.y])
			client._hud.set_player(profile)
			client._survival.open()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			_check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(client._survival.panel.get_global_rect()), "Inventory panel fits viewport %s" % dimensions)
			for button in client._survival.inventory_list.find_children("Eat", "Button", true, false):
				_check(client._survival.panel.get_global_rect().encloses(button.get_global_rect()), "Eat button fits inventory %s" % dimensions)
			root.get_texture().get_image().save_png("/tmp/ishtaria-inventory-cs-%sx%s.png" % [dimensions.x, dimensions.y])
			for kind in client._survival.MODELS:
				client._survival.set_grave({"id": "1", "player_name": notice.name, "kind": kind, "gold": "73", "items": profile.inventory.items, "obituary": notice})
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var image: Image = client._survival.preview.get_texture().get_image()
				var background := image.get_pixel(0, 0)
				var rendered := false
				for pixel_y in range(0, image.get_height(), 4):
					for pixel_x in range(0, image.get_width(), 4):
						var pixel := image.get_pixel(pixel_x, pixel_y)
						rendered = rendered or absf(pixel.r - background.r) + absf(pixel.g - background.g) + absf(pixel.b - background.b) > 0.05
				_check(rendered, "Actual Kenney %s renders nonblank at %s" % [kind, dimensions])
				root.get_texture().get_image().save_png("/tmp/ishtaria-grave-%s-%sx%s.png" % [kind, dimensions.x, dimensions.y])
			client._survival.show_obituary({"name": "Longest_Deceased_Character_Name32", "born_at": "2000-01-02T03:04:05.000006Z", "lived_days": "12345", "lifetime_gold": "9223372036854775807", "friends_count": "12345"})
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			_check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(client._survival.panel.get_global_rect()), "Obituary fits viewport %s" % dimensions)
			for label in client._survival.grave_list.find_children("*", "Label", true, false):
				_check(label.get_global_rect().size.x <= client._survival.panel.size.x, "Obituary text fits its panel %s" % dimensions)
			root.get_texture().get_image().save_png("/tmp/ishtaria-obituary-cs-%sx%s.png" % [dimensions.x, dimensions.y])
		client._survival.hide()
	client._disconnect_server()
	client.free()
	await process_frame
	client = MAIN_SCENE.instantiate()
	client._settings_path = path
	root.add_child(client)
	client._audio.set_enabled(false)
	client._disconnect_server()
	_check(not client._creator.visible and client._creator.character == "survivors/survivorMaleB" and client._creator.nickname_input.text == "PlayerOne", "Restart restores identity but waits for server verification")
	_check(client._player_profile.is_empty() and client._hud.gold_label.text == "Zlato -", "Restart does not fabricate an authenticated player")
	_world_ready(client)
	_check(client._creator.visible and client._creator.mode.current_tab == 1 and client._creator.password_input.text.is_empty(), "Returning player is prompted to sign in after server verification")
	_check(client._creator.password_input.has_focus() and client._creator.password_input.placeholder_text == "Nepovinné heslo", "Returning player focuses the optional password without stored credentials")
	if DisplayServer.get_name() != "headless":
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
			root.size = dimensions
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			_check(bounds.encloses(client._creator.submit_button.get_global_rect()) and bounds.encloses(client._creator.password_input.get_global_rect()) and bounds.encloses(client._creator.back_button.get_global_rect()), "Returning sign-in and change-server controls fit viewport %s" % dimensions)
			root.get_texture().get_image().save_png("/tmp/ishtaria-signin-cs-%sx%s.png" % [dimensions.x, dimensions.y])
	client._creator.back_button.pressed.emit()
	_check(not client._creator.visible and not client._connection_enabled and client._creator.password_input.text.is_empty(), "Change server returns to server selection without credentials")
	var test_url := OS.get_environment("ISHTARIA_PLAYER_TEST_URL")
	if not test_url.is_empty():
		await _test_accounts(client, test_url, path)
	client.free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_surface_preview(client: Node, profile: Dictionary) -> void:
	client.set_process(false)
	client._on_player_profile(profile)
	client._creator.hide()
	client._survival.hide()
	var image := Image.create(12, 2, false, Image.FORMAT_RGB8)
	for face in 6:
		for pixel_x in 2:
			for pixel_y in 2:
				var value := 0.1 + float(face) * 0.15
				image.set_pixel(face * 2 + pixel_x, pixel_y, Color(value, value, value))
	var png := image.save_png_to_buffer()
	client._terrain_loaded = false
	client._on_terrain_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), png, client._connection_generation - 1, 2)
	_check(not client._terrain_loaded, "Stale heightmap cannot replace the selected world")
	client._on_terrain_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), png, client._connection_generation, 3)
	_check(not client._terrain_loaded, "Unexpected heightmap dimensions are rejected before decoding")
	client._on_terrain_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), png, client._connection_generation, 2)
	_check(client._terrain_loaded and client._terrain_material.get_shader_parameter("heightmap").get_width() == 12, "Valid six-face heightmap is bound to the planet shader")
	for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
		root.size = dimensions
		client._surface_direction = Vector3.ZERO
		client._sky.set_altitude(1000000.0)
		client._process(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var orbital := root.get_texture().get_image()
		orbital.save_png("/tmp/ishtaria-approach-orbit-%sx%s.png" % [dimensions.x, dimensions.y])
		client._start_approach(profile.position)
		client._process(2.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/ishtaria-approach-moving-%sx%s.png" % [dimensions.x, dimensions.y])
		client._process(2.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var surface := root.get_texture().get_image()
		surface.save_png("/tmp/ishtaria-approach-surface-%sx%s.png" % [dimensions.x, dimensions.y])
		var center := Vector2i(dimensions.x / 2, dimensions.y / 4)
		var before := orbital.get_pixel(center.x, center.y)
		var after := surface.get_pixel(center.x, center.y)
		_check(after.g > 0.005 and absf(after.g - before.g) + absf(after.r - before.r) > 0.01, "Approach renders a nonblank, changed surface at %s" % dimensions)
	client.set_process(true)

func _wait_session(session: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while session.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	return not session.busy

func _wait_world(client: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while client._connected_world.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	return not client._connected_world.is_empty()

func _test_accounts(client: Node, url: String, settings_path: String) -> void:
	_check(SESSION.safe_transport(url) and url.begins_with("http://127.0.0.1:"), "End-to-end tests use an isolated loopback server")
	if not url.begins_with("http://127.0.0.1:"):
		return
	var nickname := "KenneyTest_%s" % Time.get_ticks_usec()
	client._server_input.text = url
	client._connect_server(false)
	_check(await _wait_world(client) and client._creator.visible, "Actual verified server connection opens account setup")
	client._creator.show_setup(nickname, "protagonists/cyborgFemaleA")
	client._creator.password_input.text = ""
	client._creator.submit_button.pressed.emit()
	_check(client._session.busy, "Creation sends a real HTTP request")
	_check(await _wait_session(client._session), "Registration completes")
	_check(client._player_profile.get("username") == nickname and client._player_profile.get("character") == "protagonists/cyborgFemaleA", "PostgreSQL API returns the selected nickname and character")
	_check(client._hud.gold_label.text == "Zlato 100" and not client._creator.visible, "Actual registration shows initial gold and closes creation")
	_check(client._hud.age_label.text == "Věk: 0 dní", "Actual registration displays a newborn age from the server")
	_check(client._player_profile.get("inventory", {}).get("capacity") == 100, "Actual registration grants a 100-slot inventory")
	var saved_position: Dictionary = client._player_profile.get("position", {})
	_check(saved_position.has("x") and client._surface_direction != Vector3.ZERO, "Actual registration starts approach toward the server-assigned location")
	_check(client._terrain_loaded, "Actual HTTP heightmap is loaded for the authenticated world")
	client._session.eat("apple")
	_check(await _wait_session(client._session), "Real Eat HTTP request completes")
	_check(client._player_profile.get("life", {}).get("calories_consumed") == "95", "Actual eating records authoritative calories")
	_check(client._player_profile.inventory.items[0].quantity == "2", "Actual eating consumes exactly one apple")
	_check(client._creator.password_input.text.is_empty(), "Submitted password is cleared from the form")
	var settings := ConfigFile.new()
	settings.load(settings_path)
	_check(not settings.has_section_key("player", "password") and not settings.has_section_key("player", "token") and not settings.encode_to_text().contains(client._session._token), "HTTP credentials and bearer token are not persisted")
	client._session.refresh()
	_check(await _wait_session(client._session) and client._player_profile.get("character") == "protagonists/cyborgFemaleA", "Actual profile refresh preserves selected character")
	client._session.sign_out()
	_check(await _wait_session(client._session) and client._player_profile.is_empty() and client._hud.gold_label.text == "Zlato -", "Actual logout clears profile and gold")
	_check(client._creator.visible and client._creator.mode.current_tab == 1 and client._creator.nickname_input.text == nickname, "Logout returns to sign-in with the remembered nickname")
	client._disconnect_server()
	client._server_input.text = url
	client._connect_server(false)
	_check(await _wait_world(client) and client._creator.visible and client._creator.mode.current_tab == 1 and client._creator.nickname_input.text == nickname, "Reconnection prompts the returning player to sign in")
	client._creator.password_input.text = ""
	client._creator.submit_button.pressed.emit()
	_check(await _wait_session(client._session) and client._player_profile.get("character") == "protagonists/cyborgFemaleA" and not client._creator.visible, "Empty-password login restores the server character and closes sign-in")
	_check(client._hud.gold_label.text == "Zlato 100", "Login does not regrant or reset gold")
	_check(client._player_profile.get("position") == saved_position, "Actual relogin returns to the same saved surface location")
	client._session.sign_out()
	await _wait_session(client._session)
	if OS.get_environment("ISHTARIA_TEST_OBITUARY") == "1":
		client._creator.show_setup("dead-player", CATALOG.DEFAULT_CHARACTER, false)
		client._creator.password_input.text = "test-password"
		client._creator.submit_button.pressed.emit()
		_check(await _wait_session(client._session), "Actual dead-character login completes")
		_check(client._session._token.is_empty() and client._player_profile.is_empty(), "Actual dead-character login issues no token or player profile")
		_check(client._survival.visible and client._survival._obituary.get("name") == "dead-player", "PostgreSQL obituary is displayed on failed login")
		_check(client._survival._obituary.get("lived_days") == "0" and client._survival._obituary.get("lifetime_gold") == "100" and client._survival._obituary.get("friends_count") == "0", "Actual obituary displays the persisted lifespan, wealth and friends")
		_check(SESSION.valid_obituary(client._survival._obituary) and client._survival.grave_list.get_node("born_at").text.contains("UTC"), "Actual obituary displays the server birth timestamp")
		client._survival.grave_list.get_node("NewCharacter").pressed.emit()
		_check(client._creator.visible and client._creator.nickname_input.text.is_empty() and client._creator.mode.current_tab == 0, "Actual obituary offers a distinct new character")