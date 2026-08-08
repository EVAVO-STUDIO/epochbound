extends "res://tools/multiplayer_loopback_peer.gd"

const LOOPBACK_INPUT_RETRY_MSEC := 200
const LOOPBACK_INPUT_SEQUENCE_START := 10000
const INITIAL_EXCHANGE_HOLD_MSEC := 650
const RECONNECT_EXCHANGE_HOLD_MSEC := 450
const RECONNECT_SETTLE_MSEC := 250

var explicit_input_sequence := LOOPBACK_INPUT_SEQUENCE_START
var next_input_retry_msec := 0
var join_logged := false
var snapshot_logged := false
var first_input_logged := false
var join_generation := 0


# The production client normally sends input from its frame-rate accumulator.
# A transport gate must not depend on idle-frame timing, so after each real join
# this driver repeatedly uses the same production RPC surface until host
# authority records a fresh sequence. The ally then uses the production
# graceful-leave protocol and reconnects inside this same Godot process.

func run_client() -> void:
	session.set(
		"local_name",
		"LOOPBACK INVADER"
		if peer_role == MultiplayerSessionModel.ROLE_INVADER
		else "LOOPBACK ALLY"
	)
	if not start_join("LOOPBACK CONNECT STARTED"):
		return
	var first_peer_id := -1
	var first_snapshot_sequence := -1
	var first_input_sequence_sent := -1
	var initial_complete_since_msec := -1
	var reconnect_complete_since_msec := -1
	var graceful_leave_requested := false
	var reconnect_started := false
	var receipt_ready := false
	var pending_receipt: Dictionary = {}
	var deadline_msec := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		var mode := str(session.get("mode"))
		var notice := str(session.get("session_notice"))
		var host_commit_received := bool(session.get("last_host_shutdown_commit_received"))
		if mode == MultiplayerSessionModel.MODE_OFFLINE and not host_commit_received and (
			notice.begins_with("JOIN REJECTED")
			or notice.contains("CONNECTION FAILED")
			or notice.contains("HOST DISCONNECTED")
			or notice.contains("HOST ACK TIMEOUT")
		):
			finish_failure("Loopback %s failed: %s" % [peer_role, notice])
			return
		if mode == MultiplayerSessionModel.MODE_CLIENT:
			log_join_if_needed()
			send_explicit_input_if_due()
		log_snapshot_if_needed()

		var complete_exchange := client_has_complete_exchange()
		if peer_role == MultiplayerSessionModel.ROLE_ALLY:
			if not graceful_leave_requested:
				if complete_exchange:
					if initial_complete_since_msec < 0:
						initial_complete_since_msec = Time.get_ticks_msec()
					if (
						Time.get_ticks_msec() - initial_complete_since_msec
						>= INITIAL_EXCHANGE_HOLD_MSEC
						and explicit_input_sequence >= LOOPBACK_INPUT_SEQUENCE_START + 3
					):
						first_peer_id = int(session.get("local_peer_id"))
						first_snapshot_sequence = int(session.get("last_snapshot_sequence"))
						first_input_sequence_sent = explicit_input_sequence
						if not bool(session.call("request_graceful_leave", "LOOPBACK ALLY RECONNECT")):
							finish_failure("Loopback ally could not request a graceful leave.")
							return
						graceful_leave_requested = true
						print(
							"LOOPBACK GRACEFUL LEAVE REQUESTED: ally peer %d sequence %d" % [
								first_peer_id,
								int(session.get("graceful_leave_sequence"))
							]
						)
				else:
					initial_complete_since_msec = -1
			elif not reconnect_started:
				if (
					mode == MultiplayerSessionModel.MODE_OFFLINE
					and int(session.get("last_graceful_leave_ack_sequence")) > 0
				):
					print(
						"LOOPBACK GRACEFUL LEAVE ACKNOWLEDGED: sequence %d" %
						int(session.get("last_graceful_leave_ack_sequence"))
					)
					await create_timer(float(RECONNECT_SETTLE_MSEC) / 1000.0).timeout
					join_generation = 1
					join_logged = false
					snapshot_logged = false
					first_input_logged = false
					next_input_retry_msec = 0
					if not start_join("LOOPBACK RECONNECT STARTED"):
						return
					reconnect_started = true
			elif complete_exchange and not receipt_ready:
				if reconnect_complete_since_msec < 0:
					reconnect_complete_since_msec = Time.get_ticks_msec()
				if (
					Time.get_ticks_msec() - reconnect_complete_since_msec
					>= RECONNECT_EXCHANGE_HOLD_MSEC
					and explicit_input_sequence > first_input_sequence_sent
				):
					pending_receipt = client_receipt()
					pending_receipt["same_process_reconnect"] = true
					pending_receipt["first_peer_id"] = first_peer_id
					pending_receipt["first_snapshot_sequence"] = first_snapshot_sequence
					pending_receipt["first_input_sequence_sent"] = first_input_sequence_sent
					pending_receipt["graceful_leave_ack_sequence"] = int(session.get("last_graceful_leave_ack_sequence"))
					pending_receipt["reconnect_generation"] = join_generation
					receipt_ready = true
					print("LOOPBACK CLIENT READY FOR HOST SHUTDOWN: ally")
			else:
				reconnect_complete_since_msec = -1
		elif complete_exchange and not receipt_ready:
			pending_receipt = client_receipt()
			receipt_ready = true
			print("LOOPBACK CLIENT READY FOR HOST SHUTDOWN: invader")

		if (
			receipt_ready
			and mode == MultiplayerSessionModel.MODE_OFFLINE
			and host_commit_received
		):
			pending_receipt["host_shutdown_sequence"] = int(session.get("last_host_shutdown_sequence"))
			pending_receipt["host_shutdown_ack_sent_sequence"] = int(session.get("last_host_shutdown_ack_sent_sequence"))
			pending_receipt["host_shutdown_commit_received"] = true
			pending_receipt["host_shutdown_reason"] = str(session.get("last_host_shutdown_reason"))
			pending_receipt["final_mode"] = mode
			pending_receipt["independent_exit"] = true
			if (
				int(pending_receipt.get("host_shutdown_sequence", -1)) <= 0
				or int(pending_receipt.get("host_shutdown_ack_sent_sequence", -1))
				!= int(pending_receipt.get("host_shutdown_sequence", -1))
			):
				finish_failure("Loopback client did not preserve the acknowledged host-shutdown sequence.")
				return
			if not write_json(receipt_path, pending_receipt):
				finish_failure("Loopback %s could not write its host-shutdown receipt." % peer_role)
				return
			print(
				"LOOPBACK HOST SHUTDOWN COMMIT RECEIVED: %s sequence %d" % [
					peer_role,
					int(pending_receipt.get("host_shutdown_sequence", -1))
				]
			)
			await finish_success()
			return
		await create_timer(0.05).timeout
	finish_failure(
		"Loopback %s timed out: mode=%s peer=%d snapshot=%d input_sequence=%d ack=%d host_shutdown=%d commit=%s reconnect=%s notice=%s" % [
			peer_role,
			str(session.get("mode")),
			int(session.get("local_peer_id")),
			int(session.get("last_snapshot_sequence")),
			explicit_input_sequence,
			int(session.get("last_graceful_leave_ack_sequence")),
			int(session.get("last_host_shutdown_sequence")),
			str(session.get("last_host_shutdown_commit_received")),
			str(reconnect_started),
			str(session.get("session_notice"))
		]
	)

func start_join(log_prefix: String) -> bool:
	if not bool(session.call("join_session", HOST_ADDRESS, peer_role, port)):
		finish_failure(
			"Loopback %s could not start ENet connection: %s" % [
				peer_role,
				str(session.get("session_notice"))
			]
		)
		return false
	print("%s: %s -> %s:%d" % [log_prefix, peer_role, HOST_ADDRESS, port])
	return true


func log_join_if_needed() -> void:
	if join_logged:
		return
	join_logged = true
	print(
		"%s: %s peer %d" % [
			"LOOPBACK REJOIN ACCEPTED"
			if join_generation > 0
			else "LOOPBACK JOIN ACCEPTED",
			peer_role,
			int(session.get("local_peer_id"))
		]
	)


func log_snapshot_if_needed() -> void:
	if int(session.get("last_snapshot_sequence")) < 0 or snapshot_logged:
		return
	snapshot_logged = true
	print(
		"%s: %s sequence %d" % [
			"LOOPBACK RECONNECT SNAPSHOT RECEIVED"
			if join_generation > 0
			else "LOOPBACK SNAPSHOT RECEIVED",
			peer_role,
			int(session.get("last_snapshot_sequence"))
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
			"%s: %s sequence %d" % [
				"LOOPBACK RECONNECT INPUT SENT"
				if join_generation > 0
				else "LOOPBACK INPUT SENT",
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
