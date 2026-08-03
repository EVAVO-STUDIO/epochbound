@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseAudit = preload("res://src/content/campaign_audit.gd")
const SupplyValidator = preload("res://src/content/supply_region_validator.gd")


static func audit_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var reports: Array[Dictionary] = []
	var blocker_count := 0
	var warning_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := audit_campaign_path(str((value as Dictionary).get("path", "")))
		reports.append(report)
		blocker_count += int(report.get("blocker_count", 0))
		warning_count += int(report.get("warning_count", 0))
	return {
		"ok": blocker_count == 0,
		"campaign_count": reports.size(),
		"blocker_count": blocker_count,
		"warning_count": warning_count,
		"reports": reports
	}


static func audit_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseAudit.audit_campaign_path(campaign_path)
	var findings: Array[Dictionary] = []
	for finding_value in base_report.get("findings", []):
		if typeof(finding_value) == TYPE_DICTIONARY:
			findings.append((finding_value as Dictionary).duplicate(true))
	var supply_report := SupplyValidator.validate_supply_only(campaign_path)
	for error_value in supply_report.get("errors", []):
		findings.append({
			"severity": "blocker",
			"code": "supply.invalid",
			"message": str(error_value),
			"context": campaign_path
		})
	for warning_value in supply_report.get("warnings", []):
		findings.append({
			"severity": "warning",
			"code": "supply.review",
			"message": str(warning_value),
			"context": campaign_path
		})
	var metrics_value: Variant = base_report.get("metrics", {})
	var metrics: Dictionary = metrics_value.duplicate(true) if typeof(metrics_value) == TYPE_DICTIONARY else {}
	metrics["supply_region_count"] = int(supply_report.get("supply_region_count", 0))
	metrics["renewable_stock_count"] = int(supply_report.get("renewable_stock_count", 0))
	return BaseAudit.build_report(str(base_report.get("campaign_id", campaign_path)), findings, metrics)


static func audit_loaded(
	campaign: Dictionary,
	maps: Dictionary,
	items: Dictionary,
	story: Dictionary,
	economy: Dictionary,
	recipes: Dictionary = {},
	objects: Dictionary = {}
) -> Dictionary:
	return BaseAudit.audit_loaded(campaign, maps, items, story, economy, recipes, objects)


static func finding_key(finding: Dictionary) -> String:
	return BaseAudit.finding_key(finding)
