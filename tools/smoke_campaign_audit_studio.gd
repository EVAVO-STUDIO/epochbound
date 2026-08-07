extends SceneTree

const CampaignAuditStudio = preload("res://addons/epochbound_campaign_audit/campaign_audit_supply.gd")
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const EXPORT_PATH := "user://audit_test/reference-audit.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var studio: Control = CampaignAuditStudio.new()
	root.add_child(studio)
	var report_value: Variant = studio.call("run_audit_for_path", CAMPAIGN_PATH)
	var report: Dictionary = report_value if typeof(report_value) == TYPE_DICTIONARY else {}
	check(str(report.get("campaign_id", "")) == "epochbound_demo", "Audit Studio must load the selected campaign.")
	check(int(report.get("probe_count", 0)) == 9, "Audit Studio must expose all nine production probes.")
	check(int(report.get("blocker_count", -1)) == 0, "Audit Studio must surface the reference campaign without blockers.")
	var metrics: Dictionary = report.get("metrics", {})
	check(int(metrics.get("supply_region_count", 0)) == 2, "Audit Studio report must preserve both supply routes.")
	check(int(metrics.get("renewable_stock_count", 0)) == 5, "Audit Studio report must preserve renewable stock evidence.")
	check(int(metrics.get("multi_era_map_count", 0)) == 3, "Audit Studio report must inspect all three multi-era maps.")
	check(int(metrics.get("meaningful_shift_map_count", 0)) == 3, "Audit Studio report must preserve meaningful temporal evidence for every reference map.")
	var metrics_label: Label = studio.get("metrics_label") as Label
	check(metrics_label != null, "Audit Studio must expose its metrics summary.")
	if metrics_label != null:
		check(metrics_label.text.contains("Progression items"), "Audit Studio must display progression-source metrics.")
		check(metrics_label.text.contains("Affordability risks"), "Audit Studio must display affordability metrics.")
		check(metrics_label.text.contains("Supply regions 2"), "Audit Studio must display supply-route metrics.")
		check(metrics_label.text.contains("Renewable stock 5"), "Audit Studio must display renewable-stock metrics.")
		check(metrics_label.text.contains("Temporal maps 3/3 authored"), "Audit Studio must display meaningful temporal map coverage.")
		check(metrics_label.text.contains("Temporal outcomes"), "Audit Studio must display bounded temporal outcome evidence.")
	var export_value: Variant = studio.call("export_last_report_to", EXPORT_PATH)
	var export_result: Dictionary = export_value if typeof(export_value) == TYPE_DICTIONARY else {}
	check(bool(export_result.get("ok", false)), "Audit Studio must export its current report.")
	check(FileAccess.file_exists(EXPORT_PATH), "Exported audit JSON must exist in user storage.")
	if FileAccess.file_exists(EXPORT_PATH):
		var parser: JSON = JSON.new()
		var file: FileAccess = FileAccess.open(EXPORT_PATH, FileAccess.READ)
		check(file != null and parser.parse(file.get_as_text()) == OK, "Exported audit JSON must parse cleanly.")
		if typeof(parser.data) == TYPE_DICTIONARY:
			var exported: Dictionary = parser.data as Dictionary
			check(str(exported.get("campaign_id", "")) == "epochbound_demo", "Exported report must preserve campaign identity.")
			check(int(exported.get("probe_count", 0)) == 9, "Exported report must preserve the expanded probe count.")
			var exported_metrics: Dictionary = exported.get("metrics", {})
			check(int(exported_metrics.get("supply_region_count", 0)) == 2, "Exported report must preserve supply-route evidence.")
	DirAccess.remove_absolute(EXPORT_PATH)
	root.remove_child(studio)
	studio.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Campaign Audit Studio smoke test passed: selection, nine-probe progression and temporal metrics, supply evidence, rendering state and JSON export are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
