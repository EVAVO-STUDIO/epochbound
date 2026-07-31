extends "res://src/presentation_overlay.gd"

const Catalog = preload("res://src/content/presentation_catalog.gd")
const PresentationValidator = preload("res://src/content/presentation_validator.gd")
const CAMERA_VIEW := Vector2(640, 360)
const GAME_FLOW := 4
const PAUSED_FLOW := 5


func runtime_root() -> Node:
	var layer := get_parent()
	return layer.get_parent() if layer != null else null


func initialize_from_runtime() -> void:
	super.initialize_from_runtime()
	var runtime := runtime_root()
	if runtime == null:
		return
	var campaign_path := str(runtime.get("campaign_path"))
	if campaign_path.is_empty():
		return
	var validation: Dictionary = PresentationValidator.validate_presentation_only(campaign_path)
	if bool(validation.get("ok", false)):
		return
	presentation_definitions = {
		Catalog.DEFAULT_PROFILE_ID: Catalog.default_profile()
	}
	presentation_bindings.clear()
	loaded_profile_key = ""
	resolve_active_profile(true)


func runtime_camera_offset() -> Vector2:
	var immediate_offset := super.runtime_camera_offset()
	var runtime := runtime_root()
	if runtime == null:
		return immediate_offset
	var camera := runtime.get_node_or_null("PresentationCamera") as Camera2D
	if camera == null:
		return immediate_offset
	return immediate_offset + camera.position - CAMERA_VIEW * 0.5


func apply_root_shake() -> void:
	var runtime := runtime_root()
	if runtime == null:
		return
	if runtime is Node2D:
		(runtime as Node2D).position = Vector2.ZERO
	var camera := runtime.get_node_or_null("PresentationCamera") as Camera2D
	if camera == null:
		return
	if shake_timer <= 0.0 or not [GAME_FLOW, PAUSED_FLOW].has(runtime_flow()) or not active_cinematic_id().is_empty():
		return
	var time := Time.get_ticks_msec() * 0.001
	var shake := Vector2(
		roundf(sin(time * 67.0) * shake_strength),
		roundf(cos(time * 53.0) * shake_strength * 0.65)
	)
	camera.position += shake


func draw_player_sprite(position: Vector2) -> void:
	var ink := profile_color("ink", "13161a")
	# Hard masks prevent the original marker from showing around the replacement silhouette.
	draw_rect(Rect2(position + Vector2(-8, -23), Vector2(16, 16)), ink)
	draw_rect(Rect2(position + Vector2(-10, -11), Vector2(20, 21)), ink)
	draw_rect(Rect2(position + Vector2(-9, 7), Vector2(8, 10)), ink)
	draw_rect(Rect2(position + Vector2(1, 7), Vector2(8, 10)), ink)
	super.draw_player_sprite(position)


func draw_companion_sprite(position: Vector2) -> void:
	var ink := profile_color("ink", "13161a")
	draw_rect(Rect2(position + Vector2(-12, -10), Vector2(21, 18)), ink)
	draw_rect(Rect2(position + Vector2(4, -15), Vector2(12, 15)), ink)
	super.draw_companion_sprite(position)


func draw_corner_brackets(rect: Rect2, color: Color) -> void:
	var length := 18.0
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.end.y),
		rect.end
	]
	for corner: Vector2 in corners:
		var horizontal_direction := 1.0 if is_equal_approx(corner.x, rect.position.x) else -1.0
		var vertical_direction := 1.0 if is_equal_approx(corner.y, rect.position.y) else -1.0
		draw_line(corner, corner + Vector2(length * horizontal_direction, 0), Color(color, 0.72), 2.0)
		draw_line(corner, corner + Vector2(0, length * vertical_direction), Color(color, 0.72), 2.0)
