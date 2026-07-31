extends SceneTree

const PresentationCatalog = preload("res://src/content/presentation_catalog.gd")
const PresentationValidator = preload("res://src/content/presentation_validator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var malformed := PresentationCatalog.default_profile()
	malformed["id"] = "Invalid Profile ID"
	var palette: Dictionary = malformed.get("palette", {})
	palette["accent"] = "NOTHEX"
	malformed["palette"] = palette
	var camera: Dictionary = malformed.get("camera", {})
	camera["deadzone"] = 900.0
	malformed["camera"] = camera
	var atmosphere: Dictionary = malformed.get("atmosphere", {})
	atmosphere["kind"] = "acid_rain"
	atmosphere["density"] = 999
	malformed["atmosphere"] = atmosphere
	var errors: Array[String] = []
	var warnings: Array[String] = []
	PresentationValidator.validate_profile_record(malformed, "synthetic", errors, warnings)
	check(errors.size() >= 5, "Malformed profiles must surface independent schema, colour, camera and atmosphere errors.")
	check(has_text(errors, "six-digit hexadecimal"), "Invalid palette colours must be rejected.")
	check(has_text(errors, "unsupported kind"), "Unknown atmosphere kinds must be rejected.")
	check(has_text(errors, "between 0.00 and 80.00"), "Unsafe camera deadzones must be rejected.")
	var definitions: Dictionary = {
		"fallback": profile_with_id("fallback", "111111"),
		"exact": profile_with_id("exact", "d47a42")
	}
	var bindings: Array = [
		{"map_id": "*", "era_id": "*", "profile_id": "fallback"},
		{"map_id": "test_map", "era_id": "ashen", "profile_id": "exact"}
	]
	var resolved := PresentationCatalog.resolved_profile(definitions, bindings, "test_map", "ashen")
	check(str(resolved.get("id", "")) == "exact", "Exact map and era bindings must outrank wildcard fallbacks.")
	check(not PresentationCatalog.safe_relative_json_path("../presentation.json"), "Presentation catalog traversal paths must be rejected.")
	finish()


func profile_with_id(profile_id: String, accent: String) -> Dictionary:
	var output := PresentationCatalog.default_profile()
	output["id"] = profile_id
	output["display_name"] = profile_id.capitalize()
	var palette: Dictionary = output.get("palette", {})
	palette["accent"] = accent
	output["palette"] = palette
	return output


func has_text(messages: Array[String], needle: String) -> bool:
	for message in messages:
		if message.contains(needle):
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Presentation validation edge smoke test passed: malformed colours, camera values, atmosphere kinds, path traversal and binding priority are controlled.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
