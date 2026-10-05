extends SceneTree

const SKY := preload("res://scripts/planet_sky.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _metadata(sky: Node, seconds: float) -> Dictionary:
	var direction: Vector3 = sky.solar_direction(seconds)
	return {"version": 1, "unix_seconds": seconds, "direction": [direction.x, direction.y, direction.z], "sidereal_day_seconds": 86164.0905, "angular_radius_degrees": 0.2666}

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	var sky := SKY.new()
	sky.sun = sun
	world.add_child(sky)
	sky.set_process(false)
	var noon := 946728000.0
	_check(sky.apply_solar(_metadata(sky, noon)), "Server solar state is accepted")
	var invalid := _metadata(sky, noon)
	invalid.direction = [0, 0, 0]
	_check(not sky.apply_solar(invalid), "Invalid solar direction is rejected")
	invalid = _metadata(sky, noon)
	invalid.unix_seconds = INF
	_check(not sky.apply_solar(invalid), "Nonfinite server clock is rejected")
	sky.set_altitude(120.0)
	sky.set_observer(Vector3.RIGHT)
	sky._update_solar(noon)
	_check(sky.sun_elevation_degrees > 60 and sky.daylight > 0.99, "Greenwich noon is daylight")
	_check((-sun.basis.z).dot(-sky.sun_direction) > 0.9999, "Light rays and visible sun use the same direction")
	var day_energy: float = sky.environment.ambient_light_energy
	sky._update_solar(noon + 43200.0)
	_check(sky.sun_elevation_degrees < -60 and sky.daylight < 0.01 and sun.light_energy == 0, "Greenwich midnight has no sunlight")
	_check(sky.environment.ambient_light_energy < day_energy * 0.02, "Night ambient illumination is dark")
	sky.set_observer(Vector3.LEFT)
	sky._update_solar(noon + 43200.0)
	_check(sky.daylight > 0.99, "Opposite longitude is daytime at the same instant")
	sky.set_observer(Vector3.UP)
	var june := (2460483.0 - 2440587.5) * 86400.0
	var december := (2460666.0 - 2440587.5) * 86400.0
	for hour in 24:
		sky._update_solar(june + hour * 3600.0)
		_check(sky.sun_elevation_degrees > 23, "North pole has summer polar day")
		sky._update_solar(december + hour * 3600.0)
		_check(sky.sun_elevation_degrees < -23, "North pole has winter polar night")
	sky.set_observer(Vector3.RIGHT)
	var clock: Dictionary = sky._clock_at(noon)
	_check(clock.day and absf(clock.local_seconds - 43200.0) < 300.0, "Local solar noon is around 12:00")
	_check(clock.remaining_seconds > 18000.0 and clock.remaining_seconds < 25200.0, "Daytime clock counts down to sunset")
	clock = sky._clock_at(noon + 43200.0)
	_check(not clock.day and (clock.local_seconds < 300.0 or clock.local_seconds > 86100.0), "Local midnight uses solar time, not system timezone")
	_check(clock.remaining_seconds > 18000.0 and clock.remaining_seconds < 25200.0, "Nighttime clock counts down to sunrise")
	var remaining: float = clock.remaining_seconds
	clock = sky._clock_at(noon + 43201.0)
	_check(absf(clock.remaining_seconds - remaining + 1.0) < 0.001, "Cached sunrise countdown advances with server time")
	sky.set_observer(Vector3.LEFT)
	_check(sky._clock_at(noon + 43200.0).day, "Opposite longitude changes the clock event")
	sky.set_observer(Vector3.UP)
	clock = sky._clock_at(june)
	_check(clock.day and clock.remaining_seconds == -1.0, "Polar day does not invent a sunset")
	clock = sky._clock_at(december)
	_check(not clock.day and clock.remaining_seconds == -1.0, "Polar night does not invent a sunrise")
	var hud := preload("res://scripts/player_hud.gd").new()
	hud.sky = sky
	root.add_child(hud)
	sky.set_observer(Vector3.RIGHT)
	sky.apply_solar(_metadata(sky, noon + 43200.0))
	hud._update_clock()
	_check(hud.clock_label.text.contains("Sunrise in "), "Night HUD shows remaining time to sunrise")
	sky.apply_solar(_metadata(sky, noon))
	hud._update_clock()
	_check(hud.clock_label.text.contains("Sunset in "), "Day HUD shows remaining time to sunset")
	if DisplayServer.get_name() != "headless":
		await _capture(world, sky, noon, hud)
	sky.clear_solar()
	_check(sky.clock_state().is_empty(), "Disconnected clock is unavailable rather than guessed")
	hud._update_clock()
	_check(hud.clock_label.text == tr("Time unavailable"), "HUD visibly handles missing server time")
	_check(sky._solar.is_empty() and not sky.material.get_shader_parameter("solar_enabled"), "Disconnect clears server clock")
	_check(sky.environment.fog_light_color.is_equal_approx(Color(0.72, 0.84, 0.85)), "Disconnect restores configured fog color")
	world.queue_free()
	hud.queue_free()
	await process_frame
	print("Day/night: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _capture(world: Node3D, sky: Node, noon: float, hud: CanvasLayer) -> void:
	var camera := Camera3D.new()
	camera.near = 0.01
	camera.far = 100.0
	world.add_child(camera)
	camera.make_current()
	sky.set_altitude(120.0)
	sky.set_observer(Vector3.RIGHT)
	var day_direction: Vector3 = sky.solar_direction(noon)
	TranslationServer.set_locale("cs")
	for dimensions in [Vector2i(1600, 900), Vector2i(640, 480), Vector2i(360, 640)]:
		root.get_window().size = dimensions
		var means := []
		for phase in ["day", "sunset", "night"]:
			hud.panel.show()
			var seconds := noon + (21600.0 if phase == "sunset" else (43200.0 if phase == "night" else 0.0))
			sky.apply_solar(_metadata(sky, seconds))
			hud._update_clock()
			var target: Vector3 = sky.sun_direction if phase == "sunset" else day_direction
			camera.look_at(target, Vector3.RIGHT)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/ishtaria-clock-%s-%dx%d.png" % [phase, dimensions.x, dimensions.y])
			_check(hud.panel.get_global_rect().encloses(hud.clock_label.get_global_rect()), "Clock fits inside HUD at " + str(dimensions))
			_check(hud.clock_label.size.y >= hud.clock_label.get_minimum_size().y, "Clock text is not clipped at " + str(dimensions))
			if phase == "night":
				_check(hud.clock_label.text.contains("Východ za "), "Night countdown is translated into Czech")
			hud.panel.hide()
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png("/tmp/ishtaria-%s-%dx%d.png" % [phase, dimensions.x, dimensions.y])
			var total := 0.0
			var samples := 0
			for row in range(0, dimensions.y, 8):
				for column in range(0, dimensions.x, 8):
					var luminance := image.get_pixel(column, row).get_luminance()
					total += luminance
					samples += 1
			means.append(total / samples)
			if phase == "day":
				var center: Color = image.get_pixel(dimensions.x / 2, dimensions.y / 2)
				_check(center.r > 0.9 and center.g > 0.8, "Visible solar disc renders at " + str(dimensions))
				var theta := 0.22163 * PI
				var phi := (0.91646 - 0.5) * TAU
				var baked_direction := Vector3(cos(theta), sin(theta) * cos(phi), -sin(theta) * sin(phi))
				var baked_pixel := camera.unproject_position(baked_direction * 10.0)
				if Rect2(Vector2.ZERO, Vector2(dimensions)).has_point(baked_pixel):
					_check(image.get_pixel(int(baked_pixel.x), int(baked_pixel.y)).get_luminance() < 0.95, "Baked duplicate sun is removed at " + str(dimensions))
		_check(means[0] > means[2] * 2.0 and means[0] > 0.1, "Native day and night differ at " + str(dimensions))