extends SceneTree

const TARGETS := [
	"res://src/game/hideaway_quiet_moment_model.gd",
	"res://src/content/hideaway_stewardship_validator.gd",
	"res://src/hideaway_runtime.gd",
	"res://tools/smoke_hideaway_quiet_moments.gd",
]


func _init() -> void:
	for path: String in TARGETS:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			push_error("Archive Hideaway quiet moment compile probe could not load %s." % path)
			quit(1)
			return
	print("Archive Hideaway quiet moment compile probe passed: pure availability, strict validation, live nook presentation and regressions load under Godot 4.6.2.")
	quit(0)
