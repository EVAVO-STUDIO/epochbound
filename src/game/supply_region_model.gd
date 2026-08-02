extends RefCounted

const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")


static func cycle_at(region_data: Dictionary, play_time_seconds: float) -> int:
	return maxi(0, int(floor(maxf(0.0, play_time_seconds) / SupplyCatalog.interval_seconds(region_data))))


static func seconds_until_next_cycle(region_data: Dictionary, play_time_seconds: float) -> float:
	var interval := SupplyCatalog.interval_seconds(region_data)
	var elapsed := fposmod(maxf(0.0, play_time_seconds), interval)
	if elapsed <= 0.0001 and play_time_seconds > 0.0:
		return interval
	return maxf(0.0, interval - elapsed)


static func initial_cycles(region_definitions: Dictionary, play_time_seconds: float = 0.0) -> Dictionary:
	var output: Dictionary = {}
	for region_id in sorted_ids(region_definitions):
		output[region_id] = cycle_at(SupplyCatalog.region(region_definitions, region_id), play_time_seconds)
	return output


static func sanitize_cycles(
	value: Variant,
	region_definitions: Dictionary,
	play_time_seconds: float
) -> Dictionary:
	var source: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var output: Dictionary = {}
	for region_id in sorted_ids(region_definitions):
		var region_data := SupplyCatalog.region(region_definitions, region_id)
		var current_cycle := cycle_at(region_data, play_time_seconds)
		var saved_cycle := int(source.get(region_id, current_cycle))
		output[region_id] = clampi(saved_cycle, 0, current_cycle)
	return output


static func apply_due_restock(
	merchant_stock: Dictionary,
	merchant_definitions: Dictionary,
	region_definitions: Dictionary,
	region_cycles: Dictionary,
	play_time_seconds: float
) -> Dictionary:
	var total_added := 0
	var cycles_advanced := 0
	var region_reports: Array = []
	var merchant_additions: Dictionary = {}
	for region_id in sorted_ids(region_definitions):
		var region_data := SupplyCatalog.region(region_definitions, region_id)
		var current_cycle := cycle_at(region_data, play_time_seconds)
		var previous_cycle := clampi(int(region_cycles.get(region_id, current_cycle)), 0, current_cycle)
		var due_cycles := maxi(0, current_cycle - previous_cycle)
		if due_cycles <= 0:
			region_cycles[region_id] = current_cycle
			continue
		cycles_advanced += due_cycles
		var applied_cycles := mini(due_cycles, SupplyCatalog.max_catchup_cycles(region_data))
		var region_added := 0
		for merchant_id in sorted_ids(merchant_definitions):
			var merchant_data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
			if SupplyCatalog.merchant_region_id(merchant_data) != region_id:
				continue
			var state_value: Variant = merchant_stock.get(merchant_id, {})
			var merchant_state: Dictionary = state_value if typeof(state_value) == TYPE_DICTIONARY else {}
			var merchant_added := 0
			for entry_value in EconomyCatalog.stock_entries(merchant_data):
				if typeof(entry_value) != TYPE_DICTIONARY:
					continue
				var entry: Dictionary = entry_value
				if not SupplyCatalog.stock_is_renewable(entry):
					continue
				var item_id := str(entry.get("item_id", ""))
				if item_id.is_empty():
					continue
				var before := clampi(
					int(merchant_state.get(item_id, EconomyCatalog.initial_stock_quantity(entry))),
					0,
					EconomyCatalog.MAX_STOCK
				)
				var target := SupplyCatalog.stock_restock_target(entry)
				var requested := SupplyCatalog.stock_restock_quantity(entry) * applied_cycles
				var added := mini(maxi(0, target - before), requested)
				if added <= 0:
					continue
				merchant_state[item_id] = before + added
				merchant_added += added
			merchant_stock[merchant_id] = merchant_state
			if merchant_added > 0:
				merchant_additions[merchant_id] = int(merchant_additions.get(merchant_id, 0)) + merchant_added
				region_added += merchant_added
		region_cycles[region_id] = current_cycle
		total_added += region_added
		region_reports.append({
			"region_id": region_id,
			"due_cycles": due_cycles,
			"applied_cycles": applied_cycles,
			"discarded_cycles": maxi(0, due_cycles - applied_cycles),
			"added": region_added
		})
	return {
		"changed": cycles_advanced > 0,
		"cycles_advanced": cycles_advanced,
		"total_added": total_added,
		"regions": region_reports,
		"merchant_additions": merchant_additions
	}


static func merchant_has_renewable_stock(merchant_data: Dictionary) -> bool:
	for entry_value in EconomyCatalog.stock_entries(merchant_data):
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		if SupplyCatalog.stock_is_renewable(entry_value as Dictionary):
			return true
	return false


static func sorted_ids(definitions: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in definitions.keys():
		output.append(str(key_value))
	output.sort()
	return output
