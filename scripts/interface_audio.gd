extends Node

const SOUNDS := {
	"click": preload("res://assets/kenney/interface-sounds/Audio/click_001.ogg"),
	"confirmation": preload("res://assets/kenney/interface-sounds/Audio/confirmation_001.ogg"),
	"error": preload("res://assets/kenney/interface-sounds/Audio/error_001.ogg"),
	"back": preload("res://assets/kenney/interface-sounds/Audio/back_001.ogg"),
}

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