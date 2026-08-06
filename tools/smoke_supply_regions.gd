extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")

const Repository = preload("res://src/content/campaign_repository.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const EconomyModel = preload("res://src/game/economy_model.gd")
const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyValidator = preload("res://src/content/supply_region_validator.gd")
const SupplyModel = preload("res://src/game/supply_region_model.gd")
const SaveProfile = preload("res://src/content/save_profile.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"
const RUNTIME_SCRIPT := "res://src/presentation_runtime_current.gd"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var campaign_result: Dictionary = Repository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load for regional supply testing.")
	if not bool(campaign_result.get("ok", false)):
		finish()
		return
	var campaign_value: Variant = campaign_result.get("data", {})
	var campaign: Dictionary = campaign_value if typeof(campaign_value) == TYPE_DICTIONARY else {}
	var economy_result: Dictionary = EconomyCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	var supply_result: Dictionary = SupplyCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(economy_result.get("ok", false)), "Reference economy must load for regional supply testing.")
	check(bool(supply_result.get("ok", false)), "Reference supply routes must load.")
	var validation: Dictionary = SupplyValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference regional supply content must validate.")
	check(int(validation.get("supply_region_count", 0)) == 2, "Reference economy must expose two supply routes.")
	check(int(validation.get("renewable_stock_count", 0)) == 5, "Reference economy must expose five renewable stock entries.")

	var merchants_value: Variant = economy_result.get("merchants", {})
	var merchants: Dictionary = merchants_value if typeof(merchants_value) == TYPE_DICTIONARY else {}
	var regions_value: Variant = supply_result.get("definitions", {})
	var regions: Dictionary = regions_value if typeof(regions_value) == TYPE_DICTIONARY else {}
	test_deterministic_model(merchants, regions)
	await test_runtime_persistence()
	finish()


func test_deterministic_model(merchants: Dictionary, regions: Dictionary) -> void:
	var stock: Dictionary = EconomyModel.initial_stock(merchants)
	var bellweather_value: Variant = stock.get("bellweather_provisions", {})
	var bellweather: Dictionary = bellweather_value if typeof(bellweather_value) == TYPE_DICTIONARY else {}
	bellweather["museum_tonic"] = 0
	bellweather["brass_filings"] = 0
	bellweather["archive_bolts"] = 0
	bellweather["museum_flashlight"] = 0
	stock["bellweather_provisions"] = bellweather
	var underworks_value: Variant = stock.get("underworks_exchange", {})
	var underworks: Dictionary = underworks_value if typeof(underworks_value) == TYPE_DICTIONARY else {}
	underworks["ashen_resin"] = 0
	underworks["clockglass_fragment"] = 0
	stock["underworks_exchange"] = underworks
	var cycles: Dictionary = SupplyModel.initial_cycles(regions, 0.0)

	var first: Dictionary = SupplyModel.apply_due_restock(stock, merchants, regions, cycles, 180.0)
	check(bool(first.get("changed", false)), "Crossing the Bellweather interval must advance supply state.")
	check(int(first.get("cycles_advanced", 0)) == 1, "Only the Bellweather route must advance at 180 seconds.")
	check(stock_quantity(stock, "bellweather_provisions", "museum_tonic") == 1, "One Bellweather cycle must deliver one Museum Tonic.")
	check(stock_quantity(stock, "bellweather_provisions", "brass_filings") == 2, "One Bellweather cycle must deliver two Brass Filings.")
	check(stock_quantity(stock, "bellweather_provisions", "archive_bolts") == 8, "One Bellweather cycle must deliver eight Archive Bolts.")
	check(stock_quantity(stock, "underworks_exchange", "ashen_resin") == 0, "Underworks stock must not replenish before its own interval.")

	var catchup: Dictionary = SupplyModel.apply_due_restock(stock, merchants, regions, cycles, 900.0)
	check(bool(catchup.get("changed", false)), "Bounded catch-up must advance elapsed routes.")
	check(stock_quantity(stock, "bellweather_provisions", "museum_tonic") == 3, "Bellweather tonic restock must stop at its authored target.")
	check(stock_quantity(stock, "bellweather_provisions", "brass_filings") == 10, "Bellweather material restock must stop at its authored target.")
	check(stock_quantity(stock, "bellweather_provisions", "archive_bolts") == 24, "Ammunition restock must stop at its authored target.")
	check(stock_quantity(stock, "underworks_exchange", "ashen_resin") == 3, "Three bounded Underworks cycles must replenish three Ashen Resin.")
	check(stock_quantity(stock, "bellweather_provisions", "museum_flashlight") == 0, "Scarce equipment must never replenish automatically.")
	check(stock_quantity(stock, "underworks_exchange", "clockglass_fragment") == 0, "Progression stock must remain scarce.")

	var repeated: Dictionary = SupplyModel.apply_due_restock(stock, merchants, regions, cycles, 900.0)
	check(not bool(repeated.get("changed", true)), "The same supply cycle must be idempotent.")
	var full_cycle: Dictionary = SupplyModel.apply_due_restock(stock, merchants, regions, cycles, 1080.0)
	check(bool(full_cycle.get("changed", false)), "A full-stock route must still consume its elapsed cycle.")
	check(int(full_cycle.get("total_added", -1)) == 0, "A full-stock cycle must not exceed authored targets.")
	check(int(cycles.get("bellweather_route", -1)) == 6, "A full-stock cycle must persist the advanced route cursor.")

	var old_save_cycles: Dictionary = SupplyModel.sanitize_cycles({}, regions, 900.0)
	check(int(old_save_cycles.get("bellweather_route", -1)) == 5, "An old save must initialise Bellweather at its current cycle without catch-up.")
	check(int(old_save_cycles.get("underworks_route", -1)) == 3, "An old save must initialise Underworks at its current cycle without catch-up.")


func test_runtime_persistence() -> void:
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Regional supply test must load the canonical runtime scene.")
	if not packed is PackedScene:
		return
	var runtime: Node = (packed as PackedScene).instantiate()
	var script_value: Variant = runtime.get_script()
	check(script_value is GDScript and str((script_value as GDScript).resource_path) == RUNTIME_SCRIPT, "Regional supply persistence must execute through the canonical presentation runtime.")
	root.add_child(runtime)
	await process_frame
	check(bool(runtime.call("supply_runtime_contract_ok")), "Canonical runtime must initialise every supply route.")
	var definitions_value: Variant = runtime.get("supply_region_definitions")
	var definitions: Dictionary = definitions_value if typeof(definitions_value) == TYPE_DICTIONARY else {}
	check(definitions.size() == 2, "Canonical runtime must load both reference supply routes.")
	check(str(runtime.call("supply_region_status_text", "bellweather_provisions")).contains("BELLWEATHER"), "Merchant status must identify the active supply route.")

	var stock_value: Variant = runtime.get("merchant_stock")
	var stock: Dictionary = stock_value if typeof(stock_value) == TYPE_DICTIONARY else {}
	var bellweather_value: Variant = stock.get("bellweather_provisions", {})
	var bellweather: Dictionary = bellweather_value if typeof(bellweather_value) == TYPE_DICTIONARY else {}
	bellweather["museum_tonic"] = 0
	stock["bellweather_provisions"] = bellweather
	runtime.set("merchant_stock", stock)
	runtime.set("play_time_seconds", 180.0)
	var cycles_value: Variant = runtime.get("supply_region_cycles")
	var cycles: Dictionary = cycles_value if typeof(cycles_value) == TYPE_DICTIONARY else {}
	cycles["bellweather_route"] = 0
	runtime.set("supply_region_cycles", cycles)
	var delivery_value: Variant = runtime.call("apply_due_supply_restock")
	var delivery: Dictionary = delivery_value if typeof(delivery_value) == TYPE_DICTIONARY else {}
	check(int(delivery.get("total_added", 0)) >= 1, "Canonical runtime must apply a due supply delivery.")
	stock_value = runtime.get("merchant_stock")
	stock = stock_value if typeof(stock_value) == TYPE_DICTIONARY else {}
	check(stock_quantity(stock, "bellweather_provisions", "museum_tonic") == 1, "Runtime delivery must mutate the authoritative merchant stock.")

	var profile_value: Variant = runtime.call("capture_save_profile", "slot_1", "Regional supply persistence")
	var profile: Dictionary = profile_value if typeof(profile_value) == TYPE_DICTIONARY else {}
	var payload_value: Variant = profile.get("payload", {})
	var payload: Dictionary = payload_value if typeof(payload_value) == TYPE_DICTIONARY else {}
	check(bool(payload.get("supply_regions_initialized", false)), "Captured saves must mark regional supply as initialised.")
	var captured_cycles_value: Variant = payload.get("supply_region_cycles", {})
	var captured_cycles: Dictionary = captured_cycles_value if typeof(captured_cycles_value) == TYPE_DICTIONARY else {}
	check(int(captured_cycles.get("bellweather_route", -1)) == 1, "Captured saves must persist the exact Bellweather cycle.")

	var restored: Node = (packed as PackedScene).instantiate()
	root.add_child(restored)
	await process_frame
	check(bool(restored.call("apply_save_profile", profile, CAMPAIGN_PATH)), "Canonical runtime must restore a supply-aware profile.")
	var restored_stock_value: Variant = restored.get("merchant_stock")
	var restored_stock: Dictionary = restored_stock_value if typeof(restored_stock_value) == TYPE_DICTIONARY else {}
	check(stock_quantity(restored_stock, "bellweather_provisions", "museum_tonic") == 1, "Loading a saved cycle must not duplicate its delivery.")
	var restored_cycles_value: Variant = restored.get("supply_region_cycles")
	var restored_cycles: Dictionary = restored_cycles_value if typeof(restored_cycles_value) == TYPE_DICTIONARY else {}
	check(int(restored_cycles.get("bellweather_route", -1)) == 1, "Loading must preserve the exact saved route cursor.")

	var legacy_profile: Dictionary = profile.duplicate(true)
	var legacy_payload_value: Variant = legacy_profile.get("payload", {})
	var legacy_payload: Dictionary = legacy_payload_value if typeof(legacy_payload_value) == TYPE_DICTIONARY else {}
	legacy_payload.erase("supply_region_cycles")
	legacy_payload.erase("supply_regions_initialized")
	legacy_profile["payload"] = legacy_payload
	SaveProfile.refresh_checksum(legacy_profile)
	var legacy: Node = (packed as PackedScene).instantiate()
	root.add_child(legacy)
	await process_frame
	check(bool(legacy.call("apply_save_profile", legacy_profile, CAMPAIGN_PATH)), "A pre-supply current-schema profile must remain loadable.")
	var legacy_cycles_value: Variant = legacy.get("supply_region_cycles")
	var legacy_cycles: Dictionary = legacy_cycles_value if typeof(legacy_cycles_value) == TYPE_DICTIONARY else {}
	check(int(legacy_cycles.get("bellweather_route", -1)) == 1, "A pre-supply profile must start at its current Bellweather cycle without retroactive stock.")
	var legacy_stock_value: Variant = legacy.get("merchant_stock")
	var legacy_stock: Dictionary = legacy_stock_value if typeof(legacy_stock_value) == TYPE_DICTIONARY else {}
	check(stock_quantity(legacy_stock, "bellweather_provisions", "museum_tonic") == 1, "A pre-supply profile must not receive a retroactive windfall.")

	for node_value in [runtime, restored, legacy]:
		if node_value is Node:
			var node := node_value as Node
			await HeadlessRuntimeCleanup.release(self, node)


func stock_quantity(stock: Dictionary, merchant_id: String, item_id: String) -> int:
	var merchant_value: Variant = stock.get(merchant_id, {})
	if typeof(merchant_value) != TYPE_DICTIONARY:
		return 0
	return int((merchant_value as Dictionary).get(item_id, 0))


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Regional supply smoke test passed: routes, bounded catch-up, targets, scarcity, cycle idempotence, save persistence and old-save safety are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
