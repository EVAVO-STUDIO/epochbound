extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")
const AudioMoodValidator = preload("res://src/content/audio_mood_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"

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
	await process_frame
	var controller: Node = runtime.get_node_or_null("AudioMood")
	check(controller != null, "Runtime scene must include AudioMood.")
	if controller != null:
		check(controller.get_node_or_null("Music") is AudioStreamPlayer, "AudioMood must create a Music generator player.")
		check(controller.get_node_or_null("Ambience") is AudioStreamPlayer, "AudioMood must create an Ambience generator player.")
		check(controller.get_node_or_null("SFX") is AudioStreamPlayer, "AudioMood must create an SFX generator player.")
		controller.call("queue_sound", "shift")
		check(int(controller.call("queued_sfx_count")) >= 3, "Era-shift feedback must queue a three-voice original stinger.")
		runtime.set("flow", 4)
		controller.call("resolve_active_profile", true)
		check(str(controller.get("active_profile_id")) == "bellweather_verdant", "Gameplay must resolve the current map and era audio profile.")
	root.remove_child(runtime)
	runtime.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Audio and Mood runtime smoke test passed: profiles, generator players, stingers and map/era resolution are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
