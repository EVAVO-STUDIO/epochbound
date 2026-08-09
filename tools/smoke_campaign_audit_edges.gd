extends SceneTree

const CampaignAudit = preload("res://src/content/campaign_audit.gd")
const CampaignValidator = preload("res://src/content/campaign_validator.gd")
const ProgressionSourceIndex = preload("res://src/content/progression_source_index.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var interaction_errors: Array[String] = []
	var interaction_warnings: Array[String] = []
	CampaignValidator._validate_interactions(
		[{
			"id": "bad_progression_flag",
			"position": {"x": 20, "y": 20},
			"radius": 12,
			"available_eras": [],
			"dialogue": "A valid interaction with one malformed classification flag.",
			"progression_required": "yes"
		}],
		"audit_edge_map",
		100,
		100,
		{"verdant": true},
		interaction_errors,
		interaction_warnings
	)
	check(
		has_message(interaction_errors, "progression_required must be boolean"),
		"Interaction progression classification must fail closed on non-boolean data."
	)

	var campaign: Dictionary = {
		"id": "audit_edge",
		"start_map": "start",
		"base_capabilities": [],
		"starting_equipment": {"tool": "starter_tool"},
		"starting_inventory": [
			{"item_id": "starter_tool", "quantity": 1},
			{"item_id": "formula_ingredient", "quantity": 1}
		],
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
				{"id": "missing_gate", "conditions": [{"type": "has_item", "item_id": "missing_relic", "quantity": 1}]},
				{"id": "starter_gate", "conditions": [{"type": "has_item", "item_id": "starter_tool", "quantity": 2}]},
				{"id": "optional_capability_gate", "required_capabilities": ["optional_sight"]},
				{"id": "boss_reward_gate", "conditions": [{"type": "has_item", "item_id": "boss_relic", "quantity": 1}]},
				{"id": "formula_gate", "conditions": [{"type": "has_item", "item_id": "locked_formula", "quantity": 1}]}
			],
			"object_placements": [
				{"id": "vendor", "object_id": "locked_vendor", "available_eras": []},
				{"id": "boss_reward", "object_id": "boss_reward", "available_eras": []}
			]
		},
		"locked": {"id": "locked", "connections": [], "interactions": [], "object_placements": []},
		"orphan": {
			"id": "orphan",
			"eras": [{"id": "verdant"}, {"id": "ashen"}],
			"connections": [],
			"interactions": [],
			"object_placements": []
		}
	}
	var items: Dictionary = {
		"gate_key": {"id": "gate_key", "kind": "key", "stack_limit": 9, "value": 5},
		"costly_pass": {"id": "costly_pass", "kind": "key", "stack_limit": 1, "value": 90},
		"cycle_key": {"id": "cycle_key", "kind": "material", "stack_limit": 9, "value": 1},
		"cycle_part": {"id": "cycle_part", "kind": "material", "stack_limit": 9, "value": 1},
		"unbound_pass": {"id": "unbound_pass", "kind": "key", "stack_limit": 1, "value": 4},
		"starter_tool": {
			"id": "starter_tool",
			"kind": "equipment",
			"stack_limit": 1,
			"value": 10,
			"equipment": {"slot": "tool", "capabilities": []}
		},
		"boss_relic": {"id": "boss_relic", "kind": "key", "stack_limit": 1, "value": 0},
		"locked_formula": {"id": "locked_formula", "kind": "key", "stack_limit": 1, "value": 0},
		"formula_ingredient": {"id": "formula_ingredient", "kind": "material", "stack_limit": 9, "value": 1},
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
		},
		"locked_formula_recipe": {
			"id": "locked_formula_recipe",
			"ingredients": [{"item_id": "formula_ingredient", "quantity": 1}],
			"output": {"item_id": "locked_formula", "quantity": 1},
			"unlocked_by_default": false
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
		"locked_vendor": {"id": "locked_vendor", "kind": "npc", "merchant_id": "locked_vendor"},
		"boss_reward": {
			"id": "boss_reward",
			"kind": "enemy",
			"boss": {
				"defeat_effects": [
					{"type": "grant_item", "item_id": "boss_relic", "quantity": 1}
				]
			}
		}
	}

	var merchant_bindings := ProgressionSourceIndex.merchant_binding_index(objects, maps)
	var source_index := ProgressionSourceIndex.build_item_source_index(
		campaign,
		maps,
		items,
		recipes,
		story,
		economy,
		objects,
		merchant_bindings
	)
	var starter_sources := ProgressionSourceIndex.usable_item_sources(
		ProgressionSourceIndex.source_array(source_index.get("starter_tool", []))
	)
	var starter_supply := ProgressionSourceIndex.finite_source_supply(starter_sources)
	check(not bool(starter_supply.get("unlimited", false)), "Starting equipment must remain a finite source.")
	check(int(starter_supply.get("quantity", 0)) == 1, "Starting equipment already present in starting inventory must not be counted twice.")
	check(has_source_context(source_index, "boss_relic", "start:boss_reward"), "Placed reusable boss defeat effects must count as authored item sources.")
	check(
		ProgressionSourceIndex.has_locked_recipe_source(
			ProgressionSourceIndex.source_array(source_index.get("locked_formula", []))
		),
		"A recipe with no default, starting or authored unlock route must remain unusable."
	)

	var unlock_index := ProgressionSourceIndex.build_item_source_index(
		{
			"starting_inventory": [{"item_id": "unlock_seed", "quantity": 1}],
			"starting_equipment": {},
			"starting_recipes": []
		},
		{
			"start": {
				"id": "start",
				"object_placements": [],
				"companion_cues": [
					{
						"id": "open_discovery",
						"unlock_recipes": ["open_recipe"]
					},
					{
						"id": "gated_discovery",
						"conditions": [{
							"type": "has_item",
							"item_id": "unlock_seed",
							"quantity": 1
						}],
						"unlock_recipes": ["gated_recipe"]
					}
				]
			}
		},
		{
			"unlock_seed": {"id": "unlock_seed"},
			"open_output": {"id": "open_output"},
			"gated_output": {"id": "gated_output"}
		},
		{
			"open_recipe": {
				"id": "open_recipe",
				"ingredients": [{"item_id": "unlock_seed", "quantity": 1}],
				"output": {"item_id": "open_output", "quantity": 1},
				"unlocked_by_default": false
			},
			"gated_recipe": {
				"id": "gated_recipe",
				"ingredients": [{"item_id": "unlock_seed", "quantity": 1}],
				"output": {"item_id": "gated_output", "quantity": 1},
				"unlocked_by_default": false
			}
		},
		{},
		{},
		{},
		{}
	)
	check(
		has_recipe_source_gate(unlock_index, "open_output", false),
		"Ungated exploration discoveries must publish an ungated recipe source."
	)
	check(
		has_recipe_source_gate(unlock_index, "gated_output", true),
		"Conditional discoveries must retain their authored recipe gate."
	)

	var report: Dictionary = CampaignAudit.audit_loaded(campaign, maps, items, story, economy, recipes, objects)
	check(int(report.get("probe_count", 0)) == 10, "Synthetic audit must execute all ten probes.")
	check(int(report.get("blocker_count", 0)) >= 12, "Synthetic audit must surface multiple independent blockers.")
	check(has_code(report, "map.unreachable"), "Unreachable maps must be reported.")
	check(has_code(report, "travel.no_exit"), "Maps without exits must be reported.")
	check(has_code(report, "capability.no_source"), "Required capabilities without a definition must be reported.")
	check(has_code(report, "economy.no_restorative_source"), "Campaigns without healing recovery must be reported.")
	check(has_code(report, "quest.no_start_path"), "Quests without a start path must be reported.")
	check(has_code(report, "save.no_path"), "Campaigns without any save path must be reported.")
	check(has_code_context(report, "temporal.palette_only", "orphan"), "Multi-era maps with palette-only differences must be reported for temporal review.")
	check(has_code(report, "progression.recipe_cycle"), "Circular recipe dependencies must be reported.")
	check(has_code(report, "progression.recipe_never_unlocked"), "Required recipe outputs without an unlock route must be reported.")
	check(has_code(report, "progression.item_no_source"), "Progression items with no viable source must be reported.")
	check(has_code_context(report, "progression.insufficient_finite_supply", "gate_key"), "Finite merchant stock below the required quantity must be reported.")
	check(has_code_context(report, "progression.insufficient_finite_supply", "starter_tool"), "Starting equipment must not inflate finite supply.")
	check(has_code(report, "progression.merchant_source_unbound"), "Merchant-only sources without an NPC binding must be reported.")
	check(has_code(report, "progression.capability_self_lock"), "Capabilities sold behind their own gate must be reported.")
	check(has_code(report, "economy.progression_item_not_for_sale"), "Merchant sources unable to supply the required quantity must be reported.")
	check(has_code(report, "economy.progression_purchase_unaffordable"), "Unaffordable merchant-only progression items must be reported.")
	check(has_code(report, "economy.capability_purchase_unaffordable"), "Unaffordable merchant-only capability items must be reported.")
	var metrics: Dictionary = report.get("metrics", {})
	check(
		int(metrics.get("progression_item_count", 0)) == 9,
		"Synthetic audit must trace the nine explicit mandatory item gates without inflating demand through a never-unlocked recipe."
	)
	check(int(metrics.get("progression_capability_count", 0)) == 2, "Synthetic audit must trace both required capabilities.")
	check(
		int(metrics.get("optional_capability_count", 0)) == 1,
		"Optional map interactions must remain visible without becoming progression requirements."
	)
	check(int(metrics.get("merchant_only_progression_count", 0)) >= 3, "Synthetic audit must identify merchant-only item and capability routes.")
	check(int(metrics.get("affordability_risk_count", 0)) >= 3, "Synthetic audit must count item and capability affordability findings.")
	check(int(metrics.get("economy_balance_risk_count", 0)) >= 1, "Synthetic audit must count opening-economy balance findings.")
	check(has_code(report, "economy.starting_wallet_single_choice"), "A wallet with only one executable opening purchase must be reported for review.")
	finish()


func has_message(messages: Array[String], fragment: String) -> bool:
	for message in messages:
		if message.contains(fragment):
			return true
	return false


func has_recipe_source_gate(
	source_index: Dictionary,
	item_id: String,
	expected_gated: bool
) -> bool:
	for source_value in ProgressionSourceIndex.source_array(source_index.get(item_id, [])):
		if typeof(source_value) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = source_value
		if (
			str(source.get("kind", "")) == "recipe"
			and bool(source.get("gated", true)) == expected_gated
		):
			return true
	return false


func has_source_context(source_index: Dictionary, item_id: String, context: String) -> bool:
	for source_value in ProgressionSourceIndex.source_array(source_index.get(item_id, [])):
		if typeof(source_value) == TYPE_DICTIONARY and str((source_value as Dictionary).get("context", "")) == context:
			return true
	return false


func has_code(report: Dictionary, code: String) -> bool:
	for finding_value in report.get("findings", []):
		if typeof(finding_value) == TYPE_DICTIONARY and str((finding_value as Dictionary).get("code", "")) == code:
			return true
	return false


func has_code_context(report: Dictionary, code: String, context: String) -> bool:
	for finding_value in report.get("findings", []):
		if typeof(finding_value) != TYPE_DICTIONARY:
			continue
		var finding: Dictionary = finding_value
		if str(finding.get("code", "")) == code and str(finding.get("context", "")) == context:
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Campaign audit edge smoke test passed: reachability, exact source accounting, nested rewards, recipe unlocks, finite stock, merchant bindings, cycles, self-gates, affordability, economy balance, quest and save blockers are detected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
