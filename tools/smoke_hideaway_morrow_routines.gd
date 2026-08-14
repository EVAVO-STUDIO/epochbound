extends SceneTree

const ROUTINES := preload("res://src/game/hideaway_morrow_routine_model.gd")
const STEWARDSHIP := preload("res://src/game/hideaway_stewardship.gd")
const VALIDATOR := preload("res://src/content/hideaway_stewardship_validator.gd")


func _init() -> void:
	var report := VALIDATOR.validate_hideaway_only(VALIDATOR.REFERENCE_CAMPAIGN_PATH)
	_assert(bool(report.get("ok", false)), "reference Hideaway definition must validate")
	_assert(int(report.get("hideaway_morrow_routine_count", 0)) == 8, "reference refuge must author eight Morrow routines")
	var definition: Dictionary = report.get("definition", {})
	_assert(ROUTINES.routine_contract_ok(), "Morrow routine model contract must hold")

	var stewardship := STEWARDSHIP.default_state(0.0)
	var session: Dictionary = {}
	var pristine_definition := definition.duplicate(true)
	var pristine_session := session.duplicate(true)
	var pristine_stewardship := stewardship.duplicate(true)
	var opening := ROUTINES.available_entries(definition, session, stewardship, "verdant")
	_assert(_ids(opening) == ["threshold_watch"], "new journeys must begin with one calm threshold routine")
	_assert(definition == pristine_definition and session == pristine_session and stewardship == pristine_stewardship, "routine evaluation must not mutate authored or durable state")

	stewardship["return_count"] = 1
	var first_return := ROUTINES.available_entries(definition, session, stewardship, "verdant")
	_assert(_ids(first_return) == ["threshold_watch", "first_return_pack"], "the first safe return must add one pack-check routine")

	var facilities: Dictionary = stewardship["facilities"]
	facilities["archive_hearth"] = 1
	facilities["sheltered_coldframe"] = 1
	facilities["salvage_workbench"] = 2
	facilities["morrows_corner"] = 1
	stewardship["facilities"] = facilities
	var verdant := ROUTINES.available_entries(definition, session, stewardship, "verdant")
	_assert(
		_ids(verdant) == [
			"threshold_watch",
			"first_return_pack",
			"hearth_sprawl",
			"coldframe_scent",
			"workbench_listen",
			"corner_curl",
		],
		"restored Verdant facilities must expose stable authored Morrow routines"
	)
	var ashen := ROUTINES.available_entries(definition, session, stewardship, "ashen")
	_assert(
		_ids(ashen) == [
			"threshold_watch",
			"first_return_pack",
			"hearth_sprawl",
			"cinder_glass_watch",
			"workbench_listen",
			"corner_curl",
		],
		"Ashen refuge must substitute its era-specific glass-watch routine"
	)

	for facility_id: StringName in STEWARDSHIP.FACILITY_IDS:
		stewardship["facilities"][String(facility_id)] = STEWARDSHIP.MAX_FACILITY_LEVEL
	var haven := ROUTINES.available_entries(definition, session, stewardship, "verdant")
	_assert(haven.size() == 7, "Archive Haven must expose seven Verdant routines")
	_assert(str((haven[haven.size() - 1] as Dictionary).get("id", "")) == "haven_sleep", "Both Ears Down must remain the final authored Haven routine")
	_assert(ROUTINES.pose_id(haven[haven.size() - 1]) == "sleep", "Haven sleep must retain its governed pose")
	_assert(ROUTINES.duration_seconds(haven[haven.size() - 1]) == 10.0, "Haven sleep must retain its authored active-play dwell")
	_assert(ROUTINES.anchor_interaction_id(haven[0]) == "quiet_moments_station", "baseline routine must retain a stable authored anchor")
	_assert(ROUTINES.offset(haven[0]) == Vector2(-72, 10), "baseline routine offset must remain deterministic")

	var duplicate := definition.duplicate(true)
	duplicate["morrow_routines"].append((duplicate["morrow_routines"] as Array)[0].duplicate(true))
	_assert(not VALIDATOR.validate_definition(duplicate).is_empty(), "duplicate routine IDs must fail closed")
	var rewarded := definition.duplicate(true)
	var rewarded_entries: Array = rewarded["morrow_routines"]
	var rewarded_entry: Dictionary = rewarded_entries[0]
	rewarded_entry["rewards"] = [{"type": "grant_currency", "amount": 99}]
	rewarded_entries[0] = rewarded_entry
	_assert(not VALIDATOR.validate_definition(rewarded).is_empty(), "Morrow routines must reject reward payloads")
	var wall_clock := definition.duplicate(true)
	var wall_entries: Array = wall_clock["morrow_routines"]
	var wall_entry: Dictionary = wall_entries[0]
	wall_entry["conditions"] = [{"type": "wall_clock_hour", "value": 1}]
	wall_entries[0] = wall_entry
	_assert(not VALIDATOR.validate_definition(wall_clock).is_empty(), "wall-clock routine conditions must fail closed")
	var bad_anchor := definition.duplicate(true)
	var anchor_entries: Array = bad_anchor["morrow_routines"]
	var anchor_entry: Dictionary = anchor_entries[0]
	anchor_entry["anchor_interaction_id"] = "missing_station"
	anchor_entries[0] = anchor_entry
	_assert(not VALIDATOR.validate_campaign_binding_for_test(VALIDATOR.REFERENCE_CAMPAIGN_PATH, bad_anchor).is_empty(), "unknown routine anchors must fail campaign binding")
	var bad_offset := definition.duplicate(true)
	var offset_entries: Array = bad_offset["morrow_routines"]
	var offset_entry: Dictionary = offset_entries[0]
	offset_entry["offset"] = {"x": 1000, "y": 0}
	offset_entries[0] = offset_entry
	_assert(not VALIDATOR.validate_definition(bad_offset).is_empty(), "out-of-range routine offsets must fail closed")
	var duplicate_era := definition.duplicate(true)
	var era_entries: Array = duplicate_era["morrow_routines"]
	var era_entry: Dictionary = era_entries[3]
	era_entry["available_eras"] = ["verdant", "verdant"]
	era_entries[3] = era_entry
	_assert(not VALIDATOR.validate_definition(duplicate_era).is_empty(), "duplicate era bindings must fail closed")
	var invalid_pose := definition.duplicate(true)
	var pose_entries: Array = invalid_pose["morrow_routines"]
	var pose_entry: Dictionary = pose_entries[0]
	pose_entry["pose"] = "dance"
	pose_entries[0] = pose_entry
	_assert(not VALIDATOR.validate_definition(invalid_pose).is_empty(), "unknown routine poses must fail closed")
	var extra_always := definition.duplicate(true)
	var always_entries: Array = extra_always["morrow_routines"]
	var always_entry: Dictionary = always_entries[1]
	always_entry["conditions"] = [{"type": "always"}]
	always_entries[1] = always_entry
	_assert(not VALIDATOR.validate_definition(extra_always).is_empty(), "exactly one baseline routine must remain authored")

	print("Archive Hideaway Morrow routine smoke passed: eight optional active-play routines derive read-only from return, facility, era and refuge state; stable cycling grants nothing, saves nothing and never overrides player commands.")
	quit(0)


func _ids(entries: Array) -> Array[String]:
	var output: Array[String] = []
	for value: Variant in entries:
		if typeof(value) == TYPE_DICTIONARY:
			output.append(str((value as Dictionary).get("id", "")))
	return output


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Archive Hideaway Morrow routine smoke failure: %s" % message)
	quit(1)
