@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")

const MAX_REGION_ID_LENGTH := 80
const MAX_DISPLAY_NAME_LENGTH := 160
const MIN_INTERVAL_SECONDS := 30.0
const MAX_INTERVAL_SECONDS := 86400.0
const MAX_CATCHUP_CYCLES := 32


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var files: Array = []
	var definitions: Dictionary = {}
	var sources: Dictionary = {}
	var files_value: Variant = campaign.get("economy_files", [])
	if typeof(files_value) != TYPE_ARRAY:
		return {
			"ok": false,
			"errors": ["%s: economy_files must be an array of safe relative JSON paths." % campaign.get("id", campaign_path)],
			"files": files,
			"definitions": definitions,
			"sources": sources
		}
	for relative_value in files_value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result := Repository.read_json(path)
		if not bool(result.get("ok", false)):
			EconomyCatalog.append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		files.append({"path": path, "relative_path": relative_path, "data": data})
		var regions_value: Variant = data.get("supply_regions", [])
		if typeof(regions_value) != TYPE_ARRAY:
			errors.append("%s: supply_regions must be an array." % path)
			continue
		for record_value in regions_value:
			if typeof(record_value) != TYPE_DICTIONARY:
				errors.append("%s: every supply region must be an object." % path)
				continue
			var record: Dictionary = record_value
			var region_id := str(record.get("id", ""))
			if region_id.is_empty():
				continue
			if definitions.has(region_id):
				errors.append("%s: supply region id '%s' is also declared by %s." % [path, region_id, sources.get(region_id, "another catalog")])
				continue
			definitions[region_id] = record
			sources[region_id] = path
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"files": files,
		"definitions": definitions,
		"sources": sources
	}


static func region(definitions: Dictionary, region_id: String) -> Dictionary:
	var value: Variant = definitions.get(region_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func region_name(definitions: Dictionary, region_id: String) -> String:
	var data := region(definitions, region_id)
	return str(data.get("display_name", region_id.replace("_", " ").capitalize()))


static func interval_seconds(region_data: Dictionary) -> float:
	return clampf(
		float(region_data.get("restock_interval_seconds", MIN_INTERVAL_SECONDS)),
		MIN_INTERVAL_SECONDS,
		MAX_INTERVAL_SECONDS
	)


static func max_catchup_cycles(region_data: Dictionary) -> int:
	return clampi(int(region_data.get("max_catchup_cycles", 1)), 1, MAX_CATCHUP_CYCLES)


static func merchant_region_id(merchant_data: Dictionary) -> String:
	return str(merchant_data.get("supply_region_id", "")).strip_edges()


static func stock_restock_quantity(entry: Dictionary) -> int:
	if EconomyCatalog.stock_is_unlimited(entry):
		return 0
	return clampi(int(entry.get("restock_quantity", 0)), 0, EconomyCatalog.MAX_STOCK)


static func stock_restock_target(entry: Dictionary) -> int:
	if EconomyCatalog.stock_is_unlimited(entry):
		return -1
	var initial := EconomyCatalog.initial_stock_quantity(entry)
	return clampi(int(entry.get("restock_target", initial)), 0, EconomyCatalog.MAX_STOCK)


static func stock_is_renewable(entry: Dictionary) -> bool:
	return (
		not EconomyCatalog.stock_is_unlimited(entry)
		and stock_restock_quantity(entry) > 0
		and stock_restock_target(entry) > 0
	)


static func default_region(
	region_id: String,
	display_name: String,
	restock_interval_seconds: float = 180.0,
	max_cycles: int = 4
) -> Dictionary:
	return {
		"id": region_id,
		"display_name": display_name,
		"restock_interval_seconds": clampf(restock_interval_seconds, MIN_INTERVAL_SECONDS, MAX_INTERVAL_SECONDS),
		"max_catchup_cycles": clampi(max_cycles, 1, MAX_CATCHUP_CYCLES)
	}


static func format_duration(seconds: float) -> String:
	var total := maxi(0, int(ceil(seconds)))
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var remaining_seconds := total % 60
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, remaining_seconds]
	return "%02d:%02d" % [minutes, remaining_seconds]
