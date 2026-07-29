@tool
extends RefCounted

const SCHEMA_VERSION := 1
const ALLOWED_KINDS := ["prop", "npc", "enemy", "pickup"]
const ALLOWED_SHAPES := ["crate", "person", "beast", "orb", "pillar", "marker"]


static func default_catalog() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"objects": [
			{
				"id": "brass_supply_crate",
				"display_name": "Brass Supply Crate",
				"kind": "prop",
				"appearance": {"shape": "crate", "color": "7f6548", "accent": "d6ba78"},
				"solid": true,
				"collision_radius": 12,
				"interaction_radius": 36,
				"dialogue": "A museum shipping crate, stamped with a date that has not happened."
			},
			{
				"id": "lost_archivist",
				"display_name": "Lost Archivist",
				"kind": "npc",
				"appearance": {"shape": "person", "color": "526b82", "accent": "e4c39e"},
				"solid": true,
				"collision_radius": 9,
				"interaction_radius": 46,
				"dialogue": "The catalogues changed first. Then the rooms began remembering other years."
			},
			{
				"id": "ash_hound",
				"display_name": "Ash Hound",
				"kind": "enemy",
				"appearance": {"shape": "beast", "color": "5d3432", "accent": "dd7652"},
				"solid": true,
				"collision_radius": 9,
				"interaction_radius": 0,
				"max_health": 12,
				"move_speed": 58,
				"awareness_radius": 132,
				"attack_radius": 20,
				"attack_damage": 4,
				"attack_cooldown": 1.05,
				"reward": 2
			},
			{
				"id": "clock_shard",
				"display_name": "Clock Shard",
				"kind": "pickup",
				"appearance": {"shape": "orb", "color": "d9c36e", "accent": "fff1ae"},
				"solid": false,
				"collision_radius": 5,
				"interaction_radius": 18,
				"pickup_value": 1,
				"pickup_label": "Clock shard recovered."
			}
		]
	}


static func object_files(campaign: Dictionary) -> Array:
	var value: Variant = campaign.get("object_files", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func primary_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	for relative_value in object_files(campaign):
		return campaign_path.get_base_dir().path_join(String(relative_value))
	return campaign_path.get_base_dir().path_join("objects/core.json")


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var definitions: Dictionary = {}
	var ordered_ids := PackedStringArray()
	var errors: Array[String] = []
	var files: Array = []
	for relative_value in object_files(campaign):
		var relative_path := String(relative_value)
		if not safe_relative_json_path(relative_path):
			errors.append("Unsafe object catalog path: %s" % relative_path)
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result := read_json(path)
		if not result.get("ok", false):
			append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		files.append({"path": path, "relative_path": relative_path, "data": data})
		var objects_value: Variant = data.get("objects", [])
		if typeof(objects_value) != TYPE_ARRAY:
			errors.append("%s: objects must be an array." % path)
			continue
		for definition_value in objects_value:
			if typeof(definition_value) != TYPE_DICTIONARY:
				errors.append("%s: object definitions must be objects." % path)
				continue
			var definition_data: Dictionary = definition_value
			var object_id := String(definition_data.get("id", ""))
			if object_id.is_empty():
				errors.append("%s: object definition is missing an id." % path)
				continue
			if definitions.has(object_id):
				errors.append("Duplicate object definition id '%s'." % object_id)
				continue
			definitions[object_id] = definition_data
			ordered_ids.append(object_id)
	return {
		"ok": errors.is_empty(),
		"definitions": definitions,
		"ordered_ids": ordered_ids,
		"files": files,
		"errors": errors
	}


static func definition(definitions: Dictionary, object_id: String) -> Dictionary:
	var value: Variant = definitions.get(object_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func appearance_color(definition_data: Dictionary, key: String, fallback: String) -> Color:
	var appearance_value: Variant = definition_data.get("appearance", {})
	if typeof(appearance_value) != TYPE_DICTIONARY:
		return Color.from_string(fallback, Color.WHITE)
	var appearance: Dictionary = appearance_value
	return Color.from_string(
		String(appearance.get(key, fallback)),
		Color.from_string(fallback, Color.WHITE)
	)


static func state_key(map_id: String, placement: Dictionary) -> String:
	var authored := String(placement.get("state_key", "")).strip_edges()
	if not authored.is_empty():
		return authored
	return "%s:%s" % [map_id, placement.get("id", "placement")]


static func placement_is_available(placement: Dictionary, era_id: String) -> bool:
	var available_value: Variant = placement.get("available_eras", [])
	if typeof(available_value) != TYPE_ARRAY:
		return true
	var available: Array = available_value
	return available.is_empty() or available.has(era_id)


static func dialogue_for(definition_data: Dictionary, era_id: String) -> String:
	var dialogue: Variant = definition_data.get("dialogue", "")
	if typeof(dialogue) == TYPE_STRING:
		return String(dialogue)
	if typeof(dialogue) == TYPE_DICTIONARY:
		var by_era: Dictionary = dialogue
		return String(by_era.get(era_id, by_era.get("default", "...")))
	return "..."


static func default_definition(object_id: String, display_name: String = "New Object") -> Dictionary:
	return {
		"id": object_id,
		"display_name": display_name,
		"kind": "prop",
		"appearance": {"shape": "crate", "color": "66717a", "accent": "d4c68f"},
		"solid": true,
		"collision_radius": 10,
		"interaction_radius": 34,
		"dialogue": "This object still needs authored behaviour."
	}


static func default_placement(placement_id: String, object_id: String, position: Vector2) -> Dictionary:
	return {
		"id": placement_id,
		"object_id": object_id,
		"position": {"x": snappedf(position.x, 0.001), "y": snappedf(position.y, 0.001)},
		"facing": "down",
		"available_eras": [],
		"state_key": ""
	}


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "errors": ["File does not exist: %s" % path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}, "errors": ["Could not open file: %s" % path]}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		return {
			"ok": false,
			"data": {},
			"errors": ["%s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()]]
		}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "errors": ["Root value must be an object: %s" % path]}
	return {"ok": true, "data": parser.data, "errors": []}


static func safe_relative_json_path(path: String) -> bool:
	return (
		not path.is_empty()
		and not path.begins_with("/")
		and not path.begins_with("\\")
		and not path.contains("..")
		and not path.contains("://")
		and path.get_extension().to_lower() == "json"
	)


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(String(message))
