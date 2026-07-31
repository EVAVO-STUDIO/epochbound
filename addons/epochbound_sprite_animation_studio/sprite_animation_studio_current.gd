@tool
extends "res://addons/epochbound_sprite_animation_studio/sprite_animation_studio.gd"

const CurrentRepository = preload("res://src/content/campaign_repository.gd")
const CurrentCatalog = preload("res://src/content/sprite_animation_catalog.gd")
const CurrentValidator = preload("res://src/content/sprite_animation_strict_validator.gd")


func _ready() -> void:
	super._ready()
	for index in range(directions.item_count - 1, -1, -1):
		if str(directions.get_item_metadata(index)) == "8":
			directions.remove_item(index)


func save_current_profile() -> void:
	if current_catalog.is_empty() or profile_selector.selected < 0 or profile_selector.selected >= profile_ids.size():
		status_label.text = "Select a valid profile first."
		return
	var profile_id := profile_ids[profile_selector.selected]
	var profile := profile_by_id(profile_id)
	if profile.is_empty():
		status_label.text = "The selected profile no longer exists."
		return
	var atlas := atlas_edit.text.strip_edges().replace("\\", "/")
	if not CurrentCatalog.safe_relative_atlas_path(atlas):
		status_label.text = "Atlas must be empty or a safe relative PNG path."
		return
	var snapshot := read_text(current_catalog_path)
	profile["atlas"] = atlas
	profile["frame_size"] = {"x": int(frame_width.value), "y": int(frame_height.value)}
	profile["render_size"] = {"x": int(render_width.value), "y": int(render_height.value)}
	profile["pivot"] = {"x": int(pivot_x.value), "y": int(pivot_y.value)}
	profile["directions"] = int(str(directions.get_item_metadata(directions.selected)))
	profile["fallback_style"] = str(fallback_style.get_item_metadata(fallback_style.selected))
	var animations: Dictionary = {}
	for state in CurrentCatalog.STATES:
		animations[state] = {
			"row": int((state_rows[state] as SpinBox).value),
			"frames": int((state_frames[state] as SpinBox).value),
			"fps": (state_fps[state] as SpinBox).value,
			"loop": (state_loop[state] as CheckBox).button_pressed
		}
	profile["animations"] = animations
	var save_result := CurrentRepository.save_json(current_catalog_path, current_catalog)
	if not bool(save_result.get("ok", false)):
		status_label.text = "Could not write the animation catalogue."
		return
	var validation := CurrentValidator.validate_campaign_path(current_campaign_path)
	if not bool(validation.get("ok", false)):
		write_text(current_catalog_path, snapshot)
		load_catalog()
		status_label.text = "Animation save rolled back: %s" % join_messages(validation.get("errors", []))
		return
	status_label.text = "Saved %s with %d warning(s)." % [profile_id, message_count(validation.get("warnings", []))]


func validate_campaign() -> void:
	if current_campaign_path.is_empty():
		return
	var validation := CurrentValidator.validate_campaign_path(current_campaign_path)
	if bool(validation.get("ok", false)):
		status_label.text = "Animation validation passed with %d profile(s), %d binding(s), and %d warning(s)." % [int(validation.get("animation_profile_count", 0)), int(validation.get("animation_binding_count", 0)), message_count(validation.get("warnings", []))]
	else:
		status_label.text = "Animation validation failed: %s" % join_messages(validation.get("errors", []))
