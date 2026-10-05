extends SceneTree

const SESSION := preload("res://scripts/player_session.gd")

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

const ID1 := "0192f3a1-5b1e-7c3a-9d4e-1a2b3c4d5e6f"
const ID2 := "1192f3a1-5b1e-7c3a-9d4e-1a2b3c4d5e6f"
const ID3 := "2192f3a1-5b1e-7c3a-9d4e-1a2b3c4d5e6f"

func _pact(id: String, state: String) -> Dictionary:
	return {"id": id, "role": "invitee", "state": state, "peer_host": "svet-a.example.org", "peer_player": "vitex", "portal_name": "brana-jih"}

func _requirement(id: String, items: Array, required: int, contributed: int) -> Dictionary:
	return {"id": id, "items": items, "required": str(required), "contributed": str(contributed)}

func _run() -> void:
	# Names, identifiers and server answers are validated; messages come from fixed keys.
	_check(SESSION.valid_portal_name("brana-sever") and not SESSION.valid_portal_name("Brana") and not SESSION.valid_portal_name("") and not SESSION.valid_portal_name("a/b"), "portal names")
	_check(SESSION.valid_uuid(ID1) and not SESSION.valid_uuid("../x") and not SESSION.valid_uuid(ID1.to_upper()), "identifiers")
	_check(SESSION.portal_error(409, "invitation already used") == "Invitation already used", "used invitation")
	_check(SESSION.portal_error(403, "the land is leased by another player") == "The land is leased by another player", "leased land")
	_check(SESSION.portal_error(502, "peer unreachable") == "The other world is unreachable", "unreachable peer")
	_check(SESSION.portal_error(422, "peer address does not match its world name") == "The other world could not be verified", "unverified peer")
	_check(SESSION.portal_error(500, "SELECT secret") == "Portal action unavailable", "unknown text is not echoed")
	_check(SESSION.valid_pact(_pact(ID1, "open")) and not SESSION.valid_pact(_pact("x", "open")) and not SESSION.valid_pact(_pact(ID1, "weird")), "pact validation")
	var building := _pact(ID1, "building")
	building["requirements"] = [_requirement("stone_block", ["stone_block"], 10, 4)]
	_check(SESSION.valid_pact(building), "a pact with requirements is valid")
	building["requirements"] = [{"id": "x", "items": [1], "required": "1", "contributed": "0"}]
	_check(not SESSION.valid_pact(building), "malformed requirements are refused")

	var panel := preload("res://scripts/portal_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var events := []
	panel.invitation_requested.connect(func(name: String) -> void: events.append(["invite", name]))
	panel.accept_requested.connect(func(code: String, name: String) -> void: events.append(["accept", code, name]))
	panel.site_requested.connect(func(id: String) -> void: events.append(["site", id]))
	panel.deliver_requested.connect(func(id: String, item: String, quantity: int) -> void: events.append(["deliver", id, item, quantity]))
	panel.cancel_requested.connect(func(id: String) -> void: events.append(["cancel", id]))
	panel.details_requested.connect(func(id: String) -> void: events.append(["details", id]))
	panel.set_profile({"life": {"alive": true}, "inventory": {"items": [{"item_id": "stone_block", "quantity": "7"}, {"item_id": "oak_plank", "quantity": "30"}]}})

	panel.name_input.text = "brana-sever"
	panel.find_child("CreateInvitation", true, false).pressed.emit()
	panel.accept_code_input.text = "ishtaria-invite:v1.abc.def"
	panel.accept_name_input.text = "brana-jih"
	panel.find_child("AcceptInvitation", true, false).pressed.emit()
	_check(events == [["invite", "brana-sever"], ["accept", "ishtaria-invite:v1.abc.def", "brana-jih"]], "invitation intentions")
	panel.set_invitation({"id": ID1, "code": "ishtaria-invite:v1.xyz", "expires_at": 1})
	_check(panel.code_output.text == "ishtaria-invite:v1.xyz", "the code is shown")

	events.clear()
	panel.set_pacts([_pact(ID1, "accepted"), _pact(ID2, "building"), _pact(ID3, "closed")])
	_check(events == [["details", ID2]], "details of the pact under construction are requested")
	_check(panel.find_child("PlaceSite", true, false) != null, "an accepted pact offers a construction site")
	var closed := panel.find_child("Pact_" + ID3, true, false)
	_check(closed != null and closed.find_child("Cancel", true, false) == null, "a closed pact cannot be cancelled")
	var detail := _pact(ID2, "building")
	detail["local_built"] = false
	detail["requirements"] = [_requirement("stone_block", ["stone_block"], 10, 4), _requirement("plank", ["pine_plank", "oak_plank"], 20, 0), _requirement("quartz_crystal", ["quartz_crystal"], 2, 0)]
	panel.set_pact(detail)
	await process_frame
	var stone := panel.find_child("Requirement_stone_block", true, false)
	var plank := panel.find_child("Requirement_plank", true, false)
	var quartz := panel.find_child("Requirement_quartz_crystal", true, false)
	_check(stone != null and stone.find_child("Deliver", true, false) != null, "stone can be delivered")
	_check(plank != null and plank.find_child("Deliver", true, false) != null, "planks of any listed wood can be delivered")
	_check(quartz != null and quartz.find_child("Deliver", true, false) == null, "no delivery without the item")
	events.clear()
	stone.find_child("Deliver", true, false).pressed.emit()
	plank.find_child("Deliver", true, false).pressed.emit()
	_check(events == [["deliver", ID2, "stone_block", 6], ["deliver", ID2, "oak_plank", 20]], "a delivery is limited by the need and by what the player holds: %s" % [events])
	_check(panel.deliverable(_requirement("stone_block", ["stone_block"], 10, 10)).is_empty(), "nothing is delivered to a finished requirement")
	panel.find_child("PlaceSite", true, false).pressed.emit()
	panel.find_child("Pact_" + ID2, true, false).find_child("Cancel", true, false).pressed.emit()
	_check(events[2] == ["site", ID1] and events[3] == ["cancel", ID2], "site and cancel intentions")
	detail["local_built"] = true
	panel.set_pact(detail)
	await process_frame
	_check(panel.find_child("Requirement_stone_block", true, false).find_child("Deliver", true, false) == null, "a built end takes no more")
	panel.set_busy(true)
	_check(panel.find_child("PlaceSite", true, false).disabled, "buttons wait for a running request")

	# Portals the server reports are validated and drawn.
	var environment := preload("res://scripts/surface_environment.gd").new()
	environment.land_material = ShaderMaterial.new()
	environment.water_material = ShaderMaterial.new()
	root.add_child(environment)
	var position := [6371000.0, 0.0, 0.0]
	_check(environment.apply_portals([{"name": "brana-sever", "state": "open", "peer": "svet-b.example.org", "position": position}, {"name": "brana-ruina", "state": "closed", "peer": "svet-b.example.org", "position": [6371000.0, 10.0, 0.0]}]), "valid portals are accepted")
	_check(environment.portals.get_child_count() == 2, "two portals are drawn")
	_check(not environment.apply_portals([{"name": "x", "state": "weird", "peer": "p", "position": position}]), "unknown states are refused")
	_check(not environment.apply_portals([{"name": "x", "state": "open", "peer": "p", "position": [1.0, 2.0, 3.0]}]), "positions off the planet are refused")
	_check(not environment.apply_portals("nonsense") and not environment.apply_portals([1]), "malformed lists are refused")
	_check(environment.portals.get_child_count() == 2, "a refused list leaves the drawn portals alone")
	_check(environment.apply_portals([]) and environment.portals.get_child_count() == 0, "an empty list removes them")

	if _failures > 0:
		push_error("%d portal client checks failed" % _failures)
	else:
		print("Portal client checks passed")
	quit(1 if _failures > 0 else 0)
