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
			"object_id": str(entity.get("object_id", "")),
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
