extends "res://src/sprite_animation_overlay_current.gd"

const AnimationRepository = preload("res://src/content/campaign_repository.gd")

const MOTION_DISTANCE_RESET := 48.0
const WALK_FRAME_DISTANCE_MIN := 3.0
const WALK_FRAME_DISTANCE_MAX := 8.0
const DEPTH_EPSILON := 0.001
const OCCLUDING_LANDMARKS := ["tree", "dead_tree", "ruin"]

var travel_distance_by_key: Dictionary = {}
var last_depth_order := PackedStringArray()


func capture_animation_positions() -> void:
	super.capture_animation_positions()
	travel_distance_by_key.clear()
	travel_distance_by_key["player"] = 0.0
	travel_distance_by_key["companion"] = 0.0
	for entity_value in runtime_array("runtime_entities"):
		if typeof(entity_value) == TYPE_DICTIONARY:
			travel_distance_by_key[entity_animation_key(entity_value as Dictionary)] = 0.0


func _process(delta: float) -> void:
	var previous_clock := animation_clock
	super._process(delta)
	if animation_should_freeze():
		animation_clock = previous_clock


func update_animation_motion(delta: float) -> void:
	accumulate_actor_distance("player", runtime_vector("player"))
	accumulate_actor_distance("companion", runtime_vector("companion"))
	for entity_value in runtime_array("runtime_entities"):
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value as Dictionary
		var key := entity_animation_key(entity)
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var current: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var previous_value: Variant = entity_previous_positions.get(key, current)
		var previous: Vector2 = previous_value if previous_value is Vector2 else current
		accumulate_distance(key, current.distance_to(previous))
	super.update_animation_motion(delta)


func accumulate_actor_distance(key: String, current: Vector2) -> void:
	var previous_value: Variant = actor_previous_positions.get(key, current)
	var previous: Vector2 = previous_value if previous_value is Vector2 else current
	accumulate_distance(key, current.distance_to(previous))


func accumulate_distance(key: String, distance: float) -> void:
	if distance <= 0.0:
		return
	if distance > MOTION_DISTANCE_RESET:
		travel_distance_by_key[key] = 0.0
		return
	travel_distance_by_key[key] = float(travel_distance_by_key.get(key, 0.0)) + distance


func resolved_frame(profile: Dictionary, state: String, key: String) -> int:
	if state != "walk" or not travel_distance_by_key.has(key):
		return super.resolved_frame(profile, state, key)
	var record := SpriteAnimationCatalog.animation(profile, state)
	var frames := maxi(1, int(record.get("frames", 1)))
	var frame_distance := walk_frame_distance(profile, frames)
	return posmod(int(floor(float(travel_distance_by_key.get(key, 0.0)) / frame_distance)), frames)


func animation_frame(profile: Dictionary, state: String, key: String) -> int:
	return resolved_frame(profile, state, key)


func walk_frame_distance(profile: Dictionary, frames: int = 1) -> float:
	var render_size := SpriteAnimationCatalog.vector2i_value(profile, "render_size", Vector2i(32, 32))
	var body_scale := maxf(1.0, float(render_size.y) * 0.16)
	var cadence_scale := 6.0 / float(maxi(1, frames))
	return clampf(body_scale * cadence_scale, WALK_FRAME_DISTANCE_MIN, WALK_FRAME_DISTANCE_MAX)


func animation_should_freeze() -> bool:
	if runtime_flow() == FLOW_PAUSED:
		return true
	return (
		runtime_boolean("inventory_open")
		or runtime_boolean("story_journal_open")
		or runtime_boolean("save_overlay_open")
		or runtime_boolean("merchant_open")
	)


func draw_actor_overlays() -> void:
	# Player, companion and placed entities are rendered together below so their
	# feet share one deterministic depth order instead of two disconnected passes.
	pass


func draw_runtime_entity_overlays() -> void:
	var records := depth_records()
	last_depth_order.clear()
	for record_value in records:
		var record: Dictionary = record_value
		var kind := str(record.get("kind", ""))
		last_depth_order.append(str(record.get("key", kind)))
		match kind:
			"player":
				draw_player_sprite(world_to_screen(runtime_vector("player")))
			"companion":
				draw_companion_sprite(world_to_screen(runtime_vector("companion")))
			"entity":
				var entity_value: Variant = record.get("entity", {})
				if typeof(entity_value) == TYPE_DICTIONARY:
					draw_entity_sprite(entity_value as Dictionary)
	draw_landmark_foregrounds()


func depth_records() -> Array:
	var records: Array = []
	var player_position := runtime_vector("player")
	records.append({
		"kind": "player",
		"key": "player",
		"y": player_position.y,
		"tie": 1
	})
	if runtime_companion_enabled():
		var companion_position := runtime_vector("companion")
		records.append({
			"kind": "companion",
			"key": "companion",
			"y": companion_position.y,
			"tie": 2
		})
	for entity_value in runtime_array("runtime_entities"):
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value as Dictionary
		if not bool(entity.get("active", true)):
			continue
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		records.append({
			"kind": "entity",
			"key": entity_animation_key(entity),
			"y": position.y,
			"tie": 3,
			"entity": entity
		})
	records.sort_custom(Callable(self, "depth_before"))
	return records


func depth_before(left_value: Variant, right_value: Variant) -> bool:
	var left: Dictionary = left_value as Dictionary if typeof(left_value) == TYPE_DICTIONARY else {}
	var right: Dictionary = right_value as Dictionary if typeof(right_value) == TYPE_DICTIONARY else {}
	var left_y := float(left.get("y", 0.0))
	var right_y := float(right.get("y", 0.0))
	if absf(left_y - right_y) > DEPTH_EPSILON:
		return left_y < right_y
	var left_tie := int(left.get("tie", 0))
	var right_tie := int(right.get("tie", 0))
	if left_tie != right_tie:
		return left_tie < right_tie
	return str(left.get("key", "")) < str(right.get("key", ""))


func depth_order_keys() -> PackedStringArray:
	var output := PackedStringArray()
	for record_value in depth_records():
		var record: Dictionary = record_value
		output.append(str(record.get("key", record.get("kind", ""))))
	return output


func current_era_landmarks() -> Array:
	var runtime := runtime_root()
	if runtime == null:
		return []
	var map_value: Variant = runtime.get("map_data")
	if typeof(map_value) != TYPE_DICTIONARY:
		return []
	var era_id := str(runtime.get("current_era_id"))
	for era_value in (map_value as Dictionary).get("eras", []):
		if typeof(era_value) != TYPE_DICTIONARY:
			continue
		var era: Dictionary = era_value as Dictionary
		if str(era.get("id", "")) == era_id:
			var landmarks_value: Variant = era.get("landmarks", [])
			return landmarks_value as Array if typeof(landmarks_value) == TYPE_ARRAY else []
	return []


func draw_landmark_foregrounds() -> void:
	for landmark_value in current_era_landmarks():
		if typeof(landmark_value) != TYPE_DICTIONARY:
			continue
		var landmark: Dictionary = landmark_value as Dictionary
		var kind := str(landmark.get("kind", ""))
		if not OCCLUDING_LANDMARKS.has(kind):
			continue
		var position_value: Variant = landmark.get("position", {})
		var world_position := AnimationRepository.data_to_vector(position_value, Vector2.ZERO)
		var position := world_to_screen(world_position)
		var size_value := maxf(8.0, float(landmark.get("size", 24.0)))
		draw_landmark_foreground(kind, position, size_value)


func draw_landmark_foreground(kind: String, position: Vector2, size_value: float) -> void:
	var ink := profile_color("ink", "13161a")
	var shadow := profile_color("shadow", "263033")
	var midtone := profile_color("midtone", "59665c")
	var light := profile_color("light", "d7c99b")
	match kind:
		"tree":
			var canopy_y := position.y - size_value * 0.82
			draw_circle(Vector2(position.x - size_value * 0.28, canopy_y), size_value * 0.44, ink)
			draw_circle(Vector2(position.x + size_value * 0.24, canopy_y - size_value * 0.08), size_value * 0.40, ink)
			draw_circle(Vector2(position.x, canopy_y - size_value * 0.30), size_value * 0.42, ink)
			draw_rect(Rect2(position.x - size_value * 0.56, canopy_y - size_value * 0.06, size_value * 1.12, size_value * 0.38), midtone)
			draw_rect(Rect2(position.x - size_value * 0.30, canopy_y - size_value * 0.40, size_value * 0.60, size_value * 0.34), shadow)
			draw_rect(Rect2(position.x - 2.0, canopy_y - size_value * 0.46, 4.0, 4.0), light)
		"dead_tree":
			var crown := position + Vector2(0, -size_value * 0.72)
			draw_line(crown, crown + Vector2(-size_value * 0.46, -size_value * 0.40), ink, 4.0)
			draw_line(crown, crown + Vector2(size_value * 0.42, -size_value * 0.52), ink, 4.0)
			draw_line(crown + Vector2(-size_value * 0.18, -size_value * 0.16), crown + Vector2(-size_value * 0.58, -size_value * 0.08), shadow, 3.0)
			draw_line(crown + Vector2(size_value * 0.16, -size_value * 0.20), crown + Vector2(size_value * 0.56, -size_value * 0.12), shadow, 3.0)
		"ruin":
			var top := position.y - size_value * 0.72
			draw_rect(Rect2(position.x - size_value * 0.52, top, size_value * 1.04, maxf(5.0, size_value * 0.14)), ink)
			draw_rect(Rect2(position.x - size_value * 0.46, top + 2.0, size_value * 0.92, maxf(2.0, size_value * 0.07)), midtone)
			draw_rect(Rect2(position.x - size_value * 0.50, top, maxf(6.0, size_value * 0.13), size_value * 0.50), shadow)
			draw_rect(Rect2(position.x + size_value * 0.37, top, maxf(6.0, size_value * 0.13), size_value * 0.50), shadow)


func landmark_foreground_count() -> int:
	var count := 0
	for landmark_value in current_era_landmarks():
		if typeof(landmark_value) == TYPE_DICTIONARY and OCCLUDING_LANDMARKS.has(str((landmark_value as Dictionary).get("kind", ""))):
			count += 1
	return count


func animation_polish_contract_ok() -> bool:
	return (
		sprite_runtime_contract_ok()
		and walk_frame_distance(SpriteAnimationCatalog.default_profile(), 6) >= WALK_FRAME_DISTANCE_MIN
		and walk_frame_distance(SpriteAnimationCatalog.default_profile(), 6) <= WALK_FRAME_DISTANCE_MAX
	)
