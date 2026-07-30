@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")

const SUPPORTED_SCHEMA := 1
const ALLOWED_STEP_TYPES := [
	"wait",
	"dialogue",
	"camera",
	"move_actor",
	"set_era",
	"fade",
	"effects",
	"checkpoint"
]
const ALLOWED_FADE_DIRECTIONS := ["in", "out"]
const ALLOWED_CAMERA_TARGETS := ["player", "companion", "world"]


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var files: Array = []
	var definitions: Dictionary = {}
	var sources: Dictionary = {}
	var files_value: Variant = campaign.get("cinematic_files", [])
	if typeof(files_value) != TYPE_ARRAY:
		return {
			"ok": false,
			"errors": ["%s: cinematic_files must be an array of safe relative JSON paths." % campaign.get("id", campaign_path)],
			"files": files,
			"definitions": definitions,
			"sources": sources
		}
	for relative_value in files_value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe cinematic catalog path '%s'." % [campaign.get("id", campaign_path), relative_path])
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result := Repository.read_json(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		files.append({"path": path, "relative_path": relative_path, "data": data})
		var sequences_value: Variant = data.get("cinematics", [])
		if typeof(sequences_value) != TYPE_ARRAY:
			errors.append("%s: cinematics must be an array." % path)
			continue
		for sequence_value in sequences_value:
			if typeof(sequence_value) != TYPE_DICTIONARY:
				errors.append("%s: every cinematic must be an object." % path)
				continue
			var sequence: Dictionary = sequence_value
			var cinematic_id := str(sequence.get("id", ""))
			if cinematic_id.is_empty():
				continue
			if definitions.has(cinematic_id):
				errors.append("%s: cinematic id '%s' is also declared by %s." % [path, cinematic_id, sources.get(cinematic_id, "another catalog")])
				continue
			definitions[cinematic_id] = sequence
			sources[cinematic_id] = path
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"files": files,
		"definitions": definitions,
		"sources": sources
	}


static func primary_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	var value: Variant = campaign.get("cinematic_files", [])
	if typeof(value) == TYPE_ARRAY:
		for relative_value in value:
			var relative_path := str(relative_value)
			if ObjectCatalog.safe_relative_json_path(relative_path):
				return campaign_path.get_base_dir().path_join(relative_path)
	return campaign_path.get_base_dir().path_join("cinematics").path_join("core.json")


static func cinematic(definitions: Dictionary, cinematic_id: String) -> Dictionary:
	var value: Variant = definitions.get(cinematic_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func steps(sequence: Dictionary) -> Array:
	var value: Variant = sequence.get("steps", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func display_name(sequence: Dictionary) -> String:
	return str(sequence.get("display_name", sequence.get("id", "Cinematic"))).strip_edges()


static func map_id(sequence: Dictionary) -> String:
	return str(sequence.get("map_id", "")).strip_edges()


static func completion_state_key(sequence: Dictionary) -> String:
	return str(sequence.get("completion_state_key", "")).strip_edges()


static func is_skippable(sequence: Dictionary) -> bool:
	return bool(sequence.get("skippable", true))


static func is_letterboxed(sequence: Dictionary) -> bool:
	return bool(sequence.get("letterbox", true))


static func trigger_once(sequence: Dictionary) -> bool:
	return bool(sequence.get("trigger_once", true))


static func available_in_era(sequence: Dictionary, era_id: String) -> bool:
	var value: Variant = sequence.get("available_eras", [])
	if typeof(value) != TYPE_ARRAY:
		return true
	var available: Array = value
	return available.is_empty() or available.has(era_id)


static func effects(sequence: Dictionary, field: String = "completion_effects") -> Array:
	var value: Variant = sequence.get(field, [])
	return value if typeof(value) == TYPE_ARRAY else []


static func step_type(step: Dictionary) -> String:
	return str(step.get("type", "wait"))


static func step_duration(step: Dictionary) -> float:
	return maxf(0.0, float(step.get("duration", 0.0)))


static func step_text(step: Dictionary, era_id: String) -> String:
	return StoryCatalog.resolved_text(step.get("text", ""), era_id, "...")


static func default_catalog() -> Dictionary:
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"cinematics": [default_sequence("arrival", "Arrival")]
	}


static func default_sequence(cinematic_id: String, name: String) -> Dictionary:
	return {
		"id": cinematic_id,
		"display_name": name,
		"map_id": "first_crossing",
		"available_eras": [],
		"skippable": true,
		"letterbox": true,
		"trigger_once": true,
		"completion_state_key": "cinematic:%s" % cinematic_id,
		"steps": [
			{
				"id": "fade_in",
				"type": "fade",
				"direction": "in",
				"duration": 0.5
			},
			{
				"id": "opening_line",
				"type": "dialogue",
				"speaker": "NARRATOR",
				"text": "The crossing remembers a road that has not yet been taken.",
				"duration": 2.5,
				"advance_on_confirm": true
			}
		],
		"completion_effects": [
			{"type": "set_state", "key": "cinematic:%s" % cinematic_id, "value": "completed"}
		],
		"skip_effects": []
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
