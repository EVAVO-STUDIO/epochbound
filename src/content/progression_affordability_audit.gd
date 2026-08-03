@tool
extends RefCounted

const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const SourceIndex = preload("res://src/content/progression_source_index.gd")

const MAX_PURCHASE_COST := 2147483647


static func audit(
	economy: Dictionary,
	progression: Dictionary,
	findings: Array[Dictionary]
) -> int:
	var requirements: Dictionary = progression.get("requirements", {})
	var sources: Dictionary = progression.get("sources", {})
	var merchant_only_count := 0
	var cumulative_progression_costs: Dictionary = {}
	for item_id in sorted_dictionary_keys(requirements):
		var usable_sources := SourceIndex.usable_item_sources(SourceIndex.source_array(sources.get(item_id, [])))
		if not sources_are_merchant_only(usable_sources):
			continue
		merchant_only_count += 1
		var analysis := audit_merchant_purchase(
			item_id,
			maxi(1, int(requirements.get(item_id, 1))),
			usable_sources,
			economy,
			"progression_item",
			findings
		)
		append_cumulative_progression_cost(item_id, analysis, cumulative_progression_costs)

	var starting_capabilities: Dictionary = progression.get("starting_capabilities", {})
	var capability_items: Dictionary = progression.get("capability_items", {})
	for capability_id in sorted_dictionary_keys(capability_items):
		if starting_capabilities.has(capability_id):
			continue
		var item_ids_value: Variant = capability_items.get(capability_id, PackedStringArray())
		var item_ids := PackedStringArray()
		if typeof(item_ids_value) == TYPE_PACKED_STRING_ARRAY:
			item_ids = item_ids_value as PackedStringArray
		var merchant_sources: Array = []
		var all_sources: Array = []
		for item_id in item_ids:
			for source_value in SourceIndex.usable_item_sources(SourceIndex.source_array(sources.get(item_id, []))):
				if typeof(source_value) != TYPE_DICTIONARY:
					continue
				var source: Dictionary = (source_value as Dictionary).duplicate(true)
				source["item_id"] = item_id
				all_sources.append(source)
				if str(source.get("kind", "")) == "merchant":
					merchant_sources.append(source)
		if all_sources.is_empty() or merchant_sources.size() != all_sources.size():
			continue
		merchant_only_count += 1
		audit_merchant_purchase(
			capability_id,
			1,
			merchant_sources,
			economy,
			"capability",
			findings
		)

	audit_cumulative_progression_budget(cumulative_progression_costs, economy, findings)
	return merchant_only_count


static func sources_are_merchant_only(sources: Array) -> bool:
	if sources.is_empty():
		return false
	for source_value in sources:
		if typeof(source_value) != TYPE_DICTIONARY or str((source_value as Dictionary).get("kind", "")) != "merchant":
			return false
	return true


static func audit_merchant_purchase(
	context_id: String,
	quantity: int,
	sources: Array,
	economy: Dictionary,
	kind: String,
	findings: Array[Dictionary]
) -> Dictionary:
	var currencies: Dictionary = economy.get("currencies", {})
	var analysis := purchase_analysis(quantity, sources, currencies)
	var noun := "Progression item" if kind == "progression_item" else "Capability"
	if not bool(analysis.get("has_sale", false)):
		var code := "economy.progression_item_not_for_sale" if kind == "progression_item" else "economy.capability_item_not_for_sale"
		add_finding(
			findings,
			"blocker",
			code,
			"%s '%s' depends only on merchant sources, but valid merchant stock provides only %d of %d required unit%s." % [
				noun,
				context_id,
				int(analysis.get("stock_quantity", 0)),
				quantity,
				"" if quantity == 1 else "s"
			],
			context_id
		)
	elif not bool(analysis.get("affordable", false)):
		var code := "economy.progression_purchase_unaffordable" if kind == "progression_item" else "economy.capability_purchase_unaffordable"
		add_finding(
			findings,
			"warning",
			code,
			"%s '%s' requires %d merchant unit%s, but the authored starting wallets can fund only %d across the valid stock routes (%s); prove an earning route before the first mandatory use." % [
				noun,
				context_id,
				quantity,
				"" if quantity == 1 else "s",
				int(analysis.get("affordable_quantity", 0)),
				format_wallet_capacity_summary(analysis)
			],
			context_id
		)
	return analysis


static func purchase_analysis(
	quantity: int,
	sources: Array,
	currencies: Dictionary
) -> Dictionary:
	var required := maxi(1, quantity)
	var grouped_sources := merchant_sources_by_currency(sources, currencies)
	var plans: Dictionary = {}
	var stock_quantity := 0
	var affordable_quantity := 0
	for currency_id in sorted_dictionary_keys(grouped_sources):
		var currency: Dictionary = currencies.get(currency_id, {})
		var plan := currency_purchase_plan(
			grouped_sources.get(currency_id, []),
			required,
			EconomyCatalog.starting_balance(currency)
		)
		plan["currency_id"] = currency_id
		plan["symbol"] = EconomyCatalog.currency_symbol(currencies, currency_id)
		plans[currency_id] = plan
		stock_quantity = mini(required, stock_quantity + int(plan.get("stock_quantity", 0)))
		affordable_quantity = mini(required, affordable_quantity + int(plan.get("affordable_quantity", 0)))

	var exclusive_currency_id := ""
	var minimum_cost := -1
	if grouped_sources.size() == 1:
		var ids := sorted_dictionary_keys(grouped_sources)
		if not ids.is_empty():
			var currency_id := str(ids[0])
			var plan: Dictionary = plans.get(currency_id, {})
			if bool(plan.get("can_supply", false)):
				exclusive_currency_id = currency_id
				minimum_cost = int(plan.get("minimum_cost", -1))
	return {
		"quantity": required,
		"has_sale": stock_quantity >= required,
		"affordable": affordable_quantity >= required,
		"stock_quantity": stock_quantity,
		"affordable_quantity": affordable_quantity,
		"currency_count": grouped_sources.size(),
		"plans": plans,
		"exclusive_currency_id": exclusive_currency_id,
		"minimum_cost": minimum_cost
	}


static func merchant_sources_by_currency(
	sources: Array,
	currencies: Dictionary
) -> Dictionary:
	var output: Dictionary = {}
	for source_value in sources:
		if typeof(source_value) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = source_value
		if str(source.get("kind", "")) != "merchant":
			continue
		var currency_id := str(source.get("currency_id", ""))
		var unit_price := int(source.get("unit_price", 0))
		var quantity := int(source.get("quantity", 0))
		if currency_id.is_empty() or not currencies.has(currency_id) or unit_price <= 0 or quantity == 0:
			continue
		if not output.has(currency_id):
			output[currency_id] = []
		var records_value: Variant = output.get(currency_id, [])
		var records: Array = records_value as Array if typeof(records_value) == TYPE_ARRAY else []
		records.append({
			"unit_price": unit_price,
			"quantity": quantity,
			"context": str(source.get("context", "")),
			"item_id": str(source.get("item_id", ""))
		})
		output[currency_id] = records
	return output


static func currency_purchase_plan(
	entries_value: Variant,
	quantity: int,
	starting_balance: int
) -> Dictionary:
	var entries: Array = (entries_value as Array).duplicate(true) if typeof(entries_value) == TYPE_ARRAY else []
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var price_order := int(left.get("unit_price", 0)) - int(right.get("unit_price", 0))
		if price_order != 0:
			return price_order < 0
		var context_order := str(left.get("context", "")).naturalnocasecmp_to(str(right.get("context", "")))
		if context_order != 0:
			return context_order < 0
		return str(left.get("item_id", "")).naturalnocasecmp_to(str(right.get("item_id", ""))) < 0
	)

	var remaining := quantity
	var stock_quantity := 0
	var minimum_cost := 0
	for entry_value in entries:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var available := available_units(entry, quantity)
		stock_quantity = mini(quantity, stock_quantity + available)
		var taken := mini(remaining, available)
		if taken <= 0:
			continue
		minimum_cost = mini(
			MAX_PURCHASE_COST,
			minimum_cost + taken * int(entry.get("unit_price", 0))
		)
		remaining -= taken
		if remaining <= 0:
			break

	var affordable_quantity := 0
	var remaining_balance := maxi(0, starting_balance)
	for entry_value in entries:
		if typeof(entry_value) != TYPE_DICTIONARY or affordable_quantity >= quantity:
			continue
		var entry: Dictionary = entry_value
		var unit_price := int(entry.get("unit_price", 0))
		if unit_price <= 0:
			continue
		var available := mini(available_units(entry, quantity), quantity - affordable_quantity)
		var purchasable := mini(
			available,
			int(floor(float(remaining_balance) / float(unit_price)))
		)
		if purchasable <= 0:
			continue
		affordable_quantity += purchasable
		remaining_balance -= purchasable * unit_price

	var can_supply := stock_quantity >= quantity
	return {
		"starting_balance": maxi(0, starting_balance),
		"stock_quantity": stock_quantity,
		"affordable_quantity": affordable_quantity,
		"can_supply": can_supply,
		"minimum_cost": minimum_cost if can_supply else -1
	}


static func available_units(entry: Dictionary, required_quantity: int) -> int:
	var quantity := int(entry.get("quantity", 0))
	if quantity < 0:
		return required_quantity
	return mini(maxi(0, quantity), required_quantity)


static func append_cumulative_progression_cost(
	item_id: String,
	analysis: Dictionary,
	output: Dictionary
) -> void:
	if not bool(analysis.get("has_sale", false)) or not bool(analysis.get("affordable", false)):
		return
	var currency_id := str(analysis.get("exclusive_currency_id", ""))
	var minimum_cost := int(analysis.get("minimum_cost", -1))
	if currency_id.is_empty() or minimum_cost <= 0:
		return
	var record_value: Variant = output.get(currency_id, {})
	var record: Dictionary = record_value if typeof(record_value) == TYPE_DICTIONARY else {}
	var item_records_value: Variant = record.get("items", [])
	var item_records: Array = item_records_value as Array if typeof(item_records_value) == TYPE_ARRAY else []
	item_records.append({"item_id": item_id, "cost": minimum_cost})
	record["items"] = item_records
	record["total_cost"] = mini(MAX_PURCHASE_COST, int(record.get("total_cost", 0)) + minimum_cost)
	output[currency_id] = record


static func audit_cumulative_progression_budget(
	costs_by_currency: Dictionary,
	economy: Dictionary,
	findings: Array[Dictionary]
) -> void:
	var currencies: Dictionary = economy.get("currencies", {})
	for currency_id in sorted_dictionary_keys(costs_by_currency):
		var record: Dictionary = costs_by_currency.get(currency_id, {})
		var items_value: Variant = record.get("items", [])
		var items: Array = items_value as Array if typeof(items_value) == TYPE_ARRAY else []
		if items.size() < 2:
			continue
		items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return str(left.get("item_id", "")).naturalnocasecmp_to(str(right.get("item_id", ""))) < 0
		)
		var currency: Dictionary = currencies.get(currency_id, {})
		var starting_balance := EconomyCatalog.starting_balance(currency)
		var total_cost := int(record.get("total_cost", 0))
		if total_cost <= starting_balance:
			continue
		var labels := PackedStringArray()
		var symbol := EconomyCatalog.currency_symbol(currencies, currency_id)
		for item_value in items:
			if typeof(item_value) == TYPE_DICTIONARY:
				var item: Dictionary = item_value
				labels.append("%s (%s %d)" % [item.get("item_id", "item"), symbol, int(item.get("cost", 0))])
		add_finding(
			findings,
			"warning",
			"economy.cumulative_progression_purchase_unaffordable",
			"Across the statically identified merchant-only progression requirements, individually affordable purchases [%s] total at least %s %d, above the starting balance of %s %d. This is an aggregate review envelope, not proof that every requirement shares one mandatory route; document which purchases co-occur and where cumulative earnings are available." % [
				", ".join(labels),
				symbol,
				total_cost,
				symbol,
				starting_balance
			],
			currency_id
		)


static func format_wallet_capacity_summary(analysis: Dictionary) -> String:
	var plans_value: Variant = analysis.get("plans", {})
	var plans: Dictionary = plans_value if typeof(plans_value) == TYPE_DICTIONARY else {}
	var required := maxi(1, int(analysis.get("quantity", 1)))
	var labels := PackedStringArray()
	for currency_id in sorted_dictionary_keys(plans):
		var plan: Dictionary = plans.get(currency_id, {})
		var symbol := str(plan.get("symbol", currency_id))
		var label := "%s %d funds %d/%d" % [
			symbol,
			int(plan.get("starting_balance", 0)),
			int(plan.get("affordable_quantity", 0)),
			required
		]
		if bool(plan.get("can_supply", false)):
			label += "; complete cost %s %d" % [symbol, int(plan.get("minimum_cost", 0))]
		else:
			label += "; stock %d/%d" % [int(plan.get("stock_quantity", 0)), required]
		labels.append(label)
	return "; ".join(labels) if not labels.is_empty() else "no valid priced stock"


static func sorted_dictionary_keys(value: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in value.keys():
		output.append(str(key_value))
	output.sort()
	return output


static func add_finding(findings: Array[Dictionary], severity: String, code: String, message: String, context: String = "") -> void:
	findings.append({"severity": severity, "code": code, "message": message, "context": context})
