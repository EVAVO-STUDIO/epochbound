extends "res://src/boss_runtime.gd"

const CinematicCatalog = preload("res://src/content/cinematic_catalog.gd")
const CinematicValidator = preload("res://src/content/cinematic_validator.gd")
const CinematicRepository = preload("res://src/content/campaign_repository.gd")
const CinematicObjectCatalog = preload("res://src/content/object_catalog.gd")
const CinematicMapModel = preload("res://src/content/map_model.gd")
const CinematicBossCatalog = preload("res://src/content/boss_catalog.gd")

const CINEMATIC_MAX_IMMEDIATE_STEPS := 64
const CINEMATIC_LETTERBOX_HEIGHT := 38.0
const CINEMATIC_NOTICE_DURATION := 1.2

var cinematic_definitions: Dictionary = {}
var active_cinematic_id := ""
var cinematic_step_index := -1
var cinematic_step: Dictionary = {}
var cinematic_step_timer := 0.0
var cinematic_step_duration := 0.0
var cinematic_step_started := false
var cinematic_skipped := false
var cinematic_speaker := ""
var cinematic_text := ""
var cinematic_fade_alpha := 0.0
var cinematic_camera_enabled := false
var cinematic_camera_position := Vector2.ZERO
var cinematic_camera_start := Vector2.ZERO
var cinematic_camera_target := Vector2.ZERO
var cinematic_camera_zoom := 1.0
var cinematic_camera_zoom_start := 1.0
var cinematic_camera_zoom_target := 1.0
var cinematic_actor_key := ""
var cinematic_actor_start := Vector2.ZERO
var cinematic_actor_target := Vector2.ZERO
var cinematic_notice := ""
var cinematic_notice_timer := 0.0


func load_campaign(path: String) -> bool:
	var validation := CinematicValidator.validate_campaign_path(path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		push_error("Cinematic validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	clear_cinematic_state()
	var loaded := super.load_campaign(path)
	if not loaded:
		return false
	return load_cinematic_catalogs()


func load_fallback_campaign() -> void:
	clear_cinematic_state()
	super.load_fallback_campaign()
	cinematic_definitions = definitions_from_catalog(CinematicCatalog.default_catalog())


func load_cinematic_catalogs() -> bool:
	var result := CinematicCatalog.load_catalogs(campaign_path, campaign)
	if not bool(result.get("ok", false)):
		load_error = format_errors(result.get("errors", []))
		push_error("Cinematic catalog load failed: %s" % load_error)
		return false
	cinematic_definitions = result.get("definitions", {})
	return true


func definitions_from_catalog(catalog: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for value in catalog.get("cinematics", []):
		if typeof(value) == TYPE_DICTIONARY:
			var sequence: Dictionary = value
			var cinematic_id := str(sequence.get("id", ""))
			if not cinematic_id.is_empty():
				output[cinematic_id] = sequence
	return output


func clear_cinematic_state() -> void:
	cinematic_definitions.clear()
	reset_active_cinematic()


func reset_active_cinematic() -> void:
	active_cinematic_id = ""
	cinematic_step_index = -1
	cinematic_step = {}
	cinematic_step_timer = 0.0
	cinematic_step_duration = 0.0
	cinematic_step_started = false
	cinematic_skipped = false
	cinematic_speaker = ""
	cinematic_text = ""
	cinematic_fade_alpha = 0.0
	cinematic_camera_enabled = false
	cinematic_camera_position = player
	cinematic_camera_start = player
	cinematic_camera_target = player
	cinematic_camera_zoom = 1.0
	cinematic_camera_zoom_start = 1.0
	cinematic_camera_zoom_target = 1.0
	cinematic_actor_key = ""
	cinematic_actor_start = Vector2.ZERO
	cinematic_actor_target = Vector2.ZERO


func begin_game() -> void:
	super.begin_game()
	var intro_id := str(campaign.get("intro_cinematic_id", "")).strip_edges()
	if not intro_id.is_empty():
		start_cinematic(intro_id)


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	if not active_cinematic_id.is_empty():
		finish_cinematic(true)
	return super.activate_map(map_id, entry_id, requested_era, use_transition)


func engage_boss(placement_id: String, object_id: String, definition_data: Dictionary, zone: Dictionary) -> void:
	super.engage_boss(placement_id, object_id, definition_data, zone)
	if flow != Flow.GAME:
		return
	var boss_record := CinematicBossCatalog.boss_record(definition_data)
	var cinematic_id := boss_cinematic_id(object_id, "intro_cinematic_id", boss_record)
	if not cinematic_id.is_empty():
		start_cinematic(cinematic_id)


func finalize_boss_outcomes() -> void:
	var pending: Array[Dictionary] = []
	for placement_id_value in boss_contexts.keys():
		var context_value: Variant = boss_contexts.get(placement_id_value, {})
		if typeof(context_value) != TYPE_DICTIONARY:
			continue
		var context: Dictionary = context_value
		var definition_data := context_definition(context)
		var outcome_key := str(context.get("outcome_state_key", CinematicBossCatalog.outcome_state_key(definition_data)))
		var boss_record := CinematicBossCatalog.boss_record(definition_data)
		var cinematic_id := boss_cinematic_id(str(context.get("object_id", "")), "defeat_cinematic_id", boss_record)
		if not cinematic_id.is_empty() and session_state.get(outcome_key) != "defeated":
			pending.append({"outcome_key": outcome_key, "cinematic_id": cinematic_id})
	super.finalize_boss_outcomes()
	if not active_cinematic_id.is_empty():
		return
	for record in pending:
		if session_state.get(str(record.get("outcome_key", ""))) == "defeated":
			start_cinematic(str(record.get("cinematic_id", "")), true)
			break


func boss_cinematic_id(object_id: String, field: String, boss_record: Dictionary) -> String:
	var authored := str(boss_record.get(field, "")).strip_edges()
	if not authored.is_empty():
		return authored
	var mapping_value: Variant = campaign.get("boss_cinematics", {})
	if typeof(mapping_value) != TYPE_DICTIONARY:
		return ""
	var record_value: Variant = (mapping_value as Dictionary).get(object_id, {})
	if typeof(record_value) != TYPE_DICTIONARY:
		return ""
	return str((record_value as Dictionary).get(field, "")).strip_edges()


func interact() -> void:
	if nearest_story_entity_index() < 0:
		var interaction := nearest_map_interaction()
		var cinematic_id := str(interaction.get("cinematic_id", "")).strip_edges()
		if not cinematic_id.is_empty():
			if not authored_requirements_met(interaction):
				dialogue = authored_blocked_message(interaction)
				return
			if not StoryModel.conditions_met(StoryCatalog.conditions(interaction, "story_conditions"), story_context()):
				dialogue = str(interaction.get("blocked_dialogue", "Nothing changes yet."))
				return
			if start_cinematic(cinematic_id):
				return
	super.interact()


func update_game(delta: float) -> void:
	cinematic_notice_timer = maxf(0.0, cinematic_notice_timer - delta)
	if cinematic_notice_timer <= 0.0:
		cinematic_notice = ""
	if not active_cinematic_id.is_empty():
		update_cinematic(delta)
		return
	super.update_game(delta)


func start_cinematic(cinematic_id: String, force: bool = false) -> bool:
	if cinematic_id.is_empty() or not active_cinematic_id.is_empty():
		return false
	var sequence := CinematicCatalog.cinematic(cinematic_definitions, cinematic_id)
	if sequence.is_empty():
		set_cinematic_notice("Cinematic '%s' is unavailable." % cinematic_id)
		return false
	if not force:
		if CinematicCatalog.map_id(sequence) != str(map_data.get("id", "")):
			return false
		if not CinematicCatalog.available_in_era(sequence, current_era_id):
			return false
		var completion_key := CinematicCatalog.completion_state_key(sequence)
		if CinematicCatalog.trigger_once(sequence) and not completion_key.is_empty() and session_state.has(completion_key):
			return false
	close_cinematic_conflicts()
	active_cinematic_id = cinematic_id
	cinematic_step_index = -1
	cinematic_skipped = false
	cinematic_camera_position = player
	cinematic_camera_start = player
	cinematic_camera_target = player
	cinematic_camera_zoom = 1.0
	cinematic_fade_alpha = 0.0
	advance_cinematic_step()
	return true


func close_cinematic_conflicts() -> void:
	inventory_open = false
	story_journal_open = false
	save_overlay_open = false
	merchant_open = false
	finish_conversation(false)
	dialogue = ""
	projectiles.clear()
	cancel_reload(false)
	player_attack_lock = maxf(player_attack_lock, 0.2)


func update_cinematic(delta: float) -> void:
	var sequence := active_cinematic()
	if sequence.is_empty():
		finish_cinematic(false)
		return
	if CinematicCatalog.is_skippable(sequence) and (Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause_game")):
		finish_cinematic(true)
		return
	if cinematic_step.is_empty():
		advance_cinematic_step()
		return
	var step_type := CinematicCatalog.step_type(cinematic_step)
	if step_type == "dialogue" and bool(cinematic_step.get("advance_on_confirm", true)):
		if confirm() or Input.is_action_just_pressed("attack"):
			advance_cinematic_step()
			return
	cinematic_step_timer = maxf(0.0, cinematic_step_timer - delta)
	var progress := 1.0
	if cinematic_step_duration > 0.0:
		progress = 1.0 - clampf(cinematic_step_timer / cinematic_step_duration, 0.0, 1.0)
	match step_type:
		"camera":
			cinematic_camera_position = cinematic_camera_start.lerp(cinematic_camera_target, progress)
			cinematic_camera_zoom = lerpf(cinematic_camera_zoom_start, cinematic_camera_zoom_target, progress)
		"move_actor":
			set_cinematic_actor_position(cinematic_actor_key, cinematic_actor_start.lerp(cinematic_actor_target, progress))
		"fade":
			var direction := str(cinematic_step.get("direction", "out"))
			cinematic_fade_alpha = progress if direction == "out" else 1.0 - progress
		_:
			pass
	if cinematic_step_timer <= 0.0:
		advance_cinematic_step()


func advance_cinematic_step() -> void:
	var sequence := active_cinematic()
	if sequence.is_empty():
		finish_cinematic(false)
		return
	var sequence_steps := CinematicCatalog.steps(sequence)
	var immediate_steps := 0
	while immediate_steps < CINEMATIC_MAX_IMMEDIATE_STEPS:
		cinematic_step_index += 1
		if cinematic_step_index >= sequence_steps.size():
			finish_cinematic(false)
			return
		var value: Variant = sequence_steps[cinematic_step_index]
		if typeof(value) != TYPE_DICTIONARY:
			immediate_steps += 1
			continue
		cinematic_step = value
		cinematic_step_duration = CinematicCatalog.step_duration(cinematic_step)
		cinematic_step_timer = cinematic_step_duration
		cinematic_step_started = true
		cinematic_speaker = ""
		cinematic_text = ""
		cinematic_actor_key = ""
		var step_type := CinematicCatalog.step_type(cinematic_step)
		match step_type:
			"wait":
				return
			"dialogue":
				cinematic_speaker = str(cinematic_step.get("speaker", "")).strip_edges()
				cinematic_text = CinematicCatalog.step_text(cinematic_step, current_era_id)
				if cinematic_step_duration <= 0.0 and bool(cinematic_step.get("advance_on_confirm", true)):
					return
				return
			"camera":
				cinematic_camera_enabled = true
				cinematic_camera_start = current_cinematic_camera_center()
				cinematic_camera_target = cinematic_target_position(str(cinematic_step.get("target", "world")), cinematic_step.get("position", {}))
				cinematic_camera_position = cinematic_camera_start
				cinematic_camera_zoom_start = cinematic_camera_zoom
				cinematic_camera_zoom_target = clampf(float(cinematic_step.get("zoom", 1.0)), 0.5, 2.0)
				if cinematic_step_duration <= 0.0:
					cinematic_camera_position = cinematic_camera_target
					cinematic_camera_zoom = cinematic_camera_zoom_target
					immediate_steps += 1
					continue
				return
			"move_actor":
				cinematic_actor_key = str(cinematic_step.get("actor", ""))
				cinematic_actor_start = cinematic_actor_position(cinematic_actor_key)
				cinematic_actor_target = CinematicRepository.data_to_vector(cinematic_step.get("position"), cinematic_actor_start)
				if cinematic_step_duration <= 0.0:
					set_cinematic_actor_position(cinematic_actor_key, cinematic_actor_target)
					immediate_steps += 1
					continue
				return
			"set_era":
				apply_cinematic_era(str(cinematic_step.get("era_id", "")))
				if cinematic_step_duration <= 0.0:
					immediate_steps += 1
					continue
				return
			"fade":
				var direction := str(cinematic_step.get("direction", "out"))
				cinematic_fade_alpha = 0.0 if direction == "out" else 1.0
				if cinematic_step_duration <= 0.0:
					cinematic_fade_alpha = 1.0 if direction == "out" else 0.0
					immediate_steps += 1
					continue
				return
			"effects":
				apply_story_effects(CinematicCatalog.effects(cinematic_step, "effects"), false)
				immediate_steps += 1
				continue
			"checkpoint":
				var key := str(cinematic_step.get("key", "")).strip_edges()
				if not key.is_empty():
					session_state[key] = cinematic_step.get("value", "completed")
				immediate_steps += 1
				continue
			_:
				immediate_steps += 1
	if immediate_steps >= CINEMATIC_MAX_IMMEDIATE_STEPS:
		push_error("Cinematic immediate-step safety limit reached for %s." % active_cinematic_id)
		finish_cinematic(true)


func finish_cinematic(skipped: bool) -> void:
	if active_cinematic_id.is_empty():
		return
	var sequence := active_cinematic()
	var finished_id := active_cinematic_id
	cinematic_skipped = skipped
	if skipped:
		apply_story_effects(CinematicCatalog.effects(sequence, "skip_effects"), false, false)
	apply_story_effects(CinematicCatalog.effects(sequence, "completion_effects"), false, false)
	var completion_key := CinematicCatalog.completion_state_key(sequence)
	if not completion_key.is_empty():
		session_state[completion_key] = "skipped" if skipped else "completed"
	reset_active_cinematic()
	evaluate_story_progress()
	last_durable_fingerprint = durable_progress_fingerprint()
	request_autosave("Cinematic completed: %s" % finished_id)
	set_cinematic_notice("SEQUENCE SKIPPED" if skipped else "SEQUENCE COMPLETE")


func active_cinematic() -> Dictionary:
	return CinematicCatalog.cinematic(cinematic_definitions, active_cinematic_id)


func cinematic_target_position(target: String, fallback_position: Variant) -> Vector2:
	match target:
		"player":
			return player
		"companion":
			return companion
		"world":
			return CinematicRepository.data_to_vector(fallback_position, player)
		_:
			if target.begins_with("placement:"):
				var placement_id := target.trim_prefix("placement:")
				var index := entity_index_for_placement(placement_id)
				if index >= 0:
					return runtime_entities[index].get("position", player)
	return player


func current_cinematic_camera_center() -> Vector2:
	if cinematic_camera_enabled:
		return cinematic_camera_position
	return player


func cinematic_actor_position(actor_key: String) -> Vector2:
	match actor_key:
		"player":
			return player
		"companion":
			return companion
		_:
			if actor_key.begins_with("placement:"):
				var index := entity_index_for_placement(actor_key.trim_prefix("placement:"))
				if index >= 0:
					return runtime_entities[index].get("position", Vector2.ZERO)
	return Vector2.ZERO


func set_cinematic_actor_position(actor_key: String, position: Vector2) -> void:
	match actor_key:
		"player":
			player = recover_if_blocked(clamp_point_to_bounds(position, PLAYER_RADIUS), player, PLAYER_RADIUS)
		"companion":
			companion = recover_if_blocked(clamp_point_to_bounds(position, COMPANION_RADIUS), companion, COMPANION_RADIUS)
		_:
			if actor_key.begins_with("placement:"):
				var index := entity_index_for_placement(actor_key.trim_prefix("placement:"))
				if index >= 0:
					var entity: Dictionary = runtime_entities[index]
					entity["position"] = position
					runtime_entities[index] = entity


func apply_cinematic_era(era_id: String) -> void:
	if era_id.is_empty() or not map_has_era(map_data, era_id) or current_era_id == era_id:
		return
	current_era_id = era_id
	shift_lock = 0.65
	projectiles.clear()
	cancel_reload(false)
	sync_runtime_entities(true)
	sync_boss_reinforcement_visibility()
	player = recover_from_entity_collision(player, PLAYER_RADIUS)
	companion = recover_from_entity_collision(companion, COMPANION_RADIUS)


func camera_offset() -> Vector2:
	if not active_cinematic_id.is_empty() and cinematic_camera_enabled:
		var canvas: Dictionary = map_data.get("canvas", {})
		var width := float(canvas.get("width", VIEW.x))
		var height := float(canvas.get("height", VIEW.y))
		var desired := cinematic_camera_position - VIEW * 0.5
		return Vector2(
			clampf(desired.x, 0.0, maxf(0.0, width - VIEW.x)),
			clampf(desired.y, 0.0, maxf(0.0, height - VIEW.y))
		)
	return super.camera_offset()


func can_open_save_overlay() -> bool:
	return active_cinematic_id.is_empty() and super.can_open_save_overlay()


func can_flush_autosave() -> bool:
	return active_cinematic_id.is_empty() and super.can_flush_autosave()


func draw_game() -> void:
	super.draw_game()
	if not active_cinematic_id.is_empty():
		draw_cinematic_overlay()
	elif not cinematic_notice.is_empty():
		draw_rect(Rect2(220, 160, 200, 28), Color(0.02, 0.03, 0.04, 0.9))
		draw_centered(cinematic_notice, 179, 10, Color("e4cf8a"))


func draw_cinematic_overlay() -> void:
	var sequence := active_cinematic()
	if CinematicCatalog.is_letterboxed(sequence):
		draw_rect(Rect2(0, 0, VIEW.x, CINEMATIC_LETTERBOX_HEIGHT), Color("05070a"))
		draw_rect(Rect2(0, VIEW.y - CINEMATIC_LETTERBOX_HEIGHT, VIEW.x, CINEMATIC_LETTERBOX_HEIGHT), Color("05070a"))
	if not cinematic_text.is_empty():
		draw_rect(Rect2(44, 244, 552, 86), Color(0.025, 0.035, 0.045, 0.94))
		draw_rect(Rect2(44, 244, 552, 86), Color("b99b58"), false, 2.0)
		if not cinematic_speaker.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(62, 265), cinematic_speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 510, 10, Color("e6c972"))
		draw_text_lines(cinematic_text, Vector2(62, 286), 11, Color("f0eadb"))
	if CinematicCatalog.is_skippable(sequence):
		draw_string(ThemeDB.fallback_font, Vector2(468, 26), "ESC / START SKIP", HORIZONTAL_ALIGNMENT_LEFT, 150, 8, Color("87939a"))
	if cinematic_fade_alpha > 0.0:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.015, 0.02, 0.028, clampf(cinematic_fade_alpha, 0.0, 1.0)))


func set_cinematic_notice(message: String) -> void:
	cinematic_notice = message
	cinematic_notice_timer = CINEMATIC_NOTICE_DURATION
