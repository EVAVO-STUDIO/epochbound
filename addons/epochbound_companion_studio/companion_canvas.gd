@tool
extends "res://addons/epochbound_encounter_studio/encounter_canvas.gd"

const CompanionModel = preload("res://src/game/companion_model.gd")

var selected_cue_id := ""


func set_selected_cue(identifier: String) -> void:
	selected_cue_id = identifier
	queue_redraw()


func _draw() -> void:
	super._draw()
	if map_data.is_empty():
		return
	var transform_data := view_transform()
	var zoom := float(transform_data.get("zoom", 1.0))
	var origin: Vector2 = transform_data.get("origin", Vector2.ZERO)
	draw_set_transform(origin, 0.0, Vector2.ONE * zoom)
	for value in CompanionModel.all_cues(map_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var cue: Dictionary = value
		if CompanionModel.cue_is_available(cue, era_id):
			draw_cue(cue)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(8, 8, 178, 24), Color(0.03, 0.04, 0.05, 0.86))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(18, 25),
		"COMPANION CUES",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("e7ce77")
	)


func draw_cue(cue: Dictionary) -> void:
	var position := CompanionModel.cue_position(cue)
	var radius := CompanionModel.cue_radius(cue)
	var identifier := str(cue.get("id", "cue"))
	var selected := identifier == selected_cue_id
	var kind := str(cue.get("kind", "clue"))
	var color := cue_color(kind)
	draw_circle(position, radius, Color(color, 0.12))
	draw_circle(position, radius, Color("fff0a8") if selected else color, false, 3.0 if selected else 1.5)
	draw_line(position + Vector2(-7, 0), position + Vector2(7, 0), color, 1.0)
	draw_line(position + Vector2(0, -7), position + Vector2(0, 7), color, 1.0)
	if not bool(cue.get("visible_before_discovery", false)):
		draw_circle(position + Vector2(0, -radius - 5), 2.5, Color("8e969d"))
	draw_string(
		ThemeDB.fallback_font,
		position + Vector2(12, -12),
		identifier,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		Color("fff2bd") if selected else Color("d7dbe0")
	)


func cue_color(kind: String) -> Color:
	match kind:
		"resource":
			return Color("8fcb8b")
		"trail":
			return Color("8eb8db")
		"warning":
			return Color("df755f")
		_:
			return Color("e4c66b")
