extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")
const ReferenceJourneyDriver = preload("res://tools/reference_journey_driver.gd")
const EconomyModel = preload("res://src/game/economy_model.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyModel = preload("res://src/game/supply_region_model.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const BOSS_ID := "underworks_sentinel"
const SOAK_LAPS := 8
const SECONDS_PER_LAP := 195.0
const EXPECTED_ROUTE_TRANSITIONS := 32
const EXPECTED_ERA_SHIFTS := 16
const EXPECTED_SAVE_RESTORES := 4
const EXPECTED_SUPPLY_CYCLES := 13

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_playthrough")


func run_playthrough() -> void:
	var packed := ResourceLoader.load(
		RUNTIME_SCENE,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	check(packed is PackedScene, "Long-form progression scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime := (packed as PackedScene).instantiate()
	check(runtime != null, "Long-form progression scene must instantiate.")
	if runtime == null:
		finish()
		return
	root.add_child(runtime)
	await process_frame

	var journey_result := ReferenceJourneyDriver.complete(
		runtime,
		CAMPAIGN_PATH,
		Callable(self, "check")
	)
	if not failures.is_empty():
		await HeadlessRuntimeCleanup.release(self, runtime)
		finish()
		return

	var completion_value: Variant = journey_result.get("completion_profile", {})
	check(
		typeof(completion_value) == TYPE_DICTIONARY,
		"Long-form progression requires the canonical completion profile."
	)
	var baseline_fingerprint := str(
		journey_result.get(
			"completion_fingerprint",
			ReferenceJourneyDriver.progression_fingerprint(runtime)
		)
	)
	var final_chits := int(journey_result.get("final_chits", -1))
	var final_shards := int(journey_result.get("final_shards", -1))
	var initial_play_time := float(runtime.get("play_time_seconds"))
	var initial_cycles := dict(runtime, "supply_region_cycles").duplicate(true)
	check(
		initial_play_time < 180.0,
		"Canonical journey must finish before the first authored supply cycle."
	)
	check(
		total_cycle_count(initial_cycles) == 0,
		"Long-form progression must begin from zero consumed supply cycles."
	)

	var report := {
		"laps": SOAK_LAPS,
		"map_transitions": 0,
		"era_shifts": 0,
		"checkpoints": 0,
		"save_restores": 0,
		"supply_cycles_advanced": 0,
		"supply_units_added": 0
	}
	var unique_checksums: Dictionary = {}
	for lap_index in range(SOAK_LAPS):
		run_lap(
			runtime,
			lap_index,
			baseline_fingerprint,
			final_chits,
			final_shards,
			report,
			unique_checksums
		)

	var final_time := float(runtime.get("play_time_seconds"))
	var expected_final_time := initial_play_time + SECONDS_PER_LAP * SOAK_LAPS
	check(
		is_equal_approx(final_time, expected_final_time),
		"Long-form progression must advance only its deterministic active-play budget."
	)
	check(
		int(report.get("map_transitions", -1)) == EXPECTED_ROUTE_TRANSITIONS,
		"Long-form progression must complete exactly thirty-two map transitions."
	)
	check(
		int(report.get("era_shifts", -1)) == EXPECTED_ERA_SHIFTS,
		"Long-form progression must complete exactly sixteen era shifts."
	)
	check(
		int(report.get("checkpoints", -1)) == SOAK_LAPS,
		"Every long-form lap must produce one checksummed checkpoint."
	)
	check(
		int(report.get("save_restores", -1)) == EXPECTED_SAVE_RESTORES,
		"Every second long-form lap must prove destructive save restoration."
	)
	check(
		unique_checksums.size() == SOAK_LAPS,
		"Every long-form checkpoint must represent a distinct durable state."
	)
	check(
		int(report.get("supply_cycles_advanced", -1)) == EXPECTED_SUPPLY_CYCLES,
		"Long-form progression must consume all thirteen due regional supply cycles."
	)
	check(
		int(report.get("supply_units_added", -1)) == 1,
		"Only the purchased Museum Tonic unit may restock during the endurance route."
	)
	check_supply_cursors(runtime, initial_cycles, final_time)
	verify_progression_invariants(
		runtime,
		baseline_fingerprint,
		final_chits,
		final_shards
	)
	check(
		str(dict(runtime, "map_data").get("id", "")) == "museum_underworks",
		"Long-form progression must finish in Museum Underworks."
	)
	check(
		merchant_stock_quantity(runtime, "bellweather_provisions", "museum_tonic") == 3,
		"Bellweather Museum Tonic stock must recover to its authored target."
	)

	print("LONG_FORM_PROGRESSION_REPORT " + JSON.stringify(report))
	await HeadlessRuntimeCleanup.release(self, runtime)
	finish()


func run_lap(
	runtime: Object,
	lap_index: int,
	baseline_fingerprint: String,
	final_chits: int,
	final_shards: int,
	report: Dictionary,
	unique_checksums: Dictionary
) -> void:
	var start_era := "verdant" if lap_index % 2 == 0 else "ashen"
	check(
		bool(runtime.call(
			"activate_map",
			"bellweather_crossing",
			"from_underworks",
			start_era,
			false
		)),
		"Lap %d must return from Underworks to Bellweather." % (lap_index + 1)
	)
	report["map_transitions"] = int(report.get("map_transitions", 0)) + 1
	shift_era(runtime, lap_index, "Bellweather", report)

	var clockwood_era := str(runtime.get("current_era_id"))
	check(
		bool(runtime.call(
			"activate_map",
			"clockwood_edge",
			"from_bellweather",
			clockwood_era,
			false
		)),
		"Lap %d must travel from Bellweather to Clockwood." % (lap_index + 1)
	)
	report["map_transitions"] = int(report.get("map_transitions", 0)) + 1
	shift_era(runtime, lap_index, "Clockwood", report)

	var return_era := str(runtime.get("current_era_id"))
	check(
		bool(runtime.call(
			"activate_map",
			"bellweather_crossing",
			"from_clockwood",
			return_era,
			false
		)),
		"Lap %d must return from Clockwood to Bellweather." % (lap_index + 1)
	)
	report["map_transitions"] = int(report.get("map_transitions", 0)) + 1
	check(
		bool(runtime.call(
			"activate_map",
			"museum_underworks",
			"from_bellweather",
			return_era,
			false
		)),
		"Lap %d must return from Bellweather to Underworks." % (lap_index + 1)
	)
	report["map_transitions"] = int(report.get("map_transitions", 0)) + 1
	check(
		str(runtime.get("active_cinematic_id")).is_empty(),
		"Completed boss travel must not replay a cinematic on lap %d." % (lap_index + 1)
	)

	var before_time := float(runtime.get("play_time_seconds"))
	runtime.set("play_time_seconds", before_time + SECONDS_PER_LAP)
	var delivery_value: Variant = runtime.call("apply_due_supply_restock")
	var delivery: Dictionary = (
		delivery_value
		if typeof(delivery_value) == TYPE_DICTIONARY
		else {}
	)
	check(
		int(delivery.get("cycles_advanced", 0)) > 0,
		"Every long-form lap must cross at least one supply-cycle boundary."
	)
	report["supply_cycles_advanced"] = (
		int(report.get("supply_cycles_advanced", 0))
		+ int(delivery.get("cycles_advanced", 0))
	)
	report["supply_units_added"] = (
		int(report.get("supply_units_added", 0))
		+ int(delivery.get("total_added", 0))
	)

	var checkpoint: Dictionary = runtime.call(
		"capture_save_profile",
		"slot_2",
		"Long-form progression lap %d" % (lap_index + 1)
	)
	var checksum := str(checkpoint.get("checksum", ""))
	check(
		not checksum.is_empty(),
		"Lap %d checkpoint must be checksummed." % (lap_index + 1)
	)
	check(
		not unique_checksums.has(checksum),
		"Lap %d checkpoint checksum must be unique." % (lap_index + 1)
	)
	unique_checksums[checksum] = true
	report["checkpoints"] = int(report.get("checkpoints", 0)) + 1

	if (lap_index + 1) % 2 == 0:
		destructively_mutate_runtime(runtime)
		check(
			bool(runtime.call("apply_save_profile", checkpoint, CAMPAIGN_PATH)),
			"Lap %d checkpoint must restore through the production load path." % (lap_index + 1)
		)
		report["save_restores"] = int(report.get("save_restores", 0)) + 1
		check(
			str(dict(runtime, "map_data").get("id", "")) == "museum_underworks",
			"Lap %d restore must recover the Underworks map." % (lap_index + 1)
		)
		check(
			str(runtime.get("current_era_id")) == return_era,
			"Lap %d restore must recover the exact era." % (lap_index + 1)
		)

	verify_progression_invariants(
		runtime,
		baseline_fingerprint,
		final_chits,
		final_shards
	)


func shift_era(
	runtime: Object,
	lap_index: int,
	location_name: String,
	report: Dictionary
) -> void:
	var before := str(runtime.get("current_era_id"))
	runtime.call("shift_to_next_era")
	var after := str(runtime.get("current_era_id"))
	check(
		not after.is_empty() and after != before,
		"Lap %d must change era at %s." % [lap_index + 1, location_name]
	)
	report["era_shifts"] = int(report.get("era_shifts", 0)) + 1


func destructively_mutate_runtime(runtime: Object) -> void:
	runtime.set("inventory", {})
	runtime.set("session_state", {})
	runtime.set("currency_balances", {"archive_chits": 0})
	runtime.set("merchant_stock", {})
	runtime.set("supply_region_cycles", {})
	runtime.set("clock_shards", 0)
	runtime.set("map_data", {})
	runtime.set("current_era_id", "")
	runtime.set("engaged_bosses", {BOSS_ID: true})


func verify_progression_invariants(
	runtime: Object,
	baseline_fingerprint: String,
	final_chits: int,
	final_shards: int
) -> void:
	check(
		ReferenceJourneyDriver.progression_fingerprint(runtime) == baseline_fingerprint,
		"Repeated travel, era shifts and supply updates must not duplicate durable progression."
	)
	check(
		InventoryModel.count(dict(runtime, "inventory"), "clockglass_lens") == 1,
		"The crafted Clockglass Lens must remain exactly one."
	)
	check(
		InventoryModel.count(dict(runtime, "inventory"), "museum_tonic") == 2,
		"Supply restocking must not grant merchant stock directly to the player."
	)
	check(
		EconomyModel.balance(dict(runtime, "currency_balances"), "archive_chits") == final_chits,
		"Completed boss currency rewards must never duplicate."
	)
	check(
		int(runtime.get("clock_shards")) == final_shards,
		"Completed boss shard rewards must never duplicate."
	)
	check(
		dict(runtime, "session_state").get("underworks:boss:sentinel") == "defeated",
		"The completed Sentinel outcome must remain durable."
	)
	check(
		dict(runtime, "session_state").get("underworks:boss:archive_released") == true,
		"The completed Sentinel reward state must remain durable."
	)
	check(
		not bool(dict(runtime, "engaged_bosses").get(BOSS_ID, false)),
		"The completed Sentinel must never re-engage."
	)
	check(
		completed_boss_runtime_is_retired(runtime),
		"Completed boss runtime entities must remain retired after every revisit."
	)
	check(
		str(runtime.get("active_cinematic_id")).is_empty(),
		"Completed progression must not retain or replay a cinematic."
	)
	check(
		bool(runtime.call("can_open_save_overlay")),
		"Long-form progression must leave saving available."
	)


func check_supply_cursors(
	runtime: Object,
	initial_cycles: Dictionary,
	final_time: float
) -> void:
	var definitions := dict(runtime, "supply_region_definitions")
	var cycles := dict(runtime, "supply_region_cycles")
	var expected_total := 0
	for region_key in definitions.keys():
		var region_id := str(region_key)
		var region_value: Variant = definitions.get(region_key, {})
		var region_data: Dictionary = (
			region_value
			if typeof(region_value) == TYPE_DICTIONARY
			else {}
		)
		var expected := SupplyModel.cycle_at(region_data, final_time)
		var actual := int(cycles.get(region_id, -1))
		check(
			actual == expected,
			"Supply route '%s' must consume every due cycle exactly once." % region_id
		)
		expected_total += expected - int(initial_cycles.get(region_id, 0))
	check(
		expected_total == EXPECTED_SUPPLY_CYCLES,
		"Reference supply routes must produce thirteen deterministic cycles."
	)


func completed_boss_runtime_is_retired(runtime: Object) -> bool:
	var entities_value: Variant = runtime.get("runtime_entities")
	if typeof(entities_value) != TYPE_ARRAY:
		return false
	for entity_value in entities_value as Array:
		if (
			typeof(entity_value) == TYPE_DICTIONARY
			and str((entity_value as Dictionary).get("placement_id", "")) == BOSS_ID
		):
			var entity: Dictionary = entity_value
			return (
				not bool(entity.get("active", true))
				and int(entity.get("health", 1)) <= 0
			)
	return true


func merchant_stock_quantity(
	runtime: Object,
	merchant_id: String,
	item_id: String
) -> int:
	var merchants := dict(runtime, "merchant_stock")
	var merchant_value: Variant = merchants.get(merchant_id, {})
	if typeof(merchant_value) != TYPE_DICTIONARY:
		return 0
	return int((merchant_value as Dictionary).get(item_id, 0))


func total_cycle_count(cycles: Dictionary) -> int:
	var output := 0
	for cycle_value in cycles.values():
		output += int(cycle_value)
	return output


func dict(runtime: Object, property_name: String) -> Dictionary:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Long-form progression smoke test passed: eight completed-world laps, thirty-two map transitions, sixteen era shifts, thirteen consumed supply cycles, eight checkpoints and four destructive restorations remained deterministic without duplicate rewards.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
