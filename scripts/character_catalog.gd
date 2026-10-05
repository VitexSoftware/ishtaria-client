extends RefCounted

const PACKS := ["protagonists", "retro", "survivors"]
const CHARACTERS := {
	"protagonists": [["criminalMaleA", "Criminal"], ["cyborgFemaleA", "Cyborg"], ["skaterFemaleA", "Skater A"], ["skaterMaleA", "Skater B"]],
	"retro": [["humanFemaleA", "Human A"], ["humanMaleA", "Human B"], ["zombieFemaleA", "Zombie A"], ["zombieMaleA", "Zombie B"]],
	"survivors": [["survivorFemaleA", "Survivor A"], ["survivorMaleB", "Survivor B"], ["zombieA", "Zombie C"], ["zombieC", "Zombie D"]],
}
const DEFAULT_CHARACTER := "retro/humanMaleA"
const ROOT := "res://assets/kenney/characters/"

static func is_valid(character: String) -> bool:
	var parts := character.split("/")
	if parts.size() != 2 or not CHARACTERS.has(parts[0]):
		return false
	for entry in CHARACTERS[parts[0]]:
		if entry[0] == parts[1]:
			return true
	return false

static func create_model(character: String) -> Node3D:
	if not is_valid(character):
		return null
	var parts := character.split("/")
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