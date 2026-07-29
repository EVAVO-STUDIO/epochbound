extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const ArsenalValidator = preload("res://src/content/arsenal_validator.gd")
const ArsenalCatalog = preload("res://src/content/arsenal_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	run_validation_edges()
	finish()


func run_validation_edges() -> void:
	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must load for Arsenal edge testing.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var item_result := ItemCatalog.load_item_catalogs(CAMPAIGN_PATH, campaign)
	var object_result := ObjectCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(bool(item_result.get("ok", false)), "Reference item catalogue must load.")
	check(bool(object_result.get("ok", false)), "Reference object catalogue must load.")
	var items: Dictionary = item_result.get("definitions", {})
	var objects: Dictionary = object_result.get("definitions", {})

	var errors: Array[String] = []
	var warnings: Array[String] = []
	var bad_ammo := ArsenalCatalog.default_ammunition("bad_ammo", "Bad Ammo")
	bad_ammo["stack_limit"] = 1
	bad_ammo["ammunition"] = {
		"damage_bonus": -1,
		"knockback_bonus": 9999,
		"projectile_color": "not-a-colour"
	}
	ArsenalValidator.validate_ammunition(bad_ammo, "bad_ammo", errors, warnings)
	check(contains_fragment(errors, "stack_limit"), "Ammunition stack limit of one must be rejected.")
	check(contains_fragment(errors, "damage_bonus"), "Negative ammunition damage must be rejected.")
	check(contains_fragment(errors, "knockback_bonus"), "Excessive ammunition knockback must be rejected.")
	check(contains_fragment(errors, "projectile_color"), "Invalid ammunition colour must be rejected.")

	errors.clear()
	warnings.clear()
	var bad_weapon := ItemCatalog.item(items, "clockglass_dartcaster").duplicate(true)
	var equipment: Dictionary = bad_weapon.get("equipment", {})
	var ranged: Dictionary = equipment.get("ranged", {})
	ranged["ammo_item_id"] = "museum_tonic"
	ranged["magazine_size"] = 0
	ranged["projectile_speed"] = -2
	ranged["projectile_range"] = 20
	ranged["projectile_radius"] = 100
	ranged["fire_cooldown"] = 0
	ranged["reload_time"] = -1
	ranged["projectile_color"] = "xyz"
	equipment["ranged"] = ranged
	bad_weapon["equipment"] = equipment
	ArsenalValidator.validate_ranged_weapon(bad_weapon, "bad_weapon", items, {}, errors, warnings)
	check(contains_fragment(errors, "not ammunition"), "A ranged weapon referencing a non-ammunition item must be rejected.")
	check(contains_fragment(errors, "magazine_size"), "Zero magazine size must be rejected.")
	check(contains_fragment(errors, "projectile_speed"), "Negative projectile speed must be rejected.")
	check(contains_fragment(errors, "projectile_radius"), "Oversized projectile radius must be rejected.")
	check(contains_fragment(errors, "fire_cooldown"), "Zero fire cooldown must be rejected.")
	check(contains_fragment(errors, "reload_time"), "Negative reload time must be rejected.")
	check(contains_fragment(errors, "projectile_color"), "Invalid weapon projectile colour must be rejected.")

	errors.clear()
	warnings.clear()
	var bad_enemy := (objects.get("underworks_sentinel", {}) as Dictionary).duplicate(true)
	var enemy_ranged: Dictionary = bad_enemy.get("ranged_attack", {})
	enemy_ranged["projectile_range"] = 80
	enemy_ranged["projectile_speed"] = 0
	enemy_ranged["projectile_color"] = "not-a-colour"
	bad_enemy["ranged_attack"] = enemy_ranged
	bad_enemy["attack_radius"] = 160
	ArsenalValidator.validate_enemy_ranged_attack(bad_enemy, "bad_enemy", errors, warnings)
	check(contains_fragment(errors, "projectile_speed"), "Zero enemy projectile speed must be rejected.")
	check(contains_fragment(errors, "projectile_color"), "Invalid enemy projectile colour must be rejected.")
	check(contains_fragment(errors, "exceeds projectile_range"), "Enemy attack radius beyond projectile range must be rejected.")

	errors.clear()
	ArsenalValidator.validate_loaded_ammo(
		{
			"missing_weapon": 1,
			"clockglass_dartcaster": 99
		},
		{
			"clockglass_dartcaster": 1,
			"archive_bolts": 10
		},
		items,
		errors
	)
	check(contains_fragment(errors, "unknown ranged weapon"), "Unknown loaded-ammo weapon must be rejected.")
	check(contains_fragment(errors, "exceeds its magazine size"), "Loaded rounds above magazine size must be rejected.")

	errors.clear()
	ArsenalValidator.validate_loaded_ammo(
		{"clockglass_dartcaster": 2},
		{"archive_bolts": 10},
		items,
		errors
	)
	check(contains_fragment(errors, "not owned"), "Loaded magazine must require ownership of its ranged weapon.")

	var valid_report := ArsenalValidator.validate_campaign_path(CAMPAIGN_PATH)
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
		print("Arsenal validation edge smoke test passed: malformed ammunition, weapons, enemies and saved magazines are rejected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
