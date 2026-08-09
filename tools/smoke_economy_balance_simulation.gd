extends SceneTree

const CampaignRepository = preload("res://src/content/campaign_repository.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const SupplyRegionCatalog = preload("res://src/content/supply_region_catalog.gd")
const EconomyBalanceSimulation = preload("res://src/content/economy_balance_simulation.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	audit_reference_campaign()
	audit_opening_choice_edges()
	audit_arbitrage_edges()
	audit_endurance_edges()
	finish()


func audit_reference_campaign() -> void:
	var campaign_result := CampaignRepository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load for economy simulation.")
	if not bool(campaign_result.get("ok", false)):
		return
	var campaign: Dictionary = campaign_result.get("data", {})
	var item_result := ItemCatalog.load_item_catalogs(CAMPAIGN_PATH, campaign)
	var economy_result := EconomyCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	var supply_result := SupplyRegionCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(item_result.get("ok", false)), "Reference item catalog must load for economy simulation.")
	check(bool(economy_result.get("ok", false)), "Reference economy catalog must load for economy simulation.")
	check(bool(supply_result.get("ok", false)), "Reference supply catalog must load for economy simulation.")
	var items: Dictionary = item_result.get("definitions", {})
	var economy := {
		"currencies": economy_result.get("currencies", {}),
		"merchants": economy_result.get("merchants", {}),
		"supply_regions": supply_result.get("definitions", {})
	}
	var first_findings: Array[Dictionary] = []
	var first_metrics := EconomyBalanceSimulation.audit(campaign, items, economy, first_findings)
	var second_findings: Array[Dictionary] = []
	var second_metrics := EconomyBalanceSimulation.audit(campaign, items, economy, second_findings)
	check(first_findings.is_empty(), "Reference economy balance simulation must remain warning-free.")
	check(int(first_metrics.get("economy_starting_wallet_count", 0)) == 1, "Reference economy must expose one authored opening wallet.")
	check(int(first_metrics.get("economy_starting_choice_count", 0)) == 4, "Reference starting wallet must support four executable preparation choices.")
	check(int(first_metrics.get("economy_recovery_safe_choice_count", 0)) == 4, "All four reference opening purchases must retain a recovery route.")
	check(int(first_metrics.get("economy_optional_dead_end_count", -1)) == 0, "Reference optional purchases must not strand recovery.")
	check(int(first_metrics.get("economy_preparation_category_count", 0)) == 3, "Reference opening purchases must cover recovery, material and ammunition.")
	check(int(first_metrics.get("economy_arbitrage_route_count", -1)) == 0, "Reference economy must expose no positive buy-sell spread.")
	check(int(first_metrics.get("economy_repeatable_arbitrage_count", -1)) == 0, "Reference economy must expose no repeatable arbitrage.")
	check(int(first_metrics.get("economy_renewable_recovery_units", 0)) == 20, "Reference routes must replenish twenty healing units per thirty-minute horizon.")
	check(int(first_metrics.get("economy_renewable_ammo_units", 0)) == 80, "Reference routes must replenish eighty ammunition units per thirty-minute horizon.")
	check(int(first_metrics.get("economy_finite_progression_stock_count", 0)) == 3, "Reference economy must retain three finite non-renewable equipment offers.")
	check(int(first_metrics.get("economy_balance_risk_count", -1)) == 0, "Reference economy must publish zero balance risks.")
	check(
		JSON.stringify({"metrics": first_metrics, "findings": first_findings})
		== JSON.stringify({"metrics": second_metrics, "findings": second_findings}),
		"Repeated economy simulations must produce deterministic evidence."
	)


func audit_opening_choice_edges() -> void:
	var items := fixture_items()
	var no_choice_findings: Array[Dictionary] = []
	var no_choice_metrics := EconomyBalanceSimulation.audit(
		fixture_campaign([]),
		items,
		fixture_economy([
			merchant("expensive", "tokens", [stock("material", 1, 12)])
		], 10),
		no_choice_findings
	)
	check(int(no_choice_metrics.get("economy_starting_choice_count", -1)) == 0, "Unaffordable stock must not count as an executable opening choice.")
	check(has_code(no_choice_findings, "economy.starting_wallet_no_choice"), "A wallet with no executable purchase must report economy.starting_wallet_no_choice.")

	var single_choice_findings: Array[Dictionary] = []
	var single_choice_metrics := EconomyBalanceSimulation.audit(
		fixture_campaign([{"item_id": "tonic", "quantity": 1}]),
		items,
		fixture_economy([
			merchant("single", "tokens", [stock("material", 1, 5)])
		], 10),
		single_choice_findings
	)
	check(int(single_choice_metrics.get("economy_starting_choice_count", 0)) == 1, "One affordable stock entry must count as one executable opening choice.")
	check(has_code(single_choice_findings, "economy.starting_wallet_single_choice"), "A single executable opening purchase must remain visible for review.")

	var stranded_findings: Array[Dictionary] = []
	var stranded_metrics := EconomyBalanceSimulation.audit(
		fixture_campaign([]),
		items,
		fixture_economy([
			merchant("opening", "tokens", [
				stock("tonic", 1, 10),
				stock("material", 1, 5)
			])
		], 10),
		stranded_findings
	)
	check(int(stranded_metrics.get("economy_starting_choice_count", 0)) == 2, "Both affordable opening stock entries must be simulated.")
	check(int(stranded_metrics.get("economy_recovery_safe_choice_count", 0)) == 1, "Only the healing purchase may remain recovery-safe when optional spend consumes the reserve.")
	check(int(stranded_metrics.get("economy_optional_dead_end_count", 0)) == 1, "The optional material purchase must be counted as one recovery dead end.")
	check(has_code(stranded_findings, "economy.optional_spend_strands_recovery"), "Optional spend that removes every healing route must be reported.")


func audit_arbitrage_edges() -> void:
	var items := fixture_items()
	var repeatable_findings: Array[Dictionary] = []
	var repeatable_metrics := EconomyBalanceSimulation.audit(
		fixture_campaign([{"item_id": "tonic", "quantity": 1}]),
		items,
		fixture_economy([
			merchant("buyer", "tokens", [unlimited_stock("material", 2)]),
			merchant_with_sales("seller", "tokens", [], 1.0, 2.0)
		], 10),
		repeatable_findings
	)
	check(int(repeatable_metrics.get("economy_arbitrage_route_count", 0)) == 1, "A positive same-currency spread must be counted.")
	check(int(repeatable_metrics.get("economy_repeatable_arbitrage_count", 0)) == 1, "Unlimited profitable stock must count as repeatable arbitrage.")
	check(has_code(repeatable_findings, "economy.repeatable_arbitrage"), "Repeatable arbitrage must be a release-stopping finding.")

	var finite_findings: Array[Dictionary] = []
	var finite_metrics := EconomyBalanceSimulation.audit(
		fixture_campaign([{"item_id": "tonic", "quantity": 1}]),
		items,
		fixture_economy([
			merchant("finite_buyer", "tokens", [stock("material", 1, 2)]),
			merchant_with_sales("finite_seller", "tokens", [], 1.0, 2.0)
		], 10),
		finite_findings
	)
	check(int(finite_metrics.get("economy_arbitrage_route_count", 0)) == 1, "A one-time finite trade reward must remain measurable.")
	check(int(finite_metrics.get("economy_repeatable_arbitrage_count", -1)) == 0, "Finite non-renewable stock must not be misclassified as a repeatable loop.")
	check(not has_code(finite_findings, "economy.repeatable_arbitrage"), "A one-time finite spread must not create a repeatable arbitrage blocker.")


func audit_endurance_edges() -> void:
	var items := fixture_items()
	var findings: Array[Dictionary] = []
	var metrics := EconomyBalanceSimulation.audit(
		fixture_campaign([{"item_id": "tonic", "quantity": 1}]),
		items,
		fixture_economy([
			merchant("finite_resources", "tokens", [
				stock("tonic", 1, 4),
				stock("bolts", 3, 1)
			])
		], 10),
		findings
	)
	check(has_code(findings, "economy.recovery_endurance_risk"), "Finite non-renewable healing stock must report an endurance warning.")
	check(has_code(findings, "economy.ammo_endurance_risk"), "Finite non-renewable authored ammunition must report an endurance warning.")
	check(int(metrics.get("economy_renewable_recovery_units", -1)) == 0, "Finite recovery stock must not inflate renewable throughput.")
	check(int(metrics.get("economy_renewable_ammo_units", -1)) == 0, "Finite ammunition stock must not inflate renewable throughput.")


func fixture_campaign(starting_inventory: Array) -> Dictionary:
	return {
		"id": "economy_fixture",
		"starting_inventory": starting_inventory,
		"starting_equipment": {},
		"starting_recipes": []
	}


func fixture_economy(merchant_records: Array, starting_balance: int) -> Dictionary:
	var merchant_index: Dictionary = {}
	for merchant_value in merchant_records:
		if typeof(merchant_value) == TYPE_DICTIONARY:
			var merchant_data: Dictionary = merchant_value
			merchant_index[str(merchant_data.get("id", ""))] = merchant_data
	return {
		"currencies": {
			"tokens": {
				"id": "tokens",
				"display_name": "Tokens",
				"symbol": "TK",
				"starting_balance": starting_balance,
				"max_balance": 999
			}
		},
		"merchants": merchant_index,
		"supply_regions": {}
	}


func fixture_items() -> Dictionary:
	return {
		"tonic": {
			"id": "tonic",
			"display_name": "Tonic",
			"kind": "consumable",
			"stack_limit": 9,
			"value": 5,
			"use_effect": {"type": "heal", "amount": 5}
		},
		"material": {
			"id": "material",
			"display_name": "Material",
			"kind": "material",
			"stack_limit": 99,
			"value": 2,
			"use_effect": {"type": "none"}
		},
		"bolts": {
			"id": "bolts",
			"display_name": "Bolts",
			"kind": "ammunition",
			"stack_limit": 60,
			"value": 1,
			"use_effect": {"type": "none"}
		},
		"launcher": {
			"id": "launcher",
			"display_name": "Launcher",
			"kind": "equipment",
			"stack_limit": 1,
			"value": 20,
			"use_effect": {"type": "none"},
			"equipment": {
				"slot": "weapon",
				"capabilities": [],
				"ranged": {"ammo_item_id": "bolts"}
			}
		}
	}


func merchant(merchant_id: String, currency_id: String, entries: Array) -> Dictionary:
	return merchant_with_sales(merchant_id, currency_id, entries, 1.0, 0.5)


func merchant_with_sales(
	merchant_id: String,
	currency_id: String,
	entries: Array,
	buy_multiplier: float,
	sell_multiplier: float
) -> Dictionary:
	return {
		"id": merchant_id,
		"display_name": merchant_id.capitalize(),
		"currency_id": currency_id,
		"buy_multiplier": buy_multiplier,
		"sell_multiplier": sell_multiplier,
		"accepts_sales": true,
		"accepted_kinds": ["consumable", "material", "equipment", "ammunition"],
		"refused_items": [],
		"resell_player_goods": true,
		"conditions": [],
		"stock": entries
	}


func stock(item_id: String, quantity: int, buy_price: int) -> Dictionary:
	return {
		"item_id": item_id,
		"quantity": quantity,
		"unlimited": false,
		"buy_price": buy_price,
		"conditions": []
	}


func unlimited_stock(item_id: String, buy_price: int) -> Dictionary:
	return {
		"item_id": item_id,
		"quantity": 0,
		"unlimited": true,
		"buy_price": buy_price,
		"conditions": []
	}


func has_code(findings: Array[Dictionary], code: String) -> bool:
	for finding in findings:
		if str(finding.get("code", "")) == code:
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Economy choices 4/4 recovery-safe; deterministic opening choices, bounded endurance, finite trade rewards and repeatable arbitrage protection passed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
