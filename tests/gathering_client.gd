extends SceneTree

const SESSION := preload("res://scripts/player_session.gd")
const ICONS := preload("res://scripts/item_icons.gd")

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _recipe(id: String, inputs: Array, outputs: Array, tool: Variant = null) -> Dictionary:
	var recipe := {"id": id, "inputs": inputs, "outputs": outputs}
	if tool != null:
		recipe["tool"] = tool
	return recipe

func _stack(id: String, name: String, quantity: String) -> Dictionary:
	return {"item_id": id, "name": name, "quantity": quantity}

func _run() -> void:
	# Messages for refused actions come from fixed keys, never from server text.
	_check(SESSION.action_error(409, "inventory is full") == "Inventory is full", "full inventory message")
	_check(SESSION.action_error(409, "stack is full") == "Inventory is full", "full stack message")
	_check(SESSION.action_error(409, "required tool missing") == "Equip a suitable tool", "tool message")
	_check(SESSION.action_error(409, "this item cannot be equipped") == "This item cannot be equipped", "equip message")
	_check(SESSION.action_error(429, "too fast") == "", "cooldown is silent")
	_check(SESSION.action_error(500, "<script>") == "Item action unavailable", "unknown text is not echoed")

	var reply := {"object_id": "42:0:1:2", "state": "depleted", "hits": 0, "hits_required": 5, "items": [_stack("oak_log", "Oak log", "2")], "player": {}}
	_check(SESSION.valid_harvest(reply), "valid harvest reply")
	for broken in [{"state": "x"}, {"items": "no"}, {"hits": -1}, {"items": [{"item_id": "a", "name": "A", "quantity": "x"}]}]:
		var copy := reply.duplicate(true)
		copy.merge(broken, true)
		_check(not SESSION.valid_harvest(copy), "malformed harvest reply %s" % broken)
	_check(not SESSION.valid_harvest("text"), "non-dictionary harvest reply")

	# Icons: only known identifiers resolve and the baked icons exist.
	_check(ICONS.path_for("../secret").is_empty() and ICONS.path_for("A b").is_empty(), "icon paths are validated")
	_check(ICONS.path_for("apple").ends_with("food-kit/apple.png"), "food icons come from the Food Kit")
	for id in ["axe", "pickaxe", "oak_log", "pine_wood", "birch_plank", "stone", "stone_block", "iron_ore", "copper_ore", "quartz_crystal"]:
		_check(ICONS.texture(id) != null, "baked icon for " + id)
	# Every RPG item of the bundle, the sword and the gold coin have a baked icon.
	var baker: Dictionary = load("res://tools/bake-item-icons.gd").get_script_constant_map()
	_check(baker.RPG_ITEMS.size() >= 50, "the RPG item list is complete")
	for id: String in baker.RPG_ITEMS:
		_check(ICONS.texture(id) != null, "baked icon for RPG item " + id)
		_check(FileAccess.file_exists("res://assets/quaternius/ultimate-rpg-items/Models/%s.glb" % id), "bundled model for " + id)
	_check(ICONS.texture("gold") != null and ICONS.texture("sword") != null, "gold and the sword have icons")
	_check(ICONS.texture("suitcase") == null, "items without a model show no icon")

	# Scenery with harvest information; only trees and rocks can be harvested.
	var environment := preload("res://scripts/surface_environment.gd").new()
	root.add_child(environment)
	environment.placements.append({"id": "tree", "coordinates": [6371000.0, 0.0, 0.0], "collision_radius_m": 0.5, "harvest": {"kind": "tree", "tool": "axe", "hits": 5}})
	environment.placements.append({"id": "rock", "coordinates": [6371002.0, 0.0, 0.0], "collision_radius_m": 0.5, "harvest": {"kind": "rock", "tool": "pickaxe", "hits": 4}})
	environment.placements.append({"id": "flower", "coordinates": [6371000.5, 0.0, 0.0], "collision_radius_m": 0.0, "harvest": {}})
	_check(environment.nearest_harvestable(Vector3(6371001.0, 0.0, 0.0), 3.6).id == "tree" or environment.nearest_harvestable(Vector3(6371001.0, 0.0, 0.0), 3.6).id == "rock", "a harvestable object is found")
	_check(environment.nearest_harvestable(Vector3(6371000.2, 0.0, 0.0), 3.6).id == "tree", "the nearest object wins and scenery is skipped")
	_check(environment.nearest_harvestable(Vector3(6371100.0, 0.0, 0.0), 3.6).is_empty(), "nothing is found out of reach")
	_check(environment._harvest_info({"kind": "castle", "tool": "axe", "hits": 1}).is_empty() and environment._harvest_info("x").is_empty(), "unknown kinds are scenery")
	environment.queue_free()

	# Crafting is offered only with the ingredients and the tool in the inventory.
	var panel := preload("res://scripts/survival_panel.gd").new()
	root.add_child(panel)
	var chop := _recipe("chop_oak_log", [_stack("oak_log", "Oak log", "1")], [_stack("oak_wood", "Oak wood", "20")], "axe")
	panel.set_recipes([chop, {"id": 5}, _recipe("bad", [], [])])
	_check(panel._recipes.size() == 1, "malformed recipes are ignored")
	panel.set_profile({"life": {"alive": true}, "stats": {"gold": "0"}, "inventory": {"used": 1, "capacity": 100, "items": [_stack("oak_log", "Oak log", "1")]}})
	_check(not panel.can_craft(chop), "no axe, no chopping")
	panel.set_profile({"life": {"alive": true}, "stats": {"gold": "0"}, "inventory": {"used": 2, "capacity": 100, "items": [_stack("oak_log", "Oak log", "1"), _stack("axe", "Axe", "1")]}})
	_check(panel.can_craft(chop), "log and axe allow chopping")
	panel.open()
	var recipe_row := panel.find_child("Recipe_chop_oak_log", true, false)
	_check(recipe_row != null, "the recipe is listed")
	var craft_button: Button = recipe_row.find_child("Craft", true, false) if recipe_row != null else null
	_check(craft_button != null and not craft_button.disabled, "the craft button is enabled")
	var requested := []
	panel.craft_requested.connect(func(id: String) -> void: requested.append(id))
	if craft_button != null:
		craft_button.pressed.emit()
	_check(requested == ["chop_oak_log"], "pressing craft requests the recipe")
	# Tools and weapons can be put in hand; the one in hand can be taken out.
	var hand_events := []
	panel.equip_requested.connect(func(id: String) -> void: hand_events.append(["equip", id]))
	panel.unequip_requested.connect(func() -> void: hand_events.append(["unequip"]))
	panel.set_profile({"life": {"alive": true}, "stats": {"gold": "0"}, "equipment": {"hand": "axe"}, "inventory": {"used": 3, "capacity": 100, "items": [
		{"item_id": "apple", "name": "Apple", "quantity": "3", "calories": 95, "category": "food"},
		{"item_id": "axe", "name": "Axe", "quantity": "1", "calories": 0, "category": "tool"},
		{"item_id": "pickaxe", "name": "Pickaxe", "quantity": "1", "calories": 0, "category": "tool"}]}})
	_check(panel.find_child("Unequip", true, false) != null and panel.find_child("Equip", true, false) != null, "the axe is in hand, the pickaxe can be equipped")
	_check(panel.summary.text.contains("Axe"), "the summary names the item in hand")
	panel.find_child("Equip", true, false).pressed.emit()
	panel.find_child("Unequip", true, false).pressed.emit()
	_check(hand_events == [["equip", "pickaxe"], ["unequip"]], "equip intentions: %s" % [hand_events])
	# Every tool also has a Use button (not food); it names the tool to use.
	var uses := []
	panel.use_requested.connect(func(id: String) -> void: uses.append(id))
	var use_buttons := panel.find_children("Use", "Button", true, false)
	_check(use_buttons.size() == 2, "the axe and the pickaxe can be used, the apple cannot: %d" % use_buttons.size())
	for button: Button in use_buttons:
		button.pressed.emit()
	_check(uses == ["axe", "pickaxe"], "use intentions: %s" % [uses])
	var equip_buttons := panel.find_children("Equip", "Button", true, false)
	_check(equip_buttons.size() == 1, "food cannot be equipped")
	_check(recipe_row != null and recipe_row.get_child(0) is TextureRect, "the recipe shows the icon of its product")

	# A shield goes in the other hand, and worn items show their durability.
	var offhand_events := []
	panel.unequip_offhand_requested.connect(func() -> void: offhand_events.append("offhand"))
	panel.set_profile({"life": {"alive": true}, "stats": {"gold": "0"}, "equipment": {"hand": "axe", "offhand": "shield_round"}, "inventory": {"used": 2, "capacity": 100, "items": [
		{"item_id": "axe", "name": "Axe", "quantity": "1", "calories": 0, "category": "tool", "durability": 100, "max_durability": 120},
		{"item_id": "shield_round", "name": "Shield Round", "quantity": "1", "calories": 0, "category": "shield", "durability": 149, "max_durability": 150}]}})
	_check(panel.find_children("Unequip", "Button", true, false).size() == 2, "both hands can be emptied")
	var texts := []
	for label in panel.find_children("*", "Label", true, false):
		texts.append(label.text)
	_check("\n".join(texts).contains("149 / 150"), "durability is shown")
	for button in panel.find_children("Unequip", "Button", true, false):
		button.pressed.emit()
	_check(offhand_events == ["offhand"] and hand_events.back() == ["unequip"], "the shield leaves the other hand")
	var session := preload("res://scripts/player_session.gd")
	_check(session.valid_block({"blocking_seconds": 2, "wear": null, "player": {}}) and session.valid_block({"blocking_seconds": 2, "wear": {"broken": false, "durability": 3, "max_durability": 150}, "player": {}}), "block replies")
	_check(not session.valid_block({"blocking_seconds": 999, "wear": null, "player": {}}) and not session.valid_block({"blocking_seconds": 2, "wear": {"broken": "x"}, "player": {}}), "malformed block replies are refused")
	if _failures > 0:
		push_error("%d gathering client checks failed" % _failures)
	else:
		print("Gathering client checks passed")
	quit(1 if _failures > 0 else 0)
