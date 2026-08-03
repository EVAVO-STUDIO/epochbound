extends SceneTree

const PlayerInputBindings = preload("res://src/game/player_input_bindings.gd")
const PlayerSettings = preload("res://src/game/player_settings.gd")
const PlayerSettingsStore = preload("res://src/game/player_settings_store.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const TEST_ROOT := "user://epochbound_test_player_settings"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	test_model_contract()
	test_isolated_atomic_storage()
	await test_runtime_integration()
	PlayerSettingsStore.delete_settings(TEST_ROOT)
	finish()


func test_model_contract() -> void:
	var defaults: Dictionary = PlayerSettings.default_settings()
	check(bool(PlayerSettings.validate(defaults).get("ok", false)), "Default player settings must validate.")
	check(PlayerSettings.entries().size() == 13, "Player settings must expose ten adjustable values, Controls, Reset All Defaults and Back.")
	check(is_equal_approx(PlayerSettings.number(defaults, "master_volume"), 1.0), "Default master volume must be full.")
	check(PlayerSettings.boolean(defaults, "show_action_prompts", false), "Action prompts must be enabled by default.")
	check(bool(PlayerInputBindings.validate_profile(PlayerSettings.input_bindings(defaults)).get("ok", false)), "Default player settings must include a complete keyboard and controller binding profile.")

	var sanitized: Dictionary = PlayerSettings.sanitize({
		"schema_version": 2,
		"music_volume": 4.25,
		"sfx_volume": -2.0,
		"show_action_prompts": "invalid"
	})
	check(is_equal_approx(PlayerSettings.number(sanitized, "music_volume"), 1.0), "Numeric player settings must clamp at their maximum.")
	check(is_equal_approx(PlayerSettings.number(sanitized, "sfx_volume"), 0.0), "Numeric player settings must clamp at their minimum.")
	check(PlayerSettings.boolean(sanitized, "show_action_prompts", false), "Malformed booleans must fall back to safe defaults.")
	check(bool(PlayerInputBindings.validate_profile(PlayerSettings.input_bindings(sanitized)).get("ok", false)), "Missing bindings must sanitize to the complete default profile.")

	var migration: Dictionary = PlayerSettings.migrate({"schema_version": 1, "master_volume": 0.4})
	check(bool(migration.get("ok", false)), "Schema-one player settings must migrate to persistent controls.")
	check(bool(migration.get("migrated", false)), "Partial legacy player settings must report migration.")
	var migrated: Dictionary = dictionary_field(migration, "settings")
	check(int(migrated.get("schema_version", 0)) == PlayerSettings.CURRENT_SCHEMA, "Migrated player settings must use the current schema.")
	check(is_equal_approx(PlayerSettings.number(migrated, "master_volume"), 0.4), "Migration must preserve recognised values.")
	check(PlayerSettings.boolean(migrated, "show_action_prompts", false), "Migration must fill newly introduced settings.")
	check(bool(PlayerInputBindings.validate_profile(PlayerSettings.input_bindings(migrated)).get("ok", false)), "Migration must add complete default input bindings.")

	var future: Dictionary = PlayerSettings.migrate({"schema_version": PlayerSettings.CURRENT_SCHEMA + 1})
	check(not bool(future.get("ok", true)), "Unknown future player-setting schemas must be rejected.")
	var adjusted: Dictionary = PlayerSettings.adjusted(defaults, "screen_texture_intensity", -1)
	check(is_equal_approx(PlayerSettings.number(adjusted, "screen_texture_intensity"), 0.75), "Range adjustment must follow the authored step.")
	adjusted = PlayerSettings.adjusted(adjusted, "high_contrast_ui", 1)
	check(PlayerSettings.boolean(adjusted, "high_contrast_ui", false), "Boolean adjustment must toggle deterministically.")


func test_isolated_atomic_storage() -> void:
	PlayerSettingsStore.delete_settings(TEST_ROOT)
	var empty: Dictionary = PlayerSettingsStore.load_settings(TEST_ROOT)
	check(bool(empty.get("ok", false)), "Missing player settings must resolve to defaults.")
	check(bool(empty.get("used_defaults", false)), "Missing player settings must report default recovery.")

	var first: Dictionary = PlayerSettings.default_settings()
	first["master_volume"] = 0.4
	var first_write: Dictionary = PlayerSettingsStore.write_settings(first, TEST_ROOT)
	check(bool(first_write.get("ok", false)), "First player-settings write must complete atomically.")
	check(FileAccess.file_exists(PlayerSettingsStore.settings_path(TEST_ROOT)), "Atomic settings write must promote the final file.")
	check(not FileAccess.file_exists(PlayerSettingsStore.temp_path(TEST_ROOT)), "Atomic settings write must not leave a temporary file.")

	var second: Dictionary = PlayerSettings.default_settings()
	second["master_volume"] = 0.8
	var second_write: Dictionary = PlayerSettingsStore.write_settings(second, TEST_ROOT)
	check(bool(second_write.get("ok", false)), "Second player-settings write must complete.")
	check(FileAccess.file_exists(PlayerSettingsStore.backup_path(TEST_ROOT)), "Replacing valid settings must preserve the previous file as backup.")
	var current: Dictionary = PlayerSettingsStore.load_settings(TEST_ROOT)
	var current_settings := dictionary_field(current, "settings")
	check(is_equal_approx(PlayerSettings.number(current_settings, "master_volume"), 0.8), "The promoted settings file must contain the latest value.")
	check(bool(PlayerInputBindings.validate_profile(PlayerSettings.input_bindings(current_settings)).get("ok", false)), "Atomic storage must preserve the complete binding profile.")

	var corrupt: FileAccess = FileAccess.open(PlayerSettingsStore.settings_path(TEST_ROOT), FileAccess.WRITE)
	check(corrupt != null, "Test must be able to corrupt the isolated primary settings file.")
	if corrupt != null:
		corrupt.store_string("{ invalid settings")
		corrupt.flush()
		corrupt.close()
	var recovered: Dictionary = PlayerSettingsStore.load_settings(TEST_ROOT)
	check(bool(recovered.get("ok", false)), "A corrupt primary settings file must not prevent recovery.")
	check(bool(recovered.get("recovered_from_backup", false)), "A valid backup must be identified as the recovery source.")
	var recovered_settings := dictionary_field(recovered, "settings")
	check(is_equal_approx(PlayerSettings.number(recovered_settings, "master_volume"), 0.4), "Backup recovery must restore the previous complete value.")

	var rewrite: Dictionary = PlayerSettingsStore.rewrite_loaded_settings(recovered, TEST_ROOT)
	check(bool(rewrite.get("ok", false)), "Recovered settings must be promotable without destroying the valid backup first.")
	var promoted: Dictionary = PlayerSettingsStore.load_settings(TEST_ROOT)
	check(not bool(promoted.get("recovered_from_backup", false)), "A rewritten recovered profile must load from the primary path.")
	var promoted_settings := dictionary_field(promoted, "settings")
	check(is_equal_approx(PlayerSettings.number(promoted_settings, "master_volume"), 0.4), "Rewritten recovered settings must retain their value.")
	PlayerSettingsStore.delete_settings(TEST_ROOT)


func test_runtime_integration() -> void:
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Player-settings-aware runtime scene must load.")
	if not packed is PackedScene:
		return
	var runtime: Node = (packed as PackedScene).instantiate()
	check(runtime != null, "Player-settings-aware runtime scene must instantiate.")
	if runtime == null:
		return
	root.add_child(runtime)
	await process_frame

	check(bool(runtime.call("player_settings_contract_ok")), "Runtime player settings and input bindings must satisfy the versioned model contract.")
	var title_value: Variant = runtime.call("title_menu")
	var title_entries: Array = title_value as Array if typeof(title_value) == TYPE_ARRAY else []
	check(title_entries.has("OPTIONS"), "Title menu must expose Options.")
	check(int(runtime.call("player_settings_entry_count")) == 13, "Runtime Options surface must expose every authored row.")

	var custom: Dictionary = PlayerSettings.default_settings()
	custom["master_volume"] = 0.8
	custom["music_volume"] = 0.5
	custom["ambience_volume"] = 0.25
	custom["sfx_volume"] = 0.75
	custom["screen_texture_intensity"] = 0.25
	custom["camera_shake_intensity"] = 0.0
	custom["environment_motion_intensity"] = 0.0
	custom["flash_intensity"] = 0.5
	custom["show_action_prompts"] = false
	custom["high_contrast_ui"] = true
	runtime.set("player_settings", PlayerSettings.sanitize(custom))
	check(bool(runtime.call("apply_input_bindings")), "Runtime must keep InputMap synchronized after settings replacement.")

	var overlay: Node = runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	check(overlay != null, "Playable scene must include the settings-aware presentation overlay.")
	var controls_overlay: Node = runtime.get_node_or_null("PresentationLayer/PlayerControlsOverlay")
	check(controls_overlay != null, "Playable scene must include the remapping-aware controls overlay.")
	if controls_overlay != null:
		check(bool(controls_overlay.call("control_remapping_overlay_contract_ok")), "Controls overlay must preserve dynamic control hint contracts.")
	if overlay != null:
		check(bool(overlay.call("player_settings_overlay_contract_ok")), "Presentation overlay must preserve all inherited contracts while applying player settings.")
		var prompt_value: Variant = overlay.call("resolve_context_prompt")
		var prompt: Dictionary = prompt_value as Dictionary if typeof(prompt_value) == TYPE_DICTIONARY else {}
		check(prompt.is_empty(), "Disabled action prompts must suppress prompt selection before drawing.")
		overlay.set("shake_strength", 0.0)
		overlay.set("shake_timer", 0.0)
		overlay.call("trigger_shake", 5.0, 0.3)
		check(is_equal_approx(float(overlay.get("shake_strength")), 0.0), "Zero camera-shake intensity must prevent new shake.")
		check(not bool(overlay.call("environment_spawn_allowed")), "Zero world-motion intensity must suppress new movement disturbances.")
		var contrast_value: Variant = overlay.call("profile_color", "ui_text", "eee3c6")
		var contrast: Color = contrast_value if contrast_value is Color else Color.BLACK
		check(contrast.is_equal_approx(Color("ffffff")), "High-contrast UI must resolve white interface text.")

	var audio: Node = runtime.get_node_or_null("AudioMood")
	check(audio != null, "Playable scene must include settings-aware AudioMood.")
	if audio != null:
		audio.call("apply_player_volume_settings")
		var volume_value: Variant = audio.call("player_volume_snapshot")
		var volume: Dictionary = volume_value as Dictionary if typeof(volume_value) == TYPE_DICTIONARY else {}
		check(is_equal_approx(float(volume.get("music", 0.0)), 0.4), "Music gain must combine master and music settings.")
		check(is_equal_approx(float(volume.get("ambience", 0.0)), 0.2), "Ambience gain must combine master and ambience settings.")
		check(is_equal_approx(float(volume.get("sfx", 0.0)), 0.6), "SFX gain must combine master and SFX settings.")
		check(bool(audio.call("player_settings_audio_contract_ok")), "Audio players must apply the current player gain settings exactly.")

	runtime.call("change_flow", 4)
	runtime.set("transition_lock", 0.0)
	runtime.set("dialogue", "")
	runtime.set("active_cinematic_id", "")
	check(bool(runtime.call("open_player_settings")), "Options must open during safe gameplay.")
	check(bool(runtime.get("player_settings_open")), "Options open state must be explicit.")
	check(not bool(runtime.call("can_open_save_overlay")), "Manual saving must remain blocked while Options is open.")
	check(not bool(runtime.call("can_flush_autosave")), "Autosave must defer while Options is open.")
	if overlay != null:
		check(bool(overlay.call("animation_should_freeze")), "Options must freeze animation and environment time.")

	runtime.set("player_settings_index", 0)
	check(bool(runtime.call("adjust_selected_player_setting", -1)), "Left adjustment must change the selected numeric setting.")
	check(is_equal_approx(float(runtime.call("player_setting_number", "master_volume", 1.0)), 0.7), "Master volume must step from eighty to seventy percent.")
	runtime.set("player_settings_index", 8)
	check(bool(runtime.call("activate_selected_player_setting")), "Confirm must toggle a selected boolean setting.")
	check(bool(runtime.call("player_setting_bool", "show_action_prompts", false)), "Action prompts must toggle back on.")
	runtime.set("player_settings_index", 11)
	check(bool(runtime.call("activate_selected_player_setting")), "Reset All Defaults must activate.")
	check(is_equal_approx(float(runtime.call("player_setting_number", "master_volume", 0.0)), 1.0), "Reset All Defaults must restore master volume.")
	check(bool(runtime.call("player_setting_bool", "show_action_prompts", false)), "Reset All Defaults must restore action prompts.")
	check(PlayerInputBindings.input_map_matches(runtime.call("input_binding_profile")), "Reset All Defaults must also restore and apply default controls.")

	# Persistence is exercised against isolated stores above. Avoid touching a
	# developer's real user://settings while still verifying the runtime close path.
	runtime.set("player_settings_dirty", false)
	check(bool(runtime.call("close_player_settings")), "Options must close cleanly when no write is pending.")
	check(not bool(runtime.get("player_settings_open")), "Closing Options must restore the previous flow without changing campaign state.")

	root.remove_child(runtime)
	runtime.free()


func dictionary_field(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Player settings smoke test passed: schema migration, isolated atomic storage, backup recovery, Options controls, persistent remapping, accessibility presentation and audio gains are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
