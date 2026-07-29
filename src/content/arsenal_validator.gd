@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/economy_validator.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const ArsenalCatalog = preload("res://src/content/arsenal_catalog.gd")

const MAX_RELOAD_TIME := 20.0
const MAX_FIRE_COOLDOWN := 10.0


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report := BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var ammunition_count := 0
	var ranged_weapon_count := 0
	var ranged_enemy_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		var report := validate_arsenal_only(str(entry.get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		ammunition_count += int(report.get("ammunition_count", 0))
		ranged_weapon_count += int(report.get("ranged_weapon_count", 0))
		ranged_enemy_count += int(report.get("ranged_enemy_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["ammunition_count"] = ammunition_count
	output["ranged_weapon_count"] = ranged_weapon_count
	output["ranged_enemy_count"] = ranged_enemy_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_campaign_path(campaign_path)
	var arsenal_report := validate_arsenal_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, arsenal_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, arsenal_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	for field in ["ammunition_count", "ranged_weapon_count", "ranged_enemy_count"]:
		output[field] = arsenal_report.get(field, 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_profile(profile, campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings}
	var campaign: Dictionary = campaign_result.get("data", {})
	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) == TYPE_DICTIONARY:
		var payload: Dictionary = payload_value
		validate_loaded_ammo(
			payload.get("loaded_ammo", {}),
			payload.get("inventory", {}),
			item_result.get("definitions", {}),
			errors
		)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func validate_arsenal_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return make_report(errors, warnings, 0, 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id := str(campaign.get("id", campaign_path))
	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	var object_result := ObjectCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	append_messages(errors, object_result.get("errors", []))
	var items: Dictionary = item_result.get("definitions", {})
	var definitions: Dictionary = object_result.get("definitions", {})
	var ammunition_count := 0
	var ranged_weapon_count := 0
	var ranged_enemy_count := 0
	var referenced_ammunition: Dictionary = {}

	for item_id_value in items.keys():
		var item_id := str(item_id_value)
		var item_data := ItemCatalog.item(items, item_id)
		var prefix := "%s/item/%s" % [campaign_id, item_id]
		if ArsenalCatalog.is_ammunition(item_data):
			ammunition_count += 1
			validate_ammunition(item_data, prefix, errors, warnings)
		if ArsenalCatalog.is_ranged_weapon(item_data):
			ranged_weapon_count += 1
			validate_ranged_weapon(item_data, prefix, items, referenced_ammunition, errors, warnings)
		elif EquipmentCatalog.equipment_data(item_data).has("ranged"):
			errors.append("%s: ranged profile is only valid on equipment items." % prefix)

	for object_id_value in definitions.keys():
		var object_id := str(object_id_value)
		var definition_data: Dictionary = definitions.get(object_id, {})
		if definition_data.has("ranged_attack"):
			if str(definition_data.get("kind", "")) != "enemy":
				errors.append("%s/object/%s: ranged_attack is only valid on enemy definitions." % [campaign_id, object_id])
				continue
			ranged_enemy_count += 1
			validate_enemy_ranged_attack(
				definition_data,
				"%s/object/%s/ranged_attack" % [campaign_id, object_id],
				errors,
				warnings
			)

	for item_id_value in items.keys():
		var item_id := str(item_id_value)
		if ArsenalCatalog.is_ammunition(ItemCatalog.item(items, item_id)) and not referenced_ammunition.has(item_id):
			warnings.append("%s: ammunition '%s' is not referenced by a ranged weapon." % [campaign_id, item_id])
	if ranged_weapon_count == 0:
		warnings.append("%s: no ranged equipment is authored." % campaign_id)
	return make_report(errors, warnings, ammunition_count, ranged_weapon_count, ranged_enemy_count)


static func validate_ammunition(
	item_data: Dictionary,
	prefix: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if ItemCatalog.stack_limit(item_data) <= 1:
		errors.append("%s: ammunition stack_limit must be greater than 1." % prefix)
	var value: Variant = item_data.get("ammunition", {})
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: ammunition must be an object." % prefix)
		return
	var data: Dictionary = value
	validate_numeric_range(data, "damage_bonus", 0.0, ArsenalCatalog.MAX_DAMAGE_BONUS, prefix, errors)
	validate_numeric_range(data, "knockback_bonus", 0.0, ArsenalCatalog.MAX_KNOCKBACK, prefix, errors)
	var color_text := str(data.get("projectile_color", ArsenalCatalog.DEFAULT_PROJECTILE_COLOR))
	if not Color.html_is_valid(color_text):
		errors.append("%s: ammunition projectile_color is invalid." % prefix)
	if int(item_data.get("value", 0)) <= 0:
		warnings.append("%s: ammunition has no positive economy value." % prefix)


static func validate_ranged_weapon(
	item_data: Dictionary,
	prefix: String,
	items: Dictionary,
	referenced_ammunition: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if EquipmentCatalog.equipment_slot(item_data) != "weapon":
		errors.append("%s: ranged equipment must use the weapon slot." % prefix)
	var data := ArsenalCatalog.ranged_data(item_data)
	var ammo_item_id := str(data.get("ammo_item_id", ""))
	if ammo_item_id.is_empty() or not items.has(ammo_item_id):
		errors.append("%s: ranged ammo_item_id '%s' does not exist." % [prefix, ammo_item_id])
	else:
		var ammo_data := ItemCatalog.item(items, ammo_item_id)
		if not ArsenalCatalog.is_ammunition(ammo_data):
			errors.append("%s: ammo_item_id '%s' is not ammunition." % [prefix, ammo_item_id])
		else:
			referenced_ammunition[ammo_item_id] = true
	validate_numeric_range(data, "magazine_size", 1.0, ArsenalCatalog.MAX_MAGAZINE_SIZE, prefix, errors)
	validate_numeric_range(data, "damage_bonus", 0.0, ArsenalCatalog.MAX_DAMAGE_BONUS, prefix, errors)
	validate_numeric_range(data, "projectile_speed", 1.0, ArsenalCatalog.MAX_PROJECTILE_SPEED, prefix, errors)
	validate_numeric_range(data, "projectile_range", 1.0, ArsenalCatalog.MAX_PROJECTILE_RANGE, prefix, errors)
	validate_numeric_range(data, "projectile_radius", 1.0, ArsenalCatalog.MAX_PROJECTILE_RADIUS, prefix, errors)
	validate_numeric_range(data, "fire_cooldown", 0.05, MAX_FIRE_COOLDOWN, prefix, errors)
	validate_numeric_range(data, "reload_time", 0.05, MAX_RELOAD_TIME, prefix, errors)
	validate_numeric_range(data, "knockback_distance", 0.0, ArsenalCatalog.MAX_KNOCKBACK, prefix, errors)
	validate_numeric_range(data, "muzzle_offset", 0.0, 64.0, prefix, errors)
	var color_text := str(data.get("projectile_color", ArsenalCatalog.DEFAULT_PROJECTILE_COLOR))
	if not Color.html_is_valid(color_text):
		errors.append("%s: ranged projectile_color is invalid." % prefix)
	if float(data.get("projectile_range", 0.0)) < 64.0:
		warnings.append("%s: projectile_range is very short for a ranged weapon." % prefix)


static func validate_enemy_ranged_attack(
	definition_data: Dictionary,
	prefix: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var value: Variant = definition_data.get("ranged_attack", {})
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be an object." % prefix)
		return
	var data: Dictionary = value
	validate_numeric_range(data, "projectile_speed", 1.0, ArsenalCatalog.MAX_PROJECTILE_SPEED, prefix, errors)
	validate_numeric_range(data, "projectile_range", 1.0, ArsenalCatalog.MAX_PROJECTILE_RANGE, prefix, errors)
	validate_numeric_range(data, "projectile_radius", 1.0, ArsenalCatalog.MAX_PROJECTILE_RADIUS, prefix, errors)
	validate_numeric_range(data, "knockback_distance", 0.0, ArsenalCatalog.MAX_KNOCKBACK, prefix, errors)
	var color_text := str(data.get("projectile_color", ArsenalCatalog.DEFAULT_ENEMY_PROJECTILE_COLOR))
	if not Color.html_is_valid(color_text):
		errors.append("%s: projectile_color is invalid." % prefix)
	var attack_radius := float(definition_data.get("attack_radius", 0.0))
	var projectile_range := float(data.get("projectile_range", 0.0))
	if attack_radius <= 32.0:
		warnings.append("%s: parent enemy attack_radius is too small to demonstrate ranged behaviour." % prefix)
	if attack_radius > projectile_range:
		errors.append("%s: parent enemy attack_radius exceeds projectile_range." % prefix)


static func validate_loaded_ammo(
	value: Variant,
	inventory_value: Variant,
	items: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("Save payload loaded_ammo must be an object.")
		return
	var inventory: Dictionary = inventory_value if typeof(inventory_value) == TYPE_DICTIONARY else {}
	for weapon_id_value in (value as Dictionary).keys():
		var weapon_id := str(weapon_id_value)
		var quantity_value: Variant = (value as Dictionary).get(weapon_id_value, 0)
		if typeof(quantity_value) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("Save loaded_ammo '%s' must be numeric." % weapon_id)
			continue
		var quantity := int(quantity_value)
		var weapon_data := ItemCatalog.item(items, weapon_id)
		if not ArsenalCatalog.is_ranged_weapon(weapon_data):
			errors.append("Save loaded_ammo references unknown ranged weapon '%s'." % weapon_id)
			continue
		if int(inventory.get(weapon_id, 0)) <= 0:
			errors.append("Save loaded_ammo weapon '%s' is not owned in inventory." % weapon_id)
		if quantity < 0 or quantity > ArsenalCatalog.magazine_size(weapon_data):
			errors.append(
				"Save loaded_ammo '%s' quantity %d exceeds its magazine size %d." % [
					weapon_id,
					quantity,
					ArsenalCatalog.magazine_size(weapon_data)
				]
			)


static func validate_numeric_range(
	data: Dictionary,
	field: String,
	minimum: float,
	maximum: float,
	prefix: String,
	errors: Array[String]
) -> void:
	var value: Variant = data.get(field)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: %s must be numeric." % [prefix, field])
		return
	var number := float(value)
	if number < minimum or number > maximum:
		errors.append("%s: %s must be between %.2f and %.2f." % [prefix, field, minimum, maximum])


static func make_report(
	errors: Array[String],
	warnings: Array[String],
	ammunition_count: int,
	ranged_weapon_count: int,
	ranged_enemy_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"ammunition_count": ammunition_count,
		"ranged_weapon_count": ranged_weapon_count,
		"ranged_enemy_count": ranged_enemy_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
