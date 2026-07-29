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
	test_schema_two_economy_migration()
	test_default_policy_compatibility()
	test_canonical_slot_discovery()
	test_json_round_trip_checksum()
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


func test_schema_two_economy_migration() -> void:
	var legacy := valid_profile("Schema two economy migration", 82)
	legacy["schema_version"] = 2
	var payload: Dictionary = legacy.get("payload", {})
	payload.erase("currency_balances")
	payload.erase("merchant_stock")
	payload.erase("economy_initialized")
	legacy["payload"] = payload
	SaveProfile.refresh_checksum(legacy)
	var migration := SaveProfile.migrate(legacy)
	check(bool(migration.get("ok", false)), "Schema 2 profile must migrate to the economy-aware schema.")
	check(bool(migration.get("migrated", false)), "Schema 2 migration must report a change.")
	check(int(migration.get("from_version", -1)) == 2, "Schema 2 migration must preserve the source version.")
	var migrated: Dictionary = migration.get("profile", {})
	var migrated_payload: Dictionary = migrated.get("payload", {})
	check(int(migrated.get("schema_version", 0)) == SaveProfile.CURRENT_SCHEMA, "Schema 2 profile must migrate to the current schema.")
	check(typeof(migrated_payload.get("currency_balances")) == TYPE_DICTIONARY, "Migration must add a wallet dictionary.")
	check(typeof(migrated_payload.get("merchant_stock")) == TYPE_DICTIONARY, "Migration must add merchant stock state.")
	check(not bool(migrated_payload.get("economy_initialized", true)), "Pre-economy saves must request authored defaults on first load.")
	check(SaveProfile.checksum_valid(migrated), "Migrated schema 2 profile must receive a valid checksum.")


func test_default_policy_compatibility() -> void:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	SaveValidator.validate_policy({}, "legacy_campaign", errors, warnings)
	check(errors.is_empty(), "A campaign created before save_policy existed must inherit defaults without becoming invalid.")
	check(contains_fragment(warnings, "default policy"), "Omitted save policy must produce a clear compatibility warning.")
	var defaults := SaveProfile.policy({})
	check(int(defaults.get("manual_slots", 0)) == 3, "The backwards-compatible policy must expose three manual slots.")
	check(bool(defaults.get("autosave_enabled", false)), "The backwards-compatible policy must enable autosave.")

	errors.clear()
	warnings.clear()
	SaveValidator.validate_policy({"save_policy": {"manual_slots": 4}}, "partial_policy", errors, warnings)
	check(errors.is_empty(), "A partial save policy must inherit omitted boolean fields.")
	check(SaveProfile.manual_slot_ids({"save_policy": {"manual_slots": 4}}).size() == 4, "Partial policy overrides must still control manual slot count.")


func test_canonical_slot_discovery() -> void:
	check(SaveProfile.valid_slot_id("slot_1"), "Canonical manual slot IDs must remain valid.")
	check(not SaveProfile.valid_slot_id("slot_01"), "Leading-zero slot aliases must be rejected.")
	check(not SaveProfile.valid_slot_id("slot_0"), "Slot zero must be rejected.")
	check(not SaveProfile.valid_slot_id("checkpoint"), "Arbitrary save filenames must not become slots.")

	var directory := SaveProfileStore.campaign_directory(CAMPAIGN_ID)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var profile := valid_profile("Mismatched filename", 98)
	var invalid_path := directory.path_join("slot_01.json")
	var mismatched_path := directory.path_join("slot_1.json")
	for path in [invalid_path, mismatched_path]:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		check(file != null, "Slot discovery test must be able to create its fixture.")
		if file != null:
			file.store_string(JSON.stringify(SaveProfile.canonicalize(profile), "\t", true) + "\n")
			file.close()
	var records := SaveProfileStore.list_campaign_profiles(CAMPAIGN_ID)
	check(records.is_empty(), "Continue discovery must ignore non-canonical filenames and filename/profile slot mismatches.")
	for path in [invalid_path, mismatched_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_json_round_trip_checksum() -> void:
	var profile := valid_profile("JSON round trip", 99)
	var encoded := JSON.stringify(SaveProfile.canonicalize(profile), "\t", true)
	var decoded_value: Variant = JSON.parse_string(encoded)
	check(typeof(decoded_value) == TYPE_DICTIONARY, "Canonical profile JSON must parse back into an object.")
	if typeof(decoded_value) != TYPE_DICTIONARY:
		return
	var decoded: Dictionary = decoded_value
	check(SaveProfile.checksum_valid(decoded), "A canonical JSON round trip must preserve the profile checksum.")
	check(SaveProfile.canonical_json(profile) == SaveProfile.canonical_json(decoded), "Canonical JSON must be identical before and after parsing.")


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
		print("Save migration smoke test passed: legacy migration, policy compatibility, canonical slots, JSON round trips, integrity rejection and backup recovery are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
