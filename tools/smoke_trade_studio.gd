extends SceneTree

const TradeStudio = preload("res://addons/epochbound_trade_studio/trade_studio.gd")
const EconomyValidator = preload("res://src/content/economy_validator.gd")

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
	check(campaign_selector_value is OptionButton, "Trade Studio must create a campaign selector.")
	check(currency_list_value is ItemList, "Trade Studio must create a currency list.")
	check(merchant_list_value is ItemList, "Trade Studio must create a merchant list.")
	check(binding_list_value is ItemList, "Trade Studio must create an NPC binding list.")
	check(stock_edit_value is TextEdit, "Trade Studio must create a stock source editor.")
	check(currency_selector_value is OptionButton, "Trade Studio must create a merchant currency selector.")
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
	if stock_edit_value is TextEdit:
		var stock_text := (stock_edit_value as TextEdit).text
		check(stock_text.contains("item_id"), "Merchant inspector must preserve stock as complete JSON-line records.")
		check(stock_text.contains("quantity"), "Merchant stock editor must expose quantities.")

	check(str(studio.get("selected_currency_id")) == "archive_chits", "Trade Studio must select the reference currency.")
	check(str(studio.get("selected_merchant_id")) in ["bellweather_provisions", "underworks_exchange"], "Trade Studio must select a reference merchant.")
	check(not str(studio.get("selected_object_id")).is_empty(), "Trade Studio must select an NPC binding record.")

	var valid_stock: Variant = studio.call(
		"parse_json_lines",
		'{"item_id":"museum_tonic","quantity":3,"unlimited":false,"buy_price":18,"sell_price":10,"conditions":[]}',
		"test stock"
	)
	check(typeof(valid_stock) == TYPE_DICTIONARY and bool((valid_stock as Dictionary).get("ok", false)), "Trade Studio must parse complete stock JSON records.")
	if typeof(valid_stock) == TYPE_DICTIONARY:
		check((valid_stock as Dictionary).get("entries", []).size() == 1, "Stock parser must retain the complete record.")
	var malformed: Variant = studio.call("parse_json_lines", "not-json", "test stock")
	check(typeof(malformed) == TYPE_DICTIONARY and not bool((malformed as Dictionary).get("ok", true)), "Trade Studio must reject malformed JSON-line stock.")
	var duplicate_ids: Variant = studio.call("parse_id_lines", "material\nmaterial", "accepted kinds")
	check(typeof(duplicate_ids) == TYPE_DICTIONARY and not bool((duplicate_ids as Dictionary).get("ok", true)), "Trade Studio must reject duplicate list entries.")

	var validation := EconomyValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(validation.get("ok", false), "Trade Studio reference campaign must pass complete validation.")
	check(int(validation.get("merchant_stock_count", 0)) == 7, "Trade Studio validator must count every authored stock record.")

	root.remove_child(studio)
	studio.free()
	finish()


func finish() -> void:
	if failures.is_empty():
		print("Trade Studio smoke test passed: campaigns, currencies, merchants, NPC bindings, source parsing and complete validation are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
