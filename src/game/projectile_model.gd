extends RefCounted

const EncounterModel = preload("res://src/game/encounter_model.gd")


static func create_projectile(
	source_kind: String,
	source_id: String,
	source_name: String,
	position: Vector2,
	direction: Vector2,
	speed: float,
	maximum_range: float,
	radius: float,
	damage: int,
	knockback_distance: float,
	color: Color,
	target_kind: String
) -> Dictionary:
	var resolved_direction := direction.normalized()
	if resolved_direction.length_squared() <= 0.001:
		resolved_direction = Vector2.DOWN
	return {
		"active": true,
		"source_kind": source_kind,
		"source_id": source_id,
		"source_name": source_name,
		"position": position,
		"previous_position": position,
		"direction": resolved_direction,
		"speed": maxf(1.0, speed),
		"remaining_distance": maxf(1.0, maximum_range),
		"radius": maxf(1.0, radius),
		"damage": maxi(1, damage),
		"knockback_distance": maxf(0.0, knockback_distance),
		"color": color,
		"target_kind": target_kind
	}


static func advance(projectile: Dictionary, delta: float) -> Dictionary:
	var output := projectile.duplicate(true)
	var previous: Vector2 = vector_value(output.get("position"), Vector2.ZERO)
	var direction: Vector2 = vector_value(output.get("direction"), Vector2.DOWN).normalized()
	var requested_distance := maxf(0.0, float(output.get("speed", 1.0)) * maxf(0.0, delta))
	var remaining := maxf(0.0, float(output.get("remaining_distance", 0.0)))
	var travelled := minf(requested_distance, remaining)
	output["previous_position"] = previous
	output["position"] = previous + direction * travelled
	output["remaining_distance"] = maxf(0.0, remaining - travelled)
	if travelled <= 0.0 or float(output.get("remaining_distance", 0.0)) <= 0.0:
		output["active"] = false
	return output


static func segment_hits_circle(
	start: Vector2,
	finish: Vector2,
	center: Vector2,
	radius: float
) -> bool:
	return segment_distance_squared(start, finish, center) <= radius * radius


static func segment_distance_squared(start: Vector2, finish: Vector2, point: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return start.distance_squared_to(point)
	var projection := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	var closest := start + segment * projection
	return closest.distance_squared_to(point)


static func segment_progress(start: Vector2, finish: Vector2, point: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return 0.0
	return clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)


static func first_enemy_hit(projectile: Dictionary, entities: Array) -> int:
	var start := vector_value(projectile.get("previous_position"), Vector2.ZERO)
	var finish := vector_value(projectile.get("position"), start)
	var projectile_radius := maxf(1.0, float(projectile.get("radius", 1.0)))
	var best_index := -1
	var best_progress := INF
	for index in range(entities.size()):
		if typeof(entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entities[index]
		if not bool(entity.get("active", true)) or EncounterModel.kind(entity) != "enemy":
			continue
		var center := vector_value(entity.get("position"), Vector2.ZERO)
		var combined_radius := projectile_radius + EncounterModel.collision_radius(entity)
		if not segment_hits_circle(start, finish, center, combined_radius):
			continue
		var progress := segment_progress(start, finish, center)
		if progress < best_progress:
			best_progress = progress
			best_index = index
	return best_index


static func first_solid_obstacle_hit(projectile: Dictionary, entities: Array) -> int:
	var start := vector_value(projectile.get("previous_position"), Vector2.ZERO)
	var finish := vector_value(projectile.get("position"), start)
	var projectile_radius := maxf(1.0, float(projectile.get("radius", 1.0)))
	var best_index := -1
	var best_progress := INF
	for index in range(entities.size()):
		if typeof(entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entities[index]
		if not bool(entity.get("active", true)) or EncounterModel.kind(entity) == "enemy":
			continue
		var definition_data: Dictionary = entity.get("definition", {})
		if not bool(definition_data.get("solid", false)):
			continue
		var center := vector_value(entity.get("position"), Vector2.ZERO)
		var combined_radius := projectile_radius + EncounterModel.collision_radius(entity)
		if not segment_hits_circle(start, finish, center, combined_radius):
			continue
		var progress := segment_progress(start, finish, center)
		if progress < best_progress:
			best_progress = progress
			best_index = index
	return best_index


static func hits_actor(projectile: Dictionary, actor_position: Vector2, actor_radius: float) -> bool:
	return segment_hits_circle(
		vector_value(projectile.get("previous_position"), actor_position),
		vector_value(projectile.get("position"), actor_position),
		actor_position,
		maxf(1.0, float(projectile.get("radius", 1.0))) + maxf(1.0, actor_radius)
	)


static func vector_value(value: Variant, fallback: Vector2) -> Vector2:
	return value if value is Vector2 else fallback
