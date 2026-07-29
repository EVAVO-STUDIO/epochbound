extends RefCounted

const ItemCatalog = preload("res://src/content/item_catalog.gd")


static func initial_inventory(campaign: Dictionary, item_definitions: Dictionary) -> Dictionary:
	var inventory: Dictionary = {}
	for entry_value in ItemCatalog.starting_inventory(campaign):
		var entry: Dictionary = entry_value
		var item_id := str(entry.get("item_id", ""))
		var definition_data := ItemCatalog.item(item_definitions, item_id)
		if definition_data.is_empty():
			continue
		var quantity := clampi(
			int(entry.get("quantity", 0)),
			0,
			ItemCatalog.stack_limit(definition_data)
		)
		if quantity > 0:
			inventory[item_id] = quantity
	return inventory


static func initial_recipe_unlocks(campaign: Dictionary, recipe_definitions: Dictionary) -> Dictionary:
	var unlocked: Dictionary = {}
	for recipe_id in recipe_definitions.keys():
		var recipe_data := ItemCatalog.recipe(recipe_definitions, str(recipe_id))
		if bool(recipe_data.get("unlocked_by_default", false)):
			unlocked[str(recipe_id)] = true
	for recipe_id in ItemCatalog.starting_recipes(campaign):
		if recipe_definitions.has(recipe_id):
			unlocked[recipe_id] = true
	return unlocked


static func count(inventory: Dictionary, item_id: String) -> int:
	return maxi(0, int(inventory.get(item_id, 0)))


static func add_item(
	inventory: Dictionary,
	item_definitions: Dictionary,
	item_id: String,
	quantity: int
) -> Dictionary:
	var definition_data := ItemCatalog.item(item_definitions, item_id)
	if definition_data.is_empty() or quantity <= 0:
		return {"ok": false, "added": 0, "overflow": maxi(0, quantity)}
	var current := count(inventory, item_id)
	var maximum := ItemCatalog.stack_limit(definition_data)
	var added := mini(quantity, maximum - current)
	if added > 0:
		inventory[item_id] = current + added
	return {"ok": added > 0, "added": added, "overflow": quantity - added}


static func add_grants(
	inventory: Dictionary,
	item_definitions: Dictionary,
	grants: Array
) -> Dictionary:
	var added: Dictionary = {}
	var overflow: Dictionary = {}
	for grant_value in grants:
		if typeof(grant_value) != TYPE_DICTIONARY:
			continue
		var grant: Dictionary = grant_value
		var item_id := str(grant.get("item_id", ""))
		var quantity := int(grant.get("quantity", 0))
		var result := add_item(inventory, item_definitions, item_id, quantity)
		var added_quantity := int(result.get("added", 0))
		var overflow_quantity := int(result.get("overflow", 0))
		if added_quantity > 0:
			added[item_id] = int(added.get(item_id, 0)) + added_quantity
		if overflow_quantity > 0:
			overflow[item_id] = int(overflow.get(item_id, 0)) + overflow_quantity
	return {"added": added, "overflow": overflow}


static func remove_item(inventory: Dictionary, item_id: String, quantity: int) -> bool:
	if quantity <= 0 or count(inventory, item_id) < quantity:
		return false
	var next_quantity := count(inventory, item_id) - quantity
	if next_quantity <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = next_quantity
	return true


static func ingredients(recipe_data: Dictionary) -> Array:
	var output: Array = []
	var value: Variant = recipe_data.get("ingredients", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for ingredient_value in value:
		if typeof(ingredient_value) == TYPE_DICTIONARY:
			output.append(ingredient_value)
	return output


static func recipe_output(recipe_data: Dictionary) -> Dictionary:
	var value: Variant = recipe_data.get("output", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func missing_ingredients(recipe_data: Dictionary, inventory: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	for ingredient_value in ingredients(recipe_data):
		var ingredient: Dictionary = ingredient_value
		var item_id := str(ingredient.get("item_id", ""))
		var required := maxi(1, int(ingredient.get("quantity", 1)))
		var available := count(inventory, item_id)
		if available < required:
			missing.append("%s:%d" % [item_id, required - available])
	return missing


static func can_craft(
	recipe_data: Dictionary,
	inventory: Dictionary,
	item_definitions: Dictionary
) -> bool:
	if recipe_data.is_empty() or not missing_ingredients(recipe_data, inventory).is_empty():
		return false
	var output := recipe_output(recipe_data)
	var item_id := str(output.get("item_id", ""))
	var quantity := maxi(1, int(output.get("quantity", 1)))
	var definition_data := ItemCatalog.item(item_definitions, item_id)
	if definition_data.is_empty():
		return false
	return count(inventory, item_id) + quantity <= ItemCatalog.stack_limit(definition_data)


static func craft(
	recipe_data: Dictionary,
	inventory: Dictionary,
	item_definitions: Dictionary
) -> Dictionary:
	if not can_craft(recipe_data, inventory, item_definitions):
		return {"ok": false, "item_id": "", "quantity": 0}
	for ingredient_value in ingredients(recipe_data):
		var ingredient: Dictionary = ingredient_value
		remove_item(
			inventory,
			str(ingredient.get("item_id", "")),
			maxi(1, int(ingredient.get("quantity", 1)))
		)
	var output := recipe_output(recipe_data)
	var item_id := str(output.get("item_id", ""))
	var quantity := maxi(1, int(output.get("quantity", 1)))
	var add_result := add_item(inventory, item_definitions, item_id, quantity)
	return {
		"ok": int(add_result.get("added", 0)) == quantity,
		"item_id": item_id,
		"quantity": int(add_result.get("added", 0))
	}


static func sorted_inventory_ids(inventory: Dictionary, item_definitions: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	for item_id in inventory.keys():
		if count(inventory, str(item_id)) > 0 and item_definitions.has(item_id):
			ids.append(str(item_id))
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_name := ItemCatalog.item_name(ItemCatalog.item(item_definitions, left), left)
		var right_name := ItemCatalog.item_name(ItemCatalog.item(item_definitions, right), right)
		return left_name.naturalnocasecmp_to(right_name) < 0
	)
	return ids


static func sorted_recipe_ids(unlocked: Dictionary, recipe_definitions: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	for recipe_id in unlocked.keys():
		if bool(unlocked.get(recipe_id, false)) and recipe_definitions.has(recipe_id):
			ids.append(str(recipe_id))
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_data := ItemCatalog.recipe(recipe_definitions, left)
		var right_data := ItemCatalog.recipe(recipe_definitions, right)
		return str(left_data.get("display_name", left)).naturalnocasecmp_to(str(right_data.get("display_name", right))) < 0
	)
	return ids


static func first_healing_item(inventory: Dictionary, item_definitions: Dictionary) -> String:
	for item_id in sorted_inventory_ids(inventory, item_definitions):
		var definition_data := ItemCatalog.item(item_definitions, item_id)
		if ItemCatalog.item_kind(definition_data) != "consumable":
			continue
		var effect := ItemCatalog.use_effect(definition_data)
		if str(effect.get("type", "none")) == "heal" and int(effect.get("amount", 0)) > 0:
			return item_id
	return ""


static func grant_summary(grants: Dictionary, item_definitions: Dictionary) -> String:
	var parts := PackedStringArray()
	for item_id in grants.keys():
		var definition_data := ItemCatalog.item(item_definitions, str(item_id))
		parts.append("%s x%d" % [ItemCatalog.item_name(definition_data, str(item_id)), int(grants.get(item_id, 0))])
	return ", ".join(parts)
