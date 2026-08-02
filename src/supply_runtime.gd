extends "res://src/presentation_runtime_current.gd"

const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyValidator = preload("res://src/content/supply_region_validator.gd")
const SupplyModel = preload("res://src/game/supply_region_model.gd")
const SupplySaveProfile = preload("res://src/content/save_profile.gd")
const SupplySaveStore = preload("res://src/content/save_profile_store.gd")

var supply_region_definitions: Dictionary = {}
var supply_region_cycles: Dictionary = {}
var supply_regions_initialized := false
var last_supply_delivery: Dictionary = {}


func load_campaign(path: String) -> bool:
	var validation := SupplyValidator.validate_campaign_path(path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		push_error("Regional supply validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	clear_supply_state()
	return super.load_campaign(path)


func load_fallback_campaign() -> void:
	clear_supply_state()
	supply_region_definitions = {
		"local_route": SupplyCatalog.default_region("local_route", "Local Supply Route", 180.0, 4)
	}
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
			supply_region_definitions = {
				"local_route": SupplyCatalog.default_region("local_route", "Local Supply Route", 180.0, 4)
			}
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
		return {
			"changed": false,
			"cycles_advanced": 0,
			"total_added": 0,
			"regions": [],
			"merchant_additions": {}
		}
	var result := SupplyModel.apply_due_restock(
		merchant_stock,
		merchant_definitions,
		supply_region_definitions,
		supply_region_cycles,
		play_time_seconds
	)
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
	var region_id := SupplyCatalog.merchant_region_id(merchant_data)
	return SupplyCatalog.region(supply_region_definitions, region_id)


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
	return "%s  •  SUPPLY %s" % [
		SupplyCatalog.region_name(supply_region_definitions, region_id).to_upper(),
		SupplyCatalog.format_duration(SupplyModel.seconds_until_next_cycle(region_data, play_time_seconds))
	]


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
	var validation := SupplyValidator.validate_profile(profile, campaign_path)
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
	var validation := SupplyValidator.validate_profile(profile, target_campaign_path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		set_save_notice("Profile rejected: %s" % load_error, 2.6)
		return false
	clear_supply_state()
	var loaded := super.apply_save_profile(profile, target_campaign_path)
	if not loaded:
		return false
	var payload: Dictionary = profile.get("payload", {})
	supply_region_cycles = SupplyModel.sanitize_cycles(
		payload.get("supply_region_cycles", {}),
		supply_region_definitions,
		play_time_seconds
	)
	supply_regions_initialized = true
	var delivery := apply_due_supply_restock()
	if bool(delivery.get("changed", false)):
		request_autosave("Regional supply caught up")
	last_durable_fingerprint = durable_progress_fingerprint()
	return true


func durable_progress_fingerprint() -> String:
	return SupplySaveProfile.canonical_json({
		"base": super.durable_progress_fingerprint(),
		"supply_region_cycles": supply_region_cycles
	})


func draw_merchant_overlay() -> void:
	super.draw_merchant_overlay()
	if active_merchant_id.is_empty():
		return
	draw_string(
		ThemeDB.fallback_font,
		Vector2(330, 68),
		supply_region_status_text(),
		HORIZONTAL_ALIGNMENT_RIGHT,
		248,
		8,
		Color("91a6a1")
	)


func supply_runtime_contract_ok() -> bool:
	if not supply_regions_initialized:
		return false
	for region_id_value in supply_region_definitions.keys():
		if not supply_region_cycles.has(str(region_id_value)):
			return false
	return true
