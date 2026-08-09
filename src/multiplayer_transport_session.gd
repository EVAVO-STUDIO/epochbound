extends "res://src/multiplayer_session.gd"

const NETWORK_SNAPSHOT_COMPRESSION_MODE := FileAccess.COMPRESSION_DEFLATE
const SNAPSHOT_WIRE_MAGIC_TEXT := "EPB1"
const SNAPSHOT_WIRE_MAGIC_BYTES := 4
const SNAPSHOT_WIRE_DIGEST_BYTES := 32
const SNAPSHOT_WIRE_HEADER_BYTES := SNAPSHOT_WIRE_MAGIC_BYTES + SNAPSHOT_WIRE_DIGEST_BYTES
const MAX_NETWORK_SNAPSHOT_BYTES := 1200
const MAX_DECOMPRESSED_SNAPSHOT_BYTES := 65536
const GRACEFUL_LEAVE_TIMEOUT_SECONDS := 3.0
const MAX_GRACEFUL_LEAVE_REASON_CHARS := 80
const MAX_GRACEFUL_LEAVE_HISTORY := 8
const GRACEFUL_HOST_SHUTDOWN_TIMEOUT_SECONDS := 3.0
const HOST_SHUTDOWN_COMMIT_GRACE_SECONDS := 1.0
const HOST_SHUTDOWN_DISCONNECT_GRACE_SECONDS := 1.0

var snapshot_broadcast_pending := false
var last_snapshot_wire_bytes := 0
var last_snapshot_uncompressed_bytes := 0
var session_closing := false
var graceful_leave_pending := false
var graceful_leave_sequence := 0
var last_graceful_leave_ack_sequence := -1
var graceful_leave_timeout_remaining := 0.0
var graceful_leave_request_count := 0
var last_graceful_leave_peer_id := -1
var graceful_leave_peer_history: Array[int] = []
var host_shutdown_pending := false
var host_shutdown_sequence := 0
var host_shutdown_timeout_remaining := 0.0
var host_shutdown_commit_remaining := 0.0
var host_shutdown_reason := ""
var host_shutdown_expected_peer_ids: Array[int] = []
var host_shutdown_ack_peer_ids: Array[int] = []
var host_shutdown_commit_sent := false
var host_shutdown_disconnect_sent := false
var host_shutdown_disconnect_remaining := 0.0
var host_shutdown_disconnected_peer_ids: Array[int] = []
var remote_host_shutdown_pending := false
var remote_host_shutdown_sequence := -1
var remote_host_shutdown_reason := ""
var last_host_shutdown_sequence := -1
var last_host_shutdown_expected_count := 0
var last_host_shutdown_ack_count := 0
var last_host_shutdown_disconnect_count := 0
var last_host_shutdown_forced := false
var last_host_shutdown_ack_sent_sequence := -1
var last_host_shutdown_commit_received := false
var last_host_shutdown_disconnect_observed := false
var last_host_shutdown_reason := ""

func _process(delta: float) -> void:
	super._process(delta)
	if graceful_leave_pending:
		graceful_leave_timeout_remaining = maxf(
			0.0,
			graceful_leave_timeout_remaining - delta
		)
		if graceful_leave_timeout_remaining <= 0.0:
			graceful_leave_pending = false
			close_session_immediately("ONLINE SESSION CLOSED — HOST ACK TIMEOUT")
	update_host_shutdown(delta)

func host_session(port: int = -1) -> bool:
	reset_host_shutdown_tracking(true)
	graceful_leave_request_count = 0
	last_graceful_leave_peer_id = -1
	graceful_leave_peer_history.clear()
	var hosted: bool = super.host_session(port)
	if hosted and network_peer != null:
		network_peer.set("refuse_new_connections", false)
	return hosted

func join_session(
	address: String = DEFAULT_ADDRESS,
	role: String = MultiplayerSessionModel.ROLE_ALLY,
	port: int = -1
) -> bool:
	reset_host_shutdown_tracking(true)
	return super.join_session(address, role, port)


func pre_host_runtime_process() -> void:
	if host_shutdown_pending:
		return
	super.pre_host_runtime_process()


func post_runtime_process(delta: float) -> void:
	if host_shutdown_pending:
		return
	super.post_runtime_process(delta)


func _on_server_disconnected() -> void:
	if session_closing:
		return
	if last_host_shutdown_commit_received:
		last_host_shutdown_disconnect_observed = true
		call_deferred("finish_remote_host_shutdown")
		return
	super._on_server_disconnected()


func _on_peer_disconnected(peer_id: int) -> void:
	if (
		host_shutdown_pending
		and host_shutdown_expected_peer_ids.has(peer_id)
		and not host_shutdown_disconnected_peer_ids.has(peer_id)
	):
		host_shutdown_disconnected_peer_ids.append(peer_id)
		host_shutdown_disconnected_peer_ids.sort()
		last_host_shutdown_disconnect_count = host_shutdown_disconnected_peer_ids.size()
	if (
		peer_id == 1
		and mode == MultiplayerSessionModel.MODE_CLIENT
		and last_host_shutdown_commit_received
	):
		last_host_shutdown_disconnect_observed = true
		call_deferred("finish_remote_host_shutdown")
		return
	super._on_peer_disconnected(peer_id)


func finish_remote_host_shutdown() -> void:
	if mode != MultiplayerSessionModel.MODE_CLIENT or session_closing:
		return
	close_session_immediately(last_host_shutdown_reason)


func update_client_prediction_and_input(delta: float) -> void:
	if (
		graceful_leave_pending
		or remote_host_shutdown_pending
		or last_host_shutdown_commit_received
	):
		return
	super.update_client_prediction_and_input(delta)

func broadcast_world_snapshot() -> void:
	if (
		mode != MultiplayerSessionModel.MODE_HOST
		or test_mode
		or snapshot_broadcast_pending
		or session_closing
		or host_shutdown_pending
	):
		return
	snapshot_broadcast_pending = true
	call_deferred("broadcast_world_snapshot_wire")

func broadcast_world_snapshot_wire() -> void:
	snapshot_broadcast_pending = false
	if (
		mode != MultiplayerSessionModel.MODE_HOST
		or test_mode
		or session_closing
		or host_shutdown_pending
		or not multiplayer.is_server()
	):
		return
	var connected_peer_ids: PackedInt32Array = multiplayer.get_peers()
	if connected_peer_ids.is_empty():
		return
	var snapshot: Dictionary = build_world_snapshot()
	var payload: PackedByteArray = encode_world_snapshot(snapshot)
	if payload.is_empty():
		set_notice(
			"ONLINE SNAPSHOT EXCEEDED THE %d-BYTE TRANSPORT BUDGET" %
			MAX_NETWORK_SNAPSHOT_BYTES
		)
		return
	for peer_id in connected_peer_ids:
		if peers.has(int(peer_id)):
			_receive_snapshot_wire.rpc_id(int(peer_id), payload)


func encode_world_snapshot(snapshot: Dictionary) -> PackedByteArray:
	var serialized: PackedByteArray = var_to_bytes(snapshot)
	last_snapshot_uncompressed_bytes = serialized.size()
	if serialized.is_empty() or serialized.size() > MAX_DECOMPRESSED_SNAPSHOT_BYTES:
		last_snapshot_wire_bytes = 0
		return PackedByteArray()
	var compressed: PackedByteArray = serialized.compress(
		NETWORK_SNAPSHOT_COMPRESSION_MODE
	)
	if compressed.is_empty():
		last_snapshot_wire_bytes = 0
		return PackedByteArray()
	var digest: PackedByteArray = snapshot_wire_digest(compressed)
	if digest.size() != SNAPSHOT_WIRE_DIGEST_BYTES:
		last_snapshot_wire_bytes = 0
		return PackedByteArray()
	var payload := PackedByteArray()
	payload.append_array(snapshot_wire_magic())
	payload.append_array(digest)
	payload.append_array(compressed)
	last_snapshot_wire_bytes = payload.size()
	if payload.size() > MAX_NETWORK_SNAPSHOT_BYTES:
		return PackedByteArray()
	return payload


func decode_world_snapshot(payload: PackedByteArray) -> Dictionary:
	if (
		payload.size() <= SNAPSHOT_WIRE_HEADER_BYTES
		or payload.size() > MAX_NETWORK_SNAPSHOT_BYTES
	):
		return {}
	var magic: PackedByteArray = payload.slice(0, SNAPSHOT_WIRE_MAGIC_BYTES)
	if magic != snapshot_wire_magic():
		return {}
	var expected_digest: PackedByteArray = payload.slice(
		SNAPSHOT_WIRE_MAGIC_BYTES,
		SNAPSHOT_WIRE_HEADER_BYTES
	)
	var compressed: PackedByteArray = payload.slice(SNAPSHOT_WIRE_HEADER_BYTES)
	var actual_digest: PackedByteArray = snapshot_wire_digest(compressed)
	if (
		actual_digest.size() != SNAPSHOT_WIRE_DIGEST_BYTES
		or actual_digest != expected_digest
	):
		return {}
	var serialized: PackedByteArray = compressed.decompress_dynamic(
		MAX_DECOMPRESSED_SNAPSHOT_BYTES,
		NETWORK_SNAPSHOT_COMPRESSION_MODE
	)
	if serialized.is_empty():
		return {}
	var decoded: Variant = bytes_to_var(serialized)
	return decoded as Dictionary if typeof(decoded) == TYPE_DICTIONARY else {}


func snapshot_wire_magic() -> PackedByteArray:
	return SNAPSHOT_WIRE_MAGIC_TEXT.to_ascii_buffer()


func snapshot_wire_digest(value: PackedByteArray) -> PackedByteArray:
	if value.is_empty():
		return PackedByteArray()
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if hashing.update(value) != OK:
		return PackedByteArray()
	return hashing.finish()

@rpc("authority", "call_remote", "unreliable_ordered", SNAPSHOT_CHANNEL)
func _receive_snapshot_wire(payload: PackedByteArray) -> void:
	if (
		mode != MultiplayerSessionModel.MODE_CLIENT
		or session_closing
		or graceful_leave_pending
		or remote_host_shutdown_pending
		or last_host_shutdown_commit_received
	):
		return
	var snapshot: Dictionary = decode_world_snapshot(payload)
	if not snapshot.is_empty():
		apply_world_snapshot(snapshot)

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
		var position: Vector2 = (
			position_value if position_value is Vector2 else Vector2.ZERO
		)
		output.append({
			"placement_id": str(entity.get("placement_id", "")),
			"position": {
				"x": snappedf(position.x, 0.01),
				"y": snappedf(position.y, 0.01)
			},
			"facing": snapshot_facing_name(entity.get("facing", "down")),
			"health": int(entity.get("health", 0)),
			"active": bool(entity.get("active", true)),
			"hit_flash": clampf(float(entity.get("hit_flash", 0.0)), 0.0, 0.2)
		})
	return output


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
		var current_position: Vector2 = (
			current_position_value
			if current_position_value is Vector2
			else Vector2.ZERO
		)
		entity["position"] = MultiplayerSessionModel.vector_from_data(
			entity_snapshot.get("position"),
			current_position
		)
		entity["facing"] = snapshot_facing_name(
			entity_snapshot.get("facing", entity.get("facing", "down"))
		)
		entity["health"] = int(
			entity_snapshot.get("health", entity.get("health", 0))
		)
		entity["active"] = bool(
			entity_snapshot.get("active", entity.get("active", true))
		)
		entity["hit_flash"] = clampf(
			float(entity_snapshot.get("hit_flash", 0.0)),
			0.0,
			0.2
		)
		entities[index] = entity
	runtime.set("runtime_entities", entities)


func snapshot_facing_name(value: Variant) -> String:
	if value is Vector2:
		var direction: Vector2 = value
		if absf(direction.x) > absf(direction.y):
			return "right" if direction.x > 0.0 else "left"
		if absf(direction.y) > 0.001:
			return "down" if direction.y > 0.0 else "up"
		return "down"
	var facing_name: String = str(value).to_lower()
	return facing_name if facing_name in ["up", "left", "right", "down"] else "down"


func request_graceful_leave(reason: String = "ONLINE SESSION CLOSED") -> bool:
	if (
		mode != MultiplayerSessionModel.MODE_CLIENT
		or connection_pending
		or network_peer == null
		or session_closing
	):
		return false
	if graceful_leave_pending:
		return true
	graceful_leave_sequence += 1
	graceful_leave_pending = true
	graceful_leave_timeout_remaining = GRACEFUL_LEAVE_TIMEOUT_SECONDS
	lobby_open = false
	_request_graceful_leave.rpc_id(
		1,
		graceful_leave_sequence,
		graceful_leave_reason(reason)
	)
	set_notice("LEAVING ONLINE SESSION — WAITING FOR HOST")
	return true


@rpc("any_peer", "call_remote", "reliable", 0)
func _request_graceful_leave(sequence: int, reason: String) -> void:
	if mode != MultiplayerSessionModel.MODE_HOST or not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sequence <= 0 or sender_id <= 1 or not peers.has(sender_id):
		return
	var peer_value: Variant = peers.get(sender_id, {})
	var peer: Dictionary = (
		peer_value if typeof(peer_value) == TYPE_DICTIONARY else {}
	)
	var resolved_reason: String = graceful_leave_reason(reason)
	graceful_leave_request_count += 1
	last_graceful_leave_peer_id = sender_id
	graceful_leave_peer_history.append(sender_id)
	while graceful_leave_peer_history.size() > MAX_GRACEFUL_LEAVE_HISTORY:
		graceful_leave_peer_history.pop_front()
	MultiplayerSessionModel.remove_peer(peers, sender_id)
	_graceful_leave_accepted.rpc_id(
		sender_id,
		sequence,
		sender_id,
		resolved_reason
	)
	set_notice(
		"%s LEFT CLEANLY" % str(peer.get("display_name", "REMOTE PEER"))
	)


@rpc("authority", "call_remote", "reliable", 0)
func _graceful_leave_accepted(
	sequence: int,
	peer_id: int,
	reason: String
) -> void:
	if (
		mode != MultiplayerSessionModel.MODE_CLIENT
		or not graceful_leave_pending
		or sequence != graceful_leave_sequence
		or peer_id != local_peer_id
	):
		return
	last_graceful_leave_ack_sequence = sequence
	graceful_leave_pending = false
	graceful_leave_timeout_remaining = 0.0
	close_session_immediately(graceful_leave_reason(reason))


func graceful_leave_reason(value: String) -> String:
	var output: String = value.strip_edges().to_upper()
	if output.is_empty():
		output = "ONLINE SESSION CLOSED"
	if output.length() > MAX_GRACEFUL_LEAVE_REASON_CHARS:
		output = output.substr(0, MAX_GRACEFUL_LEAVE_REASON_CHARS)
	return output


func reset_host_shutdown_tracking(clear_evidence: bool) -> void:
	host_shutdown_pending = false
	host_shutdown_timeout_remaining = 0.0
	host_shutdown_commit_remaining = 0.0
	host_shutdown_reason = ""
	host_shutdown_expected_peer_ids.clear()
	host_shutdown_ack_peer_ids.clear()
	host_shutdown_commit_sent = false
	host_shutdown_disconnect_sent = false
	host_shutdown_disconnect_remaining = 0.0
	host_shutdown_disconnected_peer_ids.clear()
	remote_host_shutdown_pending = false
	remote_host_shutdown_sequence = -1
	remote_host_shutdown_reason = ""
	if clear_evidence:
		host_shutdown_sequence = 0
		last_host_shutdown_sequence = -1
		last_host_shutdown_expected_count = 0
		last_host_shutdown_ack_count = 0
		last_host_shutdown_disconnect_count = 0
		last_host_shutdown_forced = false
		last_host_shutdown_ack_sent_sequence = -1
		last_host_shutdown_commit_received = false
		last_host_shutdown_disconnect_observed = false
		last_host_shutdown_reason = ""


func registered_remote_peer_ids() -> Array[int]:
	var connected_ids := PackedInt32Array()
	if not test_mode:
		connected_ids = multiplayer.get_peers()
	var output: Array[int] = []
	for key in peers.keys():
		if typeof(key) != TYPE_INT or int(key) <= 1:
			continue
		var peer_id := int(key)
		if test_mode or connected_ids.has(peer_id):
			output.append(peer_id)
	output.sort()
	return output


func request_graceful_host_shutdown(reason: String = "ONLINE SESSION CLOSED") -> bool:
	if (
		mode != MultiplayerSessionModel.MODE_HOST
		or connection_pending
		or session_closing
		or (network_peer == null and not test_mode)
	):
		return false
	if host_shutdown_pending:
		return true
	host_shutdown_sequence += 1
	host_shutdown_pending = true
	host_shutdown_timeout_remaining = GRACEFUL_HOST_SHUTDOWN_TIMEOUT_SECONDS
	host_shutdown_commit_remaining = 0.0
	host_shutdown_reason = graceful_leave_reason(reason)
	host_shutdown_expected_peer_ids = registered_remote_peer_ids()
	host_shutdown_ack_peer_ids.clear()
	host_shutdown_commit_sent = false
	host_shutdown_disconnect_sent = false
	host_shutdown_disconnect_remaining = 0.0
	host_shutdown_disconnected_peer_ids.clear()
	last_host_shutdown_sequence = host_shutdown_sequence
	last_host_shutdown_expected_count = host_shutdown_expected_peer_ids.size()
	last_host_shutdown_ack_count = 0
	last_host_shutdown_disconnect_count = 0
	last_host_shutdown_forced = false
	last_host_shutdown_reason = host_shutdown_reason
	snapshot_broadcast_pending = false
	lobby_open = false
	if network_peer != null:
		network_peer.set("refuse_new_connections", true)
	if not test_mode:
		for peer_id in host_shutdown_expected_peer_ids:
			_host_shutdown_requested.rpc_id(
				peer_id,
				host_shutdown_sequence,
				host_shutdown_reason
			)
	set_notice(
		"CLOSING ONLINE SESSION — WAITING FOR %d PEER ACK" %
		host_shutdown_expected_peer_ids.size()
	)
	if host_shutdown_expected_peer_ids.is_empty():
		commit_host_shutdown(false)
	return true


@rpc("authority", "call_remote", "reliable", 0)
func _host_shutdown_requested(sequence: int, reason: String) -> void:
	if (
		mode != MultiplayerSessionModel.MODE_CLIENT
		or connection_pending
		or session_closing
		or sequence <= 0
		or sequence <= remote_host_shutdown_sequence
	):
		return
	remote_host_shutdown_pending = true
	remote_host_shutdown_sequence = sequence
	remote_host_shutdown_reason = graceful_leave_reason(reason)
	last_host_shutdown_sequence = sequence
	last_host_shutdown_reason = remote_host_shutdown_reason
	last_host_shutdown_ack_sent_sequence = sequence
	_ack_host_shutdown.rpc_id(1, sequence, local_peer_id)
	set_notice("HOST IS CLOSING — SHUTDOWN ACKNOWLEDGED")


@rpc("any_peer", "call_remote", "reliable", 0)
func _ack_host_shutdown(sequence: int, peer_id: int) -> void:
	if mode != MultiplayerSessionModel.MODE_HOST or not multiplayer.is_server():
		return
	accept_host_shutdown_ack(
		multiplayer.get_remote_sender_id(),
		sequence,
		peer_id
	)


func accept_host_shutdown_ack(
	sender_id: int,
	sequence: int,
	peer_id: int
) -> bool:
	if (
		not host_shutdown_pending
		or host_shutdown_commit_sent
		or sequence != host_shutdown_sequence
		or sender_id != peer_id
		or not host_shutdown_expected_peer_ids.has(sender_id)
		or host_shutdown_ack_peer_ids.has(sender_id)
	):
		return false
	host_shutdown_ack_peer_ids.append(sender_id)
	host_shutdown_ack_peer_ids.sort()
	last_host_shutdown_ack_count = host_shutdown_ack_peer_ids.size()
	if host_shutdown_ack_peer_ids.size() >= host_shutdown_expected_peer_ids.size():
		commit_host_shutdown(false)
	return true


func commit_host_shutdown(forced: bool) -> bool:
	if not host_shutdown_pending or host_shutdown_commit_sent:
		return false
	host_shutdown_commit_sent = true
	host_shutdown_timeout_remaining = 0.0
	host_shutdown_commit_remaining = HOST_SHUTDOWN_COMMIT_GRACE_SECONDS
	last_host_shutdown_sequence = host_shutdown_sequence
	last_host_shutdown_expected_count = host_shutdown_expected_peer_ids.size()
	last_host_shutdown_ack_count = host_shutdown_ack_peer_ids.size()
	last_host_shutdown_forced = forced
	last_host_shutdown_reason = host_shutdown_reason
	if (
		not test_mode
		and multiplayer.is_server()
		and not multiplayer.get_peers().is_empty()
	):
		# Queue one reliable broadcast before any recipient can detach. Per-peer
		# sends allow the first recipient's immediate close to race the next send.
		_host_shutdown_committed.rpc(
			host_shutdown_sequence,
			host_shutdown_reason
		)
	set_notice(
		"ONLINE SESSION SHUTDOWN COMMITTED%s" %
		(" — ACK TIMEOUT" if forced else "")
	)
	return true


@rpc("authority", "call_remote", "reliable", 0)
func _host_shutdown_committed(sequence: int, reason: String) -> void:
	if (
		mode != MultiplayerSessionModel.MODE_CLIENT
		or not remote_host_shutdown_pending
		or sequence != remote_host_shutdown_sequence
	):
		return
	last_host_shutdown_sequence = sequence
	last_host_shutdown_commit_received = true
	last_host_shutdown_reason = graceful_leave_reason(reason)
	remote_host_shutdown_pending = false
	set_notice("HOST SHUTDOWN COMMITTED — WAITING FOR DISCONNECT")


func begin_host_shutdown_disconnect() -> void:
	if not host_shutdown_pending or host_shutdown_disconnect_sent:
		return
	host_shutdown_disconnect_sent = true
	host_shutdown_disconnect_remaining = HOST_SHUTDOWN_DISCONNECT_GRACE_SECONDS
	if test_mode:
		host_shutdown_disconnected_peer_ids = host_shutdown_expected_peer_ids.duplicate()
		last_host_shutdown_disconnect_count = host_shutdown_disconnected_peer_ids.size()
		finish_host_shutdown()
		return
	if network_peer != null and multiplayer.is_server():
		var connected_ids: PackedInt32Array = multiplayer.get_peers()
		for peer_id in host_shutdown_expected_peer_ids:
			if not connected_ids.has(peer_id):
				continue
			# SceneMultiplayer removes the peer from its relay set before ENet
			# begins closing. Calling ENet directly leaves stale relay state and
			# can make Godot send through a peer whose channel count is already 0.
			multiplayer.call("disconnect_peer", peer_id)
			if not host_shutdown_disconnected_peer_ids.has(peer_id):
				host_shutdown_disconnected_peer_ids.append(peer_id)
		host_shutdown_disconnected_peer_ids.sort()
		last_host_shutdown_disconnect_count = host_shutdown_disconnected_peer_ids.size()
	set_notice("ONLINE SESSION SHUTDOWN — DISCONNECTING PEERS")
	if host_shutdown_remote_connections_closed():
		finish_host_shutdown()


func update_host_shutdown(delta: float) -> void:
	if not host_shutdown_pending:
		return
	if host_shutdown_commit_sent:
		if not host_shutdown_disconnect_sent:
			host_shutdown_commit_remaining = maxf(
				0.0,
				host_shutdown_commit_remaining - delta
			)
			# Keep the ENet server attached for the complete reliable-commit flush
			# window, then make the host own every remote disconnect.
			if host_shutdown_commit_remaining <= 0.0:
				begin_host_shutdown_disconnect()
		else:
			host_shutdown_disconnect_remaining = maxf(
				0.0,
				host_shutdown_disconnect_remaining - delta
			)
			if (
				host_shutdown_remote_connections_closed()
				or host_shutdown_disconnect_remaining <= 0.0
			):
				finish_host_shutdown()
		return
	host_shutdown_timeout_remaining = maxf(
		0.0,
		host_shutdown_timeout_remaining - delta
	)
	if host_shutdown_ack_peer_ids.size() >= host_shutdown_expected_peer_ids.size():
		commit_host_shutdown(false)
	elif host_shutdown_timeout_remaining <= 0.0:
		commit_host_shutdown(true)


func host_shutdown_remote_connections_closed() -> bool:
	if test_mode or network_peer == null:
		return host_shutdown_commit_sent
	var connected_ids: PackedInt32Array = multiplayer.get_peers()
	for peer_id in host_shutdown_expected_peer_ids:
		if connected_ids.has(peer_id):
			return false
	return true


func finish_host_shutdown() -> void:
	if not host_shutdown_pending:
		return
	var reason := host_shutdown_reason
	last_host_shutdown_expected_count = host_shutdown_expected_peer_ids.size()
	last_host_shutdown_ack_count = host_shutdown_ack_peer_ids.size()
	last_host_shutdown_disconnect_count = host_shutdown_disconnected_peer_ids.size()
	reset_host_shutdown_tracking(false)
	close_session_immediately(reason, true)


func accept_test_host_shutdown_ack(peer_id: int, sequence: int) -> bool:
	if not test_mode:
		return false
	return accept_host_shutdown_ack(peer_id, sequence, peer_id)


func advance_test_host_shutdown(delta: float) -> void:
	if test_mode:
		update_host_shutdown(maxf(0.0, delta))


# The normal online-menu leave action takes the acknowledged path on clients.
# Failure callbacks and host-forced removals use distinct reasons and therefore
# still close immediately without attempting a second protocol exchange.

func leave_session(reason: String = "ONLINE SESSION CLOSED") -> void:
	if reason == "ONLINE SESSION CLOSED":
		if (
			mode == MultiplayerSessionModel.MODE_CLIENT
			and request_graceful_leave(reason)
		):
			return
		if (
			mode == MultiplayerSessionModel.MODE_HOST
			and request_graceful_host_shutdown(reason)
		):
			return
	close_session_immediately(reason)

func close_session_immediately(
	reason: String,
	close_peer_before_detach: bool = false
) -> void:
	if session_closing:
		return
	session_closing = true
	snapshot_broadcast_pending = false
	graceful_leave_pending = false
	graceful_leave_timeout_remaining = 0.0
	var closing_peer: MultiplayerPeer = network_peer
	mode = MultiplayerSessionModel.MODE_OFFLINE
	connection_pending = false
	requested_role = MultiplayerSessionModel.ROLE_ALLY
	local_role = MultiplayerSessionModel.ROLE_HOST
	local_peer_id = 1
	peers = {}
	input_sequence = 0
	input_accumulator = 0.0
	snapshot_sequence = 0
	last_snapshot_sequence = -1
	snapshot_accumulator = 0.0
	lobby_open = false
	network_peer = null
	if close_peer_before_detach and closing_peer != null:
		# The server path closes while still attached so replacing MultiplayerAPI
		# cannot be followed by a second send through a zero-channel ENet peer.
		closing_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if not close_peer_before_detach and closing_peer != null:
		# Clients retain the proven detach-first order required for reconnect.
		closing_peer.close()
	reset_host_shutdown_tracking(false)
	restore_runtime_processing()
	set_notice(reason)
	session_closing = false

func multiplayer_runtime_contract_ok() -> bool:
	return (
		super.multiplayer_runtime_contract_ok()
		and SNAPSHOT_WIRE_MAGIC_TEXT.length() == SNAPSHOT_WIRE_MAGIC_BYTES
		and SNAPSHOT_WIRE_DIGEST_BYTES == 32
		and SNAPSHOT_WIRE_HEADER_BYTES == 36
		and MAX_NETWORK_SNAPSHOT_BYTES > SNAPSHOT_WIRE_HEADER_BYTES
		and MAX_NETWORK_SNAPSHOT_BYTES < 1392
		and MAX_DECOMPRESSED_SNAPSHOT_BYTES >= MAX_NETWORK_SNAPSHOT_BYTES
		and NETWORK_SNAPSHOT_COMPRESSION_MODE == FileAccess.COMPRESSION_DEFLATE
		and GRACEFUL_LEAVE_TIMEOUT_SECONDS >= 1.0
		and GRACEFUL_LEAVE_TIMEOUT_SECONDS <= 5.0
		and GRACEFUL_HOST_SHUTDOWN_TIMEOUT_SECONDS >= 1.0
		and GRACEFUL_HOST_SHUTDOWN_TIMEOUT_SECONDS <= 5.0
		and HOST_SHUTDOWN_COMMIT_GRACE_SECONDS >= 0.25
		and HOST_SHUTDOWN_COMMIT_GRACE_SECONDS <= 2.0
		and HOST_SHUTDOWN_DISCONNECT_GRACE_SECONDS >= 0.25
		and HOST_SHUTDOWN_DISCONNECT_GRACE_SECONDS <= 2.0
		and MAX_GRACEFUL_LEAVE_REASON_CHARS >= 32
		and MAX_GRACEFUL_LEAVE_REASON_CHARS <= 128
		and graceful_leave_request_count >= 0
		and graceful_leave_peer_history.size() <= MAX_GRACEFUL_LEAVE_HISTORY
		and host_shutdown_ack_peer_ids.size() <= host_shutdown_expected_peer_ids.size()
		and last_host_shutdown_expected_count >= 0
		and last_host_shutdown_ack_count >= 0
		and last_host_shutdown_ack_count <= last_host_shutdown_expected_count
		and last_host_shutdown_disconnect_count >= 0
		and last_host_shutdown_disconnect_count <= last_host_shutdown_expected_count
		and last_snapshot_wire_bytes >= 0
		and last_snapshot_uncompressed_bytes >= 0
		and not session_closing
	)
