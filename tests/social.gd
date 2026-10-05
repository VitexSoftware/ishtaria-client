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
