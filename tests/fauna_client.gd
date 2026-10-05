extends SceneTree

const ICONS := preload("res://scripts/item_icons.gd")

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _entry(id: String, model: String, position: Array) -> Dictionary:
	return {"id": id, "model": model, "position": position, "scale_m": 1.0, "yaw": 0.0, "collision_radius_m": 0.0, "biome": 4}

func _run() -> void:
	var environment := preload("res://scripts/surface_environment.gd").new()
	root.add_child(environment)
	var animals := 0
	var fish := 0
	for entry: Dictionary in environment.catalog:
		if entry.get("fauna", false):
			_check(entry.has("animation"), "%s has an animation" % entry.id)
			if entry.id.begins_with("fish."):
				fish += 1
				_check(entry.has("swim_radius_m"), "%s swims in circles" % entry.id)
				_check(not "mountain" in entry.biomes and not "grassland" in entry.biomes, "%s lives in water" % entry.id)
			else:
				animals += 1
				_check(not entry.has("swim_radius_m") and not "ocean" in entry.biomes, "%s stands on land" % entry.id)
	_check(animals == 12 and fish == 35, "12 animals and 35 fish in the catalog, found %d and %d" % [animals, fish])
	_check(environment.catalog.size() == 170 + 47, "the plant and rock catalog is unchanged")

	# An animal stands and plays its idle animation; a fish also circles.
	environment._place_object(_entry("cow-1", "animal.cow", [6371000.0, 0.0, 0.0]))
	environment._place_object(_entry("fish-1", "fish.koi", [6370995.0, 0.0, 0.0]))
	await process_frame
	var players := environment.objects.find_children("*", "AnimationPlayer", true, false)
	_check(players.size() == 2, "both models are animated")
	for player: AnimationPlayer in players:
		_check(player.is_playing() and player.current_animation.ends_with("Idle") or player.current_animation.ends_with("Swimming_Normal"), "an idle or swimming animation plays: " + player.current_animation)
		_check(player.get_animation(player.current_animation).loop_mode == Animation.LOOP_LINEAR, "the animation loops")
	_check(environment._swimmers.size() == 1, "only the fish circles")
	var swimmer: Node3D = environment._swimmers[0].node
	var before := swimmer.position
	await create_timer(0.3).timeout
	environment._swim()
	_check(swimmer.position.distance_to(before) > 0.0, "the fish moved")
	var radius: float = environment._swimmers[0].radius
	_check(absf(Vector2(swimmer.position.x, swimmer.position.z).length() - radius) < 0.001, "the fish stays on its circle")
	# Two animals with different identities do not move in step.
	environment._place_object(_entry("cow-2", "animal.cow", [6371001.0, 0.0, 0.0]))
	var cows := environment.objects.find_children("*", "AnimationPlayer", true, false).filter(func(p: AnimationPlayer) -> bool: return p.current_animation.ends_with("Idle"))
	_check(cows.size() == 2 and not is_equal_approx(cows[0].current_animation_position, cows[1].current_animation_position), "animals start at different moments")
	environment._clear_objects()
	_check(environment._swimmers.is_empty(), "clearing the region forgets the fish")

	# Every animal and fish item has an icon and a bundled model.
	var baker: Dictionary = load("res://tools/bake-item-icons.gd").get_script_constant_map()
	_check(baker.ANIMAL_ITEMS.size() == 12 and baker.FISH_ITEMS.size() == 35, "item lists of the baker")
	for id: String in baker.ANIMAL_ITEMS + baker.FISH_ITEMS:
		_check(ICONS.texture(id) != null, "icon for " + id)
	if _failures > 0:
		push_error("%d fauna client checks failed" % _failures)
	else:
		print("Fauna client checks passed")
	quit(1 if _failures > 0 else 0)
