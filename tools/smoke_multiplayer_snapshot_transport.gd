extends SceneTree

const MultiplayerSessionModel = preload("res://src/game/multiplayer_session_model.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const MAX_WIRE_BYTES := 1200
const SNAPSHOT_CASES := [
	{
		"map_id": "bellweather_crossing",
		"era_id": "verdant",
		"position": Vector2(344, 220),
		"invader": false
	},
	{
		"map_id": "bellweather_crossing",
		"era_id": "ashen",
		"position": Vector2(344, 220),
		"invader": false
	},
	{
		"map_id": "clockwood_edge",
		"era_id": "verdant",
		"position": Vector2(112, 248),
		"invader": false
	},
	{
		"map_id": "clockwood_edge",
		"era_id": "ashen",
		"position": Vector2(360, 240),
		"invader": true
	},
	{
		"map_id": "museum_underworks",
		"era_id": "verdant",
		"position": Vector2(136, 238),
		"invader": false
	},
	{
		"map_id": "museum_underworks",
		"era_id": "ashen",
		"position": Vector2(136, 238),
		"invader": false
	}
]

var failures: Array[String] = []
var maximum_wire_bytes := 0
var maximum_uncompressed_bytes := 0
var maximum_context := ""


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var runtime: Node = await instantiate_runtime()
	if runtime == null:
		finish()
		return
	var session: Node = runtime.get_node_or_null("MultiplayerSession")
	check(session != null, "Snapshot transport matrix requires MultiplayerSession.")
	if session == null:
		await cleanup(runtime)
		finish()
		return

	runtime.call("change_flow", 4)
	for case_value in SNAPSHOT_CASES:
		if typeof(case_value) != TYPE_DICTIONARY:
			continue
		var case_data: Dictionary = case_value
		await validate_snapshot_case(runtime, session, case_data)

	validate_payload_rejection(session)
	await cleanup(runtime)
	finish()


func validate_snapshot_case(
	runtime: Node,
	session: Node,
	case_data: Dictionary
) -> void:
	var map_id := str(case_data.get("map_id", ""))
	var era_id := str(case_data.get("era_id", ""))
	var context := "%s/%s" % [map_id, era_id]
	check(
		bool(runtime.call("activate_map", map_id, "", era_id, false)),
		"Snapshot transport matrix must activate %s." % context
	)
	var position_value: Variant = case_data.get("position", Vector2.ZERO)
	var position: Vector2 = (
		position_value if position_value is Vector2 else Vector2.ZERO
	)
	runtime.set("player", position)
	runtime.set("facing", Vector2.RIGHT)
	runtime.set("companion", position + Vector2(-18, 20))
	check(
		bool(session.call("configure_test_host_session")),
		"Snapshot transport matrix must configure host authority for %s." % context
	)
	check(
		bool(
			(session.call(
				"register_test_peer",
				2,
				MultiplayerSessionModel.ROLE_ALLY
			) as Dictionary).get("ok", false)
		),
		"Snapshot transport matrix must register the first ally for %s." % context
	)
	check(
		bool(
			(session.call(
				"register_test_peer",
				3,
				MultiplayerSessionModel.ROLE_ALLY
			) as Dictionary).get("ok", false)
		),
		"Snapshot transport matrix must register the second ally for %s." % context
	)
	if bool(case_data.get("invader", false)):
		check(
			bool(
				(session.call(
					"register_test_peer",
					4,
					MultiplayerSessionModel.ROLE_INVADER
				) as Dictionary).get("ok", false)
			),
			"Snapshot transport matrix must register the invader for %s." % context
		)

	var snapshot_value: Variant = session.call("build_world_snapshot")
	var snapshot: Dictionary = (
		snapshot_value if typeof(snapshot_value) == TYPE_DICTIONARY else {}
	)
	check(not snapshot.is_empty(), "Snapshot transport matrix must build %s." % context)
	var payload_value: Variant = session.call("encode_world_snapshot", snapshot)
	var payload: PackedByteArray = (
		payload_value if payload_value is PackedByteArray else PackedByteArray()
	)
	var wire_bytes := payload.size()
	var uncompressed_bytes := int(session.get("last_snapshot_uncompressed_bytes"))
	check(wire_bytes > 0, "Snapshot transport payload must not be empty for %s." % context)
	check(
		wire_bytes <= MAX_WIRE_BYTES,
		"Snapshot transport payload for %s must remain inside the 1,200-byte wire budget." % context
	)
	check(
		uncompressed_bytes > wire_bytes,
		"Snapshot transport payload for %s must prove bounded compression." % context
	)
	var decoded_value: Variant = session.call("decode_world_snapshot", payload)
	var decoded: Dictionary = (
		decoded_value if typeof(decoded_value) == TYPE_DICTIONARY else {}
	)
	check(not decoded.is_empty(), "Snapshot transport payload must decode for %s." % context)
	check(
		int(decoded.get("protocol_version", 0)) == 1,
		"Decoded snapshot must retain protocol version for %s." % context
	)
	check(
		str(decoded.get("map_id", "")) == map_id
		and str(decoded.get("era_id", "")) == era_id,
		"Decoded snapshot must retain map and era for %s." % context
	)
	var expected_peer_count := 4 if bool(case_data.get("invader", false)) else 3
	var decoded_peers_value: Variant = decoded.get("peers", [])
	var decoded_peers: Array = (
		decoded_peers_value
		if typeof(decoded_peers_value) == TYPE_ARRAY
		else []
	)
	check(
		decoded_peers.size() == expected_peer_count,
		"Decoded snapshot must retain the maximum allowed party for %s." % context
	)
	if wire_bytes > maximum_wire_bytes:
		maximum_wire_bytes = wire_bytes
		maximum_uncompressed_bytes = uncompressed_bytes
		maximum_context = context
	print(
		"Snapshot transport %s: %d -> %d bytes (%d peers)." % [
			context,
			uncompressed_bytes,
			wire_bytes,
			expected_peer_count
		]
	)
	await process_frame


func validate_payload_rejection(session: Node) -> void:
	var oversized := PackedByteArray()
	oversized.resize(MAX_WIRE_BYTES + 1)
	check(
		(session.call("decode_world_snapshot", oversized) as Dictionary).is_empty(),
		"Snapshot transport must reject payloads above 1,200 bytes before decompression."
	)
	var wrong_magic := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	check(
		(session.call("decode_world_snapshot", wrong_magic) as Dictionary).is_empty(),
		"Snapshot transport must reject malformed wire headers before decompression."
	)
	var valid_value: Variant = session.call(
		"encode_world_snapshot",
		{"protocol_version": 1, "sequence": 7, "marker": "checksum"}
	)
	var tampered: PackedByteArray = (
		(valid_value as PackedByteArray).duplicate()
		if valid_value is PackedByteArray
		else PackedByteArray()
	)
	check(not tampered.is_empty(), "Snapshot transport checksum setup must encode.")
	if not tampered.is_empty():
		tampered[tampered.size() - 1] = int(tampered[tampered.size() - 1]) ^ 0x01
		check(
			(session.call("decode_world_snapshot", tampered) as Dictionary).is_empty(),
			"Snapshot transport must reject checksum mismatches before decompression."
		)
	var incompressible := deterministic_noise(8192)
	var rejected_value: Variant = session.call(
		"encode_world_snapshot",
		{"padding": incompressible}
	)
	var rejected: PackedByteArray = (
		rejected_value
		if rejected_value is PackedByteArray
		else PackedByteArray()
	)
	check(
		rejected.is_empty(),
		"Snapshot transport must fail closed when compressed state exceeds its wire budget."
	)


func deterministic_noise(size: int) -> PackedByteArray:
	var output := PackedByteArray()
	output.resize(maxi(0, size))
	var state: int = 0x13579BDF
	for index in range(output.size()):
		state = state ^ ((state << 13) & 0x7fffffff)
		state = state ^ (state >> 17)
		state = state ^ ((state << 5) & 0x7fffffff)
		state = state & 0x7fffffff
		output[index] = state & 0xff
	return output


func instantiate_runtime() -> Node:
	var packed: Resource = ResourceLoader.load(
		RUNTIME_SCENE,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	check(packed is PackedScene, "Snapshot transport runtime scene must load.")
	if not packed is PackedScene:
		return null
	var runtime: Node = (packed as PackedScene).instantiate()
	check(runtime != null, "Snapshot transport runtime scene must instantiate.")
	if runtime == null:
		return null
	root.add_child(runtime)
	await process_frame
	return runtime


func cleanup(runtime: Node) -> void:
	if runtime == null:
		return
	runtime.queue_free()
	await process_frame
	await process_frame


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print(
			"Multiplayer snapshot transport matrix passed: all six reference map/era states and maximum authored parties fit the 1,200-byte wire budget; largest %s was %d -> %d bytes." % [
				maximum_context,
				maximum_uncompressed_bytes,
				maximum_wire_bytes
			]
		)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
