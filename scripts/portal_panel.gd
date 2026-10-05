extends CanvasLayer
## The player's portals: building one, and linking a finished one with a portal of another
## world by a share link. All decisions are the server's; the panel shows what it reports and
## sends the player's intentions.

signal build_requested(portal_name: String)
signal refresh_requested
signal details_requested(portal_id: String)
signal deliver_requested(portal_id: String, item_id: String, quantity: int)
signal link_requested(portal_id: String)
signal connect_requested(portal_id: String, link: String)
signal disconnect_requested(portal_id: String)
signal close_requested(portal_id: String)

const ITEM_ICONS := preload("res://scripts/item_icons.gd")
const PLANK_NAMES := {"plank": "Planks (any wood)"}

var panel: PanelContainer
var summary: Label
var feedback: Label
var name_input: LineEdit
var link_output: LineEdit
var portal_list: VBoxContainer
var _portals: Array = []
var _details: Dictionary = {}
var _owned: Dictionary = {}
var _pasted: Dictionary = {}
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
	var title := _label(content, "")
	title.name = "BuildTitle"
	title.add_theme_font_size_override("font_size", 20)
	var row := HBoxContainer.new()
	content.add_child(row)
	name_input = _line(row, "PortalName", "brana-sever")
	var build := Button.new()
	build.name = "Build"
	build.pressed.connect(func() -> void:
		set_feedback("")
		build_requested.emit(name_input.text.strip_edges())
	)
	row.add_child(build)
	link_output = _line(content, "ShareLink", "")
	link_output.editable = false
	portal_list = VBoxContainer.new()
	portal_list.name = "Portals"
	portal_list.add_theme_constant_override("separation", 8)
	content.add_child(portal_list)
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
		_portals = []
		_details = {}
		_pasted = {}
		link_output.text = ""
		hide()
	_render()

func set_busy(value: bool) -> void:
	_busy = value
	_render()

func set_feedback(message: String) -> void:
	_feedback_key = message
	feedback.text = tr(message) if not message.is_empty() else ""

## The share link of a finished portal: shown and copied to the clipboard.
func set_link(link: String) -> void:
	link_output.text = link
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(link)
	set_feedback("Share link copied")

## The list of portals; details of those under construction are requested one by one.
func set_portals(portals: Array) -> void:
	_portals = portals.duplicate(true)
	var known := {}
	for portal: Dictionary in _portals:
		known[portal.id] = true
	for id: String in _details.keys():
		if not known.has(id):
			_details.erase(id)
	_wanted.clear()
	for portal: Dictionary in _portals:
		if portal.state == "building":
			_wanted.append(portal.id)
	_render()
	_request_next()

func set_portal(portal: Dictionary) -> void:
	_details[portal.id] = portal.duplicate(true)
	var found := false
	for index in _portals.size():
		if _portals[index].id == portal.id:
			_portals[index] = portal.duplicate(true)
			found = true
	if not found:
		_portals.push_front(portal.duplicate(true))
	_wanted.erase(portal.id)
	if portal.state != "built":
		_pasted.erase(portal.id)
	_render()
	_request_next()

func _request_next() -> void:
	if not _wanted.is_empty():
		details_requested.emit(_wanted[0])

func _state_text(state: String) -> String:
	match state:
		"building":
			return tr("Under construction")
		"built":
			return tr("Finished, not linked")
		"pending":
			return tr("Linked, waiting for the operator")
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
	find_child("BuildTitle", true, false).text = tr("Build a portal where you stand")
	find_child("Build", true, false).text = tr("Build")
	find_child("Close", true, false).text = tr("Close")
	name_input.placeholder_text = tr("Name of the portal")
	link_output.placeholder_text = tr("The share link of a finished portal appears here")
	if not _feedback_key.is_empty():
		feedback.text = tr(_feedback_key)

func _render() -> void:
	if not is_instance_valid(portal_list):
		return
	for child in portal_list.get_children():
		portal_list.remove_child(child)
		child.queue_free()
	if _portals.is_empty():
		_label(portal_list, tr("No portals yet"))
		return
	for portal: Dictionary in _portals:
		var detail: Dictionary = _details.get(portal.id, portal)
		var box := VBoxContainer.new()
		box.name = "Portal_" + portal.id
		portal_list.add_child(box)
		var title := _label(box, "%s  ·  %s" % [portal.portal_name, _state_text(portal.state)])
		title.add_theme_font_size_override("font_size", 18)
		_actions(box, portal, detail)
		box.add_child(HSeparator.new())

func _button(parent: Node, name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = name
	button.text = text
	button.disabled = _busy
	button.pressed.connect(func() -> void:
		set_feedback("")
		action.call()
	)
	parent.add_child(button)
	return button

func _actions(box: VBoxContainer, portal: Dictionary, detail: Dictionary) -> void:
	match portal.state:
		"building":
			for requirement: Dictionary in detail.get("requirements", []):
				_requirement_row(box, portal, requirement)
		"built":
			# The two things a finished portal offers: its own link, and another portal's link.
			_button(box, "CopyLink", tr("Copy share link"), func() -> void: link_requested.emit(portal.id))
			var row := HBoxContainer.new()
			box.add_child(row)
			var paste := _line(row, "PasteLink", "ishtaria-portal:v1.…")
			paste.text = _pasted.get(portal.id, "")
			paste.text_changed.connect(func(text: String) -> void: _pasted[portal.id] = text)
			_button(row, "Connect", tr("Connect"), func() -> void: connect_requested.emit(portal.id, paste.text.strip_edges()))
		"pending", "open":
			var peer := "%s (%s)" % [portal.get("peer_portal_name", ""), portal.get("peer_host", "")]
			_label(box, tr("Linked with %s") % peer)
			_button(box, "Disconnect", tr("Break the link"), func() -> void: disconnect_requested.emit(portal.id))
	if portal.state != "closed":
		_button(box, "CloseRuin", tr("Close the portal"), func() -> void: close_requested.emit(portal.id))

func _requirement_row(box: VBoxContainer, portal: Dictionary, requirement: Dictionary) -> void:
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
	if not offer.is_empty():
		_button(row, "Deliver", tr("Deliver %s") % offer.quantity, func() -> void: deliver_requested.emit(portal.id, offer.item_id, offer.quantity))

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_texts()
		_render()
