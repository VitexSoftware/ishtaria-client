extends SceneTree
## Renders inventory item icons from the bundled Kenney 3D models.
## Run natively (it needs a GPU renderer):
##   godot4 --path . --script res://tools/bake-item-icons.gd
## Then import the new PNGs: godot4 --headless --path . --editor --import

const MODELS := "res://assets/kenney/survival-kit/Models/GLB format/"
const ANIMAL_MODELS := "res://assets/quaternius/animated-animal-pack/Models/"
const FISH_MODELS := "res://assets/quaternius/animated-fish-bundle/Models/"
const RPG_MODELS := "res://assets/quaternius/ultimate-rpg-items/Models/"
const OUTPUT := "res://assets/icons/items/"
const UI_OUTPUT := "res://assets/icons/ui/"
const GRAVEYARD := "res://assets/kenney/graveyard-kit/"
const SIZE := 128
const WOODS := {
	"pine": Color("c49a63"),
	"oak": Color("9a7348"),
	"palm": Color("d6b878"),
	"birch": Color("e4dccb"),
}
## Items from the Quaternius Ultimate RPG Items Bundle: the item id is the model name.
const RPG_ITEMS := [
	"armor_golden",
	"armor_leather",
	"armor_metal",
	"arrow",
	"axe_double",
	"axe_small",
	"backpack",
	"bag",
	"bone",
	"open_book",
	"open_book_2",
	"open_book_3",
	"open_book_4",
	"book",
	"book_2",
	"book_3",
	"chalice",
	"chest",
	"claymore",
	"coin_pouch",
	"crown",
	"dagger",
	"doublesided_hammer",
	"fish_bone",
	"glove",
	"gold_ingots",
	"key",
	"key_2",
	"key_3",
	"key_4",
	"knife",
	"mineral",
	"necklace",
	"necklace_2",
	"padlock",
	"parchment",
	"potion_bottle",
	"potion_bottle_2",
	"scroll",
	"scythe",
	"shield_celtic_golden",
	"shield_heater",
	"shield_heater_2",
	"shield_round",
	"shield_round_2",
	"skull_coin",
	"skull",
	"skull_2",
	"snowflake",
	"spear",
	"star_coin",
	"sword",
	"sword_2",
	"wooden_bow",
]
## Whole animals and fish as items: `animal_<name>` and `fish_<name>` show the animated model.
const ANIMAL_ITEMS := [
	"animal_fox",
	"animal_shiba_inu",
	"animal_husky",
	"animal_wolf",
	"animal_alpaca",
	"animal_deer",
	"animal_stag",
	"animal_donkey",
	"animal_horse",
	"animal_white_horse",
	"animal_cow",
	"animal_bull",
]
const FISH_ITEMS := [
	"fish_anglerfish",
	"fish_armored_catfish",
	"fish_betta",
	"fish_black_lion_fish",
	"fish_blobfish",
	"fish_blue_goldfish",
	"fish_blue_tang",
	"fish_butterfly_fish",
	"fish_cardinal_fish",
	"fish_clownfish",
	"fish_coral_grouper",
	"fish_cowfish",
	"fish_flatfish",
	"fish_flower_horn",
	"fish_goblin_shark",
	"fish_goldfish",
	"fish_humphead",
	"fish_koi",
	"fish_lionfish",
	"fish_mandarin_fish",
	"fish_moorish_idol",
	"fish_parrot_fish",
	"fish_piranha",
	"fish_puffer",
	"fish_red_snapper",
	"fish_royal_gramma",
	"fish_shark",
	"fish_sunfish",
	"fish_swordfish",
	"fish_tang",
	"fish_tetra",
	"fish_tuna",
	"fish_turbot",
	"fish_yellow_tang",
	"fish_zebra_clown_fish",
]
## Icons of the interface rather than of items, rendered into `assets/icons/ui/`.
const UI_ICONS := {
	"headstone": {"model": "gravestone-round", "dir": GRAVEYARD, "ui": true},
}
## Icons that reuse another model: the gold coin item shows the coin model.
const RPG_ALIASES := {"gold": "coin"}
const ICONS := {
	"axe": {"model": "tool-axe"},
	"pickaxe": {"model": "tool-pickaxe"},
	"stone": {"model": "resource-stone", "tint": Color("9b9ca0")},
	"stone_block": {"model": "resource-stone-large", "tint": Color("b4b5b9")},
	"iron_ore": {"model": "rock-c", "tint": Color("8a6f66")},
	"copper_ore": {"model": "rock-c", "tint": Color("d9894a")},
	"quartz_crystal": {"model": "rock-c", "tint": Color("bfe6f2")},
}

func _initialize() -> void:
	_run.call_deferred()

func _icons() -> Dictionary:
	var icons := ICONS.duplicate()
	for wood: String in WOODS:
		icons[wood + "_log"] = {"model": "tree-log", "tint": WOODS[wood]}
		icons[wood + "_wood"] = {"model": "resource-wood", "tint": WOODS[wood]}
		icons[wood + "_plank"] = {"model": "resource-planks", "tint": WOODS[wood]}
	for id: String in RPG_ITEMS:
		icons[id] = {"model": id, "rpg": true}
	for id: String in ANIMAL_ITEMS:
		icons[id] = {"model": id.trim_prefix("animal_"), "dir": ANIMAL_MODELS, "animation": "Idle"}
	for id: String in FISH_ITEMS:
		icons[id] = {"model": id.trim_prefix("fish_"), "dir": FISH_MODELS, "animation": "Swimming_Normal"}
	for id: String in UI_ICONS:
		icons[id] = UI_ICONS[id]
	for id: String in RPG_ALIASES:
		icons[id] = {"model": RPG_ALIASES[id], "rpg": true}
	return icons

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UI_OUTPUT))
	var failures := 0
	var icons := _icons()
	for id: String in icons:
		if not await _bake(id, icons[id]):
			failures += 1
	print("Baked %d icons, %d failed" % [icons.size() - failures, failures])
	quit(1 if failures > 0 else 0)

func _bake(id: String, spec: Dictionary) -> bool:
	var directory: String = spec.get("dir", RPG_MODELS if spec.get("rpg", false) else MODELS)
	var scene: PackedScene = load(directory + spec.model + ".glb")
	if scene == null:
		push_error("Missing model for " + id)
		return false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var model: Node3D = scene.instantiate()
	viewport.add_child(model)
	if spec.has("tint"):
		_tint(model, spec.tint)
	if spec.has("animation"):
		_pose(model, spec.animation)
		for i in 2:
			await process_frame
	var bounds := _bounds(model)
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 0.001)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 35, 0)
	light.light_energy = 1.1
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = radius * 2.15
	viewport.add_child(camera)
	var direction := Vector3(1.0, 0.8, 1.0).normalized()
	camera.look_at_from_position(center + direction * radius * 4.0, center, Vector3.UP)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if spec.has("animation") or spec.get("ui", false):
		image = _fit(image)
	var error := image.save_png((UI_OUTPUT if spec.get("ui", false) else OUTPUT) + id + ".png")
	viewport.queue_free()
	if error != OK:
		push_error("Cannot save " + id)
		return false
	return true

## Crops an image to what is drawn and centres it in a square with a small margin; skeletons
## include bones far from the body, so the camera framing alone is not reliable for animals.
func _fit(image: Image) -> Image:
	var used := image.get_used_rect()
	if used.size.x == 0 or used.size.y == 0:
		return image
	var side := int(maxi(used.size.x, used.size.y) * 1.1) + 2
	var fitted := Image.create(side, side, false, Image.FORMAT_RGBA8)
	fitted.blit_rect(image, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
	fitted.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return fitted

func _tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh: MeshInstance3D = node
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material is StandardMaterial3D:
				var tinted: StandardMaterial3D = material.duplicate()
				# A flat colour replaces the warm palette texture so the tint is not muddied.
				tinted.albedo_texture = null
				tinted.albedo_color = color
				mesh.set_surface_override_material(surface, tinted)
	for child in node.get_children():
		_tint(child, color)

## Starts an animation and moves it a little way in, so the icon shows a living pose.
func _pose(model: Node, animation_name: String) -> void:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player: AnimationPlayer = players[0]
	for candidate in player.get_animation_list():
		if candidate == animation_name or candidate.ends_with("|" + animation_name):
			player.play(candidate)
			player.seek(0.4, true)
			player.pause()
			return

func _bounds(node: Node3D) -> AABB:
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		# Skinned meshes report their unposed size; the bones give the real extent.
		var skeleton: Skeleton3D = skeletons[0]
		var box := AABB(skeleton.global_transform * skeleton.get_bone_global_pose(0).origin, Vector3.ZERO)
		for bone in skeleton.get_bone_count():
			box = box.expand(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)
		return box.grow(box.size.length() * 0.12)
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		var box := mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
