extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const EquipmentValidator = preload("res://src/content/equipment_validator.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")

const ROOT := "user://equipment_validation_edge"
const CAMPAIGN_PATH := ROOT + "/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	build_malformed_campaign()
	test_campaign_validation()
	test_profile_equipment_validation()
	finish()


func build_malformed_campaign() -> void:
	var campaign := Repository.default_campaign("equipment_edge", "Equipment Edge")
	campaign["equipment_slots"] = [{"id": "weapon", "display_name": "Weapon"}]
	campaign["base_capabilities"] = ["unknown_power"]
	campaign["starting_equipment"] = {"weapon": "trail_hook"}
	Repository.save_json(CAMPAIGN_PATH, campaign)

	var item_catalog := ItemCatalog.default_item_catalog()
	for index in range((item_catalog.get("items", []) as Array).size()):
		var item_data: Dictionary = (item_catalog.get("items", []) as Array)[index]
		if str(item_data.get("id", "")) != "trail_hook":
			continue
		item_data["stack_limit"] = 2
		item_data["equipment"] = {
			"slot": "missing_slot",
			"attack_bonus": -1,
			"defense_bonus": 0,
			"max_health_bonus": 0,
			"move_speed_bonus": 0,
			"capabilities": ["unknown_power"]
		}
		(item_catalog.get("items", []) as Array)[index] = item_data
	Repository.save_json(ROOT + "/items/core.json", item_catalog)
	Repository.save_json(ROOT + "/recipes/core.json", ItemCatalog.default_recipe_catalog())
	Repository.save_json(ROOT + "/capabilities/core.json", EquipmentCatalog.default_capability_catalog())

	var story_catalog := StoryCatalog.default_story_catalog()
	var conversations: Array = story_catalog.get("conversations", [])
	if not conversations.is_empty():
		var conversation: Dictionary = conversations[0]
		conversation["conditions"] = [{"type": "has_capability", "capability_id": "unknown_power"}]
		conversations[0] = conversation
	story_catalog["conversations"] = conversations
	Repository.save_json(ROOT + "/story/core.json", story_catalog)

	var map_data := Repository.default_map("first_crossing", "First Crossing")
	map_data["connections"] = [
		{
			"id": "bad_gate",
			"position": {"x": 320, "y": 224},
			"radius": 24,
			"target_map": "first_crossing",
			"target_entry": "start",
			"target_era": "same",
			"trigger": "interact",
			"available_eras": [],
			"required_capabilities": ["unknown_power"],
			"blocked_dialogue": ""
		}
	]
	Repository.save_json(ROOT + "/maps/first_crossing.json", map_data)


func test_campaign_validation() -> void:
	var report: Dictionary = EquipmentValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(not bool(report.get("ok", true)), "Malformed equipment campaign must fail validation.")
	var errors: Variant = report.get("errors", [])
	check(contains_fragment(errors, "stack_limit must be 1"), "Validation must enforce single-item equipment stacks.")
	check(contains_fragment(errors, "missing_slot"), "Validation must reject unknown equipment slots.")
	check(contains_fragment(errors, "attack_bonus"), "Validation must reject negative combat modifiers.")
	check(contains_fragment(errors, "unknown_power"), "Validation must reject unknown capability references across content systems.")
	check(contains_fragment(errors, "blocked_dialogue"), "Validation must require player-facing blocked gate feedback.")


func test_profile_equipment_validation() -> void:
	var item_catalog := ItemCatalog.default_item_catalog()
	var item_definitions: Dictionary = {}
	for item_value in item_catalog.get("items", []):
		if typeof(item_value) == TYPE_DICTIONARY:
			var item_data: Dictionary = item_value
			item_definitions[str(item_data.get("id", ""))] = item_data
	var campaign := Repository.default_campaign("profile_edge", "Profile Edge")
	var errors: Array[String] = []
	EquipmentValidator.validate_profile_equipment(
		{"weapon": "trail_hook", "unknown_slot": "field_coat"},
		{},
		campaign,
		item_definitions,
		errors
	)
	check(contains_fragment(errors, "without owning"), "Profile validation must reject equipped items absent from inventory.")
	check(contains_fragment(errors, "unknown slot"), "Profile validation must reject unknown equipment slots.")


func contains_fragment(messages: Variant, fragment: String) -> bool:
	if typeof(messages) != TYPE_ARRAY:
		return false
	for message in messages:
		if fragment.to_lower() in str(message).to_lower():
			return true
	return false


func finish() -> void:
	if failures.is_empty():
		print("Equipment validation edge test passed: malformed slots, stats, capabilities, gates and profile ownership are rejected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
