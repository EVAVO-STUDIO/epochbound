extends SceneTree

const ProgressionAffordabilityAudit = preload("res://src/content/progression_affordability_audit.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var currencies: Dictionary = {
		"tokens": {
			"id": "tokens",
			"display_name": "Tokens",
			"symbol": "TK",
			"starting_balance": 10,
			"max_balance": 999
		},
		"seals": {
			"id": "seals",
			"display_name": "Seals",
			"symbol": "SL",
			"starting_balance": 4,
			"max_balance": 999
		}
	}
	var split_sources := [
		merchant_source("north_vendor", "tokens", 1, 4, "split_pass"),
		merchant_source("south_vendor", "tokens", 1, 5, "split_pass")
	]
	var mixed_sources := [
		merchant_source("token_vendor", "tokens", 1, 4, "mixed_pass"),
		merchant_source("seal_vendor", "seals", 1, 4, "mixed_pass")
	]
	var expensive_sources := [
		merchant_source("first_vendor", "tokens", 2, 4, "expensive_split"),
		merchant_source("second_vendor", "tokens", 1, 4, "expensive_split")
	]

	var split_analysis := ProgressionAffordabilityAudit.purchase_analysis(2, split_sources, currencies)
	check(bool(split_analysis.get("has_sale", false)), "Two merchants must be able to combine finite stock for one progression requirement.")
	check(bool(split_analysis.get("affordable", false)), "Combined same-currency stock costing TK 9 must fit the TK 10 starting wallet.")
	check(int(split_analysis.get("stock_quantity", 0)) == 2, "Combined merchant stock must expose both required units.")
	check(int(split_analysis.get("affordable_quantity", 0)) == 2, "The wallet-capacity planner must fund both split units.")
	check(str(split_analysis.get("exclusive_currency_id", "")) == "tokens", "A one-currency route must preserve its currency identity.")
	check(int(split_analysis.get("minimum_cost", -1)) == 9, "The same-currency planner must choose the cheapest complete stock combination.")

	var mixed_analysis := ProgressionAffordabilityAudit.purchase_analysis(2, mixed_sources, currencies)
	check(bool(mixed_analysis.get("has_sale", false)), "Different merchant currencies may combine stock for the same required item.")
	check(bool(mixed_analysis.get("affordable", false)), "Independent starting wallets must be evaluated without comparing unlike currency values.")
	check(int(mixed_analysis.get("currency_count", 0)) == 2, "The planner must preserve both merchant currencies.")
	check(int(mixed_analysis.get("affordable_quantity", 0)) == 2, "The two independent wallets must jointly fund two required units.")

	var expensive_analysis := ProgressionAffordabilityAudit.purchase_analysis(3, expensive_sources, currencies)
	check(bool(expensive_analysis.get("has_sale", false)), "Three valid stock units must remain a complete sale route.")
	check(not bool(expensive_analysis.get("affordable", true)), "TK 10 must not be reported as able to fund a TK 12 purchase.")
	check(int(expensive_analysis.get("affordable_quantity", 0)) == 2, "The planner must report the exact number of units the starting wallet can fund.")

	var progression: Dictionary = {
		"requirements": {
			"split_pass": 2,
			"mixed_pass": 2,
			"budget_pass_a": 1,
			"budget_pass_b": 1,
			"expensive_split": 3,
			"insufficient_stock": 2
		},
		"sources": {
			"split_pass": split_sources,
			"mixed_pass": mixed_sources,
			"budget_pass_a": [merchant_source("budget_a_vendor", "tokens", 1, 6, "budget_pass_a")],
			"budget_pass_b": [merchant_source("budget_b_vendor", "tokens", 1, 6, "budget_pass_b")],
			"expensive_split": expensive_sources,
			"insufficient_stock": [merchant_source("thin_vendor", "tokens", 1, 1, "insufficient_stock")],
			"lamp_a": [merchant_source("lamp_token_vendor", "tokens", 1, 20, "lamp_a")],
			"lamp_b": [merchant_source("lamp_seal_vendor", "seals", 1, 4, "lamp_b")]
		},
		"starting_capabilities": {},
		"capability_items": {
			"illuminate_dark": PackedStringArray(["lamp_a", "lamp_b"])
		}
	}
	var findings: Array[Dictionary] = []
	var merchant_only_count := ProgressionAffordabilityAudit.audit(
		{"currencies": currencies, "merchants": {}},
		progression,
		findings
	)
	check(merchant_only_count == 7, "The fixture must audit six progression items and one capability route.")
	check(not has_code_context(findings, "economy.progression_item_not_for_sale", "split_pass"), "Split finite stock must not create a false not-for-sale blocker.")
	check(not has_code_context(findings, "economy.progression_purchase_unaffordable", "split_pass"), "An affordable combined stock route must not create an affordability warning.")
	check(not has_code_context(findings, "economy.progression_item_not_for_sale", "mixed_pass"), "Cross-currency stock must not create a false not-for-sale blocker.")
	check(not has_code_context(findings, "economy.progression_purchase_unaffordable", "mixed_pass"), "Affordable independent wallets must not create a cross-currency warning.")
	check(has_code_context(findings, "economy.progression_purchase_unaffordable", "expensive_split"), "A complete stock route above wallet capacity must remain a warning.")
	check(has_code_context(findings, "economy.progression_item_not_for_sale", "insufficient_stock"), "Combined stock below the explicit quantity must remain a blocker.")
	check(has_code_context(findings, "economy.cumulative_progression_purchase_unaffordable", "tokens"), "Individually affordable token purchases that exceed the shared starting wallet must create a cumulative warning.")
	check(not has_code_context(findings, "economy.capability_item_not_for_sale", "illuminate_dark"), "Alternative capability items must share valid merchant routes.")
	check(not has_code_context(findings, "economy.capability_purchase_unaffordable", "illuminate_dark"), "A capability affordable through one independent wallet must not be warned because another currency route is expensive.")
	finish()


func merchant_source(
	context: String,
	currency_id: String,
	quantity: int,
	unit_price: int,
	item_id: String
) -> Dictionary:
	return {
		"kind": "merchant",
		"context": context,
		"quantity": quantity,
		"gated": false,
		"gate_items": PackedStringArray(),
		"gate_capabilities": PackedStringArray(),
		"bound": true,
		"currency_id": currency_id,
		"unit_price": unit_price,
		"item_id": item_id
	}


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
		print("Progression affordability smoke test passed: split stock, independent currencies, exact wallet capacity, cumulative mandatory spend and capability alternatives are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
