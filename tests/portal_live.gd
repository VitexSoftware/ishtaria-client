extends SceneTree
## Talks to a real server given in ISHTARIA_TEST_SERVER; skipped without it.

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _wait(session: Node, signal_name: String) -> Array:
	var result := []
	var done := [false]
	session.connect(signal_name, func(...args: Array) -> void:
		result.assign(args)
		done[0] = true
	, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + 8000
	while not done[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	return result if done[0] else ["timeout"]

func _run() -> void:
	var url := OS.get_environment("ISHTARIA_TEST_SERVER")
	if url.is_empty():
		print("Portal live checks skipped (ISHTARIA_TEST_SERVER is not set)")
		quit()
		return
	var session := preload("res://scripts/player_session.gd").new()
	root.add_child(session)
	session.configure(url)
	var name := "live-%d" % (Time.get_ticks_usec() % 100000)
	session.submit(name, "test-password", "retro/humanMaleA", true)
	var profile := await _wait(session, "profile_changed")
	_check(profile.size() == 1 and profile[0] is Dictionary and profile[0].get("username") == name, "registered")
	session.build_portal("brana-live-%d" % (Time.get_ticks_usec() % 100000))
	var built := await _wait(session, "portal_received")
	_check(built.size() == 1 and built[0] is Dictionary and built[0].state == "building" and built[0].requirements.size() == 3, "a portal is started where the player stands")
	var id: String = built[0].id
	session.fetch_link(id)
	var refused := await _wait(session, "failed")
	_check(refused == ["Only a finished, unlinked portal can be linked"], "an unfinished portal has no share link: %s" % [refused])
	session.fetch_portals()
	var listed := await _wait(session, "portals_received")
	_check(listed.size() == 1 and listed[0] is Array and listed[0].size() == 1, "the portal is listed")
	session.build_portal("Bad Name")
	_check(session.busy == false, "an invalid name sends nothing")
	session.connect_portal(id, "not a link")
	_check(session.busy == false, "an invalid link sends nothing")
	session.connect_portal(id, "ishtaria-portal:v1.abc.def")
	var unfinished := await _wait(session, "failed")
	_check(unfinished == ["Only a finished, unlinked portal can be linked"], "an unfinished portal cannot be connected: %s" % [unfinished])
	session.close_portal(id)
	await _wait(session, "portal_closed")
	if _failures > 0:
		push_error("%d portal live checks failed" % _failures)
	else:
		print("Portal live checks passed")
	quit(1 if _failures > 0 else 0)
