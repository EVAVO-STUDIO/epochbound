@tool
extends RefCounted

const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const SupplyRegionCatalog = preload("res://src/content/supply_region_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const EconomyModel = preload("res://src/game/economy_model.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")

const SIMULATION_HORIZON_SECONDS := 1800.0


static func audit(
	campaign: Dictionary,
	items: Dictionary,
	economy: Dictionary,
	findings: Array[Dictionary]
) -> Dictionary:
	var finding_start := findings.size()
	var currencies: Dictionary = dictionary_value(economy.get("currencies", {}))
	var merchants: Dictionary = dictionary_value(economy.get("merchants", {}))
	var supply_regions: Dictionary = dictionary_value(economy.get("supply_regions", {}))
	var starting_inventory := InventoryModel.initial_inventory(campaign, items)
	var starting_balances := EconomyModel.initial_balances(currencies)
	var healing_ids := healing_item_ids(items)
	var ammunition_ids := authored_ammunition_ids(items)

	var opening := audit_opening_choices(
		starting_inventory,
		starting_balances,
		items,
		currencies,
		merchants,
		healing_ids,
		findings
	)
	var market := audit_market_arbitrage(
		items,
		currencies,
		merchants,
		supply_regions,
		findings
	)
	var endurance := audit_endurance(
		items,
		merchants,
		supply_regions,
		healing_ids,
		ammunition_ids,
		findings
	)

	return {
		"economy_balance_scenario_count": (
			int(opening.get("scenario_count", 0))
			+ int(market.get("scenario_count", 0))
			+ int(endurance.get("scenario_count", 0))
		),
		"economy_balance_risk_count": findings.size() - finding_start,
		"economy_starting_wallet_count": starting_balances.size(),
		"economy_starting_choice_count": int(opening.get("choice_count", 0)),
		"economy_recovery_safe_choice_count": int(opening.get("recovery_safe_count", 0)),
		"economy_optional_dead_end_count": int(opening.get("dead_end_count", 0)),
		"economy_preparation_category_count": int(opening.get("category_count", 0)),
		"economy_arbitrage_route_count": int(market.get("arbitrage_route_count", 0)),
		"economy_repeatable_arbitrage_count": int(market.get("repeatable_arbitrage_count", 0)),
		"economy_renewable_recovery_units": int(endurance.get("renewable_recovery_units", 0)),
		"economy_renewable_ammo_units": int(endurance.get("renewable_ammo_units", 0)),
		"economy_finite_progression_stock_count": int(endurance.get("finite_progression_stock_count", 0))
	}


static func audit_opening_choices(
	starting_inventory: Dictionary,
	starting_balances: Dictionary,
	items: Dictionary,
	currencies: Dictionary,
	merchants: Dictionary,
	healing_ids: Dictionary,
	findings: Array[Dictionary]
) -> Dictionary:
	var choices: Array[Dictionary] = []
	var category_index: Dictionary = {}
	var scenario_count := 0
	for merchant_id in sorted_dictionary_keys(merchants):
		var merchant_data := EconomyCatalog.merchant(merchants, merchant_id)
		if merchant_data.is_empty() or not is_unconditional(merchant_data):
			continue
		var currency_id := EconomyCatalog.merchant_currency_id(merchant_data)
		if not currencies.has(currency_id):
			continue
		for entry_value in EconomyCatalog.stock_entries(merchant_data):
			if typeof(entry_value) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_value
			if not is_unconditional(entry):
				continue
			scenario_count += 1
			var item_id := str(entry.get("item_id", ""))
			var item_data := ItemCatalog.item(items, item_id)
			if item_data.is_empty() or not stock_can_supply_one(entry):
				continue
			var unit_price := EconomyModel.buy_price(item_data, merchant_data, entry)
			if unit_price <= 0 or EconomyModel.balance(starting_balances, currency_id) < unit_price:
				continue
			if InventoryModel.count(starting_inventory, item_id) >= ItemCatalog.stack_limit(item_data):
				continue
			var category := preparation_category(item_data)
			var recovery_safe := purchase_retains_recovery(
				starting_inventory,
				starting_balances,
				merchant_id,
				item_id,
				currency_id,
				unit_price,
				items,
				currencies,
				merchants,
				healing_ids
			)
			choices.append({
				"merchant_id": merchant_id,
				"item_id": item_id,
				"currency_id": currency_id,
				"unit_price": unit_price,
				"category": category,
				"recovery_safe": recovery_safe
			})
			if not category.is_empty():
				category_index[category] = true
			if not recovery_safe:
				add_finding(
					findings,
					"warning",
					"economy.optional_spend_strands_recovery",
					"Buying '%s' from '%s' with the authored opening wallet leaves no healing item owned or affordable from another executable opening offer." % [
						ItemCatalog.item_name(item_data, item_id),
						str(merchant_data.get("display_name", merchant_id))
					],
					"%s:%s" % [merchant_id, item_id]
				)

	if not starting_balances.is_empty():
		if choices.is_empty():
			add_finding(
				findings,
				"warning",
				"economy.starting_wallet_no_choice",
				"The authored starting wallets cannot execute any unconditional merchant purchase after starting inventory stack limits are applied.",
				"opening_market"
			)
		elif choices.size() == 1:
			var only_choice: Dictionary = choices[0]
			add_finding(
				findings,
				"warning",
				"economy.starting_wallet_single_choice",
				"The authored starting wallets expose only one executable unconditional purchase ('%s'); review whether opening preparation is meaningfully optional." % str(only_choice.get("item_id", "")),
				str(only_choice.get("merchant_id", ""))
			)

	var recovery_safe_count := 0
	for choice in choices:
		if bool(choice.get("recovery_safe", false)):
			recovery_safe_count += 1
	return {
		"scenario_count": scenario_count,
		"choice_count": choices.size(),
		"recovery_safe_count": recovery_safe_count,
		"dead_end_count": choices.size() - recovery_safe_count,
		"category_count": category_index.size(),
		"choices": choices
	}


static func purchase_retains_recovery(
	starting_inventory: Dictionary,
	starting_balances: Dictionary,
	merchant_id: String,
	item_id: String,
	currency_id: String,
	unit_price: int,
	items: Dictionary,
	currencies: Dictionary,
	merchants: Dictionary,
	healing_ids: Dictionary
) -> bool:
	var inventory := starting_inventory.duplicate(true)
	var balances := starting_balances.duplicate(true)
	inventory[item_id] = InventoryModel.count(inventory, item_id) + 1
	balances[currency_id] = EconomyModel.balance(balances, currency_id) - unit_price
	if owns_healing_item(inventory, healing_ids):
		return true
	return can_afford_healing_offer(
		inventory,
		balances,
		items,
		currencies,
		merchants,
		healing_ids,
		merchant_id,
		item_id
	)


static func can_afford_healing_offer(
	inventory: Dictionary,
	balances: Dictionary,
	items: Dictionary,
	currencies: Dictionary,
	merchants: Dictionary,
	healing_ids: Dictionary,
	purchased_merchant_id: String,
	purchased_item_id: String
) -> bool:
	for merchant_id in sorted_dictionary_keys(merchants):
		var merchant_data := EconomyCatalog.merchant(merchants, merchant_id)
		if merchant_data.is_empty() or not is_unconditional(merchant_data):
			continue
		var currency_id := EconomyCatalog.merchant_currency_id(merchant_data)
		if not currencies.has(currency_id):
			continue
		for entry_value in EconomyCatalog.stock_entries(merchant_data):
			if typeof(entry_value) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_value
			if not is_unconditional(entry):
				continue
			var item_id := str(entry.get("item_id", ""))
			if not healing_ids.has(item_id):
				continue
			var available := EconomyCatalog.initial_stock_quantity(entry)
			if merchant_id == purchased_merchant_id and item_id == purchased_item_id and available > 0:
				available -= 1
			if available == 0:
				continue
			var item_data := ItemCatalog.item(items, item_id)
			if item_data.is_empty() or InventoryModel.count(inventory, item_id) >= ItemCatalog.stack_limit(item_data):
				continue
			var unit_price := EconomyModel.buy_price(item_data, merchant_data, entry)
			if unit_price > 0 and EconomyModel.balance(balances, currency_id) >= unit_price:
				return true
	return false


static func audit_market_arbitrage(
	items: Dictionary,
	currencies: Dictionary,
	merchants: Dictionary,
	supply_regions: Dictionary,
	findings: Array[Dictionary]
) -> Dictionary:
	var pairs: Dictionary = {}
	for merchant_id in sorted_dictionary_keys(merchants):
		var merchant_data := EconomyCatalog.merchant(merchants, merchant_id)
		if merchant_data.is_empty() or not is_unconditional(merchant_data):
			continue
		var currency_id := EconomyCatalog.merchant_currency_id(merchant_data)
		if not currencies.has(currency_id):
			continue
		for entry_value in EconomyCatalog.stock_entries(merchant_data):
			if typeof(entry_value) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_value
			if not is_unconditional(entry) or not stock_can_supply_one(entry):
				continue
			var item_id := str(entry.get("item_id", ""))
			var item_data := ItemCatalog.item(items, item_id)
			if item_data.is_empty():
				continue
			var unit_price := EconomyModel.buy_price(item_data, merchant_data, entry)
			if unit_price <= 0:
				continue
			var key := market_key(currency_id, item_id)
			var record: Dictionary = dictionary_value(pairs.get(key, {}))
			if record.is_empty():
				record = {
					"currency_id": currency_id,
					"item_id": item_id,
					"cheapest_buy_price": unit_price,
					"cheapest_buy_merchant": merchant_id,
					"cheapest_repeatable_buy_price": -1,
					"cheapest_repeatable_buy_merchant": ""
				}
			elif unit_price < int(record.get("cheapest_buy_price", unit_price)):
				record["cheapest_buy_price"] = unit_price
				record["cheapest_buy_merchant"] = merchant_id
			if source_is_repeatable(merchant_data, entry, supply_regions):
				var repeatable_price := int(record.get("cheapest_repeatable_buy_price", -1))
				if repeatable_price < 0 or unit_price < repeatable_price:
					record["cheapest_repeatable_buy_price"] = unit_price
					record["cheapest_repeatable_buy_merchant"] = merchant_id
			pairs[key] = record

	var arbitrage_route_count := 0
	var repeatable_arbitrage_count := 0
	for key in sorted_dictionary_keys(pairs):
		var record: Dictionary = pairs.get(key, {})
		var currency_id := str(record.get("currency_id", ""))
		var item_id := str(record.get("item_id", ""))
		var item_data := ItemCatalog.item(items, item_id)
		var highest_sell_price := 0
		var highest_sell_merchant := ""
		for merchant_id in sorted_dictionary_keys(merchants):
			var merchant_data := EconomyCatalog.merchant(merchants, merchant_id)
			if (
				merchant_data.is_empty()
				or not is_unconditional(merchant_data)
				or EconomyCatalog.merchant_currency_id(merchant_data) != currency_id
				or not EconomyModel.merchant_accepts_item(merchant_data, item_id, item_data)
			):
				continue
			var sell_price := EconomyModel.sell_price(
				item_data,
				merchant_data,
				EconomyCatalog.stock_entry(merchant_data, item_id)
			)
			if sell_price > highest_sell_price:
				highest_sell_price = sell_price
				highest_sell_merchant = merchant_id
		var cheapest_buy_price := int(record.get("cheapest_buy_price", 0))
		if highest_sell_price > cheapest_buy_price and cheapest_buy_price > 0:
			arbitrage_route_count += 1
		var repeatable_buy_price := int(record.get("cheapest_repeatable_buy_price", -1))
		if repeatable_buy_price > 0 and highest_sell_price > repeatable_buy_price:
			repeatable_arbitrage_count += 1
			add_finding(
				findings,
				"blocker",
				"economy.repeatable_arbitrage",
				"'%s' can be bought repeatedly from '%s' for %d and sold to '%s' for %d in the same currency, minting %d per cycle." % [
					ItemCatalog.item_name(item_data, item_id),
					str(record.get("cheapest_repeatable_buy_merchant", "")),
					repeatable_buy_price,
					highest_sell_merchant,
					highest_sell_price,
					highest_sell_price - repeatable_buy_price
				],
				item_id
			)
	return {
		"scenario_count": pairs.size(),
		"arbitrage_route_count": arbitrage_route_count,
		"repeatable_arbitrage_count": repeatable_arbitrage_count
	}


static func audit_endurance(
	items: Dictionary,
	merchants: Dictionary,
	supply_regions: Dictionary,
	healing_ids: Dictionary,
	ammunition_ids: Dictionary,
	findings: Array[Dictionary]
) -> Dictionary:
	var recovery_source_exists := false
	var ammunition_source_exists := false
	var recovery_sustainable := false
	var ammunition_sustainable := false
	var renewable_recovery_units := 0
	var renewable_ammo_units := 0
	var finite_progression_stock_count := 0
	var scenario_count := 0

	for merchant_id in sorted_dictionary_keys(merchants):
		var merchant_data := EconomyCatalog.merchant(merchants, merchant_id)
		if merchant_data.is_empty():
			continue
		var region_id := SupplyRegionCatalog.merchant_region_id(merchant_data)
		var region_data := SupplyRegionCatalog.region(supply_regions, region_id)
		for entry_value in EconomyCatalog.stock_entries(merchant_data):
			if typeof(entry_value) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_value
			var item_id := str(entry.get("item_id", ""))
			var item_data := ItemCatalog.item(items, item_id)
			if item_data.is_empty() or not stock_can_supply_one(entry):
				continue
			scenario_count += 1
			var unlimited := EconomyCatalog.stock_is_unlimited(entry)
			var renewable := not region_data.is_empty() and SupplyRegionCatalog.stock_is_renewable(entry)
			var horizon_units := renewable_units_for_horizon(entry, region_data) if renewable else 0
			if healing_ids.has(item_id):
				recovery_source_exists = true
				recovery_sustainable = recovery_sustainable or unlimited or renewable
				renewable_recovery_units += horizon_units
			if ammunition_ids.has(item_id):
				ammunition_source_exists = true
				ammunition_sustainable = ammunition_sustainable or unlimited or renewable
				renewable_ammo_units += horizon_units
			var kind := ItemCatalog.item_kind(item_data)
			if (
				not unlimited
				and not renewable
				and EconomyCatalog.initial_stock_quantity(entry) > 0
				and kind in ["equipment", "key"]
			):
				finite_progression_stock_count += 1

	if recovery_source_exists and not recovery_sustainable:
		add_finding(
			findings,
			"warning",
			"economy.recovery_endurance_risk",
			"Healing items exist in merchant stock, but every merchant source is finite and non-renewable across the deterministic thirty-minute active-play horizon.",
			"recovery"
		)
	if ammunition_source_exists and not ammunition_sustainable:
		add_finding(
			findings,
			"warning",
			"economy.ammo_endurance_risk",
			"Authored ranged equipment consumes merchant ammunition, but every merchant ammunition source is finite and non-renewable across the deterministic thirty-minute active-play horizon.",
			"ammunition"
		)
	return {
		"scenario_count": scenario_count,
		"renewable_recovery_units": renewable_recovery_units,
		"renewable_ammo_units": renewable_ammo_units,
		"finite_progression_stock_count": finite_progression_stock_count
	}


static func renewable_units_for_horizon(entry: Dictionary, region_data: Dictionary) -> int:
	var interval := SupplyRegionCatalog.interval_seconds(region_data)
	if interval <= 0.0:
		return 0
	var cycles := int(floor(SIMULATION_HORIZON_SECONDS / interval))
	return cycles * SupplyRegionCatalog.stock_restock_quantity(entry)


static func source_is_repeatable(
	merchant_data: Dictionary,
	entry: Dictionary,
	supply_regions: Dictionary
) -> bool:
	if EconomyCatalog.stock_is_unlimited(entry):
		return true
	var region_id := SupplyRegionCatalog.merchant_region_id(merchant_data)
	return (
		not SupplyRegionCatalog.region(supply_regions, region_id).is_empty()
		and SupplyRegionCatalog.stock_is_renewable(entry)
	)


static func stock_can_supply_one(entry: Dictionary) -> bool:
	return EconomyCatalog.stock_is_unlimited(entry) or EconomyCatalog.initial_stock_quantity(entry) > 0


static func is_unconditional(record: Dictionary) -> bool:
	return StoryCatalog.conditions(record).is_empty()


static func owns_healing_item(inventory: Dictionary, healing_ids: Dictionary) -> bool:
	for item_id in sorted_dictionary_keys(healing_ids):
		if InventoryModel.count(inventory, item_id) > 0:
			return true
	return false


static func healing_item_ids(items: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for item_id in sorted_dictionary_keys(items):
		var item_data := ItemCatalog.item(items, item_id)
		if ItemCatalog.item_kind(item_data) != "consumable":
			continue
		var effect := ItemCatalog.use_effect(item_data)
		if str(effect.get("type", "")) == "heal" and int(effect.get("amount", 0)) > 0:
			output[item_id] = true
	return output


static func authored_ammunition_ids(items: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for item_id in sorted_dictionary_keys(items):
		var item_data := ItemCatalog.item(items, item_id)
		if ItemCatalog.item_kind(item_data) != "equipment":
			continue
		var equipment := dictionary_value(item_data.get("equipment", {}))
		var ranged := dictionary_value(equipment.get("ranged", {}))
		var ammo_item_id := str(ranged.get("ammo_item_id", ""))
		if not ammo_item_id.is_empty() and ItemCatalog.item_kind(ItemCatalog.item(items, ammo_item_id)) == "ammunition":
			output[ammo_item_id] = true
	return output


static func preparation_category(item_data: Dictionary) -> String:
	if is_healing_item(item_data):
		return "recovery"
	match ItemCatalog.item_kind(item_data):
		"ammunition":
			return "ammunition"
		"equipment":
			return "equipment"
		"material":
			return "material"
		_:
			return ""


static func is_healing_item(item_data: Dictionary) -> bool:
	if ItemCatalog.item_kind(item_data) != "consumable":
		return false
	var effect := ItemCatalog.use_effect(item_data)
	return str(effect.get("type", "")) == "heal" and int(effect.get("amount", 0)) > 0


static func market_key(currency_id: String, item_id: String) -> String:
	return "%s\u001f%s" % [currency_id, item_id]


static func dictionary_value(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func sorted_dictionary_keys(value: Dictionary) -> PackedStringArray:
	var keys := PackedStringArray()
	for key_value in value.keys():
		keys.append(str(key_value))
	keys.sort()
	return keys


static func add_finding(
	findings: Array[Dictionary],
	severity: String,
	code: String,
	message: String,
	context: String = ""
) -> void:
	findings.append({
		"severity": severity,
		"code": code,
		"message": message,
		"context": context
	})
