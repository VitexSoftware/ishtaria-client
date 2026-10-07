extends SceneTree
## Checks of the building, farming and fishing client: what the server may say is validated,
## refusals have fixed messages, and placed things are drawn and found.

var failures := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAILED: " + what)

func _init() -> void:
	var client := preload("res://scripts/placed_client.gd")
	var thing := {"id": 4, "kind": "campfire", "model": "survival.campfire-pit", "position": [6371000.0, 2.0, 0.0], "yaw": 1.0, "scale": 1.0, "owner": "anna", "station": "campfire", "crop": null}
	_check(client.valid_thing(thing), "a thing")
	var crop := thing.duplicate(true)
	crop.kind = "crop_carrot"
	crop.model = "food.carrot"
	crop.crop = {"growth": 0.5, "ripe": false}
	_check(client.valid_thing(crop), "a crop")
	for broken in [{"id": 0}, {"kind": 5}, {"position": [1, 2]}, {"position": [INF, 0, 0]}, {"yaw": "x"}, {"owner": 7}, {"crop": {"growth": 2, "ripe": false}}, {"crop": {"growth": 0.5, "ripe": 1}}, {"model": "x".repeat(80)}]:
		var copy := thing.duplicate(true)
		copy.merge(broken, true)
		_check(not client.valid_thing(copy), "malformed thing %s" % broken)
	_check(client.valid_things([thing, crop]) and not client.valid_things([thing, "x"]) and not client.valid_things("no"), "lists")

	var profile := {"player": {}}
	_check(client.valid_reply("place", {"object": thing, "player": {}}) and client.valid_reply("plant", {"object": crop, "player": {}}), "place and plant replies")
	_check(client.valid_reply("harvest", {"items": [{"item_id": "carrot", "name": "Carrot", "quantity": "3"}], "player": {}}) and not client.valid_reply("harvest", {"items": [{"item_id": "carrot", "name": "Carrot", "quantity": "x"}], "player": {}}), "taken items")
	_check(client.valid_reply("fish", {"caught": true, "items": [], "player": {}}) and not client.valid_reply("fish", {"caught": "yes", "items": [], "player": {}}) and not client.valid_reply("unknown", profile), "fishing and unknown replies")
	_check(client.error_key(409, "not ripe yet") == "Not ripe yet" and client.error_key(500, "SQL boom") == "Action unavailable" and client.error_key(429, "too fast") == "", "error keys never echo server text")

	var surface: Node3D = preload("res://scripts/surface_environment.gd").new()
	surface.land_material = ShaderMaterial.new()
	surface.water_material = ShaderMaterial.new()
	root.add_child(surface)
	await process_frame
	var radius := 6371.0 * 1000.0
	var near := thing.duplicate(true)
	near.position = [radius, 0.0, 0.0]
	var far := crop.duplicate(true)
	far.id = 5
	far.position = [radius, 40.0, 0.0]
	var unknown := thing.duplicate(true)
	unknown.id = 6
	unknown.model = "survival.nothing-like-it"
	_check(surface.apply_placed([near, far, unknown, "junk"]), "placed things are applied")
	_check(surface.placed.get_child_count() == 2, "known models are drawn, the unknown and the junk are skipped")
	var found: Dictionary = surface.nearest_placed(Vector3(radius, 1.0, 0.0), 3.5)
	_check(found.get("id") == 4, "the nearest thing in reach is found")
	_check(surface.nearest_placed(Vector3(radius, 20.0, 0.0), 3.5).is_empty(), "nothing between the two is in reach")
	surface.apply_placed([])
	_check(surface.placed.get_child_count() == 0, "an empty list clears everything")
	surface.apply_placed([near])
	surface.clear_world()
	await process_frame
	_check(surface.placed.get_child_count() == 0 and is_instance_valid(surface.placed), "leaving a server clears the things, not the container")

	# Seeds and things in the inventory get their buttons.
	var panel: CanvasLayer = preload("res://scripts/survival_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var placed := []
	var planted := []
	panel.place_requested.connect(func(id: String) -> void: placed.append(id))
	panel.plant_requested.connect(func(id: String) -> void: planted.append(id))
	panel.set_profile({"life": {"alive": true}, "stats": {"gold": "0", "health": 100}, "inventory": {"capacity": 100, "used": 3, "items": [
		{"item_id": "campfire", "name": "Campfire", "quantity": "1", "category": "placeable", "calories": 0},
		{"item_id": "seed_carrot", "name": "Carrot seeds", "quantity": "2", "category": "raw_material", "calories": 0},
		{"item_id": "stone", "name": "Stone", "quantity": "2", "category": "raw_material", "calories": 0}]}})
	var campfire_button: Node = panel.inventory_list.find_child("Place", true, false)
	var seed_button: Node = panel.inventory_list.find_child("Plant", true, false)
	_check(campfire_button != null and seed_button != null, "place and plant buttons exist")
	if campfire_button != null and seed_button != null:
		campfire_button.pressed.emit()
		seed_button.pressed.emit()
		_check(placed == ["campfire"] and planted == ["seed_carrot"], "the buttons send the item")
	_check(panel.inventory_list.find_children("Place", "Button", true, false).size() == 1, "plain materials have no place button")

	# Icons of the new foods exist.
	var icons := preload("res://scripts/item_icons.gd")
	for id in ["corn", "cabbage", "pumpkin", "fish", "cooked_fish", "cooked_meat", "raw_meat", "seed_carrot", "seed_pumpkin"]:
		_check(icons.texture(id) != null, "icon of " + id)

	print("Placed client checks %s" % ("failed" if failures > 0 else "passed"))
	quit(1 if failures > 0 else 0)
