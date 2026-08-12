class_name HideawayStewardship
extends RefCounted

## Deterministic, player-owned Archive Hideaway stewardship state.
##
## This model advances only from durable active-play time supplied by the
## campaign runtime. It deliberately has no wall-clock, offline-growth,
## hunger, thirst, crop-maintenance, decay, or forced-sleep behaviour.

const SCHEMA_VERSION: int = 1
const HIDEAWAY_ID: StringName = &"archive_hideaway"
const MINIMUM_EXPEDITION_SECONDS: float = 90.0
const MAX_BANKED_RETURNS: int = 3
const MAX_SALVAGE: int = 99
const MAX_FACILITY_LEVEL: int = 3

const FACILITY_IDS: Array[StringName] = [
	&"archive_hearth",
	&"sheltered_coldframe",
	&"salvage_workbench",
	&"morrows_corner",
]

const FACILITY_EFFECTS: Dictionary = {
	&"archive_hearth": &"warmth",
	&"sheltered_coldframe": &"recovery",
	&"salvage_workbench": &"repair",
	&"morrows_corner": &"companion_focus",
}

const FACILITY_COSTS: Dictionary = {
	&"archive_hearth": [2, 4, 7],
	&"sheltered_coldframe": [2, 5, 8],
	&"salvage_workbench": [3, 5, 8],
	&"morrows_corner": [2, 4, 6],
}


static func default_state(play_time_seconds: float = 0.0) -> Dictionary:
	var facilities: Dictionary = {}
	var prepared: Dictionary = {}
	for facility_id: StringName in FACILITY_IDS:
		facilities[String(facility_id)] = 0
		prepared[String(FACILITY_EFFECTS[facility_id])] = 0
	return {
		"schema_version": SCHEMA_VERSION,
		"salvage": 0,
		"banked_returns": 0,
		"return_count": 0,
		"expedition_active": false,
		"expedition_started_play_time": maxf(play_time_seconds, 0.0),
		"expedition_origin_map": String(HIDEAWAY_ID),
		"last_return_play_time": maxf(play_time_seconds, 0.0),
		"facilities": facilities,
		"prepared": prepared,
	}


static func validate_state(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary:
		errors.append("hideaway.state_not_dictionary")
		return errors
	var state: Dictionary = value
	if not _is_exact_int(state.get("schema_version"), SCHEMA_VERSION):
		errors.append("hideaway.schema_invalid")
	_validate_bounded_int(state, "salvage", 0, MAX_SALVAGE, errors)
	_validate_bounded_int(state, "banked_returns", 0, MAX_BANKED_RETURNS, errors)
	_validate_bounded_int(state, "return_count", 0, 2147483647, errors)
	if not state.get("expedition_active") is bool:
		errors.append("hideaway.expedition_active_not_bool")
	_validate_non_negative_number(state, "expedition_started_play_time", errors)
	_validate_non_negative_number(state, "last_return_play_time", errors)
	if not state.get("expedition_origin_map") is String:
		errors.append("hideaway.expedition_origin_map_not_string")
	var facilities_value: Variant = state.get("facilities")
	if not facilities_value is Dictionary:
		errors.append("hideaway.facilities_not_dictionary")
	else:
		var facilities: Dictionary = facilities_value
		for facility_id: StringName in FACILITY_IDS:
			_validate_bounded_int(facilities, String(facility_id), 0, MAX_FACILITY_LEVEL, errors)
		for key: Variant in facilities.keys():
			if not FACILITY_IDS.has(StringName(String(key))):
				errors.append("hideaway.facility_unknown:%s" % String(key))
	var prepared_value: Variant = state.get("prepared")
	if not prepared_value is Dictionary:
		errors.append("hideaway.prepared_not_dictionary")
	else:
		var prepared: Dictionary = prepared_value
		for facility_id: StringName in FACILITY_IDS:
			var effect_id := String(FACILITY_EFFECTS[facility_id])
			_validate_bounded_int(prepared, effect_id, 0, MAX_FACILITY_LEVEL, errors)
		for key: Variant in prepared.keys():
			if not FACILITY_EFFECTS.values().has(StringName(String(key))):
				errors.append("hideaway.prepared_effect_unknown:%s" % String(key))
	return errors


static func begin_expedition(
	state_value: Dictionary,
	current_map_id: String,
	play_time_seconds: float
) -> Dictionary:
	var state := state_value.duplicate(true)
	if not validate_state(state).is_empty():
		return {"accepted": false, "reason": "invalid_state", "state": state}
	if bool(state["expedition_active"]):
		return {"accepted": false, "reason": "already_active", "state": state}
	if current_map_id.strip_edges().is_empty() or current_map_id == String(HIDEAWAY_ID):
		return {"accepted": false, "reason": "invalid_destination", "state": state}
	state["expedition_active"] = true
	state["expedition_started_play_time"] = maxf(play_time_seconds, float(state["last_return_play_time"]))
	state["expedition_origin_map"] = String(HIDEAWAY_ID)
	return {"accepted": true, "reason": "", "state": state}


static func record_return(state_value: Dictionary, play_time_seconds: float) -> Dictionary:
	var state := state_value.duplicate(true)
	if not validate_state(state).is_empty():
		return _return_result(state, false, "invalid_state", 0.0, 0)
	if not bool(state["expedition_active"]):
		return _return_result(state, false, "no_active_expedition", 0.0, 0)
	var started := float(state["expedition_started_play_time"])
	var returned_at := maxf(play_time_seconds, started)
	var elapsed := returned_at - started
	state["expedition_active"] = false
	state["last_return_play_time"] = returned_at
	if elapsed < MINIMUM_EXPEDITION_SECONDS:
		return _return_result(state, false, "expedition_too_short", elapsed, 0)
	var award := mini(3, 1 + int(floor(elapsed / 300.0)))
	state["salvage"] = mini(MAX_SALVAGE, int(state["salvage"]) + award)
	state["banked_returns"] = mini(MAX_BANKED_RETURNS, int(state["banked_returns"]) + 1)
	state["return_count"] = int(state["return_count"]) + 1
	return _return_result(state, true, "", elapsed, award)


static func facility_upgrade_cost(state_value: Dictionary, facility_id: StringName) -> int:
	if not FACILITY_IDS.has(facility_id):
		return -1
	var facilities: Dictionary = state_value.get("facilities", {})
	var level := int(facilities.get(String(facility_id), -1))
	if level < 0 or level >= MAX_FACILITY_LEVEL:
		return -1
	var costs: Array = FACILITY_COSTS[facility_id]
	return int(costs[level])


static func upgrade_facility(state_value: Dictionary, facility_id: StringName) -> Dictionary:
	var state := state_value.duplicate(true)
	if not validate_state(state).is_empty():
		return {"accepted": false, "reason": "invalid_state", "cost": 0, "state": state}
	var cost := facility_upgrade_cost(state, facility_id)
	if cost < 0:
		return {"accepted": false, "reason": "facility_unavailable", "cost": 0, "state": state}
	if int(state["salvage"]) < cost:
		return {"accepted": false, "reason": "insufficient_salvage", "cost": cost, "state": state}
	var facilities: Dictionary = state["facilities"]
	facilities[String(facility_id)] = int(facilities[String(facility_id)]) + 1
	state["salvage"] = int(state["salvage"]) - cost
	return {"accepted": true, "reason": "", "cost": cost, "state": state}


static func prepare_facility(state_value: Dictionary, facility_id: StringName) -> Dictionary:
	var state := state_value.duplicate(true)
	if not validate_state(state).is_empty():
		return {"accepted": false, "reason": "invalid_state", "state": state}
	if not FACILITY_IDS.has(facility_id):
		return {"accepted": false, "reason": "facility_unknown", "state": state}
	var facilities: Dictionary = state["facilities"]
	var level := int(facilities[String(facility_id)])
	if level <= 0:
		return {"accepted": false, "reason": "facility_unrestored", "state": state}
	if int(state["banked_returns"]) <= 0:
		return {"accepted": false, "reason": "no_return_opportunity", "state": state}
	var effect_id := String(FACILITY_EFFECTS[facility_id])
	var prepared: Dictionary = state["prepared"]
	if int(prepared[effect_id]) >= level:
		return {"accepted": false, "reason": "preparation_full", "state": state}
	prepared[effect_id] = int(prepared[effect_id]) + 1
	state["banked_returns"] = int(state["banked_returns"]) - 1
	return {"accepted": true, "reason": "", "effect_id": effect_id, "state": state}


static func consume_prepared_effect(state_value: Dictionary, effect_id: StringName) -> Dictionary:
	var state := state_value.duplicate(true)
	if not validate_state(state).is_empty():
		return {"accepted": false, "reason": "invalid_state", "state": state}
	if not FACILITY_EFFECTS.values().has(effect_id):
		return {"accepted": false, "reason": "effect_unknown", "state": state}
	var prepared: Dictionary = state["prepared"]
	var key := String(effect_id)
	if int(prepared[key]) <= 0:
		return {"accepted": false, "reason": "effect_empty", "state": state}
	prepared[key] = int(prepared[key]) - 1
	return {"accepted": true, "reason": "", "state": state}


static func _return_result(
	state: Dictionary,
	qualified: bool,
	reason: String,
	elapsed: float,
	award: int
) -> Dictionary:
	return {
		"qualified": qualified,
		"reason": reason,
		"elapsed_seconds": elapsed,
		"salvage_awarded": award,
		"state": state,
	}


static func _is_exact_int(value: Variant, expected: int) -> bool:
	return (value is int or value is float) and float(value) == float(expected)


static func _validate_bounded_int(
	owner: Dictionary,
	key: String,
	minimum: int,
	maximum: int,
	errors: PackedStringArray
) -> void:
	var value: Variant = owner.get(key)
	if not value is int:
		errors.append("hideaway.%s_not_int" % key)
		return
	if int(value) < minimum or int(value) > maximum:
		errors.append("hideaway.%s_out_of_range" % key)


static func _validate_non_negative_number(
	owner: Dictionary,
	key: String,
	errors: PackedStringArray
) -> void:
	var value: Variant = owner.get(key)
	if not (value is int or value is float):
		errors.append("hideaway.%s_not_number" % key)
		return
	if float(value) < 0.0 or not is_finite(float(value)):
		errors.append("hideaway.%s_invalid" % key)
