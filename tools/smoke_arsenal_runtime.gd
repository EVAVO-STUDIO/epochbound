extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")

const Repository = preload("res://src/content/campaign_repository.gd")
const ArsenalValidator = preload("res://src/content/arsenal_validator.gd")
const ArsenalCatalog = preload("res://src/content/arsenal_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const EncounterModel = preload("res://src/game/encounter_model.gd")
const SaveProfile = preload("res://src/content/save_profile.gd")
const SaveProfileStore = preload("res://src/content/save_profile_store.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const CAMPAIGN_ID := "epochbound_demo"
const SLOT_ID := "slot_2"
const RUNTIME_SCENE := "res://src/app.tscn"
const WEAPON_ID := "clockglass_dartcaster"
const AMMO_ID := "archive_bolts"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	var validation := ArsenalValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must pass Arsenal validation.")
	check(int(validation.get("ammunition_count", 0)) == 1, "Reference campaign must expose one ammunition type.")
	check(int(validation.get("ranged_weapon_count", 0)) == 1, "Reference campaign must expose one ranged weapon.")
	check(int(validation.get("ranged_enemy_count", 0)) == 1, "Reference campaign must expose one ranged enemy profile.")

	var scene_resource := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(scene_resource is PackedScene, "Arsenal-aware runtime scene must load.")
	if not scene_resource is PackedScene:
		finish()
		return
	var runtime := (scene_resource as PackedScene).instantiate()
	check(runtime != null, "Arsenal-aware runtime scene must instantiate.")
	if runtime == null:
		finish()
		return
	var script_value: Variant = runtime.get_script()
	check(script_value is GDScript, "Runtime root must retain its GDScript.")
	if script_value is GDScript:
		check(str((script_value as GDScript).resource_path) in ["res://src/boss_runtime.gd", "res://src/cinematic_runtime.gd", "res://src/presentation_runtime_current.gd"], "Runtime scene must bind the presentation-safe Boss runtime built on Arsenal.")
	root.add_child(runtime)
	check(runtime.has_method("start_reload"), "Runtime must expose explicit reload behaviour.")
	check(runtime.has_method("update_projectiles"), "Runtime must expose deterministic projectile updates.")
	check(runtime.has_method("capture_save_profile"), "Runtime must expose Arsenal-aware save capture.")
	if not runtime.has_method("start_reload"):
		await HeadlessRuntimeCleanup.release(self, runtime)
		finish()
		return

	var item_definitions := dictionary_property(runtime, "item_definitions")
	var weapon_data := ItemCatalog.item(item_definitions, WEAPON_ID)
	check(ArsenalCatalog.is_ranged_weapon(weapon_data), "Clockglass Dartcaster must resolve as ranged equipment.")
	check(ArsenalCatalog.weapon_ammunition_id(weapon_data) == AMMO_ID, "Dartcaster must consume Archive Bolts.")

	var inventory := dictionary_property(runtime, "inventory")
	InventoryModel.add_item(inventory, item_definitions, WEAPON_ID, 1)
	InventoryModel.add_item(inventory, item_definitions, AMMO_ID, 8)
	runtime.set("inventory", inventory)
	check(bool(runtime.call("equip_specific_item", WEAPON_ID)), "Owned Dartcaster must equip into the weapon slot.")
	check(str(dictionary_property(runtime, "equipped_items").get("weapon", "")) == WEAPON_ID, "Dartcaster must become the active weapon.")

	var reserve_before := InventoryModel.count(dictionary_property(runtime, "inventory"), AMMO_ID)
	check(bool(runtime.call("start_reload")), "An empty ranged weapon with reserve ammunition must start reloading.")
	check(InventoryModel.count(dictionary_property(runtime, "inventory"), AMMO_ID) == reserve_before, "Starting reload must not consume ammunition early.")
	runtime.call("update_reload", 0.25)
	check(InventoryModel.count(dictionary_property(runtime, "inventory"), AMMO_ID) == reserve_before, "Partial reload must preserve reserve ammunition.")
	runtime.call("update_reload", 2.0)
	var loaded := dictionary_property(runtime, "loaded_ammo")
	check(int(loaded.get(WEAPON_ID, 0)) == 4, "Completed reload must fill the authored four-round magazine.")
	check(InventoryModel.count(dictionary_property(runtime, "inventory"), AMMO_ID) == 4, "Completed reload must remove exactly four reserve rounds.")

	check(bool(runtime.call("activate_map", "bellweather_crossing", "", "ashen", false)), "Ashen Bellweather must activate for ranged testing.")
	runtime.set("player", Vector2(380, 216))
	runtime.set("facing", Vector2.RIGHT)
	runtime.call("sync_runtime_entities", false)
	var entities := array_property(runtime, "runtime_entities")
	var hound_index := enemy_index(entities, "crossing_hound")
	check(hound_index >= 0, "Ashen Bellweather must expose crossing_hound.")
	if hound_index >= 0:
		var health_before := int((entities[hound_index] as Dictionary).get("health", 0))
		runtime.call("perform_player_attack")
		entities = array_property(runtime, "runtime_entities")
		check(int((entities[hound_index] as Dictionary).get("health", 0)) == health_before, "Firing must not apply instant hitscan damage.")
		check(array_property(runtime, "projectiles").size() == 1, "Firing must create one projectile.")
		runtime.call("update_projectiles", 0.25)
		entities = array_property(runtime, "runtime_entities")
		check(int((entities[hound_index] as Dictionary).get("health", 0)) < health_before, "Projectile arrival must damage the authored enemy.")
		check(int(dictionary_property(runtime, "loaded_ammo").get(WEAPON_ID, 0)) == 3, "Firing must consume one loaded round.")

	runtime.set("loaded_ammo", {WEAPON_ID: 0})
	var before_cancel := InventoryModel.count(dictionary_property(runtime, "inventory"), AMMO_ID)
	check(bool(runtime.call("start_reload")), "Reload must restart after the magazine is emptied.")
	check(bool(runtime.call("equip_specific_item", "brass_hook")), "Brass Hook must remain an available melee weapon.")
	check(float(runtime.get("reload_timer")) == 0.0, "Changing weapons must cancel reload.")
	check(InventoryModel.count(dictionary_property(runtime, "inventory"), AMMO_ID) == before_cancel, "Cancelled reload must preserve every reserve round.")
	check(bool(runtime.call("equip_specific_item", WEAPON_ID)), "Dartcaster must re-equip after cancellation.")

	var object_definitions := dictionary_property(runtime, "object_definitions")
	var sentinel: Dictionary = object_definitions.get("underworks_sentinel", {})
	check(ArsenalCatalog.is_ranged_enemy(sentinel), "Underworks Sentinel must resolve as a ranged enemy.")
	runtime.set("player", Vector2(300, 224))
	runtime.set("player_health", 30)
	var attacker := sentinel.duplicate(true)
	attacker["_position"] = Vector2(250, 224)
	runtime.call("damage_actor", "player", int(sentinel.get("attack_damage", 3)), attacker)
	check(int(runtime.get("player_health")) == 30, "Enemy ranged attack must not deal instant damage.")
	check(array_property(runtime, "projectiles").size() >= 1, "Enemy ranged attack must create a projectile.")
	runtime.call("update_projectiles", 0.4)
	check(int(runtime.get("player_health")) < 30, "Enemy projectile arrival must damage the player through active defence.")

	inventory = dictionary_property(runtime, "inventory")
	if InventoryModel.count(inventory, WEAPON_ID) <= 0:
		InventoryModel.add_item(inventory, item_definitions, WEAPON_ID, 1)
	if InventoryModel.count(inventory, AMMO_ID) <= 0:
		InventoryModel.add_item(inventory, item_definitions, AMMO_ID, 6)
	runtime.set("inventory", inventory)
	runtime.call("equip_specific_item", WEAPON_ID)
	runtime.set("loaded_ammo", {WEAPON_ID: 2})
	check(bool(runtime.call("equip_specific_item", "brass_hook")), "Loaded Dartcaster must be unequippable without losing its magazine.")
	var protected_ids: PackedStringArray = runtime.call("protected_equipment_ids")
	check(protected_ids.has(WEAPON_ID), "An unequipped ranged weapon with loaded rounds must remain protected from sale.")
	check(bool(runtime.call("equip_specific_item", WEAPON_ID)), "Dartcaster must re-equip after loaded-sale protection testing.")
	var captured_value: Variant = runtime.call("capture_save_profile", SLOT_ID, "Arsenal smoke checkpoint")
	check(typeof(captured_value) == TYPE_DICTIONARY, "Arsenal profile capture must return an object.")
	var captured: Dictionary = captured_value if typeof(captured_value) == TYPE_DICTIONARY else {}
	check(int(captured.get("schema_version", 0)) == SaveProfile.CURRENT_SCHEMA, "Arsenal profile must use the current save schema.")
	check(int(((captured.get("payload", {}) as Dictionary).get("loaded_ammo", {}) as Dictionary).get(WEAPON_ID, 0)) == 2, "Profile must capture exact loaded rounds.")
	check(SaveProfile.checksum_valid(captured), "Arsenal profile checksum must be valid.")
	var profile_validation := ArsenalValidator.validate_profile(captured, CAMPAIGN_PATH)
	check(bool(profile_validation.get("ok", false)), "Captured Arsenal profile must pass campaign-bound validation.")
	check(bool(SaveProfileStore.write_profile(captured).get("ok", false)), "Arsenal profile must write atomically.")
	runtime.set("loaded_ammo", {})
	check(bool(runtime.call("load_profile_from_slot", CAMPAIGN_ID, SLOT_ID)), "Normal slot API must restore the Arsenal profile.")
	check(int(dictionary_property(runtime, "loaded_ammo").get(WEAPON_ID, 0)) == 2, "Loaded magazine must restore exactly.")

	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	await HeadlessRuntimeCleanup.release(self, runtime)
	finish()


func dictionary_property(object: Object, property_name: String) -> Dictionary:
	var value: Variant = object.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_property(object: Object, property_name: String) -> Array:
	var value: Variant = object.get(property_name)
	return value if typeof(value) == TYPE_ARRAY else []


func enemy_index(entities: Array, placement_id: String) -> int:
	for index in range(entities.size()):
		if typeof(entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entities[index]
		if str(entity.get("placement_id", "")) == placement_id and EncounterModel.kind(entity) == "enemy":
			return index
	return -1


func finish() -> void:
	if failures.is_empty():
		print("Arsenal runtime smoke test passed: reload timing, projectiles, enemy ranged attacks, cancellation and durable magazines are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
