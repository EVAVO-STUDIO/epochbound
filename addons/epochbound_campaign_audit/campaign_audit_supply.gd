@tool
extends "res://addons/epochbound_campaign_audit/campaign_audit_studio.gd"

const SupplyCampaignAudit = preload("res://src/content/supply_campaign_audit.gd")


func run_audit_for_path(campaign_path: String) -> Dictionary:
	current_campaign_path = campaign_path
	last_report = SupplyCampaignAudit.audit_campaign_path(campaign_path)
	if is_instance_valid(findings_tree):
		render_report(last_report)
	return last_report


func render_report(report: Dictionary) -> void:
	super.render_report(report)
	var metrics_value: Variant = report.get("metrics", {})
	var metrics: Dictionary = metrics_value if typeof(metrics_value) == TYPE_DICTIONARY else {}
	metrics_label.text += "\nSupply regions %d   •   Renewable stock %d" % [
		int(metrics.get("supply_region_count", 0)),
		int(metrics.get("renewable_stock_count", 0))
	]
