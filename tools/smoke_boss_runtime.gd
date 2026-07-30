extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const BossValidator = preload("res://src/content/boss_validator.gd")
const BossCatalog = preload("res://src/content/boss_catalog.gd")
const EncounterModel = preload("res://src/game/encounter_model.gd")
const EconomyModel = preload("res://src/game/economy_model.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"
const BOSS_PLACEMENT := "underworks_sentinel"
const REINFORCEMENTS := ["curator_echo_west", "curator_echo_east"]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var validation := BossValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Reference campaign must pass Boss and Phase validation.")
	check(int(validation.get("boss_count", 0)) == 1, "Reference campaign must expose one boss definition.")
	check(int(validation.get("boss_placement_count", 0)) == 1, "Reference campaign must expose one boss placement.")
	check(int(validation.get("boss_phase_count", 0)) == 3, "Reference boss must expose three phase records.")
	check(int(validation.get("boss_reinforcement_count", 0)) == 2, "Reference boss must expose two reinforcement placements.")

	var scene_resource := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(scene_resource is PackedScene, "Boss-aware runtime scene must load.")
	if not scene_resource is PackedScene:
		finish()
		return
	var runtime := (scene_resource as PackedScene).instantiate()
	check(runtime != null, "Boss-aware runtime scene must instantiate.")
	if runtime == null:
		finish()
		return
	var script_value: Variant = runtime.get_script()
	check(script_value is GDScript, "Runtime root must retain its GDScript.")
	if script_value is GDScript:
		check(str((script_value as GDScript).resource_path) in ["res://src/boss_runtime.gd", "res://src/cinematic_runtime.gd"], "Runtime scene must bind the Boss runtime.")
	root.add_child(runtime)
	check(runtime.has_method("update_boss_engagements"), "Runtime must expose boss engagement evaluation.")
	check(runtime.has_method("perform_boss_pattern_attack"), "Runtime must expose deterministic boss patterns.")
	check(runtime.has_method("finalize_boss_outcomes"), "Runtime must expose durable boss completion.")

	check(bool(runtime.call("activate_map", "museum_underworks", "from_bellweather", "verdant", false)), "Museum Underworks must activate for boss testing.")
	# Flow.GAME is enum value 4 in the shared runtime contract.
	runtime.call("change_flow", 4)
	runtime.set("player", Vector2(320, 224))
	runtime.set("companion", Vector2(294, 238))
	runtime.call("update_boss_engagements")
	check(bool(dictionary_property(runtime, "engaged_bosses").get(BOSS_PLACEMENT, false)), "Entering the authored activation area must engage the boss.")
	check(str(dictionary_property(runtime, "boss_phase_ids").get(BOSS_PLACEMENT, "")) == "catalogue_measure", "Verdant engagement must select the era-specific Catalogue Measure phase.")
	check(not bool(runtime.call("can_open_save_overlay")), "Manual saving must remain blocked while a boss arena is active.")
	var connection := connection_by_id(dictionary_property(runtime, "map_data"), "west_to_bellweather")
	check(not bool(runtime.call("travel_through", connection)), "Authored arena lock must block the Underworks exit during the fight.")

	runtime.call("shift_to_next_era")
	check(str(runtime.get("current_era_id")) == "ashen", "Boss arena must permit the authored era shift.")
	check(str(dictionary_property(runtime, "boss_phase_ids").get(BOSS_PLACEMENT, "")) == "cinder_measure", "Era shifting at full health must select the Ashen Cinder Measure phase.")

	var entities := array_property(runtime, "runtime_entities")
	var boss_index := entity_index(entities, BOSS_PLACEMENT)
	check(boss_index >= 0, "Underworks boss placement must resolve in the runtime.")
	if boss_index < 0:
		cleanup(runtime)
		finish()
		return
	var boss_before: Dictionary = entities[boss_index]
	var maximum := int((dictionary_property(runtime, "object_definitions").get("underworks_sentinel", {}) as Dictionary).get("max_health", 1))
	check(int(boss_before.get("health", 0)) == maximum, "Boss must begin at authored maximum health.")

	runtime.call("damage_entity", boss_index, 999, "ELI")
	entities = array_property(runtime, "runtime_entities")
	var boss_after: Dictionary = entities[boss_index]
	check(bool(boss_after.get("active", true)), "Phase-boundary clamping must prevent a full-health one-shot.")
	check(int(boss_after.get("health", 0)) > 0 and int(boss_after.get("health", 0)) <= int(floor(float(maximum) * 0.55)), "Boundary damage must land at the final-phase threshold.")
	check(str(dictionary_property(runtime, "boss_phase_ids").get(BOSS_PLACEMENT, "")) == "last_accession", "Crossing the threshold must enter Last Accession.")
	for reinforcement_id in REINFORCEMENTS:
		check(bool(dictionary_property(runtime, "boss_reinforcement_active").get(reinforcement_id, false)), "Final phase must activate reinforcement '%s'." % reinforcement_id)
		var reinforcement_index := entity_index(entities, reinforcement_id)
		check(reinforcement_index >= 0 and bool((entities[reinforcement_index] as Dictionary).get("active", false)), "Activated reinforcement '%s' must become a live runtime enemy." % reinforcement_id)

	runtime.set("projectiles", [])
	var object_definitions := dictionary_property(runtime, "object_definitions")
	var boss_definition: Dictionary = object_definitions.get("underworks_sentinel", {})
	var phase := BossCatalog.phase_by_id(boss_definition, "last_accession")
	var attacker := BossCatalog.apply_phase(boss_definition, phase)
	attacker["_position"] = (boss_after.get("position", Vector2(470, 224)) as Vector2)
	var player_health_before := int(runtime.get("player_health"))
	runtime.call("damage_actor", "player", int(attacker.get("attack_damage", 4)), attacker)
	check(int(runtime.get("player_health")) == player_health_before, "Boss attack-pattern dispatch must not apply instant damage.")
	check(array_property(runtime, "projectiles").size() == 5, "Last Accession must emit the authored five-shot fan.")

	runtime.set("projectiles", [])
	var currency_before := EconomyModel.balance(dictionary_property(runtime, "currency_balances"), "archive_chits")
	var shards_before := int(runtime.get("clock_shards"))
	runtime.call("damage_entity", boss_index, 999, "ELI")
	for reinforcement_id in REINFORCEMENTS:
		entities = array_property(runtime, "runtime_entities")
		var reinforcement_index := entity_index(entities, reinforcement_id)
		if reinforcement_index >= 0:
			runtime.call("damage_entity", reinforcement_index, 999, "ELI")
	runtime.call("update_zone_clear_states")
	runtime.call("finalize_boss_outcomes")
	var session := dictionary_property(runtime, "session_state")
	check(session.get("underworks:zone:gallery_watch") == "cleared", "Defeating every arena member must clear the authored encounter zone.")
	check(session.get("underworks:boss:sentinel") == "defeated", "Boss completion must publish its durable outcome state key.")
	check(EconomyModel.balance(dictionary_property(runtime, "currency_balances"), "archive_chits") == currency_before + 15, "Boss completion must grant the authored Archive Chits exactly once.")
	check(int(runtime.get("clock_shards")) >= shards_before + 5, "Boss completion must grant its authored clock-shard reward.")
	check((runtime.call("active_arena_context") as Dictionary).is_empty(), "Clearing the arena must release every boss lock.")
	check(array_property(runtime, "projectiles").is_empty(), "Boss completion must clear unresolved arena projectiles.")
	check(float(runtime.get("transition_lock")) == 0.0, "Boss completion must clear the phase transition lock.")
	check(str(runtime.get("dialogue")).is_empty(), "Boss completion must clear stale arena-lock dialogue.")
	check(bool(runtime.call("can_open_save_overlay")), "Saving must become available after durable arena completion.")

	cleanup(runtime)
	finish()


func connection_by_id(map_data: Dictionary, connection_id: String) -> Dictionary:
	for value in map_data.get("connections", []):
		if typeof(value) == TYPE_DICTIONARY and str((value as Dictionary).get("id", "")) == connection_id:
			return value
	return {}


func entity_index(entities: Array, placement_id: String) -> int:
	for index in range(entities.size()):
		if typeof(entities[index]) == TYPE_DICTIONARY and str((entities[index] as Dictionary).get("placement_id", "")) == placement_id:
			return index
	return -1


func dictionary_property(object: Object, property_name: String) -> Dictionary:
	var value: Variant = object.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func array_property(object: Object, property_name: String) -> Array:
	var value: Variant = object.get(property_name)
	return value if typeof(value) == TYPE_ARRAY else []


func cleanup(runtime: Node) -> void:
	root.remove_child(runtime)
	runtime.free()


func finish() -> void:
	if failures.is_empty():
		print("Boss runtime smoke test passed: engagement, era phases, phase clamping, patterns, reinforcements, arena locks and durable outcomes are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
