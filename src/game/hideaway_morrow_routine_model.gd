class_name HideawayMorrowRoutineModel
extends RefCounted

## Pure, read-only Archive Hideaway companion routine selection.
##
## Routines make the refuge feel inhabited while preserving player command
## authority. They are derived from existing campaign and stewardship state,
## use only active in-session delta time, and never write unlocks or rewards.

const HideawayStewardship = preload("res://src/game/hideaway_stewardship.gd")

const MAX_ROUTINES := 12
const MIN_DURATION_SECONDS := 3.0
const MAX_DURATION_SECONDS := 12.0
const MAX_OFFSET_COMPONENT := 96.0
const CONDITION_TYPES: PackedStringArray = [
	"always",
	"state_equals",
	"return_count_at_least",
	"refuge_tier_at_least",
	"facility_level_at_least",
]
const POSE_IDS: PackedStringArray = [
	"watch",
	"sniff",
	"warm",
	"listen",
	"curl",
	"sleep",
]


static func available_entries(
	definition: Dictionary,
	session_state: Dictionary,
	hideaway_state: Dictionary,
	era_id: String
) -> Array:
	var output: Array = []
	var entries_value: Variant = definition.get("morrow_routines", [])
	if typeof(entries_value) != TYPE_ARRAY:
		return output
	for entry_value: Variant in entries_value:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		if entry_available(entry, session_state, hideaway_state, era_id):
			output.append(entry.duplicate(true))
	return output


static func entry_available(
	entry: Dictionary,
	session_state: Dictionary,
	hideaway_state: Dictionary,
	era_id: String
) -> bool:
	if not available_in_era(entry, era_id):
		return false
	var conditions_value: Variant = entry.get("conditions", [])
	if typeof(conditions_value) != TYPE_ARRAY or (conditions_value as Array).is_empty():
		return false
	for condition_value: Variant in conditions_value:
		if typeof(condition_value) != TYPE_DICTIONARY:
			return false
		if not condition_met(condition_value as Dictionary, session_state, hideaway_state):
			return false
	return true


static func available_in_era(entry: Dictionary, era_id: String) -> bool:
	var eras_value: Variant = entry.get("available_eras", [])
	if typeof(eras_value) != TYPE_ARRAY:
		return false
	var eras: Array = eras_value
	return eras.is_empty() or eras.has(era_id)


static func condition_met(
	condition: Dictionary,
	session_state: Dictionary,
	hideaway_state: Dictionary
) -> bool:
	match str(condition.get("type", "")):
		"always":
			return condition.size() == 1
		"state_equals":
			var key := str(condition.get("key", ""))
			return not key.is_empty() and values_equal(
				session_state.get(key),
				condition.get("value")
			)
		"return_count_at_least":
			return int(hideaway_state.get("return_count", 0)) >= int(condition.get("value", 0))
		"refuge_tier_at_least":
			var expected := StringName(str(condition.get("value", "")))
			var summary := HideawayStewardship.refuge_summary(hideaway_state)
			var actual := StringName(str(summary.get("tier_id", "unsettled")))
			var actual_index := HideawayStewardship.REFUGE_TIER_IDS.find(actual)
			var expected_index := HideawayStewardship.REFUGE_TIER_IDS.find(expected)
			return expected_index >= 0 and actual_index >= expected_index
		"facility_level_at_least":
			var facility_id := StringName(str(condition.get("facility_id", "")))
			if not HideawayStewardship.FACILITY_IDS.has(facility_id):
				return false
			var facilities_value: Variant = hideaway_state.get("facilities", {})
			if typeof(facilities_value) != TYPE_DICTIONARY:
				return false
			return int((facilities_value as Dictionary).get(String(facility_id), 0)) >= int(condition.get("value", 0))
		_:
			return false


static func values_equal(actual: Variant, expected: Variant) -> bool:
	if (
		(actual is int or actual is float)
		and (expected is int or expected is float)
	):
		return (
			is_finite(float(actual))
			and is_finite(float(expected))
			and float(actual) == float(expected)
		)
	return actual == expected


static func anchor_interaction_id(entry: Dictionary) -> String:
	return str(entry.get("anchor_interaction_id", ""))


static func offset(entry: Dictionary) -> Vector2:
	var value: Variant = entry.get("offset", {})
	if typeof(value) != TYPE_DICTIONARY:
		return Vector2.ZERO
	var data: Dictionary = value
	return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))


static func duration_seconds(entry: Dictionary) -> float:
	return clampf(
		float(entry.get("duration_seconds", MIN_DURATION_SECONDS)),
		MIN_DURATION_SECONDS,
		MAX_DURATION_SECONDS
	)


static func display_name_key(entry: Dictionary) -> String:
	return str(entry.get("display_name_key", ""))


static func display_name_fallback(entry: Dictionary) -> String:
	return str(entry.get("display_name", "Morrow rests nearby"))


static func pose_id(entry: Dictionary) -> String:
	return str(entry.get("pose", "watch"))


static func routine_contract_ok() -> bool:
	return (
		MAX_ROUTINES == 12
		and MIN_DURATION_SECONDS == 3.0
		and MAX_DURATION_SECONDS == 12.0
		and MAX_OFFSET_COMPONENT == 96.0
		and CONDITION_TYPES.size() == 5
		and POSE_IDS.size() == 6
		and HideawayStewardship.FACILITY_IDS.has(&"morrows_corner")
		and HideawayStewardship.REFUGE_TIER_IDS.has(&"haven")
	)
