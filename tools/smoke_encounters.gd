extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/epochbound_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EncounterModel = preload("res://src/game/encounter_model.gd")
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"
const COMBAT_RUNTIME_PATHS := [
	"res://src/combat_runtime.gd",
	"res://src/combat_director_runtime.gd",
	"res://src/companion_runtime.gd",
	"res://src/inventory_runtime.gd",
	"res://src/story_runtime.gd"
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var validation := Validator.validate_campaign_path(CAMPAIGN_PATH)
	check(validation.get("ok", false), "Reference campaign must pass catalog and placement validation.")
	check(int(validation.get("definition_count", 0)) == 4, "Reference campaign must expose four reusable object definitions.")
	check(int(validation.get("placement_count", 0)) == 9, "Reference campaign must expose nine object placements.")

	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(campaign_result.get("ok", false), "Reference campaign must load.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog_result := ObjectCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(catalog_result.get("ok", false), "Reference object catalog must load.")
	var definitions: Dictionary = catalog_result.get("definitions", {})
	check(str(ObjectCatalog.definition(definitions, "ash_hound").get("kind", "")) == "enemy", "Ash Hound must resolve as an enemy definition.")
	check(str(ObjectCatalog.definition(definitions, "clock_shard").get("kind", "")) == "pickup", "Clock Shard must resolve as a pickup definition.")

	var bell_path := Repository.find_exact_map_path(CAMPAIGN_PATH, campaign, "bellweather_crossing")
	var bell_result := Repository.read_json(bell_path)
	check(bell_result.get("ok", false), "Bellweather map must load.")
	var bell: Dictionary = bell_result.get("data", {})
	var session_state: Dictionary = {}
	var verdant_entities := EncounterModel.instantiate_entities(bell, definitions, "verdant", session_state)
	var ashen_entities := EncounterModel.instantiate_entities(bell, definitions, "ashen", session_state)
	check(verdant_entities.size() == 3, "Verdant Bellweather must instantiate the crate, archivist and shard.")
	check(ashen_entities.size() == 2, "Ashen Bellweather must instantiate the crate and Ash Hound.")
	var crate_index := EncounterModel.nearest_entity_index(verdant_entities, Vector2(368, 248), ["prop"], 8.0)
	check(crate_index >= 0, "Placed crate must be discoverable by kind and position.")
	check(EncounterModel.position_is_blocked_by_entities(verdant_entities, Vector2(368, 248), 7.0), "Solid placed props must block actors.")
	var hound_index := EncounterModel.nearest_facing_enemy_index(ashen_entities, Vector2(380, 216), Vector2.RIGHT, 42.0)
	check(hound_index >= 0, "A facing player must acquire the nearby authored enemy.")
	var shard_key := "bellweather:clock_shard"
	session_state[shard_key] = "collected"
	var collected_entities := EncounterModel.instantiate_entities(bell, definitions, "verdant", session_state)
	check(collected_entities.size() == 2, "Collected pickups must not respawn from the same persistent state key.")

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
	var runtime_script: Variant = runtime.get_script()
	check(runtime_script is GDScript, "Runtime root must retain its GDScript after scene loading.")
	if runtime_script is GDScript:
		var runtime_path := str((runtime_script as GDScript).resource_path)
		check(
			COMBAT_RUNTIME_PATHS.has(runtime_path),
			"Runtime scene must bind a combat-capable runtime script."
		)
	if not has_property(runtime, "object_definitions") or not has_property(runtime, "runtime_entities"):
		failures.append("Runtime script did not expose encounter state properties.")
		runtime.free()
		return
	root.add_child(runtime)
	var loaded_definitions: Variant = runtime.get("object_definitions")
	check(typeof(loaded_definitions) == TYPE_DICTIONARY, "Runtime object definitions must be a dictionary.")
	if typeof(loaded_definitions) == TYPE_DICTIONARY:
		check((loaded_definitions as Dictionary).size() == 4, "Runtime must load the campaign object catalog during ready.")
	check(runtime.has_method("sync_runtime_entities"), "Runtime must expose entity synchronisation.")
	check(runtime.has_method("perform_player_attack"), "Runtime must expose the player attack contract.")
	if runtime.has_method("sync_runtime_entities"):
		runtime.set("current_era_id", "ashen")
		runtime.call("sync_runtime_entities", false)
	var runtime_entities_value: Variant = runtime.get("runtime_entities")
	var runtime_entities: Array = runtime_entities_value if typeof(runtime_entities_value) == TYPE_ARRAY else []
	check(runtime_entities.size() == 2, "Runtime must resolve era-scoped Bellweather entities.")
	if runtime.has_method("perform_player_attack"):
		runtime.set("player", Vector2(380, 216))
		runtime.set("facing", Vector2.RIGHT)
		var runtime_hound := EncounterModel.nearest_facing_enemy_index(runtime_entities, Vector2(380, 216), Vector2.RIGHT, 42.0)
		check(runtime_hound >= 0, "Runtime must expose an attackable Ash Hound.")
		if runtime_hound >= 0:
			var health_before := int((runtime_entities[runtime_hound] as Dictionary).get("health", 0))
			runtime.call("perform_player_attack")
			var after_value: Variant = runtime.get("runtime_entities")
			var after_entities: Array = after_value if typeof(after_value) == TYPE_ARRAY else []
			var health_after := int((after_entities[runtime_hound] as Dictionary).get("health", 0)) if runtime_hound < after_entities.size() else health_before
			check(health_after == health_before - 4, "Player attack must apply authored combat damage.")
	root.remove_child(runtime)
	runtime.free()


func has_property(object: Object, property_name: String) -> bool:
	for property_value in object.get_property_list():
		if typeof(property_value) == TYPE_DICTIONARY and str((property_value as Dictionary).get("name", "")) == property_name:
			return true
	return false


func finish() -> void:
	if failures.is_empty():
		print("Encounter smoke test passed: catalogs, placements, era scope, collision, persistence and runtime damage are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
