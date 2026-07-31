extends "res://src/sprite_animation_polish_overlay.gd"

const FeedbackRepository = preload("res://src/content/campaign_repository.gd")
const FeedbackMapModel = preload("res://src/content/map_model.gd")
const FeedbackEncounterModel = preload("res://src/game/encounter_model.gd")

const FEEDBACK_FLOW_GAME := 4
const FEEDBACK_FLOW_PAUSED := 5
const FEEDBACK_VIEW := Vector2(640, 360)
const AREA_BANNER_DURATION := 2.4
const AREA_BANNER_FADE_IN := 0.24
const AREA_BANNER_FADE_OUT := 0.55
const PROMPT_FADE_SPEED := 9.0
const PROMPT_VERTICAL_OFFSET := 31.0

var feedback_last_flow := -1
var feedback_last_map_key := ""
var area_banner_timer := 0.0
var area_banner_title := ""
var area_banner_subtitle := ""
var context_prompt: Dictionary = {}
var context_prompt_alpha := 0.0
var context_prompt_target_key := ""


func _process(delta: float) -> void:
	super._process(delta)
	update_adventure_feedback(delta)
	queue_redraw()


func update_adventure_feedback(delta: float) -> void:
	var current_flow := runtime_flow()
	var in_world := current_flow == FEEDBACK_FLOW_GAME or current_flow == FEEDBACK_FLOW_PAUSED
	var map_key := current_feedback_map_key()
	var entering_game := (
		current_flow == FEEDBACK_FLOW_GAME
		and feedback_last_flow != FEEDBACK_FLOW_GAME
		and feedback_last_flow != FEEDBACK_FLOW_PAUSED
	)
	if in_world:
		if entering_game or (
			not feedback_last_map_key.is_empty()
			and not map_key.is_empty()
			and map_key != feedback_last_map_key
		):
			announce_current_area()
		if not map_key.is_empty():
			feedback_last_map_key = map_key

	var presentation_active := (
		current_flow == FEEDBACK_FLOW_GAME
		and not animation_should_freeze()
		and active_cinematic_id().is_empty()
	)
	if presentation_active and runtime_number("transition_lock", 0.0) <= 0.15:
		area_banner_timer = maxf(0.0, area_banner_timer - delta)
	var prompt_active := (
		presentation_active
		and runtime_string("dialogue").is_empty()
		and runtime_number("transition_lock", 0.0) <= 0.0
	)
	if prompt_active:
		var next_prompt := resolve_context_prompt()
		if not next_prompt.is_empty():
			var next_key := str(next_prompt.get("key", ""))
			if next_key != context_prompt_target_key:
				context_prompt_alpha = minf(context_prompt_alpha, 0.32)
			context_prompt = next_prompt
			context_prompt_target_key = next_key
			context_prompt_alpha = move_toward(context_prompt_alpha, 1.0, delta * PROMPT_FADE_SPEED)
		else:
			fade_context_prompt(delta)
	else:
		fade_context_prompt(delta)
	feedback_last_flow = current_flow


func fade_context_prompt(delta: float) -> void:
	context_prompt_alpha = move_toward(context_prompt_alpha, 0.0, delta * PROMPT_FADE_SPEED)
	if context_prompt_alpha <= 0.01:
		context_prompt.clear()
		context_prompt_target_key = ""


func current_feedback_map_key() -> String:
	var map_data := runtime_map_data()
	var map_id := str(map_data.get("id", ""))
	if map_id.is_empty():
		return ""
	return "%s|%s" % [map_id, runtime_string("current_era_id")]


func announce_current_area() -> void:
	var map_data := runtime_map_data()
	var map_id := str(map_data.get("id", ""))
	if map_id.is_empty():
		return
	area_banner_title = str(map_data.get("display_name", map_id.replace("_", " ").capitalize())).to_upper()
	area_banner_subtitle = runtime_era_name().to_upper()
	area_banner_timer = AREA_BANNER_DURATION


func draw_game_finish() -> void:
	super.draw_game_finish()
	draw_area_banner()
	draw_context_prompt()


func feedback_draw_allowed() -> bool:
	return (
		runtime_flow() == FEEDBACK_FLOW_GAME
		and not animation_should_freeze()
		and active_cinematic_id().is_empty()
	)


func draw_area_banner() -> void:
	if not feedback_draw_allowed():
		return
	if area_banner_timer <= 0.0 or area_banner_title.is_empty():
		return
	if runtime_number("transition_lock", 0.0) > 0.35:
		return
	var elapsed_time := AREA_BANNER_DURATION - area_banner_timer
	var alpha := minf(
		1.0,
		minf(
			elapsed_time / AREA_BANNER_FADE_IN,
			area_banner_timer / AREA_BANNER_FADE_OUT
		)
	)
	alpha = clampf(alpha, 0.0, 1.0)
	var center_x := FEEDBACK_VIEW.x * 0.5
	var frame := profile_color("ui_frame", "9f8651")
	var text := profile_color("ui_text", "eee3c6")
	var fill := profile_color("ui_fill", "15191b")
	var rect := Rect2(center_x - 142.0, 39.0, 284.0, 42.0)
	draw_rect(rect, Color(fill, 0.88 * alpha))
	draw_line(Vector2(rect.position.x + 10.0, rect.position.y + 6.0), Vector2(rect.end.x - 10.0, rect.position.y + 6.0), Color(frame, 0.72 * alpha), 1.0)
	draw_line(Vector2(rect.position.x + 10.0, rect.end.y - 6.0), Vector2(rect.end.x - 10.0, rect.end.y - 6.0), Color(frame, 0.42 * alpha), 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(rect.position.x + 8.0, rect.position.y + 23.0),
		area_banner_title,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(rect.size.x - 16.0),
		12,
		Color(text, alpha)
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(rect.position.x + 8.0, rect.position.y + 35.0),
		area_banner_subtitle,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(rect.size.x - 16.0),
		7,
		Color(frame, 0.88 * alpha)
	)


func draw_context_prompt() -> void:
	if not feedback_draw_allowed():
		return
	if not runtime_string("dialogue").is_empty() or runtime_number("transition_lock", 0.0) > 0.0:
		return
	if context_prompt_alpha <= 0.01 or context_prompt.is_empty():
		return
	var world_position_value: Variant = context_prompt.get("position", Vector2.ZERO)
	var world_position: Vector2 = world_position_value if world_position_value is Vector2 else Vector2.ZERO
	var screen_position := world_to_screen(world_position)
	var bob := roundf(sin(Time.get_ticks_msec() * 0.008) * 2.0)
	var target_y := clampf(screen_position.y - PROMPT_VERTICAL_OFFSET + bob, 92.0, FEEDBACK_VIEW.y - 76.0)
	var action := str(context_prompt.get("action", "USE"))
	var target_name := str(context_prompt.get("target_name", ""))
	var enabled := bool(context_prompt.get("enabled", true))
	var frame := profile_color("ui_frame", "9f8651") if enabled else profile_color("danger", "b94d45")
	var text := profile_color("ui_text", "eee3c6")
	var fill := profile_color("ui_fill", "15191b")
	var label := "E / A  %s" % action
	var label_width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	var name_width := ThemeDB.fallback_font.get_string_size(target_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	var width := clampf(maxf(label_width, name_width) + 24.0, 82.0, 190.0)
	var height := 30.0 if not target_name.is_empty() else 22.0
	var left := clampf(screen_position.x - width * 0.5, 8.0, FEEDBACK_VIEW.x - width - 8.0)
	var rect := Rect2(left, target_y - height, width, height)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(screen_position.x - 4.0, target_y),
			Vector2(screen_position.x + 4.0, target_y),
			Vector2(screen_position.x, target_y + 5.0)
		]),
		Color(frame, 0.94 * context_prompt_alpha)
	)
	draw_rect(rect, Color(fill, 0.94 * context_prompt_alpha))
	draw_rect(rect, Color(frame, 0.92 * context_prompt_alpha), false, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(rect.position.x + 8.0, rect.position.y + 14.0),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(rect.size.x - 16.0),
		9,
		Color(text, context_prompt_alpha)
	)
	if not target_name.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(rect.position.x + 8.0, rect.position.y + 25.0),
			target_name.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER,
			int(rect.size.x - 16.0),
			7,
			Color(frame, 0.82 * context_prompt_alpha)
		)


func resolve_context_prompt() -> Dictionary:
	var runtime := runtime_root()
	if runtime == null:
		return {}
	var player_position := runtime_vector("player")
	var best: Dictionary = {}
	best = choose_prompt(best, nearest_entity_prompt(player_position))
	best = choose_prompt(best, nearest_connection_prompt(player_position))
	best = choose_prompt(best, nearest_map_interaction_prompt(player_position))
	return best


func nearest_entity_prompt(player_position: Vector2) -> Dictionary:
	var best: Dictionary = {}
	for entity_value in runtime_array("runtime_entities"):
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value as Dictionary
		if not bool(entity.get("active", true)):
			continue
		var kind := FeedbackEncounterModel.kind(entity)
		if kind != "npc" and kind != "prop":
			continue
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var distance := player_position.distance_to(position)
		var radius := maxf(20.0, FeedbackEncounterModel.interaction_radius(entity))
		if distance > radius:
			continue
		var definition_value: Variant = entity.get("definition", {})
		var definition: Dictionary = definition_value as Dictionary if typeof(definition_value) == TYPE_DICTIONARY else {}
		var action := "TALK" if kind == "npc" else "EXAMINE"
		if kind == "npc" and (definition.has("merchant_id") or definition.has("merchant")):
			action = "TRADE"
		var placement_id := str(entity.get("placement_id", entity.get("state_key", "entity")))
		var display_name := str(definition.get("display_name", kind.capitalize()))
		best = choose_prompt(best, make_prompt(
			"entity:%s" % placement_id,
			action,
			display_name,
			position,
			distance,
			true
		))
	return best


func nearest_connection_prompt(player_position: Vector2) -> Dictionary:
	var map_data := runtime_map_data()
	var connection := FeedbackMapModel.find_connection_near(
		map_data,
		player_position,
		runtime_string("current_era_id"),
		"interact"
	)
	if connection.is_empty():
		return {}
	var position := FeedbackRepository.data_to_vector(connection.get("position"), player_position)
	var enabled := authored_requirements_met(connection)
	var target_name := str(connection.get("display_name", connection.get("label", "Passage")))
	return make_prompt(
		"connection:%s" % str(connection.get("id", connection.get("target_map", "passage"))),
		"ENTER" if enabled else "LOCKED",
		target_name,
		position,
		player_position.distance_to(position),
		enabled
	)


func nearest_map_interaction_prompt(player_position: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var map_data := runtime_map_data()
	var era_id := runtime_string("current_era_id")
	var interactions_value: Variant = map_data.get("interactions", [])
	if typeof(interactions_value) != TYPE_ARRAY:
		return best
	for interaction_value in interactions_value as Array:
		if typeof(interaction_value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = interaction_value as Dictionary
		if not FeedbackMapModel.available_in_era(interaction, era_id):
			continue
		var position := FeedbackRepository.data_to_vector(interaction.get("position"), Vector2.ZERO)
		var distance := player_position.distance_to(position)
		var radius := maxf(20.0, float(interaction.get("radius", 32.0)))
		if distance > radius:
			continue
		var enabled := authored_requirements_met(interaction)
		var action := str(interaction.get("prompt_action", "USE")).strip_edges().to_upper()
		if action.is_empty():
			action = "USE"
		if not enabled:
			action = "LOCKED"
		var interaction_id := str(interaction.get("id", "interaction"))
		var target_name := str(interaction.get("display_name", interaction_id.replace("_", " ").capitalize()))
		best = choose_prompt(best, make_prompt(
			"interaction:%s" % interaction_id,
			action,
			target_name,
			position,
			distance,
			enabled
		))
	return best


func authored_requirements_met(record: Dictionary) -> bool:
	var runtime := runtime_root()
	if runtime != null and runtime.has_method("authored_requirements_met"):
		return bool(runtime.call("authored_requirements_met", record))
	return true


func make_prompt(
	key: String,
	action: String,
	target_name: String,
	position: Vector2,
	distance: float,
	enabled: bool
) -> Dictionary:
	return {
		"key": key,
		"action": action,
		"target_name": target_name,
		"position": position,
		"distance": distance,
		"enabled": enabled
	}


func choose_prompt(current: Dictionary, candidate: Dictionary) -> Dictionary:
	if candidate.is_empty():
		return current
	if current.is_empty() or float(candidate.get("distance", INF)) < float(current.get("distance", INF)):
		return candidate
	return current


func runtime_map_data() -> Dictionary:
	var runtime := runtime_root()
	if runtime == null:
		return {}
	var value: Variant = runtime.get("map_data")
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func context_prompt_snapshot() -> Dictionary:
	return resolve_context_prompt().duplicate(true)


func adventure_feedback_contract_ok() -> bool:
	return (
		animation_polish_contract_ok()
		and AREA_BANNER_DURATION > AREA_BANNER_FADE_IN + AREA_BANNER_FADE_OUT
		and PROMPT_FADE_SPEED > 0.0
	)
