extends SceneTree

const LocalisationLayout = preload("res://src/content/localisation_layout.gd")

const TARGETS := [
	"res://src/content/localisation_layout.gd",
	"res://src/app.gd",
	"res://src/combat_readability_overlay.gd",
	"res://src/player_controls_overlay.gd",
	"res://src/game/runtime_scene_contract.gd",
	"res://tools/smoke_localisation_layout.gd",
	"res://src/app.tscn"
]

var failures: Array[String] = []


func _initialize() -> void:
	if not LocalisationLayout.localisation_layout_contract_ok():
		failures.append("Localisation layout utility contract is invalid.")
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
		print("Localisation layout compile probe passed: measured fitting, bounded wrapping, stable ellipsis, fixed-viewport runtime surfaces and regressions load cleanly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
