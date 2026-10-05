extends SceneTree

func _initialize() -> void:
	_export.call_deferred()

func _export() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Expected output JSON path")
		quit(1)
		return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world_objects.json"))
	var models := {}
	for entry: Dictionary in catalog.objects:
		var model: Node3D = load(entry.scene).instantiate()
		root.add_child(model)
		var vertices := []
		var triangles := []
		for instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var transform := model.global_transform.affine_inverse() * instance.global_transform
			for surface in instance.mesh.get_surface_count():
				var arrays := instance.mesh.surface_get_arrays(surface)
				var offset := vertices.size()
				for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					var point := transform * vertex
					vertices.append([point.x, point.y, point.z])
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for index in arrays[Mesh.ARRAY_VERTEX].size():
						indices.append(index)
				for index in range(0, indices.size(), 3):
					triangles.append([offset + indices[index], offset + indices[index + 1], offset + indices[index + 2]])
		models[entry.id] = {"vertices": vertices, "triangles": triangles}
		model.free()
	var output := FileAccess.open(arguments[0], FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify(models) + "\n")
	output.close()
	print("Exported %d original object collision meshes" % models.size())
	quit()