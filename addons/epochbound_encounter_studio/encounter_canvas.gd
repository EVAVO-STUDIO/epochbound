@tool
extends "res://addons/epochbound_campaign_studio/map_canvas.gd"

const EncounterRepository = preload("res://src/content/campaign_repository.gd")
const EncounterCatalog = preload("res://src/content/object_catalog.gd")

var object_definitions: Dictionary = {}
var selected_placement_id := ""


func set_encounter_data(definitions: Dictionary, selected_id: String = "") -> void:
	object_definitions = definitions
	selected_placement_id = selected_id
	queue_redraw()


func set_selected_placement(identifier: String) -> void:
	selected_placement_id = identifier
	queue_redraw()


func _draw() -> void:
	super._draw()
	if map_data.is_empty():
		return
	var transform_data := view_transform()
	var zoom := float(transform_data.get("zoom", 1.0))
	var origin: Vector2 = transform_data.get("origin", Vector2.ZERO)
	draw_set_transform(origin, 0.0, Vector2.ONE * zoom)
	for value in map_data.get("object_placements", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = value
		if not EncounterCatalog.placement_is_available(placement, era_id):
			continue
		draw_placement(placement)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(size.x - 196, 8, 188, 24), Color(0.03, 0.04, 0.05, 0.86))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 186, 25),
		"OBJECT PLACEMENTS",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("e5d291")
	)


func draw_placement(placement: Dictionary) -> void:
	var object_id := String(placement.get("object_id", ""))
	var definition_data := EncounterCatalog.definition(object_definitions, object_id)
	var position := EncounterRepository.data_to_vector(placement.get("position"), Vector2.ZERO)
	var identifier := String(placement.get("id", "placement"))
	var selected := identifier == selected_placement_id
	var color := EncounterCatalog.appearance_color(definition_data, "color", "66717a")
	var accent := EncounterCatalog.appearance_color(definition_data, "accent", "e5d291")
	var appearance: Dictionary = definition_data.get("appearance", {})
	var shape := String(appearance.get("shape", "marker"))
	var kind := String(definition_data.get("kind", "prop"))
	match shape:
		"crate":
			draw_rect(Rect2(position - Vector2(11, 9), Vector2(22, 18)), color)
			draw_rect(Rect2(position - Vector2(9, 7), Vector2(18, 14)), accent, false, 2.0)
			draw_line(position + Vector2(-9, -7), position + Vector2(9, 7), accent.darkened(0.25), 1.0)
		"person":
			draw_circle(position + Vector2(0, -9), 6, accent)
			draw_rect(Rect2(position + Vector2(-7, -3), Vector2(14, 19)), color)
		"beast":
			draw_circle(position + Vector2(-3, 0), 9, color)
			draw_circle(position + Vector2(7, -5), 6, accent)
			draw_line(position + Vector2(-10, -2), position + Vector2(-17, -8), color, 3.0)
		"orb":
			draw_circle(position, 7, color)
			draw_circle(position, 11, Color(accent, 0.55), false, 2.0)
		"pillar":
			draw_rect(Rect2(position - Vector2(7, 15), Vector2(14, 30)), color)
			draw_rect(Rect2(position - Vector2(10, 17), Vector2(20, 4)), accent)
		_:
			draw_circle(position, 8, color)
	if bool(definition_data.get("solid", false)):
		draw_circle(
			position,
			float(definition_data.get("collision_radius", 8.0)),
			Color(0.98, 0.3, 0.32, 0.28),
			false,
			1.0
		)
	if kind == "enemy":
		draw_circle(position, 16, Color(0.95, 0.25, 0.2, 0.45), false, 2.0)
	elif kind == "pickup":
		draw_line(position + Vector2(-13, 0), position + Vector2(13, 0), accent, 1.0)
		draw_line(position + Vector2(0, -13), position + Vector2(0, 13), accent, 1.0)
	if selected:
		draw_circle(position, 21, Color("fff0a8"), false, 3.0)
	draw_string(
		ThemeDB.fallback_font,
		position + Vector2(13, -13),
		identifier,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("fff2bd") if selected else Color("d7dbe0")
	)
