extends SceneTree
## Talks to a real server given in ISHTARIA_TEST_SERVER with federation enabled; skipped without it.

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
	session.create_invitation("brana-live")
	var invitation := await _wait(session, "invitation_created")
	_check(invitation.size() == 1 and invitation[0].code.begins_with("ishtaria-invite:v1."), "invitation created")
	session.accept_invitation(invitation[0].code, "brana-jih")
	var refused := await _wait(session, "failed")
	_check(refused == ["That invitation is from your own world"], "own invitation is refused with a fixed message: %s" % [refused])
	session.fetch_pacts()
	var pacts := await _wait(session, "pacts_received")
	_check(pacts.size() == 1 and pacts[0] is Array and pacts[0].is_empty(), "no pacts yet")
	session.create_invitation("Bad Name")
	_check(session.busy == false, "an invalid name sends nothing")
	session.place_site("0192f3a1-5b1e-7c3a-9d4e-1a2b3c4d5e6f")
	var missing := await _wait(session, "failed")
	_check(missing == ["Portal action unavailable"], "an unknown pact gives the generic message: %s" % [missing])
	if _failures > 0:
		push_error("%d portal live checks failed" % _failures)
	else:
		print("Portal live checks passed")
	quit(1 if _failures > 0 else 0)
