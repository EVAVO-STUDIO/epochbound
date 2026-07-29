@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")

const SUPPORTED_SCHEMA := 1
const ALLOWED_PATTERN_TYPES := ["aimed_shot", "fan_shot", "radial_burst", "strike", "pause"]
const DEFAULT_PHASE_TRANSITION := 0.55
const DEFAULT_SAFE_PAUSE := 0.45


static func boss_record(definition_data: Dictionary) -> Dictionary:
	var value: Variant = definition_data.get("boss", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func is_boss(definition_data: Dictionary) -> bool:
	var data := boss_record(definition_data)
	return not data.is_empty() and bool(data.get("enabled", true))


static func phases(definition_data: Dictionary) -> Array:
	var value: Variant = boss_record(definition_data).get("phases", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func phase_is_available(phase: Dictionary, era_id: String) -> bool:
	var value: Variant = phase.get("available_eras", [])
	if typeof(value) != TYPE_ARRAY:
		return true
	var eras: Array = value
	return eras.is_empty() or eras.has(era_id)


static func phase_threshold(phase: Dictionary) -> float:
	return clampf(float(phase.get("health_ratio_at_or_below", 1.0)), 0.001, 1.0)


static func phase_for(
	definition_data: Dictionary,
	health: int,
	era_id: String
) -> Dictionary:
	var maximum := maxi(1, int(definition_data.get("max_health", 1)))
	var ratio := clampf(float(health) / float(maximum), 0.0, 1.0)
	var best: Dictionary = {}
	var best_threshold := INF
	for value in phases(definition_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var phase: Dictionary = value
		if not phase_is_available(phase, era_id):
			continue
		var threshold := phase_threshold(phase)
		if threshold + 0.0001 < ratio:
			continue
		if threshold < best_threshold:
			best = phase
			best_threshold = threshold
	if not best.is_empty():
		return best
	for value in phases(definition_data):
		if typeof(value) == TYPE_DICTIONARY and phase_is_available(value, era_id):
			return value
	return {}


static func phase_by_id(definition_data: Dictionary, phase_id: String) -> Dictionary:
	for value in phases(definition_data):
		if typeof(value) == TYPE_DICTIONARY:
			var phase: Dictionary = value
			if str(phase.get("id", "")) == phase_id:
				return phase
	return {}


static func phase_id(phase: Dictionary) -> String:
	return str(phase.get("id", ""))


static func phase_name(phase: Dictionary) -> String:
	var identifier := phase_id(phase)
	return str(phase.get("display_name", identifier.replace("_", " ").capitalize()))


static func phase_pattern(phase: Dictionary) -> Array:
	var value: Variant = phase.get("attack_pattern", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func phase_reinforcements(phase: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = phase.get("reinforcement_placements", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for item in value:
		var placement_id := str(item).strip_edges()
		if not placement_id.is_empty() and not output.has(placement_id):
			output.append(placement_id)
	return output


static func phase_transition_duration(phase: Dictionary) -> float:
	return clampf(float(phase.get("transition_duration", DEFAULT_PHASE_TRANSITION)), 0.0, 3.0)


static func apply_phase(
	definition_data: Dictionary,
	phase: Dictionary
) -> Dictionary:
	if phase.is_empty():
		return definition_data.duplicate(true)
	var output := definition_data.duplicate(true)
	output["move_speed"] = maxf(
		1.0,
		float(definition_data.get("move_speed", 48.0)) * maxf(0.05, float(phase.get("move_speed_multiplier", 1.0)))
	)
	output["attack_cooldown"] = maxf(
		0.05,
		float(definition_data.get("attack_cooldown", 1.0)) * maxf(0.05, float(phase.get("attack_cooldown_multiplier", 1.0)))
	)
	output["attack_damage"] = maxi(
		1,
		int(round(float(definition_data.get("attack_damage", 1)) * maxf(0.05, float(phase.get("attack_damage_multiplier", 1.0)))))
	)
	if phase.has("attack_windup"):
		output["attack_windup"] = maxf(0.05, float(phase.get("attack_windup", 0.5)))
	var ranged_value: Variant = output.get("ranged_attack", {})
	var ranged: Dictionary = ranged_value.duplicate(true) if typeof(ranged_value) == TYPE_DICTIONARY else {}
	var override_value: Variant = phase.get("ranged_attack_override", {})
	if typeof(override_value) == TYPE_DICTIONARY:
		for key in (override_value as Dictionary).keys():
			ranged[key] = (override_value as Dictionary).get(key)
	if not ranged.is_empty():
		output["ranged_attack"] = ranged
	return output


static func arena_zone_id(definition_data: Dictionary) -> String:
	return str(boss_record(definition_data).get("arena_zone_id", ""))


static func outcome_state_key(definition_data: Dictionary) -> String:
	return str(boss_record(definition_data).get("outcome_state_key", "")).strip_edges()


static func intro_message(definition_data: Dictionary) -> String:
	return str(boss_record(definition_data).get("intro_message", "A greater threat enters the field."))


static func defeat_message(definition_data: Dictionary) -> String:
	return str(boss_record(definition_data).get("defeat_message", "The arena falls silent."))


static func phase_message(phase: Dictionary) -> String:
	return str(phase.get("on_enter_message", phase_name(phase)))


static func locked_connections(definition_data: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = boss_record(definition_data).get("lock_connection_ids", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for item in value:
		var identifier := str(item).strip_edges()
		if not identifier.is_empty() and not output.has(identifier):
			output.append(identifier)
	return output


static func allow_era_shift(definition_data: Dictionary) -> bool:
	return bool(boss_record(definition_data).get("allow_era_shift", true))


static func arena_bounds(definition_data: Dictionary) -> Rect2:
	var value: Variant = boss_record(definition_data).get("arena_bounds", {})
	if typeof(value) != TYPE_DICTIONARY:
		return Rect2()
	var data: Dictionary = value
	var left := float(data.get("left", 0.0))
	var right := float(data.get("right", left))
	var top := float(data.get("top", 0.0))
	var bottom := float(data.get("bottom", top))
	return Rect2(Vector2(left, top), Vector2(maxf(0.0, right - left), maxf(0.0, bottom - top)))


static func defeat_effects(definition_data: Dictionary) -> Array:
	var value: Variant = boss_record(definition_data).get("defeat_effects", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func next_phase_threshold(
	definition_data: Dictionary,
	current_ratio: float,
	era_id: String
) -> float:
	var next := -1.0
	for value in phases(definition_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var phase: Dictionary = value
		if not phase_is_available(phase, era_id):
			continue
		var threshold := phase_threshold(phase)
		if threshold >= current_ratio - 0.0001:
			continue
		if threshold > next:
			next = threshold
	return next


static func pattern_step_type(step: Dictionary) -> String:
	return str(step.get("type", "aimed_shot"))


static func pattern_step_count(step: Dictionary) -> int:
	match pattern_step_type(step):
		"fan_shot":
			return clampi(int(step.get("count", 3)), 2, 12)
		"radial_burst":
			return clampi(int(step.get("count", 8)), 4, 16)
		_:
			return clampi(int(step.get("count", 1)), 1, 12)


static func pattern_step_spread(step: Dictionary) -> float:
	return clampf(float(step.get("spread_degrees", 28.0)), 0.0, 360.0)


static func pattern_step_pause(step: Dictionary) -> float:
	return clampf(float(step.get("duration", DEFAULT_SAFE_PAUSE)), 0.0, 5.0)


static func placement_record(map_data: Dictionary, placement_id: String) -> Dictionary:
	for value in map_data.get("object_placements", []):
		if typeof(value) == TYPE_DICTIONARY:
			var placement: Dictionary = value
			if str(placement.get("id", "")) == placement_id:
				return placement
	return {}


static func default_boss_profile() -> Dictionary:
	return {
		"enabled": true,
		"arena_zone_id": "boss_arena",
		"outcome_state_key": "map:boss:defeated",
		"intro_message": "The chamber seals as the guardian wakes.",
		"defeat_message": "The guardian's final mechanism falls still.",
		"lock_connection_ids": [],
		"allow_era_shift": true,
		"arena_bounds": {"left": 128, "right": 560, "top": 112, "bottom": 312},
		"defeat_effects": [],
		"phases": [
			{
				"id": "opening_measure",
				"display_name": "Opening Measure",
				"health_ratio_at_or_below": 1.0,
				"available_eras": [],
				"on_enter_message": "The guardian measures the arena.",
				"transition_duration": 0.55,
				"move_speed_multiplier": 0.85,
				"attack_cooldown_multiplier": 1.0,
				"attack_damage_multiplier": 1.0,
				"attack_windup": 0.55,
				"reinforcement_placements": [],
				"ranged_attack_override": {},
				"attack_pattern": [
					{"type": "aimed_shot", "count": 1, "spread_degrees": 0},
					{"type": "pause", "duration": 0.5},
					{"type": "fan_shot", "count": 3, "spread_degrees": 28}
				]
			},
			{
				"id": "final_measure",
				"display_name": "Final Measure",
				"health_ratio_at_or_below": 0.5,
				"available_eras": [],
				"on_enter_message": "The guardian abandons restraint.",
				"transition_duration": 0.65,
				"move_speed_multiplier": 1.15,
				"attack_cooldown_multiplier": 0.8,
				"attack_damage_multiplier": 1.15,
				"attack_windup": 0.48,
				"reinforcement_placements": [],
				"ranged_attack_override": {},
				"attack_pattern": [
					{"type": "fan_shot", "count": 5, "spread_degrees": 52},
					{"type": "pause", "duration": 0.55},
					{"type": "radial_burst", "count": 8, "spread_degrees": 360}
				]
			}
		]
	}
