extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const EquipmentValidator = preload("res://src/content/equipment_validator.gd")
const EquipmentModel = preload("res://src/game/equipment_model.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const StoryModel = preload("res://src/game/story_model.gd")
const SaveProfile = preload("res://src/content/save_profile.gd")
const SaveProfileStore = preload("res://src/content/save_profile_store.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const CAMPAIGN_ID := "epochbound_demo"
const SLOT_ID := "slot_3"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	var validation: Dictionary = EquipmentValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must pass equipment and capability validation.")
	check(int(validation.get("equipment_item_count", 0)) == 6, "Reference campaign must expose six equipment items.")
	check(int(validation.get("equipment_slot_count", 0)) == 3, "Reference campaign must expose three equipment slots.")
	check(int(validation.get("capability_count", 0)) == 3, "Reference campaign must expose three capability definitions.")
	check(int(validation.get("capability_gate_count", 0)) == 3, "Reference campaign must expose three authored capability gates.")

	var campaign_result: Dictionary = Repository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load for loadout testing.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var capability_result: Dictionary = EquipmentCatalog.load_capability_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(capability_result.get("ok", false)), "Reference capability catalog must load.")
	var capability_definitions: Dictionary = capability_result.get("definitions", {})
	check(EquipmentCatalog.capability_name(capability_definitions, "clockglass_sight") == "Clockglass Sight", "Capability display names must resolve deterministically.")

	var scene_resource := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(scene_resource is PackedScene, "Equipment-aware runtime scene must load.")
	if not scene_resource is PackedScene:
		finish()
		return
	var runtime := (scene_resource as PackedScene).instantiate()
	check(runtime != null, "Equipment-aware runtime scene must instantiate.")
	if runtime == null:
		finish()
		return
	var script_value: Variant = runtime.get_script()
	check(script_value is GDScript, "Runtime root must retain its GDScript.")
	if script_value is GDScript:
		check(str((script_value as GDScript).resource_path) in ["res://src/boss_runtime.gd", "res://src/cinematic_runtime.gd"], "Runtime scene must bind the Boss-aware runtime.")
	root.add_child(runtime)

	check(runtime.has_method("active_capabilities"), "Runtime must expose derived capabilities.")
	check(runtime.has_method("cycle_equipment_slot"), "Runtime must expose deterministic slot cycling.")
	check(runtime.has_method("capture_save_profile"), "Runtime must expose equipment-aware profile capture.")
	if not runtime.has_method("active_capabilities"):
		root.remove_child(runtime)
		runtime.free()
		finish()
		return

	var equipment := runtime_dictionary(runtime, "equipped_items")
	check(str(equipment.get("weapon", "")) == "brass_hook", "Brass Hook must start equipped as the weapon.")
	check(str(equipment.get("body", "")) == "museum_coat", "Museum Field Coat must start equipped as body gear.")
	check(str(equipment.get("tool", "")) == "museum_flashlight", "Museum Flashlight must start equipped as the tool.")
	check(int(runtime.call("player_attack_damage_value")) == 6, "Starting weapon must raise player attack damage from four to six.")
	check(int(runtime.call("player_defense_value")) == 1, "Starting coat must provide one point of defence.")
	check(int(runtime.call("actor_health", "player", 32)) == 36, "Starting coat must raise maximum player health to thirty-six.")
	check(is_equal_approx(float(runtime.call("player_move_speed_value")), 105.0), "Starting loadout must preserve the baseline movement speed.")
	var capabilities := runtime.call("active_capabilities") as PackedStringArray
	check(capabilities.has("illuminate_dark"), "Starting flashlight must grant Illuminate Darkness.")
	check(capabilities.has("cut_clockvines"), "Starting hook must grant Cut Clockvines.")
	check(not capabilities.has("clockglass_sight"), "Clockglass Sight must remain unavailable before the Archivist Lens is equipped.")
	check(StoryModel.condition_met({"type": "has_capability", "capability_id": "cut_clockvines"}, runtime.call("story_context")), "Story conditions must consume the same active capability set.")

	var bell_map := runtime_dictionary(runtime, "map_data")
	var stairs := find_record(bell_map.get("connections", []), "stairs_to_underworks")
	check(not stairs.is_empty(), "Bellweather must expose the Underworks connection.")
	check(bool(runtime.call("authored_requirements_met", stairs)), "The equipped flashlight must satisfy the Underworks travel gate.")

	check(bool(runtime.call("cycle_equipment_slot", "tool")), "Cycling the Tool slot must unequip the only starting tool.")
	capabilities = runtime.call("active_capabilities") as PackedStringArray
	check(not capabilities.has("illuminate_dark"), "Unequipping the flashlight must remove its capability immediately.")
	runtime.set("transition_lock", 0.0)
	check(not bool(runtime.call("travel_through", stairs)), "Underworks travel must fail without Illuminate Darkness.")
	check("light" in str(runtime.get("dialogue")).to_lower() or "dark" in str(runtime.get("dialogue")).to_lower(), "A blocked capability gate must explain the missing light requirement.")
	runtime.set("dialogue", "")
	check(bool(runtime.call("cycle_equipment_slot", "tool")), "Cycling the empty Tool slot must re-equip the owned flashlight.")
	runtime.set("transition_lock", 0.0)
	check(bool(runtime.call("travel_through", stairs)), "Underworks travel must succeed after re-equipping the flashlight.")
	check(str(runtime_dictionary(runtime, "map_data").get("id", "")) == "museum_underworks", "Successful gated travel must activate Museum Underworks.")

	var underworks := runtime_dictionary(runtime, "map_data")
	var clockvines := find_record(underworks.get("interactions", []), "clockvine_bulkhead")
	var catalogue := find_record(underworks.get("interactions", []), "sealed_catalogue")
	check(bool(runtime.call("authored_requirements_met", clockvines)), "The equipped hook must satisfy the Clockvine Bulkhead interaction.")
	check(not bool(runtime.call("authored_requirements_met", catalogue)), "The sealed catalogue must remain blocked without Clockglass Sight.")

	var inventory := runtime_dictionary(runtime, "inventory")
	var items := runtime_dictionary(runtime, "item_definitions")
	var add_result: Dictionary = InventoryModel.add_item(inventory, items, "archivist_lens", 1)
	check(int(add_result.get("added", 0)) == 1, "Test must grant the Archivist Lens into normal inventory ownership.")
	runtime.set("inventory", inventory)
	check(bool(runtime.call("equip_specific_item", "archivist_lens")), "Owned Archivist Lens must equip into the Tool slot.")
	equipment = runtime_dictionary(runtime, "equipped_items")
	check(str(equipment.get("tool", "")) == "archivist_lens", "Archivist Lens must replace the flashlight in the shared Tool slot.")
	capabilities = runtime.call("active_capabilities") as PackedStringArray
	check(capabilities.has("clockglass_sight"), "Equipped Archivist Lens must grant Clockglass Sight.")
	check(not capabilities.has("illuminate_dark"), "Replacing the flashlight must remove Illuminate Darkness.")
	check(bool(runtime.call("authored_requirements_met", catalogue)), "Clockglass Sight must unlock the sealed catalogue interaction.")
	check(is_equal_approx(float(runtime.call("player_move_speed_value")), 113.0), "Archivist Lens must apply its authored movement bonus.")

	var profile_value: Variant = runtime.call("capture_save_profile", SLOT_ID, "Loadout smoke checkpoint")
	check(typeof(profile_value) == TYPE_DICTIONARY, "Equipment-aware profile capture must return a dictionary.")
	var profile: Dictionary = profile_value if typeof(profile_value) == TYPE_DICTIONARY else {}
	check(int(profile.get("schema_version", 0)) == SaveProfile.CURRENT_SCHEMA, "Captured profile must use the current save schema.")
	check(SaveProfile.checksum_valid(profile), "Captured equipment profile must have a valid checksum.")
	var payload: Dictionary = profile.get("payload", {})
	check(str((payload.get("equipment", {}) as Dictionary).get("tool", "")) == "archivist_lens", "Captured profile must store the exact equipped tool.")
	var profile_validation: Dictionary = EquipmentValidator.validate_profile(profile, CAMPAIGN_PATH)
	check(bool(profile_validation.get("ok", false)), "Captured equipment profile must pass campaign-bound validation.")
	var write_result: Dictionary = SaveProfileStore.write_profile(profile)
	check(bool(write_result.get("ok", false)), "Equipment profile must write atomically.")

	check(bool(runtime.call("equip_specific_item", "museum_flashlight")), "Runtime must be able to alter the live tool before restoration.")
	check(str(runtime_dictionary(runtime, "equipped_items").get("tool", "")) == "museum_flashlight", "Live loadout mutation must take effect before loading.")
	check(bool(runtime.call("load_profile_from_slot", CAMPAIGN_ID, SLOT_ID)), "Equipment profile must restore through the normal slot API.")
	equipment = runtime_dictionary(runtime, "equipped_items")
	check(str(equipment.get("tool", "")) == "archivist_lens", "Loading must restore the exact equipped tool.")
	check(int(runtime.call("actor_health", "player", 32)) == 36, "Loading must rebuild maximum health from restored body equipment.")
	check((runtime.call("active_capabilities") as PackedStringArray).has("clockglass_sight"), "Loading must rebuild active capabilities from restored gear.")

	root.remove_child(runtime)
	runtime.free()
	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	finish()


func find_record(value: Variant, record_id: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {}
	for record_value in value:
		if typeof(record_value) == TYPE_DICTIONARY and str((record_value as Dictionary).get("id", "")) == record_id:
			return record_value
	return {}


func runtime_dictionary(runtime: Object, property_name: String) -> Dictionary:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func finish() -> void:
	if failures.is_empty():
		print("Loadout runtime smoke test passed: stats, slots, gates, story conditions, schema capture and exact restoration are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
