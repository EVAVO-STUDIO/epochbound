class_name HideawayStewardshipValidator
extends RefCounted

const MODEL := preload("res://src/game/hideaway_stewardship.gd")
const DEFINITION_PATH := "res://campaigns/epochbound_demo/hideaway_stewardship.json"
const REQUIRED_KEYS: PackedStringArray = [
	"schema_version",
	"hideaway_id",
	"minimum_expedition_seconds",
	"max_banked_returns",
	"max_salvage",
	"facilities",
]


static func load_reference_definition() -> Dictionary:
	if not FileAccess.file_exists(DEFINITION_PATH):
		return {}
	var file := FileAccess.open(DEFINITION_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


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
	if not _exact_number(definition.get("minimum_expedition_seconds"), MODEL.MINIMUM_EXPEDITION_SECONDS):
		errors.append("hideaway.definition_expedition_seconds_invalid")
	if not _exact_number(definition.get("max_banked_returns"), MODEL.MAX_BANKED_RETURNS):
		errors.append("hideaway.definition_banked_returns_invalid")
	if not _exact_number(definition.get("max_salage", definition.get("max_salvage")), MODEL.MAX_SALVAGE):
		errors.append("hideaway.definition_salvage_invalid")
	var facilities_value: Variant = definition.get("facilities")
	if not facilities_value is Array:
		errors.append("hideaway.definition_facilities_not_array")
		return errors
	var facilities: Array = facilities_value
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
		if not entry.get("display_name") is String or String(entry["display_name"]).strip_edges().is_empty():
			errors.append("hideaway.definition_facility_name_invalid:%s" % String(facility_id))
		if StringName(String(entry.get("effect_id", ""))) != MODEL.FACILITY_EFFECTS[facility_id]:
			errors.append("hideaway.definition_facility_effect_invalid:%s" % String(facility_id))
		var costs_value: Variant = entry.get("upgrade_costs")
		if not costs_value is Array or costs_value != MODEL.FACILITY_COSTS[facility_id]:
			errors.append("hideaway.definition_facility_costs_invalid:%s" % String(facility_id))
	return errors


static func _exact_number(value: Variant, expected: float) -> bool:
	return (value is int or value is float) and float(value) == expected
