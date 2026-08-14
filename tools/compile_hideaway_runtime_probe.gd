extends SceneTree

const PATHS := [
	"res://src/game/hideaway_stewardship.gd",
	"res://src/game/hideaway_memento_model.gd",
	"res://src/game/hideaway_quiet_moment_model.gd",
	"res://src/game/hideaway_morrow_routine_model.gd",
	"res://src/content/hideaway_stewardship_validator.gd",
	"res://src/hideaway_runtime.gd",
	"res://tools/smoke_hideaway_stewardship.gd",
	"res://tools/compile_hideaway_memento_probe.gd",
	"res://tools/compile_hideaway_quiet_moment_probe.gd",
	"res://tools/compile_hideaway_morrow_routine_probe.gd",
	"res://tools/smoke_hideaway_mementos.gd",
	"res://tools/smoke_hideaway_quiet_moments.gd",
	"res://tools/smoke_hideaway_morrow_routines.gd",
	"res://tools/smoke_hideaway_runtime.gd",
	"res://src/app.tscn",
]


func _init() -> void:
	for path in PATHS:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			push_error("Archive Hideaway runtime compile probe failed to load %s" % path)
			quit(1)
			return
	print("Archive Hideaway runtime compile probe passed: stewardship, derived mementos, optional quiet moments, living Morrow refuge routines, live root bridge, save semantics, map and dedicated regressions load under Godot 4.6.2.")
	quit(0)
