extends "res://src/app.gd"

const FullValidator = preload("res://src/content/epochbound_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EncounterModel = preload("res://src/game/encounter_model.gd")

const PLAYER_ATTACK_RANGE := 42.0
const PLAYER_ATTACK_DAMAGE := 4
const PLAYER_ATTACK_COOLDOWN := 0.34
const COMPANION_ATTACK_RANGE := 38.0
const COMPANION_ATTACK_DAMAGE := 2
const COMPANION_ATTACK_COOLDOWN := 0.78

var object_definitions: Dictionary = {}
var runtime_entities: Array = []
var session_state: Dictionary = {}
var player_health := 32
var companion_health := 24
var clock_shards := 0
var player_attack_lock := 0.0
var companion_attack_lock := 0.0
var player_hurt_lock := 0.0
var companion_hurt_lock := 0.0
var player_attack_timer := 0.0
var companion_attack_timer := 0.0
var combat_text := ""
var combat_text_timer := 0.0


func load_campaign(path: String) -> bool:
	var validation := FullValidator.validate_campaign_path(path)
	if not validation.get("ok", false):
		load_error = format_errors(validation.get("errors", []))
		push_error("Campaign validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	var loaded := super.load_campaign(path)
	if not loaded:
		return false
	var catalog_result := ObjectCatalog.load_catalogs(campaign_path, campaign)
	if not catalog_result.get("ok", false):
		load_error = format_errors(catalog_result.get("errors", []))
		push_error("Object catalog load failed: %s" % load_error)
		return false
	object_definitions = catalog_result.get("definitions", {})
	reset_encounter_session()
	sync_runtime_entities(false)
	return true


func load_fallback_campaign() -> void:
	super.load_fallback_campaign()
	object_definitions = {}
	var fallback_catalog := ObjectCatalog.default_catalog()
	for value in fallback_catalog.get("objects", []):
		if typeof(value) == TYPE_DICTIONARY:
			var definition_data: Dictionary = value
			object_definitions[String(definition_data.get("id", ""))] = definition_data
	reset_encounter_session()
	sync_runtime_entities(false)


func reset_encounter_session() -> void:
	session_state.clear()
	clock_shards = 0
	player_health = actor_health("player", 32)
	companion_health = actor_health("companion", 24)
	player_attack_lock = 0.0
	companion_attack_lock = 0.0
	player_hurt_lock = 0.0
	companion_hurt_lock = 0.0
	player_attack_timer = 0.0
	companion_attack_timer = 0.0
	combat_text = ""
	combat_text_timer = 0.0


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	var activated := super.activate_map(map_id, entry_id, requested_era, use_transition)
	if activated:
		sync_runtime_entities(false)
	return activated


func begin_game() -> void:
	current_era_id = String(campaign.get("start_era", first_era_id()))
	if current_era_id.is_empty():
		current_era_id = first_era_id()
	reset_actor_positions()
	player_health = maxi(1, player_health)
	companion_health = maxi(1, companion_health)
	shift_lock = 0.0
	transition_lock = 0.0
	sync_runtime_entities(false)
	change_flow(Flow.GAME)


func update_game(delta: float) -> void:
	player_attack_lock = maxf(0.0, player_attack_lock - delta)
	companion_attack_lock = maxf(0.0, companion_attack_lock - delta)
	player_hurt_lock = maxf(0.0, player_hurt_lock - delta)
	companion_hurt_lock = maxf(0.0, companion_hurt_lock - delta)
	player_attack_timer = maxf(0.0, player_attack_timer - delta)
	companion_attack_timer = maxf(0.0, companion_attack_timer - delta)
	combat_text_timer = maxf(0.0, combat_text_timer - delta)
	if combat_text_timer <= 0.0:
		combat_text = ""
	var can_attack := dialogue.is_empty() and transition_lock <= 0.45
	if can_attack and Input.is_action_just_pressed("attack") and player_attack_lock <= 0.0:
		perform_player_attack()
	super.update_game(delta)
	if flow != Flow.GAME or not dialogue.is_empty() or transition_lock > 0.45:
		return
	update_runtime_entities(delta)
	collect_nearby_pickups()
	perform_companion_attack()


func move_actor(actor_id: String, desired_position: Vector2) -> void:
	var radius := PLAYER_RADIUS if actor_id == "player" else COMPANION_RADIUS
	var current := player if actor_id == "player" else companion
	var target := clamp_point_to_bounds(desired_position, radius)
	var horizontal := Vector2(target.x, current.y)
	if not world_position_blocked(horizontal, radius):
		current.x = horizontal.x
	var vertical := Vector2(current.x, target.y)
	if not world_position_blocked(vertical, radius):
		current.y = vertical.y
	if actor_id == "player":
		player = current
	else:
		companion = current


func world_position_blocked(position: Vector2, radius: float) -> bool:
	return (
		MapModel.is_position_blocked(map_data, position, current_era_id, radius)
		or EncounterModel.position_is_blocked_by_entities(runtime_entities, position, radius)
	)


func sync_runtime_entities(preserve_existing: bool) -> void:
	var next_entities := EncounterModel.instantiate_entities(
		map_data,
		object_definitions,
		current_era_id,
		session_state
	)
	if preserve_existing:
		next_entities = EncounterModel.preserve_runtime_state(runtime_entities, next_entities)
	runtime_entities = next_entities


func shift_to_next_era() -> void:
	super.shift_to_next_era()
	sync_runtime_entities(true)
	player = recover_from_entity_collision(player, PLAYER_RADIUS)
	companion = recover_from_entity_collision(companion, COMPANION_RADIUS)


func recover_from_entity_collision(position: Vector2, radius: float) -> Vector2:
	if not EncounterModel.position_is_blocked_by_entities(runtime_entities, position, radius):
		return position
	var recovered := MapModel.nearest_recovery_point(map_data, position, current_era_id, position)
	if not EncounterModel.position_is_blocked_by_entities(runtime_entities, recovered, radius):
		return recovered
	return clamp_point_to_bounds(position - facing * 24.0, radius)


func interact() -> void:
	var best_index := -1
	var best_distance := INF
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		if not bool(entity.get("active", true)):
			continue
		var kind := EncounterModel.kind(entity)
		if not ["prop", "npc", "pickup"].has(kind):
			continue
		var radius := EncounterModel.interaction_radius(entity)
		var distance := player.distance_to(entity.get("position", Vector2.ZERO))
		if distance <= radius and distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index < 0:
		super.interact()
		return
	var entity: Dictionary = runtime_entities[best_index]
	if EncounterModel.kind(entity) == "pickup":
		collect_pickup(best_index)
		return
	var definition_data: Dictionary = entity.get("definition", {})
	dialogue = ObjectCatalog.dialogue_for(definition_data, current_era_id)


func perform_player_attack() -> void:
	player_attack_lock = PLAYER_ATTACK_COOLDOWN
	player_attack_timer = 0.17
	var target_index := EncounterModel.nearest_facing_enemy_index(
		runtime_entities,
		player,
		facing,
		PLAYER_ATTACK_RANGE
	)
	if target_index >= 0:
		damage_entity(target_index, PLAYER_ATTACK_DAMAGE, player_name())


func perform_companion_attack() -> void:
	if not companion_enabled() or companion_attack_lock > 0.0 or companion_health <= 0:
		return
	var target_index := EncounterModel.nearest_entity_index(
		runtime_entities,
		companion,
		["enemy"],
		COMPANION_ATTACK_RANGE
	)
	if target_index < 0:
		return
	companion_attack_lock = COMPANION_ATTACK_COOLDOWN
	companion_attack_timer = 0.18
	damage_entity(target_index, COMPANION_ATTACK_DAMAGE, companion_name())


func damage_entity(index: int, amount: int, source_name: String) -> void:
	if index < 0 or index >= runtime_entities.size():
		return
	var entity: Dictionary = runtime_entities[index]
	if not bool(entity.get("active", true)) or EncounterModel.kind(entity) != "enemy":
		return
	entity["health"] = int(entity.get("health", 1)) - amount
	entity["hit_flash"] = 0.16
	var definition_data: Dictionary = entity.get("definition", {})
	if int(entity.get("health", 0)) <= 0:
		entity["active"] = false
		session_state[String(entity.get("state_key", ""))] = "defeated"
		clock_shards += int(definition_data.get("reward", 0))
		set_combat_text(
			"%s defeated %s." % [source_name.capitalize(), String(definition_data.get("display_name", "enemy"))]
		)
	else:
		set_combat_text("%s strikes for %d." % [source_name.capitalize(), amount], 0.65)
	runtime_entities[index] = entity


func update_runtime_entities(delta: float) -> void:
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		entity["attack_cooldown"] = maxf(0.0, float(entity.get("attack_cooldown", 0.0)) - delta)
		entity["hit_flash"] = maxf(0.0, float(entity.get("hit_flash", 0.0)) - delta)
		if not bool(entity.get("active", true)) or EncounterModel.kind(entity) != "enemy":
			runtime_entities[index] = entity
			continue
		update_enemy(index, entity, delta)


func update_enemy(index: int, entity: Dictionary, delta: float) -> void:
	var definition_data: Dictionary = entity.get("definition", {})
	var position: Vector2 = entity.get("position", Vector2.ZERO)
	var target_name := "player"
	var target_position := player
	if companion_enabled() and companion_health > 0 and position.distance_to(companion) < position.distance_to(player):
		target_name = "companion"
		target_position = companion
	var distance := position.distance_to(target_position)
	var awareness := float(definition_data.get("awareness_radius", 96.0))
	var attack_range := float(definition_data.get("attack_radius", 18.0))
	if distance <= attack_range and float(entity.get("attack_cooldown", 0.0)) <= 0.0:
		entity["attack_cooldown"] = float(definition_data.get("attack_cooldown", 1.0))
		damage_actor(target_name, int(definition_data.get("attack_damage", 1)), definition_data)
		runtime_entities[index] = entity
		return
	if distance > awareness:
		runtime_entities[index] = entity
		return
	var navigation_target := MapModel.navigation_step(map_data, position, target_position, current_era_id)
	var direction := position.direction_to(navigation_target)
	if direction.length_squared() <= 0.001:
		direction = position.direction_to(target_position)
	if direction.length_squared() > 0.001:
		EncounterModel.update_facing(entity, direction)
		var movement := direction * float(definition_data.get("move_speed", 48.0)) * delta
		entity["position"] = move_entity(index, position, position + movement)
	runtime_entities[index] = entity


func move_entity(index: int, current: Vector2, desired: Vector2) -> Vector2:
	var entity: Dictionary = runtime_entities[index]
	var radius := EncounterModel.collision_radius(entity)
	var target := clamp_point_to_bounds(desired, radius)
	var horizontal := Vector2(target.x, current.y)
	if (
		not MapModel.is_position_blocked(map_data, horizontal, current_era_id, radius)
		and not EncounterModel.position_is_blocked_by_entities(runtime_entities, horizontal, radius, index)
	):
		current.x = horizontal.x
	var vertical := Vector2(current.x, target.y)
	if (
		not MapModel.is_position_blocked(map_data, vertical, current_era_id, radius)
		and not EncounterModel.position_is_blocked_by_entities(runtime_entities, vertical, radius, index)
	):
		current.y = vertical.y
	return current


func damage_actor(actor_id: String, amount: int, attacker: Dictionary) -> void:
	var attacker_name := String(attacker.get("display_name", "Enemy"))
	if actor_id == "player":
		if player_hurt_lock > 0.0:
			return
		player_hurt_lock = 0.55
		player_health -= amount
		set_combat_text("%s hits %s for %d." % [attacker_name, player_name().capitalize(), amount])
		if player_health <= 0:
			rewind_after_defeat()
		return
	if companion_hurt_lock > 0.0:
		return
	companion_hurt_lock = 0.65
	companion_health -= amount
	set_combat_text("%s wounds %s for %d." % [attacker_name, companion_name().capitalize(), amount])
	if companion_health <= 0:
		companion_health = maxi(1, actor_health("companion", 24) / 2)
		var fallback := player - facing * COMPANION_FOLLOW_DISTANCE
		companion = MapModel.nearest_recovery_point(map_data, player, current_era_id, fallback)
		set_combat_text("%s retreats, then finds the trail again." % companion_name().capitalize(), 1.4)


func rewind_after_defeat() -> void:
	player_health = actor_health("player", 32)
	companion_health = actor_health("companion", 24)
	reset_actor_positions()
	sync_runtime_entities(false)
	transition_lock = 0.9
	set_combat_text("The hour recoils. The crossing remembers you alive.", 1.8)


func collect_nearby_pickups() -> void:
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		if not bool(entity.get("active", true)) or EncounterModel.kind(entity) != "pickup":
			continue
		var radius := maxf(12.0, EncounterModel.interaction_radius(entity))
		if player.distance_to(entity.get("position", Vector2.ZERO)) <= radius:
			collect_pickup(index)


func collect_pickup(index: int) -> void:
	if index < 0 or index >= runtime_entities.size():
		return
	var entity: Dictionary = runtime_entities[index]
	if not bool(entity.get("active", true)) or EncounterModel.kind(entity) != "pickup":
		return
	var definition_data: Dictionary = entity.get("definition", {})
	entity["active"] = false
	runtime_entities[index] = entity
	session_state[String(entity.get("state_key", ""))] = "collected"
	clock_shards += int(definition_data.get("pickup_value", 1))
	set_combat_text(String(definition_data.get("pickup_label", "Item recovered.")), 1.35)


func set_combat_text(value: String, duration: float = 1.0) -> void:
	combat_text = value
	combat_text_timer = duration


func draw_game() -> void:
	var era_data: Dictionary = current_era()
	var canvas_data: Dictionary = map_data.get("canvas", {})
	var width := float(canvas_data.get("width", VIEW.x))
	var height := float(canvas_data.get("height", VIEW.y))
	var offset := camera_offset()
	draw_set_transform(-offset, 0.0, Vector2.ONE)
	draw_rect(Rect2(0, 0, width, height), palette_color("sky", "819a91"))
	var bounds: Dictionary = map_data.get("bounds", {})
	var ground_top := float(bounds.get("top", 96.0))
	draw_rect(Rect2(0, ground_top, width, height - ground_top), palette_color("ground", "4f6550"))
	draw_terrain_cells()
	for value in era_data.get("landmarks", []):
		if typeof(value) == TYPE_DICTIONARY:
			draw_landmark(value)
	draw_connections()
	draw_runtime_entities()
	if companion_enabled():
		draw_companion()
	draw_player()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_hud(era_data)
	if dialogue.is_empty():
		draw_centered("MOVE: WASD   ATTACK: SPACE / C   INTERACT: E / Z   SHIFT: Q / X", 348, 9, Color("d7d0bd"))
	else:
		draw_dialogue()
	if not combat_text.is_empty() and dialogue.is_empty():
		draw_rect(Rect2(118, 66, 404, 26), Color(0.03, 0.04, 0.05, 0.82))
		draw_centered(combat_text, 84, 11, Color("f4dfaa"))
	if transition_lock > 0.0:
		var alpha := clampf((transition_lock - 0.12) / 0.68, 0.0, 0.9)
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.03, 0.04, 0.05, alpha))


func draw_runtime_entities() -> void:
	for value in runtime_entities:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = value
		if bool(entity.get("active", true)):
			draw_runtime_entity(entity)


func draw_runtime_entity(entity: Dictionary) -> void:
	var definition_data: Dictionary = entity.get("definition", {})
	var position: Vector2 = entity.get("position", Vector2.ZERO)
	var appearance: Dictionary = definition_data.get("appearance", {})
	var shape := String(appearance.get("shape", "marker"))
	var base_color := ObjectCatalog.appearance_color(definition_data, "color", "66717a")
	var accent := ObjectCatalog.appearance_color(definition_data, "accent", "d4c68f")
	if float(entity.get("hit_flash", 0.0)) > 0.0:
		base_color = Color.WHITE
		accent = Color("fff2c2")
	match shape:
		"crate":
			draw_rect(Rect2(position - Vector2(11, 9), Vector2(22, 18)), base_color)
			draw_rect(Rect2(position - Vector2(9, 7), Vector2(18, 14)), accent, false, 2.0)
			draw_line(position + Vector2(-9, -7), position + Vector2(9, 7), accent.darkened(0.25), 1.0)
		"person":
			draw_circle(position + Vector2(0, -10), 6, accent)
			draw_rect(Rect2(position + Vector2(-7, -4), Vector2(14, 20)), base_color)
		"beast":
			draw_circle(position + Vector2(-3, 0), 9, base_color)
			var facing_vector := EncounterModel.facing_vector(String(entity.get("facing", "down")))
			draw_circle(position + facing_vector * 7.0 + Vector2(0, -4), 6, accent)
			draw_line(position + Vector2(-10, -2), position + Vector2(-17, -8), base_color, 3.0)
		"orb":
			var pulse := 1.0 + sin(elapsed * 5.0 + position.x) * 0.18
			draw_circle(position, 6.0 * pulse, base_color)
			draw_circle(position, 11.0 * pulse, Color(accent, 0.55), false, 2.0)
		"pillar":
			draw_rect(Rect2(position - Vector2(7, 15), Vector2(14, 30)), base_color)
			draw_rect(Rect2(position - Vector2(10, 17), Vector2(20, 4)), accent)
		_:
			draw_circle(position, 8, base_color)
	if EncounterModel.kind(entity) == "enemy":
		var maximum := maxi(1, int(definition_data.get("max_health", 1)))
		var health := clampi(int(entity.get("health", maximum)), 0, maximum)
		if health < maximum:
			draw_rect(Rect2(position + Vector2(-13, -23), Vector2(26, 3)), Color("241b1b"))
			draw_rect(Rect2(position + Vector2(-13, -23), Vector2(26.0 * float(health) / float(maximum), 3)), Color("d6624f"))


func draw_player() -> void:
	super.draw_player()
	if player_attack_timer > 0.0:
		var angle := facing.angle()
		draw_arc(player + Vector2(0, -2), 27.0, angle - 0.8, angle + 0.8, 14, Color("f5dfa0"), 3.0)


func draw_companion() -> void:
	super.draw_companion()
	if companion_attack_timer > 0.0:
		draw_circle(companion + Vector2(4, -5), 19, Color(0.95, 0.77, 0.42, 0.72), false, 2.0)


func draw_hud(era_data: Dictionary) -> void:
	draw_rect(Rect2(10, 9, 272, 48), Color(0.03, 0.04, 0.05, 0.88))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(21, 29),
		"%s  %d / %d" % [player_name(), player_health, actor_health("player", 32)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color("f0e5c7")
	)
	if companion_enabled():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(21, 48),
			"%s  %d / %d" % [companion_name(), companion_health, actor_health("companion", 24)],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color("c8b998")
		)
	draw_string(ThemeDB.fallback_font, Vector2(205, 47), "SHARDS %02d" % clock_shards, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("e8cf72"))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(472, 24),
		String(era_data.get("display_name", current_era_id.capitalize())).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("f3df9b")
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(472, 42),
		String(map_data.get("display_name", "MAP")).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		Color("d2c8aa")
	)
