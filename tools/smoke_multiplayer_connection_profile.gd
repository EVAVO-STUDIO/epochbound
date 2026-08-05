extends SceneTree

const MultiplayerConnectionProfile = preload("res://src/game/multiplayer_connection_profile.gd")
const MultiplayerConnectionProfileStore = preload("res://src/game/multiplayer_connection_profile_store.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const TEST_ROOT := "user://tests/multiplayer_connection_profile_smoke"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	MultiplayerConnectionProfileStore.delete_profile(TEST_ROOT)

	check(
		MultiplayerConnectionProfile.address_is_valid("play.example.test"),
		"Connection profiles must accept fully qualified hostnames."
	)
	check(
		MultiplayerConnectionProfile.address_is_valid("192.168.1.40"),
		"Connection profiles must accept IPv4 addresses."
	)
	check(
		MultiplayerConnectionProfile.sanitize_address("[::1]") == "::1",
		"Connection profiles must normalize bracketed IPv6 addresses for ENet."
	)
	check(
		not MultiplayerConnectionProfile.address_is_valid(
			"https://play.example.test/path"
		),
		"Connection profiles must reject URL schemes and paths."
	)
	check(
		not MultiplayerConnectionProfile.address_is_valid(
			"play example.test"
		),
		"Connection profiles must reject whitespace."
	)
	check(
		not bool(
			MultiplayerConnectionProfile.validate(
				{
					"schema_version": 1,
					"address": "play.example.test",
					"port": 80,
					"player_name": "ALLY"
				}
			).get("ok", true)
		),
		"Connection profiles must reject privileged or malformed UDP ports."
	)
	check(
		not bool(
			MultiplayerConnectionProfile.validate(
				{
					"schema_version": 1,
					"address": "play.example.test",
					"port": 27491,
					"player_name": "ALLY!"
				}
			).get("ok", true)
		),
		"Connection profiles must reject unsupported display-name characters."
	)

	var first_profile := {
		"schema_version": MultiplayerConnectionProfile.CURRENT_SCHEMA,
		"address": "first.example.test",
		"port": 27491,
		"player_name": "FIRST ALLY"
	}
	var first_write := MultiplayerConnectionProfileStore.write_profile(
		first_profile,
		27491,
		"WANDERER",
		TEST_ROOT
	)
	check(
		bool(first_write.get("ok", false)),
		"Atomic connection-profile storage must write a valid first profile."
	)
	var second_profile := {
		"schema_version": MultiplayerConnectionProfile.CURRENT_SCHEMA,
		"address": "second.example.test",
		"port": 27501,
		"player_name": "SECOND ALLY"
	}
	var second_write := MultiplayerConnectionProfileStore.write_profile(
		second_profile,
		27491,
		"WANDERER",
		TEST_ROOT
	)
	check(
		bool(second_write.get("ok", false)),
		"Atomic connection-profile storage must rotate a valid previous profile."
	)
	check(
		FileAccess.file_exists(
			MultiplayerConnectionProfileStore.backup_path(TEST_ROOT)
		),
		"A second valid write must retain one known-good backup."
	)
	var primary_file := FileAccess.open(
		MultiplayerConnectionProfileStore.profile_path(TEST_ROOT),
		FileAccess.WRITE
	)
	check(
		primary_file != null,
		"Connection-profile recovery setup must open the primary profile."
	)
	if primary_file != null:
		primary_file.store_string("{broken")
		primary_file.flush()
		primary_file.close()
	var recovered := MultiplayerConnectionProfileStore.load_profile(
		27491,
		"WANDERER",
		TEST_ROOT
	)
	check(
		bool(recovered.get("ok", false))
		and bool(recovered.get("recovered_from_backup", false)),
		"Malformed primary connection data must recover from the last valid backup."
	)
	check(
		str(
			(recovered.get("profile", {}) as Dictionary).get(
				"address",
				""
			)
		) == "first.example.test",
		"Backup recovery must restore the exact previous connection address."
	)

	var runtime := await instantiate_runtime()
	if runtime != null:
		var session := runtime.get_node_or_null("MultiplayerSession")
		var panel := runtime.get_node_or_null(
			"PresentationLayer/MultiplayerConnectionPanel"
		)
		check(
			session != null,
			"Playable scene must include MultiplayerSession."
		)
		check(
			panel != null,
			"Playable scene must include MultiplayerConnectionPanel."
		)
		if session != null and panel != null:
			check(
				bool(
					panel.call(
						"multiplayer_connection_panel_contract_ok"
					)
				),
				"Connection panel must retain its player-local editor contract."
			)
			session.call("toggle_lobby")
			check(
				bool(session.get("lobby_open")),
				"Connection-panel smoke setup must open the online lobby."
			)
			check(
				bool(panel.call("open_editor")),
				"The offline online lobby must open connection setup."
			)
			check(
				not session.is_processing(),
				"Connection setup must suspend lobby polling while text controls own input."
			)
			var address_edit := panel.get("address_edit") as LineEdit
			var port_edit := panel.get("port_edit") as SpinBox
			var name_edit := panel.get("name_edit") as LineEdit
			check(
				address_edit != null
				and port_edit != null
				and name_edit != null,
				"Connection setup must expose address, port and display-name controls."
			)
			if address_edit != null and port_edit != null and name_edit != null:
				address_edit.text = "lan-host.example.test"
				port_edit.value = 27601
				name_edit.text = "MORROW ALLY"
				check(
					bool(panel.call("save_current_profile", TEST_ROOT)),
					"Valid in-game connection details must save atomically."
				)
				check(
					str(session.get("connect_address"))
						== "lan-host.example.test",
					"Saved connection address must immediately update the session."
				)
				check(
					int(session.get("connect_port")) == 27601,
					"Saved UDP port must immediately update the session."
				)
				check(
					str(session.get("local_name")) == "MORROW ALLY",
					"Saved display name must immediately update the session."
				)
				await process_frame
				check(
					session.is_processing(),
					"Returning to the lobby must restore session polling."
				)
				check(
					bool(session.get("lobby_open")),
					"Saving connection setup must return to the existing lobby."
				)
			var stored := MultiplayerConnectionProfileStore.load_profile(
				27491,
				"WANDERER",
				TEST_ROOT
			)
			check(
				str(
					(stored.get("profile", {}) as Dictionary).get(
						"address",
						""
					)
				) == "lan-host.example.test",
				"Panel writes must remain readable through the player-local store."
			)
		cleanup(runtime)

	var deleted := MultiplayerConnectionProfileStore.delete_profile(
		TEST_ROOT
	)
	check(
		bool(deleted.get("ok", false)),
		"Connection-profile smoke data must clean up without touching campaign source."
	)
	finish()


func instantiate_runtime() -> Node:
	var packed := ResourceLoader.load(
		RUNTIME_SCENE,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	check(
		packed is PackedScene,
		"Connection-aware runtime scene must load."
	)
	if not packed is PackedScene:
		return null
	var runtime := (packed as PackedScene).instantiate()
	check(
		runtime != null,
		"Connection-aware runtime scene must instantiate."
	)
	if runtime == null:
		return null
	root.add_child(runtime)
	await process_frame
	return runtime


func cleanup(runtime: Node) -> void:
	if runtime == null:
		return
	root.remove_child(runtime)
	runtime.free()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print(
			"Multiplayer connection profile smoke test passed: hostname and IP validation, atomic player-local persistence, backup recovery, focused text controls and lobby restoration are coherent."
		)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
