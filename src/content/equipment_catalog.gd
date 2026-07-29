@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")

const SUPPORTED_SCHEMA := 1
const MAX_CAPABILITY_ID_LENGTH := 80
const MAX_DESCRIPTION_LENGTH := 1200
const MODIFIER_FIELDS := [
	"attack_bonus",
	"defense_bonus",
	"max_health_bonus",
	"move_speed_bonus"
]


static func load_capability_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var definitions: Dictionary = {}
	var files: Array = []
	var sources: Dictionary = {}
	var value: Variant = campaign.get("capability_files", [])
	if typeof(value) != TYPE_ARRAY:
		return {
			"ok": false,
			"errors": ["%s: capability_files must be an array of safe relative JSON paths." % campaign.get("id", campaign_path)],
			"definitions": definitions,
			"files": files,
			"sources": sources
		}
	for relative_value in value:
		var relative_path: String = str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			errors.append("Unsafe capability_files path: %s" % relative_path)
			continue
		var path: String = campaign_path.get_base_dir().path_join(relative_path)
		var result: Dictionary = Repository.read_json(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		files.append({"path": path, "relative_path": relative_path, "data": data})
		var capabilities_value: Variant = data.get("capabilities", [])
		if typeof(capabilities_value) != TYPE_ARRAY:
			errors.append("%s: capabilities must be an array." % path)
			continue
		for capability_value in capabilities_value:
			if typeof(capability_value) != TYPE_DICTIONARY:
				continue
			var capability_data: Dictionary = capability_value
			var capability_id: String = str(capability_data.get("id", ""))
			if capability_id.is_empty():
				continue
			if definitions.has(capability_id):
				errors.append("%s: capability id '%s' is also declared by %s." % [path, capability_id, sources.get(capability_id, "another catalog")])
				continue
			definitions[capability_id] = capability_data
			sources[capability_id] = path
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"definitions": definitions,
		"files": files,
		"sources": sources
	}


static func primary_capability_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	var value: Variant = campaign.get("capability_files", [])
	if typeof(value) == TYPE_ARRAY:
		for relative_value in value:
			var relative_path: String = str(relative_value)
			if ObjectCatalog.safe_relative_json_path(relative_path):
				return campaign_path.get_base_dir().path_join(relative_path)
	return campaign_path.get_base_dir().path_join("capabilities").path_join("core.json")


static func capability(definitions: Dictionary, capability_id: String) -> Dictionary:
	var value: Variant = definitions.get(capability_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func capability_name(definitions: Dictionary, capability_id: String) -> String:
	var data: Dictionary = capability(definitions, capability_id)
	return str(data.get("display_name", capability_id.replace("_", " ").capitalize()))


static func slot_records(campaign: Dictionary) -> Array:
	var output: Array = []
	var value: Variant = campaign.get("equipment_slots", [])
	if typeof(value) == TYPE_ARRAY:
		for slot_value in value:
			if typeof(slot_value) == TYPE_DICTIONARY:
				output.append(slot_value)
	if output.is_empty():
		return default_slots()
	return output


static func slot_index(campaign: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for slot_value in slot_records(campaign):
		var slot_data: Dictionary = slot_value
		var slot_id: String = str(slot_data.get("id", ""))
		if not slot_id.is_empty():
			output[slot_id] = slot_data
	return output


static func slot_ids(campaign: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for slot_value in slot_records(campaign):
		var slot_data: Dictionary = slot_value
		var slot_id: String = str(slot_data.get("id", ""))
		if not slot_id.is_empty():
			output.append(slot_id)
	return output


static func slot_name(campaign: Dictionary, slot_id: String) -> String:
	var slots: Dictionary = slot_index(campaign)
	var value: Variant = slots.get(slot_id, {})
	if typeof(value) == TYPE_DICTIONARY:
		return str((value as Dictionary).get("display_name", slot_id.replace("_", " ").capitalize()))
	return slot_id.replace("_", " ").capitalize()


static func starting_equipment(campaign: Dictionary) -> Dictionary:
	var value: Variant = campaign.get("starting_equipment", {})
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


static func base_capabilities(campaign: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = campaign.get("base_capabilities", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for capability_value in value:
		var capability_id: String = str(capability_value).strip_edges()
		if not capability_id.is_empty() and not output.has(capability_id):
			output.append(capability_id)
	return output


static func equipment_data(item_data: Dictionary) -> Dictionary:
	var value: Variant = item_data.get("equipment", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func equipment_slot(item_data: Dictionary) -> String:
	return str(equipment_data(item_data).get("slot", ""))


static func modifier(item_data: Dictionary, field: String) -> float:
	if not MODIFIER_FIELDS.has(field):
		return 0.0
	return float(equipment_data(item_data).get(field, 0.0))


static func granted_capabilities(item_data: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = equipment_data(item_data).get("capabilities", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for capability_value in value:
		var capability_id: String = str(capability_value).strip_edges()
		if not capability_id.is_empty() and not output.has(capability_id):
			output.append(capability_id)
	return output


static func required_capabilities(record: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = record.get("required_capabilities", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for capability_value in value:
		var capability_id: String = str(capability_value).strip_edges()
		if not capability_id.is_empty() and not output.has(capability_id):
			output.append(capability_id)
	return output


static func default_capability_catalog() -> Dictionary:
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"capabilities": [
			default_capability(
				"illuminate_dark",
				"Illuminate Darkness",
				"Allows the player to enter and interpret spaces where ordinary ambient light is insufficient."
			),
			default_capability(
				"cut_clockvines",
				"Cut Clockvines",
				"Allows a suitable weapon to cut fibrous growth hardened by displaced time."
			),
			default_capability(
				"clockglass_sight",
				"Clockglass Sight",
				"Reveals seams, inscriptions and mechanisms hidden beneath an object's remembered surface."
			)
		]
	}


static func default_capability(capability_id: String, display_name: String, description: String = "") -> Dictionary:
	return {
		"id": capability_id,
		"display_name": display_name,
		"description": description
	}


static func default_slots() -> Array:
	return [
		{"id": "weapon", "display_name": "Weapon"},
		{"id": "body", "display_name": "Body"},
		{"id": "tool", "display_name": "Tool"}
	]


static func default_equipment(slot_id: String = "tool") -> Dictionary:
	return {
		"slot": slot_id,
		"attack_bonus": 0,
		"defense_bonus": 0,
		"max_health_bonus": 0,
		"move_speed_bonus": 0.0,
		"capabilities": []
	}


static func equipment_item_ids(item_definitions: Dictionary) -> PackedStringArray:
	var ids: Array[String] = []
	for item_id_value in item_definitions.keys():
		var item_id: String = str(item_id_value)
		var item_data: Dictionary = ItemCatalog.item(item_definitions, item_id)
		if ItemCatalog.item_kind(item_data) == "equipment":
			ids.append(item_id)
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_name: String = ItemCatalog.item_name(ItemCatalog.item(item_definitions, left), left)
		var right_name: String = ItemCatalog.item_name(ItemCatalog.item(item_definitions, right), right)
		return left_name.naturalnocasecmp_to(right_name) < 0
	)
	return PackedStringArray(ids)


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
