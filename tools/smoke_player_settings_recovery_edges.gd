extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")

const PlayerSettings = preload("res://src/game/player_settings.gd")
const PlayerSettingsStore = preload("res://src/game/player_settings_store.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const TEST_ROOT := "user://epochbound_test_player_settings_recovery"
const VIEW_CENTER := Vector2(320, 180)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	test_backup_only_recovery()
	await test_modal_presentation_freeze()
	PlayerSettingsStore.delete_settings(TEST_ROOT)
	finish()


func prepare_backup_only_settings() -> void:
	PlayerSettingsStore.delete_settings(TEST_ROOT)
	var previous: Dictionary = PlayerSettings.default_settings()
	previous["master_volume"] = 0.3
	check(bool(PlayerSettingsStore.write_settings(previous, TEST_ROOT).get("ok", false)), "Recovery setup must write the previous complete settings.")
	var current: Dictionary = PlayerSettings.default_settings()
	current["master_volume"] = 0.9
	check(bool(PlayerSettingsStore.write_settings(current, TEST_ROOT).get("ok", false)), "Recovery setup must rotate a valid backup.")
	check(FileAccess.file_exists(PlayerSettingsStore.backup_path(TEST_ROOT)), "Recovery setup must leave the previous complete settings as backup.")
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerSettingsStore.settings_path(TEST_ROOT)))
	check(remove_error == OK, "Recovery setup must simulate a crash after primary rotation.")


func test_backup_only_recovery() -> void:
	prepare_backup_only_settings()
	var recovered: Dictionary = PlayerSettingsStore.load_settings(TEST_ROOT)
	check(bool(recovered.get("ok", false)), "Backup-only settings must load successfully.")
	check(bool(recovered.get("recovered_from_backup", false)), "Backup-only settings must identify their recovery source.")
	var settings_value: Variant = recovered.get("settings", {})
	var settings: Dictionary = settings_value as Dictionary if typeof(settings_value) == TYPE_DICTIONARY else {}
	check(is_equal_approx(PlayerSettings.number(settings, "master_volume"), 0.3), "Backup-only recovery must restore the last complete previous value.")
	check(bool(PlayerSettingsStore.rewrite_loaded_settings(recovered, TEST_ROOT).get("ok", false)), "Backup-only recovery must be promotable into a new primary file.")
	check(FileAccess.file_exists(PlayerSettingsStore.settings_path(TEST_ROOT)), "Promoting recovered settings must recreate the primary file.")
	var promoted: Dictionary = PlayerSettingsStore.load_settings(TEST_ROOT)
	check(not bool(promoted.get("recovered_from_backup", false)), "A promoted recovery must load from the repaired primary file.")
	PlayerSettingsStore.delete_settings(TEST_ROOT)


func test_modal_presentation_freeze() -> void:
	prepare_backup_only_settings()
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Settings recovery edge scene must load.")
	if not packed is PackedScene:
		return
	var runtime: Node = (packed as PackedScene).instantiate()
	check(runtime != null, "Settings recovery edge scene must instantiate.")
	if runtime == null:
		return
	root.add_child(runtime)
	await process_frame

	var migration_result: Dictionary = PlayerSettings.migrate({"schema_version": 0, "master_volume": 0.6})
	check(bool(migration_result.get("ok", false)), "Recovery edge setup must produce a supported migrated settings result.")
	runtime.call("apply_player_settings_load_result", migration_result)
	check(str(runtime.get("player_settings_load_status")) == "migrated", "Runtime Options must preserve supported migration status.")
	check(bool(runtime.get("player_settings_dirty")), "Migrated runtime settings must remain pending for atomic promotion.")
	check(str(runtime.call("player_settings_open_notice")) == "SETTINGS UPDATED TO CURRENT VERSION", "Options must explain when settings were migrated.")
	check(is_equal_approx(float(runtime.call("player_setting_number", "master_volume", 1.0)), 0.6), "Runtime migration must preserve recognised legacy values.")

	runtime.call("load_player_settings", TEST_ROOT)
	check(str(runtime.get("player_settings_load_status")) == "recovered", "Runtime Options must preserve the backup recovery status.")
	check(bool(runtime.get("player_settings_dirty")), "Recovered runtime settings must remain pending for atomic primary repair.")
	check(is_equal_approx(float(runtime.call("player_setting_number", "master_volume", 1.0)), 0.3), "Runtime recovery must expose the last complete backup value.")

	runtime.call("change_flow", 4)
	runtime.set("transition_lock", 0.0)
	runtime.set("dialogue", "")
	runtime.set("active_cinematic_id", "")
	check(bool(runtime.call("open_player_settings")), "Options must open for modal-freeze testing.")
	check(str(runtime.get("player_settings_notice")) == "RECOVERED SETTINGS FROM BACKUP", "Options must explain that settings came from the backup.")

	var overlay: Node = runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	var camera: Camera2D = runtime.get_node_or_null("PresentationCamera") as Camera2D
	check(overlay != null, "Settings recovery edge test requires the presentation overlay.")
	check(camera != null, "Settings recovery edge test requires the presentation camera.")
	if overlay != null:
		var particles_value: Variant = overlay.get("atmosphere_particles")
		var particles: Array = particles_value as Array if typeof(particles_value) == TYPE_ARRAY else []
		if particles.is_empty():
			particles.append({"position": Vector2(44, 55), "scale": 1.0, "phase": 0.0})
			overlay.set("atmosphere_particles", particles)
		var before_value: Variant = (particles[0] as Dictionary).get("position", Vector2.ZERO)
		var before: Vector2 = before_value if before_value is Vector2 else Vector2.ZERO
		overlay.call("update_atmosphere", 1.0)
		particles_value = overlay.get("atmosphere_particles")
		particles = particles_value as Array if typeof(particles_value) == TYPE_ARRAY else []
		var after_value: Variant = (particles[0] as Dictionary).get("position", Vector2.ZERO) if not particles.is_empty() else Vector2.INF
		var after: Vector2 = after_value if after_value is Vector2 else Vector2.INF
		check(after.is_equal_approx(before), "Options must freeze existing atmosphere particles exactly.")

		overlay.set("shake_strength", 4.0)
		overlay.set("shake_timer", 0.5)
		if runtime is Node2D:
			(runtime as Node2D).position = Vector2(5, 3)
		overlay.call("apply_root_shake")
		check(is_equal_approx(float(overlay.get("shake_strength")), 0.0), "Options must clear existing shake strength.")
		check(is_equal_approx(float(overlay.get("shake_timer")), 0.0), "Options must clear the remaining shake timer.")
		if runtime is Node2D:
			check((runtime as Node2D).position.is_equal_approx(Vector2.ZERO), "Options must restore the runtime root to a neutral position.")

	if camera != null:
		camera.position = Vector2(347, 194)
		check(bool(camera.call("modal_surface_open", runtime)), "PresentationCamera must recognise Options as a modal surface.")
		camera.call("_process", 0.1)
		check(camera.position.is_equal_approx(VIEW_CENTER), "Options must centre and neutralise the presentation camera.")
		check(not bool(camera.get("initialized")), "Options must reset camera smoothing state before gameplay resumes.")

	check(bool(runtime.call("close_player_settings", TEST_ROOT)), "Closing recovered Options must atomically heal the isolated primary settings file.")
	check(not bool(runtime.get("player_settings_dirty")), "Successful recovery promotion must clear the pending settings write.")
	check(str(runtime.get("player_settings_load_status")) == "saved", "Successful recovery promotion must enter the saved state.")
	check(FileAccess.file_exists(PlayerSettingsStore.settings_path(TEST_ROOT)), "Closing recovered Options must recreate the primary settings file.")
	var healed: Dictionary = PlayerSettingsStore.load_settings(TEST_ROOT)
	check(not bool(healed.get("recovered_from_backup", false)), "The next settings load must use the healed primary file.")
	var healed_value: Variant = healed.get("settings", {})
	var healed_settings: Dictionary = healed_value as Dictionary if typeof(healed_value) == TYPE_DICTIONARY else {}
	check(is_equal_approx(PlayerSettings.number(healed_settings, "master_volume"), 0.3), "The healed primary file must retain the recovered value.")

	await HeadlessRuntimeCleanup.release(self, runtime)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Player settings recovery-edge smoke test passed: migration status, backup-only recovery, atomic runtime healing, frozen particles, cleared shake and centred modal camera are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
