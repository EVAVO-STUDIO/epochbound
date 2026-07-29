extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const EconomyValidator = preload("res://src/content/economy_validator.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(campaign_result.get("ok", false), "Reference campaign must load for malformed economy tests.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var economy_result := EconomyCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	var item_result := ItemCatalog.load_item_catalogs(CAMPAIGN_PATH, campaign)
	var story_result := StoryCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	var capability_result := EquipmentCatalog.load_capability_catalogs(CAMPAIGN_PATH, campaign)
	check(economy_result.get("ok", false), "Reference economy must load for malformed economy tests.")
	check(item_result.get("ok", false), "Reference items must load for malformed economy tests.")
	check(story_result.get("ok", false), "Reference story must load for malformed economy tests.")
	check(capability_result.get("ok", false), "Reference capabilities must load for malformed economy tests.")

	var malformed := {
		"schema_version": 1,
		"currencies": [
			{
				"id": "bad currency",
				"display_name": "",
				"symbol": "",
				"starting_balance": 50,
				"max_balance": 10
			},
			{
				"id": "archive_chits",
				"display_name": "Archive Chits",
				"symbol": "AC",
				"starting_balance": 0,
				"max_balance": 999999
			},
			{
				"id": "archive_chits",
				"display_name": "Duplicate",
				"symbol": "D",
				"starting_balance": 0,
				"max_balance": 10
			}
		],
		"merchants": [
			{
				"id": "broken_merchant",
				"display_name": "",
				"currency_id": "missing_currency",
				"greeting": "",
				"farewell": "",
				"buy_multiplier": 0,
				"sell_multiplier": -1,
				"accepts_sales": "yes",
				"accepted_kinds": ["material", "material", "forbidden"],
				"refused_items": ["missing_item"],
				"resell_player_goods": true,
				"conditions": [
					{"type": "currency_at_least", "currency_id": "missing_currency", "amount": -1}
				],
				"stock": [
					{
						"item_id": "missing_item",
						"quantity": -2,
						"unlimited": false,
						"buy_price": -1,
						"sell_price": -3,
						"conditions": []
					},
					{
						"item_id": "museum_tonic",
						"quantity": 1,
						"unlimited": false,
						"buy_price": 1,
						"conditions": []
					},
					{
						"item_id": "museum_tonic",
						"quantity": 2,
						"unlimited": false,
						"buy_price": 1,
						"conditions": []
					}
				]
			}
		]
	}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	EconomyValidator.validate_catalog_file(
		malformed,
		"malformed_economy.json",
		economy_result.get("currencies", {}),
		economy_result.get("merchants", {}),
		item_result.get("definitions", {}),
		story_result.get("quests", {}),
		{"bellweather_crossing": true},
		{"verdant": true, "ashen": true},
		capability_result.get("definitions", {}),
		{},
		{},
		{},
		errors,
		warnings
	)
	check(errors.size() >= 12, "Malformed economy catalog must produce a broad set of validation errors.")
	check(contains_message(errors, "normalised lowercase identifier"), "Malformed currency ID must be rejected.")
	check(contains_message(errors, "starting_balance"), "Out-of-range starting balance must be rejected.")
	check(contains_message(errors, "unknown currency_id"), "Unknown merchant currency must be rejected.")
	check(contains_message(errors, "buy_multiplier"), "Non-positive buy multiplier must be rejected.")
	check(contains_message(errors, "unsupported accepted item kind"), "Unknown accepted item kind must be rejected.")
	check(contains_message(errors, "unknown item"), "Unknown stock and refusal items must be rejected.")
	check(contains_message(errors, "quantity must be between zero"), "Negative stock quantity must be rejected.")
	check(contains_message(errors, "price overrides cannot be negative"), "Negative price overrides must be rejected.")
	check(contains_message(errors, "repeated in merchant stock"), "Repeated stock item must be rejected.")

	var profile_errors: Array[String] = []
	var profile_warnings: Array[String] = []
	EconomyValidator.validate_profile_economy(
		{
			"economy_initialized": true,
			"currency_balances": {
				"archive_chits": -1,
				"unknown_money": 10
			},
			"merchant_stock": {
				"bellweather_provisions": {
					"museum_tonic": -2,
					"missing_item": 1
				},
				"missing_merchant": {}
			}
		},
		economy_result.get("currencies", {}),
		economy_result.get("merchants", {}),
		item_result.get("definitions", {}),
		profile_errors,
		profile_warnings
	)
	check(contains_message(profile_errors, "unknown currency"), "Unknown saved currency must be rejected.")
	check(contains_message(profile_errors, "must be between zero"), "Negative saved balance or stock must be rejected.")
	check(contains_message(profile_errors, "unknown merchant"), "Unknown saved merchant must be rejected.")
	check(contains_message(profile_errors, "unknown item"), "Unknown saved stock item must be rejected.")
	check(contains_message(profile_errors, "missing 'underworks_exchange'"), "Initialised save must contain every merchant record.")

	finish()


func contains_message(messages: Array[String], fragment: String) -> bool:
	for message in messages:
		if fragment in message:
			return true
	return false


func finish() -> void:
	if failures.is_empty():
		print("Economy validation edge test passed: malformed currencies, merchants, prices, stock and saved economy state are rejected cleanly.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
