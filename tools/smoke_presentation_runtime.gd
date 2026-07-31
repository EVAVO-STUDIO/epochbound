extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const PresentationCatalog = preload("res://src/content/presentation_catalog.gd")
const PresentationValidator = preload("res://src/content/presentation_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var validation: Dictionary = PresentationValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must pass presentation validation.")
	check(int(validation.get("presentation_profile_count", 0)) == 6, "Reference campaign must expose six presentation profiles.")
	check(int(validation.get("presentation_binding_count", 0)) == 6, "Reference campaign must bind every map and era.")
	var campaign_result: Dictionary = Repository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load for presentation testing.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog_result: Dictionary = PresentationCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(catalog_result.get("ok", false)), "Presentation catalog must load.")
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var bindings_value: Variant = catalog_result.get("bindings", [])
	var bindings: Array = bindings_value as Array if typeof(bindings_value) == TYPE_ARRAY else []
	var verdant: Dictionary = PresentationCatalog.resolved_profile(definitions, bindings, "bellweather_crossing", "verdant")
	var ashen: Dictionary = PresentationCatalog.resolved_profile(definitions, bindings, "bellweather_crossing", "ashen")
	check(str(verdant.get("id", "")) == "bellweather_verdant", "Verdant Bellweather must resolve its authored profile.")
	check(str(ashen.get("id", "")) == "bellweather_ashen", "Ashen Bellweather must resolve its authored profile.")
	check(PresentationCatalog.palette_color(verdant, "accent", "000000") != PresentationCatalog.palette_color(ashen, "accent", "000000"), "Era profiles must produce distinct accent colour treatment.")
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Presentation-aware runtime scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime: Node = (packed as PackedScene).instantiate()
	check(runtime != null, "Presentation-aware runtime scene must instantiate.")
	if runtime == null:
		finish()
		return
	root.add_child(runtime)
	await process_frame
	var audio: Node = runtime.get_node_or_null("AudioMood")
	check(audio != null, "Full runtime scene must include AudioMood.")
	if audio != null:
		check(str(audio.get_script().resource_path) == "res://src/audio_mood_runtime.gd", "Full runtime scene must use the hardened Audio adapter.")
		check(bool(audio.call("generator_players_ready")), "Full scene gate must confirm Audio generator playback readiness.")
	var camera: Node = runtime.get_node_or_null("PresentationCamera")
	check(camera is Camera2D, "Runtime scene must include the profile-driven PresentationCamera.")
	if camera != null:
		check(camera.has_method("desired_camera_offset"), "Presentation camera must expose authored deadzone and look-ahead resolution.")
	var layer: Node = runtime.get_node_or_null("PresentationLayer")
	check(layer is CanvasLayer, "Presentation HUD must be isolated in a CanvasLayer.")
	var overlay: Node = runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	check(overlay != null, "Runtime scene must include the PresentationOverlay inside its CanvasLayer.")
	if overlay != null:
		check(overlay.has_method("initialize_from_runtime"), "Presentation overlay must load campaign profiles.")
		check(overlay.has_method("draw_adventure_hud"), "Presentation overlay must provide the framed adventure HUD.")
		overlay.call("initialize_from_runtime")
		check(str(overlay.get("active_profile_id")) == "bellweather_verdant", "Runtime overlay must resolve the current map and era profile.")
	root.remove_child(runtime)
	runtime.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Presentation runtime smoke test passed: Audio readiness, profiles, camera feel, era resolution, CanvasLayer isolation and original HUD treatment are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
