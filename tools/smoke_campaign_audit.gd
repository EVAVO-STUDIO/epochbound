extends SceneTree

const CampaignAudit = preload("res://src/content/supply_campaign_audit.gd")
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var first: Dictionary = CampaignAudit.audit_campaign_path(CAMPAIGN_PATH)
	var second: Dictionary = CampaignAudit.audit_campaign_path(CAMPAIGN_PATH)
	check(int(first.get("probe_count", 0)) == 8, "Reference audit must execute all eight production probes.")
	check(int(first.get("blocker_count", -1)) == 0, "Reference campaign must have no audit blockers.")
	var metrics: Dictionary = first.get("metrics", {})
	check(int(metrics.get("map_count", 0)) == 3, "Reference audit must inspect all three maps.")
	check(int(metrics.get("reachable_map_count", 0)) == 3, "Every reference map must be structurally reachable.")
	check(int(metrics.get("quest_count", 0)) == 2, "Reference audit must inspect both authored quests.")
	check(int(metrics.get("restorative_source_count", 0)) >= 1, "Reference campaign must expose a restorative source.")
	check(int(metrics.get("progression_item_count", 0)) >= 3, "Reference audit must trace the Clockglass Lens and its progression ingredients.")
	check(int(metrics.get("progression_capability_count", 0)) >= 2, "Reference audit must trace authored capability gates.")
	check(int(metrics.get("progression_source_risk_count", -1)) >= 0, "Reference audit must publish progression-source metrics.")
	check(int(metrics.get("merchant_only_progression_count", -1)) >= 0, "Reference audit must publish merchant-only progression metrics.")
	check(int(metrics.get("affordability_risk_count", -1)) >= 0, "Reference audit must publish affordability metrics.")
	check(int(metrics.get("supply_region_count", 0)) == 2, "Reference audit must publish both regional supply routes.")
	check(int(metrics.get("renewable_stock_count", 0)) == 5, "Reference audit must publish all renewable stock entries.")
	check(JSON.stringify(first) == JSON.stringify(second), "Repeated audits must produce deterministic JSON output.")
	check(findings_are_sorted(first.get("findings", [])), "Audit findings must remain sorted by severity rank and stable code.")
	finish()


func findings_are_sorted(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var previous := ""
	for finding_value in value:
		if typeof(finding_value) != TYPE_DICTIONARY:
			return false
		var finding: Dictionary = finding_value
		var key: String = CampaignAudit.finding_key(finding)
		if not previous.is_empty() and previous.naturalnocasecmp_to(key) > 0:
			return false
		previous = key
	return true


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Campaign audit smoke test passed: reference reachability, capability, economy, progression-source, affordability, regional supply, quest and save probes are deterministic.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
