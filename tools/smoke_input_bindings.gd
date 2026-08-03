extends SceneTree

const PlayerInputBindings = preload("res://src/game/player_input_bindings.gd")
const PlayerSettings = preload("res://src/game/player_settings.gd")
const PlayerSettingsStore = preload("res://src/game/player_settings_store.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const TEST_ROOT := "user://epochbound_test_input_bindings"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	test_binding_model()
	test_atomic_binding_persistence()
	await test_runtime_controls()
	PlayerInputBindings.apply_profile(PlayerInputBindings.default_profile())
	PlayerSettingsStore.delete_settings(TEST_ROOT)
	finish()


func profile_with_modified_attack(profile_value: Variant) -> Dictionary:
	var profile: Dictionary = (profile_value as Dictionary).duplicate(true) if typeof(profile_value) == TYPE_DICTIONARY else PlayerInputBindings.default_profile()
	var actions_value: Variant = profile.get("actions", {})
	var actions: Dictionary = (actions_value as Dictionary).duplicate(true) if typeof(actions_value) == TYPE_DICTIONARY else {}
	actions["attack"] = [
		PlayerInputBindings.key_descriptor(84, true),
		PlayerInputBindings.button_descriptor(1)
	]
	profile["actions"] = actions
	return profile


func test_binding_model() -> void:
	var defaults := PlayerInputBindings.default_profile()
	check(bool(PlayerInputBindings.validate_profile(defaults).get("ok", false)), "Default keyboard and controller bindings must validate.")
	check(PlayerInputBindings.managed_action_ids().size() == 14, "Control remapping must cover all fourteen gameplay actions.")
	check(PlayerInputBindings.device_binding_text(defaults, "move_up", PlayerInputBindings.DEVICE_KEYBOARD) == "W / UP", "Movement defaults must retain both WASD and arrow-key access.")
	check("LS UP" in PlayerInputBindings.device_binding_text(defaults, "move_up", PlayerInputBindings.DEVICE_GAMEPAD), "Movement defaults must retain analogue left-stick input.")
	check(PlayerInputBindings.descriptor_is_reserved(PlayerInputBindings.key_descriptor(PlayerInputBindings.RESERVED_ESCAPE_PHYSICAL)), "Escape must remain reserved for cancel and Pause recovery.")
	check(PlayerInputBindings.descriptor_is_reserved(PlayerInputBindings.key_descriptor(PlayerInputBindings.RESERVED_OPTIONS_PHYSICAL)), "O must remain reserved for direct Options recovery.")
	check(PlayerInputBindings.descriptor_is_reserved(PlayerInputBindings.button_descriptor(PlayerInputBindings.RESERVED_START_BUTTON)), "Start must remain reserved for Pause recovery.")

	var captured_key := InputEventKey.new()
	captured_key.pressed = true
	captured_key.physical_keycode = 84
	check(PlayerInputBindings.binding_label(PlayerInputBindings.descriptor_from_event(captured_key)) == "T", "Physical keyboard capture must produce a readable key label.")
	var modified_key := InputEventKey.new()
	modified_key.pressed = true
	modified_key.physical_keycode = 84
	modified_key.shift_pressed = true
	check(PlayerInputBindings.event_uses_modifiers(modified_key), "Keyboard capture must detect modifier chords before InputMap matching.")
	var modified_descriptor := PlayerInputBindings.descriptor_from_event(modified_key)
	check(not modified_descriptor.is_empty(), "Modifier capture must retain enough evidence to consume and explain the rejected event.")
	check(PlayerInputBindings.descriptor_is_reserved(modified_descriptor), "Modifier chords must be consumed by the same guarded capture path as recovery inputs.")
	check("non-exact InputMap matching" in PlayerInputBindings.reserved_descriptor_message(modified_descriptor), "Modifier rejection must explain Godot's non-exact action-matching constraint.")
	var modified_rebind := PlayerInputBindings.rebind(defaults, "attack", PlayerInputBindings.DEVICE_KEYBOARD, PlayerInputBindings.key_descriptor(84, true))
	check(not bool(modified_rebind.get("ok", true)), "Stored or programmatic modifier chords must be rejected rather than creating overlapping actions.")
	var invalid_profile := profile_with_modified_attack(defaults)
	check(not bool(PlayerInputBindings.validate_profile(invalid_profile).get("ok", true)), "A complete profile containing a modifier chord must fail validation.")
	check(bool(PlayerInputBindings.apply_profile(defaults).get("ok", false)), "Fail-closed application setup must install the known-good defaults.")
	var invalid_apply := PlayerInputBindings.apply_profile(invalid_profile)
	check(not bool(invalid_apply.get("ok", true)), "Invalid modifier profiles must fail before InputMap mutation.")
	check(PlayerInputBindings.input_map_matches(defaults), "Rejected modifier profiles must leave the previous complete InputMap unchanged.")
	check(not PlayerInputBindings.input_map_matches(invalid_profile), "An invalid modifier profile must never be reported as matching InputMap.")

	var quiet_axis := InputEventJoypadMotion.new()
	quiet_axis.axis = 0
	quiet_axis.axis_value = 0.25
	check(PlayerInputBindings.descriptor_from_event(quiet_axis).is_empty(), "Small analogue noise must not become a binding.")
	var active_axis := InputEventJoypadMotion.new()
	active_axis.axis = 0
	active_axis.axis_value = -0.9
	check(PlayerInputBindings.binding_label(PlayerInputBindings.descriptor_from_event(active_axis)) == "LS LEFT", "Deliberate analogue motion must capture its direction.")

	var swap := PlayerInputBindings.rebind(defaults, "attack", PlayerInputBindings.DEVICE_KEYBOARD, PlayerInputBindings.key_descriptor(70))
	check(bool(swap.get("ok", false)), "A valid keyboard binding must be accepted.")
	check(str(swap.get("swapped_with", "")) == "companion_recall", "Binding a used key must swap with its previous action instead of creating a duplicate.")
	var swapped: Dictionary = swap.get("profile", {})
	check(PlayerInputBindings.device_binding_text(swapped, "attack", PlayerInputBindings.DEVICE_KEYBOARD) == "F", "The requested action must receive the captured key.")
	check("SPACE" in PlayerInputBindings.device_binding_text(swapped, "companion_recall", PlayerInputBindings.DEVICE_KEYBOARD), "The displaced action must inherit the target action's previous keyboard access.")
	check(bool(PlayerInputBindings.validate_profile(swapped).get("ok", false)), "Conflict-safe swaps must leave a complete unique binding profile.")
	check(bool(PlayerInputBindings.apply_profile(swapped).get("ok", false)), "A valid profile must apply through InputMap.")
	check(PlayerInputBindings.input_map_matches(swapped), "InputMap must exactly match the persisted binding profile after application.")
	PlayerInputBindings.apply_profile(defaults)


func test_atomic_binding_persistence() -> void:
	PlayerSettingsStore.delete_settings(TEST_ROOT)
	var settings := PlayerSettings.default_settings()
	var rebound := PlayerInputBindings.rebind(PlayerSettings.input_bindings(settings), "attack", PlayerInputBindings.DEVICE_KEYBOARD, PlayerInputBindings.key_descriptor(84))
	check(bool(rebound.get("ok", false)), "Persistence setup must create a valid custom control profile.")
	settings["input_bindings"] = rebound.get("profile", PlayerInputBindings.default_profile())
	var write := PlayerSettingsStore.write_settings(settings, TEST_ROOT)
	check(bool(write.get("ok", false)), "Custom controls must write through the existing atomic player-settings store.")
	var read := PlayerSettingsStore.load_settings(TEST_ROOT)
	check(bool(read.get("ok", false)), "Custom controls must load from the isolated player-settings store.")
	var loaded_settings: Dictionary = read.get("settings", {})
	check(PlayerInputBindings.device_binding_text(PlayerSettings.input_bindings(loaded_settings), "attack", PlayerInputBindings.DEVICE_KEYBOARD) == "T", "Atomic persistence must retain the custom keyboard binding exactly.")

	var invalid_settings := loaded_settings.duplicate(true)
	invalid_settings["input_bindings"] = profile_with_modified_attack(PlayerSettings.input_bindings(loaded_settings))
	var rejected_write := PlayerSettingsStore.write_settings(invalid_settings, TEST_ROOT)
	check(not bool(rejected_write.get("ok", true)), "Atomic settings writes must reject malformed controls before rotating the valid primary file.")
	check(not FileAccess.file_exists(PlayerSettingsStore.temp_path(TEST_ROOT)), "Rejected control writes must not leave a temporary settings file.")
	var after_rejection := PlayerSettingsStore.load_settings(TEST_ROOT)
	var retained_settings: Dictionary = after_rejection.get("settings", {})
	check(PlayerInputBindings.device_binding_text(PlayerSettings.input_bindings(retained_settings), "attack", PlayerInputBindings.DEVICE_KEYBOARD) == "T", "A rejected control write must preserve the previous complete primary profile.")
	PlayerSettingsStore.delete_settings(TEST_ROOT)


func test_runtime_controls() -> void:
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Control-remapping runtime scene must load.")
	if not packed is PackedScene:
		return
	var runtime: Node = (packed as PackedScene).instantiate()
	check(runtime != null, "Control-remapping runtime scene must instantiate.")
	if runtime == null:
		return
	root.add_child(runtime)
	await process_frame

	runtime.set("player_settings", PlayerSettings.default_settings())
	check(bool(runtime.call("apply_input_bindings")), "Runtime must apply the default binding profile.")
	check(bool(runtime.call("input_binding_cache_contract_ok")), "Runtime must build complete validated binding, row and prompt caches.")
	check(bool(runtime.call("control_bindings_contract_ok")), "Runtime control bindings must satisfy the complete InputMap contract.")
	check(int(runtime.call("player_settings_entry_count")) == 13, "Options must expose ten adjustable values, Controls, Reset All Defaults and Back.")
	var initial_cache_revision := int(runtime.get("input_binding_cache_revision"))
	check(initial_cache_revision > 0, "Applying a profile must create a positive binding-cache revision.")
	for _index in range(64):
		runtime.call("input_action_hint", "interact")
		runtime.call("input_action_hint", "attack")
		runtime.call("input_action_device_hint", "reload_weapon", PlayerInputBindings.DEVICE_GAMEPAD)
		runtime.call("control_binding_entries")
	check(int(runtime.get("input_binding_cache_revision")) == initial_cache_revision, "Repeated draw-time hint and row reads must not rebuild the binding profile cache.")

	var presentation_overlay: Node = runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	check(presentation_overlay != null, "Playable scene must retain the combat readability presentation overlay.")
	var controls_overlay: Node = runtime.get_node_or_null("PresentationLayer/PlayerControlsOverlay")
	check(controls_overlay != null, "Playable scene must include the remapping-aware control overlay.")
	if controls_overlay != null:
		check(str(controls_overlay.get_script().resource_path) == "res://src/player_controls_overlay.gd", "Playable scene must bind the remapping-aware control overlay.")
		check(bool(controls_overlay.call("control_remapping_overlay_contract_ok")), "Control overlay must preserve every inherited presentation contract.")

	runtime.call("change_flow", 4)
	runtime.set("transition_lock", 0.0)
	runtime.set("dialogue", "")
	runtime.set("active_cinematic_id", "")
	check(bool(runtime.call("open_player_settings")), "Options must open during safe gameplay for control editing.")
	runtime.set("player_settings_index", 10)
	check(bool(runtime.call("activate_selected_player_setting")), "The Controls row must open the binding editor.")
	check(bool(runtime.get("control_bindings_open")), "Control binding editor state must be explicit.")
	var visible_rows: Array = runtime.call("player_settings_rows")
	check(visible_rows.size() == 12, "The binding editor must use a bounded twelve-row window at 640 by 360.")
	check(runtime.call("control_binding_entries").size() == 16, "The binding editor must expose fourteen gameplay actions plus Reset and Back.")

	check(bool(runtime.call("begin_control_capture", "attack", PlayerInputBindings.DEVICE_KEYBOARD)), "A gameplay action must enter keyboard capture mode.")
	var capture := InputEventKey.new()
	capture.pressed = true
	capture.physical_keycode = 84
	check(bool(runtime.call("handle_control_capture_event", capture)), "A deliberate keyboard press must be consumed by capture mode.")
	check(not bool(runtime.get("control_capture_active")), "Successful capture must end listening mode.")
	check(str(runtime.call("input_action_device_hint", "attack", PlayerInputBindings.DEVICE_KEYBOARD)) == "T", "Runtime hints must update immediately after rebinding.")
	check(binding_row_value(runtime.call("control_binding_entries"), "attack") == "T", "Cached Controls rows must update immediately after rebinding.")
	check(PlayerInputBindings.input_map_matches(runtime.call("input_binding_profile")), "Runtime InputMap must remain synchronized after a capture.")
	var rebound_cache_revision := int(runtime.get("input_binding_cache_revision"))
	check(rebound_cache_revision > initial_cache_revision, "A successful capture must rebuild the binding caches exactly when the profile changes.")
	for _index in range(64):
		runtime.call("input_action_hint", "attack")
		runtime.call("input_action_device_hint", "attack", PlayerInputBindings.DEVICE_KEYBOARD)
	check(int(runtime.get("input_binding_cache_revision")) == rebound_cache_revision, "Cached post-rebind hints must remain stable across repeated draw reads.")

	check(bool(runtime.call("begin_control_capture", "attack", PlayerInputBindings.DEVICE_KEYBOARD)), "Keyboard capture must be reusable for modifier rejection.")
	var modified := InputEventKey.new()
	modified.pressed = true
	modified.physical_keycode = 84
	modified.shift_pressed = true
	check(bool(runtime.call("handle_control_capture_event", modified)), "Modifier chords must be consumed rather than leaking into a non-exact gameplay action.")
	check(bool(runtime.get("control_capture_active")), "A rejected modifier chord must leave capture active for one physical key.")
	check("MODIFIER CHORDS" in str(runtime.get("player_settings_notice")), "Modifier rejection must explain the physical-key-only rule.")
	check(int(runtime.get("input_binding_cache_revision")) == rebound_cache_revision, "Rejected modifier chords must not mutate or rebuild the active binding caches.")
	runtime.call("cancel_control_capture", false)

	check(bool(runtime.call("begin_control_capture", "attack", PlayerInputBindings.DEVICE_KEYBOARD)), "Keyboard capture must be reusable for recovery-input rejection.")
	var reserved := InputEventKey.new()
	reserved.pressed = true
	reserved.physical_keycode = PlayerInputBindings.RESERVED_OPTIONS_PHYSICAL
	check(bool(runtime.call("handle_control_capture_event", reserved)), "Reserved recovery inputs must be consumed rather than leaking into gameplay.")
	check(bool(runtime.get("control_capture_active")), "A reserved input must leave capture active for another valid choice.")
	check("RESERVED" in str(runtime.get("player_settings_notice")), "Reserved-input feedback must explain the recovery rule.")
	check(int(runtime.get("input_binding_cache_revision")) == rebound_cache_revision, "Rejected reserved input must not rebuild or mutate the active binding caches.")
	runtime.call("cancel_control_capture", false)

	check(bool(runtime.call("reset_control_bindings")), "Reset Controls must restore the authored default profile.")
	check("SPACE" in str(runtime.call("input_action_device_hint", "attack", PlayerInputBindings.DEVICE_KEYBOARD)), "Reset Controls must restore the default attack keys.")
	check(int(runtime.get("input_binding_cache_revision")) > rebound_cache_revision, "Reset Controls must invalidate and rebuild every cached hint and row.")
	check(bool(runtime.call("close_control_bindings")), "Back must return from Controls to the parent Options screen.")
	runtime.set("player_settings_dirty", false)
	check(bool(runtime.call("close_player_settings")), "Options must close without writing to the developer's real settings path during the regression.")

	root.remove_child(runtime)
	runtime.free()


func binding_row_value(value: Variant, action_id: String) -> String:
	if typeof(value) != TYPE_ARRAY:
		return ""
	for row_value in value as Array:
		if typeof(row_value) == TYPE_DICTIONARY and str((row_value as Dictionary).get("id", "")) == action_id:
			return str((row_value as Dictionary).get("value", ""))
	return ""


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Input binding smoke test passed: schema migration, fail-closed atomic persistence, fixed recovery inputs, physical-key-only capture, conflict-safe swaps, analogue thresholds, cached dynamic hints and runtime InputMap application are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
