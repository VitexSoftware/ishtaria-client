extends SceneTree

const HISTORY := preload("res://scripts/server_history.gd")

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _validate(address: String) -> String:
	return address if address.begins_with("http://127.0.0.1:") or address.begins_with("https://") else ""

func _wait_probe(history: Node, url: String) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if not history.result_for(url).is_empty():
			return true
		await process_frame
	return false

func _run() -> void:
	var path := "user://history-test-%s.cfg" % Time.get_ticks_usec()
	var seed_file := ConfigFile.new()
	seed_file.set_value("interface", "language", "cs")
	seed_file.save(path)
	var history: Node = HISTORY.new()
	history.settings_path = path
	history.url_validator = _validate
	root.add_child(history)
	history.load_entries()
	_check(history.entries.is_empty(), "Empty settings give an empty history")
	var world := {"server_name": "Alpha", "ruleset": "core-rules@1.0", "seed": 1}
	_check(history.record_connection("http://127.0.0.1:1", world) == OK, "Connection is recorded")
	history.record_connection("https://example.org", {"server_name": "Beta", "ruleset": "core-rules@1.0", "seed": 2}, "portal")
	history.record_connection("http://127.0.0.1:1", world)
	_check(history.entries.size() == 2, "Repeated connection updates the existing entry")
	var saved := ConfigFile.new()
	saved.load(path)
	_check(saved.get_value("interface", "language") == "cs", "Saving history preserves other sections")
	_check(not "token" in str(saved.get_value("servers", "entries")).to_lower(), "History holds no token fields")
	var reloaded: Node = HISTORY.new()
	reloaded.settings_path = path
	reloaded.url_validator = _validate
	root.add_child(reloaded)
	reloaded.load_entries()
	_check(reloaded.entries.size() == 2 and reloaded.entries[0].source in ["manual", "portal"], "History survives a restart")
	saved.set_value("servers", "entries", [{"url": "ftp://bad"}, "junk", {"url": "http://127.0.0.1:1", "source": "evil"}])
	saved.save(path)
	reloaded.load_entries()
	_check(reloaded.entries.size() == 1 and reloaded.entries[0].source == "manual", "Invalid stored entries are dropped and sources sanitized")
	for i in 30:
		history.record_connection("https://host%d.example.org" % i, world)
	_check(history.entries.size() == HISTORY.MAX_ENTRIES, "History is bounded")
	history.forget("https://host29.example.org")
	_check(not history.has_entry("https://host29.example.org"), "Entries can be forgotten")
	_check(history.is_unencrypted("http://example.org") and not history.is_unencrypted("http://127.0.0.1:7400") and not history.is_unencrypted("https://example.org"), "Plain HTTP to remote hosts is flagged")
	# Availability: a closed port is unreachable.
	var probe_history: Node = HISTORY.new()
	probe_history.settings_path = path
	probe_history.url_validator = _validate
	root.add_child(probe_history)
	probe_history.record_connection("http://127.0.0.1:1", world)
	probe_history.probe_all()
	_check(await _wait_probe(probe_history, "http://127.0.0.1:1"), "Probe of a closed port finishes")
	_check(probe_history.result_for("http://127.0.0.1:1").get("state") == "unreachable", "Closed port is reported unreachable")
	# Optional live check against a running server or fake endpoint.
	var live := OS.get_environment("ISHTARIA_TEST_PROBE_URL")
	if not live.is_empty():
		probe_history.record_connection(live, world)
		probe_history.probe_all()
		_check(await _wait_probe(probe_history, live), "Live probe finishes")
		var result: Dictionary = probe_history.result_for(live)
		var expected := OS.get_environment("ISHTARIA_TEST_PROBE_STATE")
		_check(result.get("state") == (expected if not expected.is_empty() else "online"), "Live probe state: %s" % result)
		_check(result.get("latency_ms", -1.0) >= 0.0, "Live probe measures latency")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures > 0:
		push_error("%d server history checks failed" % _failures)
	else:
		print("Server history checks passed")
	quit(1 if _failures > 0 else 0)
