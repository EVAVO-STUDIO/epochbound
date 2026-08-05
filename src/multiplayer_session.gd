extends Node

const MultiplayerCatalog = preload("res://src/content/multiplayer_catalog.gd")
const MultiplayerSessionModel = preload("res://src/game/multiplayer_session_model.gd")
const EncounterModel = preload("res://src/game/encounter_model.gd")

const PROTOCOL_VERSION := 1
const ENET_CLASS_NAME := "ENetMultiplayerPeer"
const DEFAULT_ADDRESS := "127.0.0.1"
const INPUT_CHANNEL := 1
const SNAPSHOT_CHANNEL := 2
const MENU_ENTRIES := ["HOST CO-OP", "JOIN CO-OP", "INVADE", "BACK"]
const ONLINE_MENU_ENTRIES := ["LEAVE ONLINE SESSION", "BACK"]
const PEER_RADIUS := 7.0
const NOTICE_DURATION := 3.0

# The official runtime equivalent of ENetMultiplayerPeer.new() is resolved
# through ClassDB so projects still parse on builds where the ENet class is
# registered at runtime but is not exposed as a static GDScript type.
var mode: String = MultiplayerSessionModel.MODE_OFFLINE
var requested_role: String = MultiplayerSessionModel.ROLE_ALLY
var local_role: String = MultiplayerSessionModel.ROLE_HOST
var local_peer_id: int = 1
var local_name: String = "WANDERER"
var connect_address: String = DEFAULT_ADDRESS
var connect_port: int = 27491
var network_peer: MultiplayerPeer
var policy: Dictionary = MultiplayerCatalog.default_policy()
var area_definitions: Dictionary = {}
var peers: Dictionary = {}
var lobby_open: bool = false
var lobby_index: int = 0
var connection_pending: bool = false
var session_notice: String = ""
var session_notice_timer: float = 0.0
var input_sequence: int = 0
var snapshot_sequence: int = 0
var last_snapshot_sequence: int = -1
var input_accumulator: float = 0.0
var snapshot_accumulator: float = 0.0
var session_score: Dictionary = {
	"allies_revived": 0,
	"invaders_banished": 0,
	"host_defeats": 0
}
var test_mode: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	connect_multiplayer_signals()
	local_name = default_local_name()
	load_campaign_multiplayer_contract()
	parse_command_line()


func runtime_root() -> Node:
	return get_parent()


func connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func default_local_name() -> String:
	var candidate: String = OS.get_environment("USERNAME")
	if candidate.is_empty():
		candidate = OS.get_environment("USER")
	return MultiplayerSessionModel.sanitize_name(candidate, "WANDERER")


func parse_command_line() -> void:
	var should_host: bool = false
	var should_join: bool = false
	var parsed_address: String = connect_address
	var parsed_port: int = connect_port
	var parsed_role: String = requested_role
	for argument_value in OS.get_cmdline_user_args():
		var argument: String = str(argument_value)
		if argument == "--host":
			should_host = true
		elif argument == "--invade":
			parsed_role = MultiplayerSessionModel.ROLE_INVADER
		elif argument.begins_with("--join="):
			parsed_address = argument.trim_prefix("--join=").strip_edges()
			should_join = true
		elif argument.begins_with("--port="):
			parsed_port = clampi(int(argument.trim_prefix("--port=")), 1024, 65535)
		elif argument.begins_with("--name="):
			local_name = MultiplayerSessionModel.sanitize_name(
				argument.trim_prefix("--name="),
				"WANDERER"
			)
	connect_address = parsed_address if not parsed_address.is_empty() else DEFAULT_ADDRESS
	connect_port = parsed_port
	requested_role = parsed_role
	if should_host:
		call_deferred("host_session", connect_port)
	elif should_join:
		call_deferred("join_session", connect_address, requested_role, connect_port)


func _process(delta: float) -> void:
	session_notice_timer = maxf(0.0, session_notice_timer - delta)
	if session_notice_timer <= 0.0:
		session_notice = ""
	if Input.is_action_just_pressed("network_menu"):
		toggle_lobby()
	if lobby_open:
		update_lobby_menu()
		return
	if mode == MultiplayerSessionModel.MODE_HOST:
		pre_host_runtime_process()
	elif mode == MultiplayerSessionModel.MODE_CLIENT:
		update_client_prediction_and_input(delta)


func post_runtime_process(delta: float) -> void:
	if mode != MultiplayerSessionModel.MODE_HOST:
		return
	var runtime: Node = runtime_root()
	if runtime == null:
		return
	if int(runtime.get("flow")) == 5:
		runtime.call("change_flow", 4)
		set_notice("ONLINE SESSIONS CANNOT PAUSE THE HOST WORLD")
	if int(runtime.get("flow")) != 4:
		return
	sync_host_peer()
	sync_remote_peers_to_host_world()
	update_remote_peers(delta)
	sync_host_peer()
	snapshot_accumulator += delta
	var snapshot_interval: float = 1.0 / maxf(
		4.0,
		float(policy.get("snapshot_rate_hz", 12))
	)
	if snapshot_accumulator >= snapshot_interval:
		snapshot_accumulator = fmod(snapshot_accumulator, snapshot_interval)
		broadcast_world_snapshot()


func toggle_lobby() -> void:
	var runtime: Node = runtime_root()
	if runtime == null:
		return
	lobby_open = not lobby_open
	lobby_index = 0
	if lobby_open:
		runtime.set_process(false)
		set_notice("ONLINE PLAY USES DIRECT ENET / UDP")
	else:
		restore_runtime_processing()


func update_lobby_menu() -> void:
	var entries: Array = online_menu_entries()
	if entries.is_empty():
		return
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
		lobby_index = posmod(lobby_index - 1, entries.size())
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
		lobby_index = posmod(lobby_index + 1, entries.size())
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause_game"):
		lobby_open = false
		restore_runtime_processing()
		return
	var runtime: Node = runtime_root()
	var confirmed: bool = (
		runtime != null
		and runtime.has_method("confirm")
		and bool(runtime.call("confirm"))
	)
	if not confirmed:
		return
	if mode != MultiplayerSessionModel.MODE_OFFLINE or connection_pending:
		if lobby_index == 0:
			leave_session("ONLINE SESSION CLOSED")
		else:
			lobby_open = false
			restore_runtime_processing()
		return
	match lobby_index:
		0:
			host_session(connect_port)
		1:
			join_session(
				connect_address,
				MultiplayerSessionModel.ROLE_ALLY,
				connect_port
			)
		2:
			join_session(
				connect_address,
				MultiplayerSessionModel.ROLE_INVADER,
				connect_port
			)
		3:
			lobby_open = false
			restore_runtime_processing()


func online_menu_entries() -> Array:
	return (
		ONLINE_MENU_ENTRIES.duplicate()
		if mode != MultiplayerSessionModel.MODE_OFFLINE or connection_pending
		else MENU_ENTRIES.duplicate()
	)


func restore_runtime_processing() -> void:
	var runtime: Node = runtime_root()
	if runtime != null:
		runtime.set_process(
			mode != MultiplayerSessionModel.MODE_CLIENT
			and not connection_pending
		)


func ensure_host_gameplay_ready() -> bool:
	var runtime: Node = runtime_root()
	if runtime == null:
		return false
	if int(runtime.get("flow")) == 4:
		return true
	if runtime.has_method("begin_game"):
		runtime.call("begin_game")
	if int(runtime.get("flow")) != 4:
		runtime.call("change_flow", 4)
	return int(runtime.get("flow")) == 4


func load_campaign_multiplayer_contract() -> bool:
	var runtime: Node = runtime_root()
	if runtime == null:
		return false
	var campaign_value: Variant = runtime.get("campaign")
	var campaign: Dictionary = (
		campaign_value if typeof(campaign_value) == TYPE_DICTIONARY else {}
	)
	policy = MultiplayerCatalog.policy(campaign)
	area_definitions = {}
	var campaign_path: String = str(runtime.get("campaign_path"))
	if campaign_path.is_empty():
		return false
	var result: Dictionary = MultiplayerCatalog.load_catalogs(campaign_path, campaign)
	if not bool(result.get("ok", false)):
		set_notice(
			"MULTIPLAYER DATA FAILED: %s" % format_errors(result.get("errors", []))
		)
		return false
	var definitions_value: Variant = result.get("definitions", {})
	area_definitions = (
		definitions_value if typeof(definitions_value) == TYPE_DICTIONARY else {}
	)
	connect_port = int(policy.get("default_port", 27491))
	return bool(policy.get("enabled", false))


func create_enet_peer() -> MultiplayerPeer:
	if not ClassDB.class_exists(ENET_CLASS_NAME):
		return null
	var instance: Object = ClassDB.instantiate(ENET_CLASS_NAME)
	return instance as MultiplayerPeer if instance is MultiplayerPeer else null


func host_session(port: int = -1) -> bool:
	if mode != MultiplayerSessionModel.MODE_OFFLINE or connection_pending:
		return false
	if not load_campaign_multiplayer_contract() or not bool(policy.get("enabled", false)):
		set_notice("THIS CAMPAIGN DOES NOT ENABLE ONLINE PLAY")
		return false
	if not ensure_host_gameplay_ready():
		set_notice("HOST COULD NOT START A VALID JOURNEY")
		return false
	var resolved_port: int = (
		int(policy.get("default_port", 27491))
		if port < 0
		else clampi(port, 1024, 65535)
	)
	var peer: MultiplayerPeer = create_enet_peer()
	if peer == null or not peer.has_method("create_server"):
		set_notice("THIS GODOT BUILD DOES NOT PROVIDE ENET MULTIPLAYER")
		return false
	var max_clients: int = (
		int(policy.get("max_allies", 0))
		+ int(policy.get("max_invaders", 0))
	)
	var error: int = int(peer.call(
		"create_server",
		resolved_port,
		maxi(1, max_clients),
		3
	))
	if error != OK:
		set_notice("HOST FAILED ON UDP PORT %d (ERROR %d)" % [resolved_port, error])
		return false
	network_peer = peer
	multiplayer.multiplayer_peer = network_peer
	mode = MultiplayerSessionModel.MODE_HOST
	local_role = MultiplayerSessionModel.ROLE_HOST
	local_peer_id = 1
	peers = {}
	register_host_peer()
	connection_pending = false
	lobby_open = false
	restore_runtime_processing()
	set_notice("HOSTING CO-OP ON UDP %d" % resolved_port)
	return true


func join_session(
	address: String = DEFAULT_ADDRESS,
	role: String = MultiplayerSessionModel.ROLE_ALLY,
	port: int = -1
) -> bool:
	if mode != MultiplayerSessionModel.MODE_OFFLINE or connection_pending:
		return false
	if not load_campaign_multiplayer_contract() or not bool(policy.get("enabled", false)):
		set_notice("THIS CAMPAIGN DOES NOT ENABLE ONLINE PLAY")
		return false
	connect_address = address.strip_edges() if not address.strip_edges().is_empty() else DEFAULT_ADDRESS
	connect_port = (
		int(policy.get("default_port", 27491))
		if port < 0
		else clampi(port, 1024, 65535)
	)
	requested_role = (
		MultiplayerSessionModel.ROLE_INVADER
		if role == MultiplayerSessionModel.ROLE_INVADER
		else MultiplayerSessionModel.ROLE_ALLY
	)
	var peer: MultiplayerPeer = create_enet_peer()
	if peer == null or not peer.has_method("create_client"):
		set_notice("THIS GODOT BUILD DOES NOT PROVIDE ENET MULTIPLAYER")
		return false
	var error: int = int(peer.call("create_client", connect_address, connect_port, 3))
	if error != OK:
		set_notice("CONNECTION FAILED (ERROR %d)" % error)
		return false
	network_peer = peer
	multiplayer.multiplayer_peer = network_peer
	connection_pending = true
	lobby_open = false
	var runtime: Node = runtime_root()
	if runtime != null:
		runtime.set_process(false)
	set_notice("CONNECTING TO %s:%d" % [connect_address, connect_port])
	return true


func leave_session(reason: String = "ONLINE SESSION CLOSED") -> void:
	if network_peer != null:
		network_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	network_peer = null
	mode = MultiplayerSessionModel.MODE_OFFLINE
	connection_pending = false
	requested_role = MultiplayerSessionModel.ROLE_ALLY
	local_role = MultiplayerSessionModel.ROLE_HOST
	local_peer_id = 1
	peers = {}
	input_sequence = 0
	snapshot_sequence = 0
	last_snapshot_sequence = -1
	lobby_open = false
	restore_runtime_processing()
	set_notice(reason)


func register_host_peer() -> void:
	var runtime: Node = runtime_root()
	if runtime != null:
		peers[1] = host_peer_state(runtime)


func host_peer_state(runtime: Node) -> Dictionary:
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	var position_value: Variant = runtime.get("player")
	var facing_value: Variant = runtime.get("facing")
	var position: Vector2 = (
		position_value if position_value is Vector2 else Vector2.ZERO
	)
	var facing: Vector2 = (
		facing_value if facing_value is Vector2 else Vector2.DOWN
	)
	var display_name: String = "HOST"
	if runtime.has_method("player_name"):
		display_name = str(runtime.call("player_name"))
	var maximum_health: int = 32
	if runtime.has_method("actor_health"):
		maximum_health = int(runtime.call("actor_health", "player", 32))
	return {
		"peer_id": 1,
		"role": MultiplayerSessionModel.ROLE_HOST,
		"display_name": MultiplayerSessionModel.sanitize_name(display_name, "HOST"),
		"position": position,
		"facing": facing,
		"health": int(runtime.get("player_health")),
		"max_health": maximum_health,
		"map_id": str(map_data.get("id", "")),
		"era_id": str(runtime.get("current_era_id")),
		"attack_cooldown": float(runtime.get("player_attack_lock")),
		"hurt_lock": float(runtime.get("player_hurt_lock")),
		"downed": false,
		"respawn_timer": 0.0,
		"banished": false,
		"banish_timer": 0.0,
		"pvp_grace": 0.0,
		"last_sequence": -1,
		"direction": Vector2.ZERO,
		"attack_requested": false,
		"active": true
	}


func sync_host_peer() -> void:
	var runtime: Node = runtime_root()
	if runtime != null:
		peers[1] = host_peer_state(runtime)


func current_host_area() -> Dictionary:
	var runtime: Node = runtime_root()
	if runtime == null:
		return {}
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	var position_value: Variant = runtime.get("player")
	var position: Vector2 = (
		position_value if position_value is Vector2 else Vector2.ZERO
	)
	return MultiplayerCatalog.active_area(
		area_definitions,
		str(map_data.get("id", "")),
		str(runtime.get("current_era_id")),
		position
	)


func join_area_for_role(role: String) -> Dictionary:
	var area: Dictionary = current_host_area()
	if area.is_empty():
		return {}
	if role == MultiplayerSessionModel.ROLE_INVADER:
		return area if MultiplayerCatalog.invaders_allowed(area) else {}
	return area if MultiplayerCatalog.allies_allowed(area) else {}


func campaign_id() -> String:
	var runtime: Node = runtime_root()
	var campaign_value: Variant = runtime.get("campaign") if runtime != null else {}
	var campaign: Dictionary = (
		campaign_value if typeof(campaign_value) == TYPE_DICTIONARY else {}
	)
	return str(campaign.get("id", ""))


func campaign_version() -> String:
	var runtime: Node = runtime_root()
	var campaign_value: Variant = runtime.get("campaign") if runtime != null else {}
	var campaign: Dictionary = (
		campaign_value if typeof(campaign_value) == TYPE_DICTIONARY else {}
	)
	var release_value: Variant = campaign.get("release", {})
	var release: Dictionary = (
		release_value if typeof(release_value) == TYPE_DICTIONARY else {}
	)
	return str(release.get("version", "0.0.0"))


func _on_connected_to_server() -> void:
	connection_pending = false
	local_peer_id = multiplayer.get_unique_id()
	_request_join.rpc_id(
		1,
		requested_role,
		local_name,
		campaign_id(),
		campaign_version(),
		PROTOCOL_VERSION
	)
	set_notice("CONNECTED — NEGOTIATING %s ROLE" % requested_role.to_upper())


func _on_connection_failed() -> void:
	leave_session("CONNECTION FAILED")


func _on_server_disconnected() -> void:
	leave_session("HOST DISCONNECTED")


func _on_peer_connected(_peer_id: int) -> void:
	if mode == MultiplayerSessionModel.MODE_HOST:
		set_notice("A REMOTE PEER CONNECTED")


func _on_peer_disconnected(peer_id: int) -> void:
	MultiplayerSessionModel.remove_peer(peers, peer_id)
	if peer_id == 1 and mode == MultiplayerSessionModel.MODE_CLIENT:
		leave_session("HOST DISCONNECTED")
	elif mode == MultiplayerSessionModel.MODE_HOST:
		set_notice("PEER %d LEFT THE SESSION" % peer_id)


@rpc("any_peer", "call_remote", "reliable", 0)
func _request_join(
	role: String,
	display_name: String,
	remote_campaign_id: String,
	remote_version: String,
	protocol_version: int
) -> void:
	if mode != MultiplayerSessionModel.MODE_HOST or not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if protocol_version != PROTOCOL_VERSION:
		_join_rejected.rpc_id(sender_id, "PROTOCOL VERSION MISMATCH")
		return
	if remote_campaign_id != campaign_id() or remote_version != campaign_version():
		_join_rejected.rpc_id(sender_id, "CAMPAIGN VERSION MISMATCH")
		return
	var resolved_role: String = (
		MultiplayerSessionModel.ROLE_INVADER
		if role == MultiplayerSessionModel.ROLE_INVADER
		else MultiplayerSessionModel.ROLE_ALLY
	)
	var area: Dictionary = join_area_for_role(resolved_role)
	if area.is_empty():
		_join_rejected.rpc_id(sender_id, "HOST IS NOT IN A COMPATIBLE ONLINE AREA")
		return
	var runtime: Node = runtime_root()
	var map_value: Variant = runtime.get("map_data") if runtime != null else {}
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	var host_position_value: Variant = (
		runtime.get("player") if runtime != null else Vector2.ZERO
	)
	var host_position: Vector2 = (
		host_position_value if host_position_value is Vector2 else Vector2.ZERO
	)
	var spawn: Vector2 = MultiplayerCatalog.spawn_position(
		area,
		resolved_role,
		host_position + Vector2(24, 0)
	)
	var era_id: String = (
		str(runtime.get("current_era_id")) if runtime != null else ""
	)
	var result: Dictionary = MultiplayerSessionModel.register_peer(
		peers,
		sender_id,
		resolved_role,
		policy,
		spawn,
		str(map_data.get("id", "")),
		era_id,
		display_name
	)
	if not bool(result.get("ok", false)):
		_join_rejected.rpc_id(
			sender_id,
			str(result.get("reason", "SESSION FULL")).replace("_", " ").to_upper()
		)
		return
	_join_accepted.rpc_id(sender_id, resolved_role, sender_id)
	set_notice(
		"%s ENTERED AS %s" % [
			MultiplayerSessionModel.sanitize_name(display_name),
			resolved_role.to_upper()
		]
	)
	broadcast_world_snapshot()


@rpc("authority", "call_remote", "reliable", 0)
func _join_accepted(role: String, peer_id: int) -> void:
	mode = MultiplayerSessionModel.MODE_CLIENT
	connection_pending = false
	local_role = role
	local_peer_id = peer_id
	lobby_open = false
	restore_runtime_processing()
	set_notice("JOINED AS %s — HOST PROGRESSION ONLY" % role.to_upper())


@rpc("authority", "call_remote", "reliable", 0)
func _join_rejected(reason: String) -> void:
	leave_session("JOIN REJECTED: %s" % reason)


@rpc("any_peer", "call_remote", "unreliable_ordered", INPUT_CHANNEL)
func _submit_input(sequence: int, payload: Dictionary) -> void:
	if mode != MultiplayerSessionModel.MODE_HOST or not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	MultiplayerSessionModel.accept_input(peers, sender_id, sequence, payload)


@rpc("authority", "call_remote", "unreliable_ordered", SNAPSHOT_CHANNEL)
func _receive_snapshot(snapshot: Dictionary) -> void:
	if mode == MultiplayerSessionModel.MODE_CLIENT:
		apply_world_snapshot(snapshot)


func update_client_prediction_and_input(delta: float) -> void:
	if not peers.has(local_peer_id):
		return
	var runtime: Node = runtime_root()
	if runtime == null:
		return
	var direction: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	var attack: bool = Input.is_action_just_pressed("attack")
	var peer_value: Variant = peers.get(local_peer_id, {})
	if typeof(peer_value) == TYPE_DICTIONARY:
		var peer: Dictionary = peer_value
		peer["direction"] = direction
		peer = MultiplayerSessionModel.update_facing(peer)
		if direction.length_squared() > 0.001 and bool(peer.get("active", true)):
			var desired: Vector2 = MultiplayerSessionModel.proposed_position(peer, delta)
			runtime.call("move_actor", "player", desired)
			peer["position"] = runtime.get("player")
		peers[local_peer_id] = peer
	input_accumulator += delta
	var input_interval: float = 1.0 / maxf(
		10.0,
		float(policy.get("input_rate_hz", 30))
	)
	if input_accumulator >= input_interval or attack:
		input_accumulator = fmod(input_accumulator, input_interval)
		input_sequence += 1
		_submit_input.rpc_id(1, input_sequence, {
			"direction": {
				"x": snappedf(direction.x, 0.001),
				"y": snappedf(direction.y, 0.001)
			},
			"attack": attack
		})


func pre_host_runtime_process() -> void:
	var runtime: Node = runtime_root()
	if runtime == null or int(runtime.get("flow")) != 4:
		return
	sync_host_peer()
	if (
		Input.is_action_just_pressed("attack")
		and float(runtime.get("player_attack_lock")) <= 0.0
		and try_host_attack_invader()
	):
		runtime.set("player_attack_lock", MultiplayerSessionModel.ATTACK_COOLDOWN)
		runtime.set("player_attack_timer", 0.17)


func try_host_attack_invader() -> bool:
	var host_value: Variant = peers.get(1, {})
	if typeof(host_value) != TYPE_DICTIONARY:
		return false
	var target_id: int = nearest_actor_target(
		host_value as Dictionary,
		[MultiplayerSessionModel.ROLE_INVADER]
	)
	return (
		target_id > 1
		and apply_peer_damage(1, target_id, MultiplayerSessionModel.ATTACK_DAMAGE)
	)


func update_remote_peers(delta: float) -> void:
	var ids: Array[int] = []
	for key in peers.keys():
		if typeof(key) == TYPE_INT and int(key) > 1:
			ids.append(int(key))
	ids.sort()
	for peer_id in ids:
		var peer_value: Variant = peers.get(peer_id, {})
		if typeof(peer_value) != TYPE_DICTIONARY:
			continue
		var peer: Dictionary = MultiplayerSessionModel.tick_peer(
			peer_value as Dictionary,
			delta
		)
		if bool(peer.get("banished", false)) and float(peer.get("banish_timer", 0.0)) <= 0.0:
			peers[peer_id] = peer
			disconnect_remote_peer(peer_id, "INVADER BANISHED")
			continue
		if bool(peer.get("downed", false)) and float(peer.get("respawn_timer", 0.0)) <= 0.0:
			peer = respawn_remote_peer(peer)
			session_score["allies_revived"] = int(
				session_score.get("allies_revived", 0)
			) + 1
		if bool(peer.get("active", true)):
			peer = move_remote_peer(peer_id, peer, delta)
			if (
				bool(peer.get("attack_requested", false))
				and float(peer.get("attack_cooldown", 0.0)) <= 0.0
			):
				peer["attack_cooldown"] = MultiplayerSessionModel.ATTACK_COOLDOWN
				process_remote_peer_attack(peer_id, peer)
		peer["attack_requested"] = false
		peers[peer_id] = peer


func move_remote_peer(peer_id: int, peer: Dictionary, delta: float) -> Dictionary:
	var runtime: Node = runtime_root()
	if runtime == null:
		return peer
	var output: Dictionary = MultiplayerSessionModel.update_facing(peer)
	var desired: Vector2 = MultiplayerSessionModel.proposed_position(output, delta)
	var current_value: Variant = output.get("position", Vector2.ZERO)
	var current: Vector2 = (
		current_value if current_value is Vector2 else Vector2.ZERO
	)
	var target: Vector2 = runtime.call(
		"clamp_point_to_bounds",
		desired,
		PEER_RADIUS
	)
	var horizontal: Vector2 = Vector2(target.x, current.y)
	if (
		not bool(runtime.call("world_position_blocked", horizontal, PEER_RADIUS))
		and not peer_position_blocked(peer_id, horizontal)
	):
		current.x = horizontal.x
	var vertical: Vector2 = Vector2(current.x, target.y)
	if (
		not bool(runtime.call("world_position_blocked", vertical, PEER_RADIUS))
		and not peer_position_blocked(peer_id, vertical)
	):
		current.y = vertical.y
	output["position"] = current
	return output


func peer_position_blocked(peer_id: int, position: Vector2) -> bool:
	var runtime: Node = runtime_root()
	if runtime != null:
		var host_value: Variant = runtime.get("player")
		if (
			host_value is Vector2
			and (host_value as Vector2).distance_to(position) < PEER_RADIUS * 1.7
		):
			return true
	for key in peers.keys():
		if typeof(key) != TYPE_INT or int(key) == peer_id or int(key) == 1:
			continue
		var value: Variant = peers.get(key, {})
		if (
			typeof(value) != TYPE_DICTIONARY
			or not bool((value as Dictionary).get("active", true))
		):
			continue
		var other_value: Variant = (value as Dictionary).get("position", Vector2.ZERO)
		if (
			other_value is Vector2
			and (other_value as Vector2).distance_to(position) < PEER_RADIUS * 1.7
		):
			return true
	return false


func process_remote_peer_attack(peer_id: int, peer: Dictionary) -> void:
	var role: String = str(peer.get("role", MultiplayerSessionModel.ROLE_ALLY))
	if role == MultiplayerSessionModel.ROLE_INVADER:
		var actor_target: int = nearest_actor_target(
			peer,
			[
				MultiplayerSessionModel.ROLE_HOST,
				MultiplayerSessionModel.ROLE_ALLY
			]
		)
		if actor_target > 0:
			apply_peer_damage(peer_id, actor_target, MultiplayerSessionModel.ATTACK_DAMAGE)
		return
	var invader_target: int = nearest_actor_target(
		peer,
		[MultiplayerSessionModel.ROLE_INVADER]
	)
	if (
		invader_target > 1
		and apply_peer_damage(
			peer_id,
			invader_target,
			MultiplayerSessionModel.ATTACK_DAMAGE
		)
	):
		return
	if MultiplayerSessionModel.can_damage_enemy(role):
		attack_nearest_enemy(peer)


func nearest_actor_target(attacker: Dictionary, roles: Array) -> int:
	var best_id: int = -1
	var best_distance: float = INF
	var origin: Vector2 = MultiplayerSessionModel.peer_attack_origin(attacker)
	for key in peers.keys():
		if typeof(key) != TYPE_INT:
			continue
		var target_id: int = int(key)
		if target_id == int(attacker.get("peer_id", 0)):
			continue
		var value: Variant = peers.get(target_id, {})
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = value
		if (
			not roles.has(str(target.get("role", "")))
			or not MultiplayerSessionModel.can_damage_actor(
				attacker,
				target,
				area_definitions,
				policy
			)
		):
			continue
		var position_value: Variant = target.get("position", Vector2.ZERO)
		var position: Vector2 = (
			position_value if position_value is Vector2 else Vector2.ZERO
		)
		var distance: float = origin.distance_to(position)
		if (
			MultiplayerSessionModel.in_attack_arc(attacker, position)
			and distance < best_distance
		):
			best_id = target_id
			best_distance = distance
	return best_id


func apply_peer_damage(attacker_id: int, target_id: int, amount: int) -> bool:
	var attacker_value: Variant = peers.get(attacker_id, {})
	var target_value: Variant = peers.get(target_id, {})
	if (
		typeof(attacker_value) != TYPE_DICTIONARY
		or typeof(target_value) != TYPE_DICTIONARY
	):
		return false
	var attacker: Dictionary = attacker_value
	var target: Dictionary = target_value
	if not MultiplayerSessionModel.can_damage_actor(
		attacker,
		target,
		area_definitions,
		policy
	):
		return false
	if not MultiplayerSessionModel.in_attack_arc(
		attacker,
		MultiplayerSessionModel.peer_attack_origin(target)
	):
		return false
	if target_id == 1:
		return damage_host_from_peer(attacker, amount)
	var was_active: bool = bool(target.get("active", true))
	target = MultiplayerSessionModel.apply_actor_damage(target, amount)
	peers[target_id] = target
	if was_active and bool(target.get("banished", false)):
		session_score["invaders_banished"] = int(
			session_score.get("invaders_banished", 0)
		) + 1
		set_notice(
			"INVADER %s WAS BANISHED" % str(target.get("display_name", "INVADER"))
		)
	elif was_active and bool(target.get("downed", false)):
		set_notice(
			"ALLY %s WAS DOWNED" % str(target.get("display_name", "ALLY"))
		)
	return true


func damage_host_from_peer(attacker: Dictionary, amount: int) -> bool:
	var runtime: Node = runtime_root()
	if runtime == null or float(runtime.get("player_hurt_lock")) > 0.0:
		return false
	var before: int = int(runtime.get("player_health"))
	var defense: int = 0
	if runtime.has_method("player_defense_value"):
		defense = int(runtime.call("player_defense_value"))
	var resolved: int = maxi(1, amount - defense)
	var host_will_fall: bool = before <= resolved
	runtime.call("damage_actor", "player", amount, {
		"display_name": str(attacker.get("display_name", "INVADER")),
		"attack_damage": amount
	})
	if host_will_fall:
		session_score["host_defeats"] = int(
			session_score.get("host_defeats", 0)
		) + 1
		banish_all_invaders("HOST FELL — INVASION ENDED")
	return true


func attack_nearest_enemy(peer: Dictionary) -> bool:
	var runtime: Node = runtime_root()
	if runtime == null:
		return false
	var entities_value: Variant = runtime.get("runtime_entities")
	var entities: Array = (
		entities_value if typeof(entities_value) == TYPE_ARRAY else []
	)
	var target_index: int = EncounterModel.nearest_facing_enemy_index(
		entities,
		MultiplayerSessionModel.peer_attack_origin(peer),
		MultiplayerSessionModel.peer_facing(peer),
		MultiplayerSessionModel.ATTACK_RANGE
	)
	if target_index < 0:
		return false
	runtime.call(
		"damage_entity",
		target_index,
		MultiplayerSessionModel.ATTACK_DAMAGE,
		str(peer.get("display_name", "ALLY"))
	)
	return true


func respawn_remote_peer(peer: Dictionary) -> Dictionary:
	var area: Dictionary = current_host_area()
	var runtime: Node = runtime_root()
	var fallback_value: Variant = (
		runtime.get("player") if runtime != null else Vector2.ZERO
	)
	var fallback: Vector2 = (
		fallback_value if fallback_value is Vector2 else Vector2.ZERO
	)
	var spawn: Vector2 = MultiplayerCatalog.spawn_position(
		area,
		MultiplayerSessionModel.ROLE_ALLY,
		fallback + Vector2(24, 0)
	)
	var map_value: Variant = runtime.get("map_data") if runtime != null else {}
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	var era_id: String = (
		str(runtime.get("current_era_id")) if runtime != null else ""
	)
	return MultiplayerSessionModel.respawn_peer(
		peer,
		spawn,
		str(map_data.get("id", "")),
		era_id
	)


func sync_remote_peers_to_host_world() -> void:
	var runtime: Node = runtime_root()
	if runtime == null:
		return
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	var map_id: String = str(map_data.get("id", ""))
	var era_id: String = str(runtime.get("current_era_id"))
	var host_area: Dictionary = current_host_area()
	for key in peers.keys().duplicate():
		if typeof(key) != TYPE_INT or int(key) <= 1:
			continue
		var peer_id: int = int(key)
		var value: Variant = peers.get(peer_id, {})
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var peer: Dictionary = value
		var role: String = str(peer.get("role", MultiplayerSessionModel.ROLE_ALLY))
		if (
			role == MultiplayerSessionModel.ROLE_INVADER
			and (
				host_area.is_empty()
				or not MultiplayerCatalog.invaders_allowed(host_area)
			)
		):
			disconnect_remote_peer(peer_id, "HOST LEFT THE INVASION AREA")
			continue
		if (
			role == MultiplayerSessionModel.ROLE_ALLY
			and (
				host_area.is_empty()
				or not MultiplayerCatalog.allies_allowed(host_area)
			)
		):
			disconnect_remote_peer(peer_id, "HOST ENTERED A SOLO AREA")
			continue
		if (
			str(peer.get("map_id", "")) != map_id
			or str(peer.get("era_id", "")) != era_id
		):
			var fallback_value: Variant = runtime.get("player")
			var fallback: Vector2 = (
				fallback_value if fallback_value is Vector2 else Vector2.ZERO
			)
			var spawn: Vector2 = MultiplayerCatalog.spawn_position(
				host_area,
				role,
				fallback + Vector2(24, 0)
			)
			peer = MultiplayerSessionModel.respawn_peer(
				peer,
				spawn,
				map_id,
				era_id
			)
			peers[peer_id] = peer


func banish_all_invaders(reason: String) -> void:
	for key in peers.keys().duplicate():
		if typeof(key) != TYPE_INT or int(key) <= 1:
			continue
		var value: Variant = peers.get(key, {})
		if (
			typeof(value) == TYPE_DICTIONARY
			and str((value as Dictionary).get("role", ""))
			== MultiplayerSessionModel.ROLE_INVADER
		):
			disconnect_remote_peer(int(key), reason)
	set_notice(reason)


func disconnect_remote_peer(peer_id: int, reason: String) -> void:
	if mode == MultiplayerSessionModel.MODE_HOST and network_peer != null and not test_mode:
		_peer_removed.rpc_id(peer_id, reason)
		network_peer.disconnect_peer(peer_id)
	MultiplayerSessionModel.remove_peer(peers, peer_id)


@rpc("authority", "call_remote", "reliable", 0)
func _peer_removed(reason: String) -> void:
	leave_session(reason)


func broadcast_world_snapshot() -> void:
	if mode != MultiplayerSessionModel.MODE_HOST:
		return
	var snapshot: Dictionary = build_world_snapshot()
	if not test_mode:
		_receive_snapshot.rpc(snapshot)


func build_world_snapshot() -> Dictionary:
	var runtime: Node = runtime_root()
	if runtime == null:
		return {}
	sync_host_peer()
	snapshot_sequence += 1
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	var companion_value: Variant = runtime.get("companion")
	var companion_position: Vector2 = (
		companion_value if companion_value is Vector2 else Vector2.ZERO
	)
	return {
		"protocol_version": PROTOCOL_VERSION,
		"sequence": snapshot_sequence,
		"campaign_id": campaign_id(),
		"campaign_version": campaign_version(),
		"map_id": str(map_data.get("id", "")),
		"era_id": str(runtime.get("current_era_id")),
		"peers": MultiplayerSessionModel.snapshot_peers(peers),
		"companion": {
			"position": {
				"x": snappedf(companion_position.x, 0.01),
				"y": snappedf(companion_position.y, 0.01)
			},
			"health": int(runtime.get("companion_health"))
		},
		"clock_shards": int(runtime.get("clock_shards")),
		"runtime_entities": snapshot_runtime_entities(),
		"session_score": session_score.duplicate(true),
		"area": MultiplayerCatalog.area_summary(current_host_area())
	}


func snapshot_runtime_entities() -> Array:
	var runtime: Node = runtime_root()
	var entities_value: Variant = (
		runtime.get("runtime_entities") if runtime != null else []
	)
	var entities: Array = (
		entities_value if typeof(entities_value) == TYPE_ARRAY else []
	)
	var output: Array = []
	for value in entities:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = value
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var facing_value: Variant = entity.get("facing", Vector2.DOWN)
		var position: Vector2 = (
			position_value if position_value is Vector2 else Vector2.ZERO
		)
		var facing: Vector2 = (
			facing_value if facing_value is Vector2 else Vector2.DOWN
		)
		output.append({
			"placement_id": str(entity.get("placement_id", "")),
			"object_id": str(entity.get("object_id", "")),
			"position": {
				"x": snappedf(position.x, 0.01),
				"y": snappedf(position.y, 0.01)
			},
			"facing": {
				"x": snappedf(facing.x, 0.001),
				"y": snappedf(facing.y, 0.001)
			},
			"health": int(entity.get("health", 0)),
			"active": bool(entity.get("active", true)),
			"hit_flash": clampf(float(entity.get("hit_flash", 0.0)), 0.0, 0.2)
		})
	return output


func apply_world_snapshot(snapshot: Dictionary) -> bool:
	if (
		typeof(snapshot.get("protocol_version")) != TYPE_INT
		or int(snapshot.get("protocol_version")) != PROTOCOL_VERSION
	):
		return false
	if (
		str(snapshot.get("campaign_id", "")) != campaign_id()
		or str(snapshot.get("campaign_version", "")) != campaign_version()
	):
		return false
	var sequence_value: Variant = snapshot.get("sequence", -1)
	if (
		typeof(sequence_value) != TYPE_INT
		or int(sequence_value) <= last_snapshot_sequence
	):
		return false
	last_snapshot_sequence = int(sequence_value)
	var runtime: Node = runtime_root()
	if runtime == null:
		return false
	var map_id: String = str(snapshot.get("map_id", ""))
	var era_id: String = str(snapshot.get("era_id", ""))
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	if (
		str(map_data.get("id", "")) != map_id
		and not bool(runtime.call("activate_map", map_id, "", era_id, false))
	):
		return false
	runtime.set("current_era_id", era_id)
	runtime.call("sync_runtime_entities", false)
	apply_entity_snapshots(snapshot.get("runtime_entities", []))
	peers = {}
	var peer_values: Variant = snapshot.get("peers", [])
	if typeof(peer_values) == TYPE_ARRAY:
		for peer_value in peer_values as Array:
			var peer: Dictionary = MultiplayerSessionModel.peer_from_snapshot(peer_value)
			if not peer.is_empty():
				peers[int(peer.get("peer_id", 0))] = peer
	var local_value: Variant = peers.get(local_peer_id, {})
	if typeof(local_value) == TYPE_DICTIONARY:
		var local: Dictionary = local_value
		runtime.set("player", local.get("position", runtime.get("player")))
		runtime.set("facing", local.get("facing", runtime.get("facing")))
		runtime.set(
			"player_health",
			int(local.get("health", runtime.get("player_health")))
		)
	var companion_value: Variant = snapshot.get("companion", {})
	if typeof(companion_value) == TYPE_DICTIONARY:
		var companion_data: Dictionary = companion_value
		var current_companion_value: Variant = runtime.get("companion")
		var current_companion: Vector2 = (
			current_companion_value
			if current_companion_value is Vector2
			else Vector2.ZERO
		)
		runtime.set(
			"companion",
			MultiplayerSessionModel.vector_from_data(
				companion_data.get("position"),
				current_companion
			)
		)
		runtime.set(
			"companion_health",
			int(companion_data.get("health", runtime.get("companion_health")))
		)
	runtime.set(
		"clock_shards",
		int(snapshot.get("clock_shards", runtime.get("clock_shards")))
	)
	if typeof(snapshot.get("session_score")) == TYPE_DICTIONARY:
		session_score = (snapshot.get("session_score") as Dictionary).duplicate(true)
	if int(runtime.get("flow")) != 4:
		runtime.call("change_flow", 4)
	runtime.queue_redraw()
	return true


func apply_entity_snapshots(value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	var runtime: Node = runtime_root()
	if runtime == null:
		return
	var entities_value: Variant = runtime.get("runtime_entities")
	var entities: Array = (
		entities_value if typeof(entities_value) == TYPE_ARRAY else []
	)
	var by_id: Dictionary = {}
	for index in range(entities.size()):
		if typeof(entities[index]) == TYPE_DICTIONARY:
			by_id[str((entities[index] as Dictionary).get("placement_id", ""))] = index
	for snapshot_value in value as Array:
		if typeof(snapshot_value) != TYPE_DICTIONARY:
			continue
		var entity_snapshot: Dictionary = snapshot_value
		var placement_id: String = str(entity_snapshot.get("placement_id", ""))
		if not by_id.has(placement_id):
			continue
		var index: int = int(by_id.get(placement_id))
		var entity: Dictionary = entities[index]
		var current_position_value: Variant = entity.get("position", Vector2.ZERO)
		var current_facing_value: Variant = entity.get("facing", Vector2.DOWN)
		var current_position: Vector2 = (
			current_position_value
			if current_position_value is Vector2
			else Vector2.ZERO
		)
		var current_facing: Vector2 = (
			current_facing_value
			if current_facing_value is Vector2
			else Vector2.DOWN
		)
		entity["position"] = MultiplayerSessionModel.vector_from_data(
			entity_snapshot.get("position"),
			current_position
		)
		entity["facing"] = MultiplayerSessionModel.vector_from_data(
			entity_snapshot.get("facing"),
			current_facing
		)
		entity["health"] = int(entity_snapshot.get("health", entity.get("health", 0)))
		entity["active"] = bool(entity_snapshot.get("active", entity.get("active", true)))
		entity["hit_flash"] = clampf(
			float(entity_snapshot.get("hit_flash", 0.0)),
			0.0,
			0.2
		)
		entities[index] = entity
	runtime.set("runtime_entities", entities)


func visible_peer_states() -> Array:
	var output: Array = []
	var map_id: String = ""
	var era_id: String = ""
	var runtime: Node = runtime_root()
	if runtime != null:
		var map_value: Variant = runtime.get("map_data")
		var map_data: Dictionary = (
			map_value if typeof(map_value) == TYPE_DICTIONARY else {}
		)
		map_id = str(map_data.get("id", ""))
		era_id = str(runtime.get("current_era_id"))
	var ids: Array[int] = []
	for key in peers.keys():
		if typeof(key) == TYPE_INT:
			ids.append(int(key))
	ids.sort()
	for peer_id in ids:
		if peer_id == local_peer_id:
			continue
		var value: Variant = peers.get(peer_id, {})
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var peer: Dictionary = value
		if (
			str(peer.get("map_id", "")) == map_id
			and str(peer.get("era_id", "")) == era_id
		):
			output.append(peer.duplicate(true))
	return output


func online_area() -> Dictionary:
	var runtime: Node = runtime_root()
	if runtime == null:
		return {}
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	var player_value: Variant = runtime.get("player")
	var position: Vector2 = (
		player_value if player_value is Vector2 else Vector2.ZERO
	)
	return MultiplayerCatalog.active_area(
		area_definitions,
		str(map_data.get("id", "")),
		str(runtime.get("current_era_id")),
		position
	)


func online_status_text() -> String:
	if connection_pending:
		return "CONNECTING %s:%d" % [connect_address, connect_port]
	if mode == MultiplayerSessionModel.MODE_HOST:
		return "HOST  •  %d ALLY  •  %d INVADER" % [
			MultiplayerSessionModel.role_count(
				peers,
				MultiplayerSessionModel.ROLE_ALLY
			),
			MultiplayerSessionModel.role_count(
				peers,
				MultiplayerSessionModel.ROLE_INVADER
			)
		]
	if mode == MultiplayerSessionModel.MODE_CLIENT:
		return "%s  •  HOST-AUTHORITATIVE" % local_role.to_upper()
	return "OFFLINE"


func blocks_manual_save() -> bool:
	return (
		mode == MultiplayerSessionModel.MODE_CLIENT
		or peers.size() > 1
		or connection_pending
	)


func blocks_autosave() -> bool:
	return (
		mode == MultiplayerSessionModel.MODE_CLIENT
		or connection_pending
		or MultiplayerSessionModel.role_count(
			peers,
			MultiplayerSessionModel.ROLE_INVADER
		) > 0
	)


func configure_test_host_session() -> bool:
	test_mode = true
	if not load_campaign_multiplayer_contract():
		return false
	mode = MultiplayerSessionModel.MODE_HOST
	local_role = MultiplayerSessionModel.ROLE_HOST
	local_peer_id = 1
	peers = {}
	register_host_peer()
	return MultiplayerSessionModel.contract_ok(policy)


func register_test_peer(peer_id: int, role: String) -> Dictionary:
	var area: Dictionary = current_host_area()
	var runtime: Node = runtime_root()
	var map_value: Variant = runtime.get("map_data") if runtime != null else {}
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	var fallback_value: Variant = (
		runtime.get("player") if runtime != null else Vector2.ZERO
	)
	var fallback: Vector2 = (
		fallback_value if fallback_value is Vector2 else Vector2.ZERO
	)
	var spawn: Vector2 = MultiplayerCatalog.spawn_position(
		area,
		role,
		fallback + Vector2(24, 0)
	)
	var era_id: String = (
		str(runtime.get("current_era_id")) if runtime != null else ""
	)
	return MultiplayerSessionModel.register_peer(
		peers,
		peer_id,
		role,
		policy,
		spawn,
		str(map_data.get("id", "")),
		era_id,
		"TEST %d" % peer_id
	)


func accept_test_input(peer_id: int, sequence: int, payload: Dictionary) -> Dictionary:
	return MultiplayerSessionModel.accept_input(peers, peer_id, sequence, payload)


func set_test_peer_grace(peer_id: int, seconds: float) -> void:
	var value: Variant = peers.get(peer_id, {})
	if typeof(value) == TYPE_DICTIONARY:
		var peer: Dictionary = value
		peer["pvp_grace"] = maxf(0.0, seconds)
		peers[peer_id] = peer


func multiplayer_runtime_contract_ok() -> bool:
	return (
		MultiplayerSessionModel.contract_ok(policy)
		and str(policy.get("transport", "")) == MultiplayerCatalog.TRANSPORT_ENET
		and str(policy.get("shared_progression", ""))
		== MultiplayerCatalog.PROGRESSION_HOST_ONLY
		and str(policy.get("pvp_rewards", ""))
		== MultiplayerCatalog.REWARD_SESSION_ONLY
		and input_accumulator >= 0.0
		and snapshot_accumulator >= 0.0
		and PROTOCOL_VERSION == 1
	)


func set_notice(message: String, duration: float = NOTICE_DURATION) -> void:
	session_notice = message.strip_edges().to_upper()
	session_notice_timer = maxf(0.1, duration)


func format_errors(value: Variant) -> String:
	var output: PackedStringArray = PackedStringArray()
	if typeof(value) == TYPE_ARRAY:
		for message in value as Array:
			output.append(str(message))
	return " | ".join(output)
