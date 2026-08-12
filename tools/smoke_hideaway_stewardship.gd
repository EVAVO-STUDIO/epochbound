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
	var duplicate := MODEL.record_return(qualified["state"], 400.0)
	_assert(not bool(duplicate["qualified"]), "duplicate return must not award twice")
	state = qualified["state"]
	for index: int in range(4):
		departure = MODEL.begin_expedition(state, "bellweather_crossing", 500.0 + index * 800.0)
		qualified = MODEL.record_return(departure["state"], 1200.0 + index * 800.0)
		state = qualified["state"]
	_assert(int(state["banked_returns"]) == MODEL.MAX_BANKED_RETURNS, "banked returns must remain capped")
	_assert(int(state["salvage"]) >= 2, "long expeditions must award bounded salvage")
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
	_assert(MODEL.validate_state(decoded).is_empty(), "JSON round trip must preserve valid durable state")
	var fractional := decoded.duplicate(true)
	fractional["banked_returns"] = 1.5
	_assert(not MODEL.validate_state(fractional).is_empty(), "fractional durable counters must fail closed")
	var unchanged := state.duplicate(true)
	var later_time := 999999.0
	_assert(state == unchanged and later_time > float(state["last_return_play_time"]), "time alone must not create offline progress")
	var invalid := state.duplicate(true)
	invalid["banked_returns"] = 4
	_assert(not MODEL.validate_state(invalid).is_empty(), "out-of-range return bank must fail closed")
	print("Archive Hideaway stewardship smoke test passed: short trips cannot farm rewards; qualifying active-play expeditions bank bounded opportunities; salvage restores facilities; preparations consume exactly once; JSON numeric round trips remain strict; and elapsed time alone grants nothing.")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Archive Hideaway stewardship smoke failure: %s" % message)
	quit(1)
