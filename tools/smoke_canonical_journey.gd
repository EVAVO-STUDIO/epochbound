extends SceneTree

const EconomyModel = preload("res://src/game/economy_model.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const BOSS_PLACEMENT := "underworks_sentinel"
const REINFORCEMENTS := ["curator_echo_west", "curator_echo_east"]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_journey")


func run_journey() -> void:
	var packed := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Canonical journey runtime scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime := (packed as PackedScene).instantiate()
	check(runtime != null, "Canonical journey runtime scene must instantiate.")
	if runtime == null:
		finish()
		return
	root.add_child(runtime)
	await process_frame

	check(runtime.has_method("capture_save_profile"), "Canonical journey requires deterministic save capture.")
	check(runtime.has_method("apply_save_profile"), "Canonical journey requires in-memory save restoration.")
	check(runtime.has_method("craft_inventory_recipe"), "Canonical journey requires runtime crafting.")
	check(runtime.has_method("open_merchant"), "Canonical journey requires player-facing merchant entry.")
	check(runtime.has_method("finalize_boss_outcomes"), "Canonical journey requires durable boss completion.")

	runtime.call("change_flow", 4)
	check(str((runtime.get("map_data") as Dictionary).get("id", "")) == "bellweather_crossing", "A new reference journey must begin at Bellweather Crossing.")

	# Buy one recovery item through the actual merchant UI path.
	check(bool(runtime.call("open_merchant", "bellweather_provisions")), "Bellweather Provisions must open at journey start.")
	var buy_ids: PackedStringArray = runtime.call("merchant_entry_ids")
	var tonic_index := buy_ids.find("museum_tonic")
	check(tonic_index >= 0, "Bellweather Provisions must sell Museum Tonic.")
	if tonic_index >= 0:
		runtime.set("merchant_index", tonic_index)
		check(bool(runtime.call("activate_merchant_selection")), "Canonical journey must purchase Museum Tonic.")
	runtime.call("close_merchant", false)
	check(InventoryModel.count(runtime_dictionary(runtime, "inventory"), "museum_tonic") == 2, "Merchant purchase must persist in inventory.")
	check(EconomyModel.balance(runtime_dictionary(runtime, "currency_balances"), "archive_chits") == 42, "Merchant purchase must debit the authored price.")

	# Collect the first crafting material route and checkpoint it.
	var bell_map: Dictionary = runtime.get("map_data")
	var well_cue := find_cue(bell_map, "well_name_scent")
	check(not well_cue.is_empty(), "Bellweather well discovery must exist.")
	if not well_cue.is_empty():
		runtime.call("reveal_companion_cue", well_cue)
	var crossing_index := entity_index(runtime_array(runtime, "runtime_entities"), "crossing_shard")
	check(crossing_index >= 0, "Bellweather clock shard must resolve.")
	if crossing_index >= 0:
		runtime.call("collect_pickup", crossing_index)
	check(InventoryModel.count(runtime_dictionary(runtime, "inventory"), "brass_filings") == 3, "Bellweather discovery must grant two Brass Filings.")
	check(InventoryModel.count(runtime_dictionary(runtime, "inventory"), "clockglass_fragment") == 1, "Bellweather shard must grant the first Clockglass Fragment.")

	var checkpoint_one: Dictionary = runtime.call("capture_save_profile", "slot_1", "Canonical journey: Bellweather")
	check(not checkpoint_one.is_empty(), "First canonical checkpoint must capture.")
	var checkpoint_one_fingerprint := str(checkpoint_one.get("checksum", ""))
	check(not checkpoint_one_fingerprint.is_empty(), "First canonical checkpoint must be checksummed.")

	# Prove the first restore crosses inventory, wallet, map and durable pickup state.
	runtime.set("inventory", {})
	runtime.set("currency_balances", {"archive_chits": 1})
	runtime.set("session_state", {})
	check(bool(runtime.call("activate_map", "clockwood_edge", "from_bellweather", "ashen", false)), "Mutation setup must leave Bellweather.")
	check(bool(runtime.call("apply_save_profile", checkpoint_one, CAMPAIGN_PATH)), "First canonical checkpoint must restore through the normal load path.")
	check(str((runtime.get("map_data") as Dictionary).get("id", "")) == "bellweather_crossing", "First restore must return to Bellweather Crossing.")
	check(InventoryModel.count(runtime_dictionary(runtime, "inventory"), "clockglass_fragment") == 1, "First restore must recover the first fragment.")
	check(EconomyModel.balance(runtime_dictionary(runtime, "currency_balances"), "archive_chits") == 42, "First restore must recover the exact wallet.")
	check(runtime_dictionary(runtime, "session_state").get("bellweather:crossing_shard") == "collected", "First restore must preserve collected pickup state.")

	# Travel, collect the second route, unlock both recipes and craft both outputs.
	check(bool(runtime.call("activate_map", "clockwood_edge", "from_bellweather", "ashen", false)), "Canonical journey must travel to Clockwood Edge.")
	var clockwood_map: Dictionary = runtime.get("map_data")
	var ash_cue := find_cue(clockwood_map, "cold_ash_cache")
	check(not ash_cue.is_empty(), "Clockwood Ashen cache must exist.")
	if not ash_cue.is_empty():
		runtime.call("reveal_companion_cue", ash_cue)
	check(bool(runtime.call("craft_inventory_recipe", "ember_salve_recipe")), "Canonical journey must craft Ember Salve.")
	check(InventoryModel.count(runtime_dictionary(runtime, "inventory"), "ember_salve") == 1, "Ember Salve must exist after crafting.")

	runtime.set("current_era_id", "verdant")
	runtime.call("sync_runtime_entities", false)
	clockwood_map = runtime.get("map_data")
	var trail_cue := find_cue(clockwood_map, "future_bark_trail")
	check(not trail_cue.is_empty(), "Clockwood future-bark trail must exist.")
	if not trail_cue.is_empty():
		runtime.call("reveal_companion_cue", trail_cue)
	var clockwood_index := entity_index(runtime_array(runtime, "runtime_entities"), "clockwood_shard")
	check(clockwood_index >= 0, "Clockwood clock shard must resolve.")
	if clockwood_index >= 0:
		runtime.call("collect_pickup", clockwood_index)
	check(bool(runtime.call("craft_inventory_recipe", "clockglass_lens_recipe")), "Canonical journey must craft the Clockglass Lens.")
	check(InventoryModel.count(runtime_dictionary(runtime, "inventory"), "clockglass_lens") == 1, "Clockglass Lens must exist before the boss route.")

	# Enter and resolve the complete authored boss encounter.
	check(bool(runtime.call("equip_specific_item", "museum_flashlight")), "Canonical journey must equip Illuminate Darkness.")
	check(bool(runtime.call("activate_map", "museum_underworks", "from_bellweather", "verdant", false)), "Canonical journey must enter Museum Underworks.")
	runtime.set("player", Vector2(320, 224))
	runtime.set("companion", Vector2(294, 238))
	runtime.call("update_boss_engagements")
	check(bool(runtime_dictionary(runtime, "engaged_bosses").get(BOSS_PLACEMENT, false)), "Canonical journey must engage the Underworks Sentinel.")
	if runtime.has_method("finish_cinematic") and not str(runtime.get("active_cinematic_id")).is_empty():
		runtime.call("finish_cinematic", true)
	runtime.call("shift_to_next_era")
	check(str(runtime.get("current_era_id")) == "ashen", "Canonical journey must preserve era shifting during the boss fight.")

	var entities := runtime_array(runtime, "runtime_entities")
	var boss_index := entity_index(entities, BOSS_PLACEMENT)
	check(boss_index >= 0, "Underworks Sentinel placement must resolve.")
	if boss_index >= 0:
		runtime.call("damage_entity", boss_index, 999, "ELI")
		check(str(runtime_dictionary(runtime, "boss_phase_ids").get(BOSS_PLACEMENT, "")) == "last_accession", "Oversized damage must stop at the authored final phase.")
		runtime.call("damage_entity", boss_index, 999, "ELI")
	for reinforcement_id in REINFORCEMENTS:
		entities = runtime_array(runtime, "runtime_entities")
		var reinforcement_index := entity_index(entities, reinforcement_id)
		check(reinforcement_index >= 0, "Canonical journey reinforcement '%s' must resolve." % reinforcement_id)
		if reinforcement_index >= 0:
			runtime.call("damage_entity", reinforcement_index, 999, "ELI")
	runtime.call("update_zone_clear_states")
	runtime.call("finalize_boss_outcomes")
	if runtime.has_method("finish_cinematic") and not str(runtime.get("active_cinematic_id")).is_empty():
		runtime.call("finish_cinematic", false)

	var completed_state := runtime_dictionary(runtime, "session_state")
	check(completed_state.get("underworks:boss:sentinel") == "defeated", "Canonical journey must publish the durable boss outcome.")
	check(completed_state.get("underworks:boss:archive_released") == true, "Canonical journey must publish the boss reward state.")
	check(bool(runtime.call("can_open_save_overlay")), "Saving must reopen after complete boss resolution.")
	var boss_chits := EconomyModel.balance(runtime_dictionary(runtime, "currency_balances"), "archive_chits")
	var boss_shards := int(runtime.get("clock_shards"))
	check(boss_chits >= 57, "Canonical journey must retain merchant spending and boss currency rewards.")
	check(boss_shards >= 7, "Canonical journey must retain world and boss shard rewards.")

	var checkpoint_two: Dictionary = runtime.call("capture_save_profile", "slot_2", "Canonical journey: Sentinel defeated")
	check(not checkpoint_two.is_empty(), "Second canonical checkpoint must capture.")
	check(str(checkpoint_two.get("checksum", "")) != checkpoint_one_fingerprint, "Second checkpoint must represent later durable progress.")

	# Prove the second restore keeps the completed route idempotent.
	runtime.set("inventory", {})
	runtime.set("session_state", {})
	runtime.set("currency_balances", {"archive_chits": 0})
	runtime.set("clock_shards", 0)
	check(bool(runtime.call("apply_save_profile", checkpoint_two, CAMPAIGN_PATH)), "Second canonical checkpoint must restore through the normal load path.")
	check(InventoryModel.count(runtime_dictionary(runtime, "inventory"), "clockglass_lens") == 1, "Second restore must preserve the crafted key item.")
	check(runtime_dictionary(runtime, "session_state").get("underworks:boss:sentinel") == "defeated", "Second restore must preserve the defeated boss outcome.")
	check(EconomyModel.balance(runtime_dictionary(runtime, "currency_balances"), "archive_chits") == boss_chits, "Second restore must preserve the exact final wallet.")
	check(int(runtime.get("clock_shards")) == boss_shards, "Second restore must preserve the exact shard total.")
	check(not bool(runtime_dictionary(runtime, "engaged_bosses").get(BOSS_PLACEMENT, false)), "A restored completed boss must not remain engaged.")

	root.remove_child(runtime)
	runtime.free()
	finish()


func runtime_dictionary(runtime: Object, property_name: String) -> Dictionary:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func runtime_array(runtime: Object, property_name: String) -> Array:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_ARRAY else []


func entity_index(entities: Array, placement_id: String) -> int:
	for index in range(entities.size()):
		if typeof(entities[index]) == TYPE_DICTIONARY and str((entities[index] as Dictionary).get("placement_id", "")) == placement_id:
			return index
	return -1


func find_cue(map_data: Dictionary, cue_id: String) -> Dictionary:
	var value: Variant = map_data.get("companion_cues", [])
	if typeof(value) != TYPE_ARRAY:
		return {}
	for cue_value in value:
		if typeof(cue_value) == TYPE_DICTIONARY and str((cue_value as Dictionary).get("id", "")) == cue_id:
			return (cue_value as Dictionary).duplicate(true)
	return {}


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Canonical journey smoke test passed: merchant purchase, discoveries, crafting, travel, era shift, boss phases, durable outcomes and two exact save restorations are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
