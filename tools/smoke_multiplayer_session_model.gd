extends SceneTree

const MultiplayerCatalog = preload("res://src/content/multiplayer_catalog.gd")
const MultiplayerSessionModel = preload("res://src/game/multiplayer_session_model.gd")

var failures: Array[String] = []


func _initialize() -> void:
	run_test()


func run_test() -> void:
	var policy := MultiplayerCatalog.default_policy()
	policy["enabled"] = true
	policy["max_allies"] = 2
	policy["max_invaders"] = 1
	check(MultiplayerSessionModel.contract_ok(policy), "Default online policy must preserve host-only progression and session-only PvP rewards.")

	var peers: Dictionary = {
		1: host_peer(Vector2(360, 240), "clockwood_edge", "ashen")
	}
	var ally_one := MultiplayerSessionModel.register_peer(peers, 2, MultiplayerSessionModel.ROLE_ALLY, policy, Vector2(328, 272), "clockwood_edge", "ashen", "ALLY ONE")
	var ally_two := MultiplayerSessionModel.register_peer(peers, 3, MultiplayerSessionModel.ROLE_ALLY, policy, Vector2(344, 272), "clockwood_edge", "ashen", "ALLY TWO")
	check(bool(ally_one.get("ok", false)) and bool(ally_two.get("ok", false)), "Two co-op allies must fit the authored party cap.")
	var ally_overflow := MultiplayerSessionModel.register_peer(peers, 4, MultiplayerSessionModel.ROLE_ALLY, policy, Vector2(360, 272), "clockwood_edge", "ashen", "ALLY THREE")
	check(not bool(ally_overflow.get("ok", true)) and str(ally_overflow.get("reason", "")) == "ally_capacity", "A third ally must be rejected deterministically.")
	var invader := MultiplayerSessionModel.register_peer(peers, 5, MultiplayerSessionModel.ROLE_INVADER, policy, Vector2(488, 272), "clockwood_edge", "ashen", "RED HOUR")
	check(bool(invader.get("ok", false)), "One invader must fit the authored invasion cap.")
	var invader_overflow := MultiplayerSessionModel.register_peer(peers, 6, MultiplayerSessionModel.ROLE_INVADER, policy, Vector2(472, 272), "clockwood_edge", "ashen", "SECOND RED")
	check(not bool(invader_overflow.get("ok", true)) and str(invader_overflow.get("reason", "")) == "invader_capacity", "A second invader must be rejected deterministically.")

	check(bool(MultiplayerSessionModel.accept_input(peers, 2, 1, {"direction": {"x": 4.0, "y": 0.0}, "attack": true}).get("ok", false)), "Fresh ally input must be accepted.")
	var stale_input := MultiplayerSessionModel.accept_input(peers, 2, 1, {"direction": Vector2.LEFT})
	check(not bool(stale_input.get("ok", true)) and str(stale_input.get("reason", "")) == "stale_sequence", "Repeated input sequence numbers must be rejected as stale_sequence.")
	var ally: Dictionary = peers.get(2, {})
	check(is_equal_approx((ally.get("direction", Vector2.ZERO) as Vector2).length(), 1.0), "Remote directions must be clamped to unit length.")
	check(bool(ally.get("attack_requested", false)), "The host input model must retain only the requested attack intent.")

	var definitions := multiplayer_areas()
	var host: Dictionary = peers.get(1, {})
	var red: Dictionary = peers.get(5, {})
	host["pvp_grace"] = 0.0
	red["pvp_grace"] = 0.0
	peers[1] = host
	peers[5] = red
	check(MultiplayerSessionModel.can_damage_actor(red, host, definitions, policy), "An invader and host inside the same authored PvP area must be hostile.")
	var sanctuary_host := host.duplicate(true)
	sanctuary_host["map_id"] = "bellweather_crossing"
	sanctuary_host["position"] = Vector2(312, 220)
	var sanctuary_invader := red.duplicate(true)
	sanctuary_invader["map_id"] = "bellweather_crossing"
	sanctuary_invader["position"] = Vector2(344, 220)
	check(not MultiplayerSessionModel.can_damage_actor(sanctuary_invader, sanctuary_host, definitions, policy), "Sanctuary areas must suppress invasion damage.")
	check(not MultiplayerSessionModel.can_damage_actor(peers.get(2, {}), peers.get(3, {}), definitions, policy), "Co-op allies must not damage each other when friendly fire is disabled.")

	red["position"] = Vector2(392, 240)
	red["facing"] = Vector2.LEFT
	host["position"] = Vector2(360, 240)
	check(MultiplayerSessionModel.in_attack_arc(red, host.get("position", Vector2.ZERO)), "A nearby forward target must be inside the deterministic melee arc.")
	var wounded := MultiplayerSessionModel.apply_actor_damage(host, 4)
	check(int(wounded.get("health", 0)) == 28 and not bool(wounded.get("downed", false)), "Host-side actor damage must reduce health without inventing durable state.")
	var downed := MultiplayerSessionModel.apply_actor_damage(peers.get(2, {}), 999)
	check(bool(downed.get("downed", false)) and not bool(downed.get("active", true)), "A defeated ally must enter a temporary downed state.")
	var banished := MultiplayerSessionModel.apply_actor_damage(red, 999)
	check(bool(banished.get("banished", false)) and not bool(banished.get("active", true)), "A defeated invader must enter a temporary banished state.")
	var restored := MultiplayerSessionModel.respawn_peer(downed, Vector2(328, 272), "clockwood_edge", "ashen")
	check(bool(restored.get("active", false)) and int(restored.get("health", 0)) == int(restored.get("max_health", 0)), "A co-op ally must respawn at full session health with PvP grace.")
	check(float(restored.get("pvp_grace", 0.0)) > 0.0, "Respawn must add bounded PvP grace.")

	var snapshots := MultiplayerSessionModel.snapshot_peers(peers)
	check(snapshots.size() == 4, "Peer snapshots must be bounded and deterministically ordered.")
	var round_trip := MultiplayerSessionModel.peer_from_snapshot(snapshots[1])
	check(not round_trip.is_empty() and int(round_trip.get("peer_id", 0)) == 2, "A peer snapshot must reconstruct a bounded transient actor.")
	check(not round_trip.has("inventory") and not round_trip.has("session_state"), "Online peer snapshots must not contain durable inventory or story progression.")

	finish()


func host_peer(position: Vector2, map_id: String, era_id: String) -> Dictionary:
	return {
		"peer_id": 1,
		"role": MultiplayerSessionModel.ROLE_HOST,
		"display_name": "HOST",
		"position": position,
		"facing": Vector2.RIGHT,
		"health": 32,
		"max_health": 32,
		"map_id": map_id,
		"era_id": era_id,
		"attack_cooldown": 0.0,
		"hurt_lock": 0.0,
		"downed": false,
		"banished": false,
		"pvp_grace": 0.0,
		"active": true
	}


func multiplayer_areas() -> Dictionary:
	return {
		"bellweather_sanctuary": {
			"id": "bellweather_sanctuary",
			"display_name": "Bellweather Sanctuary",
			"map_id": "bellweather_crossing",
			"kind": "sanctuary",
			"priority": 0,
			"bounds": {"left": 32, "right": 608, "top": 96, "bottom": 328},
			"available_eras": [],
			"allow_allies": true,
			"allow_invaders": false,
			"friendly_fire": false,
			"ally_spawn": {"x": 344, "y": 220}
		},
		"clockwood_coop": {
			"id": "clockwood_coop",
			"display_name": "Clockwood Fellowship",
			"map_id": "clockwood_edge",
			"kind": "co_op",
			"priority": 0,
			"bounds": {"left": 32, "right": 768, "top": 96, "bottom": 448},
			"available_eras": [],
			"allow_allies": true,
			"allow_invaders": false,
			"friendly_fire": false,
			"ally_spawn": {"x": 112, "y": 248}
		},
		"clockwood_pvp": {
			"id": "clockwood_pvp",
			"display_name": "Clockwood Ashen Hunt",
			"map_id": "clockwood_edge",
			"kind": "pvp",
			"priority": 20,
			"bounds": {"left": 288, "right": 528, "top": 176, "bottom": 320},
			"available_eras": ["ashen"],
			"allow_allies": true,
			"allow_invaders": true,
			"friendly_fire": false,
			"ally_spawn": {"x": 328, "y": 272},
			"invader_spawn": {"x": 488, "y": 272}
		}
	}


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Multiplayer session-model smoke test passed: party caps, fresh input, sanctuary safety, authored PvP hostility, temporary defeat and bounded snapshots are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
