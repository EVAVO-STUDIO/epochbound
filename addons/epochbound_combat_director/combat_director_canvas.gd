@tool
extends "res://addons/epochbound_encounter_studio/encounter_canvas.gd"

const EncounterZoneModel = preload("res://src/game/encounter_zone_model.gd")

var selected_zone_id := ""


func set_selected_zone(identifier: String) -> void:
	selected_zone_id = identifier
	queue_redraw()


func _draw() -> void:
	super._draw()
	if map_data.is_empty():
		return
	var transform_data := view_transform()
	var zoom := float(transform_data.get("zoom", 1.0))
	var origin: Vector2 = transform_data.get("origin", Vector2.ZERO)
	draw_set_transform(origin, 0.0, Vector2.ONE * zoom)
	for value in EncounterZoneModel.available_zones(map_data, era_id):
		if typeof(value) == TYPE_DICTIONARY:
			draw_zone(value)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(8, 8, 174, 24), Color(0.03, 0.04, 0.05, 0.86))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 25),
		"ENCOUNTER ZONES",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("efc96f")
	)


func draw_zone(zone: Dictionary) -> void:
	var position := EncounterZoneModel.center(zone)
	var zone_radius := EncounterZoneModel.radius(zone)
	var activation := EncounterZoneModel.activation_radius(zone)
	var identifier := str(zone.get("id", "encounter"))
	var selected := identifier == selected_zone_id
	var fill := Color(0.85, 0.28, 0.18, 0.12) if not selected else Color(0.95, 0.62, 0.18, 0.2)
	var line := Color(0.9, 0.34, 0.22, 0.75) if not selected else Color("ffd77a")
	draw_circle(position, zone_radius, fill)
	draw_circle(position, zone_radius, line, false, 2.0 if selected else 1.0)
	draw_circle(position, activation, Color(0.95, 0.74, 0.26, 0.3), false, 1.0)
	draw_line(position + Vector2(-8, 0), position + Vector2(8, 0), line, 1.0)
	draw_line(position + Vector2(0, -8), position + Vector2(0, 8), line, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		position + Vector2(12, -12),
		identifier,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("fff1b8") if selected else Color("e7c6a4")
	)
