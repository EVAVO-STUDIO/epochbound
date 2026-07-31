extends SceneTree

const PresentationStudio = preload("res://addons/epochbound_presentation_studio/presentation_studio.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var studio := PresentationStudio.new()
	root.add_child(studio)
	check(not str(studio.get("current_campaign_path")).is_empty(), "Presentation Studio must discover a campaign.")
	var profile_ids_value: Variant = studio.get("profile_ids")
	check(profile_ids_value is PackedStringArray, "Presentation Studio must expose deterministic profile IDs.")
	if profile_ids_value is PackedStringArray:
		check((profile_ids_value as PackedStringArray).size() == 6, "Reference Presentation Studio must load six profiles.")
	var profile: Dictionary = studio.call("profile_by_id", "clockwood_ashen")
	check(str(profile.get("display_name", "")) == "Clockwood Ashen", "Presentation Studio must preserve authored profile names.")
	var palette_value: Variant = profile.get("palette", {})
	check(typeof(palette_value) == TYPE_DICTIONARY and str((palette_value as Dictionary).get("accent", "")) == "dc7541", "Presentation Studio must preserve source-controlled palette values.")
	var catalog_value: Variant = studio.get("current_catalog")
	check(typeof(catalog_value) == TYPE_DICTIONARY, "Presentation Studio must retain its editable catalog state.")
	root.remove_child(studio)
	studio.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Presentation Studio smoke test passed: campaign discovery, profile ordering and editable palette state are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
