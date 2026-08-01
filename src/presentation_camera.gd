extends Camera2D

const PresentationCatalog = preload("res://src/content/presentation_catalog.gd")

const VIEW := Vector2(640, 360)
const FLOW_GAME := 4

var visual_offset := Vector2.ZERO
var initialized := false
var context_key := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = true
	position = VIEW * 0.5
	position_smoothing_enabled = false


func _process(delta: float) -> void:
	var runtime: Node = get_parent()
	if runtime == null:
		return
	var flow := int(runtime.get("flow"))
	var cinematic_id := str(runtime.get("active_cinematic_id"))
	var next_context := camera_context(runtime)
	if next_context != context_key:
		context_key = next_context
		initialized = false
	if flow != FLOW_GAME or not cinematic_id.is_empty() or modal_surface_open(runtime):
		position = VIEW * 0.5
		initialized = false
		return
	var immediate_offset := runtime_camera_offset(runtime)
	var desired_offset := desired_camera_offset(runtime)
	if not initialized:
		visual_offset = immediate_offset
		initialized = true
	var profile: Dictionary = active_profile()
	var deadzone := clampf(PresentationCatalog.number(profile, "camera", "deadzone", 20.0), 0.0, 80.0)
	var follow_strength := clampf(PresentationCatalog.number(profile, "camera", "follow_strength", 8.0), 1.0, 30.0)
	var delta_to_target := desired_offset - visual_offset
	if delta_to_target.length() > deadzone:
		var corrected_target := desired_offset - delta_to_target.normalized() * deadzone
		var weight := 1.0 - exp(-follow_strength * maxf(delta, 0.0))
		visual_offset = visual_offset.lerp(corrected_target, clampf(weight, 0.0, 1.0))
	position = VIEW * 0.5 + visual_offset - immediate_offset


func modal_surface_open(runtime: Node) -> bool:
	if bool(runtime.get("inventory_open")):
		return true
	if bool(runtime.get("story_journal_open")):
		return true
	if bool(runtime.get("save_overlay_open")):
		return true
	if bool(runtime.get("merchant_open")):
		return true
	if bool(runtime.get("player_settings_open")):
		return true
	if not str(runtime.get("dialogue")).is_empty():
		return true
	if not str(runtime.get("active_conversation_id")).is_empty():
		return true
	return false


func camera_context(runtime: Node) -> String:
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = map_value as Dictionary if typeof(map_value) == TYPE_DICTIONARY else {}
	return "%s|%s" % [str(map_data.get("id", "")), str(runtime.get("current_era_id"))]


func desired_camera_offset(runtime: Node) -> Vector2:
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = map_value as Dictionary if typeof(map_value) == TYPE_DICTIONARY else {}
	var canvas_value: Variant = map_data.get("canvas", {})
	var canvas: Dictionary = canvas_value as Dictionary if typeof(canvas_value) == TYPE_DICTIONARY else {}
	var world_size := Vector2(float(canvas.get("width", VIEW.x)), float(canvas.get("height", VIEW.y)))
	var player_value: Variant = runtime.get("player")
	var player: Vector2 = player_value if player_value is Vector2 else VIEW * 0.5
	var facing_value: Variant = runtime.get("facing")
	var facing: Vector2 = facing_value if facing_value is Vector2 else Vector2.DOWN
	var look_ahead := clampf(PresentationCatalog.number(active_profile(), "camera", "look_ahead", 18.0), 0.0, 80.0)
	var center := player + facing.normalized() * look_ahead
	return Vector2(
		clampf(center.x - VIEW.x * 0.5, 0.0, maxf(0.0, world_size.x - VIEW.x)),
		clampf(center.y - VIEW.y * 0.5, 0.0, maxf(0.0, world_size.y - VIEW.y))
	)


func runtime_camera_offset(runtime: Node) -> Vector2:
	if runtime.has_method("camera_offset"):
		var value: Variant = runtime.call("camera_offset")
		if value is Vector2:
			return value
	return Vector2.ZERO


func active_profile() -> Dictionary:
	var overlay: Node = get_node_or_null("../PresentationLayer/PresentationOverlay")
	if overlay == null:
		return PresentationCatalog.default_profile()
	var value: Variant = overlay.get("active_profile")
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else PresentationCatalog.default_profile()
