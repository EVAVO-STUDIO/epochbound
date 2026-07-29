extends RefCounted

const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const StoryModel = preload("res://src/game/story_model.gd")


static func initial_balances(currency_definitions: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for currency_id_value in currency_definitions.keys():
		var currency_id := str(currency_id_value)
		var currency_data := EconomyCatalog.currency(currency_definitions, currency_id)
		output[currency_id] = EconomyCatalog.starting_balance(currency_data)
	return output


static func initial_stock(merchant_definitions: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for merchant_id_value in merchant_definitions.keys():
		var merchant_id := str(merchant_id_value)
		var merchant_data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
		var merchant_state: Dictionary = {}
		for value in EconomyCatalog.stock_entries(merchant_data):
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = value
			var item_id := str(entry.get("item_id", ""))
			if not item_id.is_empty():
				merchant_state[item_id] = EconomyCatalog.initial_stock_quantity(entry)
		output[merchant_id] = merchant_state
	return output


static func sanitize_balances(
	value: Variant,
	currency_definitions: Dictionary,
	initialize_missing: bool = true
) -> Dictionary:
	var source: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var output: Dictionary = {}
	for currency_id_value in currency_definitions.keys():
		var currency_id := str(currency_id_value)
		var currency_data := EconomyCatalog.currency(currency_definitions, currency_id)
		var fallback := EconomyCatalog.starting_balance(currency_data) if initialize_missing else 0
		output[currency_id] = clampi(int(source.get(currency_id, fallback)), 0, EconomyCatalog.max_balance(currency_data))
	return output


static func sanitize_stock(
	value: Variant,
	merchant_definitions: Dictionary,
	initialize_missing: bool = true
) -> Dictionary:
	var source: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var output: Dictionary = {}
	for merchant_id_value in merchant_definitions.keys():
		var merchant_id := str(merchant_id_value)
		var merchant_data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
		var merchant_source_value: Variant = source.get(merchant_id, {})
		var merchant_source: Dictionary = merchant_source_value if typeof(merchant_source_value) == TYPE_DICTIONARY else {}
		var merchant_state: Dictionary = {}
		var authored := EconomyCatalog.stock_entry_index(merchant_data)
		for item_id_value in authored.keys():
			var item_id := str(item_id_value)
			var entry: Dictionary = authored.get(item_id, {})
			var fallback := EconomyCatalog.initial_stock_quantity(entry) if initialize_missing else 0
			var quantity := int(merchant_source.get(item_id, fallback))
			if EconomyCatalog.stock_is_unlimited(entry):
				merchant_state[item_id] = -1
			else:
				merchant_state[item_id] = clampi(quantity, 0, EconomyCatalog.MAX_STOCK)
		if EconomyCatalog.merchant_resells_player_goods(merchant_data):
			for item_key in merchant_source.keys():
				var item_id := str(item_key)
				if merchant_state.has(item_id):
					continue
				var quantity := int(merchant_source.get(item_key, 0))
				if quantity > 0:
					merchant_state[item_id] = clampi(quantity, 0, EconomyCatalog.MAX_STOCK)
		output[merchant_id] = merchant_state
	return output


static func balance(balances: Dictionary, currency_id: String) -> int:
	return maxi(0, int(balances.get(currency_id, 0)))


static func add_currency(
	balances: Dictionary,
	currency_definitions: Dictionary,
	currency_id: String,
	amount: int
) -> Dictionary:
	var currency_data := EconomyCatalog.currency(currency_definitions, currency_id)
	if currency_data.is_empty() or amount <= 0:
		return {"ok": false, "added": 0, "overflow": maxi(0, amount)}
	var before := balance(balances, currency_id)
	var maximum := EconomyCatalog.max_balance(currency_data)
	var added := mini(amount, maxi(0, maximum - before))
	if added > 0:
		balances[currency_id] = before + added
	return {"ok": added == amount, "added": added, "overflow": amount - added}


static func remove_currency(balances: Dictionary, currency_id: String, amount: int) -> bool:
	if amount <= 0 or balance(balances, currency_id) < amount:
		return false
	var next := balance(balances, currency_id) - amount
	balances[currency_id] = next
	return true


static func merchant_available(merchant_data: Dictionary, context: Dictionary) -> bool:
	return StoryModel.conditions_met(StoryCatalog.conditions(merchant_data), context)


static func stock_entry_available(entry: Dictionary, context: Dictionary) -> bool:
	return StoryModel.conditions_met(StoryCatalog.conditions(entry), context)


static func stock_quantity(merchant_stock: Dictionary, merchant_id: String, item_id: String) -> int:
	var merchant_value: Variant = merchant_stock.get(merchant_id, {})
	if typeof(merchant_value) != TYPE_DICTIONARY:
		return 0
	return int((merchant_value as Dictionary).get(item_id, 0))


static func stock_available(merchant_stock: Dictionary, merchant_id: String, item_id: String, quantity: int = 1) -> bool:
	var available := stock_quantity(merchant_stock, merchant_id, item_id)
	return quantity > 0 and (available < 0 or available >= quantity)


static func buy_price(item_data: Dictionary, merchant_data: Dictionary, entry: Dictionary = {}) -> int:
	var override := int(entry.get("buy_price", 0))
	if override > 0:
		return override
	var base := maxi(0, int(item_data.get("value", 0)))
	if base <= 0:
		return 0
	return maxi(1, int(ceil(float(base) * EconomyCatalog.merchant_buy_multiplier(merchant_data))))


static func sell_price(item_data: Dictionary, merchant_data: Dictionary, entry: Dictionary = {}) -> int:
	var override := int(entry.get("sell_price", 0))
	if override > 0:
		return override
	var base := maxi(0, int(item_data.get("value", 0)))
	if base <= 0:
		return 0
	return maxi(1, int(floor(float(base) * EconomyCatalog.merchant_sell_multiplier(merchant_data))))


static func merchant_accepts_item(merchant_data: Dictionary, item_id: String, item_data: Dictionary) -> bool:
	if not EconomyCatalog.merchant_accepts_sales(merchant_data):
		return false
	if item_data.is_empty() or int(item_data.get("value", 0)) <= 0:
		return false
	if EconomyCatalog.refused_items(merchant_data).has(item_id):
		return false
	return EconomyCatalog.accepted_kinds(merchant_data).has(ItemCatalog.item_kind(item_data))


static func available_stock_ids(
	merchant_id: String,
	merchant_stock: Dictionary,
	merchant_definitions: Dictionary,
	item_definitions: Dictionary,
	context: Dictionary
) -> PackedStringArray:
	var merchant_data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
	var ids: Array[String] = []
	var merchant_state_value: Variant = merchant_stock.get(merchant_id, {})
	var merchant_state: Dictionary = merchant_state_value if typeof(merchant_state_value) == TYPE_DICTIONARY else {}
	var authored := EconomyCatalog.stock_entry_index(merchant_data)
	for item_key in merchant_state.keys():
		var item_id := str(item_key)
		if not item_definitions.has(item_id) or int(merchant_state.get(item_key, 0)) == 0:
			continue
		var entry_value: Variant = authored.get(item_id, {})
		var entry: Dictionary = entry_value if typeof(entry_value) == TYPE_DICTIONARY else {}
		if not entry.is_empty() and not stock_entry_available(entry, context):
			continue
		ids.append(item_id)
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_name := ItemCatalog.item_name(ItemCatalog.item(item_definitions, left), left)
		var right_name := ItemCatalog.item_name(ItemCatalog.item(item_definitions, right), right)
		return left_name.naturalnocasecmp_to(right_name) < 0
	)
	return PackedStringArray(ids)


static func sellable_inventory_ids(
	merchant_id: String,
	inventory: Dictionary,
	merchant_definitions: Dictionary,
	item_definitions: Dictionary,
	protected_item_ids: PackedStringArray = PackedStringArray()
) -> PackedStringArray:
	var merchant_data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
	var ids: Array[String] = []
	for item_key in inventory.keys():
		var item_id := str(item_key)
		if int(inventory.get(item_key, 0)) <= 0 or protected_item_ids.has(item_id):
			continue
		var item_data := ItemCatalog.item(item_definitions, item_id)
		if merchant_accepts_item(merchant_data, item_id, item_data):
			ids.append(item_id)
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_name := ItemCatalog.item_name(ItemCatalog.item(item_definitions, left), left)
		var right_name := ItemCatalog.item_name(ItemCatalog.item(item_definitions, right), right)
		return left_name.naturalnocasecmp_to(right_name) < 0
	)
	return PackedStringArray(ids)


static func buy_item(
	balances: Dictionary,
	merchant_stock: Dictionary,
	inventory: Dictionary,
	currency_definitions: Dictionary,
	merchant_definitions: Dictionary,
	item_definitions: Dictionary,
	merchant_id: String,
	item_id: String,
	quantity: int = 1,
	context: Dictionary = {}
) -> Dictionary:
	var merchant_data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
	if merchant_data.is_empty() or not merchant_available(merchant_data, context):
		return failure("merchant_unavailable", merchant_id, item_id)
	var item_data := ItemCatalog.item(item_definitions, item_id)
	if item_data.is_empty():
		return failure("unknown_item", merchant_id, item_id)
	var entry := EconomyCatalog.stock_entry(merchant_data, item_id)
	var dynamic_stock := entry.is_empty() and stock_quantity(merchant_stock, merchant_id, item_id) != 0
	if entry.is_empty() and not dynamic_stock:
		return failure("not_sold_here", merchant_id, item_id)
	if not entry.is_empty() and not stock_entry_available(entry, context):
		return failure("stock_unavailable", merchant_id, item_id)
	if quantity <= 0 or not stock_available(merchant_stock, merchant_id, item_id, quantity):
		return failure("out_of_stock", merchant_id, item_id)
	var current := InventoryModel.count(inventory, item_id)
	if current + quantity > ItemCatalog.stack_limit(item_data):
		return failure("stack_full", merchant_id, item_id)
	var unit_price := buy_price(item_data, merchant_data, entry)
	if unit_price <= 0:
		return failure("not_for_sale", merchant_id, item_id)
	var currency_id := EconomyCatalog.merchant_currency_id(merchant_data)
	var total := unit_price * quantity
	if balance(balances, currency_id) < total:
		return failure("insufficient_funds", merchant_id, item_id, currency_id, total)
	if not remove_currency(balances, currency_id, total):
		return failure("insufficient_funds", merchant_id, item_id, currency_id, total)
	var add_result := InventoryModel.add_item(inventory, item_definitions, item_id, quantity)
	if int(add_result.get("added", 0)) != quantity:
		add_currency(balances, currency_definitions, currency_id, total)
		return failure("stack_full", merchant_id, item_id, currency_id, total)
	var merchant_state: Dictionary = merchant_stock.get(merchant_id, {})
	var before_stock := int(merchant_state.get(item_id, 0))
	if before_stock >= 0:
		merchant_state[item_id] = before_stock - quantity
	merchant_stock[merchant_id] = merchant_state
	return {
		"ok": true,
		"reason": "bought",
		"merchant_id": merchant_id,
		"item_id": item_id,
		"quantity": quantity,
		"currency_id": currency_id,
		"unit_price": unit_price,
		"total": total
	}


static func sell_item(
	balances: Dictionary,
	merchant_stock: Dictionary,
	inventory: Dictionary,
	currency_definitions: Dictionary,
	merchant_definitions: Dictionary,
	item_definitions: Dictionary,
	merchant_id: String,
	item_id: String,
	quantity: int = 1,
	protected_item_ids: PackedStringArray = PackedStringArray(),
	context: Dictionary = {}
) -> Dictionary:
	var merchant_data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
	if merchant_data.is_empty() or not merchant_available(merchant_data, context):
		return failure("merchant_unavailable", merchant_id, item_id)
	if quantity <= 0 or InventoryModel.count(inventory, item_id) < quantity:
		return failure("not_owned", merchant_id, item_id)
	if protected_item_ids.has(item_id):
		return failure("equipped_item", merchant_id, item_id)
	var item_data := ItemCatalog.item(item_definitions, item_id)
	if not merchant_accepts_item(merchant_data, item_id, item_data):
		return failure("merchant_refuses", merchant_id, item_id)
	var entry := EconomyCatalog.stock_entry(merchant_data, item_id)
	var unit_price := sell_price(item_data, merchant_data, entry)
	if unit_price <= 0:
		return failure("merchant_refuses", merchant_id, item_id)
	var currency_id := EconomyCatalog.merchant_currency_id(merchant_data)
	var total := unit_price * quantity
	var currency_data := EconomyCatalog.currency(currency_definitions, currency_id)
	if currency_data.is_empty() or balance(balances, currency_id) + total > EconomyCatalog.max_balance(currency_data):
		return failure("wallet_full", merchant_id, item_id, currency_id, total)
	if not InventoryModel.remove_item(inventory, item_id, quantity):
		return failure("not_owned", merchant_id, item_id)
	var currency_result := add_currency(balances, currency_definitions, currency_id, total)
	if int(currency_result.get("added", 0)) != total:
		InventoryModel.add_item(inventory, item_definitions, item_id, quantity)
		return failure("wallet_full", merchant_id, item_id, currency_id, total)
	if EconomyCatalog.merchant_resells_player_goods(merchant_data):
		var merchant_state: Dictionary = merchant_stock.get(merchant_id, {})
		var before_stock := int(merchant_state.get(item_id, 0))
		if before_stock >= 0:
			merchant_state[item_id] = clampi(before_stock + quantity, 0, EconomyCatalog.MAX_STOCK)
		merchant_stock[merchant_id] = merchant_state
	return {
		"ok": true,
		"reason": "sold",
		"merchant_id": merchant_id,
		"item_id": item_id,
		"quantity": quantity,
		"currency_id": currency_id,
		"unit_price": unit_price,
		"total": total
	}


static func failure(
	reason: String,
	merchant_id: String,
	item_id: String,
	currency_id: String = "",
	total: int = 0
) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"merchant_id": merchant_id,
		"item_id": item_id,
		"currency_id": currency_id,
		"total": total
	}
