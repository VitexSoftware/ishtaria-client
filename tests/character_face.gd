extends SceneTree

const FACE := preload("res://scripts/character_face.gd")
const STORY := preload("res://scripts/story_client.gd")
const FAUST := "res://../ishtaria-datadisk-endland/media/models/faust.glb"

var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)

## A mesh with the VRChat blend shapes: one triangle, every shape moves it.
func _face_mesh(names: Array) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for shape: String in names:
		mesh.add_blend_shape(shape)
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var shapes: Array = []
	for shape in names:
		var target := []
		target.resize(Mesh.ARRAY_MAX)
		target[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
		shapes.append(target)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance

func _value(instance: MeshInstance3D, shape: String) -> float:
	for index in instance.get_blend_shape_count():
		if String(instance.mesh.get_blend_shape_name(index)).ends_with(shape):
			return instance.get_blend_shape_value(index)
	return -1.0

func _run() -> void:
	var model := Node3D.new()
	var head := _face_mesh(["blendShape2.vrc_blink", "blendShape3.vrc_v_aa", "blendShape5.vrc_v_oh", "blendShape6.vrc_v_ee", "other.sil"])
	model.add_child(head)
	root.add_child(model)
	var face := FACE.new()
	model.add_child(face)
	_check(face.setup(model), "A model with blend shapes gets a face")
	# Blinking: over a few seconds the eyes close fully at least once and open again.
	var closed_max := 0.0
	var open_after := false
	for step in 900:
		face._process(1.0 / 60.0)
		var blink := _value(head, "vrc_blink")
		closed_max = maxf(closed_max, blink)
		open_after = open_after or (closed_max > 0.9 and blink == 0.0)
	_check(closed_max > 0.95 and open_after, "The eyes blink and open again within fifteen seconds")
	# Quiet: nothing of the mouth moves.
	for step in 30:
		face._process(1.0 / 60.0)
	_check(_value(head, "vrc_v_aa") == 0.0 and _value(head, "vrc_v_oh") == 0.0 and _value(head, "vrc_v_ee") == 0.0, "The mouth stays shut while the character is silent")
	# Talking: vowels open one at a time, several different ones, and the mouth closes afterwards.
	face.talking = true
	var seen := {}
	var most_open := 0.0
	for step in 240:
		face._process(1.0 / 60.0)
		var open_now := 0
		for shape in ["vrc_v_aa", "vrc_v_oh", "vrc_v_ee"]:
			var weight := _value(head, shape)
			if weight > 0.05:
				seen[shape] = true
				open_now += 1
				most_open = maxf(most_open, weight)
		_check(open_now <= 1 or step < 3, "Only one mouth shape is open at a time")
	_check(seen.size() >= 2 and most_open > 0.4 and most_open <= 1.0, "The mouth changes between vowels while talking")
	face.talking = false
	for step in 60:
		face._process(1.0 / 60.0)
	_check(_value(head, "vrc_v_aa") == 0.0 and _value(head, "vrc_v_oh") == 0.0 and _value(head, "vrc_v_ee") == 0.0, "The mouth closes when the character stops talking")
	# A model without such shapes is left alone.
	var plain := Node3D.new()
	plain.add_child(_face_mesh(["something_else"]))
	var other := FACE.new()
	plain.add_child(other)
	_check(not other.setup(plain) and not other.is_processing(), "A model without eye and mouth shapes gets no face")
	model.free()
	plain.free()
	# The real Faust of the End Land disk, when it is next to this repository.
	var path := ProjectSettings.globalize_path("res://").path_join("../ishtaria-datadisk-endland/media/models/faust.glb").simplify_path()
	if FileAccess.file_exists(path):
		var scene := STORY.decode_model(FileAccess.get_file_as_bytes(path))
		_check(scene != null, "Faust loads like a downloaded model")
		if scene != null:
			var faust := scene.instantiate() as Node3D
			root.add_child(faust)
			var faust_face := FACE.new()
			faust.add_child(faust_face)
			_check(faust_face.setup(faust), "Faust has blend shapes for the eyes and the mouth")
			faust_face.talking = true
			var opened := false
			for step in 120:
				faust_face._process(1.0 / 60.0)
				for mesh: MeshInstance3D in faust.find_children("*", "MeshInstance3D", true, false):
					for index in mesh.get_blend_shape_count():
						opened = opened or mesh.get_blend_shape_value(index) > 0.3
			_check(opened, "Faust's blend shapes move while he talks")
			faust.free()
	print("Character face: %s checks, %s failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
