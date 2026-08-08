extends RefCounted

const EconomyModel = preload("res://src/game/economy_model.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const SaveProfile = preload("res://src/content/save_profile.gd")

const BOSS_ID := "underworks_sentinel"
const REINFORCEMENTS := ["curator_echo_west", "curator_echo_east"]


static func complete(
	runtime: Object,
	campaign_path: String,
	check_callback: Callable
) -> Dictionary:
	runtime.call("change_flow", 4)

	check(check_callback, str(dict(runtime, "map_data").get("id", "")) == "bellweather_crossing", "Journey must begin at Bellweather Crossing.")
	check(
		check_callback,
		runtime.has_method("capture_save_profile") and runtime.has_method("apply_save_profile"),
		"Journey requires exact save capture and restoration."
	)

	# Merchant purchase through the player-facing transaction path.
	check(check_callback, bool(runtime.call("open_merchant", "bellweather_provisions")), "Bellweather merchant must open.")
	var buy_ids: PackedStringArray = runtime.call("merchant_entry_ids")
	var tonic_index := buy_ids.find("museum_tonic")
	check(check_callback, tonic_index >= 0, "Bellweather merchant must stock Museum Tonic.")
	if tonic_index >= 0:
		runtime.set("merchant_index", tonic_index)
		check(check_callback, bool(runtime.call("activate_merchant_selection")), "Journey must buy Museum Tonic.")
	runtime.call("close_merchant", false)
	check(
		check_callback,
		InventoryModel.count(dict(runtime, "inventory"), "museum_tonic") == 2,
		"Purchase must add one tonic."
	)
	check(
		check_callback,
		EconomyModel.balance(dict(runtime, "currency_balances"), "archive_chits") == 42,
		"Purchase must debit eighteen Archive Chits."
	)

	# Bellweather discovery and first durable checkpoint.
	var bell_map := dict(runtime, "map_data")
	runtime.call(
		"reveal_companion_cue",
		record_by_id(bell_map.get("companion_cues", []), "well_name_scent")
	)
	collect(runtime, "crossing_shard", check_callback)
	check(
		check_callback,
		InventoryModel.count(dict(runtime, "inventory"), "brass_filings") == 3,
		"Well discovery must grant Brass Filings."
	)
	check(
		check_callback,
		InventoryModel.count(dict(runtime, "inventory"), "clockglass_fragment") == 1,
		"Bellweather shard must grant the first fragment."
	)

	var first: Dictionary = runtime.call(
		"capture_save_profile",
		"slot_1",
		"Canonical journey: Bellweather"
	)
	check(
		check_callback,
		not str(first.get("checksum", "")).is_empty(),
		"First checkpoint must be checksummed."
	)
	runtime.set("inventory", {})
	runtime.set("currency_balances", {"archive_chits": 1})
	runtime.set("session_state", {})
	check(
		check_callback,
		bool(runtime.call("activate_map", "clockwood_edge", "from_bellweather", "ashen", false)),
		"Mutation setup must leave Bellweather."
	)
	check(
		check_callback,
		bool(runtime.call("apply_save_profile", first, campaign_path)),
		"First checkpoint must restore through the normal load path."
	)
	check(
		check_callback,
		str(dict(runtime, "map_data").get("id", "")) == "bellweather_crossing",
		"First restore must return to Bellweather."
	)
	check(
		check_callback,
		InventoryModel.count(dict(runtime, "inventory"), "clockglass_fragment") == 1,
		"First restore must recover the fragment."
	)
	check(
		check_callback,
		EconomyModel.balance(dict(runtime, "currency_balances"), "archive_chits") == 42,
		"First restore must recover the wallet."
	)
	check(
		check_callback,
		dict(runtime, "session_state").get("bellweather:clock_shard") == "collected",
		"First restore must preserve pickup state."
	)

	# Cross-map, cross-era crafting route.
	check(
		check_callback,
		bool(runtime.call("activate_map", "clockwood_edge", "from_bellweather", "ashen", false)),
		"Journey must enter Clockwood Edge."
	)
	var clockwood_map := dict(runtime, "map_data")
	runtime.call(
		"reveal_companion_cue",
		record_by_id(clockwood_map.get("companion_cues", []), "cold_ash_cache")
	)
	check(
		check_callback,
		bool(runtime.call("craft_inventory_recipe", "ember_salve_recipe")),
		"Journey must craft Ember Salve."
	)
	check(
		check_callback,
		InventoryModel.count(dict(runtime, "inventory"), "ember_salve") == 1,
		"Crafting must add Ember Salve."
	)

	runtime.set("current_era_id", "verdant")
	runtime.call("sync_runtime_entities", false)
	clockwood_map = dict(runtime, "map_data")
	runtime.call(
		"reveal_companion_cue",
		record_by_id(clockwood_map.get("companion_cues", []), "future_bark_trail")
	)
	collect(runtime, "clockwood_shard", check_callback)
	check(
		check_callback,
		bool(runtime.call("craft_inventory_recipe", "clockglass_lens_recipe")),
		"Journey must craft the Clockglass Lens."
	)
	check(
		check_callback,
		InventoryModel.count(dict(runtime, "inventory"), "clockglass_lens") == 1,
		"Crafting must add the Clockglass Lens."
	)

	# Capability gate and complete boss outcome.
	var stairs := record_by_id(bell_map.get("connections", []), "stairs_to_underworks")
	check(
		check_callback,
		bool(runtime.call("authored_requirements_met", stairs)),
		"Starting flashlight must satisfy Illuminate Darkness."
	)
	check(
		check_callback,
		bool(runtime.call("activate_map", "museum_underworks", "from_bellweather", "verdant", false)),
		"Journey must enter Museum Underworks."
	)
	runtime.set("player", Vector2(320, 224))
	runtime.set("companion", Vector2(294, 238))
	runtime.call("update_boss_engagements")
	check(
		check_callback,
		bool(dict(runtime, "engaged_bosses").get(BOSS_ID, false)),
		"Journey must engage the Underworks Sentinel."
	)
	if not str(runtime.get("active_cinematic_id")).is_empty():
		runtime.call("finish_cinematic", true)
	runtime.call("shift_to_next_era")
	check(
		check_callback,
		str(runtime.get("current_era_id")) == "ashen",
		"Boss route must preserve authored era shifting."
	)

	var boss_index := entity_index(array(runtime, "runtime_entities"), BOSS_ID)
	check(check_callback, boss_index >= 0, "Underworks Sentinel must resolve.")
	if boss_index >= 0:
		runtime.call("damage_entity", boss_index, 999, "ELI")
		check(
			check_callback,
			str(dict(runtime, "boss_phase_ids").get(BOSS_ID, "")) == "last_accession",
			"Large damage must stop at Last Accession."
		)
		runtime.call("damage_entity", boss_index, 999, "ELI")
	for reinforcement_id in REINFORCEMENTS:
		var reinforcement_index := entity_index(
			array(runtime, "runtime_entities"),
			reinforcement_id
		)
		check(
			check_callback,
			reinforcement_index >= 0,
			"Reinforcement '%s' must resolve." % reinforcement_id
		)
		if reinforcement_index >= 0:
			runtime.call("damage_entity", reinforcement_index, 999, "ELI")
	runtime.call("update_zone_clear_states")
	runtime.call("finalize_boss_outcomes")
	if not str(runtime.get("active_cinematic_id")).is_empty():
		runtime.call("finish_cinematic", false)

	var completed := dict(runtime, "session_state")
	check(
		check_callback,
		completed.get("underworks:boss:sentinel") == "defeated",
		"Journey must publish the durable boss outcome."
	)
	check(
		check_callback,
		completed.get("underworks:boss:archive_released") == true,
		"Journey must publish the boss reward state."
	)
	check(
		check_callback,
		bool(runtime.call("can_open_save_overlay")),
		"Saving must reopen after the boss conclusion."
	)
	var final_chits := EconomyModel.balance(
		dict(runtime, "currency_balances"),
		"archive_chits"
	)
	var final_shards := int(runtime.get("clock_shards"))
	check(
		check_callback,
		final_chits >= 57,
		"Journey must retain spending and boss currency rewards."
	)
	check(
		check_callback,
		final_shards >= 7,
		"Journey must retain world and boss shard rewards."
	)

	# Final checkpoint proves completion is exact and idempotent.
	var second: Dictionary = runtime.call(
		"capture_save_profile",
		"slot_2",
		"Canonical journey: Sentinel defeated"
	)
	check(
		check_callback,
		not str(second.get("checksum", "")).is_empty(),
		"Second checkpoint must be checksummed."
	)
	check(
		check_callback,
		str(second.get("checksum", "")) != str(first.get("checksum", "")),
		"Second checkpoint must represent later progress."
	)
	runtime.set("inventory", {})
	runtime.set("session_state", {})
	runtime.set("currency_balances", {"archive_chits": 0})
	runtime.set("clock_shards", 0)
	check(
		check_callback,
		bool(runtime.call("apply_save_profile", second, campaign_path)),
		"Second checkpoint must restore through the normal load path."
	)
	check(
		check_callback,
		InventoryModel.count(dict(runtime, "inventory"), "clockglass_lens") == 1,
		"Final restore must preserve the crafted key item."
	)
	check(
		check_callback,
		dict(runtime, "session_state").get("underworks:boss:sentinel") == "defeated",
		"Final restore must preserve boss completion."
	)
	check(
		check_callback,
		EconomyModel.balance(dict(runtime, "currency_balances"), "archive_chits") == final_chits,
		"Final restore must preserve the wallet exactly."
	)
	check(
		check_callback,
		int(runtime.get("clock_shards")) == final_shards,
		"Final restore must preserve shards exactly."
	)
	check(
		check_callback,
		not bool(dict(runtime, "engaged_bosses").get(BOSS_ID, false)),
		"A restored completed boss must not remain engaged."
	)

	return {
		"first_profile": first.duplicate(true),
		"completion_profile": second.duplicate(true),
		"final_chits": final_chits,
		"final_shards": final_shards,
		"completion_fingerprint": progression_fingerprint(runtime)
	}


static func progression_fingerprint(runtime: Object) -> String:
	return SaveProfile.canonical_json({
		"inventory": dict(runtime, "inventory"),
		"session_state": dict(runtime, "session_state"),
		"currency_balances": dict(runtime, "currency_balances"),
		"clock_shards": int(runtime.get("clock_shards"))
	})


static func collect(
	runtime: Object,
	placement_id: String,
	check_callback: Callable
) -> void:
	var index := entity_index(array(runtime, "runtime_entities"), placement_id)
	check(
		check_callback,
		index >= 0,
		"Pickup '%s' must resolve." % placement_id
	)
	if index >= 0:
		runtime.call("collect_pickup", index)


static func record_by_id(value: Variant, record_id: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {}
	for record_value in value as Array:
		if (
			typeof(record_value) == TYPE_DICTIONARY
			and str((record_value as Dictionary).get("id", "")) == record_id
		):
			return (record_value as Dictionary).duplicate(true)
	return {}


static func entity_index(entities: Array, placement_id: String) -> int:
	for index in range(entities.size()):
		if (
			typeof(entities[index]) == TYPE_DICTIONARY
			and str((entities[index] as Dictionary).get("placement_id", "")) == placement_id
		):
			return index
	return -1


static func dict(runtime: Object, property_name: String) -> Dictionary:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func array(runtime: Object, property_name: String) -> Array:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_ARRAY else []


static func check(
	check_callback: Callable,
	condition: bool,
	message: String
) -> void:
	if check_callback.is_valid():
		check_callback.call(condition, message)
