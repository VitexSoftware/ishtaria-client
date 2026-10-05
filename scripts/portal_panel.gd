extends CanvasLayer
## Invitations, pacts and the building of portals. All decisions are the server's; the
## panel shows what it reports and sends the player's intentions.

signal invitation_requested(portal_name: String)
signal accept_requested(code: String, portal_name: String)
signal refresh_requested
signal details_requested(pact_id: String)
signal site_requested(pact_id: String)
signal deliver_requested(pact_id: String, item_id: String, quantity: int)
signal cancel_requested(pact_id: String)

const ITEM_ICONS := preload("res://scripts/item_icons.gd")
const PLANK_NAMES := {"plank": "Planks (any wood)"}
const FINAL_STATES := ["declined", "expired", "closed", "banned"]

var panel: PanelContainer
var summary: Label
var feedback: Label
var name_input: LineEdit
var code_output: LineEdit
var accept_code_input: LineEdit
var accept_name_input: LineEdit
var pact_list: VBoxContainer
var _pacts: Array = []
var _details: Dictionary = {}
var _owned: Dictionary = {}
var _busy := false
var _feedback_key := ""
var _wanted: Array[String] = []

func _ready() -> void:
	layer = 4
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.7)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	panel = PanelContainer.new()
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.14)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	summary = _label(header, "")
	var close := Button.new()
	close.name = "Close"
	close.text = "Close"
	close.pressed.connect(hide)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	_build_invite_section(content)
	_build_accept_section(content)
	pact_list = VBoxContainer.new()
	pact_list.name = "Pacts"
	pact_list.add_theme_constant_override("separation", 8)
	content.add_child(pact_list)
	feedback = _label(column, "")
	feedback.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()
	_update_texts()

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _line(parent: Node, name: String, placeholder: String) -> LineEdit:
	var input := LineEdit.new()
	input.name = name
	input.placeholder_text = placeholder
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = 36
	parent.add_child(input)
	return input

func _build_invite_section(content: VBoxContainer) -> void:
	var title := _label(content, "")
	title.name = "InviteTitle"
	title.add_theme_font_size_override("font_size", 20)
	var row := HBoxContainer.new()
	content.add_child(row)
	name_input = _line(row, "PortalName", "brana-sever")
	var create := Button.new()
	create.name = "CreateInvitation"
	create.pressed.connect(func() -> void:
		set_feedback("")
		invitation_requested.emit(name_input.text.strip_edges())
	)
	row.add_child(create)
	var code_row := HBoxContainer.new()
	content.add_child(code_row)
	code_output = _line(code_row, "InvitationCode", "")
	code_output.editable = false
	var copy := Button.new()
	copy.name = "CopyInvitation"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(code_output.text))
	code_row.add_child(copy)

func _build_accept_section(content: VBoxContainer) -> void:
	var title := _label(content, "")
	title.name = "AcceptTitle"
	title.add_theme_font_size_override("font_size", 20)
	accept_code_input = _line(content, "AcceptCode", "ishtaria-invite:v1.…")
	var row := HBoxContainer.new()
	content.add_child(row)
	accept_name_input = _line(row, "OwnPortalName", "brana-jih")
	var accept := Button.new()
	accept.name = "AcceptInvitation"
	accept.pressed.connect(func() -> void:
		set_feedback("")
		accept_requested.emit(accept_code_input.text.strip_edges(), accept_name_input.text.strip_edges())
	)
	row.add_child(accept)

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var dimensions := Vector2(minf(780, screen.x - 24), minf(700, screen.y - 24))
	panel.position = (screen - dimensions) / 2
	panel.size = dimensions

func open() -> void:
	show()
	_update_texts()
	refresh_requested.emit()

func set_profile(profile: Dictionary) -> void:
	_owned = {}
	for item: Variant in profile.get("inventory", {}).get("items", []):
		if item is Dictionary and item.get("item_id") is String and item.get("quantity") is String and item.quantity.is_valid_int():
			_owned[item.item_id] = int(item.quantity)
	if profile.is_empty():
		_pacts = []
		_details = {}
		hide()
	_render()

func set_busy(value: bool) -> void:
	_busy = value
	_render()

func set_feedback(message: String) -> void:
	_feedback_key = message
	feedback.text = tr(message) if not message.is_empty() else ""

func set_invitation(data: Dictionary) -> void:
	code_output.text = data.code
	set_feedback("")

## The list of pacts; details of those under construction are requested one by one.
func set_pacts(pacts: Array) -> void:
	_pacts = pacts.duplicate(true)
	var known := {}
	for pact: Dictionary in _pacts:
		known[pact.id] = true
	for id: String in _details.keys():
		if not known.has(id):
			_details.erase(id)
	_wanted.clear()
	for pact: Dictionary in _pacts:
		if pact.state == "building":
			_wanted.append(pact.id)
	_render()
	_request_next()

func set_pact(pact: Dictionary) -> void:
	_details[pact.id] = pact.duplicate(true)
	var found := false
	for index in _pacts.size():
		if _pacts[index].id == pact.id:
			_pacts[index] = pact.duplicate(true)
			found = true
	if not found:
		_pacts.push_front(pact.duplicate(true))
	_wanted.erase(pact.id)
	_render()
	_request_next()

func _request_next() -> void:
	if not _wanted.is_empty():
		details_requested.emit(_wanted[0])

func _state_text(state: String) -> String:
	match state:
		"proposed":
			return tr("Waiting for the operator")
		"accepted":
			return tr("Ready to build")
		"building":
			return tr("Under construction")
		"open":
			return tr("Open")
		"closed":
			return tr("Closed (ruins)")
	return tr("Closed")

func _item_name(requirement: Dictionary) -> String:
	if PLANK_NAMES.has(requirement.id):
		return tr(PLANK_NAMES[requirement.id])
	return tr(String(requirement.items[0]).capitalize().replace("_", " "))

## Items the player holds that count for a requirement, with the amount still needed.
func deliverable(requirement: Dictionary) -> Dictionary:
	var remaining := int(requirement.required) - int(requirement.contributed)
	if remaining <= 0:
		return {}
	for item: Variant in requirement.items:
		var owned: int = _owned.get(item, 0)
		if owned > 0:
			return {"item_id": item, "quantity": mini(owned, remaining)}
	return {}

func _update_texts() -> void:
	if not is_instance_valid(summary):
		return
	summary.text = tr("Portals")
	find_child("InviteTitle", true, false).text = tr("Invite a player to build a portal")
	find_child("AcceptTitle", true, false).text = tr("Accept an invitation")
	find_child("CreateInvitation", true, false).text = tr("Create invitation")
	find_child("CopyInvitation", true, false).text = tr("Copy")
	find_child("AcceptInvitation", true, false).text = tr("Accept")
	find_child("Close", true, false).text = tr("Close")
	name_input.placeholder_text = tr("Name of your end of the portal")
	accept_name_input.placeholder_text = tr("Name of your end of the portal")
	if not _feedback_key.is_empty():
		feedback.text = tr(_feedback_key)

func _render() -> void:
	if not is_instance_valid(pact_list):
		return
	for child in pact_list.get_children():
		pact_list.remove_child(child)
		child.queue_free()
	if _pacts.is_empty():
		_label(pact_list, tr("No portal pacts yet"))
		return
	for pact: Dictionary in _pacts:
		var detail: Dictionary = _details.get(pact.id, pact)
		var box := VBoxContainer.new()
		box.name = "Pact_" + pact.id
		pact_list.add_child(box)
		var title := _label(box, "%s → %s (%s)  ·  %s" % [pact.portal_name, pact.peer_host, pact.peer_player, _state_text(pact.state)])
		title.add_theme_font_size_override("font_size", 18)
		_actions(box, pact, detail)
		box.add_child(HSeparator.new())

func _actions(box: VBoxContainer, pact: Dictionary, detail: Dictionary) -> void:
	match pact.state:
		"accepted":
			var place := Button.new()
			place.name = "PlaceSite"
			place.text = tr("Place construction site here")
			place.disabled = _busy
			place.pressed.connect(func() -> void:
				set_feedback("")
				site_requested.emit(pact.id)
			)
			box.add_child(place)
		"building":
			if detail.get("local_built", false):
				_label(box, tr("Your end is built; waiting for the other world"))
			for requirement: Dictionary in detail.get("requirements", []):
				_requirement_row(box, pact, requirement)
	if not pact.state in FINAL_STATES:
		var cancel := Button.new()
		cancel.name = "Cancel"
		cancel.text = tr("Cancel the pact")
		cancel.disabled = _busy
		cancel.pressed.connect(func() -> void:
			set_feedback("")
			cancel_requested.emit(pact.id)
		)
		box.add_child(cancel)

func _requirement_row(box: VBoxContainer, pact: Dictionary, requirement: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "Requirement_" + requirement.id
	box.add_child(row)
	var icon := ITEM_ICONS.texture(requirement.items[0])
	if icon != null:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(40, 40)
		row.add_child(picture)
	_label(row, "%s: %s / %s" % [_item_name(requirement), requirement.contributed, requirement.required])
	var offer := deliverable(requirement)
	if not offer.is_empty() and not detail_is_built(pact):
		var button := Button.new()
		button.name = "Deliver"
		button.text = tr("Deliver %s") % offer.quantity
		button.disabled = _busy
		button.pressed.connect(func() -> void:
			set_feedback("")
			deliver_requested.emit(pact.id, offer.item_id, offer.quantity)
		)
		row.add_child(button)

func detail_is_built(pact: Dictionary) -> bool:
	return _details.get(pact.id, {}).get("local_built", false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_texts()
		_render()
