@tool
extends Control

signal canvas_action(world_position: Vector2, cell: Vector2i, tool: String, erase: bool)
signal stroke_started()
signal stroke_finished()

const Repository = preload("res://src/content/campaign_repository.gd")
const MapModel = preload("res://src/content/map_model.gd")

var map_data: Dictionary = {}
var era_id := ""
var active_tool := "select"
var selected_marker_kind := ""
var selected_marker_id := ""
var show_collision := true
var show_navigation := true
var show_markers := true
var user_zoom := 1.0
var pan_offset := Vector2.ZERO
var panning := false
var painting := false
var erase_mode := false
var last_painted_cell := Vector2i(-99999, -99999)
var hover_world := Vector2(-1, -1)
var hover_cell := Vector2i(-1, -1)


func _ready() -> void:
	custom_minimum_size = Vector2(640, 360)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func set_map_data(value: Dictionary) -> void:
	map_data = value
	var era_ids: Array[String] = []
	for value_era in map_data.get("eras", []):
		if typeof(value_era) == TYPE_DICTIONARY:
			var era: Dictionary = value_era
			era_ids.append(String(era.get("id", "")))
	if era_id.is_empty() or not era_ids.has(era_id):
		era_id = first_era_id()
	queue_redraw()


func set_era(value: String) -> void:
	era_id = value
	queue_redraw()


func set_tool(value: String) -> void:
	active_tool = value
	queue_redraw()


func set_selected_marker(kind: String, identifier: String) -> void:
	selected_marker_kind = kind
	selected_marker_id = identifier
	queue_redraw()


func set_overlay_visibility(collision_visible: bool, navigation_visible: bool, markers_visible: bool) -> void:
	show_collision = collision_visible
	show_navigation = navigation_visible
	show_markers = markers_visible
	queue_redraw()


func reset_view() -> void:
	user_zoom = 1.0
	pan_offset = Vector2.ZERO
	queue_redraw()


func first_era_id() -> String:
	for value in map_data.get("eras", []):
		if typeof(value) == TYPE_DICTIONARY:
			var era: Dictionary = value
			return String(era.get("id", ""))
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		hover_world = screen_to_world(motion.position)
		hover_cell = MapModel.world_to_cell(map_data, hover_world) if hover_world.x >= 0.0 else Vector2i(-1, -1)
		if panning:
			pan_offset += motion.relative
			queue_redraw()
			accept_event()
			return
		if painting:
			emit_paint_action(motion.position)
			accept_event()
			return
		queue_redraw()
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
		user_zoom = clampf(user_zoom * 1.15, 0.5, 6.0)
		queue_redraw()
		accept_event()
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
		user_zoom = clampf(user_zoom / 1.15, 0.5, 6.0)
		queue_redraw()
		accept_event()
		return
	if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
		panning = mouse_event.pressed
		accept_event()
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT and mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if is_paint_tool(active_tool):
		if mouse_event.pressed:
			painting = true
			erase_mode = mouse_event.button_index == MOUSE_BUTTON_RIGHT
			last_painted_cell = Vector2i(-99999, -99999)
			stroke_started.emit()
			emit_paint_action(mouse_event.position)
		else:
			if painting:
				painting = false
				stroke_finished.emit()
		accept_event()
		return
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		var world_position := screen_to_world(mouse_event.position)
		if world_position.x >= 0.0:
			var cell := MapModel.world_to_cell(map_data, world_position)
			canvas_action.emit(world_position, cell, active_tool, false)
			accept_event()


func is_paint_tool(tool: String) -> bool:
	return tool in ["terrain_paint", "collision_paint", "navigation_paint"]


func emit_paint_action(screen_position: Vector2) -> void:
	var world_position := screen_to_world(screen_position)
	if world_position.x < 0.0:
		return
	var cell := MapModel.world_to_cell(map_data, world_position)
	if cell == last_painted_cell or not MapModel.cell_is_inside(map_data, cell):
		return
	last_painted_cell = cell
	canvas_action.emit(MapModel.cell_to_world(map_data, cell), cell, active_tool, erase_mode)


func screen_to_world(screen_position: Vector2) -> Vector2:
	if map_data.is_empty():
		return Vector2(-1, -1)
	var transform_data := view_transform()
	var zoom := float(transform_data.get("zoom", 1.0))
	var origin: Vector2 = transform_data.get("origin", Vector2.ZERO)
	var world_size: Vector2 = transform_data.get("world_size", Vector2(640, 360))
	var result := (screen_position - origin) / zoom
	if result.x < 0.0 or result.y < 0.0 or result.x > world_size.x or result.y > world_size.y:
		return Vector2(-1, -1)
	return result


func view_transform() -> Dictionary:
	var world_size_i := MapModel.canvas_size(map_data)
	var world_size := Vector2(world_size_i)
	var available := Vector2(maxf(1.0, size.x), maxf(1.0, size.y))
	var base_zoom := minf(available.x / world_size.x, available.y / world_size.y)
	var zoom := maxf(0.01, base_zoom * user_zoom)
	var origin := (available - world_size * zoom) * 0.5 + pan_offset
	return {"world_size": world_size, "zoom": zoom, "origin": origin}


func current_era() -> Dictionary:
	for value in map_data.get("eras", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var era: Dictionary = value
		if String(era.get("id", "")) == era_id:
			return era
	for value in map_data.get("eras", []):
		if typeof(value) == TYPE_DICTIONARY:
			return value
	return {}


func palette_color(key: String, fallback: String) -> Color:
	var era: Dictionary = current_era()
	var palette: Dictionary = era.get("palette", {})
	return Color.from_string(String(palette.get(key, fallback)), Color.from_string(fallback, Color.WHITE))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("15191f"))
	if map_data.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(24, 42), "Select or create a map to begin.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("aeb8c2"))
		return
	var transform_data := view_transform()
	var world_size: Vector2 = transform_data.get("world_size", Vector2(640, 360))
	var zoom := float(transform_data.get("zoom", 1.0))
	var origin: Vector2 = transform_data.get("origin", Vector2.ZERO)
	draw_set_transform(origin, 0.0, Vector2.ONE * zoom)
	draw_rect(Rect2(Vector2.ZERO, world_size), palette_color("sky", "819a91"))
	var bounds: Dictionary = map_data.get("bounds", {})
	var ground_top := float(bounds.get("top", 96.0))
	draw_rect(Rect2(0, ground_top, world_size.x, world_size.y - ground_top), palette_color("ground", "4f6550"))
	draw_terrain_cells()
	var era: Dictionary = current_era()
	for value in era.get("landmarks", []):
		if typeof(value) == TYPE_DICTIONARY:
			draw_landmark(value)
	draw_grid(world_size)
	if show_navigation:
		draw_cell_overlay(MapModel.NAVIGATION_CELLS, Color(0.25, 0.85, 0.8, 0.28), Color(0.35, 1.0, 0.92, 0.72))
	if show_collision:
		draw_cell_overlay(MapModel.COLLISION_CELLS, Color(0.95, 0.24, 0.32, 0.35), Color(1.0, 0.42, 0.46, 0.8))
	draw_spawns()
	if show_markers:
		draw_world_markers()
	draw_rect(
		Rect2(
			float(bounds.get("left", 0)),
			float(bounds.get("top", 0)),
			float(bounds.get("right", world_size.x)) - float(bounds.get("left", 0)),
			float(bounds.get("bottom", world_size.y)) - float(bounds.get("top", 0))
		),
		Color(1.0, 0.88, 0.45, 0.55),
		false,
		2.0
	)
	if is_paint_tool(active_tool) and hover_cell.x >= 0 and MapModel.cell_is_inside(map_data, hover_cell):
		draw_rect(MapModel.cell_rect(map_data, hover_cell), Color(1.0, 1.0, 1.0, 0.24), false, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(8, size.y - 27, 430, 20), Color(0.03, 0.04, 0.05, 0.82))
	var coordinate_text := ""
	if hover_cell.x >= 0:
		coordinate_text = "  CELL %d,%d" % [hover_cell.x, hover_cell.y]
	draw_string(
		ThemeDB.fallback_font,
		Vector2(16, size.y - 13),
		"LMB PAINT/PLACE  RMB ERASE  MMB PAN  WHEEL ZOOM%s" % coordinate_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("c4cbd0")
	)


func draw_terrain_cells() -> void:
	var fallback := palette_color("ground", "4f6550")
	for value in MapModel.resolved_cells(map_data, MapModel.TERRAIN_CELLS, era_id):
		var record: Dictionary = value
		var cell := Vector2i(int(record.get("x", -1)), int(record.get("y", -1)))
		var tile_id := String(record.get("tile", ""))
		var rect := MapModel.cell_rect(map_data, cell)
		var color := MapModel.terrain_color(map_data, tile_id, era_id, fallback)
		draw_rect(rect, color)
		if MapModel.terrain_is_blocked(map_data, tile_id):
			draw_line(rect.position + Vector2(2, 2), rect.end - Vector2(2, 2), Color(0.1, 0.08, 0.08, 0.45), 1.0)
			draw_line(rect.position + Vector2(rect.size.x - 2, 2), rect.position + Vector2(2, rect.size.y - 2), Color(0.1, 0.08, 0.08, 0.45), 1.0)


func draw_cell_overlay(collection: String, fill: Color, outline: Color) -> void:
	for value in MapModel.resolved_cells(map_data, collection, era_id):
		var record: Dictionary = value
		var cell := Vector2i(int(record.get("x", -1)), int(record.get("y", -1)))
		var rect := MapModel.cell_rect(map_data, cell)
		draw_rect(rect, fill)
		draw_rect(rect.grow(-1.0), outline, false, 1.0)


func draw_grid(world_size: Vector2) -> void:
	var cell_size := MapModel.grid_size(map_data)
	var grid_color := Color(1.0, 1.0, 1.0, 0.08)
	for x in range(0, int(world_size.x) + 1, cell_size):
		draw_line(Vector2(x, 0), Vector2(x, world_size.y), grid_color, 1.0)
	for y in range(0, int(world_size.y) + 1, cell_size):
		draw_line(Vector2(0, y), Vector2(world_size.x, y), grid_color, 1.0)


func draw_spawns() -> void:
	var spawns: Dictionary = map_data.get("spawns", {})
	var player := Repository.data_to_vector(spawns.get("player"), Vector2.ZERO)
	var companion := Repository.data_to_vector(spawns.get("companion"), Vector2.ZERO)
	draw_circle(player, 9.0, Color("5ec8ff"))
	draw_circle(player, 15.0, Color("5ec8ff"), false, 2.0)
	draw_circle(companion, 8.0, Color("e4a968"))
	draw_circle(companion, 14.0, Color("e4a968"), false, 2.0)


func draw_world_markers() -> void:
	for value in map_data.get("interactions", []):
		if typeof(value) == TYPE_DICTIONARY:
			draw_interaction(value)
	for value in map_data.get("connections", []):
		if typeof(value) == TYPE_DICTIONARY:
			draw_connection(value)
	for value in map_data.get("entry_points", []):
		if typeof(value) == TYPE_DICTIONARY:
			draw_entry(value)
	for value in map_data.get("recovery_anchors", []):
		if typeof(value) == TYPE_DICTIONARY:
			draw_recovery(value)


func draw_interaction(interaction: Dictionary) -> void:
	var position := Repository.data_to_vector(interaction.get("position"), Vector2.ZERO)
	var identifier := String(interaction.get("id", "interaction"))
	var selected := selected_marker_kind == "interaction" and selected_marker_id == identifier
	draw_circle(position, 7.0, Color("f5df71") if selected else Color("d2b95d"))
	draw_circle(position, float(interaction.get("radius", 32.0)), Color(1.0, 0.86, 0.36, 0.22), false, 1.0)
	draw_marker_label(position, identifier, Color("fff1b8"))


func draw_connection(connection: Dictionary) -> void:
	var position := Repository.data_to_vector(connection.get("position"), Vector2.ZERO)
	var identifier := String(connection.get("id", "connection"))
	var selected := selected_marker_kind == "connection" and selected_marker_id == identifier
	var color := Color("f48f62") if selected else Color("ce765a")
	draw_circle(position, 9.0, color, false, 3.0)
	draw_circle(position, float(connection.get("radius", 24.0)), Color(0.96, 0.48, 0.32, 0.2), false, 1.0)
	draw_marker_label(position, "%s → %s" % [identifier, connection.get("target_map", "map")], Color("ffd0bd"))


func draw_entry(entry: Dictionary) -> void:
	var position := Repository.data_to_vector(entry.get("player"), Vector2.ZERO)
	var identifier := String(entry.get("id", "entry"))
	var selected := selected_marker_kind == "entry" and selected_marker_id == identifier
	var color := Color("8ff2bd") if selected else Color("64bc91")
	draw_colored_polygon(PackedVector2Array([
		position + Vector2(0, -9), position + Vector2(9, 0),
		position + Vector2(0, 9), position + Vector2(-9, 0)
	]), color)
	draw_marker_label(position, identifier, Color("c9ffe1"))


func draw_recovery(anchor: Dictionary) -> void:
	var position := Repository.data_to_vector(anchor.get("position"), Vector2.ZERO)
	var identifier := String(anchor.get("id", "recovery"))
	var selected := selected_marker_kind == "recovery" and selected_marker_id == identifier
	var color := Color("b8a4ff") if selected else Color("8774cf")
	draw_line(position + Vector2(-7, 0), position + Vector2(7, 0), color, 3.0)
	draw_line(position + Vector2(0, -7), position + Vector2(0, 7), color, 3.0)
	draw_marker_label(position, identifier, Color("ded6ff"))


func draw_marker_label(position: Vector2, text: String, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, position + Vector2(11, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)


func draw_landmark(landmark: Dictionary) -> void:
	var position := Repository.data_to_vector(landmark.get("position"), Vector2.ZERO)
	var size_value := float(landmark.get("size", 24.0))
	var kind := String(landmark.get("kind", "marker"))
	var accent := palette_color("accent", "e5d89f")
	var structure := palette_color("structure", "53625b")
	match kind:
		"sun":
			draw_circle(position, size_value, accent)
		"ruin":
			draw_rect(Rect2(position - Vector2(size_value * 0.5, size_value * 0.72), Vector2(size_value, size_value * 1.44)), structure)
			draw_rect(Rect2(position - Vector2(size_value * 0.18, size_value * 0.35), Vector2(size_value * 0.36, size_value * 0.7)), Color("1a2021"))
		"well":
			draw_circle(position + Vector2(0, 4), size_value, Color("313b3b"))
			draw_circle(position, size_value * 0.78, Color("10181b"))
		"tree":
			draw_line(position + Vector2(0, size_value), position - Vector2(0, size_value), structure, 6.0)
			draw_circle(position - Vector2(0, size_value * 0.55), size_value * 0.74, Color("3f5945"))
		"dead_tree":
			draw_line(position + Vector2(0, size_value), position - Vector2(0, size_value), structure, 5.0)
			draw_line(position, position + Vector2(size_value * 0.7, -size_value), structure, 3.0)
			draw_line(position, position + Vector2(-size_value * 0.7, -size_value * 0.8), structure, 3.0)
		_:
			draw_circle(position, maxf(4.0, size_value * 0.25), accent)
