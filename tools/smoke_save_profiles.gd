extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const SaveProfile = preload("res://src/content/save_profile.gd")
const SaveProfileStore = preload("res://src/content/save_profile_store.gd")
const SaveValidator = preload("res://src/content/save_validator.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const StoryModel = preload("res://src/game/story_model.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const CAMPAIGN_ID := "epochbound_demo"
const SLOT_ID := "slot_3"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	var campaign_result: Dictionary = Repository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load for save testing.")
	var campaign: Dictionary = campaign_result.get("data", {})
	check(int(SaveProfile.policy(campaign).get("manual_slots", 0)) == 3, "Reference campaign must expose three manual save slots.")

	var scene_resource := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(scene_resource is PackedScene, "Save-aware runtime scene must load.")
	if not scene_resource is PackedScene:
		finish()
		return
	var runtime := (scene_resource as PackedScene).instantiate()
	check(runtime != null, "Save-aware runtime scene must instantiate.")
	if runtime == null:
		finish()
		return
	var script_value: Variant = runtime.get_script()
	check(script_value is GDScript, "Runtime root must retain its GDScript.")
	if script_value is GDScript:
		check(str((script_value as GDScript).resource_path) == "res://src/equipment_runtime.gd", "Runtime scene must bind the equipment-aware save runtime.")
	root.add_child(runtime)
	check(runtime.has_method("capture_save_profile"), "Runtime must expose deterministic profile capture.")
	check(runtime.has_method("load_profile_from_slot"), "Runtime must expose slot restoration.")
	check(runtime.has_method("activate_save_slot"), "Runtime must expose guarded slot activation.")
	if not runtime.has_method("capture_save_profile"):
		root.remove_child(runtime)
		runtime.free()
		finish()
		return

	var activated: Variant = runtime.call("activate_map", "clockwood_edge", "", "ashen", false)
	check(bool(activated), "Clockwood Edge must activate before profile capture.")
	runtime.set("player", Vector2(80, 232))
	runtime.set("companion", Vector2(112, 248))
	runtime.set("facing", Vector2.RIGHT)
	runtime.set("player_health", 23)
	runtime.set("companion_health", 17)
	runtime.set("clock_shards", 7)
	runtime.set("companion_command", "stay")
	runtime.set("companion_hold_position", Vector2(112, 248))
	runtime.set("play_time_seconds", 3723.5)

	var inventory_value: Variant = runtime.get("inventory")
	var inventory: Dictionary = inventory_value if typeof(inventory_value) == TYPE_DICTIONARY else {}
	inventory["brass_filings"] = 4
	inventory["clockglass_fragment"] = 2
	runtime.set("inventory", inventory)
	var unlock_value: Variant = runtime.get("unlocked_recipes")
	var unlocks: Dictionary = unlock_value if typeof(unlock_value) == TYPE_DICTIONARY else {}
	unlocks["clockglass_lens_recipe"] = true
	runtime.set("unlocked_recipes", unlocks)
	var state_value: Variant = runtime.get("session_state")
	var state: Dictionary = state_value if typeof(state_value) == TYPE_DICTIONARY else {}
	state["clockwood:clock_shard"] = "collected"
	state["test:durable_state"] = "restored"
	runtime.set("session_state", state)
	var quest_value: Variant = runtime.get("quest_progress")
	var quests: Dictionary = quest_value if typeof(quest_value) == TYPE_DICTIONARY else {}
	quests["the_missing_hour"] = {"status": StoryModel.STATUS_ACTIVE, "stage_id": "forge_the_lens"}
	runtime.set("quest_progress", quests)

	var captured_value: Variant = runtime.call("capture_save_profile", SLOT_ID, "Smoke-test checkpoint")
	check(typeof(captured_value) == TYPE_DICTIONARY, "Profile capture must return a dictionary.")
	var captured: Dictionary = captured_value if typeof(captured_value) == TYPE_DICTIONARY else {}
	check(SaveProfile.checksum_valid(captured), "Captured profile checksum must be valid.")
	var profile_validation: Dictionary = SaveValidator.validate_profile(captured, CAMPAIGN_PATH)
	check(bool(profile_validation.get("ok", false)), "Captured profile must pass campaign-bound validation.")
	var write_result: Dictionary = SaveProfileStore.write_profile(captured)
	check(bool(write_result.get("ok", false)), "Captured profile must write atomically.")
	check(FileAccess.file_exists(SaveProfileStore.slot_path(CAMPAIGN_ID, SLOT_ID)), "Save slot file must exist after writing.")

	# Occupied manual slots require a second confirmation and empty load slots fail clearly.
	runtime.call("refresh_save_slot_cache")
	runtime.set("save_overlay_mode", 0)
	var original_read: Dictionary = SaveProfileStore.read_profile(CAMPAIGN_ID, SLOT_ID)
	var original_profile: Dictionary = original_read.get("profile", {})
	var original_checksum := str(original_profile.get("checksum", ""))
	var first_confirm: Variant = runtime.call("activate_save_slot", SLOT_ID)
	check(not bool(first_confirm), "The first confirmation must not overwrite an occupied manual slot.")
	check(str(runtime.get("pending_overwrite_slot")) == SLOT_ID, "The occupied slot must become the explicit pending overwrite target.")
	var unchanged_read: Dictionary = SaveProfileStore.read_profile(CAMPAIGN_ID, SLOT_ID)
	check(str((unchanged_read.get("profile", {}) as Dictionary).get("checksum", "")) == original_checksum, "First confirmation must leave the stored profile unchanged.")
	var second_confirm: Variant = runtime.call("activate_save_slot", SLOT_ID)
	check(bool(second_confirm), "A second confirmation within the window must overwrite the occupied slot.")
	check(str(runtime.get("pending_overwrite_slot")) == "", "Successful overwrite must clear pending confirmation state.")
	var overwritten_read: Dictionary = SaveProfileStore.read_profile(CAMPAIGN_ID, SLOT_ID)
	var overwritten_metadata: Dictionary = (overwritten_read.get("profile", {}) as Dictionary).get("metadata", {})
	check(str(overwritten_metadata.get("reason", "")) == "Manual save", "Confirmed overwrite must publish a manual-save reason.")
	runtime.set("save_overlay_mode", 1)
	var empty_load: Variant = runtime.call("activate_save_slot", "slot_1")
	check(not bool(empty_load), "Loading an empty slot must fail without mutating runtime state.")
	check("EMPTY" in str(runtime.get("save_notice")), "Empty-slot load feedback must be explicit.")

	# Destroy the live state before loading so restoration proves every durable field.
	runtime.set("player", Vector2(320, 224))
	runtime.set("companion", Vector2(280, 232))
	runtime.set("player_health", 32)
	runtime.set("companion_health", 24)
	runtime.set("clock_shards", 0)
	runtime.set("inventory", {})
	runtime.set("unlocked_recipes", {})
	runtime.set("session_state", {})
	runtime.set("quest_progress", {})
	runtime.set("companion_command", "follow")
	runtime.set("play_time_seconds", 0.0)

	var loaded_value: Variant = runtime.call("load_profile_from_slot", CAMPAIGN_ID, SLOT_ID)
	check(bool(loaded_value), "Written profile must load through the runtime slot API.")
	check(str((runtime.get("map_data") as Dictionary).get("id", "")) == "clockwood_edge", "Load must restore the saved map.")
	check(str(runtime.get("current_era_id")) == "ashen", "Load must restore the saved era.")
	var restored_player: Variant = runtime.get("player")
	var restored_companion: Variant = runtime.get("companion")
	check(restored_player is Vector2 and (restored_player as Vector2).is_equal_approx(Vector2(80, 232)), "Load must restore the player position.")
	check(restored_companion is Vector2 and (restored_companion as Vector2).is_equal_approx(Vector2(112, 248)), "Load must restore the companion position.")
	check(int(runtime.get("player_health")) == 23, "Load must restore player health.")
	check(int(runtime.get("companion_health")) == 17, "Load must restore companion health.")
	check(int(runtime.get("clock_shards")) == 7, "Load must restore clock shards.")
	var restored_inventory_value: Variant = runtime.get("inventory")
	var restored_inventory: Dictionary = restored_inventory_value if typeof(restored_inventory_value) == TYPE_DICTIONARY else {}
	check(InventoryModel.count(restored_inventory, "brass_filings") == 4, "Load must restore material quantities.")
	check(InventoryModel.count(restored_inventory, "clockglass_fragment") == 2, "Load must restore key crafting materials.")
	var restored_unlock_value: Variant = runtime.get("unlocked_recipes")
	var restored_unlocks: Dictionary = restored_unlock_value if typeof(restored_unlock_value) == TYPE_DICTIONARY else {}
	check(bool(restored_unlocks.get("clockglass_lens_recipe", false)), "Load must restore learned recipes.")
	var restored_state_value: Variant = runtime.get("session_state")
	var restored_state: Dictionary = restored_state_value if typeof(restored_state_value) == TYPE_DICTIONARY else {}
	check(restored_state.get("test:durable_state") == "restored", "Load must restore durable world state.")
	check(restored_state.get("clockwood:clock_shard") == "collected", "Load must preserve collected pickup state.")
	var restored_quest_value: Variant = runtime.get("quest_progress")
	var restored_quests: Dictionary = restored_quest_value if typeof(restored_quest_value) == TYPE_DICTIONARY else {}
	check(StoryModel.quest_status(restored_quests, "the_missing_hour") == StoryModel.STATUS_ACTIVE, "Load must restore active quest status.")
	check(StoryModel.quest_stage_id(restored_quests, "the_missing_hour") == "forge_the_lens", "Load must restore the exact quest stage.")
	check(str(runtime.get("companion_command")) == "stay", "Load must restore a safe persistent companion command.")
	check(is_equal_approx(float(runtime.get("play_time_seconds")), 3723.5), "Load must restore accumulated play time.")
	check(str(runtime.get("current_save_slot")) == SLOT_ID, "Runtime must remember the active manual slot.")

	root.remove_child(runtime)
	runtime.free()
	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	finish()


func finish() -> void:
	if failures.is_empty():
		print("Save profile smoke test passed: capture, guarded overwrite, empty-slot feedback, atomic write and exact restoration are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
