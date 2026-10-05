extends Node

const SOUNDS := {
	"click": preload("res://assets/kenney/interface-sounds/Audio/click_001.ogg"),
	"confirmation": preload("res://assets/kenney/interface-sounds/Audio/confirmation_001.ogg"),
	"error": preload("res://assets/kenney/interface-sounds/Audio/error_001.ogg"),
	"back": preload("res://assets/kenney/interface-sounds/Audio/back_001.ogg"),
}

const MIX_RATE := 22050

var enabled := true
var players: Dictionary = {}

func _ready() -> void:
	for sound in SOUNDS:
		var player := AudioStreamPlayer.new()
		player.stream = SOUNDS[sound]
		player.volume_db = -14.0
		player.max_polyphony = 2
		add_child(player)
		players[sound] = player
	var fanfare := AudioStreamPlayer.new()
	fanfare.stream = make_fanfare()
	fanfare.volume_db = -9.0
	add_child(fanfare)
	players["fanfare"] = fanfare

## A short original fanfare for a new level, synthesised from sine waves: a rising
## arpeggio of C major that ends in a held chord. No recording is needed.
static func make_fanfare() -> AudioStreamWAV:
	var notes := [[523.25, 0.0, 0.14], [659.25, 0.14, 0.14], [783.99, 0.28, 0.14], [1046.5, 0.42, 0.9], [783.99, 0.42, 0.9], [659.25, 0.42, 0.9]]
	var seconds := 1.4
	var count := int(MIX_RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for note: Array in notes:
		var start := int(note[1] * MIX_RATE)
		var length := int(note[2] * MIX_RATE)
		for i in length:
			if start + i >= count:
				break
			var t := float(i) / MIX_RATE
			var attack := minf(1.0, t / 0.01)
			var release := minf(1.0, float(length - i) / (MIX_RATE * 0.12))
			var tone := sin(TAU * note[0] * t) + 0.5 * sin(TAU * 2.0 * note[0] * t) + 0.25 * sin(TAU * 3.0 * note[0] * t)
			samples[start + i] += tone * attack * release * 0.22
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream

func play(sound: String) -> void:
	if enabled and players.has(sound):
		players[sound].play()

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		for player in players.values():
			player.stop()

func _exit_tree() -> void:
	for player in players.values():
		player.stop()