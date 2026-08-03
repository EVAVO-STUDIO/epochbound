@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/sprite_animation_strict_validator.gd")
const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyValidator = preload("res://src/content/supply_region_validator.gd")


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report := BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var region_count := 0
	var renewable_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := SupplyValidator.validate_supply_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		region_count += int(report.get("supply_region_count", 0))
		renewable_count += int(report.get("renewable_stock_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["supply_region_count"] = region_count
	output["renewable_stock_count"] = renewable_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_campaign_path(campaign_path)
	var supply_report := SupplyValidator.validate_supply_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, supply_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, supply_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["supply_region_count"] = supply_report.get("supply_region_count", 0)
	output["renewable_stock_count"] = supply_report.get("renewable_stock_count", 0)
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
		SupplyValidator.validate_profile_supply(
			payload_value as Dictionary,
			supply_result.get("definitions", {}),
			maxf(0.0, float(metadata.get("play_time_seconds", 0.0))),
			errors,
			warnings
		)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
