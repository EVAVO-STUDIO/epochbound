@tool
extends RefCounted

const TERRAIN_CELLS := "terrain_cells"
const COLLISION_CELLS := "collision_cells"
const NAVIGATION_CELLS := "navigation_cells"
const CARDINAL_DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

static func grid_size(map_data: Dictionary) -> int:
	var canvas: Dictionary = map_data.get("canvas", {})
	return maxi(1, int(canvas.get("grid_size", 16)))

static func canvas_size(map_data: Dictionary) -> Vector2i:
	var canvas: Dictionary = map_data.get("canvas", {})
	return Vector2i(
		maxi(1, int(canvas.get("width", 640))),
		maxi(1, int(canvas.get("height", 360)))
	)

static func grid_dimensions(map_data: Dictionary) -> Vector2i:
	var size_value := canvas_size(map_data)
	var cell_size := grid_size(map_data)
	return Vector2i(
		ceili(float(size_value.x) / float(cell_size)),
		ceili(float(size_value.y) / float(cell_size))
	)

static func world_to_cell(map_data: Dictionary, world_position: Vector2) -> Vector2i:
	var cell_size := grid_size(map_data)
	return Vector2i(
		floori(world_position.x / float(cell_size)),
		floori(world_position.y / float(cell_size))
	)

static func cell_to_world(map_data: Dictionary, cell: Vector2i, centred: bool = true) -> Vector2:
	var cell_size := float(grid_size(map_data))
	var offset := Vector2(cell_size * 0.5, cell_size * 0.5) if centred else Vector2.ZERO
	return Vector2(float(cell.x) * cell_size, float(cell.y) * cell_size) + offset

static func cell_rect(map_data: Dictionary, cell: Vector2i) -> Rect2:
	var cell_size := float(grid_size(map_data))
	return Rect2(Vector2(cell.x, cell.y) * cell_size, Vector2.ONE * cell_size)

static func cell_is_inside(map_data: Dictionary, cell: Vector2i) -> bool:
	var dimensions := grid_dimensions(map_data)
	return cell.x >= 0 and cell.y >= 0 and cell.x < dimensions.x and cell.y < dimensions.y

static func available_in_era(record: Dictionary, era_id: String) -> bool:
	var available_value: Variant = record.get("available_eras", [])
	if typeof(available_value) != TYPE_ARRAY:
		return true
	var available: Array = available_value
	return available.is_empty() or available.has(era_id)

static func scope_for_era(era_id: String, era_only: bool) -> Array:
	if era_only and not era_id.is_empty():
		return [era_id]
	return []

static func scope_signature(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return ""
	var identifiers := PackedStringArray()
	for entry in value:
		identifiers.append(String(entry))
	identifiers.sort()
	return "|".join(identifiers)

static func resolved_cells(map_data: Dictionary, collection: String, era_id: String) -> Array:
	var by_coordinate: Dictionary = {}
	var records_value: Variant = map_data.get(collection, [])
	if typeof(records_value) != TYPE_ARRAY:
		return []
	for value in records_value:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		if not available_in_era(record, era_id):
			continue
		var key := "%d:%d" % [int(record.get("x", -1)), int(record.get("y", -1))]
		var available_value: Variant = record.get("available_eras", [])
		var is_specific := typeof(available_value) == TYPE_ARRAY and not Array(available_value).is_empty()
		if not by_coordinate.has(key) or is_specific:
			by_coordinate[key] = record
	return by_coordinate.values()

static func cell_record(map_data: Dictionary, collection: String, cell: Vector2i, era_id: String) -> Dictionary:
	var fallback: Dictionary = {}
	var records_value: Variant = map_data.get(collection, [])
	if typeof(records_value) != TYPE_ARRAY:
		return fallback
	for value in records_value:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		if int(record.get("x", -1)) != cell.x or int(record.get("y", -1)) != cell.y:
			continue
		var available_value: Variant = record.get("available_eras", [])
		if typeof(available_value) != TYPE_ARRAY or Array(available_value).is_empty():
			fallback = record
		elif Array(available_value).has(era_id):
			return record
	return fallback

static func set_cell(
	map_data: Dictionary,
	collection: String,
	cell: Vector2i,
	payload: Dictionary,
	available_eras: Array
) -> bool:
	if not cell_is_inside(map_data, cell):
		return false
	var records: Array = map_data.get(collection, [])
	var next_record := {
		"x": cell.x,
		"y": cell.y,
		"available_eras": available_eras.duplicate()
	}
	for key in payload.keys():
		next_record[key] = payload[key]
	var requested_scope := scope_signature(available_eras)
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = records[index]
		if (
			int(record.get("x", -1)) == cell.x
			and int(record.get("y", -1)) == cell.y
			and scope_signature(record.get("available_eras", [])) == requested_scope
		):
			records[index] = next_record
			map_data[collection] = records
			return true
	records.append(next_record)
	map_data[collection] = records
	return true

static func erase_cell(
	map_data: Dictionary,
	collection: String,
	cell: Vector2i,
	available_eras: Array
) -> bool:
	var records: Array = map_data.get(collection, [])
	var requested_scope := scope_signature(available_eras)
	for index in range(records.size() - 1, -1, -1):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = records[index]
		if (
			int(record.get("x", -1)) == cell.x
			and int(record.get("y", -1)) == cell.y
			and scope_signature(record.get("available_eras", [])) == requested_scope
		):
			records.remove_at(index)
			map_data[collection] = records
			return true
	return false

static func terrain_definition(map_data: Dictionary, terrain_id: String) -> Dictionary:
	for value in map_data.get("terrain_palette", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = value
		if String(definition.get("id", "")) == terrain_id:
			return definition
	return {}

static func terrain_color(
	map_data: Dictionary,
	terrain_id: String,
	era_id: String,
	fallback: Color
) -> Color:
	var definition := terrain_definition(map_data, terrain_id)
	var colors_value: Variant = definition.get("colors", {})
	if typeof(colors_value) != TYPE_DICTIONARY:
		return fallback
	var colors: Dictionary = colors_value
	var html := String(colors.get(era_id, colors.get("default", "")))
	return Color.from_string(html, fallback)

static func terrain_is_blocked(map_data: Dictionary, terrain_id: String) -> bool:
	return bool(terrain_definition(map_data, terrain_id).get("blocked", false))

static func is_cell_blocked(map_data: Dictionary, cell: Vector2i, era_id: String) -> bool:
	if not cell_is_inside(map_data, cell):
		return true
	if not cell_record(map_data, COLLISION_CELLS, cell, era_id).is_empty():
		return true
	var terrain := cell_record(map_data, TERRAIN_CELLS, cell, era_id)
	return terrain_is_blocked(map_data, String(terrain.get("tile", "")))

static func is_position_blocked(
	map_data: Dictionary,
	world_position: Vector2,
	era_id: String,
	radius: float = 6.0
) -> bool:
	var samples := [
		world_position,
		world_position + Vector2(-radius, -radius),
		world_position + Vector2(radius, -radius),
		world_position + Vector2(-radius, radius),
		world_position + Vector2(radius, radius)
	]
	for sample in samples:
		if is_cell_blocked(map_data, world_to_cell(map_data, sample), era_id):
			return true
	return false

static func navigation_cell_set(map_data: Dictionary, era_id: String) -> Dictionary:
	var cells: Dictionary = {}
	for value in resolved_cells(map_data, NAVIGATION_CELLS, era_id):
		var record: Dictionary = value
		var cell := Vector2i(int(record.get("x", -1)), int(record.get("y", -1)))
		if cell_is_inside(map_data, cell) and not is_cell_blocked(map_data, cell, era_id):
			cells[cell] = true
	return cells

static func nearest_cell_in_set(map_data: Dictionary, cells: Dictionary, world_position: Vector2) -> Vector2i:
	var fallback := world_to_cell(map_data, world_position)
	var best := fallback
	var best_distance := INF
	for value in cells.keys():
		var cell: Vector2i = value
		var distance := cell_to_world(map_data, cell).distance_squared_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best

static func navigation_step(
	map_data: Dictionary,
	start_world: Vector2,
	target_world: Vector2,
	era_id: String
) -> Vector2:
	var cells := navigation_cell_set(map_data, era_id)
	if cells.is_empty():
		return target_world
	var start_cell := nearest_cell_in_set(map_data, cells, start_world)
	var target_cell := nearest_cell_in_set(map_data, cells, target_world)
	if start_cell == target_cell:
		return cell_to_world(map_data, target_cell)
	var queue: Array = [start_cell]
	var cursor := 0
	var visited: Dictionary = {start_cell: true}
	var parents: Dictionary = {}
	var found := false
	while cursor < queue.size() and cursor < 4096:
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction in CARDINAL_DIRECTIONS:
			var next_cell: Vector2i = current + direction
			if visited.has(next_cell) or not cells.has(next_cell):
				continue
			visited[next_cell] = true
			parents[next_cell] = current
			if next_cell == target_cell:
				found = true
				break
			queue.append(next_cell)
		if found:
			break
	if not found:
		return cell_to_world(map_data, start_cell)
	var step := target_cell
	while parents.has(step) and parents[step] != start_cell:
		step = parents[step]
	return cell_to_world(map_data, step)

static func nearest_recovery_point(
	map_data: Dictionary,
	world_position: Vector2,
	era_id: String,
	fallback: Vector2
) -> Vector2:
	var best := fallback
	var best_distance := INF
	for value in map_data.get("recovery_anchors", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var anchor: Dictionary = value
		if not available_in_era(anchor, era_id):
			continue
		var position := _data_to_vector(anchor.get("position"), fallback)
		if is_position_blocked(map_data, position, era_id, 4.0):
			continue
		var distance := position.distance_squared_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = position
	return best

static func find_entry_point(map_data: Dictionary, entry_id: String, era_id: String) -> Dictionary:
	for value in map_data.get("entry_points", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		if String(entry.get("id", "")) == entry_id and available_in_era(entry, era_id):
			return entry
	return {}

static func entry_position(entry: Dictionary, actor_id: String, fallback: Vector2) -> Vector2:
	return _data_to_vector(entry.get(actor_id), fallback)

static func find_connection_near(
	map_data: Dictionary,
	world_position: Vector2,
	era_id: String,
	trigger: String
) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for value in map_data.get("connections", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = value
		if String(connection.get("trigger", "interact")) != trigger:
			continue
		if not available_in_era(connection, era_id):
			continue
		var position := _data_to_vector(connection.get("position"), Vector2.ZERO)
		var distance := position.distance_to(world_position)
		if distance <= float(connection.get("radius", 24.0)) and distance < best_distance:
			best_distance = distance
			best = connection
	return best

static func _data_to_vector(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_DICTIONARY:
		return fallback
	var data: Dictionary = value
	return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))
