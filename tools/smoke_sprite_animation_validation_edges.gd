extends SceneTree

const SpriteAnimationCatalog = preload("res://src/content/sprite_animation_catalog.gd")
const SpriteAnimationValidator = preload("res://src/content/sprite_animation_validator.gd")
const SpriteAnimationStrictValidator = preload("res://src/content/sprite_animation_strict_validator.gd")

const ROOT := "user://sprite_animation_validation_edges"
const ATLAS_PATH := ROOT + "/tiny.png"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	check(image.save_png(ATLAS_PATH) == OK, "Synthetic atlas fixture must save.")
	var invalid := SpriteAnimationCatalog.default_profile()
	invalid["id"] = "Bad Profile"
	invalid["atlas"] = "tiny.png"
	invalid["frame_size"] = {"x": 32, "y": 40}
	invalid["render_size"] = {"x": 180, "y": 40}
	invalid["pivot"] = {"x": 60, "y": 60}
	invalid["directions"] = 8
	var animations: Dictionary = invalid.get("animations", {})
	var walk: Dictionary = animations.get("walk", {})
	walk["frames"] = 0
	walk["fps"] = 80.0
	animations["walk"] = walk
	invalid["animations"] = animations
	var errors: Array[String] = []
	var warnings: Array[String] = []
	SpriteAnimationValidator.validate_profile_record(invalid, "edge", ROOT, errors, warnings)
	SpriteAnimationStrictValidator.validate_profile_integrity(invalid, "edge", errors, warnings)
	check(errors.size() >= 7, "Malformed sprite profile must produce independent validation errors.")
	check(contains_text(errors, "profile id"), "Invalid profile identifiers must be rejected.")
	check(contains_text(errors, "atlas"), "Undersized atlas data must be rejected.")
	check(contains_text(errors, "frames"), "Non-positive animation frame counts must be rejected.")
	check(contains_text(errors, "fps"), "Unsafe animation rates must be rejected.")
	check(contains_text(errors, "1 or 4 directional"), "Unsupported eight-direction records must be rejected until the runtime implements them.")
	check(contains_text(errors, "pivot"), "Pivots outside source frames must be rejected.")
	check(contains_text(errors, "render_size"), "Oversized runtime render dimensions must be rejected.")
	check(not SpriteAnimationCatalog.safe_relative_atlas_path("../outside.png"), "Traversal atlas paths must be rejected.")
	check(not SpriteAnimationCatalog.safe_relative_atlas_path("sprites/hero.webp"), "Only PNG sprite atlases are accepted by the frame contract.")
	check(SpriteAnimationCatalog.safe_relative_atlas_path("sprites/hero.png"), "Safe relative PNG atlas paths must be accepted.")
	DirAccess.remove_absolute(ATLAS_PATH)
	DirAccess.remove_absolute(ROOT)
	finish()


func contains_text(messages: Array[String], fragment: String) -> bool:
	for message in messages:
		if message.contains(fragment):
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Sprite animation validation edge smoke test passed: malformed identifiers, atlases, frame timing, direction counts, pivots and paths are rejected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
