extends Node

const SURFACE_SKIES := ["day", "morning", "night", "alien", "space"]
const SPACE_SKIES := ["band", "dark", "day", "galaxy", "nebula"]
const DEFAULTS := {
	"skybox": "day", "space_skybox": "galaxy",
	"sun_color": [1.0, 0.95, 0.85], "sun_energy": 1.2,
	"ambient_color": [0.7, 0.78, 0.84], "ambient_energy": 0.45,
	"fog_color": [0.72, 0.84, 0.85], "fog_density": 0.000025,
	"sky_energy": 1.0,
}

var sun: DirectionalLight3D
var environment: Environment
var material: ShaderMaterial
var surface_blend := 0.0
var _settings: Dictionary = {}
var sun_direction := Vector3.RIGHT
var sun_elevation_degrees := 90.0
var daylight := 1.0
var _solar: Dictionary = {}
var _sync_ticks := 0
var _observer := Vector3.UP
var _altitude_m := 0.0
var _clock_checked := -INF
var _clock_observer := Vector3.ZERO
var _clock_day := false
var _clock_transition := -1.0

func _ready() -> void:
	environment = load("res://assets/kenney/basic-scene/scenes/main-environment.tres").duplicate(true)
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	material = ShaderMaterial.new()
	material.shader = preload("res://scripts/planet_sky.gdshader")
	environment.sky.sky_material = material
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	apply_atmosphere({})

func apply_atmosphere(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var settings := DEFAULTS.duplicate(true)
	settings.merge(data, true)
	if not settings.skybox in SURFACE_SKIES or not settings.space_skybox in SPACE_SKIES:
		return false
	for key in ["sun_color", "ambient_color", "fog_color"]:
		var values: Variant = settings[key]
		if not values is Array or values.size() != 3:
			return false
		for value in values:
			if not (value is float or value is int) or not is_finite(float(value)) or value < 0.0 or value > 1.0:
				return false
	for key in ["sun_energy", "ambient_energy", "sky_energy", "fog_density"]:
		var value: Variant = settings[key]
		var maximum := 0.02 if key == "fog_density" else (16.0 if key == "sun_energy" else 8.0)
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0.0 or value > maximum:
			return false
	if settings == _settings:
		return true
	_settings = settings
	material.set_shader_parameter("orbit_panorama", load("res://assets/kenney/skyboxes-space/Skyboxes/skybox-space-%s.png" % settings.space_skybox))
	material.set_shader_parameter("surface_panorama", load("res://assets/kenney/skyboxes/Skyboxes/skybox-%s.png" % settings.skybox))
	material.set_shader_parameter("surface_energy", settings.sky_energy)
	material.set_shader_parameter("night_panorama", load("res://assets/kenney/skyboxes/Skyboxes/skybox-night.png"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = _color(settings.ambient_color)
	environment.ambient_light_energy = settings.ambient_energy
	environment.fog_light_color = _color(settings.fog_color)
	environment.fog_density = settings.fog_density
	if is_instance_valid(sun):
		sun.light_color = _color(settings.sun_color)
		sun.light_energy = settings.sun_energy
	if not _solar.is_empty():
		_update_solar(_solar.unix_seconds + (Time.get_ticks_msec() - _sync_ticks) / 1000.0)
	return true

func apply_solar(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1:
		return false
	for key in ["unix_seconds", "sidereal_day_seconds", "angular_radius_degrees"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	if data.unix_seconds < 0 or data.unix_seconds > 7258118400 or absf(data.sidereal_day_seconds - 86164.0905) > 0.001 or data.angular_radius_degrees < 0.26 or data.angular_radius_degrees > 0.28:
		return false
	var values: Variant = data.get("direction")
	if not values is Array or values.size() != 3:
		return false
	for value: Variant in values:
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	var direction := Vector3(values[0], values[1], values[2])
	if absf(direction.length() - 1.0) > 0.0001 or direction.distance_to(solar_direction(data.unix_seconds)) > 0.0001:
		return false
	_solar = data.duplicate(true)
	_sync_ticks = Time.get_ticks_msec()
	material.set_shader_parameter("solar_enabled", true)
	material.set_shader_parameter("sun_radius", deg_to_rad(data.angular_radius_degrees))
	_update_solar(data.unix_seconds)
	return true

func clear_solar() -> void:
	_solar.clear()
	_clock_checked = -INF
	material.set_shader_parameter("solar_enabled", false)
	var settings := _settings.duplicate(true)
	_settings.clear()
	apply_atmosphere(settings)
	if is_instance_valid(sun):
		sun.light_color = _color(_settings.sun_color)
		sun.light_energy = _settings.sun_energy
		sun.rotation_degrees = Vector3(-35, 40, 0)
	environment.ambient_light_energy = _settings.ambient_energy

func solar_direction(seconds: float) -> Vector3:
	var days := seconds / 86400.0 + 2440587.5 - 2451545.0
	var anomaly := deg_to_rad(fposmod(357.528 + 0.9856003 * days, 360.0))
	var longitude := deg_to_rad(fposmod(280.460 + 0.9856474 * days + 1.915 * sin(anomaly) + 0.020 * sin(2.0 * anomaly), 360.0))
	var obliquity := deg_to_rad(23.439 - 0.0000004 * days)
	var ascension := atan2(cos(obliquity) * sin(longitude), cos(longitude))
	var declination := asin(sin(obliquity) * sin(longitude))
	var sidereal := deg_to_rad(fposmod(280.46061837 + 360.98564736629 * days, 360.0))
	return Vector3(cos(declination) * cos(ascension - sidereal), sin(declination), cos(declination) * sin(ascension - sidereal))

func clock_state() -> Dictionary:
	if _solar.is_empty():
		return {}
	return _clock_at(_solar.unix_seconds + (Time.get_ticks_msec() - _sync_ticks) / 1000.0)

func _clock_at(seconds: float) -> Dictionary:
	var direction := solar_direction(seconds)
	var hour_angle := atan2(_observer.z, _observer.x) - atan2(direction.z, direction.x)
	var local_seconds := fposmod(43200.0 + hour_angle * 86400.0 / TAU, 86400.0)
	var threshold := sin(deg_to_rad(-0.833))
	var is_day := _observer.dot(direction) >= threshold
	if seconds < _clock_checked or seconds - _clock_checked >= 60.0 or _observer.distance_to(_clock_observer) > 0.0001 or is_day != _clock_day:
		_clock_checked = seconds
		_clock_observer = _observer
		_clock_day = is_day
		_clock_transition = -1.0
		for step in range(1, 289):
			var end := seconds + step * 300.0
			if (_observer.dot(solar_direction(end)) >= threshold) == is_day:
				continue
			var beginning := end - 300.0
			for iteration in 20:
				var middle := (beginning + end) * 0.5
				if (_observer.dot(solar_direction(middle)) >= threshold) == is_day:
					beginning = middle
				else:
					end = middle
			_clock_transition = end
			break
	return {"local_seconds": local_seconds, "day": is_day, "remaining_seconds": maxf(0.0, _clock_transition - seconds) if _clock_transition >= 0.0 else -1.0}

func set_observer(direction: Vector3) -> void:
	_observer = direction.normalized() if direction != Vector3.ZERO else Vector3.UP
	material.set_shader_parameter("local_up", _observer)
	if not _solar.is_empty():
		_update_solar(_solar.unix_seconds + (Time.get_ticks_msec() - _sync_ticks) / 1000.0)

func _process(_delta: float) -> void:
	if not _solar.is_empty():
		_update_solar(_solar.unix_seconds + (Time.get_ticks_msec() - _sync_ticks) / 1000.0)

func _update_solar(seconds: float) -> void:
	sun_direction = solar_direction(seconds)
	sun_elevation_degrees = rad_to_deg(asin(clampf(_observer.dot(sun_direction), -1.0, 1.0)))
	daylight = smoothstep(-6.0, 6.0, sun_elevation_degrees)
	material.set_shader_parameter("sun_direction", sun_direction)
	material.set_shader_parameter("daylight", daylight)
	material.set_shader_parameter("sun_elevation", sun_elevation_degrees)
	var anomaly := deg_to_rad(fposmod(357.528 + 0.9856003 * (seconds / 86400.0 + 2440587.5 - 2451545.0), 360.0))
	var distance_au := 1.00014 - 0.01671 * cos(anomaly) - 0.00014 * cos(2.0 * anomaly)
	material.set_shader_parameter("sun_radius", deg_to_rad(0.2666 / distance_au))
	material.set_shader_parameter("sidereal_angle", deg_to_rad(fposmod(280.46061837 + 360.98564736629 * (seconds / 86400.0 + 2440587.5 - 2451545.0), 360.0)))
	var warmth := smoothstep(0.0, 15.0, sun_elevation_degrees)
	var color := Color(1.0, 0.38, 0.12).lerp(_color(_settings.sun_color), warmth)
	material.set_shader_parameter("sun_color", color)
	environment.ambient_light_energy = _settings.ambient_energy * lerpf(0.012, lerpf(0.012, 1.0, daylight), surface_blend)
	environment.fog_light_color = Color(0.008, 0.012, 0.022).lerp(_color(_settings.fog_color), daylight)
	if is_instance_valid(sun):
		var reference := Vector3.UP if absf(sun_direction.y) < 0.99 else Vector3.RIGHT
		sun.basis = Basis.looking_at(-sun_direction, reference)
		sun.light_color = _color(_settings.sun_color).lerp(color, surface_blend)
		sun.light_energy = _settings.sun_energy * lerpf(1.0, smoothstep(-0.833, 1.0, sun_elevation_degrees), surface_blend)

func _color(values: Array) -> Color:
	return Color(values[0], values[1], values[2])

func set_altitude(altitude_m: float, local_view := false) -> void:
	_altitude_m = maxf(0.0, altitude_m)
	surface_blend = 1.0 - smoothstep(8000.0, 30000.0, altitude_m)
	material.set_shader_parameter("surface_blend", surface_blend)
	material.set_shader_parameter("horizon_dip", acos(6371000.0 / (6371000.0 + _altitude_m)))
	environment.fog_enabled = local_view and float(_settings.fog_density) > 0.0