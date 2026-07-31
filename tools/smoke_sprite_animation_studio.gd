extends SceneTree

const SpriteAnimationStudio = preload("res://addons/epochbound_sprite_animation_studio/sprite_animation_studio_current.gd")
const Repository = preload("res://src/content/campaign_repository.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const CATALOG_PATH := "res://campaigns/epochbound_demo/animation/core.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var studio := SpriteAnimationStudio.new()
	root.add_child(studio)
	await process_frame
	check(studio.load_campaign_path(CAMPAIGN_PATH), "Sprite Studio must load the reference campaign.")
	check(studio.profile_count() == 6, "Sprite Studio must expose six reference profiles.")
	var direction_selector := studio.get("directions") as OptionButton
	check(direction_selector != null and direction_selector.item_count == 2, "Sprite Studio must expose only supported 1-row and 4-row direction modes.")
	var profile: Dictionary = studio.profile_by_id("morrow_field_gait")
	check(str(profile.get("fallback_style", "")) == "dog", "Sprite Studio must preserve Morrow's dog fallback identity.")
	check(int((profile.get("animations", {}) as Dictionary).get("walk", {}).get("frames", 0)) == 6, "Sprite Studio must preserve Morrow's six-frame gait.")
	var before := FileAccess.get_file_as_string(CATALOG_PATH)
	var atlas_edit := studio.get("atlas_edit") as LineEdit
	check(atlas_edit != null, "Sprite Studio must expose its atlas path field.")
	if atlas_edit != null:
		atlas_edit.text = "../outside.png"
		studio.call("save_current_profile")
	var after := FileAccess.get_file_as_string(CATALOG_PATH)
	check(before == after, "Unsafe atlas edits must be rejected before changing source content.")
	var status := studio.get("status_label") as Label
	check(status != null and status.text.contains("safe relative PNG"), "Unsafe atlas rejection must explain the valid path contract.")
	root.remove_child(studio)
	studio.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Sprite and Animation Studio smoke test passed: campaign loading, strict direction modes, profile state and safe atlas rejection are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
