extends "res://src/adventure_feedback_overlay.gd"

const EnvironmentMapModel = preload("res://src/content/map_model.gd")

const ENVIRONMENT_FLOW_GAME := 4
const ENVIRONMENT_FLOW_PAUSED := 5
const ENVIRONMENT_VIEW := Vector2(640, 360)
const MAX_ANIMATED_TERRAIN_CELLS := 96
const MAX_GROUND_DISTURBANCES := 32
const GROUND_TRAIL_DISTANCE := 12.0
const DISTURBANCE_MOTION_RESET := 48.0
const AMBIENT_GROUND_SAMPLE_COUNT := 24

var environment_clock := 0.0
var environment_map_key := ""
var environment_previous_positions: Dictionary = {}
var environment_step_accumulators: Dictionary = {}
var ground_disturbances: Array[Dictionary] = []


func initialize_from_runtime() -> void:
	super.initialize_from_runtime()
	reset_environment_state()


func _process(delta: float) -> void:
	super._process(delta)
	update_environment_animation(delta)
	queue_redraw()


func reset_environment_state() -> void:
	environment_map_key = current_feedback_map_key()
	environment_clock = 0.0
	environment_previous_positions = {
		"player": runtime_vector("player"),
		"companion": runtime_vector("companion")
	}
	environment_step_accumulators = {
		"player": 0.0,
		"companion": 0.0
	}
	ground_disturbances.clear()


func update_environment_animation(delta: float) -> void:
	var next_key := current_feedback_map_key()
	if next_key != environment_map_key:
		reset_environment_state()
	var in_world := [ENVIRONMENT_FLOW_GAME, ENVIRONMENT_FLOW_PAUSED].has(runtime_flow())
	var frozen := animation_should_freeze()
	if in_world and not frozen:
		environment_clock += maxf(0.0, delta)
		age_ground_disturbances(delta)
	var can_spawn := environment_spawn_allowed()
	track_environment_actor("player", runtime_vector("player"), can_spawn)
	if runtime_companion_enabled():
		track_environment_actor("companion", runtime_vector("companion"), can_spawn)
	else:
		environment_previous_positions["companion"] = runtime_vector("companion")
		environment_step_accumulators["companion"] = 0.0


func environment_spawn_allowed() -> bool:
	return (
		runtime_flow() == ENVIRONMENT_FLOW_GAME
		and not animation_should_freeze()
		and active_cinematic_id().is_empty()
		and runtime_string("dialogue").is_empty()
		and runtime_number("transition_lock", 0.0) <= 0.0
	)


func track_environment_actor(role: String, current: Vector2, can_spawn: bool) -> void:
	var previous_value: Variant = environment_previous_positions.get(role, current)
	var previous: Vector2 = previous_value if previous_value is Vector2 else current
	var distance := current.distance_to(previous)
	environment_previous_positions[role] = current
	if not can_spawn or distance <= 0.01:
		return
	if distance > DISTURBANCE_MOTION_RESET:
		environment_step_accumulators[role] = 0.0
		return
	var accumulated := float(environment_step_accumulators.get(role, 0.0)) + distance
	if accumulated >= GROUND_TRAIL_DISTANCE:
		accumulated = fmod(accumulated, GROUND_TRAIL_DISTANCE)
		spawn_environment_disturbance(current, terrain_effect_kind_at(current), role)
	environment_step_accumulators[role] = accumulated


func terrain_effect_kind_at(world_position: Vector2) -> String:
	var map_data := runtime_map_data()
	if map_data.is_empty():
		return "dust"
	var era_id := runtime_string("current_era_id")
	var cell := EnvironmentMapModel.world_to_cell(map_data, world_position)
	var record := EnvironmentMapModel.cell_record(
		map_data,
		EnvironmentMapModel.TERRAIN_CELLS,
		cell,
		era_id
	)
	var tile_id := str(record.get("tile", ""))
	match tile_id:
		"water":
			return "water"
		"grass":
			return "grass"
		"brass_path":
			return "metal"
		"path", "stone":
			return "ash" if era_id == "ashen" else "dust"
	if era_id == "ashen":
		return "ash"
	if str(map_data.get("id", "")) == "museum_underworks":
		return "dust"
	return "grass"


func spawn_environment_disturbance(position: Vector2, kind: String, actor: String = "player") -> void:
	var resolved_kind := kind if ["water", "grass", "ash", "metal", "dust"].has(kind) else "dust"
	var maximum := disturbance_lifetime(resolved_kind)
	ground_disturbances.append({
		"position": position,
		"kind": resolved_kind,
		"actor": actor,
		"life": maximum,
		"maximum": maximum,
		"phase": float(posmod(absi((actor + resolved_kind + str(position)).hash()), 628)) / 100.0
	})
	while ground_disturbances.size() > MAX_GROUND_DISTURBANCES:
		ground_disturbances.pop_front()


func disturbance_lifetime(kind: String) -> float:
	match kind:
		"water":
			return 0.86
		"grass":
			return 0.58
		"ash":
			return 0.78
		"metal":
			return 0.44
		_:
			return 0.64


func age_ground_disturbances(delta: float) -> void:
	for index in range(ground_disturbances.size() - 1, -1, -1):
		var record: Dictionary = ground_disturbances[index]
		record["life"] = maxf(0.0, float(record.get("life", 0.0)) - delta)
		if float(record.get("life", 0.0)) <= 0.0:
			ground_disturbances.remove_at(index)
		else:
			ground_disturbances[index] = record


func draw_world_accents() -> void:
	super.draw_world_accents()
	if not environment_draw_allowed():
		return
	draw_animated_terrain()
	draw_ambient_ground_motion()
	draw_interaction_world_pulse()


func draw_runtime_entity_overlays() -> void:
	if environment_draw_allowed():
		draw_ground_disturbances()
	super.draw_runtime_entity_overlays()


func environment_draw_allowed() -> bool:
	return (
		[ENVIRONMENT_FLOW_GAME, ENVIRONMENT_FLOW_PAUSED].has(runtime_flow())
		and active_cinematic_id().is_empty()
	)


func interaction_world_pulse_allowed() -> bool:
	return (
		feedback_draw_allowed()
		and runtime_string("dialogue").is_empty()
		and runtime_number("transition_lock", 0.0) <= 0.0
		and context_prompt_alpha > 0.06
		and not context_prompt.is_empty()
	)


func draw_animated_terrain() -> void:
	var map_data := runtime_map_data()
	if map_data.is_empty():
		return
	var era_id := runtime_string("current_era_id")
	var records: Array = EnvironmentMapModel.resolved_cells(
		map_data,
		EnvironmentMapModel.TERRAIN_CELLS,
		era_id
	)
	records.sort_custom(Callable(self, "terrain_record_before"))
	var drawn := 0
	for record_value in records:
		if drawn >= MAX_ANIMATED_TERRAIN_CELLS or typeof(record_value) != TYPE_DICTIONARY:
			break
		var record: Dictionary = record_value as Dictionary
		var tile_id := str(record.get("tile", ""))
		var visual_kind := animated_terrain_kind(tile_id)
		if visual_kind.is_empty():
			continue
		var cell := Vector2i(int(record.get("x", -1)), int(record.get("y", -1)))
		var world_rect := EnvironmentMapModel.cell_rect(map_data, cell)
		var screen_rect := Rect2(world_rect.position - runtime_camera_offset(), world_rect.size)
		if not screen_rect.grow(8.0).intersects(Rect2(Vector2.ZERO, ENVIRONMENT_VIEW)):
			continue
		match visual_kind:
			"water":
				draw_water_cell(map_data, era_id, cell, screen_rect)
			"grass":
				draw_grass_cell(cell, screen_rect)
			"metal":
				draw_metal_cell(cell, screen_rect)
		drawn += 1


func terrain_record_before(left_value: Variant, right_value: Variant) -> bool:
	var left: Dictionary = left_value as Dictionary if typeof(left_value) == TYPE_DICTIONARY else {}
	var right: Dictionary = right_value as Dictionary if typeof(right_value) == TYPE_DICTIONARY else {}
	var left_y := int(left.get("y", 0))
	var right_y := int(right.get("y", 0))
	if left_y != right_y:
		return left_y < right_y
	return int(left.get("x", 0)) < int(right.get("x", 0))


func animated_terrain_kind(tile_id: String) -> String:
	match tile_id:
		"water":
			return "water"
		"grass":
			return "grass"
		"brass_path":
			return "metal"
	return ""


func draw_water_cell(map_data: Dictionary, era_id: String, cell: Vector2i, rect: Rect2) -> void:
	var fallback := profile_color("midtone", "59665c")
	var water := EnvironmentMapModel.terrain_color(map_data, "water", era_id, fallback)
	var phase := environment_clock * 2.4 + float(cell.x) * 0.71 + float(cell.y) * 0.37
	for lane in range(2):
		var y := roundf(rect.position.y + 5.0 + lane * 6.0 + sin(phase + lane * 1.8) * 1.4)
		var travel := posmod(int(floor(environment_clock * 9.0)) + cell.x * 3 + lane * 5, 7)
		var start_x := rect.position.x + 2.0 + float(travel)
		var end_x := minf(rect.end.x - 2.0, start_x + 6.0 + lane * 2.0)
		draw_line(Vector2(start_x, y), Vector2(end_x, y), Color(water.lightened(0.22), 0.58), 1.0)
	var dark_y := roundf(rect.end.y - 3.0 + sin(phase * 0.8) * 0.8)
	draw_line(Vector2(rect.position.x + 3.0, dark_y), Vector2(rect.end.x - 3.0, dark_y), Color(water.darkened(0.18), 0.32), 1.0)


func draw_grass_cell(cell: Vector2i, rect: Rect2) -> void:
	var midtone := profile_color("midtone", "59665c")
	var light := profile_color("light", "d7c99b")
	var phase := environment_clock * 1.8 + float(cell.x) * 0.63 + float(cell.y) * 0.41
	for blade in range(3):
		var x := rect.position.x + 4.0 + blade * 4.0
		var base := Vector2(roundf(x), rect.end.y - 2.0)
		var sway := roundf(sin(phase + blade * 1.7) * 2.0)
		var height := 4.0 + float(posmod(cell.x + cell.y + blade, 3))
		draw_line(base, base + Vector2(sway, -height), Color(midtone, 0.52), 1.0)
		if blade == 1:
			draw_rect(Rect2(base + Vector2(sway - 1.0, -height - 1.0), Vector2(1, 1)), Color(light, 0.34))


func draw_metal_cell(cell: Vector2i, rect: Rect2) -> void:
	var accent := profile_color("accent", "d49a45")
	var shadow := profile_color("shadow", "263033")
	var travel := fposmod(environment_clock * 13.0 + float(cell.x * 5 + cell.y * 3), maxf(1.0, rect.size.x - 4.0))
	var x := roundf(rect.position.x + 2.0 + travel)
	var y := roundf(rect.position.y + rect.size.y * 0.5)
	draw_line(Vector2(rect.position.x + 2.0, y + 3.0), Vector2(rect.end.x - 2.0, y + 3.0), Color(shadow, 0.34), 1.0)
	draw_rect(Rect2(Vector2(x, y - 1.0), Vector2(2, 2)), Color(accent, 0.62))
	if posmod(cell.x + cell.y, 4) == 0:
		draw_line(Vector2(x - 2.0, y), Vector2(x + 3.0, y), Color(accent.lightened(0.18), 0.34), 1.0)


func draw_ambient_ground_motion() -> void:
	var map_data := runtime_map_data()
	if map_data.is_empty():
		return
	var bounds_value: Variant = map_data.get("bounds", {})
	var bounds: Dictionary = bounds_value as Dictionary if typeof(bounds_value) == TYPE_DICTIONARY else {}
	var left := float(bounds.get("left", 32.0))
	var right := float(bounds.get("right", 608.0))
	var top := float(bounds.get("top", 96.0))
	var bottom := float(bounds.get("bottom", 328.0))
	var width := maxf(1.0, right - left)
	var height := maxf(1.0, bottom - top)
	var map_id := str(map_data.get("id", "map"))
	var era_id := runtime_string("current_era_id")
	var seed_base := absi((map_id + "|" + era_id + "|environment").hash())
	for index in range(AMBIENT_GROUND_SAMPLE_COUNT):
		var seed := seed_base + index * 4253
		var world_position := Vector2(
			left + float(posmod(seed * 31, maxi(1, int(width)))),
			top + float(posmod(seed * 47, maxi(1, int(height))))
		)
		if EnvironmentMapModel.is_position_blocked(map_data, world_position, era_id, 1.0):
			continue
		var screen_position := world_to_screen(world_position)
		if screen_position.x < -8.0 or screen_position.x > ENVIRONMENT_VIEW.x + 8.0 or screen_position.y < 82.0 or screen_position.y > ENVIRONMENT_VIEW.y + 8.0:
			continue
		var kind := terrain_effect_kind_at(world_position)
		var phase := environment_clock + float(posmod(seed, 628)) / 100.0
		match kind:
			"grass":
				var sway := roundf(sin(phase * 1.7) * 2.0)
				draw_line(screen_position, screen_position + Vector2(sway, -4.0), Color(profile_color("midtone", "59665c"), 0.28), 1.0)
			"ash":
				var ash_x := roundf(fposmod(phase * 5.0, 8.0) - 4.0)
				draw_rect(Rect2(screen_position + Vector2(ash_x, -2.0), Vector2(2, 1)), Color(profile_color("light", "d7c99b"), 0.20))
			"metal":
				if posmod(seed, 3) == 0:
					draw_rect(Rect2(screen_position + Vector2(roundf(sin(phase * 2.0) * 2.0), -1.0), Vector2(1, 1)), Color(profile_color("accent", "d49a45"), 0.42))
			"dust":
				if posmod(seed, 4) == 0:
					draw_line(screen_position, screen_position + Vector2(3.0, 0.0), Color(profile_color("shadow", "263033"), 0.20), 1.0)


func draw_interaction_world_pulse() -> void:
	if not interaction_world_pulse_allowed():
		return
	var position_value: Variant = context_prompt.get("position", Vector2.ZERO)
	var world_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
	var position: Vector2 = world_to_screen(world_position)
	var enabled := bool(context_prompt.get("enabled", true))
	var color := profile_color("accent", "d49a45") if enabled else profile_color("danger", "b94d45")
	var pulse := 10.0 + sin(environment_clock * 5.0) * 2.0
	var alpha := context_prompt_alpha * (0.48 if enabled else 0.62)
	draw_arc(position, pulse, 0.0, TAU, 20, Color(color, alpha), 1.0)
	for direction_value in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var direction: Vector2 = direction_value
		var start: Vector2 = position + direction * (pulse + 2.0)
		draw_line(start, start + direction * 3.0, Color(color, alpha), 1.0)


func draw_ground_disturbances() -> void:
	for record_value in ground_disturbances:
		var record: Dictionary = record_value
		var life := float(record.get("life", 0.0))
		var maximum := maxf(0.001, float(record.get("maximum", 1.0)))
		var alpha := clampf(life / maximum, 0.0, 1.0)
		var progress := 1.0 - alpha
		var position_value: Variant = record.get("position", Vector2.ZERO)
		var world_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var position := world_to_screen(world_position)
		if position.x < -24.0 or position.x > ENVIRONMENT_VIEW.x + 24.0 or position.y < 70.0 or position.y > ENVIRONMENT_VIEW.y + 24.0:
			continue
		match str(record.get("kind", "dust")):
			"water":
				draw_ellipse_outline(position + Vector2(0, 5), 4.0 + progress * 12.0, 2.0 + progress * 4.0, Color(profile_color("light", "d7c99b"), alpha * 0.55))
			"grass":
				var sway := sin(float(record.get("phase", 0.0)) + progress * 4.0) * 3.0
				draw_line(position + Vector2(-3, 5), position + Vector2(-2 + sway, -2), Color(profile_color("midtone", "59665c"), alpha * 0.52), 1.0)
				draw_line(position + Vector2(3, 5), position + Vector2(2 - sway, -1), Color(profile_color("midtone", "59665c"), alpha * 0.44), 1.0)
			"ash":
				for particle in range(3):
					var drift := Vector2((particle - 1) * 4.0 + progress * 5.0, -progress * (4.0 + particle * 2.0))
					draw_rect(Rect2(position + drift, Vector2(2, 1)), Color(profile_color("light", "d7c99b"), alpha * (0.26 + particle * 0.06)))
			"metal":
				var radius := 3.0 + progress * 4.0
				draw_line(position + Vector2(-radius, 3), position + Vector2(radius, 3), Color(profile_color("accent", "d49a45"), alpha * 0.62), 1.0)
				draw_line(position + Vector2(0, 3 - radius), position + Vector2(0, 3 + radius), Color(profile_color("light", "d7c99b"), alpha * 0.44), 1.0)
			_:
				for particle in range(3):
					var offset := Vector2((particle - 1) * 4.0 + progress * 2.0, 4.0 - progress * (2.0 + particle))
					draw_circle(position + offset, 1.0 + progress, Color(profile_color("shadow", "263033"), alpha * 0.26))


func draw_ellipse_outline(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(17):
		var angle := TAU * float(index) / 16.0
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	draw_polyline(points, color, 1.0, false)


func animated_terrain_counts() -> Dictionary:
	var output := {"water": 0, "grass": 0, "metal": 0}
	var map_data := runtime_map_data()
	if map_data.is_empty():
		return output
	for record_value in EnvironmentMapModel.resolved_cells(
		map_data,
		EnvironmentMapModel.TERRAIN_CELLS,
		runtime_string("current_era_id")
	):
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var kind := animated_terrain_kind(str((record_value as Dictionary).get("tile", "")))
		if output.has(kind):
			output[kind] = int(output[kind]) + 1
	return output


func ground_disturbance_kinds() -> PackedStringArray:
	var output := PackedStringArray()
	for record in ground_disturbances:
		output.append(str(record.get("kind", "dust")))
	return output


func environment_disturbance_count() -> int:
	return ground_disturbances.size()


func environment_animation_contract_ok() -> bool:
	return (
		adventure_feedback_contract_ok()
		and MAX_ANIMATED_TERRAIN_CELLS > 0
		and MAX_ANIMATED_TERRAIN_CELLS <= 128
		and MAX_GROUND_DISTURBANCES > 0
		and MAX_GROUND_DISTURBANCES <= 48
		and GROUND_TRAIL_DISTANCE >= 8.0
		and GROUND_TRAIL_DISTANCE <= 24.0
	)
