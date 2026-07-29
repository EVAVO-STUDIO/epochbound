extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/combat_director_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EncounterModel = preload("res://src/game/encounter_model.gd")
const EncounterZoneModel = preload("res://src/game/encounter_zone_model.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var validation := Validator.validate_campaign_path(CAMPAIGN_PATH)
	check(validation.get("ok", false), "Reference campaign must pass Combat Director validation.")
	check(int(validation.get("zone_count", 0)) == 3, "Reference campaign must expose three encounter zones.")
	check(int(validation.get("definition_count", 0)) == 7, "Reference object catalog must retain seven definitions.")
	check(int(validation.get("placement_count", 0)) == 12, "Reference campaign must retain twelve placements.")

	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(campaign_result.get("ok", false), "Reference campaign must load.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog_result := ObjectCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(catalog_result.get("ok", false), "Reference object catalog must load.")
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var ash_hound: Dictionary = definitions.get("ash_hound", {})
	check(float(ash_hound.get("attack_windup", 0.0)) > 0.0, "Ash Hound must define an attack windup.")
	check(float(ash_hound.get("stagger_duration", 0.0)) > 0.0, "Ash Hound must define stagger duration.")
	check(float(ash_hound.get("patrol_radius", 0.0)) > 0.0, "Ash Hound must define a patrol radius.")

	var bell := load_map(campaign, "bellweather_crossing")
	var clockwood := load_map(campaign, "clockwood_edge")
	var bell_ashen := EncounterZoneModel.available_zones(bell, "ashen")
	var bell_verdant := EncounterZoneModel.available_zones(bell, "verdant")
	var clockwood_ashen := EncounterZoneModel.available_zones(clockwood, "ashen")
	check(bell_ashen.size() == 1, "Bellweather must expose one Ashen encounter zone.")
	check(bell_verdant.is_empty(), "Bellweather encounter zone must remain Ashen-only.")
	check(clockwood_ashen.size() == 1, "Clockwood must expose one Ashen encounter zone.")
	if not bell_ashen.is_empty():
		var bell_zone: Dictionary = bell_ashen[0]
		check(EncounterZoneModel.enemy_placement_ids(bell_zone).has("crossing_hound"), "Bellweather zone must own crossing_hound.")
		check(EncounterZoneModel.is_activated(bell_zone, Vector2(380, 216), Vector2(270, 230), true), "Bellweather zone must activate near its hound.")
	if not clockwood_ashen.is_empty():
		var clockwood_zone: Dictionary = clockwood_ashen[0]
		check(EncounterZoneModel.enemy_placement_ids(clockwood_zone).size() == 2, "Clockwood zone must coordinate two authored enemies.")

	probe_runtime_scene()
	finish()


func load_map(campaign: Dictionary, map_id: String) -> Dictionary:
	var path := Repository.find_exact_map_path(CAMPAIGN_PATH, campaign, map_id)
	var result := Repository.read_json(path)
	check(result.get("ok", false), "Map '%s' must load." % map_id)
	return result.get("data", {}) if result.get("ok", false) else {}


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
		var runtime_path := str((script_value as GDScript).resource_path)
		check(
			runtime_path in ["res://src/combat_director_runtime.gd", "res://src/companion_runtime.gd", "res://src/inventory_runtime.gd", "res://src/story_runtime.gd", "res://src/save_runtime.gd", "res://src/equipment_runtime.gd", "res://src/merchant_runtime.gd", "res://src/arsenal_runtime.gd"],
			"Runtime scene must bind a Combat Director-capable runtime."
		)
	root.add_child(runtime)
	check(runtime.has_method("update_runtime_entities"), "Runtime must expose directed enemy updates.")
	check(runtime.has_method("damage_entity"), "Runtime must expose enemy damage and stagger handling.")
	check(runtime.has_method("update_zone_clear_states"), "Runtime must expose persistent zone clearing.")
	if not runtime.has_method("update_runtime_entities"):
		root.remove_child(runtime)
		runtime.free()
		return

	runtime.set("current_era_id", "ashen")
	runtime.call("sync_runtime_entities", false)
	var entities := runtime_entities(runtime)
	var hound_index := enemy_index(entities, "crossing_hound")
	check(hound_index >= 0, "Ashen Bellweather must instantiate crossing_hound.")
	if hound_index < 0:
		root.remove_child(runtime)
		runtime.free()
		return

	# Entering attack range must start a visible windup without immediate damage.
	var hound: Dictionary = entities[hound_index]
	hound["position"] = Vector2(400, 216)
	hound["mode"] = "chase"
	hound["attack_cooldown"] = 0.0
	entities[hound_index] = hound
	runtime.set("runtime_entities", entities)
	runtime.set("player", Vector2(386, 216))
	runtime.set("companion", Vector2(270, 230))
	var player_health_before := int(runtime.get("player_health"))
	var hound_definition: Dictionary = hound.get("definition", {})
	var authored_attack_damage := int(hound_definition.get("attack_damage", 4))
	var expected_player_damage := authored_attack_damage
	if runtime.has_method("player_defense_value"):
		expected_player_damage = maxi(1, authored_attack_damage - int(runtime.call("player_defense_value")))
	runtime.call("update_runtime_entities", 0.01)
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	check(str(hound.get("mode", "")) == "windup", "Enemy must enter windup before dealing contact damage.")
	check(float(hound.get("attack_windup", 0.0)) > 0.0, "Enemy windup timer must be active.")
	check(int(runtime.get("player_health")) == player_health_before, "Windup must not damage the player early.")
	runtime.call("update_runtime_entities", 0.35)
	check(int(runtime.get("player_health")) == player_health_before - expected_player_damage, "Completed windup must apply authored attack damage after active defence.")

	# Player damage must stagger and knock the enemy away.
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	hound["position"] = Vector2(416, 216)
	hound["attack_windup"] = 0.0
	hound["stagger_timer"] = 0.0
	entities[hound_index] = hound
	runtime.set("runtime_entities", entities)
	runtime.set("player", Vector2(380, 216))
	runtime.call("damage_entity", hound_index, 4, "ELI")
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	check(str(hound.get("mode", "")) == "staggered", "Damaged enemy must enter staggered mode.")
	check(float(hound.get("stagger_timer", 0.0)) > 0.0, "Damaged enemy must receive stagger time.")
	var knockback_value: Variant = hound.get("knockback_velocity", Vector2.ZERO)
	check(knockback_value is Vector2 and (knockback_value as Vector2).length_squared() > 0.0, "Damaged enemy must receive knockback velocity.")
	check(int(runtime.get("combo_count")) >= 1, "Successful hit must advance the combat chain.")

	# An enemy outside its authored leash must return to its spawn rather than chase forever.
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	hound["position"] = Vector2(580, 216)
	hound["stagger_timer"] = 0.0
	hound["knockback_velocity"] = Vector2.ZERO
	hound["attack_windup"] = 0.0
	hound["mode"] = "chase"
	entities[hound_index] = hound
	runtime.set("runtime_entities", entities)
	runtime.set("player", Vector2(600, 216))
	runtime.call("update_runtime_entities", 0.1)
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	check(str(hound.get("mode", "")) == "return", "Enemy outside its leash must enter return mode.")

	# Defeating every member must persist the zone clear state.
	var session_value: Variant = runtime.get("session_state")
	var session: Dictionary = session_value if typeof(session_value) == TYPE_DICTIONARY else {}
	session["bellweather:ash_hound"] = "defeated"
	runtime.set("session_state", session)
	runtime.call("sync_runtime_entities", false)
	runtime.call("update_zone_clear_states")
	session_value = runtime.get("session_state")
	session = session_value if typeof(session_value) == TYPE_DICTIONARY else {}
	check(session.get("bellweather:zone:east_ash_hunt") == "cleared", "Defeated zone members must persist a clear-state key.")
	check(str(runtime.get("zone_banner")) == "EAST ASH HUNT CLEARED", "Cleared encounter must publish a player-facing zone banner.")

	root.remove_child(runtime)
	runtime.free()


func runtime_entities(runtime: Object) -> Array:
	var value: Variant = runtime.get("runtime_entities")
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
		print("Combat Director smoke test passed: zones, windup, derived damage, stagger, leash return and persistent clearing are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
