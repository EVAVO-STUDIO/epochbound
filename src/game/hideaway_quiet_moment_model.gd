class_name HideawayQuietMomentModel
extends RefCounted

## Pure, data-driven Archive Hideaway hearthside moment availability.
##
## Quiet moments are optional, read-only scenes derived from campaign and
## stewardship state that already exists. Listening never advances time,
## grants rewards, consumes resources or writes an unlock list to saves.

const HideawayStewardship = preload("res://src/game/hideaway_stewardship.gd")

const MAX_MOMENTS := 12
const NOOK_KIND := "hideaway_quiet_moments"
const CONDITION_TYPES: PackedStringArray = [
	"always",
	"state_equals",
	"return_count_at_least",
	"refuge_tier_at_least",
	"facility_level_at_least",
]
const SPEAKER_IDS: PackedStringArray = [
	"eli",
	"morrow",
	"together",
	"hideaway",
]


static func available_entries(
	definition: Dictionary,
	session_state: Dictionary,
	hideaway_state: Dictionary
) -> Array:
	var output: Array = []
	var entries_value: Variant = definition.get("quiet_moments", [])
	if typeof(entries_value) != TYPE_ARRAY:
		return output
	for entry_value: Variant in entries_value:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		if entry_available(entry, session_state, hideaway_state):
			output.append(entry.duplicate(true))
	return output


static func entry_available(
	entry: Dictionary,
	session_state: Dictionary,
	hideaway_state: Dictionary
) -> bool:
	var conditions_value: Variant = entry.get("conditions", [])
	if typeof(conditions_value) != TYPE_ARRAY or (conditions_value as Array).is_empty():
		return false
	for condition_value: Variant in conditions_value:
		if typeof(condition_value) != TYPE_DICTIONARY:
			return false
		if not condition_met(condition_value as Dictionary, session_state, hideaway_state):
			return false
	return true


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


static func nook_slots(definition: Dictionary) -> int:
	var nook_value: Variant = definition.get("quiet_nook", {})
	if typeof(nook_value) != TYPE_DICTIONARY:
		return 0
	return clampi(int((nook_value as Dictionary).get("maximum_moments", 0)), 0, MAX_MOMENTS)


static func nook_interaction_id(definition: Dictionary) -> String:
	var nook_value: Variant = definition.get("quiet_nook", {})
	if typeof(nook_value) != TYPE_DICTIONARY:
		return ""
	return str((nook_value as Dictionary).get("interaction_id", ""))


static func reflection_key(entry: Dictionary, era_id: String) -> String:
	var value: Variant = entry.get("reflection_keys", {})
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	var keys: Dictionary = value
	return str(keys.get(era_id, keys.get("default", "")))


static func reflection_fallback(entry: Dictionary, era_id: String) -> String:
	var value: Variant = entry.get("reflection", {})
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	var copy: Dictionary = value
	return str(copy.get(era_id, copy.get("default", "")))


static func quiet_moment_contract_ok() -> bool:
	return (
		MAX_MOMENTS == 12
		and NOOK_KIND == "hideaway_quiet_moments"
		and CONDITION_TYPES.size() == 5
		and SPEAKER_IDS.size() == 4
		and HideawayStewardship.FACILITY_IDS.has(&"morrows_corner")
		and HideawayStewardship.REFUGE_TIER_IDS.has(&"haven")
	)
