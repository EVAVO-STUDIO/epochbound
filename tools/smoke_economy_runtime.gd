extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const EconomyValidator = preload("res://src/content/economy_validator.gd")
const EconomyModel = preload("res://src/game/economy_model.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const EquipmentModel = preload("res://src/game/equipment_model.gd")
const SaveProfile = preload("res://src/content/save_profile.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var validation := EconomyValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(validation.get("ok", false), "Reference campaign must pass merchant and economy validation.")
	check(int(validation.get("currency_count", 0)) == 1, "Reference campaign must expose one currency.")
	check(int(validation.get("merchant_count", 0)) == 2, "Reference campaign must expose two merchants.")
	check(int(validation.get("merchant_binding_count", 0)) == 2, "Reference campaign must bind two reusable NPC definitions to merchants.")
	check(int(validation.get("merchant_stock_count", 0)) == 9, "Reference merchants must expose nine authored stock entries.")

	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(campaign_result.get("ok", false), "Reference campaign must load.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var economy_result := EconomyCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	var item_result := ItemCatalog.load_item_catalogs(CAMPAIGN_PATH, campaign)
	check(economy_result.get("ok", false), "Reference economy catalog must load.")
	check(item_result.get("ok", false), "Reference item catalog must load.")
	var currencies: Dictionary = economy_result.get("currencies", {})
	var merchants: Dictionary = economy_result.get("merchants", {})
	var items: Dictionary = item_result.get("definitions", {})
	check(EconomyCatalog.currency_name(currencies, "archive_chits") == "Archive Chits", "Archive Chits must resolve from the shared catalog.")
	check(EconomyCatalog.merchant(merchants, "bellweather_provisions").get("display_name") == "Bellweather Provisions", "Bellweather merchant must resolve.")

	test_atomic_model(currencies, merchants, items)
	probe_runtime_scene()
	finish()


func test_atomic_model(currencies: Dictionary, merchants: Dictionary, items: Dictionary) -> void:
	var balances := EconomyModel.initial_balances(currencies)
	var stock := EconomyModel.initial_stock(merchants)
	var inventory := {"museum_tonic": 8, "brass_hook": 1}
	check(EconomyModel.balance(balances, "archive_chits") == 60, "New economy state must initialise the authored balance.")
	check(EconomyModel.stock_quantity(stock, "bellweather_provisions", "museum_tonic") == 3, "Finite merchant stock must initialise exactly.")

	var buy_result := EconomyModel.buy_item(
		balances,
		stock,
		inventory,
		currencies,
		merchants,
		items,
		"bellweather_provisions",
		"museum_tonic"
	)
	check(buy_result.get("ok", false), "Valid purchase must complete.")
	check(EconomyModel.balance(balances, "archive_chits") == 42, "Purchase must remove the complete authored price.")
	check(InventoryModel.count(inventory, "museum_tonic") == 9, "Purchase must add exactly one item.")
	check(EconomyModel.stock_quantity(stock, "bellweather_provisions", "museum_tonic") == 2, "Purchase must decrement finite stock.")

	var before_balance := EconomyModel.balance(balances, "archive_chits")
	var before_stock := EconomyModel.stock_quantity(stock, "bellweather_provisions", "museum_tonic")
	var blocked_buy := EconomyModel.buy_item(
		balances,
		stock,
		inventory,
		currencies,
		merchants,
		items,
		"bellweather_provisions",
		"museum_tonic"
	)
	check(not blocked_buy.get("ok", true) and blocked_buy.get("reason") == "stack_full", "A full stack must reject a purchase.")
	check(EconomyModel.balance(balances, "archive_chits") == before_balance, "Rejected purchase must not remove currency.")
	check(EconomyModel.stock_quantity(stock, "bellweather_provisions", "museum_tonic") == before_stock, "Rejected purchase must not change stock.")
	check(InventoryModel.count(inventory, "museum_tonic") == 9, "Rejected purchase must not change inventory.")

	var blocked_sell := EconomyModel.sell_item(
		balances,
		stock,
		inventory,
		currencies,
		merchants,
		items,
		"bellweather_provisions",
		"brass_hook",
		1,
		PackedStringArray(["brass_hook"])
	)
	check(not blocked_sell.get("ok", true) and blocked_sell.get("reason") == "equipped_item", "Equipped gear must be protected from sale.")
	check(InventoryModel.count(inventory, "brass_hook") == 1, "Blocked equipment sale must retain ownership.")

	var sell_result := EconomyModel.sell_item(
		balances,
		stock,
		inventory,
		currencies,
		merchants,
		items,
		"bellweather_provisions",
		"museum_tonic"
	)
	check(sell_result.get("ok", false), "Valid sale must complete.")
	check(EconomyModel.balance(balances, "archive_chits") == 52, "Sale must add the complete authored payment.")
	check(InventoryModel.count(inventory, "museum_tonic") == 8, "Sale must remove exactly one item.")
	check(EconomyModel.stock_quantity(stock, "bellweather_provisions", "museum_tonic") == 3, "Resold goods must return to finite merchant stock.")


func probe_runtime_scene() -> void:
	var scene_resource := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(scene_resource is PackedScene, "Runtime scene must load as a PackedScene.")
	if not scene_resource is PackedScene:
		return
	var runtime := (scene_resource as PackedScene).instantiate()
	check(runtime != null, "Runtime scene must instantiate.")
	if runtime == null:
		return
	var script_value: Variant = runtime.get_script()
	check(script_value is GDScript, "Runtime root must retain its GDScript.")
	if script_value is GDScript:
		check(str((script_value as GDScript).resource_path) in ["res://src/boss_runtime.gd", "res://src/cinematic_runtime.gd"], "Runtime scene must bind the Boss runtime.")
	root.add_child(runtime)
	check(runtime.has_method("open_merchant"), "Runtime must expose merchant entry.")
	check(runtime.has_method("activate_merchant_selection"), "Runtime must expose guarded transaction activation.")
	check(runtime.has_method("capture_save_profile"), "Runtime must expose durable profile capture.")
	check(runtime_dictionary(runtime, "currency_definitions").size() == 1, "Runtime must load one currency definition.")
	check(runtime_dictionary(runtime, "merchant_definitions").size() == 2, "Runtime must load two merchant definitions.")
	check(EconomyModel.balance(runtime_dictionary(runtime, "currency_balances"), "archive_chits") == 60, "Runtime must initialise the Archive Chits wallet.")

	check(bool(runtime.call("open_merchant", "bellweather_provisions")), "Bellweather merchant must open.")
	var buy_ids: PackedStringArray = runtime.call("merchant_entry_ids")
	var tonic_index := buy_ids.find("museum_tonic")
	check(tonic_index >= 0, "Bellweather buy list must expose Museum Tonic.")
	if tonic_index >= 0:
		runtime.set("merchant_index", tonic_index)
		check(bool(runtime.call("activate_merchant_selection")), "Runtime purchase must complete through the player-facing transaction path.")
	var balances := runtime_dictionary(runtime, "currency_balances")
	var stock := runtime_dictionary(runtime, "merchant_stock")
	var inventory := runtime_dictionary(runtime, "inventory")
	check(EconomyModel.balance(balances, "archive_chits") == 42, "Runtime purchase must debit Archive Chits.")
	check(InventoryModel.count(inventory, "museum_tonic") == 2, "Runtime purchase must add one Museum Tonic.")
	check(EconomyModel.stock_quantity(stock, "bellweather_provisions", "museum_tonic") == 2, "Runtime purchase must persist finite stock.")

	runtime.set("merchant_mode", 1)
	var sell_ids: PackedStringArray = runtime.call("merchant_entry_ids")
	tonic_index = sell_ids.find("museum_tonic")
	check(tonic_index >= 0, "Bellweather sell list must expose an owned Museum Tonic.")
	if tonic_index >= 0:
		runtime.set("merchant_index", tonic_index)
		check(bool(runtime.call("activate_merchant_selection")), "Runtime sale must complete through the player-facing transaction path.")
	balances = runtime_dictionary(runtime, "currency_balances")
	stock = runtime_dictionary(runtime, "merchant_stock")
	inventory = runtime_dictionary(runtime, "inventory")
	check(EconomyModel.balance(balances, "archive_chits") == 52, "Runtime sale must credit Archive Chits.")
	check(InventoryModel.count(inventory, "museum_tonic") == 1, "Runtime sale must remove one Museum Tonic.")
	check(EconomyModel.stock_quantity(stock, "bellweather_provisions", "museum_tonic") == 3, "Runtime sale must restore merchant stock.")
	runtime.call("close_merchant", false)

	var equipped := runtime_dictionary(runtime, "equipped_items")
	equipped.erase("tool")
	runtime.set("equipped_items", equipped)
	check(not bool(runtime.call("open_merchant", "underworks_exchange")), "Underworks merchant must remain unavailable without Illuminate Darkness.")
	check(bool(runtime.call("equip_specific_item", "museum_flashlight")), "Reference flashlight must be re-equippable.")
	check(bool(runtime.call("open_merchant", "underworks_exchange")), "Underworks merchant must open when its capability condition is active.")
	runtime.call("close_merchant", false)

	var before_reward := EconomyModel.balance(runtime_dictionary(runtime, "currency_balances"), "archive_chits")
	runtime.call("apply_story_effects", [{"type": "grant_currency", "currency_id": "archive_chits", "amount": 7}], false)
	check(EconomyModel.balance(runtime_dictionary(runtime, "currency_balances"), "archive_chits") == before_reward + 7, "Story effects must grant the same durable currency used by merchants.")
	var context: Dictionary = runtime.call("story_context")
	check(StoryModelCondition.currency_condition(context, before_reward + 7), "Currency condition helper setup must observe the shared wallet.")

	var profile: Dictionary = runtime.call("capture_save_profile", "slot_1", "Economy smoke test")
	check(int(profile.get("schema_version", 0)) == SaveProfile.CURRENT_SCHEMA, "Economy profile must use the current save schema.")
	var payload: Dictionary = profile.get("payload", {})
	check(bool(payload.get("economy_initialized", false)), "Economy profile must declare initialised durable state.")
	check(int((payload.get("currency_balances", {}) as Dictionary).get("archive_chits", 0)) == before_reward + 7, "Profile must capture the exact wallet balance.")
	check(int(((payload.get("merchant_stock", {}) as Dictionary).get("bellweather_provisions", {}) as Dictionary).get("museum_tonic", 0)) == 3, "Profile must capture the exact finite merchant stock.")

	var mutated_balances := runtime_dictionary(runtime, "currency_balances")
	mutated_balances["archive_chits"] = 1
	runtime.set("currency_balances", mutated_balances)
	var mutated_stock := runtime_dictionary(runtime, "merchant_stock")
	(mutated_stock["bellweather_provisions"] as Dictionary)["museum_tonic"] = 0
	runtime.set("merchant_stock", mutated_stock)
	check(bool(runtime.call("apply_save_profile", profile, CAMPAIGN_PATH)), "Economy-aware profile must restore through the normal load path.")
	check(EconomyModel.balance(runtime_dictionary(runtime, "currency_balances"), "archive_chits") == before_reward + 7, "Profile load must restore the exact wallet balance.")
	check(EconomyModel.stock_quantity(runtime_dictionary(runtime, "merchant_stock"), "bellweather_provisions", "museum_tonic") == 3, "Profile load must restore the exact merchant stock.")

	root.remove_child(runtime)
	runtime.free()


func runtime_dictionary(runtime: Object, property_name: String) -> Dictionary:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


class StoryModelCondition:
	static func currency_condition(context: Dictionary, amount: int) -> bool:
		var balances: Dictionary = context.get("currency_balances", {})
		return int(balances.get("archive_chits", 0)) >= amount


func finish() -> void:
	if failures.is_empty():
		print("Economy runtime smoke test passed: catalogs, atomic buy/sell, capability-gated merchants, story rewards and current-schema restoration are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
