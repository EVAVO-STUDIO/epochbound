extends SceneTree

const SaveProfile = preload("res://src/content/save_profile.gd")
const SaveProfileStore = preload("res://src/content/save_profile_store.gd")
const SaveValidator = preload("res://src/content/save_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const CAMPAIGN_ID := "epochbound_demo"
const SLOT_ID := "slot_2"

var failures: Array[String] = []


func _initialize() -> void:
	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	test_legacy_migration()
	test_checksum_rejection()
	test_future_schema_rejection()
	test_backup_recovery()
	SaveProfileStore.delete_profile(CAMPAIGN_ID, SLOT_ID)
	finish()


func test_legacy_migration() -> void:
	var legacy := {
		"schema_version": 0,
		"campaign_id": CAMPAIGN_ID,
		"slot": SLOT_ID,
		"saved_at_unix": 12345,
		"play_time_seconds": 81.5,
		"map": "bellweather_crossing",
		"era": "verdant",
		"player": {"x": 320, "y": 224},
		"companion": {"x": 280, "y": 232},
		"facing": {"x": 0, "y": 1},
		"health": 21,
		"companion_health": 18,
		"clock_shards": 2,
		"inventory": {"museum_tonic": 1},
		"recipes": {"ember_salve_recipe": true},
		"state": {"legacy:test": true},
		"quests": {}
	}
	var migration: Dictionary = SaveProfile.migrate(legacy)
	check(bool(migration.get("ok", false)), "Legacy schema 0 must migrate.")
	check(bool(migration.get("migrated", false)), "Legacy migration must report that it changed schema.")
	check(int(migration.get("from_version", -1)) == 0, "Legacy migration must record its source version.")
	var profile: Dictionary = migration.get("profile", {})
	check(int(profile.get("schema_version", 0)) == SaveProfile.CURRENT_SCHEMA, "Migrated profile must use the current schema.")
	check(SaveProfile.checksum_valid(profile), "Migrated profile must receive a valid checksum.")
	var validation: Dictionary = SaveValidator.validate_profile(profile, CAMPAIGN_PATH)
	check(bool(validation.get("ok", false)), "Migrated legacy state must pass campaign-bound validation.")
	var payload: Dictionary = profile.get("payload", {})
	check(str(payload.get("map_id", "")) == "bellweather_crossing", "Legacy map must migrate into payload map_id.")
	check(str(payload.get("era_id", "")) == "verdant", "Legacy era must migrate into payload era_id.")
	check((payload.get("unlocked_recipes", []) as Array).has("ember_salve_recipe"), "Legacy recipe dictionary must migrate to a stable ID array.")


func test_checksum_rejection() -> void:
	var profile := valid_profile("Checksum source", 100)
	check(SaveProfile.checksum_valid(profile), "Fresh profile checksum must be valid.")
	var payload: Dictionary = profile.get("payload", {})
	payload["clock_shards"] = 99
	profile["payload"] = payload
	var structural: Dictionary = SaveProfile.validate_structure(profile)
	check(not bool(structural.get("ok", true)), "Mutating durable state without refreshing the checksum must be rejected.")
	check(contains_fragment(structural.get("errors", []), "checksum"), "Checksum rejection must explain the integrity failure.")


func test_future_schema_rejection() -> void:
	var future := valid_profile("Future schema", 101)
	future["schema_version"] = SaveProfile.CURRENT_SCHEMA + 1
	SaveProfile.refresh_checksum(future)
	var migration: Dictionary = SaveProfile.migrate(future)
	check(not bool(migration.get("ok", true)), "A profile from a future schema must be rejected rather than guessed.")
	check(contains_fragment(migration.get("errors", []), "newer"), "Future-schema rejection must explain compatibility.")


func test_backup_recovery() -> void:
	var first := valid_profile("First durable checkpoint", 200)
	var first_write: Dictionary = SaveProfileStore.write_profile(first)
	check(bool(first_write.get("ok", false)), "First profile write must succeed.")
	var second := valid_profile("Second durable checkpoint", 300)
	var second_payload: Dictionary = second.get("payload", {})
	second_payload["clock_shards"] = 4
	second["payload"] = second_payload
	SaveProfile.refresh_checksum(second)
	var second_write: Dictionary = SaveProfileStore.write_profile(second)
	check(bool(second_write.get("ok", false)), "Second profile write must rotate the previous save into a backup.")
	check(FileAccess.file_exists(SaveProfileStore.backup_path(CAMPAIGN_ID, SLOT_ID)), "Rotated backup file must exist.")

	var final_path := SaveProfileStore.slot_path(CAMPAIGN_ID, SLOT_ID)
	var corrupt_file: FileAccess = FileAccess.open(final_path, FileAccess.WRITE)
	check(corrupt_file != null, "Test must be able to corrupt the promoted save file.")
	if corrupt_file != null:
		corrupt_file.store_string("{ definitely not valid JSON")
		corrupt_file.close()
	var recovered: Dictionary = SaveProfileStore.read_profile(CAMPAIGN_ID, SLOT_ID)
	check(bool(recovered.get("ok", false)), "A corrupt promoted save must fall back to the rotated backup.")
	check(bool(recovered.get("recovered_from_backup", false)), "Backup recovery must be reported explicitly.")
	var recovered_profile: Dictionary = recovered.get("profile", {})
	var metadata: Dictionary = recovered_profile.get("metadata", {})
	check(str(metadata.get("reason", "")) == "First durable checkpoint", "Backup recovery must return the previous complete checkpoint.")
	check(SaveProfile.checksum_valid(recovered_profile), "Recovered backup checksum must remain valid.")


func valid_profile(reason: String, saved_at: int) -> Dictionary:
	var metadata := {
		"saved_at_unix": saved_at,
		"play_time_seconds": float(saved_at),
		"reason": reason,
		"map_id": "bellweather_crossing",
		"map_name": "Bellweather Crossing",
		"era_id": "verdant",
		"era_name": "Verdant Age"
	}
	var payload := {
		"map_id": "bellweather_crossing",
		"era_id": "verdant",
		"player_position": {"x": 320, "y": 224},
		"companion_position": {"x": 280, "y": 232},
		"facing": {"x": 0, "y": 1},
		"player_health": 32,
		"companion_health": 24,
		"clock_shards": 1,
		"inventory": {"museum_tonic": 1},
		"unlocked_recipes": ["ember_salve_recipe"],
		"session_state": {"migration:test": true},
		"quest_progress": {},
		"companion_command": "follow",
		"companion_hold_position": {"x": 280, "y": 232}
	}
	return SaveProfile.build_profile(CAMPAIGN_ID, SLOT_ID, metadata, payload)


func contains_fragment(messages: Variant, fragment: String) -> bool:
	if typeof(messages) != TYPE_ARRAY:
		return false
	for message in messages:
		if fragment.to_lower() in str(message).to_lower():
			return true
	return false


func finish() -> void:
	if failures.is_empty():
		print("Save migration smoke test passed: legacy migration, integrity rejection and backup recovery are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
