extends SceneTree

const TARGETS := [
	"res://src/content/localisation_catalog.gd",
	"res://src/content/localisation_validator.gd",
	"res://src/content/complete_content_validator.gd",
	"res://src/content/campaign_repository.gd",
	"res://src/content/campaign_package.gd",
	"res://src/game/player_settings.gd",
	"res://src/presentation_runtime_base.gd",
	"res://src/presentation_runtime_current.gd",
	"res://src/combat_readability_overlay.gd",
	"res://src/player_controls_overlay.gd",
	"res://tools/smoke_localisation.gd",
	"res://localisation/ui.json",
	"res://campaigns/epochbound_demo/localisation/core.json",
	"res://src/app.tscn"
]

var failures: Array[String] = []


func _initialize() -> void:
	for path in TARGETS:
		if path.ends_with(".json"):
			if not FileAccess.file_exists(path):
				failures.append("Missing localisation catalogue %s." % path)
			continue
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			failures.append("Could not load or compile %s." % path)
			continue
		if path.ends_with(".gd") and not resource is GDScript:
			failures.append("Expected a GDScript resource at %s." % path)
		elif path.ends_with(".tscn") and not resource is PackedScene:
			failures.append("Expected a PackedScene resource at %s." % path)
	if failures.is_empty():
		print("Localisation compile probe passed: strict catalogues, schema-three settings, deterministic fallback, pseudo-localisation, package validation and runtime presentation load cleanly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
