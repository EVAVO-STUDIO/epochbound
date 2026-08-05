extends SceneTree

const TARGETS := [
	"res://src/content/multiplayer_catalog.gd",
	"res://src/content/multiplayer_area_validator.gd",
	"res://src/game/multiplayer_session_model.gd",
	"res://src/game/multiplayer_connection_profile.gd",
	"res://src/game/multiplayer_connection_profile_store.gd",
	"res://src/multiplayer_session.gd",
	"res://src/multiplayer_save_guard.gd",
	"res://src/multiplayer_post_tick.gd",
	"res://src/multiplayer_overlay.gd",
	"res://src/multiplayer_connection_panel.gd",
	"res://src/content/complete_content_validator.gd",
	"res://src/game/runtime_scene_contract.gd",
	"res://tools/smoke_multiplayer_session_model.gd",
	"res://tools/smoke_multiplayer_runtime.gd",
	"res://tools/smoke_multiplayer_connection_profile.gd",
	"res://tools/smoke_multiplayer_validation_edges.gd",
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
			failures.append("Expected GDScript at %s." % path)
		elif path.ends_with(".tscn") and not resource is PackedScene:
			failures.append("Expected PackedScene at %s." % path)
	if failures.is_empty():
		print("Multiplayer compile probe passed: policy, authored areas, host authority, ENet session, save isolation, player-local connection setup, overlays and regressions load cleanly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
