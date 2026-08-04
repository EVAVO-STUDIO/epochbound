extends "res://src/presentation_runtime_base.gd"

const PlayerInputBindings = preload("res://src/game/player_input_bindings.gd")
const ControlsPlayerSettingsStore = preload("res://src/game/player_settings_store.gd")
const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const CompleteValidator = preload("res://src/content/complete_content_validator.gd")
const SupplyModel = preload("res://src/game/supply_region_model.gd")
const SupplySaveProfile = preload("res://src/content/save_profile.gd")
const SupplySaveStore = preload("res://src/content/save_profile_store.gd")

const CONTROL_VISIBLE_ROWS := 12
const CONTROL_NOTICE_DURATION := 2.2

var control_bindings_open := false
var control_binding_index := 0
var control_binding_device := PlayerInputBindings.DEVICE_KEYBOARD
var control_capture_active := false
var control_capture_action_id := ""
var control_capture_device := ""
var control_return_index := 0
var control_window_start := 0
var control_capture_event_consumed := false

# Binding profiles are sanitised and validated only when settings actually
# change. Drawing and prompt code consume these bounded caches instead of
# rebuilding the full fourteen-action profile every frame.
var input_binding_profile_cache: Dictionary = {}
var input_action_hint_cache: Dictionary = {}
var input_device_hint_cache: Dictionary = {}
var control_binding_row_cache: Dictionary = {}
var input_binding_cache_revision := 0

var supply_region_definitions: Dictionary = {}
var supply_region_cycles: Dictionary = {}
var supply_regions_initialized := false
var last_supply_delivery: Dictionary = {}


func _ready() -> void:
	super._ready()
	# The virtual settings-load hook normally builds this during super._ready().
	# Keep a guarded fallback for stripped-down tests or custom runtime entry.
	if input_binding_profile_cache.is_empty():
		apply_input_bindings()


func _input(event: InputEvent) -> void:
	if handle_control_capture_event(event):
		control_capture_event_consumed = true
		get_viewport().set_input_as_handled()


func apply_player_settings_load_result(result: Dictionary) -> void:
	super.apply_player_settings_load_result(result)
	apply_input_bindings()


func apply_input_bindings() -> bool:
	var profile := PlayerSettings.input_bindings(player_settings)
	var result := PlayerInputBindings.apply_profile(profile)
	if not bool(result.get("ok", false)):
		player_settings_notice = "CONTROLS FAILED: %s" % format_errors(result.get("errors", []))
		player_settings_notice_timer = 3.0
		return false
	var applied_value: Variant = result.get("profile", profile)
	var applied: Dictionary = applied_value if typeof(applied_value) == TYPE_DICTIONARY else profile
	player_settings["input_bindings"] = applied.duplicate(true)
	rebuild_input_binding_cache(applied)
	return true


func rebuild_input_binding_cache(profile_value: Variant) -> void:
	var profile := PlayerInputBindings.sanitize_profile(profile_value)
	input_binding_profile_cache = profile.duplicate(true)
	input_action_hint_cache = {}
	input_device_hint_cache = {
		PlayerInputBindings.DEVICE_KEYBOARD: {},
		PlayerInputBindings.DEVICE_GAMEPAD: {}
	}
	var keyboard_rows: Array = []
	var gamepad_rows: Array = []
	var actions_value: Variant = profile.get("actions", {})
	var actions: Dictionary = actions_value if typeof(actions_value) == TYPE_DICTIONARY else {}
	for definition_value in PlayerInputBindings.action_definitions():
		if typeof(definition_value) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = definition_value
		var action_id := str(definition.get("id", ""))
		var label := str(definition.get("label", action_id)).to_upper()
		var events_value: Variant = actions.get(action_id, [])
		var events: Array = events_value if typeof(events_value) == TYPE_ARRAY else []
		var keyboard_text := PlayerInputBindings.device_binding_text_from_events(
			events,
			PlayerInputBindings.DEVICE_KEYBOARD
		)
		var gamepad_text := PlayerInputBindings.device_binding_text_from_events(
			events,
			PlayerInputBindings.DEVICE_GAMEPAD
		)
		input_action_hint_cache[action_id] = PlayerInputBindings.action_hint_from_events(events)
		var keyboard_cache: Dictionary = input_device_hint_cache.get(PlayerInputBindings.DEVICE_KEYBOARD, {})
		keyboard_cache[action_id] = keyboard_text
		input_device_hint_cache[PlayerInputBindings.DEVICE_KEYBOARD] = keyboard_cache
		var gamepad_cache: Dictionary = input_device_hint_cache.get(PlayerInputBindings.DEVICE_GAMEPAD, {})
		gamepad_cache[action_id] = gamepad_text
		input_device_hint_cache[PlayerInputBindings.DEVICE_GAMEPAD] = gamepad_cache
		keyboard_rows.append({"id": action_id, "label": label, "kind": "binding", "value": keyboard_text})
		gamepad_rows.append({"id": action_id, "label": label, "kind": "binding", "value": gamepad_text})
	control_binding_row_cache = {
		PlayerInputBindings.DEVICE_KEYBOARD: keyboard_rows,
		PlayerInputBindings.DEVICE_GAMEPAD: gamepad_rows
	}
	input_binding_cache_revision += 1


func update_player_settings_menu() -> void:
	if control_bindings_open:
		update_control_bindings_menu()
		return
	super.update_player_settings_menu()


func activate_selected_player_setting() -> bool:
	var definition := selected_player_setting_definition()
	var setting_id := str(definition.get("id", ""))
	if setting_id == "controls":
		return open_control_bindings()
	var activated := super.activate_selected_player_setting()
	if activated and setting_id == "reset_defaults":
		apply_input_bindings()
	return activated


func close_player_settings(root_path: String = ControlsPlayerSettingsStore.ROOT) -> bool:
	cancel_control_capture(false)
	control_bindings_open = false
	return super.close_player_settings(root_path)


func open_control_bindings() -> bool:
	if not player_settings_open:
		return false
	control_return_index = player_settings_index
	control_bindings_open = true
	control_binding_index = clampi(control_binding_index, 0, maxi(0, control_binding_entries().size() - 1))
	control_binding_device = PlayerInputBindings.DEVICE_KEYBOARD
	control_capture_active = false
	control_capture_action_id = ""
	control_capture_device = ""
	player_settings_notice = "LEFT / RIGHT CHOOSES KEYBOARD OR CONTROLLER"
	player_settings_notice_timer = CONTROL_NOTICE_DURATION
	return true


func close_control_bindings() -> bool:
	if not control_bindings_open:
		return false
	cancel_control_capture(false)
	control_bindings_open = false
	player_settings_index = clampi(control_return_index, 0, maxi(0, PlayerSettings.entries().size() - 1))
	player_settings_notice = "CONTROL CHANGES ARE PENDING SAVE" if player_settings_dirty else "CONTROLS UNCHANGED"
	player_settings_notice_timer = PLAYER_SETTINGS_NOTICE_DURATION
	return true


func update_control_bindings_menu() -> void:
	if control_capture_event_consumed:
		control_capture_event_consumed = false
		return
	if control_capture_active:
		return
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("options_menu") or Input.is_action_just_pressed("pause_game"):
		close_control_bindings()
		return
	var entries := control_binding_entries()
	if entries.is_empty():
		close_control_bindings()
		return
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
		control_binding_index = posmod(control_binding_index - 1, entries.size())
		return
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
		control_binding_index = posmod(control_binding_index + 1, entries.size())
		return
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left"):
		control_binding_device = PlayerInputBindings.DEVICE_KEYBOARD
		player_settings_notice = "KEYBOARD BINDINGS"
		player_settings_notice_timer = PLAYER_SETTINGS_NOTICE_DURATION
		return
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right"):
		control_binding_device = PlayerInputBindings.DEVICE_GAMEPAD
		player_settings_notice = "CONTROLLER BINDINGS"
		player_settings_notice_timer = PLAYER_SETTINGS_NOTICE_DURATION
		return
	if confirm() or Input.is_action_just_pressed("attack"):
		activate_selected_control_binding()


func cached_control_binding_rows(device: String) -> Array:
	if input_binding_profile_cache.is_empty():
		input_binding_profile()
	var rows_value: Variant = control_binding_row_cache.get(device, [])
	return (rows_value as Array).duplicate(true) if typeof(rows_value) == TYPE_ARRAY else []


func control_binding_entries() -> Array:
	var rows := cached_control_binding_rows(control_binding_device)
	rows.append({"id": "reset_controls", "label": "RESET CONTROLS", "kind": "action", "value": ""})
	rows.append({"id": "back", "label": "BACK TO OPTIONS", "kind": "action", "value": ""})
	return rows


func control_binding_rows() -> Array:
	var entries := control_binding_entries()
	if entries.is_empty():
		control_window_start = 0
		player_settings_index = 0
		return []
	control_binding_index = clampi(control_binding_index, 0, entries.size() - 1)
	var visible_count := mini(CONTROL_VISIBLE_ROWS, entries.size())
	control_window_start = clampi(control_binding_index - int(floor(float(visible_count) * 0.5)), 0, maxi(0, entries.size() - visible_count))
	player_settings_index = control_binding_index - control_window_start
	var output: Array = []
	for index in range(control_window_start, control_window_start + visible_count):
		output.append((entries[index] as Dictionary).duplicate(true))
	return output


func player_settings_rows() -> Array:
	if control_bindings_open:
		return control_binding_rows()
	return super.player_settings_rows()


func selected_control_binding_definition() -> Dictionary:
	var entries := control_binding_entries()
	if entries.is_empty():
		return {}
	control_binding_index = clampi(control_binding_index, 0, entries.size() - 1)
	return (entries[control_binding_index] as Dictionary).duplicate(true)


func activate_selected_control_binding() -> bool:
	var definition := selected_control_binding_definition()
	var entry_id := str(definition.get("id", ""))
	match entry_id:
		"reset_controls":
			return reset_control_bindings()
		"back":
			return close_control_bindings()
	if not PlayerInputBindings.managed_action_ids().has(entry_id):
		return false
	return begin_control_capture(entry_id, control_binding_device)


func begin_control_capture(action_id: String, device: String) -> bool:
	if not control_bindings_open or not PlayerInputBindings.managed_action_ids().has(action_id):
		return false
	if device not in [PlayerInputBindings.DEVICE_KEYBOARD, PlayerInputBindings.DEVICE_GAMEPAD]:
		return false
	control_capture_active = true
	control_capture_action_id = action_id
	control_capture_device = device
	player_settings_notice = "PRESS A KEY — ESC CANCELS" if device == PlayerInputBindings.DEVICE_KEYBOARD else "PRESS A BUTTON OR MOVE AN AXIS — START CANCELS"
	player_settings_notice_timer = 3600.0
	return true


func handle_control_capture_event(event: InputEvent) -> bool:
	if not player_settings_open or not control_bindings_open or not control_capture_active:
		return false
	if control_capture_cancel_event(event):
		cancel_control_capture(true)
		return true
	var descriptor := PlayerInputBindings.descriptor_from_event(event)
	if descriptor.is_empty():
		return false
	if PlayerInputBindings.descriptor_device(descriptor) != control_capture_device:
		player_settings_notice = "PRESS A KEY — ESC CANCELS" if control_capture_device == PlayerInputBindings.DEVICE_KEYBOARD else "PRESS A CONTROLLER INPUT — START CANCELS"
		return true
	if PlayerInputBindings.descriptor_is_reserved(descriptor):
		player_settings_notice = PlayerInputBindings.reserved_descriptor_message(descriptor).to_upper()
		player_settings_notice_timer = CONTROL_NOTICE_DURATION
		return true
	var rebound_action := control_capture_action_id
	var result := PlayerInputBindings.rebind(input_binding_profile(), rebound_action, control_capture_device, descriptor)
	if not bool(result.get("ok", false)):
		player_settings_notice = "BINDING FAILED: %s" % format_errors(result.get("errors", []))
		player_settings_notice_timer = CONTROL_NOTICE_DURATION
		return true
	player_settings["input_bindings"] = result.get("profile", input_binding_profile())
	player_settings_dirty = true
	apply_input_bindings()
	control_capture_active = false
	control_capture_action_id = ""
	control_capture_device = ""
	var swapped := str(result.get("swapped_with", ""))
	player_settings_notice = "%s  %s" % [PlayerInputBindings.action_label(rebound_action).to_upper(), PlayerInputBindings.binding_label(descriptor)]
	if not swapped.is_empty():
		player_settings_notice += "  •  SWAPPED WITH %s" % PlayerInputBindings.action_label(swapped).to_upper()
	player_settings_notice_timer = CONTROL_NOTICE_DURATION
	return true


func control_capture_cancel_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		var physical := int(key.physical_keycode)
		if physical <= 0:
			physical = int(key.keycode)
		return physical == PlayerInputBindings.RESERVED_ESCAPE_PHYSICAL
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return button.pressed and int(button.button_index) == PlayerInputBindings.RESERVED_START_BUTTON
	return false


func cancel_control_capture(show_notice: bool = true) -> void:
	if not control_capture_active:
		return
	control_capture_active = false
	control_capture_action_id = ""
	control_capture_device = ""
	if show_notice:
		player_settings_notice = "CONTROL CAPTURE CANCELLED"
		player_settings_notice_timer = PLAYER_SETTINGS_NOTICE_DURATION


func reset_control_bindings() -> bool:
	player_settings["input_bindings"] = PlayerInputBindings.default_profile()
	player_settings_dirty = true
	apply_input_bindings()
	player_settings_notice = "DEFAULT CONTROLS RESTORED"
	player_settings_notice_timer = CONTROL_NOTICE_DURATION
	return true


func input_binding_profile() -> Dictionary:
	if input_binding_profile_cache.is_empty():
		rebuild_input_binding_cache(PlayerSettings.input_bindings(player_settings))
	return input_binding_profile_cache.duplicate(true)


func input_action_hint(action_id: String) -> String:
	if input_binding_profile_cache.is_empty():
		input_binding_profile()
	if input_action_hint_cache.has(action_id):
		return str(input_action_hint_cache.get(action_id, ""))
	match action_id:
		"options_menu":
			return "O"
		"pause_game":
			return "ESC / START"
		"ui_cancel":
			return "ESC / B"
	return action_id.replace("_", " ").to_upper()


func input_action_device_hint(action_id: String, device: String) -> String:
	if input_binding_profile_cache.is_empty():
		input_binding_profile()
	if not input_action_hint_cache.has(action_id):
		return input_action_hint(action_id)
	var device_value: Variant = input_device_hint_cache.get(device, {})
	var device_cache: Dictionary = device_value if typeof(device_value) == TYPE_DICTIONARY else {}
	var cached := str(device_cache.get(action_id, ""))
	return cached if not cached.is_empty() else input_action_hint(action_id)


func control_binding_device_label() -> String:
	return "KEYBOARD" if control_binding_device == PlayerInputBindings.DEVICE_KEYBOARD else "CONTROLLER"


func input_binding_cache_contract_ok() -> bool:
	if input_binding_cache_revision <= 0 or input_binding_profile_cache.is_empty():
		return false
	if input_binding_profile_cache != PlayerSettings.input_bindings(player_settings):
		return false
	if not bool(PlayerInputBindings.validate_profile(input_binding_profile_cache).get("ok", false)):
		return false
	var actions := PlayerInputBindings.managed_action_ids()
	for action_id in actions:
		if str(input_action_hint_cache.get(action_id, "")).is_empty():
			return false
		for device in [PlayerInputBindings.DEVICE_KEYBOARD, PlayerInputBindings.DEVICE_GAMEPAD]:
			var device_value: Variant = input_device_hint_cache.get(device, {})
			if typeof(device_value) != TYPE_DICTIONARY or str((device_value as Dictionary).get(action_id, "")).is_empty():
				return false
	for device in [PlayerInputBindings.DEVICE_KEYBOARD, PlayerInputBindings.DEVICE_GAMEPAD]:
		var rows_value: Variant = control_binding_row_cache.get(device, [])
		if typeof(rows_value) != TYPE_ARRAY or (rows_value as Array).size() != actions.size():
			return false
	return true


func control_bindings_contract_ok() -> bool:
	var profile := input_binding_profile()
	return (
		input_binding_cache_contract_ok()
		and bool(PlayerInputBindings.validate_profile(profile).get("ok", false))
		and input_action_hint_cache.size() >= 14
		and PlayerInputBindings.input_map_matches(profile)
		and control_binding_device in [PlayerInputBindings.DEVICE_KEYBOARD, PlayerInputBindings.DEVICE_GAMEPAD]
		and control_binding_index >= 0
		and control_binding_index < control_binding_entries().size()
	)


func player_settings_contract_ok() -> bool:
	return super.player_settings_contract_ok() and control_bindings_contract_ok()


func draw_game() -> void:
	super.draw_game()
	if player_settings_open or not dialogue.is_empty() or inventory_open or story_journal_open or save_overlay_open or merchant_open:
		return
	draw_rect(Rect2(88, 333, 464, 24), Color(0.03, 0.04, 0.05, 0.88))
	draw_centered("%s USE   •   %s ATTACK   •   %s SHIFT" % [input_action_hint("interact"), input_action_hint("attack"), input_action_hint("era_shift")], 350, 8, Color("d7d0bd"))


func draw_title() -> void:
	super.draw_title()
	if player_settings_open:
		return
	draw_rect(Rect2(122, 319, 396, 32), Color(0.03, 0.04, 0.05, 0.86))
	draw_centered("%s  CONFIRM     ARROWS  SELECT" % input_action_hint("interact"), 339, 9, Color("68747e"))


func draw_pause() -> void:
	super.draw_pause()
	if player_settings_open:
		return
	draw_rect(Rect2(202, 168, 236, 30), Color("111820"))
	draw_centered("%s  OPTIONS" % input_action_hint("interact"), 187, 9, Color("bba76d"))


func load_campaign(path: String) -> bool:
	var validation := CompleteValidator.validate_campaign_path(path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		push_error("Complete campaign validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	clear_supply_state()
	return super.load_campaign(path)


func load_fallback_campaign() -> void:
	clear_supply_state()
	supply_region_definitions = {"local_route": SupplyCatalog.default_region("local_route", "Local Supply Route", 180.0, 4)}
	super.load_fallback_campaign()


func clear_supply_state() -> void:
	supply_region_definitions = {}
	supply_region_cycles = {}
	supply_regions_initialized = false
	last_supply_delivery = {}


func load_economy_catalogs() -> bool:
	if not super.load_economy_catalogs():
		return false
	if campaign_path.is_empty():
		if supply_region_definitions.is_empty():
			supply_region_definitions = {"local_route": SupplyCatalog.default_region("local_route", "Local Supply Route", 180.0, 4)}
		return true
	var result := SupplyCatalog.load_catalogs(campaign_path, campaign)
	if not bool(result.get("ok", false)):
		load_error = format_errors(result.get("errors", []))
		push_error("Supply region catalog load failed: %s" % load_error)
		return false
	supply_region_definitions = result.get("definitions", {})
	return true


func reset_economy_state() -> void:
	super.reset_economy_state()
	supply_region_cycles = SupplyModel.initial_cycles(supply_region_definitions, play_time_seconds)
	supply_regions_initialized = true
	last_supply_delivery = {}
	last_durable_fingerprint = durable_progress_fingerprint()


func update_game(delta: float) -> void:
	super.update_game(delta)
	if flow != Flow.GAME or merchant_open or save_operation_depth > 0:
		return
	var delivery := apply_due_supply_restock()
	if bool(delivery.get("changed", false)):
		record_supply_change(delivery, "Regional supply updated")


func open_merchant(merchant_id: String) -> bool:
	var delivery := apply_due_supply_restock()
	if bool(delivery.get("changed", false)):
		record_supply_change(delivery, "Regional supply updated")
	var opened := super.open_merchant(merchant_id)
	if not opened:
		return false
	var additions_value: Variant = delivery.get("merchant_additions", {})
	var additions: Dictionary = additions_value if typeof(additions_value) == TYPE_DICTIONARY else {}
	var added := int(additions.get(merchant_id, 0))
	if added > 0:
		var greeting := merchant_notice
		set_merchant_notice("SUPPLY DELIVERY +%d UNIT%s  •  %s" % [added, "" if added == 1 else "S", greeting], 2.4)
	return true


func apply_due_supply_restock() -> Dictionary:
	if not supply_regions_initialized or supply_region_definitions.is_empty():
		return {"changed": false, "cycles_advanced": 0, "total_added": 0, "regions": [], "merchant_additions": {}}
	var result := SupplyModel.apply_due_restock(merchant_stock, merchant_definitions, supply_region_definitions, supply_region_cycles, play_time_seconds)
	if int(result.get("total_added", 0)) > 0:
		last_supply_delivery = result.duplicate(true)
	return result


func record_supply_change(delivery: Dictionary, reason: String) -> void:
	if not bool(delivery.get("changed", false)):
		return
	last_durable_fingerprint = durable_progress_fingerprint()
	request_autosave(reason)


func active_supply_region() -> Dictionary:
	var merchant_data := active_merchant()
	return SupplyCatalog.region(supply_region_definitions, SupplyCatalog.merchant_region_id(merchant_data))


func supply_region_status_text(merchant_id: String = "") -> String:
	var resolved_id := merchant_id if not merchant_id.is_empty() else active_merchant_id
	var merchant_data := EconomyCatalog.merchant(merchant_definitions, resolved_id)
	if merchant_data.is_empty():
		return "STATIC STOCK"
	var region_id := SupplyCatalog.merchant_region_id(merchant_data)
	if region_id.is_empty():
		return "STATIC STOCK"
	var region_data := SupplyCatalog.region(supply_region_definitions, region_id)
	if region_data.is_empty():
		return "INVALID SUPPLY ROUTE"
	if not SupplyModel.merchant_has_renewable_stock(merchant_data):
		return "%s  •  SCARCE STOCK" % SupplyCatalog.region_name(supply_region_definitions, region_id).to_upper()
	return "%s  •  SUPPLY %s" % [SupplyCatalog.region_name(supply_region_definitions, region_id).to_upper(), SupplyCatalog.format_duration(SupplyModel.seconds_until_next_cycle(region_data, play_time_seconds))]


func capture_save_profile(slot_id: String, reason: String = "Manual save") -> Dictionary:
	var profile := super.capture_save_profile(slot_id, reason)
	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) == TYPE_DICTIONARY:
		var payload: Dictionary = payload_value
		payload["supply_region_cycles"] = supply_region_cycles.duplicate(true)
		payload["supply_regions_initialized"] = true
		profile["payload"] = payload
		SupplySaveProfile.refresh_checksum(profile)
	return profile


func save_current_profile(slot_id: String, reason: String) -> bool:
	if save_operation_depth > 0:
		return false
	var profile := capture_save_profile(slot_id, reason)
	var validation := CompleteValidator.validate_profile(profile, campaign_path)
	if not bool(validation.get("ok", false)):
		set_save_notice("Save validation failed: %s" % format_errors(validation.get("errors", [])), 2.4)
		return false
	var result := SupplySaveStore.write_profile(profile)
	if not bool(result.get("ok", false)):
		set_save_notice("Save failed: %s" % format_errors(result.get("errors", [])), 2.4)
		return false
	current_save_slot = slot_id
	pending_autosave_reason = ""
	last_durable_fingerprint = durable_progress_fingerprint()
	refresh_save_slot_cache()
	refresh_continue_profile()
	set_save_notice("%s SAVED" % SupplySaveProfile.slot_label(slot_id))
	return true


func apply_save_profile(profile: Dictionary, target_campaign_path: String) -> bool:
	var validation := CompleteValidator.validate_profile(profile, target_campaign_path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		set_save_notice("Profile rejected: %s" % load_error, 2.6)
		return false
	clear_supply_state()
	var loaded := super.apply_save_profile(profile, target_campaign_path)
	if not loaded:
		return false
	var payload: Dictionary = profile.get("payload", {})
	supply_region_cycles = SupplyModel.sanitize_cycles(payload.get("supply_region_cycles", {}), supply_region_definitions, play_time_seconds)
	supply_regions_initialized = true
	var delivery := apply_due_supply_restock()
	if bool(delivery.get("changed", false)):
		request_autosave("Regional supply caught up")
	last_durable_fingerprint = durable_progress_fingerprint()
	return true


func durable_progress_fingerprint() -> String:
	return SupplySaveProfile.canonical_json({"base": super.durable_progress_fingerprint(), "supply_region_cycles": supply_region_cycles})


func draw_merchant_overlay() -> void:
	super.draw_merchant_overlay()
	if active_merchant_id.is_empty():
		return
	draw_string(ThemeDB.fallback_font, Vector2(330, 68), supply_region_status_text(), HORIZONTAL_ALIGNMENT_RIGHT, 248, 8, Color("91a6a1"))


func supply_runtime_contract_ok() -> bool:
	if not supply_regions_initialized:
		return false
	for region_id in supply_region_definitions.keys():
		if not supply_region_cycles.has(str(region_id)):
			return false
	return true
