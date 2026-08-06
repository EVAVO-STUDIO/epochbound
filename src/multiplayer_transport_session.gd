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


func _process(delta: float) -> void:
	super._process(delta)
	if not graceful_leave_pending:
		return
	graceful_leave_timeout_remaining = maxf(
		0.0,
		graceful_leave_timeout_remaining - delta
	)
	if graceful_leave_timeout_remaining <= 0.0:
		graceful_leave_pending = false
		close_session_immediately("ONLINE SESSION CLOSED — HOST ACK TIMEOUT")


func host_session(port: int = -1) -> bool:
	graceful_leave_request_count = 0
	last_graceful_leave_peer_id = -1
	graceful_leave_peer_history.clear()
	return super.host_session(port)


func update_client_prediction_and_input(delta: float) -> void:
	if graceful_leave_pending:
		return
	super.update_client_prediction_and_input(delta)


# Join negotiation and the simulation tick both request snapshots through the
# inherited method name. Defer the actual send so a reliable join acceptance is
# queued first and so multiple requests in one frame collapse into one packet.
func broadcast_world_snapshot() -> void:
	if (
		mode != MultiplayerSessionModel.MODE_HOST
		or test_mode
		or snapshot_broadcast_pending
		or session_closing
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
	):
		return
	var snapshot: Dictionary = decode_world_snapshot(payload)
	if not snapshot.is_empty():
		apply_world_snapshot(snapshot)


# Runtime entities store authored cardinal facing names. Keep that contract on
# the wire instead of coercing them into Vector2 values that the inherited draw
# path would later attempt to pass through a String constructor.
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


# The normal online-menu leave action takes the acknowledged path on clients.
# Failure callbacks and host-forced removals use distinct reasons and therefore
# still close immediately without attempting a second protocol exchange.
func leave_session(reason: String = "ONLINE SESSION CLOSED") -> void:
	if (
		reason == "ONLINE SESSION CLOSED"
		and mode == MultiplayerSessionModel.MODE_CLIENT
		and request_graceful_leave(reason)
	):
		return
	close_session_immediately(reason)


# Detach the high-level MultiplayerAPI before closing the old ENet peer. The
# guard absorbs synchronous and deferred disconnect signals caused by the
# replacement. A completed graceful leave preserves its acknowledgement number
# so the same process can prove that a later join is a genuine reconnect.
func close_session_immediately(reason: String) -> void:
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
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if closing_peer != null:
		closing_peer.close()
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
		and MAX_GRACEFUL_LEAVE_REASON_CHARS >= 32
		and MAX_GRACEFUL_LEAVE_REASON_CHARS <= 128
		and graceful_leave_request_count >= 0
		and graceful_leave_peer_history.size() <= MAX_GRACEFUL_LEAVE_HISTORY
		and last_snapshot_wire_bytes >= 0
		and last_snapshot_uncompressed_bytes >= 0
		and not session_closing
	)