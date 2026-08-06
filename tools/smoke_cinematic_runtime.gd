extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")

const CinematicValidator = preload("res://src/content/cinematic_validator.gd")
const CinematicCatalog = preload("res://src/content/cinematic_catalog.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var validation := CinematicValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must pass cinematic validation.")
	check(int(validation.get("cinematic_count", 0)) == 3, "Reference campaign must expose three cinematic sequences.")
	check(int(validation.get("cinematic_step_count", 0)) == 16, "Reference cinematics must expose sixteen authored steps.")
	check(int(validation.get("cinematic_trigger_count", 0)) >= 1, "Reference campaign must expose at least its opening cinematic trigger.")

	var scene_resource := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(scene_resource is PackedScene, "Cinematic-aware runtime scene must load.")
	if not scene_resource is PackedScene:
		finish()
		return
	var runtime := (scene_resource as PackedScene).instantiate()
	check(runtime != null, "Cinematic-aware runtime scene must instantiate.")
	if runtime == null:
		finish()
		return
	var script_value: Variant = runtime.get_script()
	check(script_value is GDScript, "Runtime root must retain its GDScript.")
	if script_value is GDScript:
		check(str((script_value as GDScript).resource_path) == "res://src/presentation_runtime_current.gd", "Runtime scene must bind the presentation-safe cinematic runtime adapter.")
	root.add_child(runtime)
	check(runtime.has_method("start_cinematic"), "Runtime must expose cinematic playback.")
	check(runtime.has_method("finish_cinematic"), "Runtime must expose deterministic completion and skipping.")
	check(runtime.has_method("advance_cinematic_step"), "Runtime must expose timeline advancement.")
	check(runtime.has_method("presentation_overlay_handles_combat_readability"), "Runtime must expose presentation-owned combat rendering suppression.")

	var definitions := dictionary_property(runtime, "cinematic_definitions")
	check(definitions.size() == 3, "Runtime must load all three cinematic definitions.")
	check(CinematicCatalog.steps(CinematicCatalog.cinematic(definitions, "storm_door_opening")).size() == 7, "Opening sequence must retain seven steps.")

	runtime.call("change_flow", 4)
	check(bool(runtime.call("start_cinematic", "storm_door_opening")), "Opening sequence must start on its authored map and era.")
	check(str(runtime.get("active_cinematic_id")) == "storm_door_opening", "Opening sequence must become active.")
	check(not bool(runtime.call("can_open_save_overlay")), "Saving must remain blocked during cinematic playback.")
	check(str(runtime.get("cinematic_step").get("type", "")) == "fade", "Opening sequence must begin with its authored fade.")

	runtime.call("advance_cinematic_step")
	check(str(runtime.get("cinematic_step").get("type", "")) == "camera", "Timeline must advance to the authored camera step.")
	runtime.call("update_cinematic", 0.4)
	check(bool(runtime.get("cinematic_camera_enabled")), "Camera steps must enable cinematic framing.")
	runtime.call("advance_cinematic_step")
	check(str(runtime.get("cinematic_text")).contains("museum door"), "Dialogue steps must resolve authored text.")

	var state_before := dictionary_property(runtime, "session_state")
	check(not state_before.has("cinematic:storm_door_opening"), "Completion state must not be written before the sequence resolves.")
	runtime.call("finish_cinematic", true)
	var state_after := dictionary_property(runtime, "session_state")
	check(state_after.get("cinematic:storm_door_opening") == "skipped", "Skipping must publish the same durable completion key.")
	check(str(runtime.get("active_cinematic_id")).is_empty(), "Skipping must return control to gameplay.")
	check(bool(runtime.call("can_open_save_overlay")), "Saving must become available after cinematic completion.")
	check(not bool(runtime.call("start_cinematic", "storm_door_opening")), "A trigger-once sequence must not replay after skipping.")

	check(bool(runtime.call("activate_map", "museum_underworks", "from_bellweather", "ashen", false)), "Museum Underworks must activate for boss cinematic testing.")
	runtime.call("change_flow", 4)
	check(bool(runtime.call("start_cinematic", "underworks_sentinel_intro", true)), "Boss introduction must start when forced by the boss hook.")
	check(str(runtime.get("active_cinematic_id")) == "underworks_sentinel_intro", "Boss introduction must become active.")
	runtime.call("finish_cinematic", true)
	check(str(runtime.get("active_cinematic_id")).is_empty(), "Skipping the boss introduction must resume the arena.")

	check(bool(runtime.call("start_cinematic", "underworks_sentinel_defeat", true)), "Boss defeat sequence must start after durable completion.")
	runtime.call("finish_cinematic", false)
	var final_state := dictionary_property(runtime, "session_state")
	check(final_state.get("underworks:cinematic:archive_released") == true, "Watching the defeat sequence must apply its authored world-state effect.")
	check(final_state.get("cinematic:underworks_sentinel_defeat") == "completed", "Defeat sequence must publish its durable completion state.")
	var fingerprint := str(runtime.call("durable_progress_fingerprint"))
	check(fingerprint.contains("underworks:cinematic:archive_released"), "Cinematic completion must participate in the durable autosave fingerprint.")

	await HeadlessRuntimeCleanup.release(self, runtime)
	finish()


func dictionary_property(object: Object, property_name: String) -> Dictionary:
	var value: Variant = object.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func finish() -> void:
	if failures.is_empty():
		print("Cinematic runtime smoke test passed: loading, playback, presentation-safe combat suppression, camera, dialogue, skip equivalence and durable completion are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
