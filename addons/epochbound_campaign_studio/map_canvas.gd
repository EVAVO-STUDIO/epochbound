@tool
extends Control

signal canvas_clicked(world_position: Vector2, tool: String)

const Repository = preload("res://src/content/campaign_repository.gd")

var map_data: Dictionary = {}
var era_id := ""
var active_tool := "select"
var selected_interaction_id := ""

func _ready() -> void:
	custom_minimum_size = Vector2(640, 360)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func set_map_data(value: Dictionary) -> void:
	map_data = value
	if era_id.is_empty():
		era_id = first_era_id()
	queue_redraw()

func set_era(value: String) -> void:
	era_id = value
	queue_redraw()

func set_tool(value: String) -> void:
	active_tool = value

func set_selected_interaction(value: String) -> void:
	selected_interaction_id = value
	queue_redraw()

func first_era_id() -> String:
	for era in map_data.get("eras", []):
		return String(era.get("id", ""))
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_position := screen_to_world(event.position)
			if world_position.x >= 0.0 and world_position.y >= 0.0:
				canvas_clicked.emit(snap_to_grid(world_position), active_tool)
				accept_event()

func snap_to_grid(value: Vector2) -> Vector2:
	var canvas: Dictionary = map_data.get("canvas", {})
	var grid_size := maxf(1.0, float(canvas.get("grid_size", 16)))
	return Vector2(roundf(value.x / grid_size) * grid_size, roundf(value.y / grid_size) * grid_size)

func screen_to_world(screen_position: Vector2) -> Vector2:
	var transform_data := view_transform()
	var zoom := float(transform_data.get("zoom", 1.0))
	var origin: Vector2 = transform_data.get("origin", Vector2.ZERO)
	var world_size: Vector2 = transform_data.get("world_size", Vector2(640, 360))
	var result := (screen_position - origin) / zoom
	if result.x < 0.0 or result.y < 0.0 or result.x > world_size.x or result.y > world_size.y:
		return Vector2(-1, -1)
	return result

func view_transform() -> Dictionary:
	var canvas: Dictionary = map_data.get("canvas", {})
	var world_size := Vector2(float(canvas.get("width", 640)), float(canvas.get("height", 360)))
	var available := Vector2(maxf(1.0, size.x), maxf(1.0, size.y))
	var zoom := minf(available.x / world_size.x, available.y / world_size.y)
	var origin := (available - world_size * zoom) * 0.5
	return {"world_size": world_size, "zoom": zoom, "origin": origin}

func current_era() -> Dictionary:
	for era in map_data.get("eras", []):
		if String(era.get("id", "")) == era_id:
			return era
	for era in map_data.get("eras", []):
		return era
	return {}

func palette_color(key: String, fallback: String) -> Color:
	var era: Dictionary = current_era()
	var palette: Dictionary = era.get("palette", {})
	return Color(String(palette.get(key, fallback)))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("15191f"))
	if map_data.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(24, 42),
			"Select or create a map to begin.",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color("aeb8c2")
		)
		return
	var transform_data := view_transform()
	var world_size: Vector2 = transform_data.get("world_size", Vector2(640, 360))
	var zoom := float(transform_data.get("zoom", 1.0))
	var origin: Vector2 = transform_data.get("origin", Vector2.ZERO)
	draw_set_transform(origin, 0.0, Vector2.ONE * zoom)
	draw_rect(Rect2(Vector2.ZERO, world_size), palette_color("sky", "819a91"))
	var bounds: Dictionary = map_data.get("bounds", {})
	var ground_top := float(bounds.get("top", 96.0))
	draw_rect(
		Rect2(0, ground_top, world_size.x, world_size.y - ground_top),
		palette_color("ground", "4f6550")
	)
	draw_grid(world_size)
	for landmark in current_era().get("landmarks", []):
		draw_landmark(landmark)
	draw_spawns()
	draw_interactions()
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_grid(world_size: Vector2) -> void:
	var canvas: Dictionary = map_data.get("canvas", {})
	var grid_size := maxi(1, int(canvas.get("grid_size", 16)))
	var grid_color := Color(1.0, 1.0, 1.0, 0.08)
	for x in range(0, int(world_size.x) + 1, grid_size):
		draw_line(Vector2(x, 0), Vector2(x, world_size.y), grid_color, 1.0)
	for y in range(0, int(world_size.y) + 1, grid_size):
		draw_line(Vector2(0, y), Vector2(world_size.x, y), grid_color, 1.0)

func draw_spawns() -> void:
	var spawns: Dictionary = map_data.get("spawns", {})
	var player := Repository.data_to_vector(spawns.get("player"), Vector2.ZERO)
	var companion := Repository.data_to_vector(spawns.get("companion"), Vector2.ZERO)
	draw_circle(player, 9.0, Color("5ec8ff"))
	draw_circle(player, 15.0, Color("5ec8ff"), false, 2.0)
	draw_circle(companion, 8.0, Color("e4a968"))
	draw_circle(companion, 14.0, Color("e4a968"), false, 2.0)

func draw_interactions() -> void:
	for interaction in map_data.get("interactions", []):
		var position := Repository.data_to_vector(interaction.get("position"), Vector2.ZERO)
		var interaction_id := String(interaction.get("id", "interaction"))
		var selected := interaction_id == selected_interaction_id
		draw_circle(position, 7.0, Color("f5df71") if selected else Color("d2b95d"))
		draw_circle(position, float(interaction.get("radius", 32.0)), Color(1.0, 0.86, 0.36, 0.22), false, 1.0)
		draw_string(
			ThemeDB.fallback_font,
			position + Vector2(11, -8),
			interaction_id,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			Color("fff1b8")
		)

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
			draw_rect(
				Rect2(position - Vector2(size_value * 0.5, size_value * 0.72), Vector2(size_value, size_value * 1.44)),
				structure
			)
			draw_rect(
				Rect2(position - Vector2(size_value * 0.18, size_value * 0.35), Vector2(size_value * 0.36, size_value * 0.7)),
				Color("1a2021")
			)
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
