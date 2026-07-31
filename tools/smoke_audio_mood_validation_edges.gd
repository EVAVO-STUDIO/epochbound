extends SceneTree

const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")
const AudioMoodValidator = preload("res://src/content/audio_mood_validator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var invalid: Dictionary = AudioMoodCatalog.default_profile()
	invalid["id"] = "Bad Profile"
	var music: Dictionary = invalid.get("music", {})
	music["tempo_bpm"] = 320.0
	music["waveform"] = "sampled_copy"
	music["scale"] = [0]
	music["melody_steps"] = []
	invalid["music"] = music
	var ambience: Dictionary = invalid.get("ambience", {})
	ambience["kind"] = "copyrighted_sample"
	ambience["gain"] = 2.0
	invalid["ambience"] = ambience
	var errors: Array[String] = []
	var warnings: Array[String] = []
	AudioMoodValidator.validate_profile_record(invalid, "edge", errors, warnings)
	check(errors.size() >= 6, "Malformed audio profile must produce independent validation errors.")
	check(contains_text(errors, "tempo_bpm"), "Out-of-range tempo must be rejected.")
	check(contains_text(errors, "waveform"), "Unsupported waveform must be rejected.")
	check(contains_text(errors, "ambience"), "Unsupported ambience kind and gain must be rejected.")
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
	finish()


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
		print("Audio and Mood validation edge smoke test passed: malformed synthesis, ambience and binding records are rejected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
