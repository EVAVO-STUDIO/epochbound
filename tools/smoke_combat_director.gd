extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")

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
	check(int(validation.get("placement_count", 0)) == 14, "Reference campaign must retain fourteen placements.")

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

	await probe_runtime_scene()
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
			runtime_path in ["res://src/combat_director_runtime.gd", "res://src/companion_runtime.gd", "res://src/inventory_runtime.gd", "res://src/story_runtime.gd", "res://src/save_runtime.gd", "res://src/equipment_runtime.gd", "res://src/merchant_runtime.gd", "res://src/arsenal_runtime.gd", "res://src/boss_runtime.gd", "res://src/cinematic_runtime.gd", "res://src/presentation_runtime_current.gd"],
			"Runtime scene must bind a Combat Director-capable runtime."
		)
	root.add_child(runtime)
	check(runtime.has_method("update_runtime_entities"), "Runtime must expose directed enemy updates.")
	check(runtime.has_method("damage_entity"), "Runtime must expose enemy damage and stagger handling.")
	check(runtime.has_method("update_zone_clear_states"), "Runtime must expose persistent zone clearing.")
	if not runtime.has_method("update_runtime_entities"):
		await HeadlessRuntimeCleanup.release(self, runtime)
		return

	runtime.set("current_era_id", "ashen")
	runtime.call("sync_runtime_entities", false)
	var entities := runtime_entities(runtime)
	var hound_index := enemy_index(entities, "crossing_hound")
	check(hound_index >= 0, "Ashen Bellweather must instantiate crossing_hound.")
	if hound_index < 0:
		await HeadlessRuntimeCleanup.release(self, runtime)
		return

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
	check(str(hound.get("attack_target_id", "")) == "player", "Windup must lock the selected target identity.")
	check(int(runtime.get("player_health")) == player_health_before, "Windup must not damage the player early.")
	var companion_health_before := int(runtime.get("companion_health"))
	runtime.set("companion", Vector2(398, 216))
	runtime.call("update_runtime_entities", 0.35)
	check(int(runtime.get("player_health")) == player_health_before - expected_player_damage, "Completed windup must apply authored attack damage after active defence.")
	check(int(runtime.get("companion_health")) == companion_health_before, "A closer companion must not inherit the player's active telegraph.")
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	check(str(hound.get("attack_target_id", "")) == "", "Resolved windup must clear its target lock.")

	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	hound["position"] = Vector2(400, 216)
	hound["attack_windup"] = 0.0
	hound["attack_target_id"] = ""
	hound["stagger_timer"] = 0.0
	hound["knockback_velocity"] = Vector2.ZERO
	hound["attack_cooldown"] = 0.0
	hound["mode"] = "chase"
	entities[hound_index] = hound
	runtime.set("runtime_entities", entities)
	runtime.set("player", Vector2(380, 216))
	runtime.set("companion", Vector2(270, 230))
	runtime.set("player_hurt_lock", 0.0)
	runtime.call("update_runtime_entities", 0.01)
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	check(str(hound.get("mode", "")) == "windup", "Interrupt fixture must begin from an active enemy windup.")
	check(str(hound.get("attack_target_id", "")) == "player", "Interrupt fixture must retain the selected player target.")
	var player_health_before_interrupt := int(runtime.get("player_health"))
	runtime.call("damage_entity", hound_index, 1, "ELI")
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	check(str(hound.get("mode", "")) == "staggered", "Damaged enemy must enter staggered mode.")
	check(float(hound.get("stagger_timer", 0.0)) > 0.0, "Damaged enemy must receive stagger time.")
	check(float(hound.get("attack_windup", -1.0)) == 0.0, "Stagger must cancel the pending attack windup.")
	check(str(hound.get("attack_target_id", "missing")) == "", "Stagger must clear the pending attack target.")
	var knockback_value: Variant = hound.get("knockback_velocity", Vector2.ZERO)
	check(knockback_value is Vector2 and (knockback_value as Vector2).length_squared() > 0.0, "Damaged enemy must receive knockback velocity.")
	check(int(runtime.get("combo_count")) >= 1, "Successful hit must advance the combat chain.")
	var stagger_remaining := float(hound.get("stagger_timer", 0.0))
	hound["knockback_velocity"] = Vector2.ZERO
	entities[hound_index] = hound
	runtime.set("runtime_entities", entities)
	runtime.call("update_runtime_entities", stagger_remaining + 0.01)
	check(int(runtime.get("player_health")) == player_health_before_interrupt, "Interrupted windup must not deal deferred damage after stagger.")
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	check(str(hound.get("mode", "")) == "windup", "A post-stagger attack must begin a fresh telegraph.")
	check(float(hound.get("attack_windup", 0.0)) > 0.0, "Fresh post-stagger telegraph must restore the full authored windup.")
	check(str(hound.get("attack_target_id", "")) == "player", "Fresh post-stagger telegraph must acquire its own target lock.")

	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	hound["position"] = Vector2(580, 216)
	hound["stagger_timer"] = 0.0
	hound["knockback_velocity"] = Vector2.ZERO
	hound["attack_windup"] = 0.0
	hound["attack_target_id"] = ""
	hound["mode"] = "chase"
	entities[hound_index] = hound
	runtime.set("runtime_entities", entities)
	runtime.set("player", Vector2(600, 216))
	runtime.call("update_runtime_entities", 0.1)
	entities = runtime_entities(runtime)
	hound = entities[hound_index]
	check(str(hound.get("mode", "")) == "return", "Enemy outside its leash must enter return mode.")

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

	var pressure_campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(pressure_campaign_result.get("ok", false), "Pressure fixture campaign must load independently.")
	var pressure_campaign: Dictionary = pressure_campaign_result.get("data", {})
	var pressure_clockwood := load_map(pressure_campaign, "clockwood_edge")
	var pressure_clockwood_ashen := EncounterZoneModel.available_zones(pressure_clockwood, "ashen")
	check(not pressure_clockwood_ashen.is_empty(), "Pressure fixture must retain the Ashen Clockwood encounter zone.")
	var pressure_zone: Dictionary = pressure_clockwood_ashen[0] if not pressure_clockwood_ashen.is_empty() else {}
	var pressure_ids := EncounterZoneModel.enemy_placement_ids(pressure_zone)
	runtime.set("map_data", pressure_clockwood)
	runtime.set("current_era_id", "ashen")
	runtime.call("sync_runtime_entities", false)
	entities = runtime_entities(runtime)
	var pressure_indices: Array[int] = []
	for pressure_id in pressure_ids:
		var pressure_index := enemy_index(entities, pressure_id)
		check(pressure_index >= 0, "Every Clockwood pressure-zone member must instantiate.")
		if pressure_index >= 0:
			pressure_indices.append(pressure_index)
	check(pressure_indices.size() == 2, "Clockwood pressure fixture must retain two ordinary enemies.")
	if pressure_indices.size() == 2:
		var pressure_target := Vector2.ZERO
		for pressure_index in pressure_indices:
			var pressure_entity: Dictionary = entities[pressure_index]
			var spawn_value: Variant = pressure_entity.get("spawn_position", Vector2.ZERO)
			pressure_target += spawn_value if spawn_value is Vector2 else Vector2.ZERO
		pressure_target /= float(pressure_indices.size())
		for pressure_order in range(pressure_indices.size()):
			var pressure_index := pressure_indices[pressure_order]
			var pressure_entity: Dictionary = entities[pressure_index]
			var side := -1.0 if pressure_order == 0 else 1.0
			pressure_entity["position"] = pressure_target + Vector2(side * 14.0, 0.0)
			pressure_entity["mode"] = "chase"
			pressure_entity["attack_cooldown"] = 0.0
			pressure_entity["attack_windup"] = 0.0
			pressure_entity["attack_target_id"] = ""
			pressure_entity["stagger_timer"] = 0.0
			pressure_entity["knockback_velocity"] = Vector2.ZERO
			entities[pressure_index] = pressure_entity
		runtime.set("runtime_entities", entities)
		runtime.set("player", pressure_target)
		runtime.set("companion", pressure_target + Vector2(180.0, 0.0))
		runtime.set("player_hurt_lock", 0.0)
		var pressure_health_before := int(runtime.get("player_health"))
		runtime.call("update_runtime_entities", 0.01)
		entities = runtime_entities(runtime)
		var committed_index := -1
		var waiting_index := -1
		for pressure_index in pressure_indices:
			var pressure_entity: Dictionary = entities[pressure_index]
			if str(pressure_entity.get("mode", "")) == "windup":
				committed_index = pressure_index
			elif str(pressure_entity.get("mode", "")) == "pressure":
				waiting_index = pressure_index
		check(committed_index >= 0, "One ordinary enemy must own the active pressure-slot windup.")
		check(waiting_index >= 0, "The waiting enemy must enter pressure mode.")
		check(count_target_windups(entities, pressure_indices, "player") == 1, "Only one ordinary enemy may own a windup against the same actor.")
		if committed_index >= 0 and waiting_index >= 0:
			var committed: Dictionary = entities[committed_index]
			var committed_definition: Dictionary = committed.get("definition", {})
			var committed_damage := int(committed_definition.get("attack_damage", 1))
			var expected_pressure_damage := committed_damage
			if runtime.has_method("player_defense_value"):
				expected_pressure_damage = maxi(1, committed_damage - int(runtime.call("player_defense_value")))
			var committed_windup := float(committed.get("attack_windup", 0.0))
			runtime.call("update_runtime_entities", committed_windup + 0.01)
			entities = runtime_entities(runtime)
			check(int(runtime.get("player_health")) == pressure_health_before - expected_pressure_damage, "Pressure coordination must resolve exactly one telegraphed hit.")
			var handed_entity: Dictionary = entities[waiting_index]
			check(str(handed_entity.get("mode", "")) == "windup", "Attack pressure must hand the next telegraph to the waiting enemy.")
			check(str(handed_entity.get("attack_target_id", "")) == "player", "Pressure handoff must acquire a fresh target lock.")
			check(float(handed_entity.get("attack_windup", 0.0)) > 0.0, "Pressure handoff must begin a fresh full telegraph.")
			check(count_target_windups(entities, pressure_indices, "player") == 1, "Pressure handoff must retain one active ordinary-enemy windup.")
			var health_after_pressure_hit := int(runtime.get("player_health"))
			runtime.call("update_runtime_entities", 0.01)
			check(int(runtime.get("player_health")) == health_after_pressure_hit, "Pressure coordination must not add untelegraphed damage.")

	await HeadlessRuntimeCleanup.release(self, runtime)


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


func count_target_windups(entities: Array, indices: Array[int], target_id: String) -> int:
	var count := 0
	for index in indices:
		if index < 0 or index >= entities.size() or typeof(entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entities[index]
		if float(entity.get("attack_windup", 0.0)) > 0.0 and str(entity.get("attack_target_id", "")) == target_id:
			count += 1
	return count


func finish() -> void:
	if failures.is_empty():
		print("Combat Director smoke test passed: zones, target locking, interruptible windup, one-slot ordinary-enemy pressure, deterministic handoff, derived damage, stagger, leash return and persistent clearing are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
