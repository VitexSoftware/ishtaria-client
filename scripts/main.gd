extends Node3D
## Placeholder scene: renders a scaled planet and an orbit camera.
## Real terrain comes from ishtaria-worldgen via GDExtension (planned).

const PLANET_RADIUS := 6371.0 # scene units = km in this preview

var _camera: Camera3D
var _yaw := 0.0

func _ready() -> void:
	var planet := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = PLANET_RADIUS
	mesh.height = PLANET_RADIUS * 2.0
	mesh.radial_segments = 128
	mesh.rings = 64
	planet.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.45, 0.28)
	planet.material_override = mat
	add_child(planet)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	add_child(sun)

	_camera = Camera3D.new()
	_camera.far = PLANET_RADIUS * 10.0
	add_child(_camera)

	var label := Label.new()
	label.text = "Ishtaria – client preview (no server connection yet)"
	label.position = Vector2(16, 16)
	add_child(label)

func _process(delta: float) -> void:
	_yaw += delta * 0.1
	var dist := PLANET_RADIUS * 3.0
	_camera.position = Vector3(sin(_yaw), 0.3, cos(_yaw)) * dist
	_camera.look_at(Vector3.ZERO)
