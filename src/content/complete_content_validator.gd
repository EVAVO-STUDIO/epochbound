@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/sprite_animation_strict_validator.gd")
const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyValidator = preload("res://src/content/supply_region_validator.gd")
const MultiplayerValidator = preload("res://src/content/multiplayer_area_validator.gd")
const LocalisationValidator = preload("res://src/content/localisation_validator.gd")


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report := BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var region_count := 0
	var renewable_count := 0
	var multiplayer_campaign_count := 0
	var multiplayer_area_count := 0
	var pvp_area_count := 0
	var localisation_locale_count := 0
	var localisation_message_count := 0
	var ui_localisation_report := LocalisationValidator.validate_ui_only()
	append_messages(errors, ui_localisation_report.get("errors", []))
	append_messages(warnings, ui_localisation_report.get("warnings", []))
	localisation_locale_count += int(ui_localisation_report.get("localisation_locale_count", 0))
	localisation_message_count += int(ui_localisation_report.get("localisation_message_count", 0))
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var path := str((value as Dictionary).get("path", ""))
		var supply_report := SupplyValidator.validate_supply_only(path)
		append_messages(errors, supply_report.get("errors", []))
		append_messages(warnings, supply_report.get("warnings", []))
		region_count += int(supply_report.get("supply_region_count", 0))
		renewable_count += int(supply_report.get("renewable_stock_count", 0))
		var multiplayer_report := MultiplayerValidator.validate_multiplayer_only(path)
		append_messages(errors, multiplayer_report.get("errors", []))
		append_messages(warnings, multiplayer_report.get("warnings", []))
		multiplayer_campaign_count += int(multiplayer_report.get("multiplayer_campaign_count", 0))
		multiplayer_area_count += int(multiplayer_report.get("multiplayer_area_count", 0))
		pvp_area_count += int(multiplayer_report.get("pvp_area_count", 0))
		var localisation_report := LocalisationValidator.validate_localisation_only(path)
		append_messages(errors, localisation_report.get("errors", []))
		append_messages(warnings, localisation_report.get("warnings", []))
		localisation_message_count += int(localisation_report.get("campaign_localisation_message_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["supply_region_count"] = region_count
	output["renewable_stock_count"] = renewable_count
	output["multiplayer_campaign_count"] = multiplayer_campaign_count
	output["multiplayer_area_count"] = multiplayer_area_count
	output["pvp_area_count"] = pvp_area_count
	output["localisation_locale_count"] = localisation_locale_count
	output["localisation_message_count"] = localisation_message_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_campaign_path(campaign_path)
	var supply_report := SupplyValidator.validate_supply_only(campaign_path)
	var multiplayer_report := MultiplayerValidator.validate_multiplayer_only(campaign_path)
	var localisation_report := LocalisationValidator.validate_localisation_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, supply_report.get("errors", []))
	append_messages(errors, multiplayer_report.get("errors", []))
	append_messages(errors, localisation_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, supply_report.get("warnings", []))
	append_messages(warnings, multiplayer_report.get("warnings", []))
	append_messages(warnings, localisation_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["supply_region_count"] = supply_report.get("supply_region_count", 0)
	output["renewable_stock_count"] = supply_report.get("renewable_stock_count", 0)
	output["multiplayer_campaign_count"] = multiplayer_report.get("multiplayer_campaign_count", 0)
	output["multiplayer_area_count"] = multiplayer_report.get("multiplayer_area_count", 0)
	output["pvp_area_count"] = multiplayer_report.get("pvp_area_count", 0)
	output["localisation_locale_count"] = localisation_report.get("localisation_locale_count", 0)
	output["localisation_message_count"] = localisation_report.get("campaign_localisation_message_count", 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_profile(profile, campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings}
	var campaign: Dictionary = campaign_result.get("data", {})
	var supply_result := SupplyCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, supply_result.get("errors", []))
	var metadata_value: Variant = profile.get("metadata", {})
	var metadata: Dictionary = metadata_value if typeof(metadata_value) == TYPE_DICTIONARY else {}
	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) == TYPE_DICTIONARY:
		var payload: Dictionary = payload_value
		SupplyValidator.validate_profile_supply(
			payload,
			supply_result.get("definitions", {}),
			maxf(0.0, float(metadata.get("play_time_seconds", 0.0))),
			errors,
			warnings
		)
		MultiplayerValidator.validate_profile_multiplayer(payload, errors)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
