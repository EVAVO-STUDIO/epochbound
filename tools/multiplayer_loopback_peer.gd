extends SceneTree

const MultiplayerSessionModel = preload("res://src/game/multiplayer_session_model.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const HOST_ADDRESS := "127.0.0.1"
const HOST_MAP := "clockwood_edge"
const HOST_ENTRY := "from_bellweather"
const HOST_ERA := "ashen"
const HOST_POSITION := Vector2(360, 240)
const EXPECTED_AREA := "clockwood_ashen_hunt"
const DEFAULT_TIMEOUT_SECONDS := 24.0

var peer_role: String = ""
var port: int = 0
var receipt_path: String = ""
var ready_path: String = ""
var timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS
var runtime: Node
var session: Node
var failure_message: String = ""


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	if not parse_arguments():
		finish_failure(failure_message)
		return
	runtime = await instantiate_runtime()
	if runtime == null:
		finish_failure("Playable runtime scene could not be instantiated.")
		return
	session = runtime.get_node_or_null("MultiplayerSession")
	if session == null:
		finish_failure("Playable runtime scene is missing MultiplayerSession.")
		return
	if peer_role == MultiplayerSessionModel.ROLE_HOST:
		await run_host()
	else:
		await run_client()


func parse_arguments() -> bool:
	for value in OS.get_cmdline_user_args():
		var argument: String = str(value)
		if argument.begins_with("--role="):
			peer_role = argument.trim_prefix("--role=").strip_edges().to_lower()
		elif argument.begins_with("--port="):
			var port_text: String = argument.trim_prefix("--port=").strip_edges()
			if not port_text.is_valid_int():
				failure_message = "Loopback UDP port must be an integer."
				return false
			port = int(port_text)
		elif argument.begins_with("--receipt="):
			receipt_path = argument.trim_prefix("--receipt=").strip_edges()
		elif argument.begins_with("--ready="):
			ready_path = argument.trim_prefix("--ready=").strip_edges()
		elif argument.begins_with("--timeout="):
			var timeout_text: String = argument.trim_prefix("--timeout=").strip_edges()
			if timeout_text.is_valid_float():
				timeout_seconds = clampf(float(timeout_text), 5.0, 60.0)
	if peer_role not in [
		MultiplayerSessionModel.ROLE_HOST,
		MultiplayerSessionModel.ROLE_ALLY,
		MultiplayerSessionModel.ROLE_INVADER
	]:
		failure_message = "Loopback peer role must be host, ally or invader."
		return false
	if port < 1024 or port > 65535:
		failure_message = "Loopback UDP port must be between 1024 and 65535."
		return false
	if receipt_path.is_empty():
		failure_message = "Loopback peer requires an absolute receipt path."
		return false
	if peer_role == MultiplayerSessionModel.ROLE_HOST and ready_path.is_empty():
		failure_message = "Loopback host requires an absolute ready-marker path."
		return false
	return true


func instantiate_runtime() -> Node:
	var packed: Resource = ResourceLoader.load(
		RUNTIME_SCENE,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if not packed is PackedScene:
		return null
	var instance: Node = (packed as PackedScene).instantiate()
	if instance == null:
		return null
	root.add_child(instance)
	await process_frame
	await process_frame
	return instance


func run_host() -> void:
	runtime.call("change_flow", 4)
	if not bool(runtime.call(
		"activate_map",
		HOST_MAP,
		HOST_ENTRY,
		HOST_ERA,
		false
	)):
		finish_failure("Loopback host could not activate the authored PvP map and era.")
		return
	runtime.set("player", HOST_POSITION)
	runtime.set("facing", Vector2.RIGHT)
	runtime.set("companion", HOST_POSITION + Vector2(-18, 20))
	session.set("local_name", "LOOPBACK HOST")
	if not bool(session.call("host_session", port)):
		finish_failure(
			"Loopback host could not open ENet on UDP %d: %s" % [
				port,
				str(session.get("session_notice"))
			]
		)
		return
	var area_value: Variant = session.call("online_area")
	var area: Dictionary = (
		area_value if typeof(area_value) == TYPE_DICTIONARY else {}
	)
	if str(area.get("id", "")) != EXPECTED_AREA:
		finish_failure("Loopback host did not resolve the authored Ashen PvP area.")
		return
	if not write_json(ready_path, {
		"ok": true,
		"role": MultiplayerSessionModel.ROLE_HOST,
		"port": port,
		"area_id": EXPECTED_AREA
	}):
		finish_failure("Loopback host could not write its ready marker.")
		return
	var deadline_msec: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		var peers_value: Variant = session.get("peers")
		var peers: Dictionary = (
			peers_value if typeof(peers_value) == TYPE_DICTIONARY else {}
		)
		if host_has_complete_exchange(peers):
			var snapshot_value: Variant = session.call("build_world_snapshot")
			var snapshot: Dictionary = (
				snapshot_value if typeof(snapshot_value) == TYPE_DICTIONARY else {}
			)
			var receipt := {
				"ok": true,
				"role": MultiplayerSessionModel.ROLE_HOST,
				"port": port,
				"peer_count": peers.size(),
				"ally_count": MultiplayerSessionModel.role_count(
					peers,
					MultiplayerSessionModel.ROLE_ALLY
				),
				"invader_count": MultiplayerSessionModel.role_count(
					peers,
					MultiplayerSessionModel.ROLE_INVADER
				),
				"input_peer_count": remote_input_peer_count(peers),
				"snapshot_sequence": int(snapshot.get("sequence", -1)),
				"protocol_version": int(snapshot.get("protocol_version", 0)),
				"map_id": str(snapshot.get("map_id", "")),
				"era_id": str(snapshot.get("era_id", "")),
				"area_id": EXPECTED_AREA
			}
			if not write_json(receipt_path, receipt):
				finish_failure("Loopback host could not write its validation receipt.")
				return
			await create_timer(2.0).timeout
			finish_success()
			return
		await create_timer(0.05).timeout
	finish_failure(
		"Loopback host timed out before ally and invader input reached host authority."
	)


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
		if client_has_complete_exchange():
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
			var receipt := {
				"ok": true,
				"role": peer_role,
				"port": port,
				"local_peer_id": local_peer_id,
				"local_role": str(local_peer.get("role", "")),
				"peer_count": peers.size(),
				"snapshot_sequence": int(session.get("last_snapshot_sequence")),
				"map_id": str(map_data.get("id", "")),
				"era_id": str(runtime.get("current_era_id"))
			}
			if not write_json(receipt_path, receipt):
				finish_failure("Loopback %s could not write its validation receipt." % peer_role)
				return
			await create_timer(1.0).timeout
			finish_success()
			return
		await create_timer(0.05).timeout
	finish_failure(
		"Loopback %s timed out before a complete authoritative snapshot arrived." % peer_role
	)


func host_has_complete_exchange(peers: Dictionary) -> bool:
	return (
		peers.size() == 3
		and MultiplayerSessionModel.role_count(
			peers,
			MultiplayerSessionModel.ROLE_ALLY
		) == 1
		and MultiplayerSessionModel.role_count(
			peers,
			MultiplayerSessionModel.ROLE_INVADER
		) == 1
		and remote_input_peer_count(peers) == 2
	)


func remote_input_peer_count(peers: Dictionary) -> int:
	var count: int = 0
	for key in peers.keys():
		if typeof(key) != TYPE_INT or int(key) <= 1:
			continue
		var peer_value: Variant = peers.get(key, {})
		if (
			typeof(peer_value) == TYPE_DICTIONARY
			and int((peer_value as Dictionary).get("last_sequence", -1)) >= 0
		):
			count += 1
	return count


func client_has_complete_exchange() -> bool:
	if str(session.get("mode")) != MultiplayerSessionModel.MODE_CLIENT:
		return false
	if str(session.get("local_role")) != peer_role:
		return false
	if int(session.get("last_snapshot_sequence")) < 0:
		return false
	var peers_value: Variant = session.get("peers")
	var peers: Dictionary = (
		peers_value if typeof(peers_value) == TYPE_DICTIONARY else {}
	)
	var local_peer_id: int = int(session.get("local_peer_id"))
	if peers.size() != 3 or local_peer_id <= 1 or not peers.has(local_peer_id):
		return false
	var local_value: Variant = peers.get(local_peer_id, {})
	if typeof(local_value) != TYPE_DICTIONARY:
		return false
	var local_peer: Dictionary = local_value
	var map_value: Variant = runtime.get("map_data")
	var map_data: Dictionary = (
		map_value if typeof(map_value) == TYPE_DICTIONARY else {}
	)
	return (
		str(local_peer.get("role", "")) == peer_role
		and str(map_data.get("id", "")) == HOST_MAP
		and str(runtime.get("current_era_id")) == HOST_ERA
	)


func write_json(path: String, payload: Dictionary) -> bool:
	if path.is_empty():
		return false
	var directory: String = path.get_base_dir()
	if not directory.is_empty():
		var directory_error: int = DirAccess.make_dir_recursive_absolute(directory)
		if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
			return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t", true) + "\n")
	file.flush()
	file.close()
	return true


func cleanup_runtime() -> void:
	if runtime == null:
		return
	if session != null and session.has_method("leave_session"):
		session.call("leave_session", "LOOPBACK VALIDATION COMPLETE")
	if runtime.get_parent() == root:
		root.remove_child(runtime)
	runtime.free()
	runtime = null
	session = null


func finish_success() -> void:
	cleanup_runtime()
	print(
		"Real ENet loopback peer passed: %s completed host-authoritative negotiation, input and snapshot exchange." % peer_role
	)
	quit(0)


func finish_failure(message: String) -> void:
	var payload := {
		"ok": false,
		"role": peer_role,
		"port": port,
		"error": message
	}
	if not receipt_path.is_empty():
		write_json(receipt_path, payload)
	cleanup_runtime()
	push_error(message)
	quit(1)
