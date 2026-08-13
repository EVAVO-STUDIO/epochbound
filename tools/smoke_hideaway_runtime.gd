extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")
const SaveValidator = preload("res://src/content/save_validator.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Archive Hideaway smoke requires the canonical runtime scene.")
	if not packed is PackedScene:
		finish()
		return
	var runtime: Node = (packed as PackedScene).instantiate()
	root.add_child(runtime)
	await process_frame
	check(str((runtime.get_script() as Script).resource_path) == "res://src/presentation_runtime_current.gd", "Canonical scene must retain the presentation root while inheriting the live Hideaway layer.")
	check(bool(runtime.call("hideaway_runtime_contract_ok")), "Archive Hideaway runtime contract must hold after startup.")
	runtime.call("change_flow", 4)
	runtime.set("play_time_seconds", 5.0)
	check(bool(runtime.call("activate_map", "archive_hideaway", "from_bellweather", "verdant", true)), "Reference player must be able to enter the Archive Hideaway.")
	var first_visit: Dictionary = runtime.call("hideaway_state_snapshot")
	check(int(first_visit.get("salvage", -1)) == 0 and int(first_visit.get("banked_returns", -1)) == 0, "First arrival cannot fabricate return rewards.")

	runtime.set("play_time_seconds", 10.0)
	check(bool(runtime.call("activate_map", "bellweather_crossing", "from_hideaway", "verdant", true)), "Leaving the refuge must return to Bellweather.")
	var departed: Dictionary = runtime.call("hideaway_state_snapshot")
	check(bool(departed.get("expedition_active", false)), "Leaving the refuge must begin one active-play expedition.")
	runtime.set("play_time_seconds", 40.0)
	check(bool(runtime.call("activate_map", "archive_hideaway", "from_bellweather", "verdant", true)), "A short expedition must still be able to return home.")
	var short_return: Dictionary = runtime.call("hideaway_state_snapshot")
	check(int(short_return.get("salvage", -1)) == 0, "A short expedition must not award salvage.")
	check(str(runtime.get("dialogue")).contains("60"), "A short return must explain the remaining active-play requirement.")
	runtime.set("dialogue", "")
	runtime.set("play_time_seconds", 50.0)
	check(bool(runtime.call("activate_map", "bellweather_crossing", "from_hideaway", "verdant", true)), "A second expedition must be able to leave the refuge.")
	runtime.set("play_time_seconds", 350.0)
	check(bool(runtime.call("activate_map", "archive_hideaway", "from_bellweather", "verdant", true)), "A qualifying expedition must be able to return home.")
	var returned: Dictionary = runtime.call("hideaway_state_snapshot")
	check(int(returned.get("salvage", 0)) == 2, "A 300-second expedition must award exactly two bounded salvage.")
	check(int(returned.get("banked_returns", 0)) == 1, "A qualifying expedition must bank one preparation opportunity.")

	var upgraded: Dictionary = runtime.call("upgrade_hideaway_facility", &"archive_hearth")
	check(bool(upgraded.get("accepted", false)), "Two salvage must restore the Archive Hearth to level one.")
	var prepared: Dictionary = runtime.call("prepare_hideaway_facility", &"archive_hearth")
	check(bool(prepared.get("accepted", false)), "One banked return must prepare the restored Archive Hearth.")
	runtime.set("dialogue", "")
	runtime.set("play_time_seconds", 320.0)
	check(bool(runtime.call("activate_map", "bellweather_crossing", "from_hideaway", "verdant", true)), "Prepared player must be able to leave the refuge.")
	var after_departure: Dictionary = runtime.call("hideaway_state_snapshot")
	var prepared_state: Dictionary = after_departure.get("prepared", {})
	check(int(prepared_state.get("warmth", -1)) == 0, "Departure must consume exactly one prepared warmth charge.")
	var session_state: Dictionary = runtime.get("session_state")
	check(int(session_state.get("hideaway:buff:warmth_guard", 0)) == 1, "Consumed warmth must become one bounded expedition guard.")
	var health_before := int(runtime.get("player_health"))
	runtime.set("player_hurt_lock", 0.0)
	runtime.call("damage_actor", "player", 2, {"display_name": "Smoke Hound"})
	check(int(runtime.get("player_health")) == health_before, "Archive Hearth warmth must absorb one two-point hit exactly once.")
	check(int((runtime.get("session_state") as Dictionary).get("hideaway:buff:warmth_guard", 0)) == 0, "Warmth guard must consume exactly once.")

	var profile: Dictionary = runtime.call("capture_save_profile", "slot_1", "Hideaway runtime smoke")
	var validation: Dictionary = SaveValidator.validate_profile(profile, CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Valid Archive Hideaway stewardship state must survive canonical save validation.")
	var invalid_profile := profile.duplicate(true)
	var invalid_payload: Dictionary = (invalid_profile.get("payload", {}) as Dictionary).duplicate(true)
	var invalid_session: Dictionary = (invalid_payload.get("session_state", {}) as Dictionary).duplicate(true)
	var invalid_hideaway: Dictionary = (invalid_session.get("hideaway:stewardship", {}) as Dictionary).duplicate(true)
	invalid_hideaway["banked_returns"] = 1.5
	invalid_session["hideaway:stewardship"] = invalid_hideaway
	invalid_payload["session_state"] = invalid_session
	invalid_profile["payload"] = invalid_payload
	check(not bool(SaveValidator.validate_profile(invalid_profile, CAMPAIGN_PATH).get("ok", true)), "Fractional Hideaway durable state must fail closed during save validation.")
	var invalid_transient := profile.duplicate(true)
	var transient_payload: Dictionary = (invalid_transient.get("payload", {}) as Dictionary).duplicate(true)
	var transient_session: Dictionary = (transient_payload.get("session_state", {}) as Dictionary).duplicate(true)
	transient_session["hideaway:buff:warmth_guard"] = 0.5
	transient_payload["session_state"] = transient_session
	invalid_transient["payload"] = transient_payload
	check(not bool(SaveValidator.validate_profile(invalid_transient, CAMPAIGN_PATH).get("ok", true)), "Fractional Hideaway one-use counters must fail closed during save validation.")
	runtime.call("set_localisation_locale", "qps-ploc")
	var pseudo_status := str(runtime.call(
		"localise",
		"ui.hideaway.status.header",
		"ARCHIVE HIDEAWAY   SALVAGE {salvage}   RETURNS {returns}",
		{"salvage": 99, "returns": 3}
	))
	check(pseudo_status != "ui.hideaway.status.header" and pseudo_status.contains("99"), "Hideaway status feedback must resolve through deterministic pseudo-localisation.")
	runtime.call("set_localisation_locale", "en")

	check(bool(runtime.call("activate_map", "archive_hideaway", "from_bellweather", "ashen", false)), "Ashen Hideaway must activate for sanctuary testing.")
	runtime.set("player", Vector2(286, 246))
	var session: Node = runtime.get_node_or_null("MultiplayerSession")
	check(session != null, "Archive Hideaway smoke requires MultiplayerSession.")
	if session != null:
		check(bool(session.call("configure_test_host_session")), "Hideaway sanctuary test must configure host authority.")
		var area: Dictionary = session.call("online_area")
		check(str(area.get("id", "")) == "archive_hideaway_sanctuary", "Archive Hideaway must resolve an explicit sanctuary online area.")
		var invader_area: Dictionary = session.call("join_area_for_role", "invader")
		check(invader_area.is_empty(), "Invaders must be rejected inside the Archive Hideaway sanctuary.")

	await HeadlessRuntimeCleanup.release(self, runtime)
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Archive Hideaway runtime smoke passed: authored travel, active-play return rewards, facility restoration, short-return guidance, localised bounded feedback, one-use warmth, save strictness and sanctuary authority are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
