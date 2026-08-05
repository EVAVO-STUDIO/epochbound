extends "res://tools/multiplayer_loopback_peer.gd"

const LOOPBACK_INPUT_RETRY_MSEC := 200
const LOOPBACK_INPUT_SEQUENCE_START := 10000

var explicit_input_sequence := LOOPBACK_INPUT_SEQUENCE_START
var next_input_retry_msec := 0
var join_logged := false
var snapshot_logged := false
var first_input_logged := false


# The production client normally sends input from its frame-rate accumulator.
# A transport gate must not depend on idle-frame timing, so after the real join
# is accepted this driver repeatedly uses the same production RPC surface until
# host authority records a fresh sequence. No peer or state is registered here.
func run_client() -> void:
	session.set(
		"local_name",
		"LOOPBACK INVADER"
		if peer_role == MultiplayerSessionModel.ROLE_INVADER
		else "LOOPBACK ALLY"
	)
	if not bool(session.call("join_session", HOST_ADDRESS, peer_role, port)):
		finish_failure(
			"Loopback %s could not start ENet connection: %s" % [
				peer_role,
				str(session.get("session_notice"))
			]
		)
		return
	print("LOOPBACK CONNECT STARTED: %s -> %s:%d" % [peer_role, HOST_ADDRESS, port])
	var deadline_msec: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		var mode: String = str(session.get("mode"))
		var notice: String = str(session.get("session_notice"))
		if mode == MultiplayerSessionModel.MODE_OFFLINE and (
			notice.begins_with("JOIN REJECTED")
			or notice.contains("CONNECTION FAILED")
			or notice.contains("HOST DISCONNECTED")
		):
			finish_failure("Loopback %s failed: %s" % [peer_role, notice])
			return
		if mode == MultiplayerSessionModel.MODE_CLIENT:
			if not join_logged:
				join_logged = true
				print(
					"LOOPBACK JOIN ACCEPTED: %s peer %d" % [
						peer_role,
						int(session.get("local_peer_id"))
					]
				)
			send_explicit_input_if_due()
		if int(session.get("last_snapshot_sequence")) >= 0 and not snapshot_logged:
			snapshot_logged = true
			print(
				"LOOPBACK SNAPSHOT RECEIVED: %s sequence %d" % [
					peer_role,
					int(session.get("last_snapshot_sequence"))
				]
			)
		if client_has_complete_exchange():
			var receipt: Dictionary = client_receipt()
			if not write_json(receipt_path, receipt):
				finish_failure(
					"Loopback %s could not write its validation receipt." % peer_role
				)
				return
			await hold_after_receipt()
			return
		await create_timer(0.05).timeout
	finish_failure(
		"Loopback %s timed out: mode=%s peer=%d snapshot=%d input_sequence=%d notice=%s" % [
			peer_role,
			str(session.get("mode")),
			int(session.get("local_peer_id")),
			int(session.get("last_snapshot_sequence")),
			explicit_input_sequence,
			str(session.get("session_notice"))
		]
	)


func send_explicit_input_if_due() -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec < next_input_retry_msec:
		return
	next_input_retry_msec = now_msec + LOOPBACK_INPUT_RETRY_MSEC
	explicit_input_sequence += 1
	session.rpc_id(
		1,
		"_submit_input",
		explicit_input_sequence,
		{
			"direction": {"x": 0.0, "y": 0.0},
			"attack": false
		}
	)
	if not first_input_logged:
		first_input_logged = true
		print(
			"LOOPBACK INPUT SENT: %s sequence %d" % [
				peer_role,
				explicit_input_sequence
			]
		)


func client_receipt() -> Dictionary:
	var peers_value: Variant = session.get("peers")
	var peers: Dictionary = (
		peers_value if typeof(peers_value) == TYPE_DICTIONARY else {}
	)
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	var local_peer_id: int = int(session.get("local_peer_id"))
	var local_value: Variant = peers.get(local_peer_id, {})
	var local_peer: Dictionary = (
		local_value if typeof(local_value) == TYPE_DICTIONARY else {}
	)
	return {
		"ok": true,
		"role": peer_role,
		"port": port,
		"local_peer_id": local_peer_id,
		"local_role": str(local_peer.get("role", "")),
		"peer_count": peers.size(),
		"snapshot_sequence": int(session.get("last_snapshot_sequence")),
		"input_sequence_sent": explicit_input_sequence,
		"map_id": str(map_data.get("id", "")),
		"era_id": str(runtime.get("current_era_id"))
	}


# Receipt publication is atomic so the parent never observes a partially
# written success or failure record.
func write_json(path: String, payload: Dictionary) -> bool:
	if path.is_empty():
		return false
	var directory: String = path.get_base_dir()
	if not directory.is_empty():
		var directory_error: int = DirAccess.make_dir_recursive_absolute(directory)
		if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
			return false
	var temporary_path := path + ".tmp"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t", true) + "\n")
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(path)
		if remove_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return false
	return DirAccess.rename_absolute(temporary_path, path) == OK
