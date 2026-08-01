extends SceneTree

const TARGETS := [
	"res://src/content/sprite_animation_catalog.gd",
	"res://src/content/sprite_animation_validator.gd",
	"res://src/content/sprite_animation_strict_validator.gd",
	"res://src/game/runtime_scene_contract.gd",
	"res://src/presentation_runtime_current.gd",
	"res://src/sprite_animation_overlay.gd",
	"res://src/sprite_animation_overlay_current.gd",
	"res://src/sprite_animation_polish_overlay.gd",
	"res://src/adventure_feedback_overlay.gd",
	"res://src/environment_animation_overlay.gd",
	"res://src/combat_readability_overlay.gd",
	"res://addons/epochbound_campaign_studio/campaign_studio_animation_current.gd",
	"res://addons/epochbound_sprite_animation_studio/sprite_animation_studio.gd",
	"res://addons/epochbound_sprite_animation_studio/sprite_animation_studio_current.gd",
	"res://addons/epochbound_sprite_animation_studio/plugin.gd",
	"res://tools/smoke_runtime_scene_contract.gd",
	"res://tools/smoke_sprite_animation_runtime.gd",
	"res://tools/smoke_environment_animation.gd",
	"res://tools/smoke_combat_readability_overlay.gd",
	"res://tools/smoke_sprite_animation_studio.gd",
	"res://tools/smoke_sprite_animation_validation_edges.gd",
	"res://tools/smoke_sprite_campaign_scaffold.gd",
	"res://tools/smoke_sprite_package_validation.gd",
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
		print("Sprite animation compile probe passed: canonical runtime contract, catalogues, validators, presentation-safe runtime, grounded animation, adventure feedback, animated environments, combat readability, editor, scaffolding, package safety and tests load cleanly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
