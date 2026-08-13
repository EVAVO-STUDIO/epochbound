extends SceneTree

const MEMENTOS := preload("res://src/game/hideaway_memento_model.gd")
const STEWARDSHIP := preload("res://src/game/hideaway_stewardship.gd")
const VALIDATOR := preload("res://src/content/hideaway_stewardship_validator.gd")


func _init() -> void:
	var report := VALIDATOR.validate_hideaway_only(VALIDATOR.REFERENCE_CAMPAIGN_PATH)
	_assert(bool(report.get("ok", false)), "reference Hideaway definition must validate")
	_assert(int(report.get("hideaway_memento_count", 0)) == 6, "reference shelf must author six mementos")
	var definition: Dictionary = report.get("definition", {})
	_assert(MEMENTOS.memento_contract_ok(), "memento model contract must hold")
	_assert(MEMENTOS.shelf_slots(definition) == 6, "reference shelf must expose six bounded slots")
	_assert(MEMENTOS.shelf_interaction_id(definition) == "memento_shelf_station", "reference shelf interaction must remain stable")

	var stewardship := STEWARDSHIP.default_state(0.0)
	var session: Dictionary = {}
	var pristine_definition := definition.duplicate(true)
	var pristine_session := session.duplicate(true)
	var pristine_stewardship := stewardship.duplicate(true)
	_assert(MEMENTOS.unlocked_entries(definition, session, stewardship).is_empty(), "new journeys must begin with an empty memento shelf")
	_assert(definition == pristine_definition and session == pristine_session and stewardship == pristine_stewardship, "unlock evaluation must not mutate authored or durable state")

	stewardship["return_count"] = 1
	var first_return := MEMENTOS.unlocked_entries(definition, session, stewardship)
	_assert(_ids(first_return) == ["first_safe_return"], "the first qualifying return must unlock only its own memento")

	session["bellweather:companion:well_name_scent"] = "discovered"
	session["story:missing_hour:completed"] = true
	session["bellweather:zone:east_ash_hunt"] = "cleared"
	session["underworks:boss:sentinel"] = "defeated"
	var milestones := MEMENTOS.unlocked_entries(definition, session, stewardship)
	_assert(
		_ids(milestones) == [
			"first_safe_return",
			"well_name_rubbing",
			"absent_chime_case",
			"quieted_ash_mark",
			"released_accession_plate",
		],
		"existing campaign milestones must unlock authored mementos in stable order"
	)

	for facility_id: StringName in STEWARDSHIP.FACILITY_IDS:
		stewardship["facilities"][String(facility_id)] = STEWARDSHIP.MAX_FACILITY_LEVEL
	var complete := MEMENTOS.unlocked_entries(definition, session, stewardship)
	_assert(complete.size() == 6 and str((complete[complete.size() - 1] as Dictionary).get("id", "")) == "archive_haven_key", "Archive Haven must unlock the final key without a new saved flag")
	_assert(str(MEMENTOS.reflection_key(complete[0], "verdant")).ends_with(".verdant"), "Verdant reflection keys must remain deterministic")
	_assert(not MEMENTOS.reflection_fallback(complete[0], "ashen").is_empty(), "Ashen reflection fallback must remain authored")

	var duplicate := definition.duplicate(true)
	duplicate["mementos"].append((duplicate["mementos"] as Array)[0].duplicate(true))
	_assert(not VALIDATOR.validate_definition(duplicate).is_empty(), "duplicate memento IDs must fail closed")
	var rewarded := definition.duplicate(true)
	var rewarded_entries: Array = rewarded["mementos"]
	var rewarded_entry: Dictionary = rewarded_entries[0]
	rewarded_entry["rewards"] = [{"type": "grant_currency", "amount": 99}]
	rewarded_entries[0] = rewarded_entry
	_assert(not VALIDATOR.validate_definition(rewarded).is_empty(), "mementos must reject reward payloads")
	var unknown_condition := definition.duplicate(true)
	var unknown_entries: Array = unknown_condition["mementos"]
	var unknown_entry: Dictionary = unknown_entries[0]
	unknown_entry["conditions"] = [{"type": "wall_clock_day", "value": 1}]
	unknown_entries[0] = unknown_entry
	_assert(not VALIDATOR.validate_definition(unknown_condition).is_empty(), "unknown and wall-clock unlock conditions must fail closed")
	var oversized := definition.duplicate(true)
	oversized["memento_shelf"]["maximum_slots"] = 1
	_assert(not VALIDATOR.validate_definition(oversized).is_empty(), "authored mementos cannot exceed the bounded shelf")

	print("Archive Hideaway memento smoke passed: six authored memories unlock from existing journey state in stable order, add no rewards or saved flags, retain era-specific reflections and fail closed on malformed content.")
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
	push_error("Archive Hideaway memento smoke failure: %s" % message)
	quit(1)
