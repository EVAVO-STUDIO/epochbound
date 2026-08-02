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
		"starting_recipes": [],
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
			"interactions": [
				{"id": "double_gate", "conditions": [{"type": "has_item", "item_id": "gate_key", "quantity": 2}]},
				{"id": "cost_gate", "conditions": [{"type": "has_item", "item_id": "costly_pass", "quantity": 1}]},
				{"id": "cycle_gate_a", "conditions": [{"type": "has_item", "item_id": "cycle_key", "quantity": 1}]},
				{"id": "cycle_gate_b", "conditions": [{"type": "has_item", "item_id": "cycle_part", "quantity": 1}]},
				{"id": "unbound_gate", "conditions": [{"type": "has_item", "item_id": "unbound_pass", "quantity": 1}]},
				{"id": "missing_gate", "conditions": [{"type": "has_item", "item_id": "missing_relic", "quantity": 1}]}
			],
			"object_placements": [{"id": "vendor", "object_id": "locked_vendor", "available_eras": []}]
		},
		"locked": {"id": "locked", "connections": [], "interactions": [], "object_placements": []},
		"orphan": {"id": "orphan", "connections": [], "interactions": [], "object_placements": []}
	}
	var items: Dictionary = {
		"gate_key": {"id": "gate_key", "kind": "key", "stack_limit": 9, "value": 5},
		"costly_pass": {"id": "costly_pass", "kind": "key", "stack_limit": 1, "value": 90},
		"cycle_key": {"id": "cycle_key", "kind": "material", "stack_limit": 9, "value": 1},
		"cycle_part": {"id": "cycle_part", "kind": "material", "stack_limit": 9, "value": 1},
		"unbound_pass": {"id": "unbound_pass", "kind": "key", "stack_limit": 1, "value": 4},
		"self_lamp": {
			"id": "self_lamp",
			"kind": "equipment",
			"stack_limit": 1,
			"value": 40,
			"equipment": {"slot": "tool", "capabilities": ["illuminate_dark"]}
		}
	}
	var recipes: Dictionary = {
		"cycle_key_recipe": {
			"id": "cycle_key_recipe",
			"ingredients": [{"item_id": "cycle_part", "quantity": 1}],
			"output": {"item_id": "cycle_key", "quantity": 1},
			"unlocked_by_default": true
		},
		"cycle_part_recipe": {
			"id": "cycle_part_recipe",
			"ingredients": [{"item_id": "cycle_key", "quantity": 1}],
			"output": {"item_id": "cycle_part", "quantity": 1},
			"unlocked_by_default": true
		}
	}
	var story: Dictionary = {
		"quests": {"orphan_quest": {"id": "orphan_quest", "auto_start": false}},
		"conversations": {}
	}
	var economy: Dictionary = {
		"currencies": {
			"tokens": {"id": "tokens", "display_name": "Tokens", "symbol": "TK", "starting_balance": 10, "max_balance": 999}
		},
		"merchants": {
			"locked_vendor": {
				"id": "locked_vendor",
				"currency_id": "tokens",
				"buy_multiplier": 1.0,
				"conditions": [{"type": "has_capability", "capability_id": "illuminate_dark"}],
				"stock": [
					{"item_id": "gate_key", "quantity": 1, "unlimited": false, "buy_price": 5, "conditions": []},
					{"item_id": "costly_pass", "quantity": 1, "unlimited": false, "buy_price": 90, "conditions": []},
					{"item_id": "self_lamp", "quantity": 1, "unlimited": false, "buy_price": 40, "conditions": []}
				]
			},
			"ghost_vendor": {
				"id": "ghost_vendor",
				"currency_id": "tokens",
				"buy_multiplier": 1.0,
				"conditions": [],
				"stock": [{"item_id": "unbound_pass", "quantity": 1, "unlimited": false, "buy_price": 4, "conditions": []}]
			}
		}
	}
	var objects: Dictionary = {
		"locked_vendor": {"id": "locked_vendor", "kind": "npc", "merchant_id": "locked_vendor"}
	}
	var report: Dictionary = CampaignAudit.audit_loaded(campaign, maps, items, story, economy, recipes, objects)
	check(int(report.get("probe_count", 0)) == 8, "Synthetic audit must execute all eight probes.")
	check(int(report.get("blocker_count", 0)) >= 10, "Synthetic audit must surface multiple independent blockers.")
	check(has_code(report, "map.unreachable"), "Unreachable maps must be reported.")
	check(has_code(report, "travel.no_exit"), "Maps without exits must be reported.")
	check(has_code(report, "capability.no_source"), "Required capabilities without a definition must be reported.")
	check(has_code(report, "economy.no_restorative_source"), "Campaigns without healing recovery must be reported.")
	check(has_code(report, "quest.no_start_path"), "Quests without a start path must be reported.")
	check(has_code(report, "save.no_path"), "Campaigns without any save path must be reported.")
	check(has_code(report, "progression.recipe_cycle"), "Circular recipe dependencies must be reported.")
	check(has_code(report, "progression.item_no_source"), "Progression items with no viable source must be reported.")
	check(has_code(report, "progression.insufficient_finite_supply"), "Finite stock below the required quantity must be reported.")
	check(has_code(report, "progression.merchant_source_unbound"), "Merchant-only sources without an NPC binding must be reported.")
	check(has_code(report, "progression.capability_self_lock"), "Capabilities sold behind their own gate must be reported.")
	check(has_code(report, "economy.progression_item_not_for_sale"), "Merchant sources unable to supply the required quantity must be reported.")
	check(has_code(report, "economy.progression_purchase_unaffordable"), "Unaffordable merchant-only progression items must be reported.")
	check(has_code(report, "economy.capability_purchase_unaffordable"), "Unaffordable merchant-only capability items must be reported.")
	var metrics: Dictionary = report.get("metrics", {})
	check(int(metrics.get("progression_item_count", 0)) == 6, "Synthetic audit must trace all six explicit progression items.")
	check(int(metrics.get("progression_capability_count", 0)) == 2, "Synthetic audit must trace both required capabilities.")
	check(int(metrics.get("merchant_only_progression_count", 0)) >= 3, "Synthetic audit must identify merchant-only item and capability routes.")
	check(int(metrics.get("affordability_risk_count", 0)) >= 3, "Synthetic audit must count item and capability affordability findings.")
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
		print("Campaign audit edge smoke test passed: reachability, source absence, finite stock, merchant bindings, recipe cycles, self-gates, affordability, quest and save blockers are detected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
