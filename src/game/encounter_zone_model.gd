extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")

const DEFAULT_ACTIVATION_PADDING := 48.0
const DEFAULT_LEASH_PADDING := 36.0


static func all_zones(map_data: Dictionary) -> Array:
	var value: Variant = map_data.get("encounter_zones", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func available_zones(map_data: Dictionary, era_id: String) -> Array:
	var output: Array = []
	for value in all_zones(map_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = value
		if record_is_available(zone, era_id):
			output.append(zone)
	return output


static func record_is_available(record: Dictionary, era_id: String) -> bool:
	var value: Variant = record.get("available_eras", [])
	if typeof(value) != TYPE_ARRAY:
		return true
	var available: Array = value
	return available.is_empty() or available.has(era_id)


static func enemy_placement_ids(zone: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	var value: Variant = zone.get("enemy_placements", [])
	if typeof(value) != TYPE_ARRAY:
		return ids
	for item in value:
		var identifier := str(item).strip_edges()
		if not identifier.is_empty():
			ids.append(identifier)
	return ids


static func zone_for_enemy(map_data: Dictionary, placement_id: String, era_id: String) -> Dictionary:
	for value in available_zones(map_data, era_id):
		var zone: Dictionary = value
		if enemy_placement_ids(zone).has(placement_id):
			return zone
	return {}


static func center(zone: Dictionary) -> Vector2:
	return Repository.data_to_vector(zone.get("position"), Vector2.ZERO)


static func radius(zone: Dictionary) -> float:
	return maxf(8.0, float(zone.get("radius", 96.0)))


static func activation_radius(zone: Dictionary) -> float:
	return maxf(radius(zone), float(zone.get("activation_radius", radius(zone) + DEFAULT_ACTIVATION_PADDING)))


static func leash_padding(zone: Dictionary) -> float:
	return maxf(0.0, float(zone.get("leash_padding", DEFAULT_LEASH_PADDING)))


static func contains(zone: Dictionary, point: Vector2, padding: float = 0.0) -> bool:
	return center(zone).distance_to(point) <= radius(zone) + padding


static func is_activated(
	zone: Dictionary,
	player_position: Vector2,
	companion_position: Vector2,
	companion_enabled: bool
) -> bool:
	var origin := center(zone)
	var activation := activation_radius(zone)
	if origin.distance_to(player_position) <= activation:
		return true
	return companion_enabled and origin.distance_to(companion_position) <= activation


static func leash_radius_for_enemy(zone: Dictionary, definition_data: Dictionary) -> float:
	var authored := float(definition_data.get("leash_radius", 0.0))
	if authored > 0.0:
		return authored
	if zone.is_empty():
		return maxf(96.0, float(definition_data.get("awareness_radius", 96.0)) + 48.0)
	return radius(zone) + leash_padding(zone)


static func target_is_inside_leash(zone: Dictionary, spawn_position: Vector2, target: Vector2, leash: float) -> bool:
	if zone.is_empty():
		return spawn_position.distance_to(target) <= leash
	return contains(zone, target, leash_padding(zone))


static func zone_state_key(map_id: String, zone: Dictionary) -> String:
	var authored := str(zone.get("clear_state_key", "")).strip_edges()
	if not authored.is_empty():
		return authored
	return "%s:zone:%s" % [map_id, zone.get("id", "encounter")]


static func zone_is_cleared(zone: Dictionary, entities: Array) -> bool:
	var ids := enemy_placement_ids(zone)
	if ids.is_empty():
		return false
	var found_member := false
	for value in entities:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = value
		if not ids.has(str(entity.get("placement_id", ""))):
			continue
		found_member = true
		if bool(entity.get("active", true)):
			return false
	return found_member


static func default_zone(zone_id: String, position: Vector2, enemy_ids: Array = []) -> Dictionary:
	return {
		"id": zone_id,
		"position": Repository.vector_to_data(position),
		"radius": 96,
		"activation_radius": 144,
		"leash_padding": 36,
		"enemy_placements": enemy_ids.duplicate(),
		"available_eras": [],
		"clear_state_key": ""
	}
