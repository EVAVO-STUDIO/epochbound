extends SceneTree

const CampaignAudit = preload("res://src/content/campaign_audit.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var campaign: Dictionary = {
		"id": "audit_edge",
		"start_map": "start",
		"base_capabilities": [],
		"starting_equipment": {},
		"starting_inventory": [],
		"starting_quests": [],
		"save_policy": {
			"manual_slots": 0,
			"autosave_enabled": false,
			"autosave_on_travel": false,
			"autosave_on_progress": false,
			"allow_manual_save_in_combat": false
		}
	}
	var maps: Dictionary = {
		"start": {
			"id": "start",
			"connections": [{
				"id": "to_locked",
				"target_map": "locked",
				"required_capabilities": ["missing_capability"]
			}],
			"interactions": []
		},
		"locked": {"id": "locked", "connections": [], "interactions": []},
		"orphan": {"id": "orphan", "connections": [], "interactions": []}
	}
	var story: Dictionary = {
		"quests": {
			"orphan_quest": {"id": "orphan_quest", "auto_start": false}
		},
		"conversations": {}
	}
	var report: Dictionary = CampaignAudit.audit_loaded(campaign, maps, {}, story, {"currencies": {}, "merchants": {}})
	check(int(report.get("blocker_count", 0)) >= 5, "Synthetic audit must surface multiple independent blockers.")
	check(has_code(report, "map.unreachable"), "Unreachable maps must be reported.")
	check(has_code(report, "travel.no_exit"), "Maps without exits must be reported.")
	check(has_code(report, "capability.no_source"), "Required capabilities without a source must be reported.")
	check(has_code(report, "economy.no_restorative_source"), "Campaigns without healing recovery must be reported.")
	check(has_code(report, "quest.no_start_path"), "Quests without a start path must be reported.")
	check(has_code(report, "save.no_path"), "Campaigns without any save path must be reported.")
	finish()


func has_code(report: Dictionary, code: String) -> bool:
	for finding_value in report.get("findings", []):
		if typeof(finding_value) == TYPE_DICTIONARY and str((finding_value as Dictionary).get("code", "")) == code:
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Campaign audit edge smoke test passed: unreachable maps, missing capability sources, recovery, quest and save blockers are detected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
