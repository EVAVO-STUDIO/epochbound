extends SceneTree

# Load every critical runtime, editor, validator, smoke test and resource
# entrypoint directly so CI catches failures that bulk import may only log.
const TARGETS := [
	"res://default_bus_layout.tres",
	"res://src/app.gd",
	"res://src/game_runtime.gd",
	"res://src/combat_runtime.gd",
	"res://src/combat_director_runtime.gd",
	"res://src/companion_runtime.gd",
	"res://src/inventory_runtime.gd",
	"res://src/story_runtime.gd",
	"res://src/save_runtime.gd",
	"res://src/equipment_runtime.gd",
	"res://src/merchant_runtime.gd",
	"res://src/arsenal_runtime.gd",
	"res://src/content/combat_director_validator.gd",
	"res://src/content/companion_validator.gd",
	"res://src/content/item_catalog.gd",
	"res://src/content/item_validator.gd",
	"res://src/content/story_catalog.gd",
	"res://src/content/story_validator.gd",
	"res://src/content/save_profile.gd",
	"res://src/content/save_profile_store.gd",
	"res://src/content/save_validator.gd",
	"res://src/content/equipment_catalog.gd",
	"res://src/content/equipment_validator.gd",
	"res://src/content/economy_catalog.gd",
	"res://src/content/economy_validator.gd",
	"res://src/content/arsenal_catalog.gd",
	"res://src/content/arsenal_validator.gd",
	"res://src/game/encounter_zone_model.gd",
	"res://src/game/companion_model.gd",
	"res://src/game/inventory_model.gd",
	"res://src/game/story_model.gd",
	"res://src/game/equipment_model.gd",
	"res://src/game/economy_model.gd",
	"res://src/game/projectile_model.gd",
	"res://addons/epochbound_campaign_studio/campaign_studio.gd",
	"res://addons/epochbound_campaign_studio/world_builder_studio.gd",
	"res://addons/epochbound_encounter_studio/encounter_canvas.gd",
	"res://addons/epochbound_encounter_studio/encounter_studio.gd",
	"res://addons/epochbound_encounter_studio/encounter_studio_controller.gd",
	"res://addons/epochbound_encounter_studio/plugin.gd",
	"res://addons/epochbound_combat_director/combat_director_canvas.gd",
	"res://addons/epochbound_combat_director/combat_director_studio.gd",
	"res://addons/epochbound_combat_director/plugin.gd",
	"res://addons/epochbound_companion_studio/companion_canvas.gd",
	"res://addons/epochbound_companion_studio/companion_studio.gd",
	"res://addons/epochbound_companion_studio/plugin.gd",
	"res://addons/epochbound_item_forge/item_forge_studio.gd",
	"res://addons/epochbound_item_forge/plugin.gd",
	"res://addons/epochbound_story_studio/story_studio.gd",
	"res://addons/epochbound_story_studio/plugin.gd",
	"res://addons/epochbound_save_state_studio/save_state_studio.gd",
	"res://addons/epochbound_save_state_studio/plugin.gd",
	"res://addons/epochbound_loadout_studio/loadout_studio.gd",
	"res://addons/epochbound_loadout_studio/plugin.gd",
	"res://addons/epochbound_trade_studio/trade_studio.gd",
	"res://addons/epochbound_trade_studio/plugin.gd",
	"res://addons/epochbound_arsenal_studio/arsenal_studio.gd",
	"res://addons/epochbound_arsenal_studio/plugin.gd",
	"res://tools/validate_content.gd",
	"res://tools/smoke_world_model.gd",
	"res://tools/smoke_encounters.gd",
	"res://tools/smoke_combat_director.gd",
	"res://tools/smoke_companion_director.gd",
	"res://tools/smoke_item_forge.gd",
	"res://tools/smoke_item_forge_editor.gd",
	"res://tools/smoke_item_validation_edges.gd",
	"res://tools/smoke_story_studio.gd",
	"res://tools/smoke_story_studio_editor.gd",
	"res://tools/smoke_story_validation_edges.gd",
	"res://tools/smoke_save_profiles.gd",
	"res://tools/smoke_save_migrations.gd",
	"res://tools/smoke_save_state_studio.gd",
	"res://tools/smoke_loadout_runtime.gd",
	"res://tools/smoke_loadout_studio.gd",
	"res://tools/smoke_equipment_validation_edges.gd",
	"res://tools/smoke_economy_runtime.gd",
	"res://tools/smoke_trade_studio.gd",
	"res://tools/smoke_economy_validation_edges.gd",
	"res://tools/smoke_arsenal_runtime.gd",
	"res://tools/smoke_arsenal_studio.gd",
	"res://tools/smoke_arsenal_validation_edges.gd",
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
		print("Compile probe passed: runtime, all ten editors, validators, smoke tests and critical resources load cleanly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
