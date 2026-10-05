extends SceneTree
## Plays The End Land datadisk against a real server. Needs ISHTARIA_TEST_SERVER (a server whose
## world was generated with the `endland` disk) and ISHTARIA_TEST_DATABASE (its psql URL, used to
## stand the player next to a character); skipped without them.

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _wait(source: Object, signal_name: String) -> Array:
	var result := []
	var done := [false]
	source.connect(signal_name, func(...args: Array) -> void:
		result.assign(args)
		done[0] = true
	, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + 8000
	while not done[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	return result if done[0] else ["timeout"]

func _psql(sql: String) -> String:
	var output := []
	OS.execute("psql", [OS.get_environment("ISHTARIA_TEST_DATABASE"), "-Atc", sql], output)
	return String(output[0]).strip_edges()

func _fetch_json(url: String) -> Variant:
	var request := HTTPRequest.new()
	root.add_child(request)
	request.request(url)
	var reply: Array = await request.request_completed
	request.queue_free()
	return JSON.parse_string(reply[3].get_string_from_utf8())

func _run() -> void:
	var url := OS.get_environment("ISHTARIA_TEST_SERVER")
	if url.is_empty() or OS.get_environment("ISHTARIA_TEST_DATABASE").is_empty():
		print("Story live checks skipped (ISHTARIA_TEST_SERVER / ISHTARIA_TEST_DATABASE not set)")
		quit()
		return
	var session := preload("res://scripts/player_session.gd").new()
	root.add_child(session)
	session.configure(url)
	var name := "story-%d" % (Time.get_ticks_usec() % 100000)
	session.submit(name, "test-password", "retro/humanMaleA", true)
	var profile := await _wait(session, "profile_changed")
	_check(profile.size() == 1 and profile[0].get("username") == name, "registered")

	var story: Node = preload("res://scripts/story_client.gd").new()
	root.add_child(story)
	story.start_session(url, session.token())
	await _wait(story, "strings_changed")
	_check(story.text("endland:npc.kragg") == "Kragg Blackhorn", "English translation arrives")
	TranslationServer.set_locale("cs")
	_check(story.text("endland:place.old_graveyard") == "Starý hřbitov", "Czech translation arrives from the same answer")
	TranslationServer.set_locale("en")

	# Find Kragg through the objects of the tavern's neighbourhood.
	var point := _psql("select direction_x*6371000.0 || ' ' || direction_y*6371000.0 || ' ' || direction_z*6371000.0 from story_anchors where anchor_id = 'endland:blackhorn_tavern'").split(" ")
	var objects: Dictionary = await _fetch_json(url + "/world/objects?x=%s&y=%s&z=%s" % [point[0], point[1], point[2]])
	var kragg := {}
	for npc: Dictionary in objects.npcs:
		if npc.id == "endland:kragg":
			kragg = npc
	_check(not kragg.is_empty(), "Kragg stands near the tavern")
	var environment := preload("res://scripts/surface_environment.gd").new()
	root.add_child(environment)
	_check(environment.apply_npcs(objects.npcs) and environment.npcs.get_child_count() == 4, "the client accepts what the server sent")
	_check(story.valid_media_url(kragg.portrait), "the portrait path is acceptable to the client")

	# Generated towns: a coastal one has props, a harbour and a shipwright.
	var town := _psql("select direction_x*(6371000.0+height_m) || ' ' || direction_y*(6371000.0+height_m) || ' ' || direction_z*(6371000.0+height_m) from story_anchors where anchor_id = 'world:town_00'").split(" ")
	var around: Dictionary = await _fetch_json(url + "/world/objects?x=%s&y=%s&z=%s" % [town[0], town[1], town[2]])
	_check(around.props.size() > 100, "a town has buildings: %d" % around.props.size())
	_check(environment.apply_props(around.props) and environment.props.get_child_count() == around.props.size(), "the client builds every prop the server sent (%d of %d)" % [environment.props.get_child_count(), around.props.size()])
	var shipwrights: Array = around.npcs.filter(func(n: Dictionary) -> bool: return n.id.contains("shipwright"))
	_check(shipwrights.size() == 1, "the coastal town has a shipwright")

	story.start("endland:kragg")
	var refused := await _wait(story, "failed")
	_check(refused == ["Too far away to talk"], "talking from afar is refused: %s" % [refused])

	_psql("update players set position_x = %f, position_y = %f, position_z = %f where username = '%s'" % [kragg.position[0], kragg.position[1], kragg.position[2], name])
	story.start("endland:kragg")
	var started := await _wait(story, "dialogue_changed")
	_check(started.size() == 1 and started[0].node.text_key == "endland:kragg.greet" and started[0].music.loop, "the conversation opens with greeting and music")
	story.choose("endland:kragg", int(started[0].seq), 1) # buy bread
	var served := await _wait(story, "dialogue_changed")
	_check(served[0].node.text_key == "endland:kragg.served", "the server moved the conversation on")
	session.refresh()
	var after := await _wait(session, "profile_changed")
	_check(str(after[0].stats.gold) == "98", "two gold were paid: %s" % str(after[0].stats.gold))

	story.load_quests()
	await create_timer(0.6).timeout
	_check(story._quests_loaded and story._quests.is_empty(), "the quest log was fetched and no quest has been started yet")

	if _failures > 0:
		push_error("%d story live checks failed" % _failures)
	else:
		print("Story live checks passed")
	quit(1 if _failures > 0 else 0)
