extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")


static func instantiate_entities(
	map_data: Dictionary,
	definitions: Dictionary,
	era_id: String,
	session_state: Dictionary
) -> Array:
	var entities: Array = []
	var map_id := String(map_data.get("id", "map"))
	for value in map_data.get("object_placements", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = value
		if not ObjectCatalog.placement_is_available(placement, era_id):
			continue
		var object_id := String(placement.get("object_id", ""))
		var definition_data := ObjectCatalog.definition(definitions, object_id)
		if definition_data.is_empty():
			continue
		var state_key := ObjectCatalog.state_key(map_id, placement)
		var kind := String(definition_data.get("kind", "prop"))
		if kind in ["enemy", "pickup"] and session_state.has(state_key):
			continue
		var position := Repository.data_to_vector(placement.get("position"), Vector2.ZERO)
		entities.append({
			"placement_id": String(placement.get("id", "placement")),
			"object_id": object_id,
			"state_key": state_key,
			"position": position,
			"spawn_position": position,
			"facing": String(placement.get("facing", "down")),
			"definition": definition_data,
			"health": int(definition_data.get("max_health", 1)),
			"attack_cooldown": 0.0,
			"hit_flash": 0.0,
			"active": true
		})
	return entities


static func kind(entity: Dictionary) -> String:
	var definition_data: Dictionary = entity.get("definition", {})
	return String(definition_data.get("kind", "prop"))


static func collision_radius(entity: Dictionary) -> float:
	var definition_data: Dictionary = entity.get("definition", {})
	return float(definition_data.get("collision_radius", 0.0))


static func interaction_radius(entity: Dictionary) -> float:
	var definition_data: Dictionary = entity.get("definition", {})
	return float(definition_data.get("interaction_radius", 0.0))


static func is_solid(entity: Dictionary) -> bool:
	if not bool(entity.get("active", true)):
		return false
	var definition_data: Dictionary = entity.get("definition", {})
	return bool(definition_data.get("solid", false))


static func position_is_blocked_by_entities(
	entities: Array,
	position: Vector2,
	radius: float,
	ignored_index: int = -1
) -> bool:
	for index in range(entities.size()):
		if index == ignored_index or typeof(entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entities[index]
		if not is_solid(entity):
			continue
		var entity_position: Vector2 = entity.get("position", Vector2.ZERO)
		if entity_position.distance_to(position) < collision_radius(entity) + radius:
			return true
	return false


static func nearest_entity_index(
	entities: Array,
	position: Vector2,
	allowed_kinds: Array,
	maximum_distance: float
) -> int:
	var best_index := -1
	var best_distance := maximum_distance
	for index in range(entities.size()):
		if typeof(entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entities[index]
		if not bool(entity.get("active", true)) or not allowed_kinds.has(kind(entity)):
			continue
		var distance := position.distance_to(entity.get("position", Vector2.ZERO))
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


static func nearest_facing_enemy_index(
	entities: Array,
	position: Vector2,
	facing: Vector2,
	maximum_distance: float,
	minimum_dot: float = -0.1
) -> int:
	var best_index := -1
	var best_distance := maximum_distance
	var normalised_facing := facing.normalized()
	for index in range(entities.size()):
		if typeof(entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entities[index]
		if not bool(entity.get("active", true)) or kind(entity) != "enemy":
			continue
		var offset: Vector2 = entity.get("position", Vector2.ZERO) - position
		var distance := offset.length()
		if distance >= best_distance or distance <= 0.001:
			continue
		if normalised_facing.dot(offset.normalized()) < minimum_dot:
			continue
		best_distance = distance
		best_index = index
	return best_index


static func facing_vector(facing_name: String) -> Vector2:
	match facing_name:
		"up": return Vector2.UP
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
		_: return Vector2.DOWN


static func update_facing(entity: Dictionary, direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		entity["facing"] = "right" if direction.x > 0.0 else "left"
	elif absf(direction.y) > 0.001:
		entity["facing"] = "down" if direction.y > 0.0 else "up"


static func preserve_runtime_state(previous: Array, next_entities: Array) -> Array:
	var by_id: Dictionary = {}
	for value in previous:
		if typeof(value) == TYPE_DICTIONARY:
			var entity: Dictionary = value
			by_id[String(entity.get("placement_id", ""))] = entity
	for index in range(next_entities.size()):
		if typeof(next_entities[index]) != TYPE_DICTIONARY:
			continue
		var next_entity: Dictionary = next_entities[index]
		var placement_id := String(next_entity.get("placement_id", ""))
		if not by_id.has(placement_id):
			continue
		var old: Dictionary = by_id[placement_id]
		for field in ["position", "health", "attack_cooldown", "hit_flash", "facing"]:
			if old.has(field):
				next_entity[field] = old[field]
		next_entities[index] = next_entity
	return next_entities
