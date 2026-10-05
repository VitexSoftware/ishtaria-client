extends SceneTree

const STORY := preload("res://scripts/story_client.gd")
const DISK := "res://../ishtaria-datadisk-endland/"

var _failures := 0
var _chosen: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _reply(open := true) -> Dictionary:
	var reply := {"npc_id": "endland:kragg", "name_key": "endland:npc.kragg", "seq": 3, "open": open,
		"portrait": "/story/media/endland/media/portraits/kragg.jpg",
		"music": {"url": "/story/media/endland/media/music/tavern_placeholder.ogg", "title_key": "endland:music.tavern", "loop": true},
		"player": {}}
	if open:
		reply["node"] = {"node": "greet", "text_key": "endland:kragg.greet", "choices": [{"index": 0, "text_key": "endland:kragg.ask_gossip"}, {"index": 2, "text_key": "endland:kragg.leave"}]}
	else:
		reply["node"] = null
	return reply

func _run() -> void:
	# What the server sends is checked before it is shown.
	_check(STORY.valid_reply(_reply()), "a good reply is accepted")
	_check(STORY.valid_reply(_reply(false)), "a closed conversation is accepted")
	var bad := _reply()
	bad.node.choices = [{"index": "x", "text_key": "a"}]
	_check(not STORY.valid_reply(bad), "a choice needs a numeric index")
	bad = _reply()
	bad.portrait = "/story/media/endland/../datadisk.yaml"
	_check(not STORY.valid_reply(bad), "a traversal portrait is refused")
	for url in ["/other/x.png", "/story/media/a/b.exe", "/story/media/a//b.png", "/story/media/a/b.png?x=1", "/story/media/a/%2e%2e/b.png", 5]:
		_check(not STORY.valid_media_url(url), "refused media url %s" % str(url))
	_check(STORY.valid_media_url("/story/media/endland/media/portraits/kragg.jpg"), "a portrait url is valid")
	_check(STORY.error_key(403, "character is out of reach") == "Too far away to talk", "fixed error keys")
	_check(STORY.error_key(500, "SELECT secret FROM users") == "Conversation unavailable", "server text never reaches the player")

	# Translations: every language is delivered, the player's own is used, English is the fallback.
	var story: Node = STORY.new()
	root.add_child(story)
	var strings := {"languages": {"en": {"k.hello": "Hello %s", "k.only_en": "English only"}, "cs": {"k.hello": "Ahoj %s"}}}
	_check(STORY.valid_strings(strings), "strings are valid")
	story._strings = strings.languages
	TranslationServer.set_locale("cs")
	_check(story.text("k.hello", ["světe"]) == "Ahoj světe", "Czech text with an argument")
	_check(story.text("k.only_en") == "English only", "English is the fallback")
	_check(story.text("k.unknown") == "k.unknown", "an unknown key is shown as is")
	TranslationServer.set_locale("en")
	_check(story.text("k.hello", ["world"]) == "Hello world", "English text")
	_check(not STORY.valid_strings({"languages": {"english": {}}}), "language codes have two letters")

	# NPCs near the player are rendered, nameable and found by distance.
	var environment := preload("res://scripts/surface_environment.gd").new()
	root.add_child(environment)
	environment.npc_text = func(key: String) -> String: return story.text(key)
	var good := {"id": "endland:kragg", "name_key": "k.only_en", "character": "survivors/survivorMaleB", "position": [6371000.0, 10.0, 0.0], "yaw": 1.0, "scale_m": 1.8}
	var broken := {"id": "endland:x", "name_key": "k.hello", "character": "nope/none", "position": [6371000.0, 0.0, 0.0], "yaw": 1.0, "scale_m": 1.8}
	var far := {"id": "endland:far", "name_key": "k.hello", "character": "retro/humanMaleA", "position": [6371000.0, 500.0, 0.0], "yaw": 0.0, "scale_m": 1.8}
	environment.apply_npcs([good, broken, far, "junk"])
	_check(environment.npcs.get_child_count() == 2, "valid characters are placed, malformed ones skipped")
	_check(environment.nearest_npc(Vector3(6371000.0, 8.0, 0.0), 4.5).get("id", "") == "endland:kragg", "the character in reach is found")
	_check(environment.nearest_npc(Vector3(6371000.0, 100.0, 0.0), 4.5).is_empty(), "nobody is in reach")
	var label := environment.npcs.get_child(0).get_node("Name") as Label3D
	_check(label.text == "English only", "the name is shown in the player's language")
	environment.set_render_origin([6371000.0, 0.0, 0.0])
	_check(environment.npcs.get_child(0).position.distance_to(Vector3(0, 0.01, 0)) < 0.0001, "characters follow the render origin")
	environment._clear_objects()
	_check(environment.npcs.get_child_count() == 0, "clearing the region removes the characters")

	# Props of generated places: known kit models are built, anything odd is skipped.
	var prop := {"id": "world:town_00#1", "model": "town.wall", "position": [6371000.0, 5.0, 0.0], "yaw": 0.5, "scale_m": 2.5}
	var bad_props := [
		{"id": "a", "model": "town.nothing-like-this", "position": [6371000.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 2.5},
		{"id": "b", "model": "../../project", "position": [6371000.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 2.5},
		{"id": "c", "model": "town.wall", "position": [6371000.0, 0.0], "yaw": 0.0, "scale_m": 2.5},
		{"id": "d", "model": "town.wall", "position": [6371000.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 900.0},
		{"id": "e", "model": "pirate.ship-small", "position": [1.0, 0.0, 0.0], "yaw": 0.0, "scale_m": 1.0},
		"junk"]
	_check(environment.apply_props([prop, {"id": "w2", "model": "pirate.ship-small", "position": [6371000.0, 9.0, 3.0], "yaw": 0.0, "scale_m": 1.0}] + bad_props), "a prop list is accepted")
	_check(environment.props.get_child_count() == 2, "only the two good props are built: %d" % environment.props.get_child_count())
	_check(environment.prop_path("graveyard.crypt-large") != "" and environment.prop_path("castle.wall-doorway") != "", "bundled models resolve")
	for model in ["town.", ".wall", "town.a.b", "kit.wall", "town./x", 5, null]:
		_check(environment.prop_path(model) == "", "refused model %s" % str(model))
	environment._clear_objects()
	_check(environment.props.get_child_count() == 0, "clearing the region removes the props")

	# The panel shows what was said, offers the choices and reports the choice with the sequence.
	var panel: CanvasLayer = preload("res://scripts/dialogue_panel.gd").new()
	panel.story = story
	root.add_child(panel)
	panel.choice_made.connect(func(npc: String, seq: int, choice: int) -> void: _chosen.append([npc, seq, choice]))
	story._strings = {"en": {"endland:kragg.greet": "Welcome!", "endland:npc.kragg": "Kragg", "endland:kragg.ask_gossip": "News?", "endland:kragg.leave": "Bye"}}
	panel.show_reply(_reply())
	await process_frame
	_check(panel.visible and panel.speech.text == "Welcome!" and panel.name_label.text == "Kragg", "the panel shows the speaker and the speech")
	_check(panel.choices_box.get_child_count() == 2, "both choices are offered")
	(panel.choices_box.get_child(1) as Button).pressed.emit()
	_check(_chosen == [["endland:kragg", 3, 2]], "the choice carries the server's own index and sequence: %s" % str(_chosen))
	panel.show_reply(_reply(false))
	_check(not panel.visible, "a closed conversation hides the panel")

	# Portraits and music of the Endland datadisk decode (skipped when the disk is not checked out).
	var portrait_path := ProjectSettings.globalize_path("res://").path_join("../ishtaria-datadisk-endland/media/portraits/kragg.jpg").simplify_path()
	if FileAccess.file_exists(portrait_path):
		var texture := STORY.decode_media("/story/media/endland/media/portraits/kragg.jpg", FileAccess.get_file_as_bytes(portrait_path))
		_check(texture is Texture2D and texture.get_width() > 0, "the portrait decodes")
		panel.show_reply(_reply())
		panel.media_ready("/story/media/endland/media/portraits/kragg.jpg", texture)
		_check(panel.portrait.texture == texture, "the portrait is shown beside the speech")
		var track_path := portrait_path.get_base_dir().get_base_dir().path_join("music/tavern_placeholder.ogg")
		var track := STORY.decode_media("/story/media/endland/media/music/tavern_placeholder.ogg", FileAccess.get_file_as_bytes(track_path))
		_check(track is AudioStreamOggVorbis and track.get_length() > 1.0, "the track decodes")
		panel.media_ready("/story/media/endland/media/music/tavern_placeholder.ogg", track)
		_check(panel._music.stream == track and (track as AudioStreamOggVorbis).loop, "the track plays and loops during the conversation")
		panel.set_music_enabled(false)
		_check(not panel._music.playing, "music can be switched off")
		panel.close()
		_check(panel._music.stream == null, "closing the conversation ends the music")
	_check(STORY.decode_media("/story/media/a/b.jpg", PackedByteArray([1, 2, 3])) == null, "garbage is not an image")

	# The quest log lists quests with their stage and marks finished ones.
	var quests := [{"quest": "endland:graveyard_job", "title_key": "k.only_en", "stage": "have_key", "text_key": "k.hello", "final": false}, {"quest": "x:y", "title_key": "k.only_en", "stage": "done", "text_key": "k.only_en", "final": true}]
	_check(STORY.valid_quests(quests), "a quest list is valid")
	_check(not STORY.valid_quests([{"quest": 1}]) and not STORY.valid_quests("x"), "malformed quest lists are refused")
	var log: CanvasLayer = preload("res://scripts/quest_panel.gd").new()
	log.story = story
	root.add_child(log)
	log.set_quests([])
	_check(log.list.get_child_count() == 1, "an empty log says there are no quests")
	log.set_quests(quests)
	log.open()
	_check(log.visible and log.list.get_child_count() == 4, "two quests give a heading and a step each")
	_check((log.list.get_child(2) as Label).text.ends_with("(" + log.tr("Finished") + ")"), "a finished quest is marked")

	if _failures > 0:
		push_error("%d story client checks failed" % _failures)
	else:
		print("Story client checks passed")
	quit(1 if _failures > 0 else 0)
