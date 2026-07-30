extends SceneTree

const CampaignAuditStudio = preload("res://addons/epochbound_campaign_audit/campaign_audit_studio.gd")
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
	check(int(report.get("blocker_count", -1)) == 0, "Audit Studio must surface the reference campaign without blockers.")
	var export_value: Variant = studio.call("export_last_report_to", EXPORT_PATH)
	var export_result: Dictionary = export_value if typeof(export_value) == TYPE_DICTIONARY else {}
	check(bool(export_result.get("ok", false)), "Audit Studio must export its current report.")
	check(FileAccess.file_exists(EXPORT_PATH), "Exported audit JSON must exist in user storage.")
	if FileAccess.file_exists(EXPORT_PATH):
		var parser: JSON = JSON.new()
		var file: FileAccess = FileAccess.open(EXPORT_PATH, FileAccess.READ)
		check(file != null and parser.parse(file.get_as_text()) == OK, "Exported audit JSON must parse cleanly.")
		if typeof(parser.data) == TYPE_DICTIONARY:
			check(str((parser.data as Dictionary).get("campaign_id", "")) == "epochbound_demo", "Exported report must preserve campaign identity.")
	DirAccess.remove_absolute(EXPORT_PATH)
	root.remove_child(studio)
	studio.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Campaign Audit Studio smoke test passed: selection, rendering state and JSON export are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
