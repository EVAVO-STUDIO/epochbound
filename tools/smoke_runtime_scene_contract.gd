extends SceneTree

const RuntimeSceneContract = preload("res://src/game/runtime_scene_contract.gd")
const RUNTIME_SCENE := "res://src/app.tscn"
const TEST_WEAPON_ID := "clockglass_dartcaster"
const TEST_BOSS_PLACEMENT := "runtime_contract_boss"
const AUDIO_STARTUP_FRAME_BUDGET := 10

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Canonical runtime scene must load as a PackedScene.")
	if not packed is PackedScene:
		finish()
		return

	var runtime := (packed as PackedScene).instantiate()
	check(runtime != null, "Canonical runtime scene must instantiate.")
	if runtime == null:
		finish()
		return
	root.add_child(runtime)

	var audio := runtime.get_node_or_null("AudioMood")
	if audio != null and audio.has_method("generator_startup_complete"):
		for _frame_index in range(AUDIO_STARTUP_FRAME_BUDGET):
			if bool(audio.call("generator_startup_complete")):
				break
			await process_frame
		check(
			bool(audio.call("generator_startup_complete")),
			"Complete-scene Audio startup must finish within the bounded frame budget. Diagnostics: %s" % JSON.stringify(audio_generator_diagnostics(audio))
		)
	else:
		await process_frame

	var contract_errors := RuntimeSceneContract.validate_runtime_scene(runtime)
	for error in contract_errors:
		failures.append(str(error))
	check(RuntimeSceneContract.runtime_scene_is_valid(runtime), "Canonical runtime contract must pass after ready.")

	if audio != null and audio.has_method("generator_players_ready"):
		check(bool(audio.call("generator_players_ready")), "Audio generators must be ready in the complete playable scene.")
		var diagnostics := audio_generator_diagnostics(audio)
		check(
			int(audio.call("generator_skip_count")) == 0,
			"Complete-scene startup must not report Audio generator underruns. Diagnostics: %s" % JSON.stringify(diagnostics)
		)

	var inventory_value: Variant = runtime.get("inventory")
	var inventory: Dictionary = inventory_value as Dictionary if typeof(inventory_value) == TYPE_DICTIONARY else {}
	inventory[TEST_WEAPON_ID] = 1
	runtime.set("inventory", inventory)
	check(bool(runtime.call("equip_specific_item", TEST_WEAPON_ID)), "Runtime-contract setup must equip the reference ranged weapon.")
	var visible_weapon_value: Variant = runtime.call("equipped_ranged_weapon_data")
	check(typeof(visible_weapon_value) == TYPE_DICTIONARY and not (visible_weapon_value as Dictionary).is_empty(), "Normal runtime queries must expose the equipped ranged weapon.")

	var original_entities_value: Variant = runtime.get("runtime_entities")
	var original_entities: Array = (original_entities_value as Array).duplicate(true) if typeof(original_entities_value) == TYPE_ARRAY else []
	var original_engaged_value: Variant = runtime.get("engaged_bosses")
	var original_engaged: Dictionary = (original_engaged_value as Dictionary).duplicate(true) if typeof(original_engaged_value) == TYPE_DICTIONARY else {}
	runtime.set("runtime_entities", [{
		"placement_id": TEST_BOSS_PLACEMENT,
		"active": true,
		"definition": {"kind": "enemy"}
	}])
	var synthetic_engaged := {}
	synthetic_engaged[TEST_BOSS_PLACEMENT] = true
	runtime.set("engaged_bosses", synthetic_engaged)
	check(int(runtime.call("current_boss_index")) == 0, "Normal runtime queries must expose the active boss index.")

	var capabilities_before: PackedStringArray = runtime.call("active_capabilities") as PackedStringArray
	runtime.set("suppress_root_combat_hud", true)
	check(not bool(runtime.call("root_presentation_suppression_contract_ok")), "The root suppression contract must report its temporary draw-only state.")
	var suppressed_weapon_value: Variant = runtime.call("equipped_ranged_weapon_data")
	check(typeof(suppressed_weapon_value) == TYPE_DICTIONARY and (suppressed_weapon_value as Dictionary).is_empty(), "Selective root HUD suppression must hide only the duplicate Arsenal panel query.")
	check(int(runtime.call("current_boss_index")) == -1, "Selective root HUD suppression must hide only the duplicate Boss panel query.")
	var capabilities_during: PackedStringArray = runtime.call("active_capabilities") as PackedStringArray
	check(capabilities_during == capabilities_before, "Selective combat HUD suppression must not alter gameplay capabilities.")
	runtime.set("suppress_root_combat_hud", false)
	check(bool(runtime.call("root_presentation_suppression_contract_ok")), "Selective combat HUD suppression must restore immediately after drawing.")
	visible_weapon_value = runtime.call("equipped_ranged_weapon_data")
	check(typeof(visible_weapon_value) == TYPE_DICTIONARY and not (visible_weapon_value as Dictionary).is_empty(), "Ranged weapon queries must restore after root HUD drawing.")
	check(int(runtime.call("current_boss_index")) == 0, "Boss queries must restore after root HUD drawing.")
	runtime.set("runtime_entities", original_entities)
	runtime.set("engaged_bosses", original_engaged)

	var overlay := runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	var layer := runtime.get_node_or_null("PresentationLayer")
	check(overlay != null and layer is CanvasLayer, "Presentation layer and overlay must exist for fallback testing.")
	if overlay != null and layer is CanvasLayer:
		(layer as CanvasLayer).remove_child(overlay)
		check(not bool(runtime.call("presentation_overlay_handles_combat_readability")), "Removing the overlay must restore root fallback ownership.")
		check(not bool(runtime.call("root_presentation_suppression_contract_ok")), "Root suppression must disable itself when the high presentation layer is unavailable.")
		(layer as CanvasLayer).add_child(overlay)
		check(bool(runtime.call("presentation_overlay_handles_combat_readability")), "Reattaching the overlay must restore presentation-owned combat rendering.")
		check(bool(runtime.call("root_presentation_suppression_contract_ok")), "Reattaching the overlay must restore duplicate-render suppression.")

	root.remove_child(runtime)
	runtime.free()
	finish()


func audio_generator_diagnostics(audio: Node) -> Dictionary:
	var result := {
		"startup_complete": bool(audio.call("generator_startup_complete")) if audio.has_method("generator_startup_complete") else false,
		"startup_attempts": int(audio.call("generator_startup_attempt_count")) if audio.has_method("generator_startup_attempt_count") else -1,
		"active_profile_id": str(audio.get("active_profile_id")),
		"loaded_campaign_key": str(audio.get("loaded_campaign_key")),
		"loaded_context_key": str(audio.get("loaded_context_key")),
		"total_skips": int(audio.call("generator_skip_count")),
		"players": {}
	}
	var players: Dictionary = result["players"]
	for player_name in ["Music", "Ambience", "SFX"]:
		var player := audio.get_node_or_null(player_name) as AudioStreamPlayer
		var entry := {
			"exists": player != null,
			"playing": player.playing if player != null else false,
			"paused": player.stream_paused if player != null else false,
			"skips": -1,
			"frames_available": -1
		}
		if player != null and player.has_stream_playback():
			var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
			if playback != null:
				entry["skips"] = playback.get_skips()
				entry["frames_available"] = playback.get_frames_available()
		players[player_name] = entry
	return result


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Runtime scene contract smoke test passed: canonical scripts, inherited systems, selective Arsenal and Boss HUD ownership, bounded Audio readiness, CanvasLayer fallback and restoration are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)