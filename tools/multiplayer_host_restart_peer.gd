extends "res://tools/multiplayer_loopback_peer.gd"

const RESTART_INPUT_RETRY_MSEC := 180
const RESTART_INPUT_SEQUENCE_START := 20000
const INITIAL_EXCHANGE_HOLD_MSEC := 550
const RECOVERED_EXCHANGE_HOLD_MSEC := 650
const RESTART_HOST_SHUTDOWN_EXCHANGE_HOLD_MSEC := 800

var host_generation := 0
var exchange_path := ""
var initial_path := ""
var recovery_path := ""
var standby_path := ""
var activation_path := ""
var explicit_input_sequence := RESTART_INPUT_SEQUENCE_START
var next_input_retry_msec := 0
var initial_join_call_count := 0


func parse_arguments() -> bool:
	if not super.parse_arguments():
		return false
	for value in OS.get_cmdline_user_args():
		var argument := str(value)
		if argument.begins_with("--generation="):
			var generation_text := argument.trim_prefix("--generation=").strip_edges()
			if not generation_text.is_valid_int():
				failure_message = "Host-restart generation must be an integer."
				return false
			host_generation = int(generation_text)
		elif argument.begins_with("--exchange="):
			exchange_path = argument.trim_prefix("--exchange=").strip_edges()
		elif argument.begins_with("--initial="):
			initial_path = argument.trim_prefix("--initial=").strip_edges()
		elif argument.begins_with("--recovery="):
			recovery_path = argument.trim_prefix("--recovery=").strip_edges()
		elif argument.begins_with("--standby="):
			standby_path = argument.trim_prefix("--standby=").strip_edges()
		elif argument.begins_with("--activation="):
			activation_path = argument.trim_prefix("--activation=").strip_edges()
	if peer_role == MultiplayerSessionModel.ROLE_HOST:
		if host_generation not in [1, 2]:
			failure_message = "Host-restart host generation must be 1 or 2."
			return false
		if exchange_path.is_empty():
			failure_message = "Host-restart host requires an exchange-marker path."
			return false
		if host_generation == 2 and (standby_path.is_empty() or activation_path.is_empty()):
			failure_message = "Replacement host requires standby and activation marker paths."
			return false
	elif peer_role == MultiplayerSessionModel.ROLE_ALLY:
		if initial_path.is_empty() or recovery_path.is_empty():
			failure_message = "Host-restart ally requires initial and recovery marker paths."
			return false
	else:
		failure_message = "Host-restart recovery gate supports only host and ally roles."
		return false
	return true


func run_host() -> void:
	runtime.call("change_flow", 4)
	if not bool(runtime.call(
		"activate_map",
		HOST_MAP,
		HOST_ENTRY,
		HOST_ERA,
		false
	)):
		finish_failure("Host-restart host could not activate the authored PvP map and era.")
		return
	runtime.set("player", HOST_POSITION)
	runtime.set("facing", Vector2.RIGHT)
	runtime.set("companion", HOST_POSITION + Vector2(-18, 20))
	session.set("local_name", "RESTART HOST %d" % host_generation)
	if host_generation == 2:
		if not await wait_for_replacement_activation():
			return
	if not bool(session.call("host_session", port)):
		finish_failure(
			"Host-restart generation %d could not open ENet on UDP %d: %s" % [
				host_generation,
				port,
				str(session.get("session_notice"))
			]
		)
		return
	if not write_json(ready_path, {
		"ok": true,
		"role": MultiplayerSessionModel.ROLE_HOST,
		"generation": host_generation,
		"port": port,
		"area_id": EXPECTED_AREA
	}):
		finish_failure("Host-restart host could not publish its ready marker.")
		return
	print("HOST RESTART HOST READY: generation %d UDP %d" % [host_generation, port])
	if host_generation == 1:
		await run_original_host_until_forced_loss()
	else:
		await run_replacement_host()


func wait_for_replacement_activation() -> bool:
	if not write_json(standby_path, {
		"ok": true,
		"role": MultiplayerSessionModel.ROLE_HOST,
		"generation": host_generation,
		"port": port,
		"transport_bound": false
	}):
		finish_failure("Replacement host could not publish its standby marker.")
		return false
	print(
		"HOST RESTART REPLACEMENT STANDBY: generation %d UDP %d (not bound)" % [
			host_generation,
			port
		]
	)
	var deadline_msec := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		if FileAccess.file_exists(activation_path):
			print(
				"HOST RESTART REPLACEMENT ACTIVATED: generation %d UDP %d" % [
					host_generation,
					port
				]
			)
			return true
		await create_timer(0.05).timeout
	finish_failure("Replacement host timed out before its activation marker appeared.")
	return false


func run_original_host_until_forced_loss() -> void:
	var complete_since_msec := -1
	var deadline_msec := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		var peers := peer_dictionary()
		if host_has_single_ally_exchange(peers):
			if complete_since_msec < 0:
				complete_since_msec = Time.get_ticks_msec()
			if (
				Time.get_ticks_msec() - complete_since_msec
				>= INITIAL_EXCHANGE_HOLD_MSEC
			):
				var ally_id := peer_id_for_role(
					peers,
					MultiplayerSessionModel.ROLE_ALLY
				)
				var ally := peers.get(ally_id, {}) as Dictionary
				if not write_json(exchange_path, {
					"ok": true,
					"generation": 1,
					"ally_peer_id": ally_id,
					"ally_input_sequence": int(ally.get("last_sequence", -1)),
					"port": port
				}):
					finish_failure("Original host could not publish initial exchange evidence.")
					return
				print(
					"HOST RESTART INITIAL EXCHANGE: generation 1 ally %d input %d" % [
						ally_id,
						int(ally.get("last_sequence", -1))
					]
				)
				# The parent harness must now terminate this process without invoking
				# any graceful shutdown surface. A normal exit is a gate failure.
				while true:
					await create_timer(0.1).timeout
		else:
			complete_since_msec = -1
		await create_timer(0.05).timeout
	finish_failure("Original host timed out before the initial authoritative exchange.")


func run_replacement_host() -> void:
	var complete_since_msec := -1
	var shutdown_started := false
	var receipt: Dictionary = {}
	var deadline_msec := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		var peers := peer_dictionary()
		if not shutdown_started and host_has_single_ally_exchange(peers):
			if complete_since_msec < 0:
				complete_since_msec = Time.get_ticks_msec()
			if (
				Time.get_ticks_msec() - complete_since_msec
				>= RESTART_HOST_SHUTDOWN_EXCHANGE_HOLD_MSEC
			):
				var ally_id := peer_id_for_role(
					peers,
					MultiplayerSessionModel.ROLE_ALLY
				)
				var ally := peers.get(ally_id, {}) as Dictionary
				var snapshot_value: Variant = session.call("build_world_snapshot")
				var snapshot := (
					snapshot_value as Dictionary
					if typeof(snapshot_value) == TYPE_DICTIONARY
					else {}
				)
				var payload_value: Variant = session.call(
					"encode_world_snapshot",
					snapshot
				)
				var payload := (
					payload_value as PackedByteArray
					if payload_value is PackedByteArray
					else PackedByteArray()
				)
				if payload.is_empty():
					finish_failure("Replacement host could not encode a bounded snapshot.")
					return
				receipt = {
					"ok": true,
					"role": MultiplayerSessionModel.ROLE_HOST,
					"generation": 2,
					"port": port,
					"peer_count": peers.size(),
					"ally_peer_id": ally_id,
					"ally_input_sequence": int(ally.get("last_sequence", -1)),
					"snapshot_sequence": int(snapshot.get("sequence", -1)),
					"snapshot_wire_bytes": payload.size(),
					"snapshot_uncompressed_bytes": int(session.get("last_snapshot_uncompressed_bytes")),
					"map_id": str(snapshot.get("map_id", "")),
					"era_id": str(snapshot.get("era_id", "")),
					"area_id": EXPECTED_AREA
				}
				if not write_json(exchange_path, receipt):
					finish_failure("Replacement host could not publish recovered exchange evidence.")
					return
				print(
					"HOST RESTART RECOVERED EXCHANGE: generation 2 ally %d input %d" % [
						ally_id,
						int(ally.get("last_sequence", -1))
					]
				)
				if not bool(session.call(
					"request_graceful_host_shutdown",
					"HOST RESTART RECOVERY COMPLETE"
				)):
					finish_failure("Replacement host could not start acknowledged shutdown.")
					return
				shutdown_started = true
		elif not shutdown_started:
			complete_since_msec = -1
		if shutdown_started and str(session.get("mode")) == MultiplayerSessionModel.MODE_OFFLINE:
			receipt["host_shutdown_sequence"] = int(session.get("last_host_shutdown_sequence"))
			receipt["host_shutdown_expected_count"] = int(session.get("last_host_shutdown_expected_count"))
			receipt["host_shutdown_ack_count"] = int(session.get("last_host_shutdown_ack_count"))
			receipt["host_shutdown_disconnect_count"] = int(session.get("last_host_shutdown_disconnect_count"))
			receipt["host_shutdown_forced"] = bool(session.get("last_host_shutdown_forced"))
			receipt["host_shutdown_reason"] = str(session.get("last_host_shutdown_reason"))
			receipt["final_mode"] = str(session.get("mode"))
			receipt["independent_exit"] = true
			if (
				int(receipt.get("host_shutdown_expected_count", 0)) != 1
				or int(receipt.get("host_shutdown_ack_count", 0)) != 1
				or int(receipt.get("host_shutdown_disconnect_count", 0)) != 1
				or bool(receipt.get("host_shutdown_forced", true))
			):
				finish_failure("Replacement host shutdown did not receive the recovered ally acknowledgement.")
				return
			if not write_json(receipt_path, receipt):
				finish_failure("Replacement host could not write its final receipt.")
				return
			print(
				"HOST RESTART HOST SHUTDOWN COMPLETE: sequence %d acknowledgements %d" % [
					int(receipt.get("host_shutdown_sequence", -1)),
					int(receipt.get("host_shutdown_ack_count", 0))
				]
			)
			await finish_success()
			return
		await create_timer(0.05).timeout
	finish_failure("Replacement host timed out before recovered exchange and acknowledged shutdown completed.")


func run_client() -> void:
	session.set("local_name", "HOST RESTART ALLY")
	initial_join_call_count += 1
	if not bool(session.call(
		"join_session",
		HOST_ADDRESS,
		MultiplayerSessionModel.ROLE_ALLY,
		port
	)):
		finish_failure(
			"Host-restart ally could not start its one explicit connection: %s" %
			str(session.get("session_notice"))
		)
		return
	print("HOST RESTART CLIENT CONNECT STARTED: ally -> %s:%d" % [HOST_ADDRESS, port])
	var first_peer_id := -1
	var first_snapshot_sequence := -1
	var first_input_sequence := -1
	var initial_complete_since_msec := -1
	var recovered_complete_since_msec := -1
	var initial_marker_written := false
	var recovery_marker_written := false
	var recovered_receipt_ready := false
	var pending_receipt: Dictionary = {}
	var deadline_msec := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		var mode := str(session.get("mode"))
		var recovery_pending := bool(session.get("host_restart_recovery_pending"))
		var recovered := bool(session.get("last_host_restart_recovered"))
		var host_commit_received := bool(session.get("last_host_shutdown_commit_received"))
		if bool(session.get("last_host_restart_exhausted")):
			finish_failure(
				"Host-restart ally exhausted its bounded recovery budget: %s" %
				str(session.get("last_host_restart_reason"))
			)
			return
		if mode == MultiplayerSessionModel.MODE_CLIENT:
			send_explicit_input_if_due()
		if not initial_marker_written and client_has_single_ally_exchange():
			if initial_complete_since_msec < 0:
				initial_complete_since_msec = Time.get_ticks_msec()
			if (
				Time.get_ticks_msec() - initial_complete_since_msec
				>= INITIAL_EXCHANGE_HOLD_MSEC
				and explicit_input_sequence >= RESTART_INPUT_SEQUENCE_START + 3
			):
				first_peer_id = int(session.get("local_peer_id"))
				first_snapshot_sequence = int(session.get("last_snapshot_sequence"))
				first_input_sequence = explicit_input_sequence
				if not write_json(initial_path, {
					"ok": true,
					"explicit_join_calls": initial_join_call_count,
					"first_peer_id": first_peer_id,
					"first_snapshot_sequence": first_snapshot_sequence,
					"first_input_sequence": first_input_sequence,
					"port": port
				}):
					finish_failure("Host-restart ally could not publish initial exchange evidence.")
					return
				initial_marker_written = true
				print(
					"HOST RESTART CLIENT INITIAL EXCHANGE: peer %d snapshot %d input %d" % [
						first_peer_id,
						first_snapshot_sequence,
						first_input_sequence
					]
				)
		elif not initial_marker_written:
			initial_complete_since_msec = -1
		if initial_marker_written and recovery_pending and not recovery_marker_written:
			if not write_json(recovery_path, {
				"ok": true,
				"explicit_join_calls": initial_join_call_count,
				"address": str(session.get("last_host_restart_address")),
				"port": int(session.get("last_host_restart_port")),
				"role": str(session.get("last_host_restart_role")),
				"attempt_count": int(session.get("host_restart_attempt_count"))
			}):
				finish_failure("Host-restart ally could not publish pending recovery evidence.")
				return
			recovery_marker_written = true
			print("HOST RESTART CLIENT RECOVERY PENDING: endpoint %s:%d" % [
				str(session.get("last_host_restart_address")),
				int(session.get("last_host_restart_port"))
			])
		if (
			recovery_marker_written
			and recovered
			and int(session.get("last_host_restart_generation")) == 1
			and client_has_single_ally_exchange()
			and not recovered_receipt_ready
		):
			if recovered_complete_since_msec < 0:
				recovered_complete_since_msec = Time.get_ticks_msec()
			if (
				Time.get_ticks_msec() - recovered_complete_since_msec
				>= RECOVERED_EXCHANGE_HOLD_MSEC
				and explicit_input_sequence > first_input_sequence
			):
				pending_receipt = client_receipt()
				pending_receipt["explicit_join_calls"] = initial_join_call_count
				pending_receipt["first_peer_id"] = first_peer_id
				pending_receipt["first_snapshot_sequence"] = first_snapshot_sequence
				pending_receipt["first_input_sequence"] = first_input_sequence
				pending_receipt["host_restart_generation"] = int(session.get("last_host_restart_generation"))
				pending_receipt["host_restart_attempt_count"] = int(session.get("last_host_restart_attempt_count"))
				pending_receipt["host_restart_recovered"] = bool(session.get("last_host_restart_recovered"))
				pending_receipt["host_restart_exhausted"] = bool(session.get("last_host_restart_exhausted"))
				pending_receipt["host_restart_reason"] = str(session.get("last_host_restart_reason"))
				pending_receipt["host_restart_address"] = str(session.get("last_host_restart_address"))
				pending_receipt["host_restart_port"] = int(session.get("last_host_restart_port"))
				pending_receipt["host_restart_role"] = str(session.get("last_host_restart_role"))
				pending_receipt["manual_save_blocked_after_recovery"] = bool(session.call("blocks_manual_save"))
				pending_receipt["autosave_blocked_after_recovery"] = bool(session.call("blocks_autosave"))
				recovered_receipt_ready = true
				print(
					"HOST RESTART CLIENT RECOVERED: generation %d attempts %d peer %d snapshot %d input %d" % [
						int(session.get("last_host_restart_generation")),
						int(session.get("last_host_restart_attempt_count")),
						int(session.get("local_peer_id")),
						int(session.get("last_snapshot_sequence")),
						explicit_input_sequence
					]
				)
		elif recovered_receipt_ready:
			recovered_complete_since_msec = -1
		if (
			recovered_receipt_ready
			and mode == MultiplayerSessionModel.MODE_OFFLINE
			and host_commit_received
		):
			pending_receipt["host_shutdown_sequence"] = int(session.get("last_host_shutdown_sequence"))
			pending_receipt["host_shutdown_ack_sent_sequence"] = int(session.get("last_host_shutdown_ack_sent_sequence"))
			pending_receipt["host_shutdown_commit_received"] = true
			pending_receipt["host_shutdown_disconnect_observed"] = bool(session.get("last_host_shutdown_disconnect_observed"))
			pending_receipt["host_shutdown_reason"] = str(session.get("last_host_shutdown_reason"))
			pending_receipt["final_mode"] = mode
			pending_receipt["independent_exit"] = true
			if not write_json(receipt_path, pending_receipt):
				finish_failure("Host-restart ally could not publish its final receipt.")
				return
			print(
				"HOST RESTART CLIENT SHUTDOWN COMMIT: sequence %d" %
				int(pending_receipt.get("host_shutdown_sequence", -1))
			)
			await finish_success()
			return
		if (
			initial_marker_written
			and not recovery_pending
			and not recovered
			and mode == MultiplayerSessionModel.MODE_OFFLINE
			and not host_commit_received
			and str(session.get("session_notice")).contains("HOST RECOVERY CANCELLED")
		):
			finish_failure("Host-restart ally recovery was cancelled without player input.")
			return
		await create_timer(0.05).timeout
	finish_failure(
		"Host-restart ally timed out: mode=%s pending=%s attempts=%d generation=%d recovered=%s exhausted=%s snapshot=%d input=%d notice=%s" % [
			str(session.get("mode")),
			str(session.get("host_restart_recovery_pending")),
			int(session.get("host_restart_attempt_count")),
			int(session.get("last_host_restart_generation")),
			str(session.get("last_host_restart_recovered")),
			str(session.get("last_host_restart_exhausted")),
			int(session.get("last_snapshot_sequence")),
			explicit_input_sequence,
			str(session.get("session_notice"))
		]
	)


func host_has_single_ally_exchange(peers: Dictionary) -> bool:
	return (
		peers.size() == 2
		and MultiplayerSessionModel.role_count(
			peers,
			MultiplayerSessionModel.ROLE_ALLY
		) == 1
		and remote_input_peer_count(peers) == 1
	)


func client_has_single_ally_exchange() -> bool:
	if str(session.get("mode")) != MultiplayerSessionModel.MODE_CLIENT:
		return false
	if str(session.get("local_role")) != MultiplayerSessionModel.ROLE_ALLY:
		return false
	if int(session.get("last_snapshot_sequence")) < 0:
		return false
	var peers := peer_dictionary()
	var local_peer_id := int(session.get("local_peer_id"))
	if peers.size() != 2 or local_peer_id <= 1 or not peers.has(local_peer_id):
		return false
	var local_value: Variant = peers.get(local_peer_id, {})
	if typeof(local_value) != TYPE_DICTIONARY:
		return false
	var local_peer := local_value as Dictionary
	var map_value: Variant = runtime.get("map_data")
	var map_data := map_value as Dictionary if typeof(map_value) == TYPE_DICTIONARY else {}
	return (
		str(local_peer.get("role", "")) == MultiplayerSessionModel.ROLE_ALLY
		and str(map_data.get("id", "")) == HOST_MAP
		and str(runtime.get("current_era_id")) == HOST_ERA
	)


func peer_dictionary() -> Dictionary:
	var peers_value: Variant = session.get("peers")
	return peers_value as Dictionary if typeof(peers_value) == TYPE_DICTIONARY else {}


func send_explicit_input_if_due() -> void:
	var now_msec := Time.get_ticks_msec()
	if now_msec < next_input_retry_msec:
		return
	next_input_retry_msec = now_msec + RESTART_INPUT_RETRY_MSEC
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


func client_receipt() -> Dictionary:
	var peers := peer_dictionary()
	var map_value: Variant = runtime.get("map_data")
	var map_data := map_value as Dictionary if typeof(map_value) == TYPE_DICTIONARY else {}
	var local_peer_id := int(session.get("local_peer_id"))
	var local_value: Variant = peers.get(local_peer_id, {})
	var local_peer := local_value as Dictionary if typeof(local_value) == TYPE_DICTIONARY else {}
	return {
		"ok": true,
		"role": MultiplayerSessionModel.ROLE_ALLY,
		"port": port,
		"local_peer_id": local_peer_id,
		"local_role": str(local_peer.get("role", "")),
		"peer_count": peers.size(),
		"snapshot_sequence": int(session.get("last_snapshot_sequence")),
		"input_sequence_sent": explicit_input_sequence,
		"map_id": str(map_data.get("id", "")),
		"era_id": str(runtime.get("current_era_id"))
	}
