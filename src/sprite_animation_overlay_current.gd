extends "res://src/sprite_animation_overlay.gd"

const MOTION_DIRECTION_EPSILON := 0.01

var last_actor_directions: Dictionary = {
	"player": Vector2.DOWN,
	"companion": Vector2.RIGHT
}


func initialize_from_runtime() -> void:
	super.initialize_from_runtime()
	var runtime := runtime_root()
	if runtime == null:
		return
	var facing_value: Variant = runtime.get("facing")
	if facing_value is Vector2 and (facing_value as Vector2).length_squared() > MOTION_DIRECTION_EPSILON:
		last_actor_directions["player"] = (facing_value as Vector2).normalized()
	var player_to_companion := runtime_vector("player") - runtime_vector("companion")
	if player_to_companion.length_squared() > MOTION_DIRECTION_EPSILON:
		last_actor_directions["companion"] = player_to_companion.normalized()


func update_animation_motion(delta: float) -> void:
	for role in ["player", "companion"]:
		var current := runtime_vector(role)
		var previous_value: Variant = actor_previous_positions.get(role, current)
		var previous: Vector2 = previous_value if previous_value is Vector2 else current
		var movement := current - previous
		if movement.length_squared() > MOTION_DIRECTION_EPSILON:
			last_actor_directions[role] = movement.normalized()
	super.update_animation_motion(delta)


func companion_direction_index() -> int:
	var direction_value: Variant = last_actor_directions.get("companion", Vector2.RIGHT)
	var direction: Vector2 = direction_value if direction_value is Vector2 else Vector2.RIGHT
	if direction.length_squared() <= MOTION_DIRECTION_EPSILON:
		direction = Vector2.RIGHT
	return direction_index(direction)


func draw_player_sprite(position: Vector2) -> void:
	var direction := direction_vector(runtime_direction_index())
	draw_capability_light(position, direction)
	super.draw_player_sprite(position)


func draw_capability_light(position: Vector2, direction: Vector2) -> void:
	if not runtime_has_capability("illuminate_dark"):
		return
	var facing := direction.normalized()
	if facing.length_squared() <= MOTION_DIRECTION_EPSILON:
		facing = Vector2.DOWN
	var perpendicular := Vector2(-facing.y, facing.x)
	var origin := position + facing * 5.0 + Vector2(0, -6)
	var beam := PackedVector2Array([
		origin + perpendicular * 3.0,
		origin + facing * 82.0 + perpendicular * 23.0,
		origin + facing * 82.0 - perpendicular * 23.0,
		origin - perpendicular * 3.0
	])
	draw_colored_polygon(beam, Color(profile_color("light", "d7c99b"), 0.055))


func sprite_runtime_contract_ok() -> bool:
	return (
		texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and not animation_definitions.is_empty()
		and animation_bindings.size() > 0
	)
