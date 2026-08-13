extends SceneTree

const PATHS := [
	"res://src/game/hideaway_stewardship.gd",
	"res://src/game/hideaway_memento_model.gd",
	"res://src/content/hideaway_stewardship_validator.gd",
	"res://src/content/complete_content_validator.gd",
	"res://src/hideaway_runtime.gd",
	"res://tools/smoke_hideaway_mementos.gd",
	"res://tools/smoke_hideaway_runtime.gd",
	"res://src/app.tscn",
]


func _init() -> void:
	for path: String in PATHS:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			push_error("Archive Hideaway memento compile probe failed to load %s" % path)
			quit(1)
			return
	print("Archive Hideaway memento compile probe passed: data model, strict validation, live shelf presentation, reflections and regressions load under Godot 4.6.2.")
	quit(0)
