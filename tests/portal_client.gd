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
const ID4 := "3192f3a1-5b1e-7c3a-9d4e-1a2b3c4d5e6f"
const LINK := "ishtaria-portal:v1.abc.def"

func _portal(id: String, state: String, linked := false) -> Dictionary:
	return {"id": id, "state": state, "portal_name": "brana-jih", "peer_host": "svet-a.example.org" if linked else null, "peer_portal_name": "brana-sever" if linked else null}

func _requirement(id: String, items: Array, required: int, contributed: int) -> Dictionary:
	return {"id": id, "items": items, "required": str(required), "contributed": str(contributed)}

func _run() -> void:
	# Names, links and server answers are validated; messages come from fixed keys.
	_check(SESSION.valid_portal_name("brana-sever") and not SESSION.valid_portal_name("Brana") and not SESSION.valid_portal_name("") and not SESSION.valid_portal_name("a/b"), "portal names")
	_check(SESSION.valid_uuid(ID1) and not SESSION.valid_uuid("../x") and not SESSION.valid_uuid(ID1.to_upper()), "identifiers")
	_check(SESSION.valid_link(LINK) and not SESSION.valid_link("ishtaria-invite:v1.abc.def") and not SESSION.valid_link("") and not SESSION.valid_link(LINK + " x") and not SESSION.valid_link("ishtaria-portal:v1." + "a".repeat(3000)), "share links")
	_check(SESSION.portal_error(409, "the other portal is already linked") == "The other portal is already linked", "linked peer portal")
	_check(SESSION.portal_error(409, "the other portal is not finished") == "The other portal is not finished", "unfinished peer portal")
	_check(SESSION.portal_error(400, "this is not a portal share link") == "That is not a portal share link", "bad link")
	_check(SESSION.portal_error(403, "the land is leased by another player") == "The land is leased by another player", "leased land")
	_check(SESSION.portal_error(502, "peer unreachable") == "The other world is unreachable", "unreachable peer")
	_check(SESSION.portal_error(422, "peer address does not match its world name") == "The other world could not be verified", "unverified peer")
	_check(SESSION.portal_error(500, "SELECT secret") == "Portal action unavailable", "unknown text is not echoed")
	_check(SESSION.valid_portal(_portal(ID1, "open", true)) and SESSION.valid_portal(_portal(ID1, "built")) and not SESSION.valid_portal(_portal("x", "open")) and not SESSION.valid_portal(_portal(ID1, "weird")), "portal validation")
	var building := _portal(ID1, "building")
	building["requirements"] = [_requirement("stone_block", ["stone_block"], 10, 4)]
	_check(SESSION.valid_portal(building), "a portal with requirements is valid")
	building["requirements"] = [{"id": "x", "items": [1], "required": "1", "contributed": "0"}]
	_check(not SESSION.valid_portal(building), "malformed requirements are refused")

	var panel := preload("res://scripts/portal_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var events := []
	panel.build_requested.connect(func(name: String) -> void: events.append(["build", name]))
	panel.deliver_requested.connect(func(id: String, item: String, quantity: int) -> void: events.append(["deliver", id, item, quantity]))
	panel.link_requested.connect(func(id: String) -> void: events.append(["link", id]))
	panel.connect_requested.connect(func(id: String, link: String) -> void: events.append(["connect", id, link]))
	panel.disconnect_requested.connect(func(id: String) -> void: events.append(["disconnect", id]))
	panel.close_requested.connect(func(id: String) -> void: events.append(["close", id]))
	panel.details_requested.connect(func(id: String) -> void: events.append(["details", id]))
	panel.set_profile({"life": {"alive": true}, "inventory": {"items": [{"item_id": "stone_block", "quantity": "7"}, {"item_id": "oak_plank", "quantity": "30"}]}})

	panel.name_input.text = "brana-sever"
	panel.find_child("Build", true, false).pressed.emit()
	_check(events == [["build", "brana-sever"]], "build intention")

	events.clear()
	panel.set_portals([_portal(ID1, "built"), _portal(ID2, "building"), _portal(ID3, "open", true), _portal(ID4, "closed")])
	_check(events == [["details", ID2]], "details of the portal under construction are requested")
	var closed := panel.find_child("Portal_" + ID4, true, false)
	_check(closed != null and closed.find_child("CloseRuin", true, false) == null, "a closed portal cannot be closed again")

	events.clear()
	# A finished portal offers exactly two things: copy its link, paste another's.
	var finished := panel.find_child("Portal_" + ID1, true, false)
	_check(finished.find_child("CopyLink", true, false) != null and finished.find_child("PasteLink", true, false) != null and finished.find_child("Connect", true, false) != null, "a finished portal offers its link and a place for another")
	_check(finished.find_child("Disconnect", true, false) == null, "an unlinked portal has nothing to break")
	finished.find_child("CopyLink", true, false).pressed.emit()
	finished.find_child("PasteLink", true, false).text = "  " + LINK + "  "
	finished.find_child("PasteLink", true, false).text_changed.emit(finished.find_child("PasteLink", true, false).text)
	finished.find_child("Connect", true, false).pressed.emit()
	_check(events == [["link", ID1], ["connect", ID1, LINK]], "link and connect intentions: %s" % [events])
	panel.set_link(LINK)
	_check(panel.link_output.text == LINK, "the link is shown")

	# A linked portal shows its counterpart and can be disconnected by its owner.
	var linked := panel.find_child("Portal_" + ID3, true, false)
	_check(linked.find_child("CopyLink", true, false) == null and linked.find_child("PasteLink", true, false) == null, "a linked portal has one counterpart only")
	events.clear()
	linked.find_child("Disconnect", true, false).pressed.emit()
	linked.find_child("CloseRuin", true, false).pressed.emit()
	_check(events == [["disconnect", ID3], ["close", ID3]], "disconnect and close intentions")

	var detail := _portal(ID2, "building")
	detail["requirements"] = [_requirement("stone_block", ["stone_block"], 10, 4), _requirement("plank", ["pine_plank", "oak_plank"], 20, 0), _requirement("quartz_crystal", ["quartz_crystal"], 2, 0)]
	panel.set_portal(detail)
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
	var finished_detail := _portal(ID2, "built")
	panel.set_portal(finished_detail)
	await process_frame
	_check(panel.find_child("Requirement_stone_block", true, false) == null and panel.find_child("Portal_" + ID2, true, false).find_child("CopyLink", true, false) != null, "a finished portal takes no more and offers its link")
	panel.set_busy(true)
	_check(panel.find_child("Portal_" + ID2, true, false).find_child("Connect", true, false).disabled, "buttons wait for a running request")

	# Portals the server reports are validated and drawn.
	var environment := preload("res://scripts/surface_environment.gd").new()
	environment.land_material = ShaderMaterial.new()
	environment.water_material = ShaderMaterial.new()
	root.add_child(environment)
	var position := [6371000.0, 0.0, 0.0]
	_check(environment.apply_portals([{"name": "brana-sever", "state": "open", "peer": "svet-b.example.org", "position": position}, {"name": "brana-ruina", "state": "closed", "peer": "svet-b.example.org", "position": [6371000.0, 10.0, 0.0]}]), "valid portals are accepted")
	_check(environment.portals.get_child_count() == 2, "two portals are drawn")
	_check(environment.apply_portals([{"name": "volna", "state": "building", "peer": "", "position": [6371000.0, 40.0, 0.0]}]), "an unlinked portal has no peer")
	_check(not environment.apply_portals([{"name": "x", "state": "weird", "peer": "p", "position": position}]), "unknown states are refused")
	_check(not environment.apply_portals([{"name": "x", "state": "open", "peer": "p", "position": [1.0, 2.0, 3.0]}]), "positions off the planet are refused")
	_check(not environment.apply_portals("nonsense") and not environment.apply_portals([1]), "malformed lists are refused")
	_check(environment.portals.get_child_count() == 1, "a refused list leaves the drawn portals alone")
	_check(environment.apply_portals([]) and environment.portals.get_child_count() == 0, "an empty list removes them")

	if _failures > 0:
		push_error("%d portal client checks failed" % _failures)
	else:
		print("Portal client checks passed")
	quit(1 if _failures > 0 else 0)
