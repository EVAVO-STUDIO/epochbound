@tool
extends RefCounted

const MultiplayerCatalog = preload("res://src/content/multiplayer_catalog.gd")

const MODE_OFFLINE := "offline"
const MODE_HOST := "host"
const MODE_CLIENT := "client"
const ROLE_HOST := "host"
const ROLE_ALLY := "ally"
const ROLE_INVADER := "invader"
const ROLES := [ROLE_HOST, ROLE_ALLY, ROLE_INVADER]
const PLAYER_MAX_HEALTH := 32
const MOVE_SPEED := 105.0
const ATTACK_RANGE := 42.0
const ATTACK_DAMAGE := 4
const ATTACK_COOLDOWN := 0.34
const HURT_LOCK := 0.55
const ALLY_RESPAWN_SECONDS := 4.0
const INVADER_BANISH_SECONDS := 1.2
const PVP_GRACE_SECONDS := 2.0
const MAX_NAME_LENGTH := 18


static func sanitize_name(value: Variant, fallback: String = "WANDERER") -> String:
	var text: String = str(value).strip_edges()
	var output: String = ""
	for index in range(text.length()):
		var character: String = text.substr(index, 1)
		if character.to_ascii_buffer().size() == 1 and (
			character >= "A" and character <= "Z"
			or character >= "a" and character <= "z"
			or character >= "0" and character <= "9"
			or character in [" ", "_", "-"]
		):
			output += character
		if output.length() >= MAX_NAME_LENGTH:
			break
	output = output.strip_edges()
	return fallback if output.is_empty() else output


static func role_count(peers: Dictionary, role: String) -> int:
	var count: int = 0
	for value in peers.values():
		if typeof(value) == TYPE_DICTIONARY and str((value as Dictionary).get("role", "")) == role:
			count += 1
	return count


static func register_peer(
	peers: Dictionary,
	peer_id: int,
	requested_role: String,
	policy: Dictionary,
	spawn: Vector2,
	map_id: String,
	era_id: String,
	display_name: String = ""
) -> Dictionary:
	if peer_id <= 1:
		return {"ok": false, "reason": "invalid_peer_id", "peer": {}}
	if peers.has(peer_id):
		return {"ok": false, "reason": "duplicate_peer", "peer": {}}
	var role: String = requested_role
	if role not in [ROLE_ALLY, ROLE_INVADER]:
		role = ROLE_ALLY
	var capacity: int = int(policy.get("max_invaders", 0)) if role == ROLE_INVADER else int(policy.get("max_allies", 0))
	if role_count(peers, role) >= capacity:
		return {
			"ok": false,
			"reason": "invader_capacity" if role == ROLE_INVADER else "ally_capacity",
			"peer": {}
		}
	var peer: Dictionary = {
		"peer_id": peer_id,
		"role": role,
		"display_name": sanitize_name(display_name, "INVADER" if role == ROLE_INVADER else "ALLY"),
		"position": spawn,
		"facing": Vector2.DOWN,
		"health": PLAYER_MAX_HEALTH,
		"max_health": PLAYER_MAX_HEALTH,
		"map_id": map_id,
		"era_id": era_id,
		"attack_cooldown": 0.0,
		"hurt_lock": 0.0,
		"downed": false,
		"respawn_timer": 0.0,
		"banished": false,
		"banish_timer": 0.0,
		"pvp_grace": PVP_GRACE_SECONDS,
		"last_sequence": -1,
		"direction": Vector2.ZERO,
		"attack_requested": false,
		"active": true
	}
	peers[peer_id] = peer
	return {"ok": true, "reason": "", "peer": peer.duplicate(true)}


static func remove_peer(peers: Dictionary, peer_id: int) -> void:
	peers.erase(peer_id)


static func sanitize_input(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"direction": Vector2.ZERO, "attack": false}
	var source: Dictionary = value
	var direction: Vector2 = Vector2.ZERO
	var direction_value: Variant = source.get("direction", Vector2.ZERO)
	if direction_value is Vector2:
		direction = direction_value
	elif typeof(direction_value) == TYPE_DICTIONARY:
		var data: Dictionary = direction_value
		if typeof(data.get("x")) in [TYPE_INT, TYPE_FLOAT] and typeof(data.get("y")) in [TYPE_INT, TYPE_FLOAT]:
			direction = Vector2(float(data.get("x")), float(data.get("y")))
	if not direction.is_finite():
		direction = Vector2.ZERO
	if direction.length() > 1.0:
		direction = direction.normalized()
	var attack: bool = bool(source.get("attack", false)) if typeof(source.get("attack", false)) == TYPE_BOOL else false
	return {"direction": direction, "attack": attack}


static func accept_input(
	peers: Dictionary,
	peer_id: int,
	sequence: int,
	payload: Variant
) -> Dictionary:
	if not peers.has(peer_id) or typeof(peers.get(peer_id)) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "unknown_peer"}
	var peer: Dictionary = peers.get(peer_id)
	if sequence <= int(peer.get("last_sequence", -1)):
		return {"ok": false, "reason": "stale_sequence"}
	var input: Dictionary = sanitize_input(payload)
	peer["last_sequence"] = sequence
	peer["direction"] = input.get("direction", Vector2.ZERO)
	peer["attack_requested"] = bool(input.get("attack", false))
	peers[peer_id] = peer
	return {"ok": true, "reason": ""}


static func tick_peer(peer: Dictionary, delta: float) -> Dictionary:
	var output: Dictionary = peer.duplicate(true)
	output["attack_cooldown"] = maxf(0.0, float(output.get("attack_cooldown", 0.0)) - delta)
	output["hurt_lock"] = maxf(0.0, float(output.get("hurt_lock", 0.0)) - delta)
	output["pvp_grace"] = maxf(0.0, float(output.get("pvp_grace", 0.0)) - delta)
	if bool(output.get("downed", false)):
		output["respawn_timer"] = maxf(0.0, float(output.get("respawn_timer", 0.0)) - delta)
	if bool(output.get("banished", false)):
		output["banish_timer"] = maxf(0.0, float(output.get("banish_timer", 0.0)) - delta)
	return output


static func proposed_position(peer: Dictionary, delta: float) -> Vector2:
	var position_value: Variant = peer.get("position", Vector2.ZERO)
	var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
	var direction_value: Variant = peer.get("direction", Vector2.ZERO)
	var direction: Vector2 = direction_value if direction_value is Vector2 else Vector2.ZERO
	return position + direction * MOVE_SPEED * maxf(0.0, delta)


static func update_facing(peer: Dictionary) -> Dictionary:
	var output: Dictionary = peer.duplicate(true)
	var direction_value: Variant = output.get("direction", Vector2.ZERO)
	var direction: Vector2 = direction_value if direction_value is Vector2 else Vector2.ZERO
	if direction.length_squared() > 0.001:
		output["facing"] = direction.normalized()
	return output


static func shared_pvp_area(
	attacker: Dictionary,
	target: Dictionary,
	definitions: Dictionary
) -> Dictionary:
	if str(attacker.get("map_id", "")) != str(target.get("map_id", "")):
		return {}
	if str(attacker.get("era_id", "")) != str(target.get("era_id", "")):
		return {}
	var map_id: String = str(attacker.get("map_id", ""))
	var era_id: String = str(attacker.get("era_id", ""))
	var attacker_position_value: Variant = attacker.get("position", Vector2.ZERO)
	var target_position_value: Variant = target.get("position", Vector2.ZERO)
	var attacker_position: Vector2 = attacker_position_value if attacker_position_value is Vector2 else Vector2.ZERO
	var target_position: Vector2 = target_position_value if target_position_value is Vector2 else Vector2.ZERO
	var attacker_area: Dictionary = MultiplayerCatalog.active_area(definitions, map_id, era_id, attacker_position)
	var target_area: Dictionary = MultiplayerCatalog.active_area(definitions, map_id, era_id, target_position)
	if (
		attacker_area.is_empty()
		or target_area.is_empty()
		or str(attacker_area.get("id", "")) != str(target_area.get("id", ""))
		or MultiplayerCatalog.area_kind(attacker_area) != MultiplayerCatalog.AREA_PVP
	):
		return {}
	return attacker_area


static func can_damage_actor(
	attacker: Dictionary,
	target: Dictionary,
	definitions: Dictionary,
	policy: Dictionary
) -> bool:
	if not bool(attacker.get("active", true)) or not bool(target.get("active", true)):
		return false
	if bool(attacker.get("downed", false)) or bool(target.get("downed", false)):
		return false
	if bool(attacker.get("banished", false)) or bool(target.get("banished", false)):
		return false
	if float(attacker.get("pvp_grace", 0.0)) > 0.0 or float(target.get("pvp_grace", 0.0)) > 0.0:
		return false
	var attacker_role: String = str(attacker.get("role", ROLE_ALLY))
	var target_role: String = str(target.get("role", ROLE_ALLY))
	if attacker_role == target_role:
		return false
	var invader_involved: bool = attacker_role == ROLE_INVADER or target_role == ROLE_INVADER
	if not invader_involved:
		var area: Dictionary = shared_pvp_area(attacker, target, definitions)
		return not area.is_empty() and MultiplayerCatalog.friendly_fire_allowed(area, policy)
	return not shared_pvp_area(attacker, target, definitions).is_empty()


static func can_damage_enemy(role: String) -> bool:
	return role in [ROLE_HOST, ROLE_ALLY]


static func peer_attack_origin(peer: Dictionary) -> Vector2:
	var position_value: Variant = peer.get("position", Vector2.ZERO)
	return position_value if position_value is Vector2 else Vector2.ZERO


static func peer_facing(peer: Dictionary) -> Vector2:
	var facing_value: Variant = peer.get("facing", Vector2.DOWN)
	var facing: Vector2 = facing_value if facing_value is Vector2 else Vector2.DOWN
	return facing.normalized() if facing.length_squared() > 0.001 else Vector2.DOWN


static func in_attack_arc(attacker: Dictionary, target_position: Vector2) -> bool:
	var origin: Vector2 = peer_attack_origin(attacker)
	var offset: Vector2 = target_position - origin
	if offset.length() > ATTACK_RANGE or offset.length_squared() <= 0.001:
		return offset.length() <= ATTACK_RANGE
	return peer_facing(attacker).dot(offset.normalized()) >= 0.18


static func apply_actor_damage(target: Dictionary, amount: int) -> Dictionary:
	var output: Dictionary = target.duplicate(true)
	if float(output.get("hurt_lock", 0.0)) > 0.0:
		return output
	output["hurt_lock"] = HURT_LOCK
	output["health"] = maxi(0, int(output.get("health", PLAYER_MAX_HEALTH)) - maxi(1, amount))
	if int(output.get("health", 0)) > 0:
		return output
	if str(output.get("role", ROLE_ALLY)) == ROLE_INVADER:
		output["banished"] = true
		output["banish_timer"] = INVADER_BANISH_SECONDS
		output["active"] = false
	else:
		output["downed"] = true
		output["respawn_timer"] = ALLY_RESPAWN_SECONDS
		output["active"] = false
	return output


static func respawn_peer(
	peer: Dictionary,
	position: Vector2,
	map_id: String,
	era_id: String
) -> Dictionary:
	var output: Dictionary = peer.duplicate(true)
	output["position"] = position
	output["map_id"] = map_id
	output["era_id"] = era_id
	output["health"] = maxi(1, int(output.get("max_health", PLAYER_MAX_HEALTH)))
	output["downed"] = false
	output["respawn_timer"] = 0.0
	output["banished"] = false
	output["banish_timer"] = 0.0
	output["pvp_grace"] = PVP_GRACE_SECONDS
	output["active"] = true
	output["direction"] = Vector2.ZERO
	output["attack_requested"] = false
	return output


static func snapshot_peer(peer: Dictionary) -> Dictionary:
	var position_value: Variant = peer.get("position", Vector2.ZERO)
	var facing_value: Variant = peer.get("facing", Vector2.DOWN)
	var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
	var facing: Vector2 = facing_value if facing_value is Vector2 else Vector2.DOWN
	return {
		"peer_id": int(peer.get("peer_id", 0)),
		"role": str(peer.get("role", ROLE_ALLY)),
		"display_name": sanitize_name(peer.get("display_name", "WANDERER")),
		"position": {"x": snappedf(position.x, 0.01), "y": snappedf(position.y, 0.01)},
		"facing": {"x": snappedf(facing.x, 0.001), "y": snappedf(facing.y, 0.001)},
		"health": maxi(0, int(peer.get("health", PLAYER_MAX_HEALTH))),
		"max_health": maxi(1, int(peer.get("max_health", PLAYER_MAX_HEALTH))),
		"map_id": str(peer.get("map_id", "")),
		"era_id": str(peer.get("era_id", "")),
		"downed": bool(peer.get("downed", false)),
		"banished": bool(peer.get("banished", false)),
		"active": bool(peer.get("active", true))
	}


static func snapshot_peers(peers: Dictionary) -> Array:
	var ids: Array[int] = []
	for key in peers.keys():
		if typeof(key) == TYPE_INT:
			ids.append(int(key))
	ids.sort()
	var output: Array = []
	for peer_id in ids:
		var value: Variant = peers.get(peer_id, {})
		if typeof(value) == TYPE_DICTIONARY:
			output.append(snapshot_peer(value as Dictionary))
	return output


static func peer_from_snapshot(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = value
	var peer_id_value: Variant = source.get("peer_id", 0)
	if typeof(peer_id_value) != TYPE_INT or int(peer_id_value) <= 0:
		return {}
	var role: String = str(source.get("role", ""))
	if role not in ROLES:
		return {}
	var position: Vector2 = vector_from_data(source.get("position"), Vector2.ZERO)
	var facing: Vector2 = vector_from_data(source.get("facing"), Vector2.DOWN)
	return {
		"peer_id": int(peer_id_value),
		"role": role,
		"display_name": sanitize_name(source.get("display_name", "WANDERER")),
		"position": position,
		"facing": facing.normalized() if facing.length_squared() > 0.001 else Vector2.DOWN,
		"health": maxi(0, int(source.get("health", PLAYER_MAX_HEALTH))),
		"max_health": maxi(1, int(source.get("max_health", PLAYER_MAX_HEALTH))),
		"map_id": str(source.get("map_id", "")),
		"era_id": str(source.get("era_id", "")),
		"downed": bool(source.get("downed", false)),
		"banished": bool(source.get("banished", false)),
		"active": bool(source.get("active", true)),
		"attack_cooldown": 0.0,
		"hurt_lock": 0.0,
		"pvp_grace": 0.0,
		"last_sequence": -1,
		"direction": Vector2.ZERO,
		"attack_requested": false
	}


static func vector_from_data(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if typeof(value) != TYPE_DICTIONARY:
		return fallback
	var data: Dictionary = value
	if typeof(data.get("x")) not in [TYPE_INT, TYPE_FLOAT] or typeof(data.get("y")) not in [TYPE_INT, TYPE_FLOAT]:
		return fallback
	var output: Vector2 = Vector2(float(data.get("x")), float(data.get("y")))
	return output if output.is_finite() else fallback


static func contract_ok(policy: Dictionary) -> bool:
	return (
		str(policy.get("shared_progression", "")) == MultiplayerCatalog.PROGRESSION_HOST_ONLY
		and str(policy.get("pvp_rewards", "")) == MultiplayerCatalog.REWARD_SESSION_ONLY
		and int(policy.get("max_allies", -1)) >= 0
		and int(policy.get("max_allies", -1)) <= 2
		and int(policy.get("max_invaders", -1)) >= 0
		and int(policy.get("max_invaders", -1)) <= 1
		and ATTACK_RANGE > 0.0
		and ATTACK_COOLDOWN > 0.0
		and PVP_GRACE_SECONDS > 0.0
	)
