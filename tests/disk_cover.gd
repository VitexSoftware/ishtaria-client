extends SceneTree

const COVER := preload("res://scripts/disk_cover.gd")
const DISK_COVER_FILE := "res://../ishtaria-datadisk-endland/media/cover/untitled_artwork-1e124.jpg"

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _run() -> void:
	_check(COVER.valid_cover_url("/story/media/endland/media/cover/untitled_artwork-1e124.jpg"), "a disk cover path is accepted")
	for bad: Variant in ["http://evil/x.jpg", "/story/media/../x.jpg", "/story/media/a//b.jpg", "/story/media/a/b.jpg?x=1", "/story/media/a/b.ogg", "/world/heightmap.png", 5, null]:
		_check(not COVER.valid_cover_url(bad), "rejected: %s" % str(bad))
	var announced := [
		{"id": "endland", "version": "0.5.0", "name": "The End Land", "cover": "/story/media/endland/media/cover/untitled_artwork-1e124.jpg"},
		{"id": "plain", "version": "1.0.0", "name": "No cover", "cover": null},
		{"id": "bad", "version": "1.0.0", "name": "Bad", "cover": "/etc/passwd"},
		"junk",
	]
	var covered: Array = COVER.covered_disks(announced)
	_check(covered.size() == 1 and covered[0].id == "endland", "only well-formed covers are queued")
	_check(COVER.covered_disks("nope").is_empty() and COVER.covered_disks(null).is_empty(), "a missing or malformed list shows nothing")

	var cover := COVER.new()
	root.add_child(cover)
	await process_frame
	cover.present("http://127.0.0.1:1", [])
	_check(not cover.is_showing(), "no cover, nothing shown")
	var file := FileAccess.open(DISK_COVER_FILE, FileAccess.READ)
	_check(file != null, "the datadisk ships its cover")
	if file != null:
		var texture: Texture2D = COVER._decode("a.jpg", file.get_buffer(file.get_length()))
		_check(texture != null and texture.get_width() == 1334, "the cover decodes")
		_check(COVER._decode("a.jpg", PackedByteArray([1, 2, 3])) == null, "garbage is not an image")
		cover._show(covered[0], texture)
		_check(cover.is_showing(), "a cover is shown")
		_check(cover.get_node("Backdrop/Caption").text == "The End Land 0.5.0", "the disk name is captioned")
		cover.dismiss()
		_check(not cover.is_showing(), "dismissing hides the cover")
	quit(1 if _failures > 0 else 0)
