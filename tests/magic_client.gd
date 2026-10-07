extends SceneTree
## Checks of the magic client: what the server says is validated, refusals have fixed messages,
## and the inventory lists spells and scrolls.

var failures := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAILED: " + what)

func _init() -> void:
	
	var magic := preload("res://scripts/magic_client.gd")
	var spell := {"id": "firebolt", "name": "Firebolt", "mana": 20, "cooldown_ms": 3000, "effect": "bolt", "range_m": 14.0, "ready_in_ms": 0}
	_check(magic.valid_spell(spell), "a spell")
	for broken in [{"id": ""}, {"effect": "explode"}, {"mana": -1}, {"range_m": "far"}, {"name": "x".repeat(80)}, {"ready_in_ms": INF}]:
		var copy := spell.duplicate(true)
		copy.merge(broken, true)
		_check(not magic.valid_spell(copy), "malformed spell %s" % broken)
	var known := {"mana": 80, "mana_max": 100, "spells": [spell]}
	_check(magic.valid_known(known) and not magic.valid_known({"mana": 80, "mana_max": 100, "spells": "x"}) and not magic.valid_known({"mana": -4, "mana_max": 100, "spells": []}), "the spell book")

	var heal := {"spell": "heal", "effect": "heal", "strike": null, "target": null, "player": {}}
	_check(magic.valid_cast(heal), "a self spell reply")
	var bolt := {"spell": "firebolt", "effect": "bolt", "target": "animal.deer", "player": {}, "strike": {"state": "hit", "hits": 1, "hits_required": 3, "items": [], "counter": null}}
	_check(magic.valid_cast(bolt), "a bolt reply")
	var killed := bolt.duplicate(true)
	killed.strike.state = "depleted"
	killed.strike.items = [{"item_id": "raw_meat", "name": "Raw meat", "quantity": "3"}]
	_check(magic.valid_cast(killed), "a bolt that killed")
	var bitten := bolt.duplicate(true)
	bitten.strike.counter = {"attempted": 8, "damage": 4, "defense": 0, "blocked": false, "died": false, "wear": []}
	_check(magic.valid_cast(bitten), "a bolt that was bitten back")
	for broken in [{"effect": "teleport"}, {"player": 1}, {"spell": 3}]:
		var copy := heal.duplicate(true)
		copy.merge(broken, true)
		_check(not magic.valid_cast(copy), "malformed reply %s" % broken)
	var bad_strike := bolt.duplicate(true)
	bad_strike.strike.state = "gone"
	_check(not magic.valid_cast(bad_strike), "an unknown strike state")
	var bad_counter := bolt.duplicate(true)
	bad_counter.strike.counter = {"damage": 400}
	_check(not magic.valid_cast(bad_counter), "a malformed counter-attack")

	_check(magic.error_key(409, "not enough mana") == "Not enough mana" and magic.error_key(403, "level too low") == "Your level is too low for this scroll" and magic.error_key(500, "SQL boom") == "Magic unavailable" and magic.error_key(429, "x") == "", "error keys never echo server text")

	# The inventory lists the spells and offers to read scrolls.
	var panel: CanvasLayer = preload("res://scripts/survival_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var cast := []
	var read := []
	panel.cast_requested.connect(func(id: String) -> void: cast.append(id))
	panel.learn_requested.connect(func(id: String) -> void: read.append(id))
	panel.set_profile({"life": {"alive": true}, "stats": {"gold": "0", "health": 100}, "inventory": {"capacity": 100, "used": 2, "items": [
		{"item_id": "scroll_heal", "name": "Scroll of Healing", "quantity": "1", "category": "document", "calories": 0},
		{"item_id": "stone", "name": "Stone", "quantity": "2", "category": "raw_material", "calories": 0}]}})
	
	panel.set_spells(known)
	
	var row: Node = panel.inventory_list.find_child("Spell_firebolt", true, false)
	_check(row != null, "a known spell is listed")
	if row != null:
		row.find_child("Cast", true, false).pressed.emit()
		_check(cast == ["firebolt"], "the cast button sends the spell")
	var learn_button: Node = panel.inventory_list.find_child("Learn", true, false)
	_check(learn_button != null and panel.inventory_list.find_children("Learn", "Button", true, false).size() == 1, "only the scroll has a read button")
	if learn_button != null:
		learn_button.pressed.emit()
		_check(read == ["scroll_heal"], "the read button sends the scroll")
	panel.set_spells({"mana": 5, "mana_max": 100, "spells": [spell]})
	_check(panel.inventory_list.find_child("Spell_firebolt", true, false).find_child("Cast", true, false).disabled, "a spell that costs more than the mana is disabled")
	panel.set_spells({"mana": 100, "mana_max": 100, "spells": []})
	_check(panel.inventory_list.find_child("Spell_firebolt", true, false) == null, "no spells, no list")

	var icons := preload("res://scripts/item_icons.gd")
	for id in ["scroll_refresh", "scroll_firebolt", "scroll_heal", "scroll_ward"]:
		_check(icons.texture(id) != null, "icon of " + id)

	print("Magic client checks %s" % ("failed" if failures > 0 else "passed"))
	quit(1 if failures > 0 else 0)
