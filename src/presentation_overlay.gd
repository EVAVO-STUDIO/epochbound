extends Node2D

const PresentationCatalog = preload("res://src/content/presentation_catalog.gd")
const EncounterModel = preload("res://src/game/encounter_model.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")

const VIEW := Vector2(640, 360)
const FLOW_TITLE := 1
const FLOW_INTRO := 3
const FLOW_GAME := 4
const FLOW_PAUSED := 5
const FOOTSTEP_DISTANCE := 13.0
const MAX_FOOTSTEP_PUFFS := 20
const MAX_IMPACT_BURSTS := 18

var presentation_definitions: Dictionary = {}
var presentation_bindings: Array[Dictionary] = []
var active_profile: Dictionary = {}
var active_profile_id := ""
var loaded_campaign_key := ""
var loaded_profile_key := ""
var atmosphere_particles: Array[Dictionary] = []
var footstep_puffs: Array[Dictionary] = []
var impact_bursts: Array[Dictionary] = []
var entity_hit_state: Dictionary = {}
var previous_player := Vector2.ZERO
var previous_player_health := -1
var previous_companion_health := -1
var previous_attack_timer := 0.0
var previous_era_id := ""
var footstep_accumulator := 0.0
var movement_amount := 0.0
var era_flash := 0.0
var impact_flash := 0.0
var attack_glint := 0.0
var shake_timer := 0.0
var shake_strength := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1000
	initialize_from_runtime()
	queue_redraw()


func _exit_tree() -> void:
	var runtime := runtime_root()
	if runtime is Node2D:
		(runtime as Node2D).position = Vector2.ZERO


func runtime_root() -> Node:
	return get_parent()


func initialize_from_runtime() -> void:
	var runtime := runtime_root()
	if runtime == null:
		return
	var campaign_value: Variant = runtime.get("campaign")
	var campaign_data: Dictionary = campaign_value if typeof(campaign_value) == TYPE_DICTIONARY else {}
	var campaign_path := str(runtime.get("campaign_path"))
	var campaign_id := str(campaign_data.get("id", "fallback"))
	loaded_campaign_key = "%s|%s" % [campaign_path, campaign_id]
	var catalog_result := PresentationCatalog.load_catalogs(campaign_path, campaign_data)
	presentation_definitions = catalog_result.get("definitions", {})
	var bindings_value: Variant = catalog_result.get("bindings", [])
	presentation_bindings.clear()
	if typeof(bindings_value) == TYPE_ARRAY:
		for binding_value in bindings_value:
			if typeof(binding_value) == TYPE_DICTIONARY:
				presentation_bindings.append((binding_value as Dictionary).duplicate(true))
	previous_player = runtime_vector("player")
	previous_player_health = runtime_integer("player_health", -1)
	previous_companion_health = runtime_integer("companion_health", -1)
	previous_attack_timer = runtime_number("player_attack_timer", 0.0)
	previous_era_id = str(runtime.get("current_era_id"))
	resolve_active_profile(true)


func _process(delta: float) -> void:
	var runtime := runtime_root()
	if runtime == null:
		return
	var campaign_value: Variant = runtime.get("campaign")
	var campaign_data: Dictionary = campaign_value if typeof(campaign_value) == TYPE_DICTIONARY else {}
	var current_campaign_key := "%s|%s" % [str(runtime.get("campaign_path")), str(campaign_data.get("id", "fallback"))]
	if current_campaign_key != loaded_campaign_key:
		initialize_from_runtime()
	resolve_active_profile(false)
	update_reactions(delta)
	update_atmosphere(delta)
	update_footsteps(delta)
	update_impact_bursts(delta)
	apply_root_shake()
	queue_redraw()


func resolve_active_profile(force: bool) -> void:
	var runtime := runtime_root()
	if runtime == null:
		return
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	var map_id := str(map_data.get("id", ""))
	var era_id := str(runtime.get("current_era_id"))
	var profile_key := "%s|%s" % [map_id, era_id]
	if not force and profile_key == loaded_profile_key:
		return
	loaded_profile_key = profile_key
	active_profile = PresentationCatalog.resolved_profile(presentation_definitions, presentation_bindings, map_id, era_id)
	active_profile_id = str(active_profile.get("id", PresentationCatalog.DEFAULT_PROFILE_ID))
	seed_atmosphere(map_id, era_id)
	if not force:
		era_flash = 1.0
		trigger_shake(2.5, 0.24)


func seed_atmosphere(map_id: String, era_id: String) -> void:
	atmosphere_particles.clear()
	var density := clampi(PresentationCatalog.integer(active_profile, "atmosphere", "density", 18), 0, 128)
	var seed_base := absi((active_profile_id + "|" + map_id + "|" + era_id).hash())
	for index in range(density):
		var seed := seed_base + index * 7919
		var x := float(posmod(seed * 37 + index * 17, int(VIEW.x)))
		var y := float(posmod(seed * 83 + index * 29, int(VIEW.y)))
		var scale := 0.55 + float(posmod(seed, 100)) / 100.0
		var phase := float(posmod(seed * 13, 628)) / 100.0
		atmosphere_particles.append({
			"position": Vector2(x, y),
			"scale": scale,
			"phase": phase
		})


func update_reactions(delta: float) -> void:
	era_flash = maxf(0.0, era_flash - delta * 1.8)
	impact_flash = maxf(0.0, impact_flash - delta * 4.8)
	attack_glint = maxf(0.0, attack_glint - delta * 5.5)
	shake_timer = maxf(0.0, shake_timer - delta)
	if shake_timer <= 0.0:
		shake_strength = 0.0
	var runtime := runtime_root()
	var player_health := runtime_integer("player_health", previous_player_health)
	var companion_health := runtime_integer("companion_health", previous_companion_health)
	if previous_player_health >= 0 and player_health < previous_player_health:
		trigger_impact(runtime_vector("player"), true)
	if previous_companion_health >= 0 and companion_health < previous_companion_health:
		trigger_impact(runtime_vector("companion"), false)
	previous_player_health = player_health
	previous_companion_health = companion_health
	var attack_timer := runtime_number("player_attack_timer", 0.0)
	if attack_timer > 0.0 and previous_attack_timer <= 0.0:
		attack_glint = 1.0
	previous_attack_timer = attack_timer
	var era_id := str(runtime.get("current_era_id"))
	if not previous_era_id.is_empty() and era_id != previous_era_id:
		era_flash = 1.0
		trigger_shake(3.0, 0.28)
	previous_era_id = era_id
	update_entity_hits()


func update_entity_hits() -> void:
	var entities := runtime_array("runtime_entities")
	var next_state: Dictionary = {}
	for entity_value in entities:
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value
		var entity_id := str(entity.get("placement_id", entity.get("state_key", "")))
		if entity_id.is_empty():
			continue
		var hit_flash := float(entity.get("hit_flash", 0.0))
		var was_hit := bool(entity_hit_state.get(entity_id, false))
		var is_hit := hit_flash > 0.0
		if is_hit and not was_hit:
			trigger_impact(entity.get("position", Vector2.ZERO), false)
		next_state[entity_id] = is_hit
	entity_hit_state = next_state


func trigger_impact(world_position: Vector2, player_hurt: bool) -> void:
	impact_flash = 1.0
	trigger_shake(5.0 if player_hurt else 3.2, 0.24 if player_hurt else 0.16)
	impact_bursts.append({
		"position": world_position,
		"life": 0.34,
		"maximum": 0.34,
		"danger": player_hurt
	})
	if impact_bursts.size() > MAX_IMPACT_BURSTS:
		impact_bursts.pop_front()


func trigger_shake(strength: float, duration: float) -> void:
	var maximum := PresentationCatalog.number(active_profile, "camera", "maximum_shake", 5.0)
	shake_strength = minf(maximum, maxf(shake_strength, strength))
	shake_timer = maxf(shake_timer, duration)


func apply_root_shake() -> void:
	var runtime := runtime_root()
	if not runtime is Node2D:
		return
	var offset := Vector2.ZERO
	if shake_timer > 0.0 and runtime_flow() in [FLOW_GAME, FLOW_PAUSED]:
		var time := Time.get_ticks_msec() * 0.001
		offset = Vector2(
			roundf(sin(time * 67.0) * shake_strength),
			roundf(cos(time * 53.0) * shake_strength * 0.65)
		)
	(runtime as Node2D).position = offset


func update_atmosphere(delta: float) -> void:
	var kind := PresentationCatalog.text(active_profile, "atmosphere", "kind", "motes")
	var speed := PresentationCatalog.number(active_profile, "atmosphere", "speed", 8.0)
	for index in range(atmosphere_particles.size()):
		var particle: Dictionary = atmosphere_particles[index]
		var position: Vector2 = particle.get("position", Vector2.ZERO)
		var scale := float(particle.get("scale", 1.0))
		var phase := float(particle.get("phase", 0.0))
		match kind:
			"embers", "cinders":
				position.y -= speed * scale * delta
				position.x += sin(phase + position.y * 0.025) * speed * 0.18 * delta
			"fireflies":
				position.x += sin(phase + Time.get_ticks_msec() * 0.001) * speed * 0.22 * delta
				position.y += cos(phase * 1.7 + Time.get_ticks_msec() * 0.0012) * speed * 0.18 * delta
			"dust":
				position.x += speed * scale * 0.24 * delta
				position.y += sin(phase + position.x * 0.02) * speed * 0.08 * delta
			_:
				position.x += speed * scale * 0.16 * delta
				position.y += speed * scale * 0.07 * delta
		if position.x < -8.0:
			position.x = VIEW.x + 8.0
		elif position.x > VIEW.x + 8.0:
			position.x = -8.0
		if position.y < -8.0:
			position.y = VIEW.y + 8.0
		elif position.y > VIEW.y + 8.0:
			position.y = -8.0
		particle["position"] = position
		atmosphere_particles[index] = particle


func update_footsteps(delta: float) -> void:
	var current_player := runtime_vector("player")
	var distance := current_player.distance_to(previous_player)
	movement_amount = lerpf(movement_amount, clampf(distance / maxf(delta, 0.001), 0.0, 1.0), clampf(delta * 12.0, 0.0, 1.0))
	if runtime_flow() == FLOW_GAME and distance > 0.01 and active_cinematic_id().is_empty():
		footstep_accumulator += distance
		if footstep_accumulator >= FOOTSTEP_DISTANCE:
			footstep_accumulator = fmod(footstep_accumulator, FOOTSTEP_DISTANCE)
			footstep_puffs.append({"position": current_player, "life": 0.48, "maximum": 0.48})
			if footstep_puffs.size() > MAX_FOOTSTEP_PUFFS:
				footstep_puffs.pop_front()
	previous_player = current_player
	for index in range(footstep_puffs.size() - 1, -1, -1):
		var puff: Dictionary = footstep_puffs[index]
		puff["life"] = maxf(0.0, float(puff.get("life", 0.0)) - delta)
		if float(puff.get("life", 0.0)) <= 0.0:
			footstep_puffs.remove_at(index)
		else:
			footstep_puffs[index] = puff


func update_impact_bursts(delta: float) -> void:
	for index in range(impact_bursts.size() - 1, -1, -1):
		var burst: Dictionary = impact_bursts[index]
		burst["life"] = maxf(0.0, float(burst.get("life", 0.0)) - delta)
		if float(burst.get("life", 0.0)) <= 0.0:
			impact_bursts.remove_at(index)
		else:
			impact_bursts[index] = burst


func _draw() -> void:
	var flow := runtime_flow()
	if flow == FLOW_TITLE:
		draw_title_finish()
	elif flow == FLOW_INTRO:
		draw_intro_finish()
	elif flow == FLOW_GAME or flow == FLOW_PAUSED:
		draw_game_finish()
	else:
		draw_screen_texture(0.7)


func draw_title_finish() -> void:
	var frame := profile_color("ui_frame", "a58b53")
	var shadow := profile_color("shadow", "263033")
	draw_rect(Rect2(5, 5, VIEW.x - 10, VIEW.y - 10), Color(frame, 0.42), false, 1.0)
	draw_corner_brackets(Rect2(16, 16, VIEW.x - 32, VIEW.y - 32), frame)
	for index in range(7):
		var radius := 50.0 + index * 4.0
		draw_arc(Vector2(320, 81), radius, -2.55, -0.58, 24, Color(shadow, 0.12 + index * 0.012), 1.0)
	draw_screen_texture(1.0)


func draw_intro_finish() -> void:
	var frame := profile_color("ui_frame", "9f8651")
	draw_corner_brackets(Rect2(52, 46, 536, 254), frame)
	draw_screen_texture(1.0)


func draw_game_finish() -> void:
	var cinematic_active := not active_cinematic_id().is_empty()
	var menu_open := runtime_boolean("inventory_open") or runtime_boolean("story_journal_open") or runtime_boolean("save_overlay_open") or runtime_boolean("merchant_open")
	if not cinematic_active and not menu_open:
		draw_world_accents()
		draw_actor_overlays()
		draw_runtime_entity_overlays()
		draw_footstep_puffs()
		draw_impact_bursts()
		draw_adventure_hud()
		draw_dialogue_finish()
	elif menu_open:
		draw_menu_frame()
	if not cinematic_active:
		draw_atmosphere()
	draw_screen_texture(1.0)
	if era_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(profile_color("accent", "d49a45"), era_flash * 0.16))
	if impact_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(profile_color("light", "d7c99b"), impact_flash * 0.08))


func draw_world_accents() -> void:
	var runtime := runtime_root()
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	var map_id := str(map_data.get("id", ""))
	var offset := runtime_camera_offset()
	var shadow := profile_color("shadow", "263033")
	var midtone := profile_color("midtone", "59665c")
	var accent := profile_color("accent", "d49a45")
	var seed_base := absi((map_id + active_profile_id).hash())
	for index in range(28):
		var seed := seed_base + index * 3253
		var world_position := Vector2(
			float(posmod(seed * 19, 760)) - 60.0,
			118.0 + float(posmod(seed * 43, 260))
		)
		var screen_position := world_position - offset
		if screen_position.x < -12.0 or screen_position.x > VIEW.x + 12.0 or screen_position.y < 80.0 or screen_position.y > VIEW.y + 12.0:
			continue
		var tall := 2.0 + float(posmod(seed, 5))
		draw_line(screen_position, screen_position + Vector2(-2, -tall), Color(midtone, 0.35), 1.0)
		draw_line(screen_position, screen_position + Vector2(2, -tall * 0.8), Color(shadow, 0.34), 1.0)
		if posmod(seed, 7) == 0:
			draw_rect(Rect2(screen_position + Vector2(-1, -tall - 2), Vector2(2, 2)), Color(accent, 0.34))


func draw_actor_overlays() -> void:
	var player_world := runtime_vector("player")
	var companion_world := runtime_vector("companion")
	var player_screen := world_to_screen(player_world)
	var companion_screen := world_to_screen(companion_world)
	draw_player_sprite(player_screen)
	if runtime_companion_enabled():
		draw_companion_sprite(companion_screen)


func draw_player_sprite(position: Vector2) -> void:
	var runtime := runtime_root()
	var facing_value: Variant = runtime.get("facing")
	var facing_vector: Vector2 = facing_value if facing_value is Vector2 else Vector2.DOWN
	var bob_amount := PresentationCatalog.number(active_profile, "actors", "movement_bob", 1.6)
	var bob := roundf(sin(Time.get_ticks_msec() * 0.018) * bob_amount * clampf(movement_amount, 0.0, 1.0))
	var center := position + Vector2(0, bob)
	var ink := profile_color("ink", "13161a")
	var shadow := profile_color("shadow", "263033")
	var light := profile_color("light", "d7c99b")
	var accent := profile_color("accent", "d49a45")
	draw_shadow(center + Vector2(0, 7), 11.0, 4.0)
	if runtime_has_capability("illuminate_dark"):
		var direction := facing_vector.normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		var origin := center + direction * 5.0 + Vector2(0, -5)
		var beam := PackedVector2Array([
			origin + perpendicular * 3.0,
			origin + direction * 80.0 + perpendicular * 22.0,
			origin + direction * 80.0 - perpendicular * 22.0,
			origin - perpendicular * 3.0
		])
		draw_colored_polygon(beam, Color(light, 0.055))
	# Legs and boots.
	draw_rect(Rect2(center + Vector2(-7, 5), Vector2(5, 10)), ink)
	draw_rect(Rect2(center + Vector2(2, 5), Vector2(5, 10)), ink)
	draw_rect(Rect2(center + Vector2(-8, 12), Vector2(6, 3)), shadow)
	draw_rect(Rect2(center + Vector2(2, 12), Vector2(6, 3)), shadow)
	# Coat, shoulder padding and brass clasp.
	draw_rect(Rect2(center + Vector2(-9, -9), Vector2(18, 17)), shadow)
	draw_rect(Rect2(center + Vector2(-7, -7), Vector2(14, 13)), Color("334b68"))
	draw_rect(Rect2(center + Vector2(-9, -7), Vector2(3, 8)), ink)
	draw_rect(Rect2(center + Vector2(6, -7), Vector2(3, 8)), ink)
	draw_rect(Rect2(center + Vector2(-2, -5), Vector2(4, 3)), accent)
	# Head and hair use hard pixel blocks rather than smooth circles.
	draw_rect(Rect2(center + Vector2(-6, -19), Vector2(12, 11)), Color("d8a77c"))
	draw_rect(Rect2(center + Vector2(-6, -21), Vector2(12, 5)), ink)
	draw_rect(Rect2(center + Vector2(-7, -18), Vector2(3, 6)), ink)
	var side := signf(facing_vector.x)
	if absf(facing_vector.x) > absf(facing_vector.y):
		draw_rect(Rect2(center + Vector2(4 * side, -16), Vector2(2, 2)), light)
	else:
		draw_rect(Rect2(center + Vector2(-3, -16), Vector2(2, 2)), light)
		draw_rect(Rect2(center + Vector2(2, -16), Vector2(2, 2)), light)
	# Weapon/tool silhouette follows facing.
	var weapon_start := center + Vector2(0, -2)
	var weapon_end := weapon_start + facing_vector.normalized() * (22.0 + attack_glint * 5.0)
	draw_line(weapon_start, weapon_end, ink, 4.0)
	draw_line(weapon_start, weapon_end, light, 1.0)
	if attack_glint > 0.0:
		draw_arc(weapon_end, 7.0 + attack_glint * 6.0, 0.0, TAU, 12, Color(accent, attack_glint), 2.0)


func draw_companion_sprite(position: Vector2) -> void:
	var bob := roundf(sin(Time.get_ticks_msec() * 0.02 + 1.7) * 1.2 * clampf(movement_amount, 0.0, 1.0))
	var center := position + Vector2(0, bob)
	var ink := profile_color("ink", "13161a")
	var shadow := Color("35251f")
	var fur := Color("6a4935")
	var light := Color("b78a62")
	var accent := profile_color("accent", "d49a45")
	draw_shadow(center + Vector2(0, 6), 12.0, 4.0)
	draw_rect(Rect2(center + Vector2(-10, -5), Vector2(17, 10)), shadow)
	draw_rect(Rect2(center + Vector2(-7, -7), Vector2(14, 10)), fur)
	draw_rect(Rect2(center + Vector2(5, -10), Vector2(9, 9)), fur)
	draw_rect(Rect2(center + Vector2(10, -7), Vector2(5, 4)), light)
	draw_rect(Rect2(center + Vector2(7, -13), Vector2(3, 5)), ink)
	draw_rect(Rect2(center + Vector2(12, -12), Vector2(3, 5)), ink)
	draw_rect(Rect2(center + Vector2(11, -9), Vector2(2, 2)), accent)
	draw_line(center + Vector2(-10, -3), center + Vector2(-17, -10), shadow, 3.0)
	draw_rect(Rect2(center + Vector2(-7, 4), Vector2(3, 7)), ink)
	draw_rect(Rect2(center + Vector2(3, 4), Vector2(3, 7)), ink)


func draw_runtime_entity_overlays() -> void:
	var entities := runtime_array("runtime_entities")
	for entity_value in entities:
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value
		if not bool(entity.get("active", true)):
			continue
		draw_entity_sprite(entity)


func draw_entity_sprite(entity: Dictionary) -> void:
	var definition_value: Variant = entity.get("definition", {})
	var definition_data: Dictionary = definition_value if typeof(definition_value) == TYPE_DICTIONARY else {}
	var position_value: Variant = entity.get("position", Vector2.ZERO)
	var world_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
	var position := world_to_screen(world_position)
	var appearance_value: Variant = definition_data.get("appearance", {})
	var appearance: Dictionary = appearance_value if typeof(appearance_value) == TYPE_DICTIONARY else {}
	var shape := str(appearance.get("shape", "marker"))
	var base_color := ObjectCatalog.appearance_color(definition_data, "color", "66717a")
	var accent := ObjectCatalog.appearance_color(definition_data, "accent", "d4c68f")
	var ink := profile_color("ink", "13161a")
	if float(entity.get("hit_flash", 0.0)) > 0.0:
		base_color = Color.WHITE
		accent = profile_color("light", "d7c99b")
	draw_shadow(position + Vector2(0, 7), 10.0, 3.5)
	match shape:
		"crate":
			draw_rect(Rect2(position + Vector2(-12, -9), Vector2(24, 18)), ink)
			draw_rect(Rect2(position + Vector2(-10, -8), Vector2(20, 15)), base_color)
			draw_rect(Rect2(position + Vector2(-8, -6), Vector2(16, 11)), accent.darkened(0.25), false, 2.0)
			draw_line(position + Vector2(-8, -6), position + Vector2(8, 5), ink, 2.0)
		"person":
			draw_rect(Rect2(position + Vector2(-8, -7), Vector2(16, 21)), ink)
			draw_rect(Rect2(position + Vector2(-6, -6), Vector2(12, 17)), base_color)
			draw_rect(Rect2(position + Vector2(-5, -17), Vector2(10, 10)), accent)
			draw_rect(Rect2(position + Vector2(-6, -19), Vector2(12, 4)), ink)
		"beast":
			draw_rect(Rect2(position + Vector2(-11, -6), Vector2(18, 12)), ink)
			draw_rect(Rect2(position + Vector2(-8, -8), Vector2(16, 11)), base_color)
			var facing_vector := EncounterModel.facing_vector(str(entity.get("facing", "down")))
			var head := position + facing_vector * 8.0 + Vector2(0, -5)
			draw_rect(Rect2(head + Vector2(-5, -5), Vector2(10, 9)), accent)
			draw_rect(Rect2(head + Vector2(-4, -7), Vector2(3, 4)), ink)
			draw_rect(Rect2(head + Vector2(2, -7), Vector2(3, 4)), ink)
			draw_rect(Rect2(head + facing_vector * 3.0 + Vector2(-1, -2), Vector2(2, 2)), profile_color("danger", "b94d45"))
		"orb":
			var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006 + world_position.x) * 0.16
			draw_circle(position, 10.0 * pulse, Color(ink, 0.82))
			draw_rect(Rect2(position - Vector2(5, 5), Vector2(10, 10)), base_color)
			draw_rect(Rect2(position - Vector2(2, 2), Vector2(4, 4)), accent)
		"pillar":
			draw_rect(Rect2(position + Vector2(-9, -17), Vector2(18, 34)), ink)
			draw_rect(Rect2(position + Vector2(-7, -15), Vector2(14, 30)), base_color)
			draw_rect(Rect2(position + Vector2(-11, -18), Vector2(22, 5)), accent)
		_:
			draw_rect(Rect2(position + Vector2(-7, -7), Vector2(14, 14)), base_color)
	if EncounterModel.kind(entity) == "enemy":
		var maximum := maxi(1, int(definition_data.get("max_health", 1)))
		var health := clampi(int(entity.get("health", maximum)), 0, maximum)
		if health < maximum:
			draw_notched_bar(Rect2(position + Vector2(-15, -25), Vector2(30, 4)), health, maximum, profile_color("danger", "b94d45"))


func draw_footstep_puffs() -> void:
	var midtone := profile_color("midtone", "59665c")
	for puff_value in footstep_puffs:
		var puff: Dictionary = puff_value
		var life := float(puff.get("life", 0.0))
		var maximum := maxf(0.001, float(puff.get("maximum", 0.48)))
		var progress := 1.0 - life / maximum
		var position_value: Variant = puff.get("position", Vector2.ZERO)
		var world_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var position := world_to_screen(world_position) + Vector2(0, 6 - progress * 4.0)
		var alpha := (1.0 - progress) * 0.25
		draw_rect(Rect2(position + Vector2(-5 - progress * 4.0, 0), Vector2(4, 2)), Color(midtone, alpha))
		draw_rect(Rect2(position + Vector2(2 + progress * 3.0, -1), Vector2(3, 2)), Color(midtone, alpha * 0.8))


func draw_impact_bursts() -> void:
	for burst_value in impact_bursts:
		var burst: Dictionary = burst_value
		var life := float(burst.get("life", 0.0))
		var maximum := maxf(0.001, float(burst.get("maximum", 0.34)))
		var progress := 1.0 - life / maximum
		var position_value: Variant = burst.get("position", Vector2.ZERO)
		var world_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var position := world_to_screen(world_position)
		var color := profile_color("danger", "b94d45") if bool(burst.get("danger", false)) else profile_color("accent", "d49a45")
		var radius := 4.0 + progress * 15.0
		draw_arc(position, radius, 0.0, TAU, 12, Color(color, (1.0 - progress) * 0.8), 2.0)
		for index in range(6):
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / 6.0)
			draw_line(position + direction * 4.0, position + direction * (8.0 + progress * 12.0), Color(color, 1.0 - progress), 2.0)


func draw_atmosphere() -> void:
	var kind := PresentationCatalog.text(active_profile, "atmosphere", "kind", "motes")
	if kind == "none":
		return
	var opacity := PresentationCatalog.number(active_profile, "atmosphere", "opacity", 0.24)
	var light := profile_color("light", "d7c99b")
	var accent := profile_color("accent", "d49a45")
	for particle_value in atmosphere_particles:
		var particle: Dictionary = particle_value
		var position_value: Variant = particle.get("position", Vector2.ZERO)
		var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var scale := float(particle.get("scale", 1.0))
		var phase := float(particle.get("phase", 0.0))
		match kind:
			"embers", "cinders":
				draw_rect(Rect2(position, Vector2(maxf(1.0, scale * 2.0), maxf(1.0, scale * 3.0))), Color(accent, opacity * (0.65 + sin(phase + Time.get_ticks_msec() * 0.008) * 0.25)))
			"fireflies":
				draw_circle(position, 1.0 + scale, Color(light, opacity * (0.7 + sin(phase + Time.get_ticks_msec() * 0.004) * 0.3)))
			"dust":
				draw_rect(Rect2(position, Vector2(2, 1)), Color(light, opacity * 0.55))
			_:
				draw_rect(Rect2(position, Vector2(1 + floorf(scale), 1 + floorf(scale))), Color(light, opacity * 0.7))


func draw_adventure_hud() -> void:
	var fill := profile_color("ui_fill", "15191b")
	var frame := profile_color("ui_frame", "9f8651")
	var text := profile_color("ui_text", "eee3c6")
	var accent := profile_color("accent", "d49a45")
	var danger := profile_color("danger", "b94d45")
	# Cover the prototype HUD with a compact carved-metal frame.
	draw_rect(Rect2(7, 7, 286, 57), Color(fill, 0.97))
	draw_panel_frame(Rect2(7, 7, 286, 57), frame)
	var player_health := runtime_integer("player_health", 1)
	var player_max := runtime_actor_max_health("player", 32)
	draw_string(ThemeDB.fallback_font, Vector2(19, 24), runtime_player_name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 80, 10, text)
	draw_notched_bar(Rect2(92, 16, 118, 8), player_health, player_max, danger)
	draw_string(ThemeDB.fallback_font, Vector2(218, 24), "%02d/%02d" % [player_health, player_max], HORIZONTAL_ALIGNMENT_LEFT, 55, 8, text.darkened(0.08))
	if runtime_companion_enabled():
		var companion_health := runtime_integer("companion_health", 1)
		var companion_max := runtime_actor_max_health("companion", 24)
		draw_string(ThemeDB.fallback_font, Vector2(19, 43), runtime_companion_name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 80, 9, text.darkened(0.1))
		draw_notched_bar(Rect2(92, 35, 118, 7), companion_health, companion_max, accent)
		draw_string(ThemeDB.fallback_font, Vector2(218, 43), "%02d/%02d" % [companion_health, companion_max], HORIZONTAL_ALIGNMENT_LEFT, 55, 8, text.darkened(0.15))
	draw_string(ThemeDB.fallback_font, Vector2(19, 57), "CLOCKGLASS %02d" % runtime_integer("clock_shards", 0), HORIZONTAL_ALIGNMENT_LEFT, 126, 8, accent)
	# Map and era plaque.
	draw_rect(Rect2(438, 7, 195, 46), Color(fill, 0.95))
	draw_panel_frame(Rect2(438, 7, 195, 46), frame)
	var map_value: Variant = runtime_root().get("map_data")
	var map_data: Dictionary = map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	draw_string(ThemeDB.fallback_font, Vector2(450, 25), str(map_data.get("display_name", "MAP")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 170, 10, text)
	draw_string(ThemeDB.fallback_font, Vector2(450, 42), runtime_era_name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 170, 8, accent)
	# Quick restorative panel.
	draw_rect(Rect2(7, 69, 128, 30), Color(fill, 0.93))
	draw_panel_frame(Rect2(7, 69, 128, 30), frame.darkened(0.15))
	draw_string(ThemeDB.fallback_font, Vector2(17, 84), quick_item_label(), HORIZONTAL_ALIGNMENT_LEFT, 108, 8, text.darkened(0.08))
	draw_string(ThemeDB.fallback_font, Vector2(17, 95), "V / RB", HORIZONTAL_ALIGNMENT_LEFT, 60, 7, accent.darkened(0.05))
	if runtime_string("dialogue").is_empty():
		draw_rect(Rect2(144, 338, 352, 15), Color(fill, 0.78))
		draw_string(ThemeDB.fallback_font, Vector2(153, 349), "MOVE  •  ATTACK  •  INTERACT  •  SHIFT", HORIZONTAL_ALIGNMENT_CENTER, 334, 7, text.darkened(0.22))


func draw_dialogue_finish() -> void:
	var dialogue := runtime_string("dialogue")
	if dialogue.is_empty():
		return
	var fill := profile_color("ui_fill", "15191b")
	var frame := profile_color("ui_frame", "9f8651")
	var text := profile_color("ui_text", "eee3c6")
	draw_rect(Rect2(19, 260, 602, 88), Color(fill, 0.985))
	draw_panel_frame(Rect2(19, 260, 602, 88), frame)
	draw_rect(Rect2(27, 268, 10, 72), frame.darkened(0.28))
	draw_text_lines_wrapped(dialogue, Vector2(48, 284), 11, text, 550.0)
	draw_string(ThemeDB.fallback_font, Vector2(548, 338), "E / A", HORIZONTAL_ALIGNMENT_LEFT, 54, 7, frame)


func draw_menu_frame() -> void:
	var frame := profile_color("ui_frame", "9f8651")
	draw_corner_brackets(Rect2(25, 16, 590, 328), frame)


func draw_screen_texture(multiplier: float) -> void:
	var scanline_alpha := PresentationCatalog.number(active_profile, "screen", "scanline_alpha", 0.035) * multiplier
	var dither_alpha := PresentationCatalog.number(active_profile, "screen", "dither_alpha", 0.07) * multiplier
	var vignette_alpha := PresentationCatalog.number(active_profile, "screen", "vignette_alpha", 0.24) * multiplier
	var ink := profile_color("ink", "13161a")
	for y in range(1, int(VIEW.y), 3):
		draw_rect(Rect2(0, y, VIEW.x, 1), Color(ink, scanline_alpha))
	var seed_base := absi((active_profile_id + "screen").hash())
	for index in range(72):
		var seed := seed_base + index * 1777
		var position := Vector2(float(posmod(seed * 31, int(VIEW.x))), float(posmod(seed * 47, int(VIEW.y))))
		if posmod(seed, 2) == 0:
			draw_rect(Rect2(position, Vector2(1, 1)), Color(ink, dither_alpha))
	for band in range(7):
		var thickness := 4.0 + band * 4.0
		var alpha := vignette_alpha * (1.0 - float(band) / 7.0) * 0.22
		draw_rect(Rect2(0, band * 4.0, VIEW.x, thickness), Color(ink, alpha))
		draw_rect(Rect2(0, VIEW.y - thickness - band * 4.0, VIEW.x, thickness), Color(ink, alpha))
		draw_rect(Rect2(band * 4.0, 0, thickness, VIEW.y), Color(ink, alpha))
		draw_rect(Rect2(VIEW.x - thickness - band * 4.0, 0, thickness, VIEW.y), Color(ink, alpha))


func draw_shadow(center: Vector2, radius_x: float, radius_y: float) -> void:
	var points := PackedVector2Array()
	for index in range(16):
		var angle := TAU * float(index) / 16.0
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	draw_colored_polygon(points, Color(profile_color("ink", "13161a"), 0.42))


func draw_notched_bar(rect: Rect2, value: int, maximum: int, color: Color) -> void:
	var safe_maximum := maxi(1, maximum)
	draw_rect(rect, profile_color("ink", "13161a"))
	var inner := rect.grow(-1.0)
	var fill_width := floorf(inner.size.x * clampf(float(value) / float(safe_maximum), 0.0, 1.0))
	if fill_width > 0.0:
		draw_rect(Rect2(inner.position, Vector2(fill_width, inner.size.y)), color)
	for index in range(1, 5):
		var x := rect.position.x + rect.size.x * float(index) / 5.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(profile_color("ink", "13161a"), 0.55), 1.0)


func draw_panel_frame(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color, false, 2.0)
	draw_rect(rect.grow(-4.0), Color(color, 0.45), false, 1.0)
	draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(4, 4)), color)
	draw_rect(Rect2(Vector2(rect.end.x - 6, rect.position.y + 2), Vector2(4, 4)), color)
	draw_rect(Rect2(Vector2(rect.position.x + 2, rect.end.y - 6), Vector2(4, 4)), color)
	draw_rect(Rect2(rect.end - Vector2(6, 6), Vector2(4, 4)), color)


func draw_corner_brackets(rect: Rect2, color: Color) -> void:
	var length := 18.0
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		var horizontal_direction := 1.0 if corner.x == rect.position.x else -1.0
		var vertical_direction := 1.0 if corner.y == rect.position.y else -1.0
		draw_line(corner, corner + Vector2(length * horizontal_direction, 0), Color(color, 0.72), 2.0)
		draw_line(corner, corner + Vector2(0, length * vertical_direction), Color(color, 0.72), 2.0)


func draw_text_lines_wrapped(text: String, start: Vector2, font_size: int, color: Color, width: float) -> void:
	var words := text.replace("\n", " \n ").split(" ", false)
	var line := ""
	var lines := PackedStringArray()
	for word_value in words:
		var word := str(word_value)
		if word == "\n":
			lines.append(line.strip_edges())
			line = ""
			continue
		var candidate := word if line.is_empty() else line + " " + word
		if ThemeDB.fallback_font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and not line.is_empty():
			lines.append(line)
			line = word
		else:
			line = candidate
	if not line.is_empty():
		lines.append(line)
	for index in range(mini(3, lines.size())):
		draw_string(ThemeDB.fallback_font, start + Vector2(0, index * (font_size + 5)), lines[index], HORIZONTAL_ALIGNMENT_LEFT, int(width), font_size, color)


func world_to_screen(world_position: Vector2) -> Vector2:
	return world_position - runtime_camera_offset()


func runtime_camera_offset() -> Vector2:
	var runtime := runtime_root()
	if runtime != null and runtime.has_method("camera_offset"):
		var value: Variant = runtime.call("camera_offset")
		if value is Vector2:
			return value
	return Vector2.ZERO


func runtime_flow() -> int:
	return runtime_integer("flow", 0)


func active_cinematic_id() -> String:
	return runtime_string("active_cinematic_id")


func runtime_vector(property_name: String) -> Vector2:
	var runtime := runtime_root()
	if runtime == null:
		return Vector2.ZERO
	var value: Variant = runtime.get(property_name)
	return value if value is Vector2 else Vector2.ZERO


func runtime_number(property_name: String, fallback: float) -> float:
	var runtime := runtime_root()
	if runtime == null:
		return fallback
	var value: Variant = runtime.get(property_name)
	return float(value) if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT else fallback


func runtime_integer(property_name: String, fallback: int) -> int:
	var runtime := runtime_root()
	if runtime == null:
		return fallback
	var value: Variant = runtime.get(property_name)
	return int(value) if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT else fallback


func runtime_boolean(property_name: String) -> bool:
	var runtime := runtime_root()
	if runtime == null:
		return false
	return bool(runtime.get(property_name))


func runtime_string(property_name: String) -> String:
	var runtime := runtime_root()
	return str(runtime.get(property_name)) if runtime != null else ""


func runtime_array(property_name: String) -> Array:
	var runtime := runtime_root()
	if runtime == null:
		return []
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_ARRAY else []


func runtime_actor_max_health(actor_id: String, fallback: int) -> int:
	var runtime := runtime_root()
	if runtime != null and runtime.has_method("actor_health"):
		return int(runtime.call("actor_health", actor_id, fallback))
	return fallback


func runtime_player_name() -> String:
	var runtime := runtime_root()
	return str(runtime.call("player_name")) if runtime != null and runtime.has_method("player_name") else "HERO"


func runtime_companion_name() -> String:
	var runtime := runtime_root()
	return str(runtime.call("companion_name")) if runtime != null and runtime.has_method("companion_name") else "COMPANION"


func runtime_companion_enabled() -> bool:
	var runtime := runtime_root()
	return bool(runtime.call("companion_enabled")) if runtime != null and runtime.has_method("companion_enabled") else false


func runtime_era_name() -> String:
	var runtime := runtime_root()
	if runtime != null and runtime.has_method("current_era"):
		var value: Variant = runtime.call("current_era")
		if typeof(value) == TYPE_DICTIONARY:
			return str((value as Dictionary).get("display_name", runtime_string("current_era_id").capitalize()))
	return runtime_string("current_era_id").capitalize()


func runtime_has_capability(capability_id: String) -> bool:
	var runtime := runtime_root()
	if runtime == null or not runtime.has_method("active_capabilities"):
		return false
	var value: Variant = runtime.call("active_capabilities")
	if value is PackedStringArray:
		return (value as PackedStringArray).has(capability_id)
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).has(capability_id)
	return false


func quick_item_label() -> String:
	var runtime := runtime_root()
	if runtime == null:
		return "NO RESTORATIVE"
	var inventory_value: Variant = runtime.get("inventory")
	var definitions_value: Variant = runtime.get("item_definitions")
	if typeof(inventory_value) != TYPE_DICTIONARY or typeof(definitions_value) != TYPE_DICTIONARY:
		return "NO RESTORATIVE"
	var inventory: Dictionary = inventory_value
	var definitions: Dictionary = definitions_value
	var item_id := InventoryModel.first_healing_item(inventory, definitions)
	if item_id.is_empty():
		return "NO RESTORATIVE"
	var item_data := ItemCatalog.item(definitions, item_id)
	return "%s x%d" % [ItemCatalog.item_name(item_data, item_id), InventoryModel.count(inventory, item_id)]


func profile_color(key: String, fallback: String) -> Color:
	return PresentationCatalog.palette_color(active_profile, key, fallback)
