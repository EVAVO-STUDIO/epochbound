extends SceneTree

const CampaignAudit = preload("res://src/content/supply_campaign_audit.gd")
const CompleteValidator = preload("res://src/content/complete_content_validator.gd")
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var validation: Dictionary = CompleteValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference content must remain structurally valid.")
	check(
		(validation.get("errors", []) as Array).is_empty(),
		"Reference content validation must publish zero errors."
	)
	check(
		(validation.get("warnings", []) as Array).is_empty(),
		"Reference content validation must remain warning-free."
	)

	var first: Dictionary = CampaignAudit.audit_campaign_path(CAMPAIGN_PATH)
	var second: Dictionary = CampaignAudit.audit_campaign_path(CAMPAIGN_PATH)
	check(int(first.get("probe_count", 0)) == 10, "Reference audit must execute all ten production probes.")
	check(int(first.get("blocker_count", -1)) == 0, "Reference campaign must have no audit blockers.")
	check(int(first.get("warning_count", -1)) == 0, "Reference campaign audit must remain warning-free.")
	var metrics: Dictionary = first.get("metrics", {})
	check(int(metrics.get("map_count", 0)) == 4, "Reference audit must inspect all four maps.")
	check(int(metrics.get("reachable_map_count", 0)) == 4, "Every reference map must be structurally reachable.")
	check(int(metrics.get("quest_count", 0)) == 2, "Reference audit must inspect both authored quests.")
	check(int(metrics.get("restorative_source_count", 0)) >= 1, "Reference campaign must expose a restorative source.")
	check(int(metrics.get("progression_item_count", 0)) >= 3, "Reference audit must trace the Clockglass Lens and its progression ingredients.")
	check(
		int(metrics.get("required_capability_count", 0)) == 1,
		"Reference audit must trace only the journey-critical Illuminate Dark capability."
	)
	check(
		int(metrics.get("optional_capability_count", 0)) == 2,
		"Reference audit must retain the two optional Underworks exploration gates."
	)
	check(int(metrics.get("multi_era_map_count", 0)) == 4, "Reference audit must inspect all four multi-era maps.")
	check(int(metrics.get("meaningful_shift_map_count", 0)) == 4, "Every reference map must author at least one meaningful temporal consequence.")
	check(int(metrics.get("temporal_outcome_count", 0)) >= 8, "Reference maps must publish bounded temporal consequence evidence.")
	check(int(metrics.get("temporal_route_count", 0)) >= 2, "Reference shifts must alter traversal in Bellweather and Clockwood.")
	check(int(metrics.get("temporal_threat_count", 0)) >= 3, "Reference shifts must retain threat variation across the three dangerous maps.")
	check(int(metrics.get("temporal_information_count", 0)) >= 3, "Reference shifts must expose different information across the authored world.")
	check(int(metrics.get("temporal_relationship_count", 0)) >= 2, "Reference shifts must alter NPC presence in Bellweather and Clockwood.")
	check(int(metrics.get("temporal_resource_count", 0)) >= 1, "Reference shifts must alter at least one authored resource source.")
	check(
		int(metrics.get("progression_capability_count", 0)) == 1,
		"Progression-source analysis must not promote optional lore gates."
	)
	check(
		int(metrics.get("progression_source_risk_count", -1)) == 0,
		"Reference progression sources must remain warning-free."
	)
	check(
		int(metrics.get("merchant_only_progression_count", -1)) == 0,
		"Reference progression must not rely exclusively on merchant purchases."
	)
	check(
		int(metrics.get("affordability_risk_count", -1)) == 0,
		"Reference progression affordability must remain warning-free."
	)
	check(int(metrics.get("economy_starting_choice_count", 0)) == 4, "Reference starting wallet must support four executable preparation choices.")
	check(int(metrics.get("economy_recovery_safe_choice_count", 0)) == 4, "Every reference opening purchase must retain a recovery route.")
	check(int(metrics.get("economy_preparation_category_count", 0)) == 3, "Reference opening purchases must cover recovery, material and ammunition choices.")
	check(int(metrics.get("economy_repeatable_arbitrage_count", -1)) == 0, "Reference merchants must expose no repeatable positive-currency loop.")
	check(int(metrics.get("economy_balance_risk_count", -1)) == 0, "Reference economy simulation must remain warning-free.")
	check(int(metrics.get("economy_renewable_recovery_units", 0)) == 20, "Reference routes must provide twenty healing units per deterministic thirty-minute horizon.")
	check(int(metrics.get("economy_renewable_ammo_units", 0)) == 80, "Reference routes must provide eighty ammunition units per deterministic thirty-minute horizon.")
	check(int(metrics.get("economy_finite_progression_stock_count", 0)) == 3, "Reference economy must retain three finite non-renewable equipment offers.")
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
		print("Reference release readiness smoke test passed: complete content and all ten campaign probes, including meaningful temporal shifts, are deterministic with zero blockers, errors or warnings.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
