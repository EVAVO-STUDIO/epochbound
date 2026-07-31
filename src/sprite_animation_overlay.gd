extends "res://src/presentation_overlay_canvas.gd"

const SpriteAnimationCatalog = preload("res://src/content/sprite_animation_catalog.gd")
const SpriteAnimationValidator = preload("res://src/content/sprite_animation_validator.gd")
const AnimationEncounterModel = preload("res://src/game/encounter_model.gd")
const AnimationObjectCatalog = preload("res://src/content/object_catalog.gd")

const ANIMATION_SPEED_EPSILON := 6.0
const DIRECTION_DOWN := 0
const DIRECTION_LEFT := 1
const DIRECTION_RIGHT := 2
const DIRECTION_UP := 3

var animation_definitions: Dictionary = {}
var animation_bindings: Array[Dictionary] = []
var animation_campaign_key := ""
var animation_clock := 0.0
var actor_previous_positions: Dictionary = {}
var actor_speeds: Dictionary = {}
var entity_previous_positions: Dictionary = {}
var state_started_at: Dictionary = {}
var previous_states: Dictionary = {}
var atlas_cache: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	super._ready()


func initialize_from_runtime() -> void:
	super.initialize_from_runtime()
	load_animation_catalog()
	capture_animation_positions()


func _process(delta: float) -> void:
	animation_clock += maxf(0.0, delta)
	update_animation_motion(delta)
	var runtime := runtime_root()
	if runtime != null:
		var campaign_value: Variant = runtime.get("campaign")
		var campaign: Dictionary = campaign_value as Dictionary if typeof(campaign_value) == TYPE_DICTIONARY else {}
		var next_key := "%s|%s" % [str(runtime.get("campaign_path")), str(campaign.get("id", "fallback"))]
		if next_key != animation_campaign_key:
			load_animation_catalog()
			capture_animation_positions()
	super._process(delta)


func load_animation_catalog() -> void:
	var runtime := runtime_root()
	if runtime == null:
		return
	var campaign_value: Variant = runtime.get("campaign")
	var campaign: Dictionary = campaign_value as Dictionary if typeof(campaign_value) == TYPE_DICTIONARY else {}
	var campaign_path := str(runtime.get("campaign_path"))
	animation_campaign_key = "%s|%s" % [campaign_path, str(campaign.get("id", "fallback"))]
	var result: Dictionary = SpriteAnimationCatalog.load_catalogs(campaign_path, campaign)
	animation_definitions = result.get("definitions", {})
	animation_bindings.clear()
	var bindings_value: Variant = result.get("bindings", [])
	if typeof(bindings_value) == TYPE_ARRAY:
		for binding_value in bindings_value as Array:
			if typeof(binding_value) == TYPE_DICTIONARY:
				animation_bindings.append((binding_value as Dictionary).duplicate(true))
	if not campaign_path.is_empty():
		var validation: Dictionary = SpriteAnimationValidator.validate_animation_only(campaign_path)
		if not bool(validation.get("ok", false)):
			var fallback: Dictionary = SpriteAnimationCatalog.fallback_result([], [])
			animation_definitions = fallback.get("definitions", {})
			animation_bindings.clear()
			for binding_value in fallback.get("bindings", []):
				if typeof(binding_value) == TYPE_DICTIONARY:
					animation_bindings.append((binding_value as Dictionary).duplicate(true))
	atlas_cache.clear()


func capture_animation_positions() -> void:
	actor_previous_positions = {
		"player": runtime_vector("player"),
		"companion": runtime_vector("companion")
	}
	actor_speeds = {"player": 0.0, "companion": 0.0}
	entity_previous_positions.clear()
	for entity_value in runtime_array("runtime_entities"):
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value as Dictionary
		var key := entity_animation_key(entity)
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		entity_previous_positions[key] = position_value if position_value is Vector2 else Vector2.ZERO


func update_animation_motion(delta: float) -> void:
	var safe_delta := maxf(delta, 0.001)
	for role in ["player", "companion"]:
		var current := runtime_vector(role)
		var previous_value: Variant = actor_previous_positions.get(role, current)
		var previous: Vector2 = previous_value if previous_value is Vector2 else current
		var speed := current.distance_to(previous) / safe_delta
		actor_speeds[role] = lerpf(float(actor_speeds.get(role, 0.0)), speed, clampf(delta * 18.0, 0.0, 1.0))
		actor_previous_positions[role] = current
	var next_entities: Dictionary = {}
	for entity_value in runtime_array("runtime_entities"):
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value as Dictionary
		var key := entity_animation_key(entity)
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var current: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var previous_value: Variant = entity_previous_positions.get(key, current)
		var previous: Vector2 = previous_value if previous_value is Vector2 else current
		next_entities[key] = current
		actor_speeds[key] = lerpf(float(actor_speeds.get(key, 0.0)), current.distance_to(previous) / safe_delta, clampf(delta * 18.0, 0.0, 1.0))
	entity_previous_positions = next_entities


func draw_player_sprite(position: Vector2) -> void:
	var profile := resolved_profile(PackedStringArray(["player", "kind:actor", "*"]))
	var state := player_animation_state()
	var direction := runtime_direction_index()
	var frame := resolved_frame(profile, state, "player")
	if draw_profile_atlas(profile, state, direction, frame, position):
		draw_player_weapon_finish(position, state, frame)
		return
	draw_procedural_hero(profile, position, state, direction, frame)


func draw_companion_sprite(position: Vector2) -> void:
	var profile := resolved_profile(PackedStringArray(["companion", "kind:companion", "shape:beast", "*"]))
	var state := companion_animation_state()
	var direction := companion_direction_index()
	var frame := resolved_frame(profile, state, "companion")
	if draw_profile_atlas(profile, state, direction, frame, position):
		return
	draw_procedural_dog(profile, position, state, direction, frame)


func draw_entity_sprite(entity: Dictionary) -> void:
	var definition_value: Variant = entity.get("definition", {})
	var definition: Dictionary = definition_value as Dictionary if typeof(definition_value) == TYPE_DICTIONARY else {}
	var appearance_value: Variant = definition.get("appearance", {})
	var appearance: Dictionary = appearance_value as Dictionary if typeof(appearance_value) == TYPE_DICTIONARY else {}
	var placement_id := str(entity.get("placement_id", ""))
	var object_id := str(definition.get("id", entity.get("object_id", "")))
	var shape := str(appearance.get("shape", "marker"))
	var kind := str(definition.get("kind", "prop"))
	var targets := PackedStringArray()
	if not placement_id.is_empty():
		targets.append("placement:%s" % placement_id)
	if not object_id.is_empty():
		targets.append("object:%s" % object_id)
	targets.append("shape:%s" % shape)
	targets.append("kind:%s" % kind)
	targets.append("*")
	var profile := resolved_profile(targets)
	var state := entity_animation_state(entity)
	var direction := entity_direction_index(entity)
	var key := entity_animation_key(entity)
	var frame := resolved_frame(profile, state, key)
	var position_value: Variant = entity.get("position", Vector2.ZERO)
	var world_position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
	var screen_position := world_to_screen(world_position)
	if draw_profile_atlas(profile, state, direction, frame, screen_position):
		return
	draw_procedural_entity(profile, entity, definition, appearance, screen_position, state, direction, frame)


func resolved_profile(targets: PackedStringArray) -> Dictionary:
	return SpriteAnimationCatalog.resolved_profile(animation_definitions, animation_bindings, targets)


func player_animation_state() -> String:
	if runtime_number("player_hurt_lock", 0.0) > 0.0:
		return remember_state("player", "hurt")
	if runtime_number("player_attack_timer", 0.0) > 0.0:
		return remember_state("player", "attack")
	if float(actor_speeds.get("player", 0.0)) > ANIMATION_SPEED_EPSILON:
		return remember_state("player", "walk")
	return remember_state("player", "idle")


func companion_animation_state() -> String:
	if runtime_number("companion_hurt_lock", 0.0) > 0.0:
		return remember_state("companion", "hurt")
	if runtime_number("companion_attack_timer", 0.0) > 0.0:
		return remember_state("companion", "attack")
	if float(actor_speeds.get("companion", 0.0)) > ANIMATION_SPEED_EPSILON:
		return remember_state("companion", "walk")
	return remember_state("companion", "idle")


func entity_animation_state(entity: Dictionary) -> String:
	var key := entity_animation_key(entity)
	if float(entity.get("hit_flash", 0.0)) > 0.0 or str(entity.get("mode", "")) == "staggered":
		return remember_state(key, "hurt")
	var mode := str(entity.get("mode", entity.get("state", "idle")))
	if mode == "windup" or mode == "attack":
		return remember_state(key, "attack")
	if ["chase", "return", "patrol", "pursue"].has(mode) or float(actor_speeds.get(key, 0.0)) > ANIMATION_SPEED_EPSILON:
		return remember_state(key, "walk")
	return remember_state(key, "idle")


func remember_state(key: String, state: String) -> String:
	if str(previous_states.get(key, "")) != state:
		previous_states[key] = state
		state_started_at[key] = animation_clock
	return state


func resolved_frame(profile: Dictionary, state: String, key: String) -> int:
	var record := SpriteAnimationCatalog.animation(profile, state)
	var frames := maxi(1, int(record.get("frames", 1)))
	var fps := clampf(float(record.get("fps", 1.0)), 1.0, 30.0)
	var elapsed := maxf(0.0, animation_clock - float(state_started_at.get(key, animation_clock)))
	var raw := int(floor(elapsed * fps))
	return posmod(raw, frames) if bool(record.get("loop", true)) else mini(raw, frames - 1)


func runtime_direction_index() -> int:
	var runtime := runtime_root()
	if runtime == null:
		return DIRECTION_DOWN
	var facing_value: Variant = runtime.get("facing")
	var facing: Vector2 = facing_value if facing_value is Vector2 else Vector2.DOWN
	return direction_index(facing)


func companion_direction_index() -> int:
	var current := runtime_vector("companion")
	var previous_value: Variant = actor_previous_positions.get("companion", current)
	var previous: Vector2 = previous_value if previous_value is Vector2 else current
	var direction := current - previous
	if direction.length_squared() < 0.01:
		direction = runtime_vector("player") - current
	return direction_index(direction)


func entity_direction_index(entity: Dictionary) -> int:
	return direction_index(AnimationEncounterModel.facing_vector(str(entity.get("facing", "down"))))


func direction_index(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y):
		return DIRECTION_RIGHT if direction.x >= 0.0 else DIRECTION_LEFT
	return DIRECTION_DOWN if direction.y >= 0.0 else DIRECTION_UP


func draw_profile_atlas(
	profile: Dictionary,
	state: String,
	direction: int,
	frame: int,
	position: Vector2
) -> bool:
	var texture := atlas_texture(profile)
	if texture == null:
		return false
	var frame_size := SpriteAnimationCatalog.vector2i_value(profile, "frame_size", Vector2i(32, 32))
	var render_size := SpriteAnimationCatalog.vector2i_value(profile, "render_size", frame_size)
	var pivot := SpriteAnimationCatalog.vector2i_value(profile, "pivot", Vector2i(frame_size.x / 2, frame_size.y - 4))
	var record := SpriteAnimationCatalog.animation(profile, state)
	var directions := maxi(1, int(profile.get("directions", 4)))
	var row := int(record.get("row", 0)) + mini(direction, directions - 1)
	var source := Rect2(Vector2(frame * frame_size.x, row * frame_size.y), Vector2(frame_size))
	var scale := Vector2(render_size) / Vector2(frame_size)
	var destination := Rect2(position - Vector2(pivot) * scale, Vector2(render_size))
	draw_shadow(position + Vector2(0, 5), render_size.x * 0.34, maxf(3.0, render_size.y * 0.10))
	draw_texture_rect_region(texture, destination, source)
	return true


func atlas_texture(profile: Dictionary) -> Texture2D:
	var runtime := runtime_root()
	if runtime == null:
		return null
	var campaign_path := str(runtime.get("campaign_path"))
	var path := SpriteAnimationCatalog.atlas_path(campaign_path, profile)
	if path.is_empty():
		return null
	if atlas_cache.has(path):
		var cached: Variant = atlas_cache[path]
		return cached as Texture2D if cached is Texture2D else null
	var image := Image.new()
	if image.load(path) != OK:
		atlas_cache[path] = null
		return null
	var texture := ImageTexture.create_from_image(image)
	atlas_cache[path] = texture
	return texture


func draw_procedural_hero(profile: Dictionary, position: Vector2, state: String, direction: int, frame: int) -> void:
	var stride := stride_value(frame, state)
	var bob := -1.0 if state == "walk" and frame % 2 == 1 else 0.0
	var recoil := -3.0 if state == "hurt" else 0.0
	var center := position + Vector2(recoil * horizontal_sign(direction), bob)
	var ink := profile_color("ink", "13161a")
	var coat_dark := profile_color("shadow", "263033")
	var coat := Color("334b68")
	var skin := Color("d8a77c")
	var light := profile_color("light", "d7c99b")
	var brass := profile_color("accent", "d49a45")
	draw_shadow(center + Vector2(0, 7), 11.5, 4.0)
	var left_leg := stride if direction != DIRECTION_UP else -stride
	var right_leg := -stride if direction != DIRECTION_UP else stride
	draw_rect(Rect2(center + Vector2(-7 + left_leg, 4), Vector2(5, 11)), ink)
	draw_rect(Rect2(center + Vector2(2 + right_leg, 4), Vector2(5, 11)), ink)
	draw_rect(Rect2(center + Vector2(-8 + left_leg, 12), Vector2(6, 3)), coat_dark)
	draw_rect(Rect2(center + Vector2(2 + right_leg, 12), Vector2(6, 3)), coat_dark)
	var torso_shift := attack_body_shift(state, frame, direction)
	var torso := center + torso_shift
	draw_rect(Rect2(torso + Vector2(-9, -10), Vector2(18, 18)), ink)
	draw_rect(Rect2(torso + Vector2(-7, -8), Vector2(14, 14)), coat)
	var arm_swing := stride if state == "walk" else 0.0
	draw_rect(Rect2(torso + Vector2(-10, -7 + arm_swing), Vector2(3, 9)), ink)
	draw_rect(Rect2(torso + Vector2(7, -7 - arm_swing), Vector2(3, 9)), ink)
	draw_rect(Rect2(torso + Vector2(-2, -5), Vector2(4, 3)), brass)
	draw_rect(Rect2(torso + Vector2(-6, -20), Vector2(12, 11)), skin)
	draw_rect(Rect2(torso + Vector2(-6, -22), Vector2(12, 5)), ink)
	if direction == DIRECTION_UP:
		draw_rect(Rect2(torso + Vector2(-7, -19), Vector2(14, 7)), ink)
	elif direction == DIRECTION_LEFT or direction == DIRECTION_RIGHT:
		var side := horizontal_sign(direction)
		draw_rect(Rect2(torso + Vector2(4 * side, -16), Vector2(2, 2)), light)
		draw_rect(Rect2(torso + Vector2(-7 * side, -18), Vector2(3, 7)), ink)
	else:
		draw_rect(Rect2(torso + Vector2(-3, -16), Vector2(2, 2)), light)
		draw_rect(Rect2(torso + Vector2(2, -16), Vector2(2, 2)), light)
	draw_player_weapon(torso, state, direction, frame, ink, light, brass)


func draw_player_weapon_finish(position: Vector2, state: String, frame: int) -> void:
	if state != "attack" and attack_glint <= 0.0:
		return
	var direction := direction_vector(runtime_direction_index())
	var endpoint := position + direction * (15.0 + frame * 2.0)
	draw_arc(endpoint, 4.0 + attack_glint * 5.0, 0.0, TAU, 10, Color(profile_color("accent", "d49a45"), 0.75), 1.0)


func draw_player_weapon(center: Vector2, state: String, direction: int, frame: int, ink: Color, light: Color, brass: Color) -> void:
	var direction_vector_value := direction_vector(direction)
	var anticipation := 0.0
	if state == "attack":
		anticipation = float(frame - 1) * 3.0
	var start := center + Vector2(0, -2) - direction_vector_value * minf(4.0, maxf(0.0, -anticipation))
	var finish := start + direction_vector_value * (18.0 + maxf(0.0, anticipation))
	draw_line(start, finish, ink, 4.0)
	draw_line(start, finish, light, 1.0)
	draw_rect(Rect2(start - Vector2(2, 2), Vector2(4, 4)), brass)
	if state == "attack" and frame >= 2:
		var perpendicular := Vector2(-direction_vector_value.y, direction_vector_value.x)
		draw_line(finish - perpendicular * 7.0, finish + perpendicular * 7.0, Color(brass, 0.7), 2.0)


func draw_procedural_dog(profile: Dictionary, position: Vector2, state: String, direction: int, frame: int) -> void:
	var stride := stride_value(frame, state)
	var bob := -1.0 if state == "walk" and frame % 2 == 1 else 0.0
	var recoil := -2.0 if state == "hurt" else 0.0
	var center := position + Vector2(recoil * horizontal_sign(direction), bob)
	var ink := profile_color("ink", "13161a")
	var dark := Color("35251f")
	var fur := Color("6a4935")
	var light := Color("b78a62")
	var accent := profile_color("accent", "d49a45")
	draw_shadow(center + Vector2(0, 6), 12.0, 4.0)
	var side_facing := direction == DIRECTION_LEFT or direction == DIRECTION_RIGHT
	if side_facing:
		var side := horizontal_sign(direction)
		draw_rect(Rect2(center + Vector2(-10, -6), Vector2(19, 11)), dark)
		draw_rect(Rect2(center + Vector2(-8, -8), Vector2(16, 11)), fur)
		var head_x := 7.0 * side
		draw_rect(Rect2(center + Vector2(head_x - 5, -12), Vector2(10, 9)), fur)
		draw_rect(Rect2(center + Vector2(head_x + 3 * side - 2, -9), Vector2(5, 4)), light)
		draw_rect(Rect2(center + Vector2(head_x - 4, -15), Vector2(3, 5)), ink)
		draw_rect(Rect2(center + Vector2(head_x + 2, -15), Vector2(3, 5)), ink)
		draw_rect(Rect2(center + Vector2(head_x + 3 * side - 1, -11), Vector2(2, 2)), accent)
		var tail_angle := -8.0 + float(posmod(frame, 3)) * 4.0
		draw_line(center + Vector2(-9 * side, -4), center + Vector2(-17 * side, tail_angle), dark, 3.0)
	else:
		draw_rect(Rect2(center + Vector2(-8, -7), Vector2(16, 14)), dark)
		draw_rect(Rect2(center + Vector2(-6, -9), Vector2(12, 14)), fur)
		var head_y := 5.0 if direction == DIRECTION_DOWN else -8.0
		draw_rect(Rect2(center + Vector2(-6, head_y - 8), Vector2(12, 9)), fur)
		draw_rect(Rect2(center + Vector2(-5, head_y - 11), Vector2(3, 5)), ink)
		draw_rect(Rect2(center + Vector2(2, head_y - 11), Vector2(3, 5)), ink)
		if direction == DIRECTION_DOWN:
			draw_rect(Rect2(center + Vector2(-1, head_y - 3), Vector2(3, 3)), accent)
	var leg_a := stride
	var leg_b := -stride
	draw_rect(Rect2(center + Vector2(-7 + leg_a, 4), Vector2(3, 7)), ink)
	draw_rect(Rect2(center + Vector2(3 + leg_b, 4), Vector2(3, 7)), ink)
	if state == "attack":
		draw_arc(center + direction_vector(direction) * 12.0, 7.0 + frame, 0.0, TAU, 10, Color(accent, 0.55), 2.0)


func draw_procedural_entity(
	profile: Dictionary,
	entity: Dictionary,
	definition: Dictionary,
	appearance: Dictionary,
	position: Vector2,
	state: String,
	direction: int,
	frame: int
) -> void:
	var shape := str(appearance.get("shape", "marker"))
	var style := str(profile.get("fallback_style", "prop"))
	var base_color := AnimationObjectCatalog.appearance_color(definition, "color", "66717a")
	var accent := AnimationObjectCatalog.appearance_color(definition, "accent", "d4c68f")
	var ink := profile_color("ink", "13161a")
	if float(entity.get("hit_flash", 0.0)) > 0.0:
		base_color = Color.WHITE
		accent = profile_color("light", "d7c99b")
	if style == "humanoid" or shape == "person":
		draw_procedural_humanoid(position, state, direction, frame, base_color, accent, ink)
	elif style == "beast" or shape == "beast":
		draw_procedural_beast(position, state, direction, frame, base_color, accent, ink)
	elif style == "orb" or shape == "orb":
		var pulse := 1.0 + sin(animation_clock * 5.0 + frame) * 0.14
		draw_shadow(position + Vector2(0, 7), 9.0, 3.0)
		draw_circle(position, 10.0 * pulse, Color(ink, 0.82))
		draw_rect(Rect2(position - Vector2(5, 5), Vector2(10, 10)), base_color)
		draw_rect(Rect2(position - Vector2(2, 2), Vector2(4, 4)), accent)
	else:
		draw_procedural_prop(position, shape, frame, base_color, accent, ink)


func draw_procedural_humanoid(position: Vector2, state: String, direction: int, frame: int, base_color: Color, accent: Color, ink: Color) -> void:
	var stride := stride_value(frame, state)
	var recoil := -2.0 * horizontal_sign(direction) if state == "hurt" else 0.0
	var center := position + Vector2(recoil, -1.0 if state == "walk" and frame % 2 == 1 else 0.0)
	draw_shadow(center + Vector2(0, 8), 9.0, 3.5)
	draw_rect(Rect2(center + Vector2(-7 + stride, 5), Vector2(5, 10)), ink)
	draw_rect(Rect2(center + Vector2(2 - stride, 5), Vector2(5, 10)), ink)
	draw_rect(Rect2(center + Vector2(-8, -8), Vector2(16, 16)), ink)
	draw_rect(Rect2(center + Vector2(-6, -7), Vector2(12, 13)), base_color)
	draw_rect(Rect2(center + Vector2(-5, -17), Vector2(10, 10)), accent)
	draw_rect(Rect2(center + Vector2(-6, -19), Vector2(12, 4)), ink)
	if state == "attack":
		var direction_value := direction_vector(direction)
		draw_line(center, center + direction_value * (15.0 + frame * 2.0), ink, 3.0)


func draw_procedural_beast(position: Vector2, state: String, direction: int, frame: int, base_color: Color, accent: Color, ink: Color) -> void:
	var stride := stride_value(frame, state)
	var direction_value := direction_vector(direction)
	var lean := direction_value * (3.0 if state == "attack" else 0.0)
	var center := position + lean + Vector2(0, -1.0 if state == "walk" and frame % 2 == 1 else 0.0)
	draw_shadow(center + Vector2(0, 7), 11.0, 3.5)
	draw_rect(Rect2(center + Vector2(-11, -6), Vector2(19, 12)), ink)
	draw_rect(Rect2(center + Vector2(-9, -8), Vector2(17, 11)), base_color)
	var head := center + direction_value * 9.0 + Vector2(0, -5)
	draw_rect(Rect2(head + Vector2(-5, -5), Vector2(10, 9)), accent)
	draw_rect(Rect2(head + Vector2(-4, -8), Vector2(3, 5)), ink)
	draw_rect(Rect2(head + Vector2(2, -8), Vector2(3, 5)), ink)
	draw_rect(Rect2(center + Vector2(-8 + stride, 3), Vector2(3, 7)), ink)
	draw_rect(Rect2(center + Vector2(4 - stride, 3), Vector2(3, 7)), ink)
	if state == "attack":
		draw_arc(head + direction_value * 4.0, 6.0 + frame, 0.0, TAU, 10, Color(profile_color("danger", "b94d45"), 0.6), 2.0)


func draw_procedural_prop(position: Vector2, shape: String, frame: int, base_color: Color, accent: Color, ink: Color) -> void:
	draw_shadow(position + Vector2(0, 7), 10.0, 3.5)
	match shape:
		"crate":
			draw_rect(Rect2(position + Vector2(-12, -9), Vector2(24, 18)), ink)
			draw_rect(Rect2(position + Vector2(-10, -8), Vector2(20, 15)), base_color)
			draw_rect(Rect2(position + Vector2(-8, -6), Vector2(16, 11)), accent.darkened(0.25), false, 2.0)
			draw_line(position + Vector2(-8, -6), position + Vector2(8, 5), ink, 2.0)
		"pillar":
			draw_rect(Rect2(position + Vector2(-8, -24), Vector2(16, 32)), ink)
			draw_rect(Rect2(position + Vector2(-6, -22), Vector2(12, 28)), base_color)
			draw_rect(Rect2(position + Vector2(-9, -25), Vector2(18, 5)), accent)
		_:
			var pulse := 1.0 + float(frame % 2) * 0.08
			draw_circle(position, 9.0 * pulse, ink)
			draw_rect(Rect2(position - Vector2(5, 5), Vector2(10, 10)), base_color)


func stride_value(frame: int, state: String) -> float:
	if state != "walk":
		return 0.0
	var cycle := [-2.0, -1.0, 1.0, 2.0, 1.0, -1.0]
	return cycle[posmod(frame, cycle.size())]


func attack_body_shift(state: String, frame: int, direction: int) -> Vector2:
	if state != "attack":
		return Vector2.ZERO
	var progression := [-2.0, -4.0, 2.0, 4.0, 1.0]
	return direction_vector(direction) * progression[posmod(frame, progression.size())]


func direction_vector(direction: int) -> Vector2:
	match direction:
		DIRECTION_LEFT: return Vector2.LEFT
		DIRECTION_RIGHT: return Vector2.RIGHT
		DIRECTION_UP: return Vector2.UP
		_: return Vector2.DOWN


func horizontal_sign(direction: int) -> float:
	if direction == DIRECTION_LEFT:
		return -1.0
	if direction == DIRECTION_RIGHT:
		return 1.0
	return 0.0


func entity_animation_key(entity: Dictionary) -> String:
	var placement_id := str(entity.get("placement_id", ""))
	if not placement_id.is_empty():
		return "entity:%s" % placement_id
	return "entity:%s" % str(entity.get("state_key", entity.hash()))


func animation_profile_count() -> int:
	return animation_definitions.size()


func animation_binding_count() -> int:
	return animation_bindings.size()
