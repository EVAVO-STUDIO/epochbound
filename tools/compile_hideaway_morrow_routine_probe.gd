extends SceneTree

const TARGETS := [
	"res://src/game/hideaway_morrow_routine_model.gd",
	"res://src/content/hideaway_stewardship_validator.gd",
	"res://src/hideaway_runtime.gd",
	"res://tools/smoke_hideaway_morrow_routines.gd",
]


func _init() -> void:
	for path: String in TARGETS:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			push_error("Archive Hideaway Morrow routine compile probe could not load %s." % path)
			quit(1)
			return
	print("Archive Hideaway Morrow routine compile probe passed: read-only availability, stable active-play cycling, player-command authority and regressions load under Godot 4.6.2.")
	quit(0)
