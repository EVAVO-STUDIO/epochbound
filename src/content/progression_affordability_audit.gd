@tool
extends RefCounted

const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const SourceIndex = preload("res://src/content/progression_source_index.gd")

static func audit(
	economy: Dictionary,
	progression: Dictionary,
	findings: Array[Dictionary]
) -> int:
	var requirements: Dictionary = progression.get("requirements", {})
	var sources: Dictionary = progression.get("sources", {})
	var merchant_only_count := 0
	for item_id in sorted_dictionary_keys(requirements):
		var usable_sources := SourceIndex.usable_item_sources(SourceIndex.source_array(sources.get(item_id, [])))
		if not sources_are_merchant_only(usable_sources):
			continue
		merchant_only_count += 1
		audit_merchant_purchase(
			item_id,
			maxi(1, int(requirements.get(item_id, 1))),
			usable_sources,
			economy,
			"progression_item",
			findings
		)

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
) -> void:
	var currencies: Dictionary = economy.get("currencies", {})
	var has_sale := false
	var affordable := false
	var best_total := 2147483647
	var best_currency_id := ""
	for source_value in sources:
		if typeof(source_value) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = source_value
		var unit_price := int(source.get("unit_price", 0))
		var source_quantity := int(source.get("quantity", 0))
		if unit_price <= 0 or (source_quantity >= 0 and source_quantity < quantity):
			continue
		has_sale = true
		var currency_id := str(source.get("currency_id", ""))
		var currency: Dictionary = currencies.get(currency_id, {})
		var starting_balance := EconomyCatalog.starting_balance(currency)
		var total := unit_price * quantity
		if total < best_total:
			best_total = total
			best_currency_id = currency_id
		if starting_balance >= total:
			affordable = true
	if not has_sale:
		var code := "economy.progression_item_not_for_sale" if kind == "progression_item" else "economy.capability_item_not_for_sale"
		var noun := "Progression item" if kind == "progression_item" else "Capability"
		add_finding(findings, "blocker", code, "%s '%s' depends only on merchant sources, but none can sell the required quantity at a valid price." % [noun, context_id], context_id)
	elif not affordable:
		var code := "economy.progression_purchase_unaffordable" if kind == "progression_item" else "economy.capability_purchase_unaffordable"
		var noun := "Progression item" if kind == "progression_item" else "Capability"
		var currency: Dictionary = currencies.get(best_currency_id, {})
		var symbol := EconomyCatalog.currency_symbol(currencies, best_currency_id)
		var balance := EconomyCatalog.starting_balance(currency)
		add_finding(findings, "warning", code, "%s '%s' has a lowest merchant cost of %s %d, above the starting balance of %s %d; prove an earning route before the first mandatory use." % [noun, context_id, symbol, best_total, symbol, balance], context_id)


static func sorted_dictionary_keys(value: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in value.keys():
		output.append(str(key_value))
	output.sort()
	return output


static func add_finding(findings: Array[Dictionary], severity: String, code: String, message: String, context: String = "") -> void:
	findings.append({"severity": severity, "code": code, "message": message, "context": context})
