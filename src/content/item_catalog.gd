@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

const SUPPORTED_SCHEMA := 1
const ALLOWED_ITEM_KINDS := ["consumable", "material", "key", "equipment"]
const ALLOWED_EFFECT_TYPES := ["none", "heal"]


static func load_item_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	return load_catalog_group(campaign_path, campaign, "item_files", "items")


static func load_recipe_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	return load_catalog_group(campaign_path, campaign, "recipe_files", "recipes")


static func load_catalog_group(
	campaign_path: String,
	campaign: Dictionary,
	file_field: String,
	collection_field: String
) -> Dictionary:
	var errors: Array[String] = []
	var definitions: Dictionary = {}
	var files: Array = []
	var files_value: Variant = campaign.get(file_field, [])
	if typeof(files_value) != TYPE_ARRAY:
		return {
			"ok": false,
			"errors": ["%s must be an array of safe relative JSON paths." % file_field],
			"definitions": definitions,
			"files": files
		}
	for relative_value in files_value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			errors.append("Unsafe %s path: %s" % [file_field, relative_path])
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result := Repository.read_json(path)
		if not result.get("ok", false):
			append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		files.append({"path": path, "relative_path": relative_path, "data": data})
		var collection_value: Variant = data.get(collection_field, [])
		if typeof(collection_value) != TYPE_ARRAY:
			errors.append("%s: %s must be an array." % [path, collection_field])
			continue
		for record_value in collection_value:
			if typeof(record_value) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_value
			var identifier := str(record.get("id", ""))
			if identifier.is_empty():
				continue
			if definitions.has(identifier):
				errors.append("%s: duplicate %s id '%s'." % [path, collection_field.trim_suffix("s"), identifier])
				continue
			definitions[identifier] = record
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"definitions": definitions,
		"files": files
	}


static func primary_item_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	return primary_catalog_path(campaign_path, campaign, "item_files", "items/core.json")


static func primary_recipe_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	return primary_catalog_path(campaign_path, campaign, "recipe_files", "recipes/core.json")


static func primary_catalog_path(
	campaign_path: String,
	campaign: Dictionary,
	file_field: String,
	fallback_relative_path: String
) -> String:
	var files_value: Variant = campaign.get(file_field, [])
	if typeof(files_value) == TYPE_ARRAY:
		for relative_value in files_value:
			var relative_path := str(relative_value)
			if ObjectCatalog.safe_relative_json_path(relative_path):
				return campaign_path.get_base_dir().path_join(relative_path)
	return campaign_path.get_base_dir().path_join(fallback_relative_path)


static func item(definitions: Dictionary, item_id: String) -> Dictionary:
	var value: Variant = definitions.get(item_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func recipe(definitions: Dictionary, recipe_id: String) -> Dictionary:
	var value: Variant = definitions.get(recipe_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func item_kind(definition_data: Dictionary) -> String:
	return str(definition_data.get("kind", "material"))


static func item_name(definition_data: Dictionary, fallback: String = "Item") -> String:
	return str(definition_data.get("display_name", fallback))


static func stack_limit(definition_data: Dictionary) -> int:
	return clampi(int(definition_data.get("stack_limit", 1)), 1, 999)


static func use_effect(definition_data: Dictionary) -> Dictionary:
	var value: Variant = definition_data.get("use_effect", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func item_grants(record: Dictionary, field: String = "item_grants") -> Array:
	var output: Array = []
	var value: Variant = record.get(field, [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for grant_value in value:
		if typeof(grant_value) != TYPE_DICTIONARY:
			continue
		var grant: Dictionary = grant_value
		var item_id := str(grant.get("item_id", ""))
		var quantity := int(grant.get("quantity", 0))
		if not item_id.is_empty() and quantity > 0:
			output.append({"item_id": item_id, "quantity": quantity})
	return output


static func recipe_unlocks(record: Dictionary, field: String = "unlock_recipes") -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = record.get(field, [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for recipe_value in value:
		var recipe_id := str(recipe_value)
		if not recipe_id.is_empty() and not output.has(recipe_id):
			output.append(recipe_id)
	return output


static func starting_inventory(campaign: Dictionary) -> Array:
	var output: Array = []
	var value: Variant = campaign.get("starting_inventory", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for entry_value in value:
		if typeof(entry_value) == TYPE_DICTIONARY:
			output.append(entry_value)
	return output


static func starting_recipes(campaign: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = campaign.get("starting_recipes", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for recipe_value in value:
		var recipe_id := str(recipe_value)
		if not recipe_id.is_empty() and not output.has(recipe_id):
			output.append(recipe_id)
	return output


static func default_item_catalog() -> Dictionary:
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"items": [
			{
				"id": "trail_tonic",
				"display_name": "Trail Tonic",
				"kind": "consumable",
				"description": "A bitter restorative carried for uncertain roads.",
				"stack_limit": 9,
				"value": 18,
				"use_effect": {"type": "heal", "amount": 10}
			},
			{
				"id": "brass_scrap",
				"display_name": "Brass Scrap",
				"kind": "material",
				"description": "Soft brass fragments suitable for field repairs and simple compounds.",
				"stack_limit": 99,
				"value": 3,
				"use_effect": {"type": "none"}
			},
			{
				"id": "field_salve",
				"display_name": "Field Salve",
				"kind": "consumable",
				"description": "A warm salve mixed from metal salts and medicinal oil.",
				"stack_limit": 9,
				"value": 28,
				"use_effect": {"type": "heal", "amount": 16}
			}
		]
	}


static func default_recipe_catalog() -> Dictionary:
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"recipes": [
			{
				"id": "field_salve_recipe",
				"display_name": "Mix Field Salve",
				"description": "Combine prepared brass salts with a trail tonic base.",
				"ingredients": [
					{"item_id": "brass_scrap", "quantity": 2},
					{"item_id": "trail_tonic", "quantity": 1}
				],
				"output": {"item_id": "field_salve", "quantity": 1},
				"unlocked_by_default": true
			}
		]
	}


static func default_item(item_id: String, display_name: String) -> Dictionary:
	return {
		"id": item_id,
		"display_name": display_name,
		"kind": "material",
		"description": "Describe this original campaign item.",
		"stack_limit": 99,
		"value": 0,
		"use_effect": {"type": "none"}
	}


static func default_recipe(recipe_id: String, display_name: String, item_id: String) -> Dictionary:
	return {
		"id": recipe_id,
		"display_name": display_name,
		"description": "Describe how and why this recipe matters.",
		"ingredients": [{"item_id": item_id, "quantity": 1}],
		"output": {"item_id": item_id, "quantity": 1},
		"unlocked_by_default": false
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
