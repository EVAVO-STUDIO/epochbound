extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")
const Repository = preload("res://src/content/campaign_repository.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")
const AudioMoodValidator = preload("res://src/content/audio_mood_strict_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"
const BOSS_ID := "underworks_sentinel"
const BOSS_PLACEMENT := "underworks_sentinel"
const STARTUP_FRAME_BUDGET := 10

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var validation: Dictionary = AudioMoodValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must pass strict Boss Music Stem validation.")
	check(int(validation.get("boss_stem_count", 0)) == 3, "Reference campaign must expose three boss phase music stems.")

	var campaign_result: Dictionary = Repository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load for boss-stem testing.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog_result: Dictionary = AudioMoodCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(catalog_result.get("ok", false)), "Reference Audio catalogue must load with boss stems.")
	var stems_value: Variant = catalog_result.get("boss_stems", {})
	var stems: Dictionary = stems_value as Dictionary if typeof(stems_value) == TYPE_DICTIONARY else {}
	check(stems.size() == 3, "Reference Audio catalogue must index exactly three boss stems.")
	check(stems.has("underworks_sentinel|catalogue_measure"), "Catalogue Measure stem must be indexed by stable boss and phase IDs.")
	check(stems.has("underworks_sentinel|cinder_measure"), "Cinder Measure stem must be indexed by stable boss and phase IDs.")
	check(stems.has("underworks_sentinel|last_accession"), "Last Accession stem must be indexed by stable boss and phase IDs.")

	var object_result: Dictionary = ObjectCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(object_result.get("ok", false)), "Reference object catalogue must load for stem validation edges.")
	var definitions_value: Variant = object_result.get("definitions", {})
	var definitions: Dictionary = definitions_value as Dictionary if typeof(definitions_value) == TYPE_DICTIONARY else {}
	probe_validation_edges(definitions)

	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Boss Music Stem runtime scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime: Node = (packed as PackedScene).instantiate()
	root.add_child(runtime)
	var controller: Node = runtime.get_node_or_null("AudioMood")
	check(controller != null, "Canonical runtime must include the AudioMood controller.")
	if controller == null:
		await HeadlessRuntimeCleanup.release(self, runtime)
		finish()
		return
	for _frame_index in range(STARTUP_FRAME_BUDGET):
		if controller.has_method("generator_startup_complete") and bool(controller.call("generator_startup_complete")):
			break
		await process_frame
	check(bool(controller.call("generator_startup_complete")), "Audio generators must complete bounded startup before boss-stem resolution.")

	check(bool(runtime.call("activate_map", "museum_underworks", "from_bellweather", "verdant", false)), "Museum Underworks must activate for boss-stem testing.")
	runtime.call("change_flow", 4)
	runtime.set("player", Vector2(320, 224))
	runtime.set("companion", Vector2(294, 238))
	runtime.call("update_boss_engagements")
	if runtime.has_method("finish_cinematic") and not str(runtime.get("active_cinematic_id")).is_empty():
		runtime.call("finish_cinematic", true)
	controller.call("resolve_active_profile", true)
	controller.call("resolve_active_boss_stem", true)
	var snapshot: Dictionary = controller.call("boss_stem_snapshot")
	check(str(snapshot.get("key", "")) == "underworks_sentinel|catalogue_measure", "Verdant engagement must resolve Catalogue Measure music.")
	check(str(snapshot.get("boss_id", "")) == BOSS_ID, "Resolved stem must retain its stable boss ID.")
	check(str(snapshot.get("phase_id", "")) == "catalogue_measure", "Resolved stem must retain its current phase ID.")
	check(int(snapshot.get("melody_step_count", 0)) >= 4, "Resolved stem must expose a bounded melody sequence.")

	controller.set("boss_stem_sample_clock", 91)
	runtime.call("shift_to_next_era")
	controller.call("resolve_active_profile", false)
	controller.call("resolve_active_boss_stem", false)
	snapshot = controller.call("boss_stem_snapshot")
	check(str(snapshot.get("key", "")) == "underworks_sentinel|cinder_measure", "Ashen era shift must resolve Cinder Measure music.")
	check(int(snapshot.get("sample_clock", -1)) == 0, "Changing phase stems must reset only the phase-stem sample clock.")
	check(str(controller.get("active_profile_id")) == "underworks_ashen", "Boss stem changes must preserve normal map-and-era Audio profile resolution.")

	var entities: Array = array_property(runtime, "runtime_entities")
	var boss_index := entity_index(entities, BOSS_PLACEMENT)
	check(boss_index >= 0, "Reference boss placement must resolve for final-phase music testing.")
	if boss_index >= 0:
		controller.set("boss_stem_sample_clock", 47)
		runtime.call("damage_entity", boss_index, 999, "ELI")
		controller.call("resolve_active_boss_stem", false)
		snapshot = controller.call("boss_stem_snapshot")
		check(str(snapshot.get("key", "")) == "underworks_sentinel|last_accession", "Health-threshold transition must resolve Last Accession music.")
		check(int(snapshot.get("sample_clock", -1)) == 0, "Last Accession must begin from a deterministic stem clock.")
		check(float(snapshot.get("tempo_multiplier", 0.0)) > 1.0, "Final-phase music must author a faster rhythmic pressure than the base theme.")

	var engaged_value: Variant = runtime.get("engaged_bosses")
	var engaged: Dictionary = engaged_value as Dictionary if typeof(engaged_value) == TYPE_DICTIONARY else {}
	engaged.clear()
	runtime.set("engaged_bosses", engaged)
	controller.call("resolve_active_boss_stem", false)
	snapshot = controller.call("boss_stem_snapshot")
	check(str(snapshot.get("key", "")) == "", "Boss disengagement must clear the transient phase stem.")
	check((snapshot.get("stem", {}) as Dictionary).is_empty(), "Boss disengagement must leave no stale stem definition active.")

	await HeadlessRuntimeCleanup.release(self, runtime)
	finish()


func probe_validation_edges(object_definitions: Dictionary) -> void:
	var invalid: Dictionary = {
		"boss_id": "ash_hound",
		"phase_id": "missing_phase",
		"display_name": "",
		"tempo_multiplier": 3.0,
		"root_offset": 2.5,
		"melody_steps": [0, 1.5],
		"bass_steps": [],
		"waveform": "sampled_copy",
		"pulse_width": 1.5,
		"gain": 0.9,
		"percussion_gain": 0.8
	}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	AudioMoodValidator.validate_boss_stem_record(invalid, "edge", object_definitions, errors, warnings)
	check(errors.size() >= 8, "Malformed boss stem must produce independent validation errors.")
	check(contains_text(errors, "enabled boss"), "Non-boss object references must be rejected.")
	check(contains_text(errors, "phase"), "Unknown boss phases must be rejected.")
	check(contains_text(errors, "root_offset must be an integer"), "Fractional stem transposition must be rejected.")
	check(contains_text(errors, "melody_steps[1] must be an integer"), "Fractional stem sequence entries must be rejected.")

	var definitions: Dictionary = {}
	var sources: Dictionary = {}
	var duplicate_errors: Array[String] = []
	var valid: Dictionary = {
		"boss_id": BOSS_ID,
		"phase_id": "catalogue_measure",
		"display_name": "Catalogue Pulse",
		"tempo_multiplier": 1.0,
		"root_offset": 12,
		"melody_steps": [0, -99, 2, -99],
		"bass_steps": [0, -99, -99, -99],
		"waveform": "triangle",
		"pulse_width": 0.4,
		"gain": 0.1,
		"percussion_gain": 0.03
	}
	AudioMoodCatalog.merge_boss_stem(valid, "first", definitions, sources, duplicate_errors)
	AudioMoodCatalog.merge_boss_stem(valid, "second", definitions, sources, duplicate_errors)
	check(contains_text(duplicate_errors, "also declared"), "Duplicate boss and phase stem keys must fail deterministically.")


func array_property(object: Object, property_name: String) -> Array:
	var value: Variant = object.get(property_name)
	return value as Array if typeof(value) == TYPE_ARRAY else []


func entity_index(entities: Array, placement_id: String) -> int:
	for index in range(entities.size()):
		if typeof(entities[index]) == TYPE_DICTIONARY and str((entities[index] as Dictionary).get("placement_id", "")) == placement_id:
			return index
	return -1


func contains_text(messages: Array[String], fragment: String) -> bool:
	for message in messages:
		if message.contains(fragment):
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Boss Music Stem smoke test passed: strict catalogue references, deterministic phase selection, clock resets, era continuity, final-phase escalation and disengagement are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
