extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _failures := 0
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)

func _wait_for_status(client: Node, expected: String) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		if expected in client._status.text:
			return true
		await process_frame
	return false

func _run() -> void:
	var previous_environment := OS.get_environment("ISHTARIA_SERVER_URL")
	OS.set_environment("ISHTARIA_SERVER_URL", "")
	var settings_path := "user://connection-test-%s.cfg" % Time.get_ticks_usec()
	var client := MAIN_SCENE.instantiate()
	client._settings_path = settings_path
	root.add_child(client)
	_check(TranslationServer.get_locale() == "en", "English is the default client language")
	for entry in [
		["127.0.0.1:7400", "http://127.0.0.1:7400"],
		[" https://example.org:8443/ ", "https://example.org:8443"],
		["http://[::1]:7400", "http://[::1]:7400"],
		["https://example.org/ishtaria", "https://example.org/ishtaria"],
		["", ""],
		["ftp://example.org", ""],
		["http://example.org:0", ""],
		["http://example.org:65536", ""],
		["http://user:password@example.org", ""],
		["http://bad host", ""],
		["http://[:::]:7400", ""],
		["http://example.org?token=secret", ""],
	]:
		_check(client._normalize_server_url(entry[0]) == entry[1], "URL validation: " + entry[0])
	_check(await _wait_for_status(client, "ishtaria.example.org"), "Initial connection to local server")
	var previous_generation: int = client._connection_generation
	client._server_input.text = "ftp://example.org"
	client._connect_server()
	_check(client._feedback.text == "Invalid server address", "Invalid address has visible feedback")
	_check(client._connection_generation == previous_generation and client._connection_enabled, "Invalid input preserves existing connection")
	client._server_input.text = "127.0.0.1:1"
	client._server_input.text_submitted.emit(client._server_input.text)
	_check(await _wait_for_status(client, "Server unavailable"), "Unreachable server has visible status")
	_check(not client._reconnect.is_stopped(), "Failed connection schedules retry")
	var settings := ConfigFile.new()
	_check(settings.load(settings_path) == OK, "Submitted address is saved")
	_check(settings.get_value("connection", "server_url") == "http://127.0.0.1:1", "Saved address is normalized")
	var stale_body := JSON.stringify({"server_name": "stale.example.org", "ruleset": "core-rules@1.0", "server_version": "0.1.0"}).to_utf8_buffer()
	client._on_world_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), stale_body, previous_generation)
	_check(not "stale.example.org" in client._status.text, "Old server response cannot replace new status")
	client._server_input.text = "127.0.0.1:7400/"
	var connect_button: Button = client.find_child("Connect", true, false)
	connect_button.pressed.emit()
	_check(await _wait_for_status(client, "ishtaria.example.org"), "Connect button switches back to local server")
	_check(client._server_input.text == "http://127.0.0.1:7400", "Address field shows normalized URL")
	_check(client._feedback.text.is_empty(), "Successful submission clears validation feedback")
	previous_generation = client._connection_generation
	client._disconnect_button.pressed.emit()
	_check(not client._connection_enabled and client._reconnect.is_stopped(), "Disconnect stops requests and retries")
	_check(client._status.text == "Disconnected" and client._disconnect_button.disabled, "Disconnect updates controls")
	client._refresh_world()
	client._on_world_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), stale_body, previous_generation)
	_check(client._status.text == "Disconnected" and not client._request_pending, "Manual disconnect survives retries and stale responses")
	client.queue_free()
	await process_frame
	client = MAIN_SCENE.instantiate()
	client._settings_path = settings_path
	root.add_child(client)
	_check(client._server_input.text == "http://127.0.0.1:7400", "Restart restores saved address")
	_check(await _wait_for_status(client, "ishtaria.example.org"), "Restart reconnects to saved server")
	previous_generation = client._connection_generation
	var previous_request: HTTPRequest = client._request
	var previous_url: String = client._server_url
	client._set_feedback("Invalid server address")
	client._language_option.select(1)
	client._language_option.item_selected.emit(1)
	_check(TranslationServer.get_locale() == "cs", "Language selector switches to Czech")
	_check(client._connect_button.text == "Připojit" and client._disconnect_button.text == "Odpojit", "Commands are translated immediately")
	_check(client._feedback.text == "Neplatná adresa serveru", "Existing validation feedback is retranslated")
	_check(client._server_input.tooltip_text == "Adresa serveru", "Server tooltip is translated")
	_check(client._connection_generation == previous_generation and client._request == previous_request and client._server_url == previous_url, "Changing language preserves the connection and sends no new request")
	_check(settings.load(settings_path) == OK and settings.get_value("interface", "language") == "cs", "Language preference is saved locally")
	_check(settings.get_value("connection", "server_url") == previous_url, "Saving language preserves the server address")
	client._show_disconnected("invalid response")
	_check(client._status.text == "Server není dostupný (neplatná odpověď)", "Status and its nested error reason are translated")
	client._language_option.select(0)
	client._language_option.item_selected.emit(0)
	_check(client._status.text == "Server unavailable (invalid response)", "Dynamic status switches back to English")
	client._set_status("Connecting to %s", ["https://example.org"])
	client._language_option.select(1)
	client._language_option.item_selected.emit(1)
	_check(client._status.text == "Připojování k https://example.org", "Translated format strings retain their arguments")
	client._set_status("%s | %s | seed %s", ["Connect", "Disconnect", "42"])
	_check(client._status.text == "Connect | Disconnect | seed 42", "Server-provided identity is not translated")
	var message_world: Dictionary = client._world_metadata.duplicate(true)
	var notice := "Plánované vypnutí světa. Dokončete probíhající činnosti a bezpečně se odhlaste; po údržbě bude svět opět dostupný."
	message_world.messages = [{"kind": "system", "code": "shutdown", "seconds_left": 125, "text": notice}]
	client._on_world_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(message_world).to_utf8_buffer(), client._connection_generation)
	client._reconnect.stop()
	var banner: CanvasLayer = client._system_messages
	_check(banner._panel.visible and "2:05" in banner._label.text and notice in banner._label.text, "World response displays the server shutdown notice and countdown")
	_check(banner._panel.mouse_filter == Control.MOUSE_FILTER_IGNORE and banner._label.mouse_filter == Control.MOUSE_FILTER_IGNORE and banner._frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "System announcement does not capture the mouse")
	_check(banner.find_children("*", "BaseButton", true, false).is_empty(), "System announcement has no dismiss control")
	banner._process(1.2)
	_check("2:04" in banner._label.text, "Shutdown countdown advances locally")
	TranslationServer.set_locale("en")
	_check(banner._label.text.begins_with("The server will shut down"), "Announcement retranslates to English")
	TranslationServer.set_locale("cs")
	_check(banner._label.text.begins_with("Server bude vypnut za"), "Announcement retranslates to Czech")
	client._on_world_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), stale_body, client._connection_generation - 1)
	_check(banner._panel.visible and notice in banner._label.text, "Stale world response cannot erase a current system announcement")
	banner.server_unreachable()
	_check(not banner._gone, "Early network failure is not reported as an administrative shutdown")

	# Server version compatibility tests
	_check(client.parse_version("0.1.0") == [0, 1, 0], "Semver parses to array")
	_check(client.parse_version("0.1.0.10~local1") == [0, 1, 0, 10], "Extended package version parses")
	_check(client.parse_version("invalid").is_empty(), "Malformed version returns empty array")
	_check(client.compare_versions("0.1.0", "0.1.0") == 0, "Identical versions compare equal")
	_check(client.compare_versions("0.1.1", "0.1.0") > 0, "Higher patch is greater")
	_check(client.compare_versions("0.0.9", "0.1.0") < 0, "Lower minor is lesser")
	_check(client.is_server_version_compatible("0.1.0"), "Exact minimum version is compatible")
	_check(client.is_server_version_compatible("0.1.1"), "Higher version is compatible")
	_check(not client.is_server_version_compatible("0.0.9"), "Lower version is incompatible")
	_check(not client.is_server_version_compatible(""), "Empty version is incompatible")

	var missing_version := JSON.stringify({"server_name": "alpha.example.org", "ruleset": "core-rules@1.0"}).to_utf8_buffer()
	client._connection_enabled = true
	client._on_world_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), missing_version, client._connection_generation)
	_check("Server unavailable (missing server version)" in client._status.text, "Missing server version is rejected")

	var incompatible_version := JSON.stringify({"server_name": "alpha.example.org", "ruleset": "core-rules@1.0", "server_version": "0.0.9"}).to_utf8_buffer()
	client._on_world_received(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), incompatible_version, client._connection_generation)
	_check("Server unavailable (server version 0.0.9 is incompatible (minimum 0.1.0))" in client._status.text, "Incompatible server version is rejected with details")

	TranslationServer.set_locale("cs")
	client._update_translations()
	_check("Server není dostupný (verze serveru 0.0.9 není kompatibilní (minimum 0.1.0))" in client._status.text, "Incompatible server version error translates to Czech")
	TranslationServer.set_locale("en")
	client._update_translations()
	if DisplayServer.get_name() != "headless":
		client._creator.hide()
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
			root.size = dimensions
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			_check(bounds.encloses(banner._panel.get_global_rect()) and bounds.encloses(banner._frame.get_global_rect()), "Shutdown banner fits viewport %s" % dimensions)
			_check(banner._label.get_line_count() >= 2 and not banner._label.clip_text, "Long shutdown message wraps without clipping at %s" % dimensions)
			root.get_texture().get_image().save_png("/tmp/ishtaria-shutdown-cs-%sx%s.png" % [dimensions.x, dimensions.y])
	banner._shutdown_left = 0.0
	client._show_disconnected("network %s / HTTP %s", [HTTPRequest.RESULT_CANT_CONNECT, 0])
	client._reconnect.stop()
	_check(banner._gone and banner._label.text == "Server byl vypnut administrátorem.", "Announced shutdown is explained after the server stops answering")
	banner.apply([])
	_check(not banner._panel.visible and not banner._announced_shutdown, "Cancelled shutdown hides the banner and resets its state")
	banner.apply([{"kind": "player", "code": "shutdown", "seconds_left": 1, "text": "Player message"}])
	_check(not banner._panel.visible, "Player messages cannot impersonate system announcements")
	banner.apply(message_world.messages)
	if DisplayServer.get_name() != "headless":
		client._set_status("%s | %s | seed %s", ["ishtaria.example.org", "core-rules@1.0", "42"])
		for dimensions in [Vector2i(1600, 900), Vector2i(640, 480)]:
			root.size = dimensions
			await process_frame
			await RenderingServer.frame_post_draw
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			_check(bounds.encloses(client._language_option.get_global_rect()) and bounds.encloses(client._server_input.get_global_rect()) and bounds.encloses(client._disconnect_button.get_global_rect()), "Czech controls fit viewport %s" % dimensions)
			root.get_texture().get_image().save_png("/tmp/ishtaria-localization-cs-%sx%s.png" % [dimensions.x, dimensions.y])
	client._disconnect_server()
	_check(client._status.text == "Odpojeno", "Disconnected state uses the selected language")
	_check(not banner._panel.visible and not banner._announced_shutdown, "Disconnect clears the old server announcement")
	client.queue_free()
	await process_frame
	client = MAIN_SCENE.instantiate()
	client._settings_path = settings_path
	root.add_child(client)
	_check(TranslationServer.get_locale() == "cs" and client._language_option.selected == 1, "Restart restores locally saved Czech")
	_check(client._connect_button.text == "Připojit", "Restarted controls use the restored language")
	client._disconnect_server()
	client.queue_free()
	await process_frame
	settings.load(settings_path)
	settings.set_value("interface", "language", "unsupported")
	settings.save(settings_path)
	client = MAIN_SCENE.instantiate()
	client._settings_path = settings_path
	root.add_child(client)
	_check(TranslationServer.get_locale() == "en" and client._language_option.selected == 0, "Unsupported saved language falls back to English")
	client._disconnect_server()
	client.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	OS.set_environment("ISHTARIA_SERVER_URL", previous_environment)
	print("Connection controls: %s checks, %s failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
