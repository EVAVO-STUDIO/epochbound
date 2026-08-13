extends SceneTree

const MODEL := preload("res://src/game/hideaway_stewardship.gd")
const VALIDATOR := preload("res://src/content/hideaway_stewardship_validator.gd")


func _init() -> void:
	var definition := VALIDATOR.load_reference_definition()
	_assert(VALIDATOR.validate_definition(definition).is_empty(), "reference definition must validate")
	var state := MODEL.default_state(10.0)
	_assert(MODEL.validate_state(state).is_empty(), "default state must validate")
	var departure := MODEL.begin_expedition(state, "clockwood_edge", 10.0)
	_assert(bool(departure["accepted"]), "first expedition must begin")
	var short_return := MODEL.record_return(departure["state"], 99.0)
	_assert(not bool(short_return["qualified"]), "sub-threshold expedition must not qualify")
	_assert(int(short_return["state"]["salvage"]) == 0, "short expedition must not award salvage")
	departure = MODEL.begin_expedition(short_return["state"], "museum_underworks", 100.0)
	var qualified := MODEL.record_return(departure["state"], 190.0)
	_assert(bool(qualified["qualified"]), "ninety-second expedition must qualify")
	_assert(int(qualified["salvage_awarded"]) == 1, "minimum expedition must award one salvage")
	_assert(int(qualified["state"]["banked_returns"]) == 1, "return opportunity must bank")
	_assert(int(qualified["return_opportunities_awarded"]) == 1, "return result must report the stored opportunity delta")
	var duplicate := MODEL.record_return(qualified["state"], 400.0)
	_assert(not bool(duplicate["qualified"]), "duplicate return must not award twice")
	state = qualified["state"]
	for index: int in range(4):
		departure = MODEL.begin_expedition(state, "bellweather_crossing", 500.0 + index * 800.0)
		qualified = MODEL.record_return(departure["state"], 1200.0 + index * 800.0)
		state = qualified["state"]
	_assert(int(state["banked_returns"]) == MODEL.MAX_BANKED_RETURNS, "banked returns must remain capped")
	_assert(int(state["salvage"]) >= 2, "long expeditions must award bounded salvage")
	var capped := MODEL.default_state(0.0)
	capped["salvage"] = 98
	var capped_departure := MODEL.begin_expedition(capped, "clockwood_edge", 0.0)
	var capped_return := MODEL.record_return(capped_departure["state"], 900.0)
	_assert(bool(capped_return["qualified"]), "capped expedition must still qualify")
	_assert(int(capped_return["state"]["salvage"]) == MODEL.MAX_SALVAGE, "salvage must stop at the authored cap")
	_assert(int(capped_return["salvage_awarded"]) == 1, "return feedback must report only salvage actually stored")
	var capped_returns := MODEL.default_state(0.0)
	capped_returns["banked_returns"] = MODEL.MAX_BANKED_RETURNS
	var capped_returns_departure := MODEL.begin_expedition(capped_returns, "clockwood_edge", 0.0)
	var capped_returns_result := MODEL.record_return(capped_returns_departure["state"], 90.0)
	_assert(int(capped_returns_result["return_opportunities_awarded"]) == 0, "return feedback must report zero opportunities when the bank is already full")
	var empty_summary := MODEL.refuge_summary(MODEL.default_state())
	_assert(str(empty_summary["tier_id"]) == "unsettled", "an unrestored refuge must begin unsettled")
	var staged := MODEL.default_state()
	staged["facilities"]["archive_hearth"] = 1
	staged["facilities"]["sheltered_coldframe"] = 1
	staged["facilities"]["salvage_workbench"] = 1
	staged["facilities"]["morrows_corner"] = 1
	_assert(str(MODEL.refuge_summary(staged)["tier_id"]) == "sheltered", "four total facility levels must establish shelter")
	for key in staged["facilities"].keys():
		staged["facilities"][key] = 2
	_assert(str(MODEL.refuge_summary(staged)["tier_id"]) == "established", "eight total facility levels must establish the refuge")
	for key in staged["facilities"].keys():
		staged["facilities"][key] = 3
	var haven := MODEL.refuge_summary(staged)
	_assert(str(haven["tier_id"]) == "haven" and int(haven["total_level"]) == 12, "all facilities at level three must form the Archive Haven")
	var hearth_status := MODEL.facility_status(staged, &"archive_hearth")
	_assert(bool(hearth_status["fully_restored"]) and int(hearth_status["next_upgrade_cost"]) == -1, "fully restored facility status must expose no next cost")
	var upgrade := MODEL.upgrade_facility(state, &"archive_hearth")
	_assert(bool(upgrade["accepted"]), "Archive Hearth must restore when affordable")
	state = upgrade["state"]
	_assert(int(state["facilities"]["archive_hearth"]) == 1, "Archive Hearth level must increase")
	var preparation := MODEL.prepare_facility(state, &"archive_hearth")
	_assert(bool(preparation["accepted"]), "restored facility must prepare a benefit")
	state = preparation["state"]
	_assert(int(state["prepared"]["warmth"]) == 1, "warmth preparation must be stored")
	var consumed := MODEL.consume_prepared_effect(state, &"warmth")
	_assert(bool(consumed["accepted"]), "prepared warmth must be consumable")
	state = consumed["state"]
	_assert(int(state["prepared"]["warmth"]) == 0, "consumption must decrement exactly once")
	var encoded := JSON.stringify(state)
	var decoded: Variant = JSON.parse_string(encoded)
	_assert(decoded is Dictionary, "JSON round trip must restore a dictionary")
	_assert(MODEL.validate_state(decoded).is_empty(), "JSON round trip must preserve valid durable state")
	var restored: Dictionary = decoded as Dictionary
	var fractional: Dictionary = restored.duplicate(true)
	fractional["banked_returns"] = 1.5
	_assert(not MODEL.validate_state(fractional).is_empty(), "fractional durable counters must fail closed")
	var unchanged: Dictionary = state.duplicate(true)
	var later_time := 999999.0
	_assert(state == unchanged and later_time > float(state["last_return_play_time"]), "time alone must not create offline progress")
	var invalid: Dictionary = state.duplicate(true)
	invalid["banked_returns"] = 4
	_assert(not MODEL.validate_state(invalid).is_empty(), "out-of-range return bank must fail closed")
	print("Archive Hideaway stewardship smoke test passed: short trips cannot farm rewards; qualifying active-play expeditions report cap-safe salvage and return deltas; four derived refuge tiers follow exact facility levels; planning status exposes next costs and preparation capacity; salvage restores facilities; preparations consume exactly once; JSON numeric round trips remain strict; and elapsed time alone grants nothing.")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Archive Hideaway stewardship smoke failure: %s" % message)
	quit(1)
