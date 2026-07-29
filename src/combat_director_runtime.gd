extends "res://src/combat_runtime.gd"

const EncounterZoneModel = preload("res://src/game/encounter_zone_model.gd")
const CombatDirectorValidator = preload("res://src/content/combat_director_validator.gd")

const DEFAULT_STAGGER := 0.18
const DEFAULT_ATTACK_WINDUP := 0.24
const DEFAULT_KNOCKBACK_DISTANCE := 22.0
const KNOCKBACK_DECAY := 8.5

var player_knockback := Vector2.ZERO
var companion_knockback := Vector2.ZERO
var camera_shake_timer := 0.0
var camera_shake_strength := 0.0
var combo_count := 0
var combo_timer := 0.0
var zone_banner := ""
var zone_banner_timer := 0.0


func load_campaign(path: String) -> bool:
	var validation := CombatDirectorValidator.validate_campaign_path(path)
	if not validation.get("ok", false):
		load_error = format_errors(validation.get("errors", []))
		push_error("Combat director validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	var loaded := super.load_campaign(path)
	if loaded:
		reset_director_state()
		sync_runtime_entities(false)
	return loaded


func load_fallback_campaign() -> void:
	super.load_fallback_campaign()
	reset_director_state()


func reset_director_state() -> void:
	player_knockback = Vector2.ZERO
	companion_knockback = Vector2.ZERO
	camera_shake_timer = 0.0
	camera_shake_strength = 0.0
	combo_count = 0
	combo_timer = 0.0
	zone_banner = ""
	zone_banner_timer = 0.0


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	var activated := super.activate_map(map_id, entry_id, requested_era, use_transition)
	if activated:
		zone_banner = ""
		zone_banner_timer = 0.0
	return activated


func update_game(delta: float) -> void:
	camera_shake_timer = maxf(0.0, camera_shake_timer - delta)
	combo_timer = maxf(0.0, combo_timer - delta)
	zone_banner_timer = maxf(0.0, zone_banner_timer - delta)
	if combo_timer <= 0.0:
		combo_count = 0
	if zone_banner_timer <= 0.0:
		zone_banner = ""
	super.update_game(delta)
	apply_actor_knockback(delta)


func apply_actor_knockback(delta: float) -> void:
	if player_knockback.length_squared() > 0.01:
		move_actor("player", player + player_knockback * delta)
		player_knockback = player_knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * player_knockback.length() * delta)
	if companion_enabled() and companion_knockback.length_squared() > 0.01:
		move_actor("companion", companion + companion_knockback * delta)
		companion_knockback = companion_knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * companion_knockback.length() * delta)


func sync_runtime_entities(preserve_existing: bool) -> void:
	var previous_by_id: Dictionary = {}
	if preserve_existing:
		for value in runtime_entities:
			if typeof(value) == TYPE_DICTIONARY:
				var previous: Dictionary = value
				previous_by_id[str(previous.get("placement_id", ""))] = previous
	super.sync_runtime_entities(preserve_existing)
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		var placement_id := str(entity.get("placement_id", ""))
		var old: Dictionary = previous_by_id.get(placement_id, {})
		entity["mode"] = str(old.get("mode", "idle"))
		entity["stagger_timer"] = float(old.get("stagger_timer", 0.0))
		entity["attack_windup"] = float(old.get("attack_windup", 0.0))
		entity["target_memory"] = float(old.get("target_memory", 0.0))
		entity["patrol_step"] = int(old.get("patrol_step", 0))
		entity["patrol_wait"] = float(old.get("patrol_wait", 0.0))
		entity["patrol_target"] = vector_value(old.get("patrol_target"), vector_value(entity.get("spawn_position"), Vector2.ZERO))
		entity["knockback_velocity"] = vector_value(old.get("knockback_velocity"), Vector2.ZERO)
		runtime_entities[index] = entity
	update_zone_clear_states()


func update_runtime_entities(delta: float) -> void:
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		entity["attack_cooldown"] = maxf(0.0, float(entity.get("attack_cooldown", 0.0)) - delta)
		entity["hit_flash"] = maxf(0.0, float(entity.get("hit_flash", 0.0)) - delta)
		entity["target_memory"] = maxf(0.0, float(entity.get("target_memory", 0.0)) - delta)
		entity["patrol_wait"] = maxf(0.0, float(entity.get("patrol_wait", 0.0)) - delta)
		if not bool(entity.get("active", true)) or EncounterModel.kind(entity) != "enemy":
			runtime_entities[index] = entity
			continue
		update_directed_enemy(index, entity, delta)
	update_zone_clear_states()


func update_directed_enemy(index: int, entity: Dictionary, delta: float) -> void:
	var definition_data: Dictionary = entity.get("definition", {})
	var position := vector_value(entity.get("position"), Vector2.ZERO)
	var spawn_position := vector_value(entity.get("spawn_position"), position)
	var placement_id := str(entity.get("placement_id", ""))
	var zone := EncounterZoneModel.zone_for_enemy(map_data, placement_id, current_era_id)
	var target_name := "player"
	var target_position := player
	if companion_enabled() and companion_health > 0 and position.distance_to(companion) < position.distance_to(player):
		target_name = "companion"
		target_position = companion
	var distance := position.distance_to(target_position)
	var awareness := float(definition_data.get("awareness_radius", 96.0))
	var attack_range := float(definition_data.get("attack_radius", 18.0))
	var leash := EncounterZoneModel.leash_radius_for_enemy(zone, definition_data)
	var zone_active := zone.is_empty() or EncounterZoneModel.is_activated(zone, player, companion, companion_enabled())
	var target_inside_leash := EncounterZoneModel.target_is_inside_leash(zone, spawn_position, target_position, leash)
	var mode := str(entity.get("mode", "idle"))

	var stagger_timer := maxf(0.0, float(entity.get("stagger_timer", 0.0)) - delta)
	entity["stagger_timer"] = stagger_timer
	if stagger_timer > 0.0:
		entity["mode"] = "staggered"
		var knockback := vector_value(entity.get("knockback_velocity"), Vector2.ZERO)
		if knockback.length_squared() > 0.01:
			entity["position"] = move_entity(index, position, position + knockback * delta)
			entity["knockback_velocity"] = knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * knockback.length() * delta)
		runtime_entities[index] = entity
		return

	var attack_windup := maxf(0.0, float(entity.get("attack_windup", 0.0)) - delta)
	if float(entity.get("attack_windup", 0.0)) > 0.0:
		entity["attack_windup"] = attack_windup
		entity["mode"] = "windup"
		EncounterModel.update_facing(entity, position.direction_to(target_position))
		if attack_windup <= 0.0:
			if position.distance_to(target_position) <= attack_range + 6.0 and target_inside_leash:
				var attacker_context := definition_data.duplicate(true)
				attacker_context["_position"] = position
				damage_actor(target_name, int(definition_data.get("attack_damage", 1)), attacker_context)
			entity["attack_cooldown"] = float(definition_data.get("attack_cooldown", 1.0))
			entity["mode"] = "chase"
		runtime_entities[index] = entity
		return

	var outside_leash := spawn_position.distance_to(position) > leash
	if outside_leash or not target_inside_leash:
		mode = "return"
	elif zone_active and (distance <= awareness or float(entity.get("target_memory", 0.0)) > 0.0):
		mode = "chase"
		entity["target_memory"] = float(definition_data.get("target_memory", 0.8))
	elif mode in ["chase", "windup", "staggered"]:
		mode = "return"

	if mode == "return":
		if position.distance_to(spawn_position) <= 4.0:
			entity["position"] = spawn_position
			entity["mode"] = "idle"
		else:
			var multiplier := maxf(0.1, float(definition_data.get("return_speed_multiplier", 0.9)))
			entity = steer_enemy(index, entity, spawn_position, float(definition_data.get("move_speed", 48.0)) * multiplier, delta)
			entity["mode"] = "return"
		runtime_entities[index] = entity
		return

	if mode == "chase":
		if distance <= attack_range and float(entity.get("attack_cooldown", 0.0)) <= 0.0:
			entity["attack_windup"] = maxf(0.05, float(definition_data.get("attack_windup", DEFAULT_ATTACK_WINDUP)))
			entity["mode"] = "windup"
			EncounterModel.update_facing(entity, position.direction_to(target_position))
		else:
			entity = steer_enemy(index, entity, target_position, float(definition_data.get("move_speed", 48.0)), delta)
			entity["mode"] = "chase"
		runtime_entities[index] = entity
		return

	entity = update_patrol(index, entity, spawn_position, definition_data, delta)
	runtime_entities[index] = entity


func update_patrol(
	index: int,
	entity: Dictionary,
	spawn_position: Vector2,
	definition_data: Dictionary,
	delta: float
) -> Dictionary:
	var patrol_radius := maxf(0.0, float(definition_data.get("patrol_radius", 24.0)))
	if patrol_radius <= 0.0:
		entity["mode"] = "idle"
		return entity
	var position := vector_value(entity.get("position"), spawn_position)
	var patrol_target := vector_value(entity.get("patrol_target"), spawn_position)
	if float(entity.get("patrol_wait", 0.0)) <= 0.0 or position.distance_to(patrol_target) <= 4.0:
		var step := int(entity.get("patrol_step", 0)) + 1
		var seed := absi(hash(str(entity.get("placement_id", "enemy")))) % 360
		var angle := deg_to_rad(float((seed + step * 137) % 360))
		var candidate := spawn_position + Vector2(cos(angle), sin(angle)) * patrol_radius
		candidate = clamp_point_to_bounds(candidate, EncounterModel.collision_radius(entity))
		if MapModel.is_position_blocked(map_data, candidate, current_era_id, EncounterModel.collision_radius(entity)):
			candidate = spawn_position
		entity["patrol_step"] = step
		entity["patrol_target"] = candidate
		entity["patrol_wait"] = 1.2 + float(seed % 5) * 0.12
		patrol_target = candidate
	if position.distance_to(patrol_target) > 4.0:
		entity = steer_enemy(index, entity, patrol_target, float(definition_data.get("move_speed", 48.0)) * 0.42, delta)
		entity["mode"] = "patrol"
	else:
		entity["mode"] = "idle"
	return entity


func steer_enemy(
	index: int,
	entity: Dictionary,
	target_position: Vector2,
	speed: float,
	delta: float
) -> Dictionary:
	var position := vector_value(entity.get("position"), Vector2.ZERO)
	var navigation_target := MapModel.navigation_step(map_data, position, target_position, current_era_id)
	var direction := position.direction_to(navigation_target)
	if direction.length_squared() <= 0.001:
		direction = position.direction_to(target_position)
	if direction.length_squared() > 0.001:
		EncounterModel.update_facing(entity, direction)
		entity["position"] = move_entity(index, position, position + direction * speed * delta)
	return entity


func damage_entity(index: int, amount: int, source_name: String) -> void:
	if index < 0 or index >= runtime_entities.size() or typeof(runtime_entities[index]) != TYPE_DICTIONARY:
		return
	super.damage_entity(index, amount, source_name)
	if index >= runtime_entities.size() or typeof(runtime_entities[index]) != TYPE_DICTIONARY:
		return
	var entity: Dictionary = runtime_entities[index]
	if not bool(entity.get("active", true)):
		camera_shake_timer = 0.16
		camera_shake_strength = 3.2
		combo_count += 1
		combo_timer = 1.2
		update_zone_clear_states()
		return
	var definition_data: Dictionary = entity.get("definition", {})
	var source_position := player if source_name == player_name() else companion
	var position := vector_value(entity.get("position"), Vector2.ZERO)
	var direction := source_position.direction_to(position)
	if direction.length_squared() <= 0.001:
		direction = facing
	var stagger := maxf(0.05, float(definition_data.get("stagger_duration", DEFAULT_STAGGER)))
	var distance := maxf(0.0, float(definition_data.get("knockback_distance", DEFAULT_KNOCKBACK_DISTANCE)))
	entity["stagger_timer"] = stagger
	entity["knockback_velocity"] = direction.normalized() * distance / stagger
	entity["mode"] = "staggered"
	entity["target_memory"] = maxf(0.4, float(definition_data.get("target_memory", 0.8)))
	entity["hit_flash"] = maxf(0.18, float(entity.get("hit_flash", 0.0)))
	runtime_entities[index] = entity
	camera_shake_timer = 0.11
	camera_shake_strength = 2.0
	combo_count += 1
	combo_timer = 1.0


func damage_actor(actor_id: String, amount: int, attacker: Dictionary) -> void:
	var before := player_health if actor_id == "player" else companion_health
	super.damage_actor(actor_id, amount, attacker)
	var after := player_health if actor_id == "player" else companion_health
	if after >= before:
		return
	var attacker_position := vector_value(attacker.get("_position"), player)
	var actor_position := player if actor_id == "player" else companion
	var direction := attacker_position.direction_to(actor_position)
	if direction.length_squared() <= 0.001:
		direction = -facing
	var distance := maxf(0.0, float(attacker.get("contact_knockback", 20.0)))
	var velocity := direction.normalized() * distance / 0.18
	if actor_id == "player":
		player_knockback = velocity
	else:
		companion_knockback = velocity
	camera_shake_timer = 0.18
	camera_shake_strength = 3.4
	combo_count = 0
	combo_timer = 0.0


func update_zone_clear_states() -> void:
	var map_id := str(map_data.get("id", "map"))
	for value in EncounterZoneModel.available_zones(map_data, current_era_id):
		var zone: Dictionary = value
		if not zone_cleared_with_session(zone):
			continue
		var key := EncounterZoneModel.zone_state_key(map_id, zone)
		if session_state.get(key) == "cleared":
			continue
		session_state[key] = "cleared"
		zone_banner = "%s CLEARED" % str(zone.get("display_name", zone.get("id", "Encounter"))).to_upper()
		zone_banner_timer = 1.8


func zone_cleared_with_session(zone: Dictionary) -> bool:
	var enemy_ids := EncounterZoneModel.enemy_placement_ids(zone)
	if enemy_ids.is_empty():
		return false
	for placement_id in enemy_ids:
		var placement := find_placement(str(placement_id))
		if placement.is_empty():
			return false
		var key := ObjectCatalog.state_key(str(map_data.get("id", "map")), placement)
		if session_state.get(key) != "defeated":
			return false
	return true


func find_placement(placement_id: String) -> Dictionary:
	for value in map_data.get("object_placements", []):
		if typeof(value) == TYPE_DICTIONARY:
			var placement: Dictionary = value
			if str(placement.get("id", "")) == placement_id:
				return placement
	return {}


func camera_offset() -> Vector2:
	var offset := super.camera_offset()
	if camera_shake_timer <= 0.0:
		return offset
	var strength := camera_shake_strength * clampf(camera_shake_timer / 0.18, 0.0, 1.0)
	return offset + Vector2(sin(elapsed * 83.0), cos(elapsed * 67.0)) * strength


func draw_runtime_entity(entity: Dictionary) -> void:
	super.draw_runtime_entity(entity)
	if EncounterModel.kind(entity) != "enemy":
		return
	var position := vector_value(entity.get("position"), Vector2.ZERO)
	var mode := str(entity.get("mode", "idle"))
	if mode == "windup":
		var windup := maxf(0.0, float(entity.get("attack_windup", 0.0)))
		var definition_data: Dictionary = entity.get("definition", {})
		var total := maxf(0.05, float(definition_data.get("attack_windup", DEFAULT_ATTACK_WINDUP)))
		var progress := 1.0 - clampf(windup / total, 0.0, 1.0)
		draw_arc(position, 20.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 24, Color("f2a45e"), 2.0)
	elif mode == "staggered":
		draw_line(position + Vector2(-14, -18), position + Vector2(-8, -24), Color("fff0b8"), 2.0)
		draw_line(position + Vector2(14, -18), position + Vector2(8, -24), Color("fff0b8"), 2.0)
	elif mode == "chase":
		draw_circle(position, 18.0, Color(0.95, 0.28, 0.19, 0.25), false, 1.0)


func draw_player() -> void:
	super.draw_player()
	if player_hurt_lock > 0.0:
		draw_circle(player + Vector2(0, -4), 15.0, Color(1.0, 0.85, 0.72, 0.7), false, 2.0)


func draw_companion() -> void:
	super.draw_companion()
	if companion_hurt_lock > 0.0:
		draw_circle(companion + Vector2(0, -4), 14.0, Color(1.0, 0.78, 0.58, 0.65), false, 2.0)


func draw_hud(era_data: Dictionary) -> void:
	super.draw_hud(era_data)
	if combo_count > 1 and combo_timer > 0.0:
		draw_string(ThemeDB.fallback_font, Vector2(300, 27), "CHAIN x%d" % combo_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f0c968"))
	if not zone_banner.is_empty():
		draw_rect(Rect2(208, 102, 224, 26), Color(0.03, 0.04, 0.05, 0.86))
		draw_centered(zone_banner, 120, 12, Color("f1d57d"))


func vector_value(value: Variant, fallback: Vector2) -> Vector2:
	return value if value is Vector2 else fallback
