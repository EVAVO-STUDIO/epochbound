extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/epochbound_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EncounterModel = preload("res://src/game/encounter_model.gd")
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
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
	check(String(ObjectCatalog.definition(definitions, "ash_hound").get("kind", "")) == "enemy", "Ash Hound must resolve as an enemy definition.")
	check(String(ObjectCatalog.definition(definitions, "clock_shard").get("kind", "")) == "pickup", "Clock Shard must resolve as a pickup definition.")

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

	var scene_resource := load("res://src/app.tscn")
	check(scene_resource is PackedScene, "Runtime scene must load as a PackedScene.")
	if scene_resource is PackedScene:
		var runtime = scene_resource.instantiate()
		root.add_child(runtime)
		check(runtime.object_definitions.size() == 4, "Runtime must load the campaign object catalog during ready.")
		runtime.current_era_id = "ashen"
		runtime.sync_runtime_entities(false)
		check(runtime.runtime_entities.size() == 2, "Runtime must resolve era-scoped Bellweather entities.")
		runtime.player = Vector2(380, 216)
		runtime.facing = Vector2.RIGHT
		var runtime_hound := EncounterModel.nearest_facing_enemy_index(runtime.runtime_entities, runtime.player, runtime.facing, 42.0)
		check(runtime_hound >= 0, "Runtime must expose an attackable Ash Hound.")
		if runtime_hound >= 0:
			var health_before := int(Dictionary(runtime.runtime_entities[runtime_hound]).get("health", 0))
			runtime.perform_player_attack()
			var health_after := int(Dictionary(runtime.runtime_entities[runtime_hound]).get("health", 0))
			check(health_after == health_before - 4, "Player attack must apply authored combat damage.")
		runtime.queue_free()

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
