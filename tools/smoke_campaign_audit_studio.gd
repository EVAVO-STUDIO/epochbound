extends SceneTree

const CampaignAuditStudio = preload("res://addons/epochbound_campaign_audit/campaign_audit_studio.gd")
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const EXPORT_PATH := "user://audit_test/reference-audit.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var studio := CampaignAuditStudio.new()
	root.add_child(studio)
	var report: Dictionary = studio.run_audit_for_path(CAMPAIGN_PATH)
	check(str(report.get("campaign_id", "")) == "epochbound_demo", "Audit Studio must load the selected campaign.")
	check(int(report.get("blocker_count", -1)) == 0, "Audit Studio must surface the reference campaign without blockers.")
	var export_result: Dictionary = studio.export_last_report_to(EXPORT_PATH)
	check(bool(export_result.get("ok", false)), "Audit Studio must export its current report.")
	check(FileAccess.file_exists(EXPORT_PATH), "Exported audit JSON must exist in user storage.")
	if FileAccess.file_exists(EXPORT_PATH):
		var parser := JSON.new()
		var file := FileAccess.open(EXPORT_PATH, FileAccess.READ)
		check(file != null and parser.parse(file.get_as_text()) == OK, "Exported audit JSON must parse cleanly.")
		if parser.data is Dictionary:
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
