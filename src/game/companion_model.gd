extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")

const ALLOWED_COMMANDS := ["follow", "stay", "seek", "guard"]
const ALLOWED_CUE_KINDS := ["clue", "resource", "trail", "warning"]
const DEFAULT_COMMANDS := ["follow", "stay", "seek", "guard"]


static func profile(campaign: Dictionary) -> Dictionary:
	var actors: Dictionary = campaign.get("actors", {})
	var companion: Variant = actors.get("companion", {})
	return companion if typeof(companion) == TYPE_DICTIONARY else {}


static func allowed_commands(companion_profile: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = companion_profile.get("commands", DEFAULT_COMMANDS)
	if typeof(value) == TYPE_ARRAY:
		for command_value in value:
			var command := str(command_value)
			if ALLOWED_COMMANDS.has(command) and not output.has(command):
				output.append(command)
	if output.is_empty():
		for command in DEFAULT_COMMANDS:
			output.append(command)
	return output


static func command_label(command: String) -> String:
	match command:
		"stay":
			return "STAY"
		"seek":
			return "SEEK"
		"guard":
			return "GUARD"
		_:
			return "FOLLOW"


static func command_description(command: String, companion_name: String) -> String:
	var name := companion_name.capitalize()
	match command:
		"stay":
			return "%s will hold this position." % name
		"seek":
			return "%s searches for an unfinished trail." % name
		"guard":
			return "%s stays close and watches for danger." % name
		_:
			return "%s returns to your trail." % name


static func follow_distance(companion_profile: Dictionary) -> float:
	return maxf(12.0, float(companion_profile.get("follow_distance", 34.0)))


static func guard_distance(companion_profile: Dictionary) -> float:
	return maxf(10.0, float(companion_profile.get("guard_distance", 24.0)))


static func recovery_distance(companion_profile: Dictionary) -> float:
	return maxf(64.0, float(companion_profile.get("recovery_distance", 300.0)))


static func seek_radius(companion_profile: Dictionary) -> float:
	return maxf(32.0, float(companion_profile.get("seek_radius", 280.0)))


static func seek_speed(companion_profile: Dictionary) -> float:
	return maxf(24.0, float(companion_profile.get("seek_speed", 145.0)))


static func guard_attack_range(companion_profile: Dictionary) -> float:
	return maxf(24.0, float(companion_profile.get("guard_attack_range", 52.0)))


static func all_cues(map_data: Dictionary) -> Array:
	var value: Variant = map_data.get("companion_cues", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func cue_is_available(cue: Dictionary, era_id: String) -> bool:
	var value: Variant = cue.get("available_eras", [])
	if typeof(value) != TYPE_ARRAY:
		return true
	var available: Array = value
	return available.is_empty() or available.has(era_id)


static func cue_state_key(map_id: String, cue: Dictionary) -> String:
	var authored := str(cue.get("state_key", "")).strip_edges()
	if not authored.is_empty():
		return authored
	return "%s:companion:%s" % [map_id, cue.get("id", "cue")]


static func cue_position(cue: Dictionary) -> Vector2:
	return Repository.data_to_vector(cue.get("position"), Vector2.ZERO)


static func cue_radius(cue: Dictionary) -> float:
	return maxf(8.0, float(cue.get("reveal_radius", 22.0)))


static func unresolved_cues(
	map_data: Dictionary,
	era_id: String,
	session_state: Dictionary
) -> Array:
	var output: Array = []
	var map_id := str(map_data.get("id", "map"))
	for value in all_cues(map_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var cue: Dictionary = value
		if not cue_is_available(cue, era_id):
			continue
		if session_state.has(cue_state_key(map_id, cue)):
			continue
		output.append(cue)
	return output


static func nearest_unresolved_cue(
	map_data: Dictionary,
	era_id: String,
	session_state: Dictionary,
	origin: Vector2,
	maximum_distance: float
) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := maximum_distance
	for value in unresolved_cues(map_data, era_id, session_state):
		var cue: Dictionary = value
		var distance := origin.distance_to(cue_position(cue))
		if distance <= best_distance:
			best = cue
			best_distance = distance
	return best


static func cue_message(cue: Dictionary, companion_name: String) -> String:
	var value: Variant = cue.get("message", "")
	var text := str(value).strip_edges()
	if text.is_empty():
		text = "%s finds a trail that should not exist." % companion_name.capitalize()
	return text


static func cue_reward(cue: Dictionary) -> int:
	return maxi(0, int(cue.get("reward", 0)))


static func visible_before_discovery(cue: Dictionary) -> bool:
	return bool(cue.get("visible_before_discovery", false))


static func default_profile(name: String = "COMPANION") -> Dictionary:
	return {
		"name": name,
		"max_health": 24,
		"commands": DEFAULT_COMMANDS.duplicate(),
		"follow_distance": 34,
		"guard_distance": 24,
		"recovery_distance": 300,
		"seek_radius": 280,
		"seek_speed": 145,
		"guard_attack_range": 52
	}


static func default_cue(cue_id: String, position: Vector2) -> Dictionary:
	return {
		"id": cue_id,
		"kind": "clue",
		"position": Repository.vector_to_data(position),
		"reveal_radius": 22,
		"message": "The companion finds a trace hidden from ordinary sight.",
		"reward": 0,
		"visible_before_discovery": false,
		"available_eras": [],
		"state_key": ""
	}
