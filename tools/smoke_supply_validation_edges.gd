extends SceneTree

const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyValidator = preload("res://src/content/supply_region_validator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_region_validation()
	test_merchant_and_stock_validation()
	test_profile_validation()
	finish()


func test_region_validation() -> void:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var sources: Dictionary = {}
	SupplyValidator.validate_region_records(
		[
			{
				"id": "Bad Route",
				"display_name": "",
				"restock_interval_seconds": 1,
				"max_catchup_cycles": 0
			},
			{
				"id": "valid_route",
				"display_name": "Valid Route",
				"restock_interval_seconds": 300,
				"max_catchup_cycles": 2
			},
			{
				"id": "valid_route",
				"display_name": "Duplicate Route",
				"restock_interval_seconds": 300,
				"max_catchup_cycles": 2
			}
		],
		"test/economy.json",
		sources,
		errors,
		warnings
	)
	check(contains_fragment(errors, "normalised lowercase"), "Invalid supply route IDs must be rejected.")
	check(contains_fragment(errors, "display_name is required"), "Supply routes require display names.")
	check(contains_fragment(errors, "restock_interval_seconds"), "Out-of-range supply intervals must be rejected.")
	check(contains_fragment(errors, "max_catchup_cycles"), "Out-of-range catch-up limits must be rejected.")
	check(contains_fragment(errors, "repeated"), "Duplicate supply routes must be rejected.")

	var type_errors: Array[String] = []
	var type_warnings: Array[String] = []
	var type_sources: Dictionary = {}
	SupplyValidator.validate_region_records(
		[{
			"id": 7,
			"display_name": true,
			"restock_interval_seconds": "300",
			"max_catchup_cycles": 2.0
		}],
		"test/type-errors.json",
		type_sources,
		type_errors,
		type_warnings
	)
	check(contains_fragment(type_errors, "id must be a string"), "Supply route IDs must reject numeric coercion.")
	check(contains_fragment(type_errors, "display_name must be a string"), "Supply route names must reject boolean coercion.")
	check(contains_fragment(type_errors, "restock_interval_seconds must be numeric"), "Supply intervals must reject numeric strings.")
	check(contains_fragment(type_errors, "max_catchup_cycles must be an integer"), "Supply catch-up limits must reject floating-point values.")


func test_merchant_and_stock_validation() -> void:
	var regions: Dictionary = {
		"known_route": SupplyCatalog.default_region("known_route", "Known Route", 180.0, 4)
	}
	var items: Dictionary = {
		"tonic": {"id": "tonic", "kind": "consumable", "stack_limit": 9, "value": 10},
		"tool": {"id": "tool", "kind": "equipment", "stack_limit": 1, "value": 40},
		"bolts": {"id": "bolts", "kind": "ammunition", "stack_limit": 60, "value": 2}
	}
	var merchants: Dictionary = {
		"unknown_route_merchant": {"id": "unknown_route_merchant", "supply_region_id": "missing_route", "stock": []},
		"invalid_stock_merchant": {
			"id": "invalid_stock_merchant",
			"supply_region_id": "known_route",
			"stock": [
				{"item_id": "tonic", "quantity": 3, "unlimited": true, "restock_quantity": 1, "restock_target": 3},
				{"item_id": "tool", "quantity": 1, "unlimited": false, "restock_quantity": 1, "restock_target": 1},
				{"item_id": "bolts", "quantity": 20, "unlimited": false, "restock_quantity": 5, "restock_target": 10}
			]
		},
		"typed_stock_merchant": {
			"id": "typed_stock_merchant",
			"supply_region_id": 9,
			"stock": [{
				"item_id": "tonic",
				"quantity": 1,
				"unlimited": false,
				"restock_quantity": "1",
				"restock_target": 3.0
			}]
		}
	}
	var catalog: Dictionary = {"supply_regions": [], "merchants": merchants.values()}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var region_sources: Dictionary = {}
	SupplyValidator.validate_catalog_file(
		catalog,
		"test/economy.json",
		regions,
		merchants,
		items,
		region_sources,
		errors,
		warnings
	)
	check(contains_fragment(errors, "unknown supply_region_id"), "Unknown merchant supply routes must be rejected.")
	check(contains_fragment(errors, "unlimited stock cannot define"), "Unlimited stock must reject replenishment fields.")
	check(contains_fragment(errors, "only consumable, material or ammunition"), "Equipment must remain outside automatic restocking.")
	check(contains_fragment(errors, "cannot be lower than the initial quantity"), "Restock targets below initial stock must be rejected.")
	check(contains_fragment(errors, "supply_region_id must be a string"), "Merchant routes must reject numeric coercion.")
	check(contains_fragment(errors, "restock_quantity must be an integer"), "Restock quantities must reject numeric strings.")
	check(contains_fragment(errors, "restock_target must be an integer"), "Restock targets must reject floating-point values.")

	var no_route_errors: Array[String] = []
	var no_route_warnings: Array[String] = []
	var no_route_sources: Dictionary = {}
	var no_route_merchants: Dictionary = {
		"no_route": {"id": "no_route", "stock": []}
	}
	SupplyValidator.validate_catalog_file(
		{
			"supply_regions": [],
			"merchants": [{
				"id": "no_route",
				"stock": [{"item_id": "tonic", "quantity": 1, "unlimited": false, "restock_quantity": 1, "restock_target": 1}]
			}]
		},
		"test/no_route.json",
		regions,
		no_route_merchants,
		items,
		no_route_sources,
		no_route_errors,
		no_route_warnings
	)
	check(contains_fragment(no_route_errors, "requires the merchant to declare supply_region_id"), "Renewable stock must require a merchant route.")


func test_profile_validation() -> void:
	var regions: Dictionary = {
		"known_route": SupplyCatalog.default_region("known_route", "Known Route", 180.0, 4)
	}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	SupplyValidator.validate_profile_supply(
		{
			"supply_regions_initialized": true,
			"supply_region_cycles": {"unknown_route": 0, "known_route": 99}
		},
		regions,
		360.0,
		errors,
		warnings
	)
	check(contains_fragment(errors, "unknown region"), "Saved supply cycles must reject unknown routes.")
	check(contains_fragment(errors, "between zero and 2"), "Saved cycles cannot exceed the play-time-derived current cycle.")

	errors.clear()
	warnings.clear()
	SupplyValidator.validate_profile_supply(
		{"supply_regions_initialized": true, "supply_region_cycles": {}},
		regions,
		360.0,
		errors,
		warnings
	)
	check(contains_fragment(errors, "is missing 'known_route'"), "Initialised profiles must contain every declared route cursor.")

	errors.clear()
	warnings.clear()
	SupplyValidator.validate_profile_supply(
		{"supply_regions_initialized": false, "supply_region_cycles": {"known_route": 1}},
		regions,
		360.0,
		errors,
		warnings
	)
	check(errors.is_empty(), "A pre-supply compatibility payload must not be rejected solely for pending initialisation.")
	check(contains_fragment(warnings, "will replace them"), "Pending initialisation with stale cycle data must be explained.")

	errors.clear()
	warnings.clear()
	SupplyValidator.validate_profile_supply(
		{
			"supply_regions_initialized": "true",
			"supply_region_cycles": {"known_route": 1.0}
		},
		regions,
		360.0,
		errors,
		warnings
	)
	check(contains_fragment(errors, "supply_regions_initialized must be boolean"), "Supply initialisation state must reject string coercion.")
	check(contains_fragment(errors, "must be an integer"), "Saved supply cycles must reject floating-point coercion.")


func contains_fragment(messages: Variant, fragment: String) -> bool:
	if typeof(messages) != TYPE_ARRAY:
		return false
	for message in messages:
		if fragment.to_lower() in str(message).to_lower():
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Regional supply validation-edge smoke test passed: route IDs, field types, intervals, catch-up limits, scarcity kinds, targets, bindings and saved cycles fail closed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
