extends SceneTree

const TemporalShiftAudit = preload("res://src/content/temporal_shift_audit.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var maps := {
		"palette_only": {
			"id": "palette_only",
			"eras": [
				{"id": "verdant", "palette": {"ground": "446644"}},
				{"id": "ashen", "palette": {"ground": "55443f"}}
			],
			"terrain_cells": [],
			"collision_cells": [],
			"navigation_cells": [],
			"entry_points": [],
			"connections": [],
			"recovery_anchors": [],
			"interactions": [],
			"companion_cues": [],
			"object_placements": [],
			"encounter_zones": []
		},
		"authored_shift": {
			"id": "authored_shift",
			"eras": [
				{"id": "verdant", "palette": {"ground": "446644"}},
				{"id": "ashen", "palette": {"ground": "55443f"}}
			],
			"terrain_cells": [
				{"x": 4, "y": 7, "tile": "collapsed_bridge", "available_eras": ["ashen"]}
			],
			"collision_cells": [],
			"navigation_cells": [],
			"entry_points": [],
			"connections": [],
			"recovery_anchors": [],
			"interactions": [
				{
					"id": "dated_marker",
					"available_eras": [],
					"dialogue": {
						"verdant": "The marker names a year that has not happened.",
						"ashen": "The same year has been burned out of the stone."
					}
				}
			],
			"companion_cues": [],
			"object_placements": [
				{"id": "verdant_witness", "object_id": "witness", "available_eras": ["verdant"]},
				{"id": "ashen_hunter", "object_id": "hunter", "available_eras": ["ashen"]},
				{"id": "verdant_cache", "object_id": "cache", "available_eras": ["verdant"]}
			],
			"encounter_zones": [
				{"id": "ashen_hunt", "available_eras": ["ashen"]}
			]
		}
	}
	var objects := {
		"witness": {"id": "witness", "kind": "npc"},
		"hunter": {"id": "hunter", "kind": "enemy"},
		"cache": {
			"id": "cache",
			"kind": "pickup",
			"item_grants": [{"item_id": "test_resource", "quantity": 1}]
		}
	}

	var first_findings: Array[Dictionary] = []
	var first_metrics := TemporalShiftAudit.audit(maps, objects, first_findings)
	check(int(first_metrics.get("multi_era_map_count", 0)) == 2, "Both synthetic maps must be recognised as multi-era maps.")
	check(int(first_metrics.get("meaningful_shift_map_count", 0)) == 1, "Only the map with authored consequences must pass the meaningful-shift probe.")
	check(int(first_metrics.get("temporal_route_count", 0)) >= 1, "Era-scoped traversal data must count as a route consequence.")
	check(int(first_metrics.get("temporal_threat_count", 0)) >= 1, "Era-scoped enemies or encounter zones must count as a threat consequence.")
	check(int(first_metrics.get("temporal_information_count", 0)) >= 1, "Distinct era dialogue must count as an information consequence.")
	check(int(first_metrics.get("temporal_relationship_count", 0)) >= 1, "Era-scoped NPC presence must count as a relationship consequence.")
	check(int(first_metrics.get("temporal_resource_count", 0)) >= 1, "Era-scoped pickups must count as a resource consequence.")
	check(
		has_code_context(first_findings, "temporal.palette_only", "palette_only"),
		"A multi-era map with palette changes only must publish the stable temporal.palette_only warning."
	)
	check(
		not has_code_context(first_findings, "temporal.palette_only", "authored_shift"),
		"A map with authored route, threat, information, relationship and resource consequences must remain warning-free."
	)

	var second_findings: Array[Dictionary] = []
	var second_metrics := TemporalShiftAudit.audit(maps, objects, second_findings)
	check(
		JSON.stringify({"metrics": first_metrics, "findings": first_findings})
		== JSON.stringify({"metrics": second_metrics, "findings": second_findings}),
		"Repeated temporal audits must produce deterministic evidence and findings."
	)
	finish()


func has_code_context(findings: Array[Dictionary], code: String, context: String) -> bool:
	for finding in findings:
		if str(finding.get("code", "")) == code and str(finding.get("context", "")) == context:
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Temporal shift audit smoke test passed: palette-only maps warn while route, threat, information, relationship and resource consequences remain deterministic.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
