extends "res://src/arsenal_runtime.gd"

const BossCatalog = preload("res://src/content/boss_catalog.gd")
const BossValidator = preload("res://src/content/boss_validator.gd")
const BossEncounterZoneModel = preload("res://src/game/encounter_zone_model.gd")
const BossObjectCatalog = preload("res://src/content/object_catalog.gd")
const BossProjectileModel = preload("res://src/game/projectile_model.gd")
const BossArsenalCatalog = preload("res://src/content/arsenal_catalog.gd")
const BossRepository = preload("res://src/content/campaign_repository.gd")

const BOSS_BANNER_DURATION := 1.8
const BOSS_ARENA_LINE_WIDTH := 2.0

var engaged_bosses: Dictionary = {}
var boss_contexts: Dictionary = {}
var boss_phase_ids: Dictionary = {}
var boss_pattern_indices: Dictionary = {}
var boss_reinforcement_active: Dictionary = {}
var boss_banner := ""
var boss_banner_timer := 0.0


func load_campaign(path: String) -> bool:
	var validation := BossValidator.validate_campaign_path(path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		push_error("Boss and phase validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	clear_boss_state()
	var loaded := super.load_campaign(path)
	if not loaded:
		return false
	reset_boss_state()
	return true


func load_fallback_campaign() -> void:
	clear_boss_state()
	super.load_fallback_campaign()
	reset_boss_state()


func clear_boss_state() -> void:
	engaged_bosses.clear()
	boss_contexts.clear()
	boss_phase_ids.clear()
	boss_pattern_indices.clear()
	boss_reinforcement_active.clear()
	boss_banner = ""
	boss_banner_timer = 0.0


func reset_boss_state() -> void:
	clear_boss_state()
	sync_runtime_entities(false)


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	var previous_map_id := str(map_data.get("id", ""))
	if not previous_map_id.is_empty() and previous_map_id != map_id:
		clear_boss_state()
	var activated := super.activate_map(map_id, entry_id, requested_era, use_transition)
	if activated:
		sync_boss_reinforcement_visibility()
		update_boss_engagements()
	return activated


func shift_to_next_era() -> void:
	var context := active_arena_context()
	if not context.is_empty():
		var definition_data := context_definition(context)
		if not BossCatalog.allow_era_shift(definition_data):
			set_combat_text("The arena's mechanism prevents an era shift.", 1.0)
			return
	projectiles.clear()
	cancel_reload(false)
	super.shift_to_next_era()
	update_boss_engagements()


func rewind_after_defeat() -> void:
	projectiles.clear()
	cancel_reload(false)
	clear_boss_state()
	super.rewind_after_defeat()
	sync_boss_reinforcement_visibility()


func update_game(delta: float) -> void:
	boss_banner_timer = maxf(0.0, boss_banner_timer - delta)
	if boss_banner_timer <= 0.0:
		boss_banner = ""
	update_boss_engagements()
	super.update_game(delta)
	if flow == Flow.GAME:
		update_boss_engagements()
		finalize_boss_outcomes()


func sync_runtime_entities(preserve_existing: bool) -> void:
	super.sync_runtime_entities(preserve_existing)
	sync_boss_reinforcement_visibility()


func sync_boss_reinforcement_visibility() -> void:
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		var base_definition := BossObjectCatalog.definition(object_definitions, str(entity.get("object_id", "")))
		if not base_definition.is_empty():
			entity["definition"] = base_definition
		var placement := BossCatalog.placement_record(map_data, str(entity.get("placement_id", "")))
		var reinforcement_value: Variant = placement.get("boss_reinforcement", {})
		if typeof(reinforcement_value) == TYPE_DICTIONARY and not (reinforcement_value as Dictionary).is_empty():
			var placement_id := str(entity.get("placement_id", ""))
			var should_be_active := bool(boss_reinforcement_active.get(placement_id, false))
			entity["active"] = should_be_active
			if not should_be_active:
				entity["mode"] = "dormant"
		runtime_entities[index] = entity


func update_boss_engagements() -> void:
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		if not bool(entity.get("active", true)):
			continue
		var object_id := str(entity.get("object_id", ""))
		var definition_data := BossObjectCatalog.definition(object_definitions, object_id)
		if not BossCatalog.is_boss(definition_data):
			continue
		var placement_id := str(entity.get("placement_id", ""))
		var zone := boss_zone(definition_data)
		if not bool(engaged_bosses.get(placement_id, false)):
			if zone.is_empty() or not BossEncounterZoneModel.is_activated(zone, player, companion, companion_enabled()):
				continue
			engage_boss(placement_id, object_id, definition_data, zone)
		ensure_boss_phase(index, definition_data)


func engage_boss(
	placement_id: String,
	object_id: String,
	definition_data: Dictionary,
	zone: Dictionary
) -> void:
	engaged_bosses[placement_id] = true
	boss_contexts[placement_id] = {
		"placement_id": placement_id,
		"object_id": object_id,
		"zone_id": str(zone.get("id", BossCatalog.arena_zone_id(definition_data))),
		"outcome_state_key": BossCatalog.outcome_state_key(definition_data)
	}
	boss_pattern_indices[placement_id] = 0
	show_boss_banner(BossCatalog.intro_message(definition_data))
	transition_lock = maxf(transition_lock, 0.7)
	projectiles.clear()
	cancel_reload(false)


func ensure_boss_phase(index: int, definition_data: Dictionary) -> void:
	if index < 0 or index >= runtime_entities.size() or typeof(runtime_entities[index]) != TYPE_DICTIONARY:
		return
	var entity: Dictionary = runtime_entities[index]
	var placement_id := str(entity.get("placement_id", ""))
	if not bool(engaged_bosses.get(placement_id, false)):
		return
	var phase := BossCatalog.phase_for(definition_data, int(entity.get("health", definition_data.get("max_health", 1))), current_era_id)
	if phase.is_empty():
		return
	var next_id := BossCatalog.phase_id(phase)
	if str(boss_phase_ids.get(placement_id, "")) == next_id:
		return
	boss_phase_ids[placement_id] = next_id
	boss_pattern_indices[placement_id] = 0
	activate_phase_reinforcements(placement_id, phase)
	var duration := BossCatalog.phase_transition_duration(phase)
	transition_lock = maxf(transition_lock, duration)
	projectiles.clear()
	cancel_reload(false)
	show_boss_banner(BossCatalog.phase_message(phase))


func activate_phase_reinforcements(boss_placement_id: String, phase: Dictionary) -> void:
	for reinforcement_id in BossCatalog.phase_reinforcements(phase):
		var placement := BossCatalog.placement_record(map_data, reinforcement_id)
		var metadata_value: Variant = placement.get("boss_reinforcement", {})
		if typeof(metadata_value) != TYPE_DICTIONARY:
			continue
		var metadata: Dictionary = metadata_value
		if str(metadata.get("boss_placement_id", "")) != boss_placement_id:
			continue
		boss_reinforcement_active[reinforcement_id] = true
		var reinforcement_index := entity_index_for_placement(reinforcement_id)
		if reinforcement_index < 0:
			continue
		var entity: Dictionary = runtime_entities[reinforcement_index]
		entity["active"] = true
		entity["mode"] = "idle"
		var definition_data := BossObjectCatalog.definition(object_definitions, str(entity.get("object_id", "")))
		entity["health"] = maxi(1, int(definition_data.get("max_health", 1)))
		runtime_entities[reinforcement_index] = entity


func update_directed_enemy(index: int, entity: Dictionary, delta: float) -> void:
	var object_id := str(entity.get("object_id", ""))
	var base_definition := BossObjectCatalog.definition(object_definitions, object_id)
	if not BossCatalog.is_boss(base_definition):
		super.update_directed_enemy(index, entity, delta)
		return
	var placement_id := str(entity.get("placement_id", ""))
	if bool(engaged_bosses.get(placement_id, false)):
		ensure_boss_phase(index, base_definition)
	var phase := BossCatalog.phase_by_id(base_definition, str(boss_phase_ids.get(placement_id, "")))
	var directed := entity.duplicate(true)
	directed["definition"] = BossCatalog.apply_phase(base_definition, phase)
	super.update_directed_enemy(index, directed, delta)


func damage_entity(index: int, amount: int, source_name: String) -> void:
	if index < 0 or index >= runtime_entities.size() or typeof(runtime_entities[index]) != TYPE_DICTIONARY:
		return
	var before: Dictionary = runtime_entities[index]
	var base_definition := BossObjectCatalog.definition(object_definitions, str(before.get("object_id", "")))
	var applied_amount := amount
	if BossCatalog.is_boss(base_definition):
		applied_amount = clamp_boss_damage_to_phase(before, base_definition, amount)
	super.damage_entity(index, applied_amount, source_name)
	if not BossCatalog.is_boss(base_definition) or index >= runtime_entities.size() or typeof(runtime_entities[index]) != TYPE_DICTIONARY:
		return
	var after: Dictionary = runtime_entities[index]
	if bool(after.get("active", true)):
		ensure_boss_phase(index, base_definition)
	else:
		show_boss_banner("THE CORE FALLS — CLEAR THE ARENA")


func clamp_boss_damage_to_phase(
	entity: Dictionary,
	definition_data: Dictionary,
	amount: int
) -> int:
	var maximum := maxi(1, int(definition_data.get("max_health", 1)))
	var current := maxi(1, int(entity.get("health", maximum)))
	var ratio := float(current) / float(maximum)
	var threshold := BossCatalog.next_phase_threshold(definition_data, ratio, current_era_id)
	if threshold <= 0.0:
		return maxi(1, amount)
	var boundary_health := maxi(1, int(ceil(float(maximum) * threshold)))
	if current > boundary_health and current - amount < boundary_health:
		return maxi(1, current - boundary_health)
	return maxi(1, amount)


func damage_actor(actor_id: String, amount: int, attacker: Dictionary) -> void:
	if BossCatalog.is_boss(attacker) and not bool(attacker.get("_projectile_resolved", false)):
		var boss_index := boss_entity_index_from_attacker(attacker)
		if boss_index >= 0:
			perform_boss_pattern_attack(boss_index, actor_id, amount, attacker)
			return
	super.damage_actor(actor_id, amount, attacker)


func boss_entity_index_from_attacker(attacker: Dictionary) -> int:
	var object_id := str(attacker.get("id", ""))
	var origin_value: Variant = attacker.get("_position", Vector2.ZERO)
	var origin: Vector2 = origin_value if origin_value is Vector2 else Vector2.ZERO
	var best := -1
	var best_distance := INF
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		if not bool(entity.get("active", true)) or str(entity.get("object_id", "")) != object_id:
			continue
		var distance := origin.distance_to(entity.get("position", Vector2.ZERO))
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


func perform_boss_pattern_attack(
	index: int,
	actor_id: String,
	amount: int,
	attacker: Dictionary
) -> void:
	if index < 0 or index >= runtime_entities.size():
		return
	var entity: Dictionary = runtime_entities[index]
	var placement_id := str(entity.get("placement_id", ""))
	var base_definition := BossObjectCatalog.definition(object_definitions, str(entity.get("object_id", "")))
	var phase := BossCatalog.phase_by_id(base_definition, str(boss_phase_ids.get(placement_id, "")))
	var pattern := BossCatalog.phase_pattern(phase)
	if pattern.is_empty():
		super.damage_actor(actor_id, amount, attacker)
		return
	var pattern_index := int(boss_pattern_indices.get(placement_id, 0))
	var step_value: Variant = pattern[pattern_index % pattern.size()]
	boss_pattern_indices[placement_id] = (pattern_index + 1) % pattern.size()
	if typeof(step_value) != TYPE_DICTIONARY:
		return
	var step: Dictionary = step_value
	var step_type := BossCatalog.pattern_step_type(step)
	if step_type == "pause":
		set_combat_text("%s recalibrates." % BossCatalog.phase_name(phase), BossCatalog.pattern_step_pause(step))
		return
	if step_type == "strike":
		var resolved := attacker.duplicate(true)
		resolved["_projectile_resolved"] = true
		resolved["contact_knockback"] = float(attacker.get("contact_knockback", 18.0))
		super.damage_actor(actor_id, maxi(1, int(round(float(amount) * float(step.get("damage_multiplier", 1.0))))), resolved)
		return
	spawn_boss_projectiles(entity, actor_id, amount, step, phase)


func spawn_boss_projectiles(
	entity: Dictionary,
	actor_id: String,
	amount: int,
	step: Dictionary,
	phase: Dictionary
) -> void:
	var base_definition := BossObjectCatalog.definition(object_definitions, str(entity.get("object_id", "")))
	var phase_definition := BossCatalog.apply_phase(base_definition, phase)
	var origin_value: Variant = entity.get("position", Vector2.ZERO)
	var origin: Vector2 = origin_value if origin_value is Vector2 else Vector2.ZERO
	var target_position := player if actor_id == "player" else companion
	var base_direction := origin.direction_to(target_position)
	if base_direction.length_squared() <= 0.001:
		base_direction = Vector2.LEFT
	var step_type := BossCatalog.pattern_step_type(step)
	var count := BossCatalog.pattern_step_count(step)
	var directions: Array[Vector2] = []
	if step_type == "radial_burst":
		for shot_index in range(count):
			directions.append(Vector2.RIGHT.rotated(TAU * float(shot_index) / float(count)))
	elif step_type == "fan_shot":
		var spread := deg_to_rad(BossCatalog.pattern_step_spread(step))
		for shot_index in range(count):
			var ratio := 0.5 if count == 1 else float(shot_index) / float(count - 1)
			directions.append(base_direction.rotated(lerpf(-spread * 0.5, spread * 0.5, ratio)))
	else:
		directions.append(base_direction)
	var damage := maxi(1, int(round(float(amount) * maxf(0.05, float(step.get("damage_multiplier", 1.0))))))
	var speed := BossArsenalCatalog.enemy_projectile_speed(phase_definition) * maxf(0.05, float(step.get("speed_multiplier", 1.0)))
	var projectile_range := BossArsenalCatalog.enemy_projectile_range(phase_definition) * maxf(0.05, float(step.get("range_multiplier", 1.0)))
	var radius := BossArsenalCatalog.enemy_projectile_radius(phase_definition)
	var knockback := BossArsenalCatalog.enemy_projectile_knockback(phase_definition)
	var color := BossArsenalCatalog.enemy_projectile_color(phase_definition)
	for direction in directions:
		projectiles.append(BossProjectileModel.create_projectile(
			"enemy",
			str(entity.get("placement_id", "boss")),
			str(base_definition.get("display_name", "Boss")),
			origin + direction * 12.0,
			direction,
			speed,
			projectile_range,
			radius,
			damage,
			knockback,
			color,
			actor_id
		))


func finalize_boss_outcomes() -> void:
	for placement_id_value in boss_contexts.keys():
		var placement_id := str(placement_id_value)
		var context_value: Variant = boss_contexts.get(placement_id, {})
		if typeof(context_value) != TYPE_DICTIONARY:
			continue
		var context: Dictionary = context_value
		var zone := encounter_zone_by_id(str(context.get("zone_id", "")))
		if zone.is_empty():
			continue
		var clear_key := BossEncounterZoneModel.zone_state_key(str(map_data.get("id", "map")), zone)
		if session_state.get(clear_key) != "cleared":
			continue
		var definition_data := context_definition(context)
		var outcome_key := str(context.get("outcome_state_key", BossCatalog.outcome_state_key(definition_data)))
		if session_state.get(outcome_key) != "defeated":
			session_state[outcome_key] = "defeated"
			var messages := apply_story_effects(BossCatalog.defeat_effects(definition_data), false, false)
			evaluate_story_progress()
			var message := BossCatalog.defeat_message(definition_data)
			if not messages.is_empty():
				message += "  " + "  ".join(messages)
			show_boss_banner(message)
		engaged_bosses.erase(placement_id)
		boss_phase_ids.erase(placement_id)
		boss_pattern_indices.erase(placement_id)
		boss_contexts.erase(placement_id)
		last_durable_fingerprint = durable_progress_fingerprint()


func move_actor(actor_id: String, desired_position: Vector2) -> void:
	super.move_actor(actor_id, desired_position)
	var context := active_arena_context()
	if context.is_empty():
		return
	var arena := BossCatalog.arena_bounds(context_definition(context))
	if arena.size.x <= 0.0 or arena.size.y <= 0.0:
		return
	var radius := PLAYER_RADIUS if actor_id == "player" else COMPANION_RADIUS
	var current := player if actor_id == "player" else companion
	current.x = clampf(current.x, arena.position.x + radius, arena.end.x - radius)
	current.y = clampf(current.y, arena.position.y + radius, arena.end.y - radius)
	if actor_id == "player":
		player = current
	else:
		companion = current


func travel_through(connection: Dictionary) -> bool:
	var context := active_arena_context()
	if not context.is_empty():
		var definition_data := context_definition(context)
		if BossCatalog.locked_connections(definition_data).has(str(connection.get("id", ""))):
			dialogue = "The arena remains sealed while the guardian's pattern is active."
			return false
	return super.travel_through(connection)


func can_open_save_overlay() -> bool:
	return active_arena_context().is_empty() and super.can_open_save_overlay()


func can_flush_autosave() -> bool:
	return active_arena_context().is_empty() and super.can_flush_autosave()


func active_arena_context() -> Dictionary:
	for placement_id_value in boss_contexts.keys():
		var placement_id := str(placement_id_value)
		if not bool(engaged_bosses.get(placement_id, false)):
			continue
		var context_value: Variant = boss_contexts.get(placement_id, {})
		if typeof(context_value) != TYPE_DICTIONARY:
			continue
		var context: Dictionary = context_value
		var zone := encounter_zone_by_id(str(context.get("zone_id", "")))
		if zone.is_empty():
			continue
		var clear_key := BossEncounterZoneModel.zone_state_key(str(map_data.get("id", "map")), zone)
		if session_state.get(clear_key) != "cleared":
			return context
	return {}


func context_definition(context: Dictionary) -> Dictionary:
	return BossObjectCatalog.definition(object_definitions, str(context.get("object_id", "")))


func boss_zone(definition_data: Dictionary) -> Dictionary:
	return encounter_zone_by_id(BossCatalog.arena_zone_id(definition_data))


func encounter_zone_by_id(zone_id: String) -> Dictionary:
	for value in map_data.get("encounter_zones", []):
		if typeof(value) == TYPE_DICTIONARY:
			var zone: Dictionary = value
			if str(zone.get("id", "")) == zone_id:
				return zone
	return {}


func entity_index_for_placement(placement_id: String) -> int:
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) == TYPE_DICTIONARY and str((runtime_entities[index] as Dictionary).get("placement_id", "")) == placement_id:
			return index
	return -1


func current_boss_index() -> int:
	for placement_id_value in engaged_bosses.keys():
		if bool(engaged_bosses.get(placement_id_value, false)):
			var index := entity_index_for_placement(str(placement_id_value))
			if index >= 0 and bool((runtime_entities[index] as Dictionary).get("active", true)):
				return index
	return -1


func show_boss_banner(message: String) -> void:
	boss_banner = message.strip_edges()
	boss_banner_timer = BOSS_BANNER_DURATION


func draw_game() -> void:
	super.draw_game()
	draw_active_boss_arena()
	if not boss_banner.is_empty():
		draw_rect(Rect2(92, 104, 456, 34), Color(0.03, 0.04, 0.05, 0.92))
		draw_rect(Rect2(92, 104, 456, 34), Color("d5ad58"), false, 2.0)
		draw_centered(boss_banner, 126, 11, Color("f6e2a4"))


func draw_active_boss_arena() -> void:
	var context := active_arena_context()
	if context.is_empty():
		return
	var arena := BossCatalog.arena_bounds(context_definition(context))
	if arena.size.x <= 0.0 or arena.size.y <= 0.0:
		return
	var offset := camera_offset()
	draw_set_transform(-offset, 0.0, Vector2.ONE)
	draw_rect(arena, Color(0.88, 0.35, 0.16, 0.08))
	draw_rect(arena, Color(0.92, 0.49, 0.2, 0.72), false, BOSS_ARENA_LINE_WIDTH)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_hud(era_data: Dictionary) -> void:
	super.draw_hud(era_data)
	var boss_index := current_boss_index()
	if boss_index < 0:
		if not active_arena_context().is_empty():
			draw_rect(Rect2(126, 300, 388, 26), Color(0.03, 0.04, 0.05, 0.9))
			draw_centered("REINFORCEMENTS REMAIN", 318, 10, Color("e7b872"))
		return
	var entity: Dictionary = runtime_entities[boss_index]
	var definition_data := BossObjectCatalog.definition(object_definitions, str(entity.get("object_id", "")))
	var maximum := maxi(1, int(definition_data.get("max_health", 1)))
	var health := clampi(int(entity.get("health", maximum)), 0, maximum)
	var placement_id := str(entity.get("placement_id", ""))
	var phase := BossCatalog.phase_by_id(definition_data, str(boss_phase_ids.get(placement_id, "")))
	draw_rect(Rect2(86, 292, 468, 42), Color(0.03, 0.04, 0.05, 0.94))
	draw_rect(Rect2(96, 316, 448, 8), Color("2a1718"))
	draw_rect(Rect2(96, 316, 448.0 * float(health) / float(maximum), 8), Color("c5533f"))
	draw_string(ThemeDB.fallback_font, Vector2(100, 309), str(definition_data.get("display_name", "BOSS")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 250, 12, Color("f3dda3"))
	draw_string(ThemeDB.fallback_font, Vector2(352, 309), BossCatalog.phase_name(phase).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, 188, 10, Color("d8b66d"))
