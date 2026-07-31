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
	var overlay: Node = runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	check(overlay != null, "Runtime scene must include the Sprite Animation overlay.")
	if overlay != null:
		check(str(overlay.get_script().resource_path) == "res://src/sprite_animation_overlay_current.gd", "Runtime must bind the current Sprite Animation adapter.")
		check(bool(overlay.call("sprite_runtime_contract_ok")), "Runtime overlay must use nearest filtering and loaded animation data.")
		check(int(overlay.call("animation_profile_count")) == 6, "Runtime overlay must load all reference animation profiles.")
		check(int(overlay.call("animation_binding_count")) == 6, "Runtime overlay must load all reference animation bindings.")
		overlay.set("animation_clock", 0.0)
		var first_frame := int(overlay.call("animation_frame", player_profile, "walk", "test_player"))
		overlay.set("animation_clock", 0.25)
		var later_frame := int(overlay.call("animation_frame", player_profile, "walk", "test_player"))
		check(first_frame != later_frame, "Walk animation frame selection must advance deterministically with animation time.")
		var previous: Dictionary = overlay.get("actor_previous_positions")
		previous["companion"] = Vector2(100, 100)
		overlay.set("actor_previous_positions", previous)
		runtime.set("companion", Vector2(120, 100))
		overlay.call("update_animation_motion", 0.1)
		var companion_direction := int(overlay.call("companion_direction_index"))
		check(overlay.call("direction_vector", companion_direction) == Vector2.RIGHT, "Morrow must preserve his own movement-facing direction.")
	root.remove_child(runtime)
	runtime.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Sprite animation runtime smoke test passed: profiles, bindings, frame timing, scene wiring and companion facing are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
