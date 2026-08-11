extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")
const MultiplayerSessionModel = preload("res://src/game/multiplayer_session_model.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const TEST_PORT := 35191

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var runtime := await instantiate_runtime()
	if runtime == null:
		finish()
		return
	var session := runtime.get_node_or_null("MultiplayerSession")
	check(session != null, "Host-restart recovery smoke requires MultiplayerSession.")
	if session == null:
		await cleanup(runtime)
		finish()
		return

	check(
		bool(session.call("host_restart_address_is_direct", "127.0.0.1")),
		"Literal IPv4 endpoints must be eligible for bounded host-restart recovery."
	)
	check(
		bool(session.call("host_restart_address_is_direct", "[::1]")),
		"Bracketed literal IPv6 endpoints must be eligible for bounded host-restart recovery."
	)
	check(
		not bool(session.call("host_restart_address_is_direct", "example.invalid")),
		"Hostnames must not be replayed automatically after an unexpected host loss."
	)

	var expected_delays := [0.35, 0.7, 1.4, 2.0, 2.0, 2.0]
	for completed_attempts in range(expected_delays.size()):
		var actual := float(session.call(
			"host_restart_retry_delay_after_attempt",
			completed_attempts
		))
		check(
			is_equal_approx(actual, float(expected_delays[completed_attempts])),
			"Host-restart backoff must remain deterministic at attempt index %d." % completed_attempts
		)

	check(
		bool(session.call(
			"configure_test_host_restart_client",
			"127.0.0.1",
			MultiplayerSessionModel.ROLE_ALLY,
			TEST_PORT
		)),
		"A connected direct-IP ally must arm restart recovery."
	)
	check(bool(session.get("host_restart_recovery_armed")), "Direct-IP client recovery must be armed after an accepted session.")
	session.call("_on_server_disconnected")
	check(
		bool(session.get("host_restart_transition_deferred")),
		"Unexpected host loss must queue one deferred transport transition."
	)
	check(not bool(session.get("host_restart_recovery_pending")), "Disconnect signal dispatch must not detach ENet synchronously.")
	check(str(session.get("mode")) == MultiplayerSessionModel.MODE_CLIENT, "The active client peer must remain attached until deferred signal dispatch completes.")
	session.call("_on_peer_disconnected", 1)
	session.call("_on_connection_failed")
	check(bool(session.get("host_restart_transition_deferred")), "Duplicate disconnect callbacks must collapse into the same deferred transition.")
	check(str(session.get("host_restart_transition_kind")) == "begin", "Duplicate disconnect callbacks must not replace the queued recovery-begin transition.")
	session.call("apply_host_restart_transition")
	check(bool(session.get("host_restart_recovery_pending")), "Host restart recovery must remain pending before a replacement host is accepted.")
	check(str(session.get("mode")) == MultiplayerSessionModel.MODE_OFFLINE, "Recovery backoff must detach the stale peer and return transport state offline.")
	check(bool(session.call("blocks_manual_save")), "Manual saves must remain blocked while host recovery is pending.")
	check(bool(session.call("blocks_autosave")), "Autosaves must remain blocked while host recovery is pending.")
	check(str(session.get("last_host_restart_address")) == "127.0.0.1", "Recovery evidence must preserve the exact accepted endpoint.")
	check(int(session.get("last_host_restart_port")) == TEST_PORT, "Recovery evidence must preserve the exact accepted UDP port.")
	check(str(session.get("last_host_restart_role")) == MultiplayerSessionModel.ROLE_ALLY, "Recovery evidence must preserve the accepted role.")

	var delay_before_duplicate := float(session.get("host_restart_delay_remaining"))
	session.call("_on_server_disconnected")
	session.call("_on_peer_disconnected", 1)
	session.call("_on_connection_failed")
	check(
		is_equal_approx(float(session.get("host_restart_delay_remaining")), delay_before_duplicate),
		"Duplicate stale-peer disconnect signals must not reset an in-flight recovery backoff."
	)
	check(int(session.get("host_restart_attempt_count")) == 0, "Stale disconnect signals must not consume a recovery attempt.")

	# Once a new create_client call is pending, stale server and peer disconnect
	# notifications from the disposed transport must remain inert. The current
	# peer's connection_failed signal is the only authoritative pending result.
	session.set("host_restart_attempt_count", 1)
	session.set("last_host_restart_attempt_count", 1)
	session.set("connection_pending", true)
	session.call("_on_server_disconnected")
	session.call("_on_peer_disconnected", 1)
	check(
		not bool(session.get("host_restart_transition_deferred")),
		"Pending retry must ignore stale server and peer disconnect callbacks."
	)
	check(
		int(session.get("host_restart_attempt_count")) == 1,
		"Ignored stale callbacks must not consume or duplicate the active attempt."
	)
	session.call("_on_connection_failed")
	check(
		bool(session.get("host_restart_transition_deferred")),
		"Pending retry connection_failed must queue the authoritative failed attempt."
	)
	check(
		str(session.get("host_restart_transition_kind")) == "fail",
		"Authoritative pending failure must retain the fail transition kind."
	)
	session.call("apply_host_restart_transition")
	check(
		is_equal_approx(float(session.get("host_restart_delay_remaining")), 0.7),
		"The first failed retry must advance to the deterministic second backoff."
	)

	session.call("cancel_host_restart_recovery", "HOST RECOVERY CANCELLED")
	check(not bool(session.get("host_restart_recovery_pending")), "Explicit cancellation must end recovery immediately.")
	check(not bool(session.get("last_host_restart_recovered")), "Cancelled recovery must not claim success.")
	check(not bool(session.get("last_host_restart_exhausted")), "Cancelled recovery must remain distinct from retry exhaustion.")
	check(not bool(session.call("blocks_manual_save")), "Save blocking must end after recovery cancellation.")

	check(
		bool(session.call(
			"configure_test_host_restart_client",
			"[::1]",
			MultiplayerSessionModel.ROLE_INVADER,
			TEST_PORT
		)),
		"A bracketed direct IPv6 invader endpoint must arm recovery."
	)
	check(
		bool(session.call("begin_host_restart_recovery", "HOST CONNECTION LOST")),
		"The direct IPv6 endpoint must enter recovery without changing role."
	)
	session.set("host_restart_attempt_count", 2)
	session.set("mode", MultiplayerSessionModel.MODE_CLIENT)
	session.set("connection_pending", false)
	session.call("complete_host_restart_recovery")
	check(int(session.get("last_host_restart_generation")) == 1, "A recovered client must advance the monotonic restart generation exactly once.")
	check(int(session.get("last_host_restart_attempt_count")) == 2, "Recovery evidence must retain the successful attempt count.")
	check(bool(session.get("last_host_restart_recovered")), "Successful recovery must publish explicit positive evidence.")
	check(not bool(session.get("last_host_restart_exhausted")), "Successful recovery must not be marked exhausted.")
	check(str(session.get("local_role")) == MultiplayerSessionModel.ROLE_INVADER, "Successful recovery must preserve the accepted player role.")
	check(bool(session.call("blocks_manual_save")), "A recovered online client must retain normal multiplayer manual-save isolation.")
	check(bool(session.call("blocks_autosave")), "A recovered online client must retain normal multiplayer autosave isolation.")

	check(
		not bool(session.call(
			"configure_test_host_restart_client",
			"host.example.invalid",
			MultiplayerSessionModel.ROLE_ALLY,
			TEST_PORT
		)),
		"A hostname-backed client must not arm automatic outage recovery."
	)
	check(not bool(session.get("host_restart_recovery_armed")), "Rejected hostname recovery must remain disarmed.")

	check(
		bool(session.call(
			"configure_test_host_restart_client",
			"127.0.0.1",
			MultiplayerSessionModel.ROLE_ALLY,
			TEST_PORT
		)),
		"The exhaustion case must start from a valid direct endpoint."
	)
	check(bool(session.call("begin_host_restart_recovery", "HOST CONNECTION LOST")), "The exhaustion case must enter recovery.")
	session.set("host_restart_attempt_count", 6)
	session.call("exhaust_host_restart_recovery", "HOST RESTART CONNECTION FAILED")
	check(not bool(session.get("host_restart_recovery_pending")), "Retry exhaustion must end the pending state.")
	check(not bool(session.get("host_restart_recovery_armed")), "Retry exhaustion must disarm automatic recovery until a new explicit join.")
	check(bool(session.get("last_host_restart_exhausted")), "Retry exhaustion must publish explicit terminal evidence.")
	check(not bool(session.get("last_host_restart_recovered")), "Exhausted recovery must never claim success.")
	check(int(session.get("last_host_restart_attempt_count")) == 6, "Terminal evidence must retain the complete six-attempt budget.")
	check(str(session.get("mode")) == MultiplayerSessionModel.MODE_OFFLINE, "Exhausted recovery must leave the client offline.")

	await cleanup(runtime)
	finish()


func instantiate_runtime() -> Node:
	var packed := ResourceLoader.load(
		RUNTIME_SCENE,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	check(packed is PackedScene, "Host-restart smoke runtime scene must load.")
	if not packed is PackedScene:
		return null
	var runtime := (packed as PackedScene).instantiate()
	check(runtime != null, "Host-restart smoke runtime scene must instantiate.")
	if runtime == null:
		return null
	root.add_child(runtime)
	await process_frame
	await process_frame
	return runtime


func cleanup(runtime: Node) -> void:
	if runtime != null:
		await HeadlessRuntimeCleanup.release(self, runtime)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Host restart recovery smoke test passed: deferred signal-safe transport handoff, direct endpoint replay, deterministic bounded backoff, pending-attempt signal authority, stale-signal idempotence, role preservation, cancellation, completion, exhaustion and save isolation are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
