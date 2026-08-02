@tool
extends RefCounted

const ItemCatalog = preload("res://src/content/item_catalog.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const EconomyModel = preload("res://src/game/economy_model.gd")

const SOURCE_QUANTITY_UNLIMITED := -1

static func build_item_source_index(
	campaign: Dictionary,
	maps: Dictionary,
	items: Dictionary,
	recipes: Dictionary,
	story: Dictionary,
	economy: Dictionary,
	objects: Dictionary,
	merchant_bindings: Dictionary
) -> Dictionary:
	var output: Dictionary = {}
	for entry_value in campaign.get("starting_inventory", []):
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		add_item_source(output, str(entry.get("item_id", "")), {
			"kind": "starting_inventory",
			"context": "campaign.starting_inventory",
			"quantity": maxi(0, int(entry.get("quantity", 0))),
			"gated": false,
			"gate_items": PackedStringArray(),
			"gate_capabilities": PackedStringArray()
		})
	var starting_equipment_value: Variant = campaign.get("starting_equipment", {})
	if typeof(starting_equipment_value) == TYPE_DICTIONARY:
		for item_id_value in (starting_equipment_value as Dictionary).values():
			add_item_source(output, str(item_id_value), {
				"kind": "starting_equipment",
				"context": "campaign.starting_equipment",
				"quantity": 1,
				"gated": false,
				"gate_items": PackedStringArray(),
				"gate_capabilities": PackedStringArray()
			})

	collect_item_grant_sources(story, "story", output, PackedStringArray(), PackedStringArray(), false)
	for map_id in sorted_dictionary_keys(maps):
		var map_data: Dictionary = maps.get(map_id, {})
		collect_item_grant_sources(map_data, "map:%s" % map_id, output, PackedStringArray(), PackedStringArray(), false)
		for placement_value in map_data.get("object_placements", []):
			if typeof(placement_value) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placement_value
			var object_id := str(placement.get("object_id", ""))
			var definition: Dictionary = objects.get(object_id, {})
			var gate_items := PackedStringArray()
			var gate_capabilities := PackedStringArray()
			collect_gate_requirements(placement, gate_items, gate_capabilities)
			collect_gate_requirements(definition, gate_items, gate_capabilities)
			var gated := source_record_is_gated(placement) or source_record_is_gated(definition)
			for grant_field in ["item_grants", "reward_items"]:
				for grant_value in definition.get(grant_field, []):
					if typeof(grant_value) != TYPE_DICTIONARY:
						continue
					var grant: Dictionary = grant_value
					add_item_source(output, str(grant.get("item_id", "")), {
						"kind": "object_placement",
						"context": "%s:%s" % [map_id, str(placement.get("id", object_id))],
						"quantity": maxi(0, int(grant.get("quantity", 0))),
						"gated": gated,
						"gate_items": gate_items.duplicate(),
						"gate_capabilities": gate_capabilities.duplicate()
					})

	for recipe_id in sorted_dictionary_keys(recipes):
		var recipe: Dictionary = recipes.get(recipe_id, {})
		var output_value: Variant = recipe.get("output", {})
		if typeof(output_value) != TYPE_DICTIONARY:
			continue
		var item_id := str((output_value as Dictionary).get("item_id", ""))
		if item_id.is_empty():
			continue
		add_item_source(output, item_id, {
			"kind": "recipe",
			"context": recipe_id,
			"quantity": SOURCE_QUANTITY_UNLIMITED,
			"gated": not bool(recipe.get("unlocked_by_default", false)) and not ItemCatalog.starting_recipes(campaign).has(recipe_id),
			"gate_items": PackedStringArray(),
			"gate_capabilities": PackedStringArray()
		})

	var merchants: Dictionary = economy.get("merchants", {})
	for merchant_id in sorted_dictionary_keys(merchants):
		var merchant: Dictionary = merchants.get(merchant_id, {})
		for stock_value in merchant.get("stock", []):
			if typeof(stock_value) != TYPE_DICTIONARY:
				continue
			var stock: Dictionary = stock_value
			var item_id := str(stock.get("item_id", ""))
			var gate_items := PackedStringArray()
			var gate_capabilities := PackedStringArray()
			collect_gate_requirements(merchant, gate_items, gate_capabilities)
			collect_gate_requirements(stock, gate_items, gate_capabilities)
			var quantity := SOURCE_QUANTITY_UNLIMITED if bool(stock.get("unlimited", false)) else maxi(0, int(stock.get("quantity", 0)))
			var item_data: Dictionary = items.get(item_id, {})
			add_item_source(output, item_id, {
				"kind": "merchant",
				"context": merchant_id,
				"quantity": quantity,
				"gated": source_record_is_gated(merchant) or source_record_is_gated(stock),
				"gate_items": gate_items,
				"gate_capabilities": gate_capabilities,
				"bound": merchant_bindings.has(merchant_id),
				"currency_id": EconomyCatalog.merchant_currency_id(merchant),
				"unit_price": EconomyModel.buy_price(item_data, merchant, stock)
			})
	return output


static func collect_item_grant_sources(
	value: Variant,
	context: String,
	output: Dictionary,
	inherited_items: PackedStringArray,
	inherited_capabilities: PackedStringArray,
	inherited_gated: bool
) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		var gate_items := inherited_items.duplicate()
		var gate_capabilities := inherited_capabilities.duplicate()
		collect_gate_requirements(data, gate_items, gate_capabilities)
		var gated := inherited_gated or not gate_items.is_empty() or not gate_capabilities.is_empty() or source_record_is_gated(data)
		if str(data.get("type", "")) == "grant_item":
			add_item_source(output, str(data.get("item_id", "")), {
				"kind": "story_grant",
				"context": context,
				"quantity": maxi(0, int(data.get("quantity", 0))),
				"gated": gated,
				"gate_items": gate_items.duplicate(),
				"gate_capabilities": gate_capabilities.duplicate()
			})
		for grant_field in ["item_grants", "reward_items"]:
			var grant_is_gated := gated or grant_field == "reward_items"
			for grant_value in data.get(grant_field, []):
				if typeof(grant_value) != TYPE_DICTIONARY:
					continue
				var grant: Dictionary = grant_value
				add_item_source(output, str(grant.get("item_id", "")), {
					"kind": "authored_grant",
					"context": context,
					"quantity": maxi(0, int(grant.get("quantity", 0))),
					"gated": grant_is_gated,
					"gate_items": gate_items.duplicate(),
					"gate_capabilities": gate_capabilities.duplicate()
				})
		for key_value in data.keys():
			var key := str(key_value)
			var child_gated := gated or ["rewards", "defeat_effects"].has(key)
			collect_item_grant_sources(data.get(key_value), context, output, gate_items, gate_capabilities, child_gated)
	elif typeof(value) == TYPE_ARRAY:
		for child_value in value:
			collect_item_grant_sources(child_value, context, output, inherited_items, inherited_capabilities, inherited_gated)


static func add_item_source(output: Dictionary, item_id: String, source: Dictionary) -> void:
	if item_id.is_empty() or int(source.get("quantity", 0)) == 0:
		return
	var current_value: Variant = output.get(item_id, [])
	var current: Array = current_value as Array if typeof(current_value) == TYPE_ARRAY else []
	current.append(source)
	output[item_id] = current


static func source_record_is_gated(record: Dictionary) -> bool:
	var conditions_value: Variant = record.get("conditions", [])
	if typeof(conditions_value) == TYPE_ARRAY and not (conditions_value as Array).is_empty():
		return true
	var required_value: Variant = record.get("required_capabilities", [])
	return typeof(required_value) == TYPE_ARRAY and not (required_value as Array).is_empty()


static func collect_gate_requirements(
	value: Variant,
	item_ids: PackedStringArray,
	capability_ids: PackedStringArray
) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		var type_id := str(data.get("type", ""))
		if type_id == "has_item":
			append_unique(item_ids, str(data.get("item_id", "")))
		elif type_id == "has_capability":
			append_unique(capability_ids, str(data.get("capability_id", "")))
		var required_value: Variant = data.get("required_capabilities", [])
		if typeof(required_value) == TYPE_ARRAY:
			for capability_value in required_value:
				append_unique(capability_ids, str(capability_value))
		var conditions_value: Variant = data.get("conditions", [])
		if typeof(conditions_value) == TYPE_ARRAY:
			for condition_value in conditions_value:
				collect_gate_requirements(condition_value, item_ids, capability_ids)
	elif typeof(value) == TYPE_ARRAY:
		for child_value in value:
			collect_gate_requirements(child_value, item_ids, capability_ids)


static func append_unique(values: PackedStringArray, value: String) -> void:
	var clean := value.strip_edges()
	if not clean.is_empty() and not values.has(clean):
		values.append(clean)


static func merchant_binding_index(objects: Dictionary, maps: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for map_id in sorted_dictionary_keys(maps):
		var map_data: Dictionary = maps.get(map_id, {})
		for placement_value in map_data.get("object_placements", []):
			if typeof(placement_value) != TYPE_DICTIONARY:
				continue
			var object_id := str((placement_value as Dictionary).get("object_id", ""))
			var definition: Dictionary = objects.get(object_id, {})
			var merchant_id := str(definition.get("merchant_id", ""))
			if not merchant_id.is_empty():
				output[merchant_id] = true
	return output


static func source_array(value: Variant) -> Array:
	return value as Array if typeof(value) == TYPE_ARRAY else []


static func usable_item_sources(sources: Array) -> Array:
	var output: Array = []
	for source_value in sources:
		if typeof(source_value) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = source_value
		if str(source.get("kind", "")) == "merchant" and not bool(source.get("bound", false)):
			continue
		output.append(source)
	return output


static func has_unbound_merchant_source(sources: Array) -> bool:
	for source_value in sources:
		if typeof(source_value) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = source_value
		if str(source.get("kind", "")) == "merchant" and not bool(source.get("bound", false)):
			return true
	return false


static func every_source_is_gated(sources: Array) -> bool:
	if sources.is_empty():
		return false
	for source_value in sources:
		if typeof(source_value) != TYPE_DICTIONARY or not bool((source_value as Dictionary).get("gated", false)):
			return false
	return true


static func every_source_requires_item(sources: Array, item_id: String) -> bool:
	if sources.is_empty():
		return false
	for source_value in sources:
		if typeof(source_value) != TYPE_DICTIONARY:
			return false
		var source: Dictionary = source_value
		var gate_value: Variant = source.get("gate_items", PackedStringArray())
		var gate_items := PackedStringArray()
		if typeof(gate_value) == TYPE_PACKED_STRING_ARRAY:
			gate_items = gate_value as PackedStringArray
		if not gate_items.has(item_id):
			return false
	return true


static func every_source_requires_capability(sources: Array, capability_id: String) -> bool:
	if sources.is_empty():
		return false
	for source_value in sources:
		if typeof(source_value) != TYPE_DICTIONARY:
			return false
		var source: Dictionary = source_value
		var gate_value: Variant = source.get("gate_capabilities", PackedStringArray())
		var gate_capabilities := PackedStringArray()
		if typeof(gate_value) == TYPE_PACKED_STRING_ARRAY:
			gate_capabilities = gate_value as PackedStringArray
		if not gate_capabilities.has(capability_id):
			return false
	return true


static func finite_source_supply(sources: Array) -> Dictionary:
	var total := 0
	for source_value in sources:
		if typeof(source_value) != TYPE_DICTIONARY:
			continue
		var quantity := int((source_value as Dictionary).get("quantity", 0))
		if quantity < 0:
			return {"unlimited": true, "quantity": total}
		total += maxi(0, quantity)
	return {"unlimited": false, "quantity": total}


static func starting_capability_set(campaign: Dictionary, items: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for capability_value in campaign.get("base_capabilities", []):
		output[str(capability_value)] = true
	var equipment_value: Variant = campaign.get("starting_equipment", {})
	if typeof(equipment_value) != TYPE_DICTIONARY:
		return output
	for item_id_value in (equipment_value as Dictionary).values():
		var item: Dictionary = items.get(str(item_id_value), {})
		var item_equipment_value: Variant = item.get("equipment", {})
		if typeof(item_equipment_value) != TYPE_DICTIONARY:
			continue
		for capability_value in (item_equipment_value as Dictionary).get("capabilities", []):
			output[str(capability_value)] = true
	return output


static func items_granting_capability(items: Dictionary, capability_id: String) -> PackedStringArray:
	var output := PackedStringArray()
	for item_id in sorted_dictionary_keys(items):
		var item: Dictionary = items.get(item_id, {})
		var equipment_value: Variant = item.get("equipment", {})
		if typeof(equipment_value) != TYPE_DICTIONARY:
			continue
		var capabilities_value: Variant = (equipment_value as Dictionary).get("capabilities", [])
		if typeof(capabilities_value) == TYPE_ARRAY and (capabilities_value as Array).has(capability_id):
			output.append(item_id)
	return output


static func sorted_dictionary_keys(value: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in value.keys():
		output.append(str(key_value))
	output.sort()
	return output
