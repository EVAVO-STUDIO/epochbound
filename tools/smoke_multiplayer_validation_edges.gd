extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const CampaignPackage = preload("res://src/content/campaign_package.gd")
const MultiplayerValidator = preload("res://src/content/multiplayer_area_validator.gd")

const TEST_ROOT := "user://epochbound_test_multiplayer_validation"
const CAMPAIGN_PATH := TEST_ROOT + "/campaign.json"
const MAP_PATH := TEST_ROOT + "/maps/arena.json"
const CATALOG_PATH := TEST_ROOT + "/multiplayer/core.json"

var failures: Array[String] = []


func _initialize() -> void:
	run_test()


func run_test() -> void:
	CampaignPackage.remove_tree(TEST_ROOT)
	write_valid_fixture()
	var valid := MultiplayerValidator.validate_multiplayer_only(CAMPAIGN_PATH)
	check(bool(valid.get("ok", false)), "Valid multiplayer policy and area fixture must pass.")
	check(int(valid.get("multiplayer_area_count", 0)) == 1 and int(valid.get("pvp_area_count", 0)) == 1, "Valid fixture must expose one PvP area.")

	var campaign := read_data(CAMPAIGN_PATH)
	(campaign.get("multiplayer", {}) as Dictionary)["default_port"] = "27491"
	Repository.save_json(CAMPAIGN_PATH, campaign)
	var invalid_port := MultiplayerValidator.validate_multiplayer_only(CAMPAIGN_PATH)
	check(has_error(invalid_port, "default_port must be an integer"), "Multiplayer ports must reject numeric-string coercion.")

	write_valid_fixture()
	campaign = read_data(CAMPAIGN_PATH)
	(campaign.get("multiplayer", {}) as Dictionary)["default_port"] = 27491.5
	Repository.save_json(CAMPAIGN_PATH, campaign)
	var fractional_port := MultiplayerValidator.validate_multiplayer_only(CAMPAIGN_PATH)
	check(has_error(fractional_port, "default_port must be an integer"), "Multiplayer ports must reject fractional values.")

	write_valid_fixture()
	campaign = read_data(CAMPAIGN_PATH)
	(campaign.get("multiplayer", {}) as Dictionary)["shared_progression"] = "all_peers"
	Repository.save_json(CAMPAIGN_PATH, campaign)
	var invalid_progression := MultiplayerValidator.validate_multiplayer_only(CAMPAIGN_PATH)
	check(has_error(invalid_progression, "shared_progression must be 'host_only'"), "Guest-authored durable progression policy must be rejected.")

	write_valid_fixture()
	var catalog := read_data(CATALOG_PATH)
	var areas: Array = catalog.get("areas", [])
	(areas[0] as Dictionary)["priority"] = 10.5
	catalog["areas"] = areas
	Repository.save_json(CATALOG_PATH, catalog)
	var fractional_priority := MultiplayerValidator.validate_multiplayer_only(CAMPAIGN_PATH)
	check(has_error(fractional_priority, "priority must be an integer"), "Multiplayer area priority must reject fractional values.")

	write_valid_fixture()
	catalog = read_data(CATALOG_PATH)
	areas = catalog.get("areas", [])
	(areas[0] as Dictionary)["kind"] = "co_op"
	(areas[0] as Dictionary)["allow_invaders"] = true
	catalog["areas"] = areas
	Repository.save_json(CATALOG_PATH, catalog)
	var invalid_kind := MultiplayerValidator.validate_multiplayer_only(CAMPAIGN_PATH)
	check(has_error(invalid_kind, "only PvP areas may allow invaders"), "Co-op areas must not silently enable invasion damage.")

	write_valid_fixture()
	catalog = read_data(CATALOG_PATH)
	areas = catalog.get("areas", [])
	(areas[0] as Dictionary)["bounds"] = {"left": -10, "right": 700, "top": 0, "bottom": 400}
	catalog["areas"] = areas
	Repository.save_json(CATALOG_PATH, catalog)
	var invalid_bounds := MultiplayerValidator.validate_multiplayer_only(CAMPAIGN_PATH)
	check(has_error(invalid_bounds, "must remain inside map"), "Online area bounds must remain inside their authored map.")

	write_valid_fixture()
	catalog = read_data(CATALOG_PATH)
	areas = catalog.get("areas", [])
	(areas[0] as Dictionary)["available_eras"] = ["future"]
	catalog["areas"] = areas
	Repository.save_json(CATALOG_PATH, catalog)
	var invalid_era := MultiplayerValidator.validate_multiplayer_only(CAMPAIGN_PATH)
	check(has_error(invalid_era, "unknown era 'future'"), "Online areas must reject unknown era bindings.")

	write_valid_fixture()
	catalog = read_data(CATALOG_PATH)
	catalog["areas"] = []
	Repository.save_json(CATALOG_PATH, catalog)
	var missing_area := MultiplayerValidator.validate_multiplayer_only(CAMPAIGN_PATH)
	check(has_error(missing_area, "no multiplayer areas are authored"), "Enabled online campaigns must not ship without areas.")
	check(has_error(missing_area, "max_invaders is positive but no PvP area is authored"), "Positive invasion capacity must require a PvP area.")

	var payload := {"map_id": "arena", "multiplayer_peers": {2: {"role": "ally"}}, "invasion_state": {"active": true}}
	var profile_errors: Array[String] = []
	MultiplayerValidator.validate_profile_multiplayer(payload, profile_errors)
	check(profile_errors.size() == 2, "Save validation must reject every injected ephemeral multiplayer field.")

	CampaignPackage.remove_tree(TEST_ROOT)
	finish()


func write_valid_fixture() -> void:
	CampaignPackage.remove_tree(TEST_ROOT)
	Repository.save_json(MAP_PATH, {
		"schema_version": 1,
		"id": "arena",
		"display_name": "Arena",
		"canvas": {"width": 640, "height": 360, "grid_size": 16},
		"bounds": {"left": 32, "right": 608, "top": 96, "bottom": 328},
		"spawns": {"player": {"x": 128, "y": 224}, "companion": {"x": 152, "y": 232}},
		"eras": [{"id": "verdant", "display_name": "Verdant", "palette": {}, "landmarks": []}],
		"terrain_palette": [],
		"terrain_cells": [],
		"collision_cells": [],
		"navigation_cells": [],
		"recovery_anchors": [],
		"entry_points": [],
		"layers": [],
		"object_placements": [],
		"interactions": [],
		"connections": [],
		"encounter_zones": [],
		"companion_cues": []
	})
	Repository.save_json(CATALOG_PATH, {
		"schema_version": 1,
		"areas": [{
			"id": "arena_pvp",
			"display_name": "Arena PvP",
			"map_id": "arena",
			"kind": "pvp",
			"priority": 10,
			"bounds": {"left": 64, "right": 576, "top": 128, "bottom": 304},
			"available_eras": ["verdant"],
			"allow_allies": true,
			"allow_invaders": true,
			"friendly_fire": false,
			"ally_spawn": {"x": 144, "y": 224},
			"invader_spawn": {"x": 496, "y": 224}
		}]
	})
	Repository.save_json(CAMPAIGN_PATH, {
		"schema_version": 1,
		"id": "multiplayer_validation_fixture",
		"title": "Fixture",
		"start_map": "arena",
		"start_era": "verdant",
		"map_files": ["maps/arena.json"],
		"multiplayer_files": ["multiplayer/core.json"],
		"multiplayer": {
			"enabled": true,
			"transport": "enet",
			"default_port": 27491,
			"max_allies": 2,
			"max_invaders": 1,
			"snapshot_rate_hz": 12,
			"input_rate_hz": 30,
			"shared_progression": "host_only",
			"pvp_rewards": "session_only",
			"friendly_fire": false
		}
	})


func read_data(path: String) -> Dictionary:
	var result := Repository.read_json(path)
	var value: Variant = result.get("data", {})
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func has_error(report: Dictionary, fragment: String) -> bool:
	var value: Variant = report.get("errors", [])
	if typeof(value) != TYPE_ARRAY:
		return false
	for message in value as Array:
		if fragment in str(message):
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Multiplayer validation-edge smoke test passed: strict policy types, host-only progression, PvP-only invasions, map bounds, era bindings and save isolation fail closed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
