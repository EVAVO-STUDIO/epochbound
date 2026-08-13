class_name HideawayStewardshipValidator
extends RefCounted

const Repository := preload("res://src/content/campaign_repository.gd")
const MODEL := preload("res://src/game/hideaway_stewardship.gd")
const MEMENTOS := preload("res://src/game/hideaway_memento_model.gd")

const REFERENCE_CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const DEFINITION_PATH := "res://campaigns/epochbound_demo/hideaway_stewardship.json"
const CAMPAIGN_FIELD := "hideaway_stewardship_file"
const UI_CATALOG_PATH := "res://localisation/ui.json"
const REQUIRED_KEYS: PackedStringArray = [
	"schema_version",
	"hideaway_id",
	"minimum_expedition_seconds",
	"max_banked_returns",
	"max_salvage",
	"facilities",
	"memento_shelf",
	"mementos",
	"design_boundaries",
]
const REQUIRED_REFLECTION_ERAS: PackedStringArray = ["verdant", "ashen"]
const ALLOWED_MEMENTO_KEYS: PackedStringArray = [
	"id",
	"display_name_key",
	"display_name",
	"symbol",
	"conditions",
	"reflection_keys",
	"reflection",
]
const ALLOWED_CONDITION_KEYS: PackedStringArray = ["type", "key", "value"]


static func load_reference_definition() -> Dictionary:
	return load_definition(REFERENCE_CAMPAIGN_PATH)


static func load_definition(campaign_path: String) -> Dictionary:
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		return {}
	var campaign: Dictionary = campaign_result.get("data", {})
	var relative := str(campaign.get(CAMPAIGN_FIELD, ""))
	if not _safe_relative_json_path(relative):
		return {}
	var result := Repository.read_json(campaign_path.get_base_dir().path_join(relative))
	return result.get("data", {}) if bool(result.get("ok", false)) else {}


static func validate_hideaway_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		_append_messages(errors, campaign_result.get("errors", []))
		return _report(errors, warnings, {})
	var campaign: Dictionary = campaign_result.get("data", {})
	var relative := str(campaign.get(CAMPAIGN_FIELD, ""))
	if relative.is_empty():
		return _report(errors, warnings, {})
	if not _safe_relative_json_path(relative):
		errors.append("%s must be a safe relative JSON path." % CAMPAIGN_FIELD)
		return _report(errors, warnings, {})
	var definition_path := campaign_path.get_base_dir().path_join(relative)
	var definition_result := Repository.read_json(definition_path)
	if not bool(definition_result.get("ok", false)):
		_append_messages(errors, definition_result.get("errors", []))
		return _report(errors, warnings, {})
	var definition: Dictionary = definition_result.get("data", {})
	_append_messages(errors, validate_definition(definition))
	_validate_ui_catalog(definition, errors)
	_validate_campaign_binding(campaign_path, campaign, definition, errors)
	return _report(errors, warnings, definition)


static func validate_definition(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		errors.append("hideaway.definition_not_dictionary")
		return errors
	var definition: Dictionary = value
	for key: String in REQUIRED_KEYS:
		if not definition.has(key):
			errors.append("hideaway.definition_missing:%s" % key)
	if not _exact_number(definition.get("schema_version"), MODEL.SCHEMA_VERSION):
		errors.append("hideaway.definition_schema_invalid")
	if definition.get("hideaway_id") != String(MODEL.HIDEAWAY_ID):
		errors.append("hideaway.definition_id_invalid")
	if not _exact_number(
		definition.get("minimum_expedition_seconds"),
		MODEL.MINIMUM_EXPEDITION_SECONDS
	):
		errors.append("hideaway.definition_expedition_seconds_invalid")
	if not _exact_number(definition.get("max_banked_returns"), MODEL.MAX_BANKED_RETURNS):
		errors.append("hideaway.definition_banked_returns_invalid")
	if not _exact_number(definition.get("max_salvage"), MODEL.MAX_SALVAGE):
		errors.append("hideaway.definition_salvage_invalid")
	_validate_facilities(definition.get("facilities"), errors)
	_validate_memento_shelf(definition.get("memento_shelf"), errors)
	_validate_mementos(definition.get("mementos"), errors)
	var entries_value: Variant = definition.get("mementos", [])
	if (
		typeof(entries_value) == TYPE_ARRAY
		and (entries_value as Array).size() > MEMENTOS.shelf_slots(definition)
	):
		errors.append("hideaway.memento_count_exceeds_shelf")
	_validate_design_boundaries(definition.get("design_boundaries"), errors)
	return errors


static func _validate_facilities(value: Variant, errors: PackedStringArray) -> void:
	if not value is Array:
		errors.append("hideaway.definition_facilities_not_array")
		return
	var facilities: Array = value
	if facilities.size() != MODEL.FACILITY_IDS.size():
		errors.append("hideaway.definition_facility_count_invalid")
	var seen := {}
	for entry_value: Variant in facilities:
		if not entry_value is Dictionary:
			errors.append("hideaway.definition_facility_not_dictionary")
			continue
		var entry: Dictionary = entry_value
		var facility_id := StringName(String(entry.get("id", "")))
		if not MODEL.FACILITY_IDS.has(facility_id):
			errors.append("hideaway.definition_facility_unknown:%s" % String(facility_id))
			continue
		if seen.has(facility_id):
			errors.append("hideaway.definition_facility_duplicate:%s" % String(facility_id))
		seen[facility_id] = true
		if (
			not entry.get("display_name") is String
			or String(entry["display_name"]).strip_edges().is_empty()
		):
			errors.append("hideaway.definition_facility_name_invalid:%s" % String(facility_id))
		if StringName(String(entry.get("effect_id", ""))) != MODEL.FACILITY_EFFECTS[facility_id]:
			errors.append("hideaway.definition_facility_effect_invalid:%s" % String(facility_id))
		_validate_costs(entry.get("upgrade_costs"), facility_id, errors)


static func _validate_memento_shelf(value: Variant, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		errors.append("hideaway.memento_shelf_not_dictionary")
		return
	var shelf: Dictionary = value
	var interaction_id := str(shelf.get("interaction_id", ""))
	if interaction_id.is_empty() or Repository.normalise_id(interaction_id) != interaction_id:
		errors.append("hideaway.memento_shelf_interaction_invalid")
	if str(shelf.get("kind", "")) != MEMENTOS.SHELF_KIND:
		errors.append("hideaway.memento_shelf_kind_invalid")
	for key: Variant in shelf.keys():
		if not ["interaction_id", "kind", "maximum_slots"].has(str(key)):
			errors.append("hideaway.memento_shelf_field_unknown:%s" % str(key))
	var maximum_slots: Variant = shelf.get("maximum_slots")
	if not _bounded_exact_int(maximum_slots, 1, MEMENTOS.MAX_MEMENTOS):
		errors.append("hideaway.memento_shelf_slots_invalid")


static func _validate_mementos(value: Variant, errors: PackedStringArray) -> void:
	if not value is Array:
		errors.append("hideaway.mementos_not_array")
		return
	var entries: Array = value
	if entries.is_empty() or entries.size() > MEMENTOS.MAX_MEMENTOS:
		errors.append("hideaway.memento_count_invalid")
	var seen := {}
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			errors.append("hideaway.memento_not_dictionary")
			continue
		var entry: Dictionary = entry_value
		var memento_id := str(entry.get("id", ""))
		for key: Variant in entry.keys():
			if not ALLOWED_MEMENTO_KEYS.has(str(key)):
				errors.append("hideaway.memento_field_unknown:%s:%s" % [memento_id, str(key)])
		if memento_id.is_empty() or Repository.normalise_id(memento_id) != memento_id:
			errors.append("hideaway.memento_id_invalid:%s" % memento_id)
		elif seen.has(memento_id):
			errors.append("hideaway.memento_duplicate:%s" % memento_id)
		else:
			seen[memento_id] = true
		if str(entry.get("display_name", "")).strip_edges().is_empty():
			errors.append("hideaway.memento_name_invalid:%s" % memento_id)
		_validate_message_key(entry.get("display_name_key"), memento_id, "name", errors)
		if not MEMENTOS.SYMBOL_IDS.has(str(entry.get("symbol", ""))):
			errors.append("hideaway.memento_symbol_invalid:%s" % memento_id)
		_validate_reflections(entry, memento_id, errors)
		_validate_conditions(entry.get("conditions"), memento_id, errors)
		for forbidden in ["effects", "rewards", "reward", "grant", "salvage"]:
			if entry.has(forbidden):
				errors.append("hideaway.memento_forbidden_field:%s:%s" % [memento_id, forbidden])


static func _validate_reflections(
	entry: Dictionary,
	memento_id: String,
	errors: PackedStringArray
) -> void:
	var keys_value: Variant = entry.get("reflection_keys")
	var copy_value: Variant = entry.get("reflection")
	if not keys_value is Dictionary or not copy_value is Dictionary:
		errors.append("hideaway.memento_reflection_invalid:%s" % memento_id)
		return
	var keys: Dictionary = keys_value
	var copy: Dictionary = copy_value
	for era_id: String in REQUIRED_REFLECTION_ERAS:
		_validate_message_key(keys.get(era_id), memento_id, "reflection_%s" % era_id, errors)
		if str(copy.get(era_id, "")).strip_edges().is_empty():
			errors.append("hideaway.memento_reflection_copy_invalid:%s:%s" % [memento_id, era_id])


static func _validate_message_key(
	value: Variant,
	memento_id: String,
	label: String,
	errors: PackedStringArray
) -> void:
	var key := str(value)
	if (
		key.is_empty()
		or not key.begins_with("ui.hideaway.memento.")
		or key.contains(" ")
	):
		errors.append("hideaway.memento_message_key_invalid:%s:%s" % [memento_id, label])


static func _validate_conditions(
	value: Variant,
	memento_id: String,
	errors: PackedStringArray
) -> void:
	if not value is Array or (value as Array).is_empty():
		errors.append("hideaway.memento_conditions_invalid:%s" % memento_id)
		return
	for condition_value: Variant in value:
		if not condition_value is Dictionary:
			errors.append("hideaway.memento_condition_not_dictionary:%s" % memento_id)
			continue
		var condition: Dictionary = condition_value
		for key: Variant in condition.keys():
			if not ALLOWED_CONDITION_KEYS.has(str(key)):
				errors.append("hideaway.memento_condition_field_unknown:%s:%s" % [memento_id, str(key)])
		var condition_type := str(condition.get("type", ""))
		if not MEMENTOS.CONDITION_TYPES.has(condition_type):
			errors.append("hideaway.memento_condition_type_invalid:%s:%s" % [memento_id, condition_type])
			continue
		match condition_type:
			"state_equals":
				var key := str(condition.get("key", ""))
				if key.is_empty() or key.length() > 128 or key.contains(" "):
					errors.append("hideaway.memento_state_key_invalid:%s" % memento_id)
				var state_value: Variant = condition.get("value")
				if typeof(state_value) not in [TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
					errors.append("hideaway.memento_state_value_invalid:%s" % memento_id)
				elif state_value is float and not is_finite(float(state_value)):
					errors.append("hideaway.memento_state_value_invalid:%s" % memento_id)
			"return_count_at_least":
				if not _bounded_exact_int(condition.get("value"), 1, 2147483647):
					errors.append("hideaway.memento_return_count_invalid:%s" % memento_id)
			"refuge_tier_at_least":
				if not MODEL.REFUGE_TIER_IDS.has(StringName(str(condition.get("value", "")))):
					errors.append("hideaway.memento_refuge_tier_invalid:%s" % memento_id)


static func _validate_design_boundaries(value: Variant, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		errors.append("hideaway.design_boundaries_not_dictionary")
		return
	var boundaries: Dictionary = value
	var required_false := [
		"offline_progress",
		"hunger",
		"thirst",
		"forced_sleep",
		"daily_chore_calendar",
		"memento_rewards",
	]
	for key in required_false:
		if not boundaries.get(key) is bool or bool(boundaries.get(key)):
			errors.append("hideaway.design_boundary_must_be_false:%s" % key)
	for key in ["active_play_only", "memento_unlocks_derived"]:
		if not boundaries.get(key) is bool or not bool(boundaries.get(key)):
			errors.append("hideaway.design_boundary_must_be_true:%s" % key)


static func _validate_ui_catalog(definition: Dictionary, errors: Array[String]) -> void:
	var result := Repository.read_json(UI_CATALOG_PATH)
	if not bool(result.get("ok", false)):
		_append_messages(errors, result.get("errors", []))
		return
	var catalog: Dictionary = result.get("data", {})
	var messages_value: Variant = catalog.get("messages", {})
	if typeof(messages_value) != TYPE_DICTIONARY:
		errors.append("hideaway.memento_ui_messages_missing")
		return
	var messages: Dictionary = messages_value
	for entry_value: Variant in definition.get("mementos", []):
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		_validate_ui_copy(
			messages,
			str(entry.get("display_name_key", "")),
			str(entry.get("display_name", "")),
			str(entry.get("id", "")),
			"name",
			errors
		)
		var keys_value: Variant = entry.get("reflection_keys", {})
		var copy_value: Variant = entry.get("reflection", {})
		if typeof(keys_value) != TYPE_DICTIONARY or typeof(copy_value) != TYPE_DICTIONARY:
			continue
		var keys: Dictionary = keys_value
		var copy: Dictionary = copy_value
		for era_id: String in REQUIRED_REFLECTION_ERAS:
			_validate_ui_copy(
				messages,
				str(keys.get(era_id, "")),
				str(copy.get(era_id, "")),
				str(entry.get("id", "")),
				"reflection_%s" % era_id,
				errors
			)


static func _validate_ui_copy(
	messages: Dictionary,
	key: String,
	fallback: String,
	memento_id: String,
	label: String,
	errors: Array[String]
) -> void:
	var entry_value: Variant = messages.get(key)
	if typeof(entry_value) != TYPE_DICTIONARY:
		errors.append("hideaway.memento_ui_key_missing:%s:%s" % [memento_id, label])
		return
	var english := str((entry_value as Dictionary).get("en", ""))
	if english != fallback or english.strip_edges().is_empty():
		errors.append("hideaway.memento_ui_fallback_mismatch:%s:%s" % [memento_id, label])


static func _validate_campaign_binding(
	campaign_path: String,
	campaign: Dictionary,
	definition: Dictionary,
	errors: Array[String]
) -> void:
	var hideaway_id := str(definition.get("hideaway_id", ""))
	var map_data: Dictionary = {}
	for relative_value: Variant in campaign.get("map_files", []):
		var relative := str(relative_value)
		if not _safe_relative_json_path(relative):
			continue
		var result := Repository.read_json(campaign_path.get_base_dir().path_join(relative))
		if bool(result.get("ok", false)) and str((result.get("data", {}) as Dictionary).get("id", "")) == hideaway_id:
			map_data = result.get("data", {})
			break
	if map_data.is_empty():
		errors.append("hideaway.definition_map_missing:%s" % hideaway_id)
		return
	var shelf_value: Variant = definition.get("memento_shelf", {})
	if typeof(shelf_value) != TYPE_DICTIONARY:
		return
	var shelf: Dictionary = shelf_value
	var interaction_id := str(shelf.get("interaction_id", ""))
	var expected_kind := str(shelf.get("kind", ""))
	var found := false
	for interaction_value: Variant in map_data.get("interactions", []):
		if typeof(interaction_value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = interaction_value
		if str(interaction.get("id", "")) != interaction_id:
			continue
		found = true
		if str(interaction.get("kind", "")) != expected_kind:
			errors.append("hideaway.memento_shelf_map_kind_invalid")
		break
	if not found:
		errors.append("hideaway.memento_shelf_map_interaction_missing:%s" % interaction_id)


static func _validate_costs(
	value: Variant,
	facility_id: StringName,
	errors: PackedStringArray
) -> void:
	if not value is Array:
		errors.append("hideaway.definition_facility_costs_invalid:%s" % String(facility_id))
		return
	var actual: Array = value
	var expected: Array = MODEL.FACILITY_COSTS[facility_id]
	if actual.size() != expected.size():
		errors.append("hideaway.definition_facility_costs_invalid:%s" % String(facility_id))
		return
	for index: int in range(expected.size()):
		if not _exact_number(actual[index], int(expected[index])):
			errors.append("hideaway.definition_facility_costs_invalid:%s" % String(facility_id))
			return


static func _report(
	errors: Array[String],
	warnings: Array[String],
	definition: Dictionary
) -> Dictionary:
	var mementos_value: Variant = definition.get("mementos", [])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"hideaway_campaign_count": 0 if definition.is_empty() else 1,
		"hideaway_facility_count": 0 if definition.is_empty() else MODEL.FACILITY_IDS.size(),
		"hideaway_memento_count": (mementos_value as Array).size() if typeof(mementos_value) == TYPE_ARRAY else 0,
		"definition": definition,
	}


static func _bounded_exact_int(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var numeric := float(value)
	return (
		is_finite(numeric)
		and numeric == floor(numeric)
		and numeric >= minimum
		and numeric <= maximum
	)


static func _exact_number(value: Variant, expected: float) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == expected
	)


static func _safe_relative_json_path(path: String) -> bool:
	return (
		not path.is_empty()
		and not path.begins_with("/")
		and not path.begins_with("\\")
		and not path.contains("..")
		and not path.contains("://")
		and path.get_extension().to_lower() == "json"
	)


static func _append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message: Variant in value:
		target.append(str(message))
