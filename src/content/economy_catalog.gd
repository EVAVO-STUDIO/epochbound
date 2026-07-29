@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")

const SUPPORTED_SCHEMA := 1
const MAX_CURRENCY_ID_LENGTH := 80
const MAX_MERCHANT_ID_LENGTH := 80
const MAX_DISPLAY_NAME_LENGTH := 160
const MAX_MESSAGE_LENGTH := 1200
const MAX_BALANCE := 999999999
const MAX_STOCK := 999999


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var files: Array = []
	var currencies: Dictionary = {}
	var merchants: Dictionary = {}
	var currency_sources: Dictionary = {}
	var merchant_sources: Dictionary = {}
	var files_value: Variant = campaign.get("economy_files", [])
	if typeof(files_value) != TYPE_ARRAY:
		return {
			"ok": false,
			"errors": ["%s: economy_files must be an array of safe relative JSON paths." % campaign.get("id", campaign_path)],
			"files": files,
			"currencies": currencies,
			"merchants": merchants,
			"currency_sources": currency_sources,
			"merchant_sources": merchant_sources
		}
	for relative_value in files_value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe economy catalog path '%s'." % [campaign.get("id", campaign_path), relative_path])
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result := Repository.read_json(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		files.append({"path": path, "relative_path": relative_path, "data": data})
		merge_records(data.get("currencies", []), "currency", path, currencies, currency_sources, errors)
		merge_records(data.get("merchants", []), "merchant", path, merchants, merchant_sources, errors)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"files": files,
		"currencies": currencies,
		"merchants": merchants,
		"currency_sources": currency_sources,
		"merchant_sources": merchant_sources
	}


static func merge_records(
	value: Variant,
	kind: String,
	path: String,
	target: Dictionary,
	sources: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: %ss must be an array." % [path, kind])
		return
	for record_value in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("%s: every %s must be an object." % [path, kind])
			continue
		var record: Dictionary = record_value
		var identifier := str(record.get("id", ""))
		if identifier.is_empty():
			continue
		if target.has(identifier):
			errors.append("%s: %s id '%s' is also declared by %s." % [path, kind, identifier, sources.get(identifier, "another catalog")])
			continue
		target[identifier] = record
		sources[identifier] = path


static func primary_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	var value: Variant = campaign.get("economy_files", [])
	if typeof(value) == TYPE_ARRAY:
		for relative_value in value:
			var relative_path := str(relative_value)
			if ObjectCatalog.safe_relative_json_path(relative_path):
				return campaign_path.get_base_dir().path_join(relative_path)
	return campaign_path.get_base_dir().path_join("economy").path_join("core.json")


static func currency(definitions: Dictionary, currency_id: String) -> Dictionary:
	var value: Variant = definitions.get(currency_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func merchant(definitions: Dictionary, merchant_id: String) -> Dictionary:
	var value: Variant = definitions.get(merchant_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func currency_name(definitions: Dictionary, currency_id: String) -> String:
	var data := currency(definitions, currency_id)
	return str(data.get("display_name", currency_id.replace("_", " ").capitalize()))


static func currency_symbol(definitions: Dictionary, currency_id: String) -> String:
	var data := currency(definitions, currency_id)
	return str(data.get("symbol", currency_id.left(3).to_upper()))


static func starting_balance(currency_data: Dictionary) -> int:
	return clampi(int(currency_data.get("starting_balance", 0)), 0, max_balance(currency_data))


static func max_balance(currency_data: Dictionary) -> int:
	return clampi(int(currency_data.get("max_balance", MAX_BALANCE)), 1, MAX_BALANCE)


static func merchant_currency_id(merchant_data: Dictionary) -> String:
	return str(merchant_data.get("currency_id", ""))


static func merchant_buy_multiplier(merchant_data: Dictionary) -> float:
	return clampf(float(merchant_data.get("buy_multiplier", 1.0)), 0.01, 100.0)


static func merchant_sell_multiplier(merchant_data: Dictionary) -> float:
	return clampf(float(merchant_data.get("sell_multiplier", 0.5)), 0.0, 100.0)


static func merchant_accepts_sales(merchant_data: Dictionary) -> bool:
	return bool(merchant_data.get("accepts_sales", true))


static func merchant_resells_player_goods(merchant_data: Dictionary) -> bool:
	return bool(merchant_data.get("resell_player_goods", true))


static func accepted_kinds(merchant_data: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = merchant_data.get("accepted_kinds", ["consumable", "material", "equipment", "ammunition"])
	if typeof(value) != TYPE_ARRAY:
		return output
	for kind_value in value:
		var kind := str(kind_value).strip_edges()
		if ItemCatalog.ALLOWED_ITEM_KINDS.has(kind) and not output.has(kind):
			output.append(kind)
	return output


static func refused_items(merchant_data: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var value: Variant = merchant_data.get("refused_items", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for item_value in value:
		var item_id := str(item_value).strip_edges()
		if not item_id.is_empty() and not output.has(item_id):
			output.append(item_id)
	return output


static func stock_entries(merchant_data: Dictionary) -> Array:
	var value: Variant = merchant_data.get("stock", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func stock_entry_index(merchant_data: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for value in stock_entries(merchant_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		var item_id := str(entry.get("item_id", ""))
		if not item_id.is_empty():
			output[item_id] = entry
	return output


static func stock_entry(merchant_data: Dictionary, item_id: String) -> Dictionary:
	var value: Variant = stock_entry_index(merchant_data).get(item_id, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func stock_is_unlimited(entry: Dictionary) -> bool:
	return bool(entry.get("unlimited", false))


static func initial_stock_quantity(entry: Dictionary) -> int:
	if stock_is_unlimited(entry):
		return -1
	return clampi(int(entry.get("quantity", 0)), 0, MAX_STOCK)


static func default_catalog() -> Dictionary:
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"currencies": [
			default_currency("trade_marks", "Trade Marks", "TM")
		],
		"merchants": [
			{
				"id": "trail_exchange",
				"display_name": "Trail Exchange",
				"currency_id": "trade_marks",
				"greeting": "Useful goods for an uncertain road.",
				"farewell": "Keep the trail in sight.",
				"buy_multiplier": 1.0,
				"sell_multiplier": 0.5,
				"accepts_sales": true,
				"accepted_kinds": ["consumable", "material", "equipment", "ammunition"],
				"refused_items": [],
				"resell_player_goods": true,
				"conditions": [],
				"stock": [
					{"item_id": "trail_tonic", "quantity": 4, "unlimited": false, "buy_price": 18, "conditions": []},
					{"item_id": "brass_scrap", "quantity": 12, "unlimited": false, "buy_price": 3, "conditions": []},
					{"item_id": "field_salve", "quantity": 1, "unlimited": false, "buy_price": 28, "conditions": []}
				]
			}
		]
	}


static func default_currency(currency_id: String, display_name: String, symbol: String = "¤") -> Dictionary:
	return {
		"id": currency_id,
		"display_name": display_name,
		"symbol": symbol,
		"starting_balance": 40,
		"max_balance": MAX_BALANCE
	}


static func default_merchant(merchant_id: String, display_name: String, currency_id: String, item_id: String) -> Dictionary:
	return {
		"id": merchant_id,
		"display_name": display_name,
		"currency_id": currency_id,
		"greeting": "Browse what survived the road.",
		"farewell": "Travel carefully.",
		"buy_multiplier": 1.0,
		"sell_multiplier": 0.5,
		"accepts_sales": true,
		"accepted_kinds": ["consumable", "material", "equipment", "ammunition"],
		"refused_items": [],
		"resell_player_goods": true,
		"conditions": [],
		"stock": [
			{"item_id": item_id, "quantity": 1, "unlimited": false, "buy_price": 0, "conditions": []}
		]
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
