extends RefCounted
## Inventory icons: Food Kit pictures for food and icons baked from the bundled
## Kenney 3D models (tools/bake-item-icons.gd) for the other items.

const FOOD := "res://assets/kenney/food-kit/"
const BAKED := "res://assets/icons/items/"
const FOODS := ["apple", "bread", "cheese", "carrot"]
## Story items without an icon of their own may borrow the icon of a similar bundled item.
const ALIASES := {}

static func path_for(item_id: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("^[a-z0-9_]{1,40}$")
	if pattern.search(item_id) == null:
		return ""
	item_id = ALIASES.get(item_id, item_id)
	if item_id in FOODS:
		return FOOD + item_id + ".png"
	return BAKED + item_id + ".png"

static func texture(item_id: String) -> Texture2D:
	var path := path_for(item_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
