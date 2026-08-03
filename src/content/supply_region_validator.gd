@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/economy_validator.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyModel = preload("res://src/game/supply_region_model.gd")


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report := BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var region_count := 0
	var renewable_stock_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := validate_supply_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		region_count += int(report.get("supply_region_count", 0))
		renewable_stock_count += int(report.get("renewable_stock_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["supply_region_count"] = region_count
	output["renewable_stock_count"] = renewable_stock_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_campaign_path(campaign_path)
	var supply_report := validate_supply_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, supply_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, supply_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["supply_region_count"] = supply_report.get("supply_region_count", 0)
	output["renewable_stock_count"] = supply_report.get("renewable_stock_count", 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_profile(profile, campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings}
	var campaign: Dictionary = campaign_result.get("data", {})
	var supply_result := SupplyCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, supply_result.get("errors", []))
	var metadata_value: Variant = profile.get("metadata", {})
	var metadata: Dictionary = metadata_value if typeof(metadata_value) == TYPE_DICTIONARY else {}
	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) == TYPE_DICTIONARY:
		validate_profile_supply(
			payload_value as Dictionary,
			supply_result.get("definitions", {}),
			maxf(0.0, float(metadata.get("play_time_seconds", 0.0))),
			errors,
			warnings
		)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func validate_supply_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return make_report(errors, warnings, 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var supply_result := SupplyCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, supply_result.get("errors", []))
	var economy_result := EconomyCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, economy_result.get("errors", []))
	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	var region_sources: Dictionary = {}
	var renewable_count := 0
	for file_value in supply_result.get("files", []):
		if typeof(file_value) != TYPE_DICTIONARY:
			continue
		var file_record: Dictionary = file_value
		renewable_count += validate_catalog_file(
			file_record.get("data", {}),
			str(file_record.get("path", "economy catalog")),
			supply_result.get("definitions", {}),
			economy_result.get("merchants", {}),
			item_result.get("definitions", {}),
			region_sources,
			errors,
			warnings
		)
	return make_report(errors, warnings, (supply_result.get("definitions", {}) as Dictionary).size(), renewable_count)


static func validate_catalog_file(
	catalog: Dictionary,
	path: String,
	all_regions: Dictionary,
	all_merchants: Dictionary,
	items: Dictionary,
	region_sources: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> int:
	validate_region_records(catalog.get("supply_regions", []), path, region_sources, errors, warnings)
	var renewable_count := 0
	var merchants_value: Variant = catalog.get("merchants", [])
	if typeof(merchants_value) != TYPE_ARRAY:
		return renewable_count
	for merchant_value in merchants_value:
		if typeof(merchant_value) != TYPE_DICTIONARY:
			continue
		var merchant: Dictionary = merchant_value
		var merchant_id := str(merchant.get("id", ""))
		var prefix := "%s/merchant/%s" % [path, merchant_id if not merchant_id.is_empty() else "merchant"]
		var region_value: Variant = merchant.get("supply_region_id", "")
		var region_id := ""
		if merchant.has("supply_region_id") and typeof(region_value) != TYPE_STRING:
			errors.append("%s: supply_region_id must be a string." % prefix)
		elif typeof(region_value) == TYPE_STRING:
			region_id = str(region_value).strip_edges()
		if not region_id.is_empty() and not all_regions.has(region_id):
			errors.append("%s: unknown supply_region_id '%s'." % [prefix, region_id])
		var merchant_renewable := 0
		for stock_value in EconomyCatalog.stock_entries(merchant):
			if typeof(stock_value) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = stock_value
			var item_id := str(entry.get("item_id", ""))
			var stock_prefix := "%s/stock/%s" % [prefix, item_id if not item_id.is_empty() else "item"]
			var initial_quantity := EconomyCatalog.initial_stock_quantity(entry)
			var restock_quantity_value: Variant = entry.get("restock_quantity", 0)
			var restock_target_value: Variant = entry.get("restock_target", initial_quantity)
			var restock_quantity := 0
			var restock_target := initial_quantity
			if typeof(restock_quantity_value) != TYPE_INT:
				errors.append("%s: restock_quantity must be an integer." % stock_prefix)
			else:
				restock_quantity = int(restock_quantity_value)
			if typeof(restock_target_value) != TYPE_INT:
				errors.append("%s: restock_target must be an integer." % stock_prefix)
			else:
				restock_target = int(restock_target_value)
			if restock_quantity < 0 or restock_quantity > EconomyCatalog.MAX_STOCK:
				errors.append("%s: restock_quantity must be between zero and %d." % [stock_prefix, EconomyCatalog.MAX_STOCK])
			if restock_target < 0 or restock_target > EconomyCatalog.MAX_STOCK:
				errors.append("%s: restock_target must be between zero and %d." % [stock_prefix, EconomyCatalog.MAX_STOCK])
			if EconomyCatalog.stock_is_unlimited(entry):
				if restock_quantity > 0 or entry.has("restock_target"):
					errors.append("%s: unlimited stock cannot define replenishment fields." % stock_prefix)
				continue
			if restock_quantity <= 0:
				if entry.has("restock_target") and restock_target != initial_quantity:
					warnings.append("%s: restock_target has no effect while restock_quantity is zero." % stock_prefix)
				continue
			merchant_renewable += 1
			renewable_count += 1
			if region_id.is_empty():
				errors.append("%s: renewable stock requires the merchant to declare supply_region_id." % stock_prefix)
			if restock_target <= 0:
				errors.append("%s: renewable stock requires a positive restock_target." % stock_prefix)
			if restock_target < initial_quantity:
				errors.append("%s: restock_target cannot be lower than the initial quantity." % stock_prefix)
			var item_data := ItemCatalog.item(items, item_id)
			var kind := ItemCatalog.item_kind(item_data)
			if kind not in ["consumable", "material", "ammunition"]:
				errors.append("%s: only consumable, material or ammunition stock may replenish automatically." % stock_prefix)
		if not region_id.is_empty() and merchant_renewable == 0:
			warnings.append("%s: supply_region_id is declared but no finite stock entry replenishes." % prefix)
		if all_merchants.has(merchant_id) and not region_id.is_empty():
			var merged: Dictionary = all_merchants.get(merchant_id, {})
			if SupplyCatalog.merchant_region_id(merged) != region_id:
				errors.append("%s: merged merchant supply region drifted from its source record." % prefix)
	return renewable_count


static func validate_region_records(
	value: Variant,
	path: String,
	sources: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: supply_regions must be an array." % path)
		return
	var local_ids: Dictionary = {}
	for record_value in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("%s: every supply region must be an object." % path)
			continue
		var data: Dictionary = record_value
		var id_value: Variant = data.get("id", "")
		var region_id := ""
		if typeof(id_value) != TYPE_STRING:
			errors.append("%s/supply_region/region: id must be a string." % path)
		else:
			region_id = str(id_value)
		var prefix := "%s/supply_region/%s" % [path, region_id if not region_id.is_empty() else "region"]
		if typeof(id_value) == TYPE_STRING and region_id.is_empty():
			errors.append("%s: id is required." % prefix)
		elif not region_id.is_empty():
			if Repository.normalise_id(region_id) != region_id or region_id.length() > SupplyCatalog.MAX_REGION_ID_LENGTH:
				errors.append("%s: id must be a normalised lowercase identifier no longer than %d characters." % [prefix, SupplyCatalog.MAX_REGION_ID_LENGTH])
			elif local_ids.has(region_id):
				errors.append("%s: supply region is repeated." % prefix)
			else:
				local_ids[region_id] = true
				if sources.has(region_id) and sources[region_id] != path:
					errors.append("%s: supply region '%s' is also declared by %s." % [path, region_id, sources[region_id]])
				sources[region_id] = path
		var display_name_value: Variant = data.get("display_name", "")
		var display_name := ""
		if typeof(display_name_value) != TYPE_STRING:
			errors.append("%s: display_name must be a string." % prefix)
		else:
			display_name = str(display_name_value).strip_edges()
			if display_name.is_empty():
				errors.append("%s: display_name is required." % prefix)
			elif display_name.length() > SupplyCatalog.MAX_DISPLAY_NAME_LENGTH:
				errors.append("%s: display_name is too long." % prefix)
		var interval_value: Variant = data.get("restock_interval_seconds", null)
		var interval := 0.0
		var interval_valid := typeof(interval_value) in [TYPE_INT, TYPE_FLOAT]
		if not interval_valid:
			errors.append("%s: restock_interval_seconds must be numeric." % prefix)
		else:
			interval = float(interval_value)
			if interval < SupplyCatalog.MIN_INTERVAL_SECONDS or interval > SupplyCatalog.MAX_INTERVAL_SECONDS:
				errors.append("%s: restock_interval_seconds must be between %.0f and %.0f." % [prefix, SupplyCatalog.MIN_INTERVAL_SECONDS, SupplyCatalog.MAX_INTERVAL_SECONDS])
		var catchup_value: Variant = data.get("max_catchup_cycles", null)
		if typeof(catchup_value) != TYPE_INT:
			errors.append("%s: max_catchup_cycles must be an integer." % prefix)
		else:
			var catchup := int(catchup_value)
			if catchup < 1 or catchup > SupplyCatalog.MAX_CATCHUP_CYCLES:
				errors.append("%s: max_catchup_cycles must be between 1 and %d." % [prefix, SupplyCatalog.MAX_CATCHUP_CYCLES])
			elif interval_valid and interval >= 21600.0 and catchup == 1:
				warnings.append("%s: a long route with one catch-up cycle may recover stock very slowly after extended play." % prefix)


static func validate_profile_supply(
	payload: Dictionary,
	region_definitions: Dictionary,
	play_time_seconds: float,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var initialized_value: Variant = payload.get("supply_regions_initialized", false)
	var initialized := false
	if typeof(initialized_value) != TYPE_BOOL:
		errors.append("Save payload supply_regions_initialized must be boolean.")
	else:
		initialized = bool(initialized_value)
	var cycles_value: Variant = payload.get("supply_region_cycles", {})
	if typeof(cycles_value) != TYPE_DICTIONARY:
		errors.append("Save payload supply_region_cycles must be an object.")
		return
	var cycles: Dictionary = cycles_value
	for region_key in cycles.keys():
		if typeof(region_key) != TYPE_STRING:
			errors.append("Save supply_region_cycles keys must be strings.")
			continue
		var region_id := str(region_key)
		if not region_definitions.has(region_id):
			errors.append("Save supply_region_cycles references unknown region '%s'." % region_id)
			continue
		var saved_value: Variant = cycles.get(region_key, -1)
		if typeof(saved_value) != TYPE_INT:
			errors.append("Save supply cycle for '%s' must be an integer." % region_id)
			continue
		var current_cycle := SupplyModel.cycle_at(SupplyCatalog.region(region_definitions, region_id), play_time_seconds)
		var saved_cycle := int(saved_value)
		if saved_cycle < 0 or saved_cycle > current_cycle:
			errors.append("Save supply cycle for '%s' must be between zero and %d." % [region_id, current_cycle])
	if initialized:
		for region_id_value in region_definitions.keys():
			if not cycles.has(str(region_id_value)):
				errors.append("Save supply_region_cycles is missing '%s'." % region_id_value)
	elif not cycles.is_empty():
		warnings.append("Save payload contains supply cycles while supply_regions_initialized is false; current play-time cycles will replace them.")


static func make_report(errors: Array[String], warnings: Array[String], region_count: int, renewable_count: int) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"supply_region_count": region_count,
		"renewable_stock_count": renewable_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
