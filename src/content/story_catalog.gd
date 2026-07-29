@tool
extends RefCounted

const SUPPORTED_SCHEMA := 1
const ALLOWED_NODE_KINDS := ["line", "choice", "end"]
const ALLOWED_CONDITION_TYPES := [
	"always",
	"has_item",
	"has_capability",
	"state_equals",
	"quest_status",
	"quest_stage",
	"map_is",
	"era_is",
	"clock_shards_at_least",
	"currency_at_least"
]
const ALLOWED_EFFECT_TYPES := [
	"start_quest",
	"advance_quest",
	"complete_quest",
	"set_quest_stage",
	"set_state",
	"grant_item",
	"remove_item",
	"unlock_recipe",
	"grant_clock_shards",
	"grant_currency",
	"remove_currency",
	"message"
]


static func safe_relative_json_path(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or not path.ends_with(".json"):
		return false
	for part in path.replace("\\", "/").split("/", false):
		if part == ".." or part == "." or part.is_empty():
			return false
	return true


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


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var files: Array = []
	var conversations: Dictionary = {}
	var quests: Dictionary = {}
	var conversation_sources: Dictionary = {}
	var quest_sources: Dictionary = {}
	var value: Variant = campaign.get("story_files", [])
	if typeof(value) != TYPE_ARRAY:
		return {
			"ok": false,
			"errors": ["%s: story_files must be an array." % campaign.get("id", campaign_path)],
			"files": files,
			"conversations": conversations,
			"quests": quests
		}
	for relative_value in value:
		var relative_path := str(relative_value)
		if not safe_relative_json_path(relative_path):
			errors.append("%s: unsafe story catalog path '%s'." % [campaign.get("id", campaign_path), relative_path])
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result := read_json(path)
		if not result.get("ok", false):
			append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		files.append({"path": path, "relative_path": relative_path, "data": data})
		merge_records(data.get("conversations", []), "conversation", path, conversations, conversation_sources, errors)
		merge_records(data.get("quests", []), "quest", path, quests, quest_sources, errors)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"files": files,
		"conversations": conversations,
		"quests": quests,
		"conversation_sources": conversation_sources,
		"quest_sources": quest_sources
	}


static func merge_records(
	value: Variant,
	kind: String,
	path: String,
	target: Dictionary,
	sources: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: %ss must be an array." % [path, kind])
		return
	for record_value in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("%s: every %s must be an object." % [path, kind])
			continue
		var record: Dictionary = record_value
		var identifier := str(record.get("id", ""))
		if identifier.is_empty():
			continue
		if target.has(identifier):
			errors.append("%s: %s id '%s' is also declared by %s." % [path, kind, identifier, sources.get(identifier, "another catalog")])
			continue
		target[identifier] = record
		sources[identifier] = path


static func primary_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	var value: Variant = campaign.get("story_files", [])
	if typeof(value) == TYPE_ARRAY:
		for relative_value in value:
			var relative_path := str(relative_value)
			if safe_relative_json_path(relative_path):
				return campaign_path.get_base_dir().path_join(relative_path)
	return campaign_path.get_base_dir().path_join("story").path_join("core.json")


static func conversation(definitions: Dictionary, conversation_id: String) -> Dictionary:
	var value: Variant = definitions.get(conversation_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func quest(definitions: Dictionary, quest_id: String) -> Dictionary:
	var value: Variant = definitions.get(quest_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func nodes(conversation_data: Dictionary) -> Array:
	var value: Variant = conversation_data.get("nodes", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func node_index(conversation_data: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for value in nodes(conversation_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		var identifier := str(record.get("id", ""))
		if not identifier.is_empty():
			output[identifier] = record
	return output


static func node(conversation_data: Dictionary, node_id: String) -> Dictionary:
	return node_index(conversation_data).get(node_id, {})


static func node_text(node_data: Dictionary, era_id: String) -> String:
	return resolved_text(node_data.get("text", ""), era_id, "...")


static func choice_prompt(node_data: Dictionary, era_id: String) -> String:
	return resolved_text(node_data.get("prompt", "Choose a response."), era_id, "Choose a response.")


static func resolved_text(value: Variant, era_id: String, fallback: String = "") -> String:
	if typeof(value) == TYPE_STRING:
		var text := str(value).strip_edges()
		return text if not text.is_empty() else fallback
	if typeof(value) == TYPE_DICTIONARY:
		var by_era: Dictionary = value
		var text := str(by_era.get(era_id, by_era.get("default", fallback))).strip_edges()
		return text if not text.is_empty() else fallback
	return fallback


static func choices(node_data: Dictionary) -> Array:
	var value: Variant = node_data.get("choices", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func conditions(record: Dictionary, field: String = "conditions") -> Array:
	var value: Variant = record.get(field, [])
	return value if typeof(value) == TYPE_ARRAY else []


static func effects(record: Dictionary, field: String = "effects") -> Array:
	var value: Variant = record.get(field, [])
	return value if typeof(value) == TYPE_ARRAY else []


static func stages(quest_data: Dictionary) -> Array:
	var value: Variant = quest_data.get("stages", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func stage_index(quest_data: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for value in stages(quest_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		var identifier := str(record.get("id", ""))
		if not identifier.is_empty():
			output[identifier] = record
	return output


static func stage(quest_data: Dictionary, stage_id: String) -> Dictionary:
	return stage_index(quest_data).get(stage_id, {})


static func default_story_catalog() -> Dictionary:
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"conversations": [default_conversation("first_story", "First Story")],
		"quests": [default_quest("first_errand", "First Errand")]
	}


static func default_conversation(conversation_id: String, display_name: String) -> Dictionary:
	return {
		"id": conversation_id,
		"display_name": display_name,
		"start_node": "opening",
		"conditions": [],
		"nodes": [
			{
				"id": "opening",
				"kind": "line",
				"speaker": "TRAVELLER",
				"text": "A new story waits to be authored.",
				"next": "end",
				"conditions": [],
				"effects": [],
				"editor_position": {"x": 80, "y": 120}
			},
			{
				"id": "end",
				"kind": "end",
				"effects": [],
				"editor_position": {"x": 380, "y": 120}
			}
		]
	}


static func default_quest(quest_id: String, title: String) -> Dictionary:
	return {
		"id": quest_id,
		"title": title,
		"summary": "An authored objective for this campaign.",
		"initial_stage": "investigate",
		"auto_start": false,
		"stages": [
			{
				"id": "investigate",
				"description": "Investigate the unfinished story.",
				"completion_conditions": [
					{"type": "state_equals", "key": "campaign:first_errand:complete", "value": true}
				],
				"next_stage": ""
			}
		],
		"rewards": []
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
