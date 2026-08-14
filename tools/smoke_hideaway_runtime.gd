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
	var opening_moments: Array = runtime.call("available_hideaway_quiet_moments")
	check(opening_moments.size() == 1 and str((opening_moments[0] as Dictionary).get("id", "")) == "threshold_breaths", "A new journey must begin with one optional read-only hearthside moment.")

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
	check(str(runtime.get("dialogue")).contains("2") and str(runtime.get("dialogue")).contains("/99"), "Qualified return feedback must expose actual salvage delta and capacity.")
	var quiet_definition: Dictionary = runtime.call("hideaway_definition_snapshot")
	check((quiet_definition.get("quiet_moments", []) as Array).size() == 8, "Reference Hideaway must load eight authored quiet moments.")
	var return_moments: Array = runtime.call("available_hideaway_quiet_moments")
	check(return_moments.size() == 2 and str((return_moments[1] as Dictionary).get("id", "")) == "first_return_watch", "The first qualifying return must add one Morrow downtime moment.")
	runtime.set("player", Vector2(222, 272))
	check(not (runtime.call("nearest_hideaway_quiet_nook") as Dictionary).is_empty(), "Authored quiet nook must be reachable in the live Hideaway.")
	var before_quiet: Dictionary = (runtime.get("session_state") as Dictionary).duplicate(true)
	runtime.set("dialogue", "")
	var listened: Dictionary = runtime.call("inspect_hideaway_quiet_moment")
	check(str(listened.get("id", "")) == "threshold_breaths", "Quiet nook inspection must begin at the baseline authored moment each visit.")
	check(str(runtime.get("dialogue")).contains("Threshold Breaths") and str(runtime.get("dialogue")).contains("ELI"), "Quiet nook inspection must show localised speaker, title and reflection copy.")
	check((runtime.get("session_state") as Dictionary) == before_quiet, "Listening to a quiet moment must not spend or mutate campaign state.")
	var quiet_descriptor: Dictionary = runtime.call("hideaway_quiet_moment_visual_descriptor", listened, 0)
	check(str(quiet_descriptor.get("signature", "")) == "together:threshold_breaths:0", "Quiet moment visual descriptors must remain deterministic.")
	var memento_definition: Dictionary = runtime.call("hideaway_definition_snapshot")
	check((memento_definition.get("mementos", []) as Array).size() == 6, "Reference Hideaway must load six authored journey mementos.")
	var first_mementos: Array = runtime.call("unlocked_hideaway_mementos")
	check(first_mementos.size() == 1 and str((first_mementos[0] as Dictionary).get("id", "")) == "first_safe_return", "First qualifying return must place the first safe-return memento on the shelf.")
	runtime.set("player", Vector2(526, 174))
	check(not (runtime.call("nearest_hideaway_memento_shelf") as Dictionary).is_empty(), "Authored memento shelf must be reachable in the live Hideaway.")
	var before_memory: Dictionary = (runtime.get("session_state") as Dictionary).duplicate(true)
	runtime.set("dialogue", "")
	var remembered: Dictionary = runtime.call("inspect_hideaway_memento")
	check(str(remembered.get("id", "")) == "first_safe_return", "Shelf inspection must cycle through the first unlocked memento.")
	check(str(runtime.get("dialogue")).contains("First Safe Return"), "Shelf inspection must show the localised memento name and reflection.")
	check((runtime.get("session_state") as Dictionary) == before_memory, "Remembering a memento must not spend or mutate campaign state.")
	var strap_descriptor: Dictionary = runtime.call("hideaway_memento_visual_descriptor", remembered, 0)
	check(str(strap_descriptor.get("signature", "")) == "strap:0", "Memento visual descriptors must remain deterministic.")
	check(str(runtime.call("hideaway_tier_name", "unsettled")).length() > 0, "Hideaway tier labels must resolve.")
	var hearth_zero: Dictionary = runtime.call("hideaway_facility_visual_descriptor", &"archive_hearth", 0)
	var hearth_three: Dictionary = runtime.call("hideaway_facility_visual_descriptor", &"archive_hearth", 3)
	check(str(hearth_zero.get("signature", "")) == "cold_stone" and str(hearth_three.get("signature", "")) == "chimney_glow", "Archive Hearth visuals must progress from cold stone to chimney glow.")
	check(float(hearth_three.get("footprint_scale", 0.0)) > float(hearth_zero.get("footprint_scale", 0.0)), "Facility stage-three silhouette must visibly exceed stage zero.")

	var upgraded: Dictionary = runtime.call("upgrade_hideaway_facility", &"archive_hearth")
	check(bool(upgraded.get("accepted", false)), "Two salvage must restore the Archive Hearth to level one.")
	check(str(runtime.get("dialogue")).contains("4"), "Upgrade feedback must expose the exact next Archive Hearth cost.")
	var prepared: Dictionary = runtime.call("prepare_hideaway_facility", &"archive_hearth")
	check(bool(prepared.get("accepted", false)), "One banked return must prepare the restored Archive Hearth.")
	check(str(runtime.get("dialogue")).contains("1/1"), "Preparation feedback must expose stored charge and level-derived capacity.")
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

	runtime.set("play_time_seconds", 420.0)
	check(bool(runtime.call("activate_map", "archive_hideaway", "from_bellweather", "verdant", true)), "Completed preparation expedition must be able to return to the memento shelf.")
	var complete_session: Dictionary = runtime.get("session_state")
	complete_session["bellweather:companion:well_name_scent"] = "discovered"
	complete_session["story:missing_hour:completed"] = true
	complete_session["bellweather:zone:east_ash_hunt"] = "cleared"
	complete_session["underworks:boss:sentinel"] = "defeated"
	runtime.set("session_state", complete_session)
	var haven_state: Dictionary = runtime.call("hideaway_state_snapshot")
	for facility_id in ["archive_hearth", "sheltered_coldframe", "salvage_workbench", "morrows_corner"]:
		haven_state["facilities"][facility_id] = 3
	check(bool(runtime.call("store_hideaway_state", haven_state)), "Archive Haven test state must remain valid.")
	var complete_mementos: Array = runtime.call("unlocked_hideaway_mementos")
	check(complete_mementos.size() == 6, "Existing story, combat, companion and refuge milestones must unlock all six mementos without new saved flags.")
	check(str((complete_mementos[5] as Dictionary).get("id", "")) == "archive_haven_key", "Archive Haven key must remain the final authored shelf memory.")
	var complete_moments: Array = runtime.call("available_hideaway_quiet_moments")
	check(complete_moments.size() == 8, "Existing return, facility, story and refuge state must expose all eight quiet moments without new saved flags.")
	check(str((complete_moments[7] as Dictionary).get("id", "")) == "archive_haven_stillness", "Archive Haven stillness must remain the final authored quiet moment.")
	runtime.set("player", Vector2(222, 272))
	runtime.set("dialogue", "")
	runtime.call("set_localisation_locale", "qps-ploc")
	var pseudo_quiet: Dictionary = runtime.call("inspect_hideaway_quiet_moment")
	check(not pseudo_quiet.is_empty() and str(runtime.get("dialogue")) != str(pseudo_quiet.get("display_name_key", "")), "Quiet moment speakers, titles and reflections must resolve through deterministic pseudo-localisation.")
	runtime.call("set_localisation_locale", "en")
	runtime.set("player", Vector2(526, 174))
	runtime.set("dialogue", "")
	runtime.call("set_localisation_locale", "qps-ploc")
	var pseudo_memento: Dictionary = runtime.call("inspect_hideaway_memento")
	check(not pseudo_memento.is_empty() and str(runtime.get("dialogue")) != str(pseudo_memento.get("display_name_key", "")), "Memento names and reflections must resolve through deterministic pseudo-localisation.")
	runtime.call("set_localisation_locale", "en")

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
		"ui.hideaway.status.mementos",
		"MEMENTOS {unlocked}/{total}   MEMORIES FROM THE ROAD",
		{"unlocked": 6, "total": 6}
	))
	check(pseudo_status != "ui.hideaway.status.mementos" and pseudo_status.contains("6/6"), "Hideaway memento status must resolve through deterministic pseudo-localisation.")
	var pseudo_quiet_status := str(runtime.call(
		"localise",
		"ui.hideaway.status.quiet",
		"QUIET MOMENTS {available}/{total}   HEARTHSIDE REFUGE",
		{"available": 8, "total": 8}
	))
	check(pseudo_quiet_status != "ui.hideaway.status.quiet" and pseudo_quiet_status.contains("8/8"), "Hideaway quiet-moment status must resolve through deterministic pseudo-localisation.")
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
		print("Archive Hideaway runtime smoke passed: authored travel, cap-accurate return rewards, derived refuge tiers, level-specific facility visuals, exact planning, six milestone-derived mementos, eight optional read-only hearthside moments, non-consuming localised reflections, one-use preparation, save strictness and sanctuary authority are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
