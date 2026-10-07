extends SceneTree
## Checks of the friends client: validation, chat lines, the panel and the glow.

var failures := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAILED: " + what)

func _init() -> void:
	var social := preload("res://scripts/social.gd")
	_check(social.valid_name("anna") and not social.valid_name("") and not social.valid_name("a/b") and not social.valid_name("x".repeat(33)), "names")
	_check(social.valid_friend({"name": "a", "online": true, "world": "w", "level": 2}) and not social.valid_friend({"name": "a", "online": 1, "world": "w", "level": 2}), "friend shape")
	_check(social.valid_request({"id": 3, "name": "a"}) and not social.valid_request({"id": 0, "name": "a"}), "request shape")
	_check(social.valid_event({"id": 1, "kind": "level_up", "subject": "a", "level": 4}) and not social.valid_event({"id": 1, "kind": "x", "subject": "a", "level": 4}) and not social.valid_event({"id": 1, "kind": "level_up", "subject": "a", "level": 0}), "event shape")
	_check(social.valid_event({"id": 2, "kind": "say", "subject": "a", "body": "hi"}) and social.valid_event({"id": 3, "kind": "whisper", "subject": "a", "body": "psst"}), "message shape")
	_check(not social.valid_event({"id": 2, "kind": "say", "subject": "a"}) and not social.valid_event({"id": 2, "kind": "say", "subject": "a", "body": ""}) and not social.valid_event({"id": 2, "kind": "say", "subject": "a", "body": "x".repeat(501)}) and not social.valid_event({"id": 2, "kind": "say", "subject": "", "body": "hi"}), "malformed messages are dropped")
	_check(social.chat_error_key(429, "") == "You are talking too fast" and social.chat_error_key(404, "friend not found") == "You can only whisper to friends" and social.chat_error_key(500, "SQL boom") == "Message not sent", "chat error keys never echo server text")
	_check(social.error_key(409, "already friends") == "Already friends" and social.error_key(500, "SQL boom") == "Friend action unavailable", "error keys never echo server text")

	var chat: CanvasLayer = preload("res://scripts/chat_feed.gd").new()
	root.add_child(chat)
	await process_frame
	for i in 9:
		chat.add_line("line %d" % i)
	_check(chat.line_count() == 6, "the chat keeps a few lines")
	chat.add_line("short", Color.WHITE, 0.2)
	await create_timer(1.3).timeout
	_check("short" not in chat.lines(), "a line fades away")
	chat.clear()
	_check(chat.line_count() == 0, "clear")
	var written := []
	chat.submitted.connect(func(text: String) -> void: written.append(text))
	chat.open_input()
	_check(chat.is_typing(), "the input opens")
	chat._line.text_submitted.emit("  hello  ")
	_check(written == ["hello"] and not chat.is_typing(), "a written line is trimmed, sent and the input closes")
	chat.open_input()
	chat._line.text_submitted.emit("   ")
	_check(written.size() == 1 and not chat.is_typing(), "an empty line is not sent")

	# Other players: only well-formed ones are drawn, those who left disappear.
	var remote: Node3D = preload("res://scripts/remote_players.gd").new()
	root.add_child(remote)
	await process_frame
	var valid := {"name": "boris", "character": "retro/humanMaleA", "level": 2, "x": 6371000.0, "y": 5.0, "z": 0.0}
	_check(remote.valid_player(valid), "a player shape")
	for broken in [{"name": "", "character": "retro/humanMaleA", "level": 1, "x": 0, "y": 0, "z": 0}, {"name": "x", "character": "../evil", "level": 1, "x": 0, "y": 0, "z": 0}, {"name": "x", "character": "retro/humanMaleA", "level": 1, "x": INF, "y": 0, "z": 0}, {"name": "x", "character": "retro/humanMaleA", "level": 1, "x": 9e9, "y": 0, "z": 0}, "boris"]:
		_check(not remote.valid_player(broken), "broken player rejected")
	remote.apply([valid, {"name": "cyril", "character": "protagonists/skaterMaleA", "level": 1, "x": 6371000.0, "y": 9.0, "z": 0.0}, {"name": "bad"}])
	_check(remote.names() == ["boris", "cyril"], "valid players are drawn")
	remote.apply([valid])
	_check(remote.names() == ["boris"], "players who left disappear")
	remote.apply("garbage")
	_check(remote.names() == ["boris"], "a malformed answer changes nothing")
	remote.stop()
	_check(remote.names().is_empty(), "stopping removes everyone")

	# Leaving a server clears the environment, but not the nodes that belong to the owner.
	var surface: Node3D = preload("res://scripts/surface_environment.gd").new()
	surface.land_material = ShaderMaterial.new()
	surface.water_material = ShaderMaterial.new()
	root.add_child(surface)
	await process_frame
	var kept: Node3D = preload("res://scripts/remote_players.gd").new()
	kept.set_meta("persistent", true)
	var stray := Node3D.new()
	surface.add_child(kept)
	surface.add_child(stray)
	surface.clear_world()
	await process_frame
	_check(is_instance_valid(kept) and kept.get_parent() == surface, "the other players survive leaving a server")
	_check(not is_instance_valid(stray), "other children are still cleared")
	kept.stop()

	var panel: CanvasLayer = preload("res://scripts/friends_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var added := []
	panel.add_requested.connect(func(n: String) -> void: added.append(n))
	panel.set_friends([{"name": "boris", "online": true, "world": "w.example", "level": 3}, {"name": "cyril", "online": false, "world": "w.example", "level": 1}])
	panel.set_requests([{"id": 7, "name": "dana"}], [{"id": 8, "name": "eva"}])
	_check(panel.list.find_child("Friend_boris", true, false) != null and panel.list.find_child("Request_7", true, false) != null and panel.list.find_child("Sent_8", true, false) != null, "rows")
	# A friend who chose to show a bundled flag has it in the row; unknown or malformed ones show nothing.
	panel.set_friends([{"name": "boris", "online": true, "world": "w", "level": 3, "flag": "CZ"}, {"name": "cyril", "online": true, "world": "w", "level": 1, "flag": "ZZ"}, {"name": "dana", "online": true, "world": "w", "level": 1, "flag": "../x"}, {"name": "eva", "online": true, "world": "w", "level": 1, "flag": null}])
	_check(panel.list.find_child("Friend_boris", true, false).find_child("Flag", true, false) != null, "the chosen flag is shown")
	for other in ["cyril", "dana", "eva"]:
		_check(panel.list.find_child("Friend_" + other, true, false).find_child("Flag", true, false) == null, other + " shows no flag")
	panel.name_input.text = "  anna "
	panel._add()
	_check(added == ["anna"], "add trims the name")

	var audio := preload("res://scripts/interface_audio.gd")
	var fanfare: AudioStreamWAV = audio.make_fanfare()
	_check(fanfare.data.size() > 1000 and fanfare.get_length() > 1.0, "fanfare exists")

	print("Social client checks %s" % ("failed" if failures > 0 else "passed"))
	quit(1 if failures > 0 else 0)
