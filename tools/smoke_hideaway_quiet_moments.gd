extends SceneTree

const QUIET := preload("res://src/game/hideaway_quiet_moment_model.gd")
const STEWARDSHIP := preload("res://src/game/hideaway_stewardship.gd")
const VALIDATOR := preload("res://src/content/hideaway_stewardship_validator.gd")


func _init() -> void:
	var report := VALIDATOR.validate_hideaway_only(VALIDATOR.REFERENCE_CAMPAIGN_PATH)
	_assert(bool(report.get("ok", false)), "reference Hideaway definition must validate")
	_assert(int(report.get("hideaway_quiet_moment_count", 0)) == 8, "reference nook must author eight quiet moments")
	var definition: Dictionary = report.get("definition", {})
	_assert(QUIET.quiet_moment_contract_ok(), "quiet moment model contract must hold")
	_assert(QUIET.nook_slots(definition) == 8, "reference nook must expose eight bounded moments")
	_assert(QUIET.nook_interaction_id(definition) == "quiet_moments_station", "reference quiet interaction must remain stable")

	var stewardship := STEWARDSHIP.default_state(0.0)
	var session: Dictionary = {}
	var pristine_definition := definition.duplicate(true)
	var pristine_session := session.duplicate(true)
	var pristine_stewardship := stewardship.duplicate(true)
	var beginning := QUIET.available_entries(definition, session, stewardship)
	_assert(_ids(beginning) == ["threshold_breaths"], "new journeys must begin with one authored optional quiet moment")
	_assert(definition == pristine_definition and session == pristine_session and stewardship == pristine_stewardship, "quiet moment evaluation must not mutate authored or durable state")

	stewardship["return_count"] = 1
	var first_return := QUIET.available_entries(definition, session, stewardship)
	_assert(_ids(first_return) == ["threshold_breaths", "first_return_watch"], "the first safe return must add exactly its authored downtime moment")

	var facilities: Dictionary = stewardship["facilities"]
	facilities["archive_hearth"] = 1
	facilities["sheltered_coldframe"] = 1
	facilities["salvage_workbench"] = 2
	facilities["morrows_corner"] = 2
	stewardship["facilities"] = facilities
	var restored := QUIET.available_entries(definition, session, stewardship)
	_assert(
		_ids(restored) == [
			"threshold_breaths",
			"first_return_watch",
			"hearth_watch",
			"coldframe_rain",
			"quiet_tools",
			"both_ears_down",
		],
		"facility restoration must add optional hearthside moments in stable authored order"
	)

	session["story:missing_hour:completed"] = true
	var returned_hour := QUIET.available_entries(definition, session, stewardship)
	_assert(str((returned_hour[returned_hour.size() - 1] as Dictionary).get("id", "")) == "borrowed_hour", "the Missing Hour milestone must unlock one read-only shared moment")

	for facility_id: StringName in STEWARDSHIP.FACILITY_IDS:
		stewardship["facilities"][String(facility_id)] = STEWARDSHIP.MAX_FACILITY_LEVEL
	var haven := QUIET.available_entries(definition, session, stewardship)
	_assert(haven.size() == 8, "Archive Haven must expose all eight authored moments")
	_assert(str((haven[haven.size() - 1] as Dictionary).get("id", "")) == "archive_haven_stillness", "Archive Haven stillness must remain the final authored moment")
	_assert(str(QUIET.reflection_key(haven[0], "verdant")).ends_with(".verdant"), "Verdant reflection keys must remain deterministic")
	_assert(not QUIET.reflection_fallback(haven[0], "ashen").is_empty(), "Ashen reflection fallback must remain authored")

	var duplicate := definition.duplicate(true)
	duplicate["quiet_moments"].append((duplicate["quiet_moments"] as Array)[0].duplicate(true))
	_assert(not VALIDATOR.validate_definition(duplicate).is_empty(), "duplicate quiet moment IDs must fail closed")
	var rewarded := definition.duplicate(true)
	var rewarded_entries: Array = rewarded["quiet_moments"]
	var rewarded_entry: Dictionary = rewarded_entries[0]
	rewarded_entry["rewards"] = [{"type": "grant_currency", "amount": 99}]
	rewarded_entries[0] = rewarded_entry
	_assert(not VALIDATOR.validate_definition(rewarded).is_empty(), "quiet moments must reject reward payloads")
	var wall_clock := definition.duplicate(true)
	var wall_entries: Array = wall_clock["quiet_moments"]
	var wall_entry: Dictionary = wall_entries[0]
	wall_entry["conditions"] = [{"type": "wall_clock_hour", "value": 1}]
	wall_entries[0] = wall_entry
	_assert(not VALIDATOR.validate_definition(wall_clock).is_empty(), "wall-clock quiet moment conditions must fail closed")
	var bad_facility := definition.duplicate(true)
	var bad_facility_entries: Array = bad_facility["quiet_moments"]
	var bad_facility_entry: Dictionary = bad_facility_entries[2]
	bad_facility_entry["conditions"] = [{"type": "facility_level_at_least", "facility_id": "unknown", "value": 1}]
	bad_facility_entries[2] = bad_facility_entry
	_assert(not VALIDATOR.validate_definition(bad_facility).is_empty(), "unknown facility quiet moment conditions must fail closed")
	var extra_always := definition.duplicate(true)
	var always_entries: Array = extra_always["quiet_moments"]
	var always_entry: Dictionary = always_entries[1]
	always_entry["conditions"] = [{"type": "always"}]
	always_entries[1] = always_entry
	_assert(not VALIDATOR.validate_definition(extra_always).is_empty(), "exactly one baseline quiet moment must remain authored")
	var invalid_speaker := definition.duplicate(true)
	var speaker_entries: Array = invalid_speaker["quiet_moments"]
	var speaker_entry: Dictionary = speaker_entries[0]
	speaker_entry["speaker"] = "merchant"
	speaker_entries[0] = speaker_entry
	_assert(not VALIDATOR.validate_definition(invalid_speaker).is_empty(), "unknown quiet moment speakers must fail closed")

	print("Archive Hideaway quiet moment smoke passed: eight optional hearthside scenes derive from existing return, facility, story and refuge state in stable order; listening writes nothing, advances no time and grants no reward.")
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
	push_error("Archive Hideaway quiet moment smoke failure: %s" % message)
	quit(1)
