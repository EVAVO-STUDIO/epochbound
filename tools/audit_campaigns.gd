extends SceneTree

const CampaignAudit = preload("res://src/content/supply_campaign_audit.gd")


func _initialize() -> void:
	var report: Dictionary = CampaignAudit.audit_all()
	for campaign_value in report.get("reports", []):
		if typeof(campaign_value) != TYPE_DICTIONARY:
			continue
		var campaign_report: Dictionary = campaign_value
		print("Audit %s: %d blocker(s), %d warning(s)." % [
			str(campaign_report.get("campaign_id", "campaign")),
			int(campaign_report.get("blocker_count", 0)),
			int(campaign_report.get("warning_count", 0))
		])
		for finding_value in campaign_report.get("findings", []):
			if typeof(finding_value) != TYPE_DICTIONARY:
				continue
			var finding: Dictionary = finding_value
			var line := "[%s] %s %s: %s" % [
				str(finding.get("severity", "info")).to_upper(),
				str(finding.get("code", "")),
				str(finding.get("context", "")),
				str(finding.get("message", ""))
			]
			if str(finding.get("severity", "")) == "blocker":
				push_error(line)
			else:
				print_rich("[color=yellow]%s[/color]" % line)
	quit(0 if bool(report.get("ok", false)) else 1)
