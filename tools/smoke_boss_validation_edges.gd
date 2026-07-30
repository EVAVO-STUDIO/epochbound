extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const BossValidator = preload("res://src/content/boss_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	run_validation_edges()
	finish()


func run_validation_edges() -> void:
	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load for boss edge testing.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var object_result := ObjectCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	var item_result := ItemCatalog.load_item_catalogs(CAMPAIGN_PATH, campaign)
	var economy_result := EconomyCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(object_result.get("ok", false)), "Reference object catalogue must load.")
	check(bool(item_result.get("ok", false)), "Reference item catalogue must load.")
	check(bool(economy_result.get("ok", false)), "Reference economy catalogue must load.")
	var definitions: Dictionary = object_result.get("definitions", {})
	var items: Dictionary = item_result.get("definitions", {})
	var currencies: Dictionary = economy_result.get("currencies", {})

	var malformed := (definitions.get("underworks_sentinel", {}) as Dictionary).duplicate(true)
	var boss: Dictionary = (malformed.get("boss", {}) as Dictionary).duplicate(true)
	boss["outcome_state_key"] = ""
	boss["arena_bounds"] = {"left": 300, "right": 360, "top": 180, "bottom": 230}
	boss["defeat_effects"] = [{"type": "grant_currency", "currency_id": "missing_currency", "amount": 0}]
	boss["phases"] = [
		{
			"id": "broken_phase",
			"display_name": "Broken Phase",
			"health_ratio_at_or_below": 1.0,
			"available_eras": [],
			"attack_windup": 0.1,
			"move_speed_multiplier": 0,
			"attack_cooldown_multiplier": 1.0,
			"attack_damage_multiplier": 1.0,
			"reinforcement_placements": ["missing_echo", "missing_echo"],
			"ranged_attack_override": {"projectile_speed": 900, "projectile_radius": 20},
			"attack_pattern": [
				{"type": "fan_shot", "count": 9, "spread_degrees": 3},
				{"type": "fan_shot", "count": 9, "spread_degrees": 3},
				{"type": "fan_shot", "count": 9, "spread_degrees": 3},
				{"type": "fan_shot", "count": 9, "spread_degrees": 3}
			]
		}
	]
	malformed["boss"] = boss
	var errors: Array[String] = []
	var warnings: Array[String] = []
	BossValidator.validate_boss_definition(malformed, "malformed_boss", items, currencies, errors, warnings)
	check(contains_fragment(errors, "outcome_state_key"), "Missing boss outcome key must be rejected.")
	check(contains_fragment(errors, "movement space"), "Undersized boss arena must be rejected.")
	check(contains_fragment(errors, "at least two phase"), "A one-phase boss must be rejected.")
	check(contains_fragment(errors, "attack_windup"), "Unreadable phase windup must be rejected.")
	check(contains_fragment(errors, "move_speed_multiplier"), "Non-positive phase movement multiplier must be rejected.")
	check(contains_fragment(errors, "projectile speed"), "Excessive boss projectile speed must be rejected.")
	check(contains_fragment(errors, "projectile radius"), "Excessive boss projectile radius must be rejected.")
	check(contains_fragment(errors, "fan_shot count"), "Oversized boss fan must be rejected.")
	check(contains_fragment(errors, "pause step"), "Patterns without recovery pauses must be rejected.")
	check(contains_fragment(errors, "consecutive attacks"), "Excessive consecutive boss attacks must be rejected.")
	check(contains_fragment(errors, "unknown currency"), "Boss rewards referencing unknown currencies must be rejected.")
	check(contains_fragment(errors, "amount must be positive"), "Zero boss currency rewards must be rejected.")

	var map_result := Repository.read_json(Repository.find_exact_map_path(CAMPAIGN_PATH, campaign, "museum_underworks"))
	check(bool(map_result.get("ok", false)), "Museum Underworks must load for boss map edge testing.")
	var malformed_map: Dictionary = (map_result.get("data", {}) as Dictionary).duplicate(true)
	var placements: Array = malformed_map.get("object_placements", [])
	for index in range(placements.size()):
		if typeof(placements[index]) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = placements[index]
		if str(placement.get("id", "")) == "underworks_sentinel":
			placement["position"] = {"x": 110, "y": 224}
			placements[index] = placement
		elif str(placement.get("id", "")) == "curator_echo_west":
			placement["boss_reinforcement"] = {"boss_placement_id": "wrong_boss", "phase_id": "wrong_phase"}
			placements[index] = placement
	malformed_map["object_placements"] = placements
	malformed_map["encounter_zones"] = []
	malformed_map["connections"] = []
	errors.clear()
	warnings.clear()
	BossValidator.validate_map_bosses(malformed_map, definitions, {"underworks_sentinel": true}, errors, warnings)
	check(contains_fragment(errors, "arena zone"), "Missing authored boss arena zone must be rejected.")
	check(contains_fragment(errors, "lock_connection_ids"), "Missing locked connection must be rejected.")
	check(contains_fragment(errors, "immediate attack envelope"), "Entry points inside the boss attack envelope must be rejected.")
	check(contains_fragment(errors, "reinforcement"), "Broken boss reinforcement references must be rejected.")

	var valid_report := BossValidator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(valid_report.get("ok", false)), "Reference campaign must remain valid after malformed-copy tests.")


func contains_fragment(messages: Variant, fragment: String) -> bool:
	if typeof(messages) != TYPE_ARRAY:
		return false
	for message in messages:
		if fragment.to_lower() in str(message).to_lower():
			return true
	return false


func finish() -> void:
	if failures.is_empty():
		print("Boss validation edge smoke test passed: malformed arenas, phases, patterns, rewards and reinforcements are rejected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
