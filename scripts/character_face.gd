extends Node
## Blinks and talks with the blend shapes of a character mesh named in the VRChat way:
## `vrc_blink` closes the eyes, the `vrc_v_*` visemes shape the mouth. A model without them is left
## alone (`setup` returns false). While `talking` is set the mouth keeps changing between the open
## vowels, which is all a dialogue needs; it needs no lip-sync data.

const BLINK_SECONDS := 0.16
const BLINK_PAUSE := Vector2(2.0, 6.0)
## The visemes the mouth moves between while talking (suffixes of the blend shape names).
const MOUTH := ["aa", "oh", "ee", "ou", "ih", "dd", "ch"]
## Pause between mouth shapes while talking, in seconds.
const SYLLABLE := Vector2(0.09, 0.19)

var talking := false

var _eyes: Array = []
var _mouth: Array = []
var _blink_left := 0.0
var _blink_pause := 3.0
var _syllable_left := 0.0
var _shape := -1
var _target := 0.0
var _openness := 0.0
var _rng := RandomNumberGenerator.new()

## Finds the blend shapes of the model. True when it has any to move.
func setup(model: Node) -> bool:
	_eyes.clear()
	_mouth.clear()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for index in mesh.get_blend_shape_count():
			var shape := String(mesh.mesh.get_blend_shape_name(index)).to_lower()
			if shape.ends_with("vrc_blink"):
				_eyes.append([mesh, index])
			for vowel: String in MOUTH:
				if shape.ends_with("vrc_v_" + vowel):
					_mouth.append([mesh, index, vowel])
	_rng.randomize()
	_blink_pause = _rng.randf_range(BLINK_PAUSE.x, BLINK_PAUSE.y)
	set_process(not _eyes.is_empty() or not _mouth.is_empty())
	return is_processing()

func _process(delta: float) -> void:
	_blink(delta)
	_speak(delta)

func _blink(delta: float) -> void:
	if _eyes.is_empty():
		return
	if _blink_left > 0.0:
		_blink_left = maxf(_blink_left - delta, 0.0)
	else:
		_blink_pause -= delta
		if _blink_pause <= 0.0:
			_blink_left = BLINK_SECONDS
			_blink_pause = _rng.randf_range(BLINK_PAUSE.x, BLINK_PAUSE.y)
	# The lids close and open again along a half sine.
	var closed := sin(PI * (1.0 - _blink_left / BLINK_SECONDS)) if _blink_left > 0.0 else 0.0
	for eye: Array in _eyes:
		(eye[0] as MeshInstance3D).set_blend_shape_value(eye[1], closed)

func _speak(delta: float) -> void:
	if _mouth.is_empty():
		return
	if talking:
		_syllable_left -= delta
		if _syllable_left <= 0.0:
			_syllable_left = _rng.randf_range(SYLLABLE.x, SYLLABLE.y)
			var next := _rng.randi_range(0, MOUTH.size() - 1)
			_shape = next if next != _shape else (next + 1) % MOUTH.size()
			_target = _rng.randf_range(0.45, 1.0)
	else:
		_target = 0.0
	# The mouth moves towards its target a little slower than a frame, so that it neither snaps
	# open nor shut; when talking stops it closes on the shape it had.
	_openness = move_toward(_openness, _target, delta * 9.0)
	for entry: Array in _mouth:
		var active: bool = _shape >= 0 and entry[2] == MOUTH[_shape]
		(entry[0] as MeshInstance3D).set_blend_shape_value(entry[1], _openness if active else 0.0)
