class_name HideawayStewardshipValidator
extends RefCounted

const Repository := preload("res://src/content/campaign_repository.gd")
const MODEL := preload("res://src/game/hideaway_stewardship.gd")
const MEMENTOS := preload("res://src/game/hideaway_memento_model.gd")
const QUIET_MOMENTS := preload("res://src/game/hideaway_quiet_moment_model.gd")
const MORROW_ROUTINES := preload("res://src/game/hideaway_morrow_routine_model.gd")

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
	"quiet_nook",
	"quiet_moments",
	"morrow_routines",
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
const ALLOWED_QUIET_MOMENT_KEYS: PackedStringArray = [
	"id",
	"display_name_key",
	"display_name",
	"speaker",
	"conditions",
	"reflection_keys",
	"reflection",
]
const ALLOWED_QUIET_CONDITION_KEYS: PackedStringArray = ["type", "key", "value", "facility_id"]
const ALLOWED_MORROW_ROUTINE_KEYS: PackedStringArray = [
	"id",
	"display_name_key",
	"display_name",
	"pose",
	"anchor_interaction_id",
	"offset",
	"duration_seconds",
	"available_eras",
	"conditions",
]
const ALLOWED_MORROW_CONDITION_KEYS: PackedStringArray = ["type", "key", "value", "facility_id"]


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


static func validate_campaign_binding_for_test(
	campaign_path: String,
	definition: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		_append_messages(errors, campaign_result.get("errors", []))
		return errors
	var campaign: Dictionary = campaign_result.get("data", {})
	_validate_campaign_binding(campaign_path, campaign, definition, errors)
	return errors


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
	_validate_quiet_nook(definition.get("quiet_nook"), errors)
	_validate_quiet_moments(definition.get("quiet_moments"), errors)
	_validate_morrow_routines(definition.get("morrow_routines"), errors)
	var entries_value: Variant = definition.get("mementos", [])
	if (
		typeof(entries_value) == TYPE_ARRAY
		and (entries_value as Array).size() > MEMENTOS.shelf_slots(definition)
	):
		errors.append("hideaway.memento_count_exceeds_shelf")
	var quiet_value: Variant = definition.get("quiet_moments", [])
	if (
		typeof(quiet_value) == TYPE_ARRAY
		and (quiet_value as Array).size() > QUIET_MOMENTS.nook_slots(definition)
	):
		errors.append("hideaway.quiet_moment_count_exceeds_nook")
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


static func _validate_quiet_nook(value: Variant, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		errors.append("hideaway.quiet_nook_not_dictionary")
		return
	var nook: Dictionary = value
	var interaction_id := str(nook.get("interaction_id", ""))
	if interaction_id.is_empty() or Repository.normalise_id(interaction_id) != interaction_id:
		errors.append("hideaway.quiet_nook_interaction_invalid")
	if str(nook.get("kind", "")) != QUIET_MOMENTS.NOOK_KIND:
		errors.append("hideaway.quiet_nook_kind_invalid")
	for key: Variant in nook.keys():
		if not ["interaction_id", "kind", "maximum_moments"].has(str(key)):
			errors.append("hideaway.quiet_nook_field_unknown:%s" % str(key))
	if not _bounded_exact_int(nook.get("maximum_moments"), 1, QUIET_MOMENTS.MAX_MOMENTS):
		errors.append("hideaway.quiet_nook_moment_count_invalid")


static func _validate_quiet_moments(value: Variant, errors: PackedStringArray) -> void:
	if not value is Array:
		errors.append("hideaway.quiet_moments_not_array")
		return
	var entries: Array = value
	if entries.is_empty() or entries.size() > QUIET_MOMENTS.MAX_MOMENTS:
		errors.append("hideaway.quiet_moment_count_invalid")
	var seen := {}
	var always_count := 0
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			errors.append("hideaway.quiet_moment_not_dictionary")
			continue
		var entry: Dictionary = entry_value
		var moment_id := str(entry.get("id", ""))
		for key: Variant in entry.keys():
			if not ALLOWED_QUIET_MOMENT_KEYS.has(str(key)):
				errors.append("hideaway.quiet_moment_field_unknown:%s:%s" % [moment_id, str(key)])
		if moment_id.is_empty() or Repository.normalise_id(moment_id) != moment_id:
			errors.append("hideaway.quiet_moment_id_invalid:%s" % moment_id)
		elif seen.has(moment_id):
			errors.append("hideaway.quiet_moment_duplicate:%s" % moment_id)
		else:
			seen[moment_id] = true
		if str(entry.get("display_name", "")).strip_edges().is_empty():
			errors.append("hideaway.quiet_moment_name_invalid:%s" % moment_id)
		_validate_quiet_message_key(entry.get("display_name_key"), moment_id, "name", errors)
		if not QUIET_MOMENTS.SPEAKER_IDS.has(str(entry.get("speaker", ""))):
			errors.append("hideaway.quiet_moment_speaker_invalid:%s" % moment_id)
		_validate_quiet_reflections(entry, moment_id, errors)
		always_count += _validate_quiet_conditions(entry.get("conditions"), moment_id, errors)
		for forbidden in ["effects", "rewards", "reward", "grant", "salvage", "time_advance"]:
			if entry.has(forbidden):
				errors.append("hideaway.quiet_moment_forbidden_field:%s:%s" % [moment_id, forbidden])
	if always_count != 1:
		errors.append("hideaway.quiet_moment_always_count_invalid")


static func _validate_quiet_reflections(
	entry: Dictionary,
	moment_id: String,
	errors: PackedStringArray
) -> void:
	var keys_value: Variant = entry.get("reflection_keys")
	var copy_value: Variant = entry.get("reflection")
	if not keys_value is Dictionary or not copy_value is Dictionary:
		errors.append("hideaway.quiet_moment_reflection_invalid:%s" % moment_id)
		return
	var keys: Dictionary = keys_value
	var copy: Dictionary = copy_value
	for era_id: String in REQUIRED_REFLECTION_ERAS:
		_validate_quiet_message_key(keys.get(era_id), moment_id, "reflection_%s" % era_id, errors)
		if str(copy.get(era_id, "")).strip_edges().is_empty():
			errors.append("hideaway.quiet_moment_reflection_copy_invalid:%s:%s" % [moment_id, era_id])


static func _validate_quiet_message_key(
	value: Variant,
	moment_id: String,
	label: String,
	errors: PackedStringArray
) -> void:
	var key := str(value)
	if key.is_empty() or not key.begins_with("ui.hideaway.quiet.") or key.contains(" "):
		errors.append("hideaway.quiet_moment_message_key_invalid:%s:%s" % [moment_id, label])


static func _validate_quiet_conditions(
	value: Variant,
	moment_id: String,
	errors: PackedStringArray
) -> int:
	if not value is Array or (value as Array).is_empty():
		errors.append("hideaway.quiet_moment_conditions_invalid:%s" % moment_id)
		return 0
	var always_count := 0
	for condition_value: Variant in value:
		if not condition_value is Dictionary:
			errors.append("hideaway.quiet_moment_condition_not_dictionary:%s" % moment_id)
			continue
		var condition: Dictionary = condition_value
		for key: Variant in condition.keys():
			if not ALLOWED_QUIET_CONDITION_KEYS.has(str(key)):
				errors.append("hideaway.quiet_moment_condition_field_unknown:%s:%s" % [moment_id, str(key)])
		var condition_type := str(condition.get("type", ""))
		if not QUIET_MOMENTS.CONDITION_TYPES.has(condition_type):
			errors.append("hideaway.quiet_moment_condition_type_invalid:%s:%s" % [moment_id, condition_type])
			continue
		match condition_type:
			"always":
				if condition.size() != 1:
					errors.append("hideaway.quiet_moment_always_payload_invalid:%s" % moment_id)
				always_count += 1
			"state_equals":
				var state_key := str(condition.get("key", ""))
				if state_key.is_empty() or state_key.length() > 128 or state_key.contains(" "):
					errors.append("hideaway.quiet_moment_state_key_invalid:%s" % moment_id)
				var state_value: Variant = condition.get("value")
				if typeof(state_value) not in [TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
					errors.append("hideaway.quiet_moment_state_value_invalid:%s" % moment_id)
				elif state_value is float and not is_finite(float(state_value)):
					errors.append("hideaway.quiet_moment_state_value_invalid:%s" % moment_id)
			"return_count_at_least":
				if not _bounded_exact_int(condition.get("value"), 1, 2147483647):
					errors.append("hideaway.quiet_moment_return_count_invalid:%s" % moment_id)
			"refuge_tier_at_least":
				if not MODEL.REFUGE_TIER_IDS.has(StringName(str(condition.get("value", "")))):
					errors.append("hideaway.quiet_moment_refuge_tier_invalid:%s" % moment_id)
			"facility_level_at_least":
				var facility_id := StringName(str(condition.get("facility_id", "")))
				if not MODEL.FACILITY_IDS.has(facility_id):
					errors.append("hideaway.quiet_moment_facility_invalid:%s" % moment_id)
				if not _bounded_exact_int(condition.get("value"), 1, MODEL.MAX_FACILITY_LEVEL):
					errors.append("hideaway.quiet_moment_facility_level_invalid:%s" % moment_id)
	return always_count


static func _validate_morrow_routines(value: Variant, errors: PackedStringArray) -> void:
	if not value is Array:
		errors.append("hideaway.morrow_routines_not_array")
		return
	var entries: Array = value
	if entries.is_empty() or entries.size() > MORROW_ROUTINES.MAX_ROUTINES:
		errors.append("hideaway.morrow_routine_count_invalid")
	var seen := {}
	var always_count := 0
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			errors.append("hideaway.morrow_routine_not_dictionary")
			continue
		var entry: Dictionary = entry_value
		var routine_id := str(entry.get("id", ""))
		for key: Variant in entry.keys():
			if not ALLOWED_MORROW_ROUTINE_KEYS.has(str(key)):
				errors.append("hideaway.morrow_routine_field_unknown:%s:%s" % [routine_id, str(key)])
		if routine_id.is_empty() or Repository.normalise_id(routine_id) != routine_id:
			errors.append("hideaway.morrow_routine_id_invalid:%s" % routine_id)
		elif seen.has(routine_id):
			errors.append("hideaway.morrow_routine_duplicate:%s" % routine_id)
		else:
			seen[routine_id] = true
		if str(entry.get("display_name", "")).strip_edges().is_empty():
			errors.append("hideaway.morrow_routine_name_invalid:%s" % routine_id)
		_validate_morrow_routine_message_key(entry.get("display_name_key"), routine_id, errors)
		if not MORROW_ROUTINES.POSE_IDS.has(str(entry.get("pose", ""))):
			errors.append("hideaway.morrow_routine_pose_invalid:%s" % routine_id)
		var anchor_id := str(entry.get("anchor_interaction_id", ""))
		if anchor_id.is_empty() or Repository.normalise_id(anchor_id) != anchor_id:
			errors.append("hideaway.morrow_routine_anchor_invalid:%s" % routine_id)
		_validate_morrow_routine_offset(entry.get("offset"), routine_id, errors)
		if not _bounded_exact_int(
			entry.get("duration_seconds"),
			int(MORROW_ROUTINES.MIN_DURATION_SECONDS),
			int(MORROW_ROUTINES.MAX_DURATION_SECONDS)
		):
			errors.append("hideaway.morrow_routine_duration_invalid:%s" % routine_id)
		_validate_morrow_routine_eras(entry.get("available_eras"), routine_id, errors)
		always_count += _validate_morrow_routine_conditions(entry.get("conditions"), routine_id, errors)
		for forbidden in ["effects", "rewards", "reward", "grant", "salvage", "time_advance", "save_key"]:
			if entry.has(forbidden):
				errors.append("hideaway.morrow_routine_forbidden_field:%s:%s" % [routine_id, forbidden])
	if always_count != 1:
		errors.append("hideaway.morrow_routine_always_count_invalid")


static func _validate_morrow_routine_message_key(
	value: Variant,
	routine_id: String,
	errors: PackedStringArray
) -> void:
	var key := str(value)
	if key.is_empty() or not key.begins_with("ui.hideaway.morrow_routine.") or key.contains(" "):
		errors.append("hideaway.morrow_routine_message_key_invalid:%s" % routine_id)


static func _validate_morrow_routine_offset(
	value: Variant,
	routine_id: String,
	errors: PackedStringArray
) -> void:
	if not value is Dictionary:
		errors.append("hideaway.morrow_routine_offset_invalid:%s" % routine_id)
		return
	var offset: Dictionary = value
	if offset.keys().size() != 2 or not offset.has("x") or not offset.has("y"):
		errors.append("hideaway.morrow_routine_offset_invalid:%s" % routine_id)
		return
	for axis in ["x", "y"]:
		var component: Variant = offset.get(axis)
		if not (component is int or component is float):
			errors.append("hideaway.morrow_routine_offset_invalid:%s" % routine_id)
			return
		var numeric := float(component)
		if not is_finite(numeric) or absf(numeric) > MORROW_ROUTINES.MAX_OFFSET_COMPONENT:
			errors.append("hideaway.morrow_routine_offset_invalid:%s" % routine_id)
			return


static func _validate_morrow_routine_eras(
	value: Variant,
	routine_id: String,
	errors: PackedStringArray
) -> void:
	if not value is Array:
		errors.append("hideaway.morrow_routine_eras_invalid:%s" % routine_id)
		return
	var seen := {}
	for era_value: Variant in value:
		var era_id := str(era_value)
		if not REQUIRED_REFLECTION_ERAS.has(era_id) or seen.has(era_id):
			errors.append("hideaway.morrow_routine_eras_invalid:%s" % routine_id)
			return
		seen[era_id] = true


static func _validate_morrow_routine_conditions(
	value: Variant,
	routine_id: String,
	errors: PackedStringArray
) -> int:
	if not value is Array or (value as Array).is_empty():
		errors.append("hideaway.morrow_routine_conditions_invalid:%s" % routine_id)
		return 0
	var always_count := 0
	for condition_value: Variant in value:
		if not condition_value is Dictionary:
			errors.append("hideaway.morrow_routine_condition_not_dictionary:%s" % routine_id)
			continue
		var condition: Dictionary = condition_value
		for key: Variant in condition.keys():
			if not ALLOWED_MORROW_CONDITION_KEYS.has(str(key)):
				errors.append("hideaway.morrow_routine_condition_field_unknown:%s:%s" % [routine_id, str(key)])
		var condition_type := str(condition.get("type", ""))
		if not MORROW_ROUTINES.CONDITION_TYPES.has(condition_type):
			errors.append("hideaway.morrow_routine_condition_type_invalid:%s:%s" % [routine_id, condition_type])
			continue
		match condition_type:
			"always":
				if condition.size() != 1:
					errors.append("hideaway.morrow_routine_always_payload_invalid:%s" % routine_id)
				always_count += 1
			"state_equals":
				var state_key := str(condition.get("key", ""))
				if state_key.is_empty() or state_key.length() > 128 or state_key.contains(" "):
					errors.append("hideaway.morrow_routine_state_key_invalid:%s" % routine_id)
				var state_value: Variant = condition.get("value")
				if typeof(state_value) not in [TYPE_BOOL, TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
					errors.append("hideaway.morrow_routine_state_value_invalid:%s" % routine_id)
				elif state_value is float and not is_finite(float(state_value)):
					errors.append("hideaway.morrow_routine_state_value_invalid:%s" % routine_id)
			"return_count_at_least":
				if not _bounded_exact_int(condition.get("value"), 1, 2147483647):
					errors.append("hideaway.morrow_routine_return_count_invalid:%s" % routine_id)
			"refuge_tier_at_least":
				if not MODEL.REFUGE_TIER_IDS.has(StringName(str(condition.get("value", "")))):
					errors.append("hideaway.morrow_routine_refuge_tier_invalid:%s" % routine_id)
			"facility_level_at_least":
				var facility_id := StringName(str(condition.get("facility_id", "")))
				if not MODEL.FACILITY_IDS.has(facility_id):
					errors.append("hideaway.morrow_routine_facility_invalid:%s" % routine_id)
				if not _bounded_exact_int(condition.get("value"), 1, MODEL.MAX_FACILITY_LEVEL):
					errors.append("hideaway.morrow_routine_facility_level_invalid:%s" % routine_id)
	return always_count


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
		"quiet_moment_rewards",
		"quiet_moments_advance_time",
		"morrow_routine_rewards",
		"morrow_routines_advance_time",
		"morrow_routines_override_commands",
	]
	for key in required_false:
		if not boundaries.get(key) is bool or bool(boundaries.get(key)):
			errors.append("hideaway.design_boundary_must_be_false:%s" % key)
	for key in ["active_play_only", "memento_unlocks_derived", "quiet_moments_read_only", "morrow_routines_read_only"]:
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

	for entry_value: Variant in definition.get("quiet_moments", []):
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		_validate_quiet_ui_copy(
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
			_validate_quiet_ui_copy(
				messages,
				str(keys.get(era_id, "")),
				str(copy.get(era_id, "")),
				str(entry.get("id", "")),
				"reflection_%s" % era_id,
				errors
			)

	for entry_value: Variant in definition.get("morrow_routines", []):
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		_validate_morrow_routine_ui_copy(
			messages,
			str(entry.get("display_name_key", "")),
			str(entry.get("display_name", "")),
			str(entry.get("id", "")),
			errors
		)
	for key: String in ["ui.hideaway.morrow_routine.arrived", "ui.hideaway.status.morrow_routine"]:
		var routine_message: Variant = messages.get(key)
		if typeof(routine_message) != TYPE_DICTIONARY or str((routine_message as Dictionary).get("en", "")).strip_edges().is_empty():
			errors.append("hideaway.morrow_routine_ui_key_missing:%s" % key)

	for speaker_id: String in QUIET_MOMENTS.SPEAKER_IDS:
		var speaker_key := "ui.hideaway.quiet.speaker.%s" % speaker_id
		var speaker_value: Variant = messages.get(speaker_key)
		if typeof(speaker_value) != TYPE_DICTIONARY or str((speaker_value as Dictionary).get("en", "")).strip_edges().is_empty():
			errors.append("hideaway.quiet_moment_speaker_ui_missing:%s" % speaker_id)
	for key: String in ["ui.hideaway.quiet.none", "ui.hideaway.status.quiet", "ui.hideaway.controls.quiet"]:
		var message_value: Variant = messages.get(key)
		if typeof(message_value) != TYPE_DICTIONARY or str((message_value as Dictionary).get("en", "")).strip_edges().is_empty():
			errors.append("hideaway.quiet_moment_ui_key_missing:%s" % key)


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


static func _validate_quiet_ui_copy(
	messages: Dictionary,
	key: String,
	fallback: String,
	moment_id: String,
	label: String,
	errors: Array[String]
) -> void:
	var entry_value: Variant = messages.get(key)
	if typeof(entry_value) != TYPE_DICTIONARY:
		errors.append("hideaway.quiet_moment_ui_key_missing:%s:%s" % [moment_id, label])
		return
	var english := str((entry_value as Dictionary).get("en", ""))
	if english != fallback or english.strip_edges().is_empty():
		errors.append("hideaway.quiet_moment_ui_fallback_mismatch:%s:%s" % [moment_id, label])


static func _validate_morrow_routine_ui_copy(
	messages: Dictionary,
	key: String,
	fallback: String,
	routine_id: String,
	errors: Array[String]
) -> void:
	var entry_value: Variant = messages.get(key)
	if typeof(entry_value) != TYPE_DICTIONARY:
		errors.append("hideaway.morrow_routine_ui_key_missing:%s" % routine_id)
		return
	var english := str((entry_value as Dictionary).get("en", ""))
	if english != fallback or english.strip_edges().is_empty():
		errors.append("hideaway.morrow_routine_ui_fallback_mismatch:%s" % routine_id)


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

	var nook_value: Variant = definition.get("quiet_nook", {})
	if typeof(nook_value) != TYPE_DICTIONARY:
		return
	var nook: Dictionary = nook_value
	var nook_interaction_id := str(nook.get("interaction_id", ""))
	var nook_kind := str(nook.get("kind", ""))
	var nook_found := false
	for interaction_value: Variant in map_data.get("interactions", []):
		if typeof(interaction_value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = interaction_value
		if str(interaction.get("id", "")) != nook_interaction_id:
			continue
		nook_found = true
		if str(interaction.get("kind", "")) != nook_kind:
			errors.append("hideaway.quiet_nook_map_kind_invalid")
		break
	if not nook_found:
		errors.append("hideaway.quiet_nook_map_interaction_missing:%s" % nook_interaction_id)


	var interaction_ids := {}
	for interaction_value: Variant in map_data.get("interactions", []):
		if typeof(interaction_value) == TYPE_DICTIONARY:
			interaction_ids[str((interaction_value as Dictionary).get("id", ""))] = true
	for routine_value: Variant in definition.get("morrow_routines", []):
		if typeof(routine_value) != TYPE_DICTIONARY:
			continue
		var routine: Dictionary = routine_value
		var anchor_id := str(routine.get("anchor_interaction_id", ""))
		if not interaction_ids.has(anchor_id):
			errors.append("hideaway.morrow_routine_anchor_missing:%s:%s" % [str(routine.get("id", "")), anchor_id])


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
	var quiet_value: Variant = definition.get("quiet_moments", [])
	var routine_value: Variant = definition.get("morrow_routines", [])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"hideaway_campaign_count": 0 if definition.is_empty() else 1,
		"hideaway_facility_count": 0 if definition.is_empty() else MODEL.FACILITY_IDS.size(),
		"hideaway_memento_count": (mementos_value as Array).size() if typeof(mementos_value) == TYPE_ARRAY else 0,
		"hideaway_quiet_moment_count": (quiet_value as Array).size() if typeof(quiet_value) == TYPE_ARRAY else 0,
		"hideaway_morrow_routine_count": (routine_value as Array).size() if typeof(routine_value) == TYPE_ARRAY else 0,
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
