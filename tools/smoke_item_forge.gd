extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const ItemValidator = preload("res://src/content/item_validator.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var validation := ItemValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(validation.get("ok", false), "Reference campaign must pass item and recipe validation.")
	check(int(validation.get("item_count", 0)) == 13, "Reference campaign must expose thirteen inventory, equipment and ammunition item definitions.")
	check(int(validation.get("recipe_count", 0)) == 2, "Reference campaign must expose two recipe definitions.")

	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(campaign_result.get("ok", false), "Reference campaign must load.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var item_result := ItemCatalog.load_item_catalogs(CAMPAIGN_PATH, campaign)
	var recipe_result := ItemCatalog.load_recipe_catalogs(CAMPAIGN_PATH, campaign)
	check(item_result.get("ok", false), "Reference item catalog must load.")
	check(recipe_result.get("ok", false), "Reference recipe catalog must load.")
	var items: Dictionary = item_result.get("definitions", {})
	var recipes: Dictionary = recipe_result.get("definitions", {})
	var inventory := InventoryModel.initial_inventory(campaign, items)
	var unlocked := InventoryModel.initial_recipe_unlocks(campaign, recipes)
	check(InventoryModel.count(inventory, "museum_tonic") == 1, "Starting inventory must include one Museum Tonic.")
	check(InventoryModel.count(inventory, "brass_filings") == 1, "Starting inventory must include one Brass Filings stack.")
	check(InventoryModel.count(inventory, "brass_hook") == 1, "Starting inventory must own the Brass Hook.")
	check(InventoryModel.count(inventory, "museum_coat") == 1, "Starting inventory must own the Museum Field Coat.")
	check(InventoryModel.count(inventory, "museum_flashlight") == 1, "Starting inventory must own the Museum Flashlight.")
	check(bool(unlocked.get("ember_salve_recipe", false)), "Ember Salve recipe must be known at campaign start.")
	check(not bool(unlocked.get("clockglass_lens_recipe", false)), "Clockglass Lens recipe must begin locked.")

	var overflow_inventory: Dictionary = {}
	var overflow_result := InventoryModel.add_item(overflow_inventory, items, "museum_tonic", 12)
	check(int(overflow_result.get("added", 0)) == 9, "Inventory addition must respect the authored stack limit.")
	check(int(overflow_result.get("overflow", 0)) == 3, "Inventory addition must report overflow deterministically.")

	var model_inventory: Dictionary = {
		"brass_filings": 2,
		"ashen_resin": 1
	}
	var salve_recipe := ItemCatalog.recipe(recipes, "ember_salve_recipe")
	check(InventoryModel.can_craft(salve_recipe, model_inventory, items), "Model inventory must be able to craft Ember Salve.")
	var craft_result := InventoryModel.craft(salve_recipe, model_inventory, items)
	check(craft_result.get("ok", false), "Model crafting must complete.")
	check(InventoryModel.count(model_inventory, "ember_salve") == 1, "Crafting must add the recipe output.")
	check(InventoryModel.count(model_inventory, "brass_filings") == 0, "Crafting must consume brass ingredients.")
	check(InventoryModel.count(model_inventory, "ashen_resin") == 0, "Crafting must consume resin ingredients.")

	probe_runtime_scene()
	finish()


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
		check(
			str((script_value as GDScript).resource_path) in ["res://src/inventory_runtime.gd", "res://src/story_runtime.gd", "res://src/save_runtime.gd", "res://src/equipment_runtime.gd", "res://src/merchant_runtime.gd", "res://src/arsenal_runtime.gd"],
			"Runtime scene must bind an inventory-capable runtime."
		)
	root.add_child(runtime)
	check(runtime.has_method("use_inventory_item"), "Runtime must expose item use.")
	check(runtime.has_method("craft_inventory_recipe"), "Runtime must expose crafting.")
	check(runtime.has_method("open_inventory"), "Runtime must expose the inventory overlay.")
	if not runtime.has_method("craft_inventory_recipe"):
		root.remove_child(runtime)
		runtime.free()
		return

	var inventory := runtime_inventory(runtime)
	var unlocks := runtime_unlocks(runtime)
	check(InventoryModel.count(inventory, "museum_tonic") == 1, "Runtime must initialise the Museum Tonic.")
	check(InventoryModel.count(inventory, "brass_filings") == 1, "Runtime must initialise Brass Filings.")
	check(InventoryModel.count(inventory, "brass_hook") == 1, "Runtime must initialise owned weapon equipment.")
	check(InventoryModel.count(inventory, "museum_coat") == 1, "Runtime must initialise owned body equipment.")
	check(InventoryModel.count(inventory, "museum_flashlight") == 1, "Runtime must initialise owned tool equipment.")
	check(bool(unlocks.get("ember_salve_recipe", false)), "Runtime must initialise starting recipe unlocks.")

	runtime.set("player_health", 12)
	var used: Variant = runtime.call("use_inventory_item", "museum_tonic", false)
	check(bool(used), "Museum Tonic must be usable.")
	check(int(runtime.get("player_health")) == 22, "Museum Tonic must restore ten health.")
	inventory = runtime_inventory(runtime)
	check(InventoryModel.count(inventory, "museum_tonic") == 0, "Using a consumable must remove one item.")

	runtime.call("open_inventory")
	check(bool(runtime.get("inventory_open")), "Inventory overlay must open.")
	runtime.call("close_inventory")
	check(not bool(runtime.get("inventory_open")), "Inventory overlay must close.")

	# Bellweather companion discovery grants brass once.
	var bell_map: Dictionary = runtime.get("map_data")
	var well_cue := find_cue(bell_map, "well_name_scent")
	check(not well_cue.is_empty(), "Bellweather well cue must exist.")
	runtime.call("reveal_companion_cue", well_cue)
	inventory = runtime_inventory(runtime)
	check(InventoryModel.count(inventory, "brass_filings") == 3, "Well discovery must grant two Brass Filings.")
	runtime.call("reveal_companion_cue", well_cue)
	inventory = runtime_inventory(runtime)
	check(InventoryModel.count(inventory, "brass_filings") == 3, "Discovered cue must not duplicate item rewards.")

	# Bellweather clock shard grants one clockglass fragment once.
	var crossing_pickup := entity_index(runtime_entities(runtime), "crossing_shard")
	check(crossing_pickup >= 0, "Bellweather clock shard must instantiate.")
	if crossing_pickup >= 0:
		runtime.call("collect_pickup", crossing_pickup)
		inventory = runtime_inventory(runtime)
		check(InventoryModel.count(inventory, "clockglass_fragment") == 1, "Clock shard pickup must grant one clockglass fragment.")
		runtime.call("collect_pickup", crossing_pickup)
		inventory = runtime_inventory(runtime)
		check(InventoryModel.count(inventory, "clockglass_fragment") == 1, "Collected pickup must not duplicate its item grant.")

	# Clockwood discoveries supply resin and teach the lens recipe.
	var activated: Variant = runtime.call("activate_map", "clockwood_edge", "from_bellweather", "ashen", false)
	check(bool(activated), "Runtime must travel to Clockwood Edge.")
	var clockwood_map: Dictionary = runtime.get("map_data")
	var ash_cue := find_cue(clockwood_map, "cold_ash_cache")
	check(not ash_cue.is_empty(), "Clockwood Ashen cache cue must exist.")
	runtime.call("reveal_companion_cue", ash_cue)
	inventory = runtime_inventory(runtime)
	check(InventoryModel.count(inventory, "ashen_resin") == 1, "Ashen cache must grant one Ashen Resin.")

	var crafted_salve: Variant = runtime.call("craft_inventory_recipe", "ember_salve_recipe")
	check(bool(crafted_salve), "Collected materials must craft Ember Salve.")
	inventory = runtime_inventory(runtime)
	check(InventoryModel.count(inventory, "ember_salve") == 1, "Runtime crafting must add Ember Salve.")
	check(InventoryModel.count(inventory, "brass_filings") == 1, "Ember Salve crafting must leave one Brass Filings stack.")

	runtime.set("current_era_id", "verdant")
	runtime.call("sync_runtime_entities", false)
	clockwood_map = runtime.get("map_data")
	var trail_cue := find_cue(clockwood_map, "future_bark_trail")
	check(not trail_cue.is_empty(), "Clockwood future-bark trail must exist.")
	runtime.call("reveal_companion_cue", trail_cue)
	unlocks = runtime_unlocks(runtime)
	check(bool(unlocks.get("clockglass_lens_recipe", false)), "Future-bark trail must unlock the Clockglass Lens recipe.")

	var clockwood_pickup := entity_index(runtime_entities(runtime), "clockwood_shard")
	check(clockwood_pickup >= 0, "Clockwood clock shard must instantiate.")
	if clockwood_pickup >= 0:
		runtime.call("collect_pickup", clockwood_pickup)
	inventory = runtime_inventory(runtime)
	check(InventoryModel.count(inventory, "clockglass_fragment") == 2, "Two world pickups must provide two clockglass fragments.")

	var crafted_lens: Variant = runtime.call("craft_inventory_recipe", "clockglass_lens_recipe")
	check(bool(crafted_lens), "Unlocked Clockglass Lens recipe must craft after both fragments are recovered.")
	inventory = runtime_inventory(runtime)
	check(InventoryModel.count(inventory, "clockglass_lens") == 1, "Crafting must create the Clockglass Lens key item.")
	check(InventoryModel.count(inventory, "clockglass_fragment") == 0, "Lens crafting must consume both fragments.")
	check(InventoryModel.count(inventory, "brass_filings") == 0, "Lens crafting must consume the remaining brass.")

	root.remove_child(runtime)
	runtime.free()


func runtime_inventory(runtime: Object) -> Dictionary:
	var value: Variant = runtime.get("inventory")
	return value if typeof(value) == TYPE_DICTIONARY else {}


func runtime_unlocks(runtime: Object) -> Dictionary:
	var value: Variant = runtime.get("unlocked_recipes")
	return value if typeof(value) == TYPE_DICTIONARY else {}


func runtime_entities(runtime: Object) -> Array:
	var value: Variant = runtime.get("runtime_entities")
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
		if typeof(cue_value) == TYPE_DICTIONARY:
			var cue: Dictionary = cue_value
			if str(cue.get("id", "")) == cue_id:
				return cue
	return {}


func finish() -> void:
	if failures.is_empty():
		print("Item Forge smoke test passed: inventory ownership, equipment items, stacks, rewards, unlocks, crafting, healing and duplicate protection are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
