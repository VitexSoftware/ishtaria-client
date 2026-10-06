extends RefCounted

const PACKS := ["protagonists", "retro", "survivors", "quaternius"]
const CHARACTERS := {
	"protagonists": [["criminalMaleA", "Criminal"], ["cyborgFemaleA", "Cyborg"], ["skaterFemaleA", "Skater A"], ["skaterMaleA", "Skater B"]],
	"retro": [["humanFemaleA", "Human A"], ["humanMaleA", "Human B"], ["zombieFemaleA", "Zombie A"], ["zombieMaleA", "Zombie B"]],
	"survivors": [["survivorFemaleA", "Survivor A"], ["survivorMaleB", "Survivor B"], ["zombieA", "Zombie C"], ["zombieC", "Zombie D"]],
	# Quaternius glTF characters: the name is the file in `assets/quaternius/characters/Models/`.
	"quaternius": [
		["adventurer", "Adventurer"], ["adventurer_woman", "Adventuress"], ["hooded_adventurer_woman", "Hooded Adventuress"],
		["character_animated", "Rogue"], ["hoodie_character", "Hoodie"], ["punk", "Punk"], ["punk_woman", "Punk Girl"],
		["animated_woman", "Casual Woman"], ["animated_woman_2", "Formal Woman"], ["suit_woman", "Woman in Suit"],
		["worker_woman", "Worker"], ["soldier_woman", "Soldier"], ["sci_fi_woman", "Sci-Fi Woman"], ["witch", "Witch"],
	],
}
const DEFAULT_CHARACTER := "retro/humanMaleA"
## What a new character is preselected as: a look no NPC wears.
const NEW_CHARACTER_DEFAULT := "protagonists/skaterMaleA"
## Looks worn by NPCs of the story datadisks: they stay valid for existing characters but are not
## offered to a new one, so no player is mistaken for a shopkeeper. (Faust has its own model.)
const NPC_RESERVED := ["protagonists/skaterFemaleA", "retro/humanFemaleA", "retro/humanMaleA", "survivors/survivorMaleB"]
const ROOT := "res://assets/kenney/characters/"
const QUATERNIUS_ROOT := "res://assets/quaternius/characters/Models/"
## The clips of the glTF characters that stand in for the idle and walking actions.
## Characters drawn larger than a person are scaled down to about 1.8 metres.
const QUATERNIUS_SCALES := {"character_animated": 0.67}
## The Kenney characters stand 3.76 units tall in the client for a person of 1.8 metres. A glTF
## character is authored in metres: this many units per metre make it as tall as the others.
const GLTF_UNITS_PER_METRE := 2.09
## Weapons the glTF characters come with. They hang beside the body in the idle and walking clips, and
## what a player holds is decided by the server's items, so they are not drawn.
const QUATERNIUS_HELD_ITEMS := ["Pistol", "Sword"]
const QUATERNIUS_CLIPS := {"idle": "Idle", "walk": "Run"}

static func is_valid(character: String) -> bool:
	var parts := character.split("/")
	if parts.size() != 2 or not CHARACTERS.has(parts[0]):
		return false
	for entry in CHARACTERS[parts[0]]:
		if entry[0] == parts[1]:
			return true
	return false

## The looks of a pack offered to a new character; `keep` (the current choice) is always listed.
static func selectable(pack: String, keep := "") -> Array:
	var out := []
	for entry in CHARACTERS.get(pack, []):
		var id: String = pack + "/" + entry[0]
		if not NPC_RESERVED.has(id) or id == keep:
			out.append(entry)
	return out

static func create_model(character: String) -> Node3D:
	if not is_valid(character):
		return null
	var parts := character.split("/")
	if parts[0] == "quaternius":
		return _create_gltf_model(parts[1])
	var source: PackedScene = load(ROOT + parts[0] + "/Model/characterMedium.fbx")
	var model := source.instantiate() as Node3D
	var skin: Texture2D = load(ROOT + parts[0] + "/Skins/" + parts[1] + ".png")
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var material := StandardMaterial3D.new()
		material.albedo_texture = skin
		material.roughness = 0.9
		mesh.material_override = material
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var library := AnimationLibrary.new()
		for action in ["idle", "walk"]:
			var path: String = ROOT + parts[0] + "/Animations/" + ("run" if action == "walk" else "idle") + ".fbx"
			if ResourceLoader.exists(path):
				_add_animation(model, skeletons[0], library, path, action)
		var player := AnimationPlayer.new()
		player.name = "CharacterAnimation"
		model.add_child(player)
		player.add_animation_library("", library)
		player.play("idle")
	return model

## A glTF character brings its own textures and clips: only the idle and walking actions are kept,
## looping, under the names the controls play.
static func _create_gltf_model(name: String) -> Node3D:
	var scene: PackedScene = load(QUATERNIUS_ROOT + name + ".glb")
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	var body := model.get_node_or_null("RootNode") as Node3D
	if body != null:
		body.scale *= QUATERNIUS_SCALES.get(name, 1.0) * GLTF_UNITS_PER_METRE
	for held in QUATERNIUS_HELD_ITEMS:
		for item in model.find_children(held + "*", "", true, false):
			item.get_parent().remove_child(item)
			item.free()
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return model
	var player: AnimationPlayer = players[0]
	var library := AnimationLibrary.new()
	for action: String in QUATERNIUS_CLIPS:
		var clip := "CharacterArmature|%s" % QUATERNIUS_CLIPS[action]
		if player.has_animation(clip):
			var animation: Animation = player.get_animation(clip).duplicate()
			animation.loop_mode = Animation.LOOP_LINEAR
			library.add_animation(action, animation)
	for existing in player.get_animation_library_list():
		player.remove_animation_library(existing)
	player.add_animation_library("", library)
	player.name = "CharacterAnimation"
	if library.has_animation("idle"):
		player.play("idle")
	return model

## Height of the top of the head in the model's own units (the models are not 1.8 units tall:
## the FBX root carries a 100x scale). Falls back to the mesh height without a head bone.
static func head_height(model: Node3D) -> float:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		# A model without a skeleton (a datadisk's glTF): the top of its meshes.
		var top := 0.0
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			# Every node between the mesh and the model scales it (a glTF root node often does).
			var local := mesh.transform
			var ancestor := mesh.get_parent()
			while ancestor != model and ancestor is Node3D:
				local = (ancestor as Node3D).transform * local
				ancestor = ancestor.get_parent()
			top = maxf(top, (local * mesh.get_aabb()).end.y)
		return top if top > 0.1 else 1.8
	var skeleton := skeletons[0] as Skeleton3D
	var bone := skeleton.find_bone("Head_end")
	# The glTF characters end at a "Head" bone in the neck: add the height of the head itself.
	var above_bone := 0.0
	if bone < 0:
		bone = skeleton.find_bone("Head")
		above_bone = 0.25
	if bone < 0:
		return 1.8
	var point := skeleton.get_bone_global_pose(bone).origin + Vector3(0, above_bone, 0)
	var node: Node = skeleton
	while node != model and node is Node3D:
		point = (node as Node3D).transform * point
		node = node.get_parent()
	return maxf(point.y, 0.1)

static func _add_animation(model: Node3D, skeleton: Skeleton3D, library: AnimationLibrary, path: String, action: String) -> void:
	var source: PackedScene = load(path)
	var root := source.instantiate()
	var sources := root.find_children("*", "AnimationPlayer", true, false)
	if not sources.is_empty():
		var imported: AnimationPlayer = sources[0]
		var names: Array = Array(imported.get_animation_list())
		names.sort_custom(func(first: String, second: String) -> bool: return imported.get_animation(first).length > imported.get_animation(second).length)
		for animation_name in names:
			if animation_name == "RESET":
				continue
			var animation: Animation = imported.get_animation(animation_name).duplicate()
			for track in range(animation.get_track_count() - 1, -1, -1):
				var bone := animation.track_get_path(track)
				if bone.get_subname_count() != 1 or skeleton.find_bone(bone.get_subname(0)) < 0:
					animation.remove_track(track)
				else:
					animation.track_set_path(track, NodePath("%s:%s" % [model.get_path_to(skeleton), bone.get_subname(0)]))
			animation.loop_mode = Animation.LOOP_LINEAR
			library.add_animation(action, animation)
			break
	root.free()