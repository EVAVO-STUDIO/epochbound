extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")
const AudioMoodValidator = preload("res://src/content/audio_mood_strict_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"
const STARTUP_FRAME_BUDGET := 10

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var validation: Dictionary = AudioMoodValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must pass Audio and Mood validation.")
	check(int(validation.get("audio_profile_count", 0)) == 7, "Reference campaign must expose seven audio profiles.")
	check(int(validation.get("audio_binding_count", 0)) == 6, "Reference campaign must bind all six map/era contexts.")
	var campaign_result: Dictionary = Repository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog_result: Dictionary = AudioMoodCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(catalog_result.get("ok", false)), "Audio catalogue must load.")
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var bindings_value: Variant = catalog_result.get("bindings", [])
	var bindings: Array = bindings_value as Array if typeof(bindings_value) == TYPE_ARRAY else []
	var profile: Dictionary = AudioMoodCatalog.resolved_profile(definitions, bindings, "clockwood_edge", "ashen")
	check(str(profile.get("id", "")) == "clockwood_ashen", "Clockwood Ashen must resolve its authored audio profile.")
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Audio-aware runtime scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime: Node = (packed as PackedScene).instantiate()
	root.add_child(runtime)
	var controller: Node = runtime.get_node_or_null("AudioMood")
	check(controller != null, "Runtime scene must include AudioMood.")
	if controller != null:
		for _frame_index in range(STARTUP_FRAME_BUDGET):
			if controller.has_method("generator_startup_complete") and bool(controller.call("generator_startup_complete")):
				break
			await process_frame
		var startup_context := {
			"complete": bool(controller.call("generator_startup_complete")) if controller.has_method("generator_startup_complete") else false,
			"attempts": int(controller.call("generator_startup_attempt_count")) if controller.has_method("generator_startup_attempt_count") else -1,
			"players_ready": bool(controller.call("generator_players_ready")),
			"music_clock": int(controller.get("music_sample_clock")),
			"ambience_clock": int(controller.call("ambience_clock_value")),
			"skips": int(controller.call("generator_skip_count"))
		}
		check(bool(startup_context.get("complete", false)), "Audio startup must complete within the bounded frame budget. Context: %s" % JSON.stringify(startup_context))
		check(str(controller.get_script().resource_path) == "res://src/audio_mood_runtime.gd", "Runtime scene must use the hardened Audio and Mood adapter.")
		var music: AudioStreamPlayer = controller.get_node_or_null("Music") as AudioStreamPlayer
		var ambience: AudioStreamPlayer = controller.get_node_or_null("Ambience") as AudioStreamPlayer
		var sfx: AudioStreamPlayer = controller.get_node_or_null("SFX") as AudioStreamPlayer
		check(music != null and music.bus == "Music", "Music generator must route through the Music bus.")
		check(ambience != null and ambience.bus == "Ambience", "Ambience generator must route through the Ambience bus.")
		check(sfx != null and sfx.bus == "SFX", "SFX generator must route through the SFX bus.")
		check(bool(controller.call("generator_players_ready")), "All generator playback objects must be ready after startup priming.")
		check(int(controller.get("music_sample_clock")) > 0, "Music buffer must be primed before playback is released.")
		check(int(controller.call("ambience_clock_value")) > 0, "Ambience must use and advance its own sample clock.")
		check(int(controller.call("generator_skip_count")) == 0, "Startup buffer priming must avoid generator underruns. Context: %s" % JSON.stringify(startup_context))
		controller.call("queue_sound", "shift")
		check(int(controller.call("queued_sfx_count")) >= 3, "Era-shift feedback must queue a three-voice original stinger.")
		runtime.set("flow", 4)
		controller.call("resolve_active_profile", true)
		var map_value: Variant = runtime.get("map_data")
		var map_data: Dictionary = map_value as Dictionary if typeof(map_value) == TYPE_DICTIONARY else {}
		var runtime_context := {
			"flow": int(runtime.get("flow")),
			"map_id": str(map_data.get("id", "")),
			"era_id": str(runtime.get("current_era_id")),
			"campaign_path": str(runtime.get("campaign_path")),
			"campaign_id": str((runtime.get("campaign") as Dictionary).get("id", "")) if typeof(runtime.get("campaign")) == TYPE_DICTIONARY else "",
			"load_error": str(runtime.get("load_error")),
			"active_profile_id": str(controller.get("active_profile_id")),
			"loaded_campaign_key": str(controller.get("loaded_campaign_key")),
			"loaded_context_key": str(controller.get("loaded_context_key")),
			"definition_count": int((controller.get("definitions") as Dictionary).size()) if typeof(controller.get("definitions")) == TYPE_DICTIONARY else -1,
			"binding_count": int((controller.get("bindings") as Array).size()) if typeof(controller.get("bindings")) == TYPE_ARRAY else -1
		}
		check(
			str(controller.get("active_profile_id")) == "bellweather_verdant",
			"Gameplay must resolve the current map and era audio profile. Context: %s" % JSON.stringify(runtime_context)
		)
		controller.set("previous_flow", 1)
		controller.set("previous_map_id", "previous_map")
		controller.set("previous_era_id", str(runtime.get("current_era_id")))
		controller.set("previous_player_health", int(runtime.get("player_health")))
		controller.set("previous_companion_health", int(runtime.get("companion_health")))
		controller.set("previous_attack_timer", float(runtime.get("player_attack_timer")))
		controller.set("previous_clock_shards", int(runtime.get("clock_shards")))
		controller.set("previous_menu_open", false)
		controller.set("previous_dialogue", str(runtime.get("dialogue")))
		controller.set("previous_cinematic_id", str(runtime.get("active_cinematic_id")))
		controller.set("previous_combat_active", bool(controller.call("combat_is_active")))
		var voices_before := int(controller.call("queued_sfx_count"))
		controller.call("update_events")
		check(int(controller.call("queued_sfx_count")) == voices_before + 1, "Entering gameplay and changing maps in one frame must queue one travel cue, not two.")
	root.remove_child(runtime)
	runtime.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Audio and Mood runtime smoke test passed: profiles, buses, bounded priming, zero underruns, independent ambience timing and event cues are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)