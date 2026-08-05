extends "res://src/multiplayer_session.gd"

const NETWORK_SNAPSHOT_COMPRESSION_MODE := FileAccess.COMPRESSION_DEFLATE
const MAX_NETWORK_SNAPSHOT_BYTES := 1200
const MAX_DECOMPRESSED_SNAPSHOT_BYTES := 65536

var snapshot_broadcast_pending := false
var last_snapshot_wire_bytes := 0
var last_snapshot_uncompressed_bytes := 0


# Join negotiation and the simulation tick both request snapshots through the
# inherited method name. Defer the actual send so a reliable join acceptance is
# queued first and so multiple requests in one frame collapse into one packet.
func broadcast_world_snapshot() -> void:
	if (
		mode != MultiplayerSessionModel.MODE_HOST
		or test_mode
		or snapshot_broadcast_pending
	):
		return
	snapshot_broadcast_pending = true
	call_deferred("broadcast_world_snapshot_wire")


func broadcast_world_snapshot_wire() -> void:
	snapshot_broadcast_pending = false
	if (
		mode != MultiplayerSessionModel.MODE_HOST
		or test_mode
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
	last_snapshot_wire_bytes = compressed.size()
	if (
		compressed.is_empty()
		or compressed.size() > MAX_NETWORK_SNAPSHOT_BYTES
	):
		return PackedByteArray()
	return compressed


func decode_world_snapshot(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty() or payload.size() > MAX_NETWORK_SNAPSHOT_BYTES:
		return {}
	var serialized: PackedByteArray = payload.decompress_dynamic(
		MAX_DECOMPRESSED_SNAPSHOT_BYTES,
		NETWORK_SNAPSHOT_COMPRESSION_MODE
	)
	if serialized.is_empty():
		return {}
	var decoded: Variant = bytes_to_var(serialized)
	return decoded as Dictionary if typeof(decoded) == TYPE_DICTIONARY else {}


@rpc("authority", "call_remote", "unreliable_ordered", SNAPSHOT_CHANNEL)
func _receive_snapshot_wire(payload: PackedByteArray) -> void:
	if mode != MultiplayerSessionModel.MODE_CLIENT:
		return
	var snapshot: Dictionary = decode_world_snapshot(payload)
	if not snapshot.is_empty():
		apply_world_snapshot(snapshot)


func multiplayer_runtime_contract_ok() -> bool:
	return (
		super.multiplayer_runtime_contract_ok()
		and MAX_NETWORK_SNAPSHOT_BYTES > 0
		and MAX_NETWORK_SNAPSHOT_BYTES < 1392
		and MAX_DECOMPRESSED_SNAPSHOT_BYTES >= MAX_NETWORK_SNAPSHOT_BYTES
		and NETWORK_SNAPSHOT_COMPRESSION_MODE == FileAccess.COMPRESSION_DEFLATE
		and last_snapshot_wire_bytes >= 0
		and last_snapshot_uncompressed_bytes >= 0
	)
