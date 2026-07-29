extends SceneTree

# Load every critical runtime, editor, validator, smoke test and resource
# entrypoint directly so CI catches failures that bulk import may only log.
const TARGETS := [
	"res://default_bus_layout.tres",
	"res://src/app.gd",
	"res://src/game_runtime.gd",
	"res://src/combat_runtime.gd",
	"res://src/combat_director_runtime.gd",
	"res://src/content/combat_director_validator.gd",
	"res://src/game/encounter_zone_model.gd",
	"res://addons/epochbound_campaign_studio/campaign_studio.gd",
	"res://addons/epochbound_campaign_studio/world_builder_studio.gd",
	"res://addons/epochbound_encounter_studio/encounter_canvas.gd",
	"res://addons/epochbound_encounter_studio/encounter_studio.gd",
	"res://addons/epochbound_encounter_studio/encounter_studio_controller.gd",
	"res://addons/epochbound_encounter_studio/plugin.gd",
	"res://addons/epochbound_combat_director/combat_director_canvas.gd",
	"res://addons/epochbound_combat_director/combat_director_studio.gd",
	"res://addons/epochbound_combat_director/plugin.gd",
	"res://tools/validate_content.gd",
	"res://tools/smoke_world_model.gd",
	"res://tools/smoke_encounters.gd",
	"res://tools/smoke_combat_director.gd",
	"res://src/app.tscn"
]

var failures: Array[String] = []


func _initialize() -> void:
	for path in TARGETS:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			failures.append("Could not load or compile %s." % path)
			continue
		if path.ends_with(".gd") and not resource is GDScript:
			failures.append("Expected a GDScript resource at %s." % path)
		elif path.ends_with(".tscn") and not resource is PackedScene:
			failures.append("Expected a PackedScene resource at %s." % path)
	if failures.is_empty():
		print("Compile probe passed: runtime, editors, validators, smoke tests and critical resources load cleanly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
