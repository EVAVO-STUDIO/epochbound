extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")

const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Environment-aware runtime scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime := (packed as PackedScene).instantiate()
	root.add_child(runtime)
	await process_frame
	var overlay: Node = runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	check(overlay != null, "Runtime scene must include the environment animation overlay.")
	if overlay == null:
		await HeadlessRuntimeCleanup.release(self, runtime)
		finish()
		return
	var overlay_script: Script = overlay.get_script() as Script
	check(
		script_chain_contains(overlay_script, "res://src/environment_animation_overlay.gd"),
		"Playable scene must inherit the environment animation overlay."
	)
	check(bool(overlay.call("environment_animation_contract_ok")), "Environment animation must preserve inherited adventure feedback and bounded effect contracts.")

	var synthetic_map := environment_test_map()
	runtime.set("map_data", synthetic_map)
	runtime.set("current_era_id", "verdant")
	runtime.set("flow", 4)
	runtime.set("player", Vector2(120, 104))
	runtime.set("companion", Vector2(136, 120))
	runtime.set("dialogue", "")
	runtime.set("transition_lock", 0.0)
	runtime.set("inventory_open", false)
	runtime.set("story_journal_open", false)
	runtime.set("save_overlay_open", false)
	runtime.set("merchant_open", false)
	runtime.set("active_cinematic_id", "")
	overlay.call("reset_environment_state")

	overlay.set("context_prompt", {
		"key": "interaction:test",
		"action": "USE",
		"target_name": "Test Mechanism",
		"position": Vector2(136, 104),
		"distance": 16.0,
		"enabled": true
	})
	overlay.set("context_prompt_alpha", 1.0)
	check(bool(overlay.call("interaction_world_pulse_allowed")), "A visible gameplay prompt must permit its matching world pulse.")
	runtime.set("dialogue", "The mechanism answers.")
	check(not bool(overlay.call("interaction_world_pulse_allowed")), "Dialogue must suppress the world pulse immediately even while prompt fade data remains.")
	runtime.set("dialogue", "")
	runtime.set("transition_lock", 0.2)
	check(not bool(overlay.call("interaction_world_pulse_allowed")), "Unresolved map transitions must suppress the world pulse.")
	runtime.set("transition_lock", 0.0)

	var counts: Dictionary = overlay.call("animated_terrain_counts")
	check(int(counts.get("water", 0)) == 1, "Synthetic map must expose one animated water cell.")
	check(int(counts.get("grass", 0)) == 2, "Synthetic map must expose two animated grass cells.")
	check(int(counts.get("metal", 0)) == 1, "Synthetic map must expose one animated brass-path cell.")
	check(str(overlay.call("terrain_effect_kind_at", Vector2(104, 104))) == "water", "Water cells must resolve ripple disturbances.")
	check(str(overlay.call("terrain_effect_kind_at", Vector2(120, 104))) == "grass", "Grass cells must resolve vegetation disturbances.")
	check(str(overlay.call("terrain_effect_kind_at", Vector2(152, 104))) == "metal", "Brass paths must resolve mechanical glints.")
	check(str(overlay.call("terrain_effect_kind_at", Vector2(168, 104))) == "dust", "Verdant stone must resolve restrained dust.")

	var previous := {
		"player": Vector2(116, 104),
		"companion": Vector2(136, 120)
	}
	overlay.set("environment_previous_positions", previous)
	overlay.set("environment_step_accumulators", {"player": 0.0, "companion": 0.0})
	runtime.set("player", Vector2(132, 104))
	overlay.call("update_environment_animation", 0.1)
	check(int(overlay.call("environment_disturbance_count")) == 1, "Actual player travel must spawn one bounded ground disturbance.")
	var kinds: PackedStringArray = overlay.call("ground_disturbance_kinds")
	check(kinds.has("grass"), "Movement across grass must create a grass response rather than a generic puff.")

	overlay.call("update_environment_animation", 2.0)
	check(int(overlay.call("environment_disturbance_count")) == 0, "Expired ground disturbances must be removed deterministically.")
	for index in range(80):
		overlay.call("spawn_environment_disturbance", Vector2(120 + index, 104), "dust", "test")
	check(int(overlay.call("environment_disturbance_count")) == 32, "Ground disturbance history must remain bounded at its authored maximum.")

	runtime.set("inventory_open", true)
	var clock_before := float(overlay.get("environment_clock"))
	overlay.call("update_environment_animation", 0.5)
	check(is_equal_approx(float(overlay.get("environment_clock")), clock_before), "Blocking menus must freeze terrain and disturbance animation time.")
	runtime.set("inventory_open", false)

	runtime.set("current_era_id", "ashen")
	overlay.call("update_environment_animation", 0.1)
	check(int(overlay.call("environment_disturbance_count")) == 0, "Era changes must clear transient ground disturbances.")
	check(str(overlay.call("terrain_effect_kind_at", Vector2(168, 104))) == "ash", "Ashen stone must resolve an ash disturbance instead of Verdant dust.")

	await HeadlessRuntimeCleanup.release(self, runtime)
	finish()


func environment_test_map() -> Dictionary:
	return {
		"schema_version": 1,
		"id": "environment_test",
		"display_name": "Environment Test",
		"canvas": {"width": 320, "height": 240, "grid_size": 16},
		"bounds": {"left": 32, "right": 288, "top": 80, "bottom": 224},
		"spawns": {
			"player": {"x": 120, "y": 104},
			"companion": {"x": 136, "y": 120}
		},
		"eras": [
			{
				"id": "verdant",
				"display_name": "Verdant Age",
				"palette": {"sky": "819a91", "ground": "4f6550", "accent": "e5d89f", "structure": "53625b"},
				"landmarks": []
			},
			{
				"id": "ashen",
				"display_name": "Ashen Age",
				"palette": {"sky": "5e4541", "ground": "52443a", "accent": "d77850", "structure": "392f2d"},
				"landmarks": []
			}
		],
		"terrain_palette": [
			{"id": "water", "display_name": "Water", "colors": {"default": "365a68", "verdant": "3f7180", "ashen": "493f49"}, "blocked": true},
			{"id": "grass", "display_name": "Grass", "colors": {"default": "4f6550", "verdant": "5f7958", "ashen": "55483d"}, "blocked": false},
			{"id": "brass_path", "display_name": "Brass Path", "colors": {"default": "796746", "verdant": "8b7950", "ashen": "73583f"}, "blocked": false},
			{"id": "stone", "display_name": "Stone", "colors": {"default": "3e4945", "verdant": "46544d", "ashen": "493b37"}, "blocked": false}
		],
		"terrain_cells": [
			{"x": 6, "y": 6, "tile": "water", "available_eras": []},
			{"x": 7, "y": 6, "tile": "grass", "available_eras": []},
			{"x": 8, "y": 6, "tile": "grass", "available_eras": []},
			{"x": 9, "y": 6, "tile": "brass_path", "available_eras": []},
			{"x": 10, "y": 6, "tile": "stone", "available_eras": []}
		],
		"collision_cells": [],
		"navigation_cells": [],
		"recovery_anchors": [],
		"entries": [],
		"connections": [],
		"interactions": [],
		"object_placements": [],
		"encounter_zones": [],
		"companion_cues": []
	}


func script_chain_contains(script: Script, expected_path: String) -> bool:
	var current := script
	while current != null:
		if str(current.resource_path) == expected_path:
			return true
		current = current.get_base_script()
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Environment animation smoke test passed: terrain cycles, movement responses, prompt-pulse suppression, menu freezing, era reset and bounded effect history are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)