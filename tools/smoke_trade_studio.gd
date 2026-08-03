extends SceneTree

const TradeStudio = preload("res://addons/epochbound_trade_studio/trade_studio_supply.gd")
const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyValidator = preload("res://src/content/supply_region_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var studio := TradeStudio.new()
	root.add_child(studio)
	check(studio != null, "Trade Studio must instantiate.")
	if studio == null:
		finish()
		return

	var campaign_selector_value: Variant = studio.get("campaign_selector")
	var currency_list_value: Variant = studio.get("currency_list")
	var merchant_list_value: Variant = studio.get("merchant_list")
	var binding_list_value: Variant = studio.get("binding_object_list")
	var stock_edit_value: Variant = studio.get("merchant_stock_edit")
	var currency_selector_value: Variant = studio.get("merchant_currency_selector")
	var supply_list_value: Variant = studio.get("supply_region_list")
	var supply_selector_value: Variant = studio.get("merchant_supply_region_selector")
	check(campaign_selector_value is OptionButton, "Trade Studio must create a campaign selector.")
	check(currency_list_value is ItemList, "Trade Studio must create a currency list.")
	check(merchant_list_value is ItemList, "Trade Studio must create a merchant list.")
	check(binding_list_value is ItemList, "Trade Studio must create an NPC binding list.")
	check(stock_edit_value is TextEdit, "Trade Studio must create a stock source editor.")
	check(currency_selector_value is OptionButton, "Trade Studio must create a merchant currency selector.")
	check(supply_list_value is ItemList, "Trade Studio must create a supply route list.")
	check(supply_selector_value is OptionButton, "Trade Studio must create a merchant supply route selector.")
	if campaign_selector_value is OptionButton:
		check((campaign_selector_value as OptionButton).item_count >= 1, "Trade Studio must discover the reference campaign.")
	if currency_list_value is ItemList:
		check((currency_list_value as ItemList).item_count == 1, "Reference economy must expose one currency in the editor.")
	if merchant_list_value is ItemList:
		check((merchant_list_value as ItemList).item_count == 2, "Reference economy must expose two merchants in the editor.")
	if binding_list_value is ItemList:
		check((binding_list_value as ItemList).item_count == 3, "Trade Studio must expose the Archivist and two merchant-capable NPC definitions.")
	if currency_selector_value is OptionButton:
		check((currency_selector_value as OptionButton).item_count == 1, "Merchant currency selector must expose Archive Chits.")
	if supply_list_value is ItemList:
		check((supply_list_value as ItemList).item_count == 2, "Trade Studio must expose both reference supply routes.")
	if supply_selector_value is OptionButton:
		check((supply_selector_value as OptionButton).item_count == 3, "Merchant supply selector must expose static stock plus both routes.")
	if stock_edit_value is TextEdit:
		var stock_text := (stock_edit_value as TextEdit).text
		check(stock_text.contains("item_id"), "Merchant inspector must preserve stock as complete JSON-line records.")
		check(stock_text.contains("quantity"), "Merchant stock editor must expose quantities.")
		check(stock_text.contains("restock_quantity"), "Merchant stock editor must expose replenishment policy without flattening JSON.")

	check(str(studio.get("selected_currency_id")) == "archive_chits", "Trade Studio must select the reference currency.")
	check(str(studio.get("selected_merchant_id")) in ["bellweather_provisions", "underworks_exchange"], "Trade Studio must select a reference merchant.")
	check(not str(studio.get("selected_supply_region_id")).is_empty(), "Trade Studio must select a reference supply route.")
	check(not str(studio.get("selected_object_id")).is_empty(), "Trade Studio must select an NPC binding record.")

	var valid_stock: Variant = studio.call(
		"parse_json_lines",
		'{"item_id":"museum_tonic","quantity":3,"unlimited":false,"buy_price":18,"sell_price":10,"restock_quantity":1,"restock_target":3,"conditions":[]}',
		"test stock"
	)
	check(typeof(valid_stock) == TYPE_DICTIONARY and bool((valid_stock as Dictionary).get("ok", false)), "Trade Studio must parse complete replenishing stock JSON records.")
	if typeof(valid_stock) == TYPE_DICTIONARY:
		check((valid_stock as Dictionary).get("entries", []).size() == 1, "Stock parser must retain the complete replenishment record.")
	var malformed: Variant = studio.call("parse_json_lines", "not-json", "test stock")
	check(typeof(malformed) == TYPE_DICTIONARY and not bool((malformed as Dictionary).get("ok", true)), "Trade Studio must reject malformed JSON-line stock.")
	var duplicate_ids: Variant = studio.call("parse_id_lines", "material\nmaterial", "accepted kinds")
	check(typeof(duplicate_ids) == TYPE_DICTIONARY and not bool((duplicate_ids as Dictionary).get("ok", true)), "Trade Studio must reject duplicate list entries.")

	var definitions_value: Variant = studio.get("supply_region_definitions")
	var definitions: Dictionary = definitions_value.duplicate(true) if typeof(definitions_value) == TYPE_DICTIONARY else {}
	definitions["secondary_route"] = SupplyCatalog.default_region("secondary_route", "Secondary Route", 600.0, 2)
	studio.set("supply_region_definitions", definitions)
	studio.set("selected_supply_region_id", "secondary_route")
	var catalogue_before := JSON.stringify(studio.get("active_economy_catalog"))
	studio.call("delete_supply_region")
	check(JSON.stringify(studio.get("active_economy_catalog")) == catalogue_before, "Deleting a route from a secondary catalogue must not rewrite the editable primary catalogue.")
	var status_value: Variant = studio.get("status_label")
	if status_value is RichTextLabel:
		check((status_value as RichTextLabel).text.contains("not in the editable primary catalogue"), "Secondary-route deletion must explain why it was blocked.")

	var validation := SupplyValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(validation.get("ok", false), "Trade Studio reference campaign must pass supply-aware validation.")
	check(int(validation.get("merchant_stock_count", 0)) == 9, "Trade Studio validator must count every authored stock record.")
	check(int(validation.get("supply_region_count", 0)) == 2, "Trade Studio validator must count both supply routes.")
	check(int(validation.get("renewable_stock_count", 0)) == 5, "Trade Studio validator must count all renewable stock records.")

	root.remove_child(studio)
	studio.free()
	finish()


func finish() -> void:
	if failures.is_empty():
		print("Trade Studio smoke test passed: campaigns, currencies, merchants, supply routes, primary-catalogue safety, scarcity, NPC bindings, source parsing and complete validation are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
