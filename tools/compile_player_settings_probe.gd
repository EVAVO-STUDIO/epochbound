extends SceneTree

const TARGETS := [
	"res://src/game/player_settings.gd",
	"res://src/game/player_settings_store.gd",
	"res://src/presentation_runtime_current.gd",
	"res://src/combat_readability_overlay.gd",
	"res://src/audio_mood_runtime.gd",
	"res://tools/smoke_player_settings.gd",
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
		print("Player settings compile probe passed: model, atomic store, runtime, presentation, Audio, smoke test and canonical scene load cleanly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
