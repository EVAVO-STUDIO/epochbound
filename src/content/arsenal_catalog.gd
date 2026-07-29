@tool
extends RefCounted

const ItemCatalog = preload("res://src/content/item_catalog.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")

const DEFAULT_PROJECTILE_COLOR := "f2c66d"
const DEFAULT_ENEMY_PROJECTILE_COLOR := "e4674d"
const MAX_MAGAZINE_SIZE := 99
const MAX_PROJECTILE_SPEED := 2400.0
const MAX_PROJECTILE_RANGE := 2400.0
const MAX_PROJECTILE_RADIUS := 32.0
const MAX_DAMAGE_BONUS := 999
const MAX_KNOCKBACK := 256.0


static func ammunition_data(item_data: Dictionary) -> Dictionary:
	var value: Variant = item_data.get("ammunition", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func is_ammunition(item_data: Dictionary) -> bool:
	return ItemCatalog.item_kind(item_data) == "ammunition"


static func ammunition_damage_bonus(item_data: Dictionary) -> int:
	return maxi(0, int(ammunition_data(item_data).get("damage_bonus", 0)))


static func ammunition_knockback_bonus(item_data: Dictionary) -> float:
	return maxf(0.0, float(ammunition_data(item_data).get("knockback_bonus", 0.0)))


static func ammunition_color(item_data: Dictionary) -> Color:
	return Color.from_string(
		str(ammunition_data(item_data).get("projectile_color", DEFAULT_PROJECTILE_COLOR)),
		Color.from_string(DEFAULT_PROJECTILE_COLOR, Color.WHITE)
	)


static func ranged_data(item_data: Dictionary) -> Dictionary:
	var equipment := EquipmentCatalog.equipment_data(item_data)
	var value: Variant = equipment.get("ranged", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func is_ranged_weapon(item_data: Dictionary) -> bool:
	return ItemCatalog.item_kind(item_data) == "equipment" and not ranged_data(item_data).is_empty()


static func weapon_ammunition_id(item_data: Dictionary) -> String:
	return str(ranged_data(item_data).get("ammo_item_id", ""))


static func magazine_size(item_data: Dictionary) -> int:
	return clampi(int(ranged_data(item_data).get("magazine_size", 1)), 1, MAX_MAGAZINE_SIZE)


static func weapon_damage_bonus(item_data: Dictionary) -> int:
	return maxi(0, int(ranged_data(item_data).get("damage_bonus", 0)))


static func projectile_speed(item_data: Dictionary) -> float:
	return clampf(float(ranged_data(item_data).get("projectile_speed", 320.0)), 1.0, MAX_PROJECTILE_SPEED)


static func projectile_range(item_data: Dictionary) -> float:
	return clampf(float(ranged_data(item_data).get("projectile_range", 260.0)), 1.0, MAX_PROJECTILE_RANGE)


static func projectile_radius(item_data: Dictionary) -> float:
	return clampf(float(ranged_data(item_data).get("projectile_radius", 4.0)), 1.0, MAX_PROJECTILE_RADIUS)


static func fire_cooldown(item_data: Dictionary) -> float:
	return maxf(0.05, float(ranged_data(item_data).get("fire_cooldown", 0.42)))


static func reload_time(item_data: Dictionary) -> float:
	return maxf(0.05, float(ranged_data(item_data).get("reload_time", 0.85)))


static func weapon_knockback(item_data: Dictionary) -> float:
	return clampf(float(ranged_data(item_data).get("knockback_distance", 14.0)), 0.0, MAX_KNOCKBACK)


static func muzzle_offset(item_data: Dictionary) -> float:
	return clampf(float(ranged_data(item_data).get("muzzle_offset", 15.0)), 0.0, 64.0)


static func weapon_projectile_color(item_data: Dictionary, ammo_data: Dictionary = {}) -> Color:
	if not ammo_data.is_empty():
		var ammunition_record := ammunition_data(ammo_data)
		if ammunition_record.has("projectile_color"):
			return ammunition_color(ammo_data)
	return Color.from_string(
		str(ranged_data(item_data).get("projectile_color", DEFAULT_PROJECTILE_COLOR)),
		Color.from_string(DEFAULT_PROJECTILE_COLOR, Color.WHITE)
	)


static func enemy_ranged_data(definition_data: Dictionary) -> Dictionary:
	var value: Variant = definition_data.get("ranged_attack", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func is_ranged_enemy(definition_data: Dictionary) -> bool:
	return str(definition_data.get("kind", "")) == "enemy" and not enemy_ranged_data(definition_data).is_empty()


static func enemy_projectile_speed(definition_data: Dictionary) -> float:
	return clampf(float(enemy_ranged_data(definition_data).get("projectile_speed", 210.0)), 1.0, MAX_PROJECTILE_SPEED)


static func enemy_projectile_range(definition_data: Dictionary) -> float:
	return clampf(float(enemy_ranged_data(definition_data).get("projectile_range", 220.0)), 1.0, MAX_PROJECTILE_RANGE)


static func enemy_projectile_radius(definition_data: Dictionary) -> float:
	return clampf(float(enemy_ranged_data(definition_data).get("projectile_radius", 4.0)), 1.0, MAX_PROJECTILE_RADIUS)


static func enemy_projectile_knockback(definition_data: Dictionary) -> float:
	return clampf(float(enemy_ranged_data(definition_data).get("knockback_distance", 18.0)), 0.0, MAX_KNOCKBACK)


static func enemy_projectile_color(definition_data: Dictionary) -> Color:
	return Color.from_string(
		str(enemy_ranged_data(definition_data).get("projectile_color", DEFAULT_ENEMY_PROJECTILE_COLOR)),
		Color.from_string(DEFAULT_ENEMY_PROJECTILE_COLOR, Color.WHITE)
	)


static func ranged_weapon_ids(item_definitions: Dictionary) -> PackedStringArray:
	var ids: Array[String] = []
	for item_id_value in item_definitions.keys():
		var item_id := str(item_id_value)
		if is_ranged_weapon(ItemCatalog.item(item_definitions, item_id)):
			ids.append(item_id)
	ids.sort_custom(func(left: String, right: String) -> bool:
		return ItemCatalog.item_name(ItemCatalog.item(item_definitions, left), left).naturalnocasecmp_to(
			ItemCatalog.item_name(ItemCatalog.item(item_definitions, right), right)
		) < 0
	)
	return PackedStringArray(ids)


static func ammunition_ids(item_definitions: Dictionary) -> PackedStringArray:
	var ids: Array[String] = []
	for item_id_value in item_definitions.keys():
		var item_id := str(item_id_value)
		if is_ammunition(ItemCatalog.item(item_definitions, item_id)):
			ids.append(item_id)
	ids.sort_custom(func(left: String, right: String) -> bool:
		return ItemCatalog.item_name(ItemCatalog.item(item_definitions, left), left).naturalnocasecmp_to(
			ItemCatalog.item_name(ItemCatalog.item(item_definitions, right), right)
		) < 0
	)
	return PackedStringArray(ids)


static func loaded_rounds(loaded_ammo: Dictionary, weapon_id: String) -> int:
	return maxi(0, int(loaded_ammo.get(weapon_id, 0)))


static func sanitize_loaded_ammo(
	requested: Variant,
	inventory: Dictionary,
	item_definitions: Dictionary
) -> Dictionary:
	var output: Dictionary = {}
	if typeof(requested) != TYPE_DICTIONARY:
		return output
	var keys: Array[String] = []
	for key_value in (requested as Dictionary).keys():
		keys.append(str(key_value))
	keys.sort()
	for weapon_id in keys:
		var weapon_data := ItemCatalog.item(item_definitions, weapon_id)
		if not is_ranged_weapon(weapon_data):
			continue
		if InventoryModel.count(inventory, weapon_id) <= 0:
			continue
		var quantity := clampi(int((requested as Dictionary).get(weapon_id, 0)), 0, magazine_size(weapon_data))
		if quantity > 0:
			output[weapon_id] = quantity
	return output


static func default_ammunition(item_id: String, display_name: String) -> Dictionary:
	return {
		"id": item_id,
		"display_name": display_name,
		"kind": "ammunition",
		"description": "Describe this original ammunition type and where it is found.",
		"stack_limit": 60,
		"value": 2,
		"use_effect": {"type": "none"},
		"ammunition": {
			"damage_bonus": 0,
			"knockback_bonus": 0.0,
			"projectile_color": DEFAULT_PROJECTILE_COLOR
		}
	}


static func default_ranged_equipment(ammo_item_id: String) -> Dictionary:
	var equipment := EquipmentCatalog.default_equipment("weapon")
	equipment["ranged"] = {
		"ammo_item_id": ammo_item_id,
		"magazine_size": 4,
		"damage_bonus": 1,
		"projectile_speed": 340.0,
		"projectile_range": 270.0,
		"projectile_radius": 4.0,
		"fire_cooldown": 0.42,
		"reload_time": 0.85,
		"knockback_distance": 14.0,
		"muzzle_offset": 15.0,
		"projectile_color": DEFAULT_PROJECTILE_COLOR
	}
	return equipment


static func default_enemy_ranged_attack() -> Dictionary:
	return {
		"projectile_speed": 210.0,
		"projectile_range": 220.0,
		"projectile_radius": 4.0,
		"knockback_distance": 18.0,
		"projectile_color": DEFAULT_ENEMY_PROJECTILE_COLOR
	}
