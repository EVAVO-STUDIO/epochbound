extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const CampaignPackage = preload("res://src/content/campaign_package.gd")
const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")
const AudioMoodValidator = preload("res://src/content/audio_mood_strict_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

const REFERENCE_CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

const TEMP_ROOT := "user://audio_mood_validation_edges"
const TEMP_CAMPAIGN := TEMP_ROOT + "/campaign.json"
const TEMP_AUDIO := TEMP_ROOT + "/audio/core.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var invalid: Dictionary = AudioMoodCatalog.default_profile()
	invalid["id"] = "Bad Profile"
	var music: Dictionary = (invalid.get("music", {}) as Dictionary).duplicate(true)
	music["tempo_bpm"] = 320.0
	music["root_midi"] = 45.5
	music["waveform"] = "sampled_copy"
	music["scale"] = [0, 2.5, 3]
	music["melody_steps"] = []
	invalid["music"] = music
	var ambience: Dictionary = (invalid.get("ambience", {}) as Dictionary).duplicate(true)
	ambience["kind"] = "copyrighted_sample"
	ambience["gain"] = 2.0
	invalid["ambience"] = ambience
	var errors: Array[String] = []
	var warnings: Array[String] = []
	AudioMoodValidator.validate_profile_record(invalid, "edge", errors, warnings)
	check(errors.size() >= 8, "Malformed audio profile must produce independent validation errors.")
	check(contains_text(errors, "tempo_bpm"), "Out-of-range tempo must be rejected.")
	check(contains_text(errors, "waveform"), "Unsupported waveform must be rejected.")
	check(contains_text(errors, "ambience"), "Unsupported ambience kind and gain must be rejected.")
	check(contains_text(errors, "root_midi must be an integer"), "Fractional root notes must be rejected instead of truncated.")
	check(contains_text(errors, "scale[1] must be an integer"), "Fractional scale entries must be rejected instead of truncated.")
	var reference_result: Dictionary = Repository.read_json(REFERENCE_CAMPAIGN_PATH)
	var reference_campaign: Dictionary = reference_result.get("data", {})
	var object_result: Dictionary = ObjectCatalog.load_catalogs(REFERENCE_CAMPAIGN_PATH, reference_campaign)
	var object_definitions: Dictionary = object_result.get("definitions", {})
	var invalid_stem: Dictionary = {
		"boss_id": "ash_hound",
		"phase_id": "missing_phase",
		"display_name": "",
		"tempo_multiplier": 3.0,
		"root_offset": 1.5,
		"melody_steps": [0, 1.5],
		"bass_steps": [],
		"waveform": "sampled_copy",
		"pulse_width": 1.2,
		"gain": 0.9,
		"percussion_gain": 0.8
	}
	var stem_errors: Array[String] = []
	var stem_warnings: Array[String] = []
	AudioMoodValidator.validate_boss_stem_record(invalid_stem, "edge", object_definitions, stem_errors, stem_warnings)
	check(stem_errors.size() >= 8, "Malformed boss stem must fail strict validation in multiple independent fields.")
	var duplicate_stems: Dictionary = {}
	var duplicate_sources: Dictionary = {}
	var duplicate_errors: Array[String] = []
	var valid_stem: Dictionary = {
		"boss_id": "underworks_sentinel",
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
	AudioMoodCatalog.merge_boss_stem(valid_stem, "first", duplicate_stems, duplicate_sources, duplicate_errors)
	AudioMoodCatalog.merge_boss_stem(valid_stem, "second", duplicate_stems, duplicate_sources, duplicate_errors)
	check(contains_text(duplicate_errors, "also declared"), "Duplicate boss stem keys must be rejected.")
	var definitions: Dictionary = {
		"fallback": AudioMoodCatalog.default_profile(),
		"target": {
			"id": "target",
			"display_name": "Target",
			"music": AudioMoodCatalog.default_profile().get("music", {}),
			"ambience": AudioMoodCatalog.default_profile().get("ambience", {}),
			"mix": AudioMoodCatalog.default_profile().get("mix", {})
		}
	}
	var bindings: Array = [
		{"map_id": "*", "era_id": "*", "profile_id": "fallback"},
		{"map_id": "clockwood_edge", "era_id": "ashen", "profile_id": "target"}
	]
	var resolved: Dictionary = AudioMoodCatalog.resolved_profile(definitions, bindings, "clockwood_edge", "ashen")
	check(str(resolved.get("id", "")) == "target", "Specific audio bindings must outrank wildcard bindings.")
	test_unknown_title_profile()
	CampaignPackage.remove_tree(TEMP_ROOT)
	finish()


func test_unknown_title_profile() -> void:
	CampaignPackage.remove_tree(TEMP_ROOT)
	var catalog: Dictionary = AudioMoodCatalog.default_catalog()
	catalog["title_profile_id"] = "missing_title_profile"
	check(bool(Repository.save_json(TEMP_AUDIO, catalog).get("ok", false)), "Temporary Audio catalogue must save.")
	check(bool(Repository.save_json(TEMP_CAMPAIGN, {
		"schema_version": 1,
		"id": "audio_edge",
		"audio_files": ["audio/core.json"]
	}).get("ok", false)), "Temporary campaign manifest must save.")
	var report: Dictionary = AudioMoodValidator.validate_audio_integrity_only(TEMP_CAMPAIGN)
	check(not bool(report.get("ok", false)), "Unknown authored title profile must fail strict Audio validation.")
	check(contains_text_variant(report.get("errors", []), "title_profile_id references unknown"), "Unknown title-profile rejection must be explicit.")


func contains_text(messages: Array[String], fragment: String) -> bool:
	for message in messages:
		if message.contains(fragment):
			return true
	return false


func contains_text_variant(value: Variant, fragment: String) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for message in value as Array:
		if str(message).contains(fragment):
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Audio and Mood validation edge smoke test passed: malformed synthesis, fractional patterns, boss stems, title profiles and bindings are rejected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
