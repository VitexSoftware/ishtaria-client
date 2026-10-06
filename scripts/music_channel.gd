extends Node
## One track of background music with its own level. The level only ever moves gradually
## (`fade_seconds` from silence to full), so a track is never cut off: it fades in when it
## starts and fades out to the end when it is no longer wanted, then the channel is done.

signal finished

var fade_seconds := 3.0
var base_db := -10.0
## Level chosen in the settings (1.0 = default, up to 2.0).
var volume := 1.0
## Level the track is heading to (0..1) and where it is now.
var target := 0.0
var gain := 0.0
var stream: AudioStream
var url := ""
## Remove the channel once the track has faded out (a retired channel).
var free_when_done := false
var _player: AudioStreamPlayer

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.volume_db = -80.0
	add_child(_player)

func playing() -> bool:
	return _player != null and _player.playing

## Starts a track from silence and fades it in to `to_gain`.
func start(resource: AudioStream, loop: bool, to_gain: float, source_url := "") -> void:
	if resource is AudioStreamOggVorbis:
		resource.loop = loop
	stream = resource
	url = source_url
	gain = 0.0
	target = clampf(to_gain, 0.0, 1.0)
	_player.stream = resource
	_player.volume_db = -80.0
	_player.play()

func fade_out() -> void:
	target = 0.0

## Immediately silent; only for an explicit "sound off" of the player.
func stop_now() -> void:
	target = 0.0
	gain = 0.0
	if _player != null:
		_player.stop()
	stream = null
	url = ""

func _process(delta: float) -> void:
	if _player == null:
		return
	gain = move_toward(gain, target, delta / maxf(fade_seconds, 0.05))
	_player.volume_db = -80.0 if gain <= 0.001 or volume <= 0.001 else base_db + linear_to_db(gain * clampf(volume, 0.0, 2.0))
	if gain <= 0.001 and target <= 0.0 and stream != null:
		_player.stop()
		stream = null
		url = ""
		finished.emit()
		if free_when_done:
			queue_free()
