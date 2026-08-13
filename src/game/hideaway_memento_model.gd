class_name HideawayMementoModel
extends RefCounted

## Pure, data-driven Archive Hideaway memento unlock evaluation.
##
## Mementos are derived from existing durable campaign and stewardship state.
## They never grant items, currency, salvage, preparation charges or offline
## progress, and they add no new save payload of their own.

const HideawayStewardship = preload("res://src/game/hideaway_stewardship.gd")

const MAX_MEMENTOS := 12
const SHELF_KIND := "hideaway_memento_shelf"
const CONDITION_TYPES: PackedStringArray = [
	"state_equals",
	"return_count_at_least",
	"refuge_tier_at_least",
]
const SYMBOL_IDS: PackedStringArray = [
	"strap",
	"rubbing",
	"lens_case",
	"ash_mark",
	"accession_plate",
	"haven_key",
]


static func unlocked_entries(
	definition: Dictionary,
	session_state: Dictionary,
	hideaway_state: Dictionary
) -> Array:
	var output: Array = []
	var entries_value: Variant = definition.get("mementos", [])
	if typeof(entries_value) != TYPE_ARRAY:
		return output
	for entry_value: Variant in entries_value:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		if entry_unlocked(entry, session_state, hideaway_state):
			output.append(entry.duplicate(true))
	return output


static func entry_unlocked(
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


static func shelf_slots(definition: Dictionary) -> int:
	var shelf_value: Variant = definition.get("memento_shelf", {})
	if typeof(shelf_value) != TYPE_DICTIONARY:
		return 0
	return clampi(int((shelf_value as Dictionary).get("maximum_slots", 0)), 0, MAX_MEMENTOS)


static func shelf_interaction_id(definition: Dictionary) -> String:
	var shelf_value: Variant = definition.get("memento_shelf", {})
	if typeof(shelf_value) != TYPE_DICTIONARY:
		return ""
	return str((shelf_value as Dictionary).get("interaction_id", ""))


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


static func memento_contract_ok() -> bool:
	return (
		MAX_MEMENTOS == 12
		and SHELF_KIND == "hideaway_memento_shelf"
		and CONDITION_TYPES.size() == 3
		and SYMBOL_IDS.size() == 6
		and HideawayStewardship.REFUGE_TIER_IDS.has(&"haven")
	)
