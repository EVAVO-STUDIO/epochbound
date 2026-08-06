extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")

const EconomyModel = preload("res://src/game/economy_model.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const BOSS_ID := "underworks_sentinel"
const REINFORCEMENTS := ["curator_echo_west", "curator_echo_east"]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_journey")


func run_journey() -> void:
	var packed := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Canonical journey scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime := (packed as PackedScene).instantiate()
	check(runtime != null, "Canonical journey scene must instantiate.")
	if runtime == null:
		finish()
		return
	root.add_child(runtime)
	await process_frame
	runtime.call("change_flow", 4)

	check(str(dict(runtime, "map_data").get("id", "")) == "bellweather_crossing", "Journey must begin at Bellweather Crossing.")
	check(runtime.has_method("capture_save_profile") and runtime.has_method("apply_save_profile"), "Journey requires exact save capture and restoration.")

	# Merchant purchase through the player-facing transaction path.
	check(bool(runtime.call("open_merchant", "bellweather_provisions")), "Bellweather merchant must open.")
	var buy_ids: PackedStringArray = runtime.call("merchant_entry_ids")
	var tonic_index := buy_ids.find("museum_tonic")
	check(tonic_index >= 0, "Bellweather merchant must stock Museum Tonic.")
	if tonic_index >= 0:
		runtime.set("merchant_index", tonic_index)
		check(bool(runtime.call("activate_merchant_selection")), "Journey must buy Museum Tonic.")
	runtime.call("close_merchant", false)
	check(InventoryModel.count(dict(runtime, "inventory"), "museum_tonic") == 2, "Purchase must add one tonic.")
	check(EconomyModel.balance(dict(runtime, "currency_balances"), "archive_chits") == 42, "Purchase must debit eighteen Archive Chits.")

	# Bellweather discovery and first durable checkpoint.
	var bell_map := dict(runtime, "map_data")
	runtime.call("reveal_companion_cue", record_by_id(bell_map.get("companion_cues", []), "well_name_scent"))
	collect(runtime, "crossing_shard")
	check(InventoryModel.count(dict(runtime, "inventory"), "brass_filings") == 3, "Well discovery must grant Brass Filings.")
	check(InventoryModel.count(dict(runtime, "inventory"), "clockglass_fragment") == 1, "Bellweather shard must grant the first fragment.")

	var first: Dictionary = runtime.call("capture_save_profile", "slot_1", "Canonical journey: Bellweather")
	check(not str(first.get("checksum", "")).is_empty(), "First checkpoint must be checksummed.")
	runtime.set("inventory", {})
	runtime.set("currency_balances", {"archive_chits": 1})
	runtime.set("session_state", {})
	check(bool(runtime.call("activate_map", "clockwood_edge", "from_bellweather", "ashen", false)), "Mutation setup must leave Bellweather.")
	check(bool(runtime.call("apply_save_profile", first, CAMPAIGN_PATH)), "First checkpoint must restore through the normal load path.")
	check(str(dict(runtime, "map_data").get("id", "")) == "bellweather_crossing", "First restore must return to Bellweather.")
	check(InventoryModel.count(dict(runtime, "inventory"), "clockglass_fragment") == 1, "First restore must recover the fragment.")
	check(EconomyModel.balance(dict(runtime, "currency_balances"), "archive_chits") == 42, "First restore must recover the wallet.")
	check(dict(runtime, "session_state").get("bellweather:clock_shard") == "collected", "First restore must preserve pickup state.")

	# Cross-map, cross-era crafting route.
	check(bool(runtime.call("activate_map", "clockwood_edge", "from_bellweather", "ashen", false)), "Journey must enter Clockwood Edge.")
	var clockwood_map := dict(runtime, "map_data")
	runtime.call("reveal_companion_cue", record_by_id(clockwood_map.get("companion_cues", []), "cold_ash_cache"))
	check(bool(runtime.call("craft_inventory_recipe", "ember_salve_recipe")), "Journey must craft Ember Salve.")
	check(InventoryModel.count(dict(runtime, "inventory"), "ember_salve") == 1, "Crafting must add Ember Salve.")

	runtime.set("current_era_id", "verdant")
	runtime.call("sync_runtime_entities", false)
	clockwood_map = dict(runtime, "map_data")
	runtime.call("reveal_companion_cue", record_by_id(clockwood_map.get("companion_cues", []), "future_bark_trail"))
	collect(runtime, "clockwood_shard")
	check(bool(runtime.call("craft_inventory_recipe", "clockglass_lens_recipe")), "Journey must craft the Clockglass Lens.")
	check(InventoryModel.count(dict(runtime, "inventory"), "clockglass_lens") == 1, "Crafting must add the Clockglass Lens.")

	# Capability gate and complete boss outcome.
	var stairs := record_by_id(bell_map.get("connections", []), "stairs_to_underworks")
	check(bool(runtime.call("authored_requirements_met", stairs)), "Starting flashlight must satisfy Illuminate Darkness.")
	check(bool(runtime.call("activate_map", "museum_underworks", "from_bellweather", "verdant", false)), "Journey must enter Museum Underworks.")
	runtime.set("player", Vector2(320, 224))
	runtime.set("companion", Vector2(294, 238))
	runtime.call("update_boss_engagements")
	check(bool(dict(runtime, "engaged_bosses").get(BOSS_ID, false)), "Journey must engage the Underworks Sentinel.")
	if not str(runtime.get("active_cinematic_id")).is_empty():
		runtime.call("finish_cinematic", true)
	runtime.call("shift_to_next_era")
	check(str(runtime.get("current_era_id")) == "ashen", "Boss route must preserve authored era shifting.")

	var boss_index := entity_index(array(runtime, "runtime_entities"), BOSS_ID)
	check(boss_index >= 0, "Underworks Sentinel must resolve.")
	if boss_index >= 0:
		runtime.call("damage_entity", boss_index, 999, "ELI")
		check(str(dict(runtime, "boss_phase_ids").get(BOSS_ID, "")) == "last_accession", "Large damage must stop at Last Accession.")
		runtime.call("damage_entity", boss_index, 999, "ELI")
	for reinforcement_id in REINFORCEMENTS:
		var reinforcement_index := entity_index(array(runtime, "runtime_entities"), reinforcement_id)
		check(reinforcement_index >= 0, "Reinforcement '%s' must resolve." % reinforcement_id)
		if reinforcement_index >= 0:
			runtime.call("damage_entity", reinforcement_index, 999, "ELI")
	runtime.call("update_zone_clear_states")
	runtime.call("finalize_boss_outcomes")
	if not str(runtime.get("active_cinematic_id")).is_empty():
		runtime.call("finish_cinematic", false)

	var completed := dict(runtime, "session_state")
	check(completed.get("underworks:boss:sentinel") == "defeated", "Journey must publish the durable boss outcome.")
	check(completed.get("underworks:boss:archive_released") == true, "Journey must publish the boss reward state.")
	check(bool(runtime.call("can_open_save_overlay")), "Saving must reopen after the boss conclusion.")
	var final_chits := EconomyModel.balance(dict(runtime, "currency_balances"), "archive_chits")
	var final_shards := int(runtime.get("clock_shards"))
	check(final_chits >= 57, "Journey must retain spending and boss currency rewards.")
	check(final_shards >= 7, "Journey must retain world and boss shard rewards.")

	# Final checkpoint proves completion is exact and idempotent.
	var second: Dictionary = runtime.call("capture_save_profile", "slot_2", "Canonical journey: Sentinel defeated")
	check(not str(second.get("checksum", "")).is_empty(), "Second checkpoint must be checksummed.")
	check(str(second.get("checksum", "")) != str(first.get("checksum", "")), "Second checkpoint must represent later progress.")
	runtime.set("inventory", {})
	runtime.set("session_state", {})
	runtime.set("currency_balances", {"archive_chits": 0})
	runtime.set("clock_shards", 0)
	check(bool(runtime.call("apply_save_profile", second, CAMPAIGN_PATH)), "Second checkpoint must restore through the normal load path.")
	check(InventoryModel.count(dict(runtime, "inventory"), "clockglass_lens") == 1, "Final restore must preserve the crafted key item.")
	check(dict(runtime, "session_state").get("underworks:boss:sentinel") == "defeated", "Final restore must preserve boss completion.")
	check(EconomyModel.balance(dict(runtime, "currency_balances"), "archive_chits") == final_chits, "Final restore must preserve the wallet exactly.")
	check(int(runtime.get("clock_shards")) == final_shards, "Final restore must preserve shards exactly.")
	check(not bool(dict(runtime, "engaged_bosses").get(BOSS_ID, false)), "A restored completed boss must not remain engaged.")

	await HeadlessRuntimeCleanup.release(self, runtime)
	finish()


func collect(runtime: Object, placement_id: String) -> void:
	var index := entity_index(array(runtime, "runtime_entities"), placement_id)
	check(index >= 0, "Pickup '%s' must resolve." % placement_id)
	if index >= 0:
		runtime.call("collect_pickup", index)


func record_by_id(value: Variant, record_id: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {}
	for record_value in value as Array:
		if typeof(record_value) == TYPE_DICTIONARY and str((record_value as Dictionary).get("id", "")) == record_id:
			return (record_value as Dictionary).duplicate(true)
	return {}


func entity_index(entities: Array, placement_id: String) -> int:
	for index in range(entities.size()):
		if typeof(entities[index]) == TYPE_DICTIONARY and str((entities[index] as Dictionary).get("placement_id", "")) == placement_id:
			return index
	return -1


func dict(runtime: Object, property_name: String) -> Dictionary:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array(runtime: Object, property_name: String) -> Array:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_ARRAY else []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Canonical journey smoke test passed: merchant purchase, discovery, crafting, travel, era shift, boss phases, durable outcomes and two exact save restorations are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
