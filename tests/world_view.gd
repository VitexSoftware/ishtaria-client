extends SceneTree
## Starts the real client against a real server, registers a character and saves screenshots of
## the world around it (the spawn point). Needs a display and ISHTARIA_TEST_SERVER; the
## pictures go to ISHTARIA_SHOT_DIR (default /tmp).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var url := OS.get_environment("ISHTARIA_TEST_SERVER")
	if url.is_empty():
		print("World view skipped (ISHTARIA_TEST_SERVER is not set)")
		quit()
		return
	var out := OS.get_environment("ISHTARIA_SHOT_DIR") if not OS.get_environment("ISHTARIA_SHOT_DIR").is_empty() else "/tmp"
	OS.set_environment("ISHTARIA_SERVER_URL", url)
	var client := (preload("res://scenes/main.tscn") as PackedScene).instantiate()
	client._settings_path = "user://world-view-%d.cfg" % OS.get_process_id()
	root.add_child(client)
	root.size = Vector2i(1600, 900)
	await create_timer(2.0).timeout
	var existing := OS.get_environment("ISHTARIA_VIEW_USER")
	var name := existing if not existing.is_empty() else "view-%d" % (Time.get_ticks_usec() % 100000)
	client._session.submit(name, "test-password", "retro/humanMaleA", existing.is_empty())
	var waited := 0.0
	while not client._controls.active and waited < 40.0:
		await create_timer(0.5).timeout
		waited += 0.5
	print("surface active after %.1f s: %s" % [waited, str(client._controls.active)])
	await create_timer(6.0).timeout
	print("objects loaded: %s, npcs: %d, props: %d" % [str(client._environment.objects_loaded), client._environment.npcs.get_child_count(), client._environment.props.get_child_count()])
	for angle in [0.0, 1.6, 3.2, 4.8]:
		client._controls.yaw = angle
		client._controls.pitch = -0.25
		client._controls.distance_m = 14.0
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/ishtaria-world-%s-%d.png" % [out, name.left(6), int(angle * 10)])
	# E talks to the character in reach: the dialogue panel with portrait and choices.
	client._controls.yaw = 0.0
	client._interact()
	await create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/ishtaria-dialogue.png" % out)
	print("dialogue open: %s" % str(client._dialogue.visible))
	quit()
