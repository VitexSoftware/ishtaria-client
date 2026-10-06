extends Node
## Background music of a place: it fades in as the player comes within hearing distance of the
## place and fades out when they leave. The server only lists the areas near the player; the
## distance is worked out here. Tracks are never cut: a track that is no longer wanted (another
## place, a conversation with its own music) keeps playing while it fades out, and the next one
## fades in beside it.

const MusicChannel := preload("res://scripts/music_channel.gd")

var story: Node
var enabled := true
## Level chosen in the settings (1.0 = default).
var volume := 1.0
## Set while a dialogue plays a different track of its own.
var suppressed := false
var fade_seconds := 3.0
var _channels: Dictionary = {}
var _wanted_url := ""
var _wanted_gain := 0.0
var _loop := true

## URL of the track that is wanted and already audible, "" otherwise.
var current_url: String:
	get:
		return _wanted_url if _channels.has(_wanted_url) else ""

## Level of the wanted track (0 when it is not playing).
var gain: float:
	get:
		return _channels[_wanted_url].gain if _channels.has(_wanted_url) else 0.0

## `area` is what the server announced for the place the player stands in (empty for none) with
## the fade `level` 0..1 for the player's distance.
func set_target(area: Dictionary, level: float) -> void:
	if area.is_empty():
		_wanted_url = ""
		_wanted_gain = 0.0
	elif not enabled or suppressed:
		_wanted_gain = 0.0
	else:
		_wanted_gain = clampf(level, 0.0, 1.0)
		if area.music.url != _wanted_url:
			_wanted_url = area.music.url
		_loop = area.music.loop
		if not _channels.has(_wanted_url) and story != null:
			story.fetch_media(_wanted_url)
	_apply_targets()

func media_ready(url: String, resource: Resource) -> void:
	if url != _wanted_url or not resource is AudioStream or _channels.has(url):
		return
	var channel := MusicChannel.new()
	channel.fade_seconds = fade_seconds
	channel.volume = volume
	add_child(channel)
	channel.start(resource, _loop, _wanted_gain, url)
	channel.finished.connect(_on_finished.bind(url))
	_channels[url] = channel

func _on_finished(url: String) -> void:
	var channel: Node = _channels.get(url)
	_channels.erase(url)
	if is_instance_valid(channel):
		channel.queue_free()

func _apply_targets() -> void:
	for url: String in _channels:
		var channel: Node = _channels[url]
		channel.volume = volume
		channel.target = _wanted_gain if url == _wanted_url else 0.0

## Hearing level for a distance: full inside 70 % of the radius, fading linearly to nothing at the edge.
static func level_for(distance_m: float, radius_m: float) -> float:
	if radius_m <= 0.0:
		return 0.0
	return clampf((radius_m - distance_m) / (radius_m * 0.3), 0.0, 1.0)
