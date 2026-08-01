extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const SpriteAnimationCatalog = preload("res://src/content/sprite_animation_catalog.gd")
const SpriteAnimationValidator = preload("res://src/content/sprite_animation_strict_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var validation := SpriteAnimationValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must pass strict sprite animation validation.")
	check(int(validation.get("animation_profile_count", 0)) == 6, "Reference campaign must expose six animation profiles.")
	check(int(validation.get("animation_binding_count", 0)) == 6, "Reference campaign must expose six animation bindings.")
	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog_result := SpriteAnimationCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(catalog_result.get("ok", false)), "Reference animation catalogue must load.")
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var bindings_value: Variant = catalog_result.get("bindings", [])
	var bindings: Array = bindings_value as Array if typeof(bindings_value) == TYPE_ARRAY else []
	var player_profile := SpriteAnimationCatalog.resolved_profile(definitions, bindings, PackedStringArray(["player", "kind:actor", "*"]))
	var beast_profile := SpriteAnimationCatalog.resolved_profile(definitions, bindings, PackedStringArray(["object:ash_hound", "shape:beast", "kind:enemy", "*"]))
	check(str(player_profile.get("id", "")) == "eli_field_kit", "Player binding must resolve Eli's authored field profile.")
	check(str(beast_profile.get("id", "")) == "ash_beast_gait", "Beast shape binding must resolve the Ash Beast gait.")
	check(int(SpriteAnimationCatalog.animation(player_profile, "walk").get("frames", 0)) == 6, "Eli walk animation must retain six frames.")

	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Sprite-aware runtime scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime := (packed as PackedScene).instantiate()
	root.add_child(runtime)
	await process_frame
	var runtime_script: Variant = runtime.get_script()
	check(runtime_script is GDScript, "Runtime root must retain its presentation-safe adapter.")
	if runtime_script is GDScript:
		check(str((runtime_script as GDScript).resource_path) == "res://src/presentation_runtime_current.gd", "Runtime must bind the presentation-safe cinematic adapter.")
	var overlay: Node = runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	check(overlay != null, "Runtime scene must include the Sprite Animation overlay.")
	if overlay != null:
		check(str(overlay.get_script().resource_path) == "res://src/combat_readability_overlay.gd", "Runtime must bind the combat-readable environment and animation adapter.")
		check(bool(overlay.call("sprite_runtime_contract_ok")), "Runtime overlay must use nearest filtering and loaded animation data.")
		check(bool(overlay.call("animation_polish_contract_ok")), "Runtime overlay must expose grounded cadence and depth-sort guarantees.")
		check(bool(overlay.call("adventure_feedback_contract_ok")), "Runtime overlay must expose bounded area-card and action-prompt guarantees.")
		check(bool(overlay.call("environment_animation_contract_ok")), "Runtime overlay must expose bounded animated-terrain and ground-response guarantees.")
		check(bool(overlay.call("combat_readability_contract_ok")), "Runtime overlay must preserve projectile, boss and pause-layer readability.")
		check(int(overlay.call("landmark_foreground_count")) >= 1, "Reference gameplay must expose at least one foreground landmark occluder.")
		check(int(overlay.call("animation_profile_count")) == 6, "Runtime overlay must load all reference animation profiles.")
		check(int(overlay.call("animation_binding_count")) == 6, "Runtime overlay must load all reference animation bindings.")

		runtime.set("flow", 4)
		overlay.call("announce_current_area")
		check(str(overlay.get("area_banner_title")) == "BELLWEATHER CROSSING", "Area cards must resolve the current map display name.")
		check(str(overlay.get("area_banner_subtitle")).contains("VERDANT"), "Area cards must resolve the current era display name.")

		runtime.set("player", Vector2(100, 200))
		runtime.set("runtime_entities", [{
			"placement_id": "prompt_archivist",
			"position": Vector2(104, 200),
			"active": true,
			"definition": {
				"id": "prompt_archivist",
				"display_name": "Test Archivist",
				"kind": "npc",
				"interaction_radius": 40,
				"appearance": {"shape": "person"}
			}
		}])
		var prompt: Dictionary = overlay.call("context_prompt_snapshot")
		check(str(prompt.get("action", "")) == "TALK", "Nearby NPCs must resolve a TALK action prompt.")
		check(str(prompt.get("target_name", "")) == "Test Archivist", "Action prompts must identify their nearest target.")
		overlay.set("context_prompt", prompt)
		overlay.set("context_prompt_alpha", 1.0)
		overlay.call("fade_context_prompt", 0.05)
		var faded_prompt_value: Variant = overlay.get("context_prompt")
		var faded_prompt: Dictionary = faded_prompt_value as Dictionary if typeof(faded_prompt_value) == TYPE_DICTIONARY else {}
		check(not faded_prompt.is_empty(), "Prompt content must remain available while its fade-out is still visible.")
		check(float(overlay.get("context_prompt_alpha")) > 0.0 and float(overlay.get("context_prompt_alpha")) < 1.0, "Prompt fade-out must reduce alpha without popping immediately.")

		var map_value: Variant = runtime.get("map_data")
		var locked_map: Dictionary = (map_value as Dictionary).duplicate(true) if typeof(map_value) == TYPE_DICTIONARY else {}
		locked_map["connections"] = []
		locked_map["interactions"] = [{
			"id": "sealed_test",
			"display_name": "Sealed Test Panel",
			"position": {"x": 100, "y": 200},
			"radius": 32,
			"available_eras": [],
			"required_capabilities": ["clockglass_sight"],
			"blocked_dialogue": "The panel is hidden from ordinary sight."
		}]
		runtime.set("map_data", locked_map)
		runtime.set("runtime_entities", [])
		prompt = overlay.call("context_prompt_snapshot")
		check(str(prompt.get("action", "")) == "LOCKED", "Unmet capability gates must resolve a LOCKED prompt before interaction.")
		check(not bool(prompt.get("enabled", true)), "Locked prompts must expose their disabled state.")

		var travel: Dictionary = overlay.get("travel_distance_by_key")
		travel["test_player"] = 0.0
		overlay.set("travel_distance_by_key", travel)
		overlay.set("animation_clock", 0.0)
		var first_frame := int(overlay.call("animation_frame", player_profile, "walk", "test_player"))
		overlay.set("animation_clock", 0.5)
		var stationary_frame := int(overlay.call("animation_frame", player_profile, "walk", "test_player"))
		check(first_frame == stationary_frame, "Walk animation must not cycle while the actor remains stationary.")
		travel = overlay.get("travel_distance_by_key")
		travel["test_player"] = 20.0
		overlay.set("travel_distance_by_key", travel)
		var travelled_frame := int(overlay.call("animation_frame", player_profile, "walk", "test_player"))
		check(travelled_frame != first_frame, "Walk animation must advance from distance travelled rather than wall-clock time.")

		var previous: Dictionary = overlay.get("actor_previous_positions")
		previous["companion"] = Vector2(100, 100)
		overlay.set("actor_previous_positions", previous)
		runtime.set("companion", Vector2(120, 100))
		overlay.call("update_animation_motion", 0.1)
		var companion_direction := int(overlay.call("companion_direction_index"))
		check(overlay.call("direction_vector", companion_direction) == Vector2.RIGHT, "Morrow must preserve his own movement-facing direction.")

		runtime.set("player", Vector2(100, 200))
		runtime.set("companion", Vector2(100, 180))
		runtime.set("runtime_entities", [{
			"placement_id": "depth_test",
			"position": Vector2(100, 220),
			"active": true,
			"definition": {"kind": "prop", "appearance": {"shape": "crate"}}
		}])
		var depth_order: PackedStringArray = overlay.call("depth_order_keys")
		check(depth_order.size() == 3, "Depth sorting must include player, companion and active runtime entities.")
		if depth_order.size() == 3:
			check(depth_order[0] == "companion", "The actor with the highest ground contact must render first.")
			check(depth_order[1] == "player", "The player must render between shallower and deeper contacts.")
			check(depth_order[2] == "entity:depth_test", "The lowest world contact must render last and appear in front.")

		runtime.set("flow", 5)
		check(bool(overlay.call("animation_should_freeze")), "Paused gameplay must freeze animation time.")
		check(not bool(overlay.call("presentation_world_layers_allowed")), "Paused gameplay must not redraw world presentation above the pause panel.")
	root.remove_child(runtime)
	runtime.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Sprite animation runtime smoke test passed: profiles, grounded cadence, depth sorting, foreground occlusion, area cards, fading action prompts, environment animation, combat readability and companion facing are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
