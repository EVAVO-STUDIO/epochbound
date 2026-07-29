extends SceneTree

const ArsenalStudio = preload("res://addons/epochbound_arsenal_studio/arsenal_studio.gd")
const ArsenalCatalog = preload("res://src/content/arsenal_catalog.gd")
const Repository = preload("res://src/content/campaign_repository.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var studio := ArsenalStudio.new()
	root.add_child(studio)
	var campaign_selector_value: Variant = studio.get("campaign_selector")
	var weapon_list_value: Variant = studio.get("weapon_list")
	var ammunition_list_value: Variant = studio.get("ammunition_list")
	var enemy_list_value: Variant = studio.get("enemy_list")
	var weapon_ammo_selector_value: Variant = studio.get("weapon_ammo_selector")
	check(campaign_selector_value is OptionButton, "Arsenal Studio must create a campaign selector.")
	check(weapon_list_value is ItemList, "Arsenal Studio must create a ranged weapon list.")
	check(ammunition_list_value is ItemList, "Arsenal Studio must create an ammunition list.")
	check(enemy_list_value is ItemList, "Arsenal Studio must create an enemy list.")
	check(weapon_ammo_selector_value is OptionButton, "Arsenal Studio must create an ammunition selector.")
	if campaign_selector_value is OptionButton:
		check((campaign_selector_value as OptionButton).item_count >= 1, "Arsenal Studio must discover the reference campaign.")
	if weapon_list_value is ItemList:
		check((weapon_list_value as ItemList).item_count == 1, "Reference campaign must expose one ranged weapon in Arsenal Studio.")
	if ammunition_list_value is ItemList:
		check((ammunition_list_value as ItemList).item_count == 1, "Reference campaign must expose one ammunition type in Arsenal Studio.")
	if enemy_list_value is ItemList:
		check((enemy_list_value as ItemList).item_count == 2, "Arsenal Studio must expose both reference enemy definitions.")
	if weapon_ammo_selector_value is OptionButton:
		check((weapon_ammo_selector_value as OptionButton).item_count == 1, "Weapon form must expose the authored ammunition option.")

	studio.call("select_weapon_id", "clockglass_dartcaster")
	check(str(studio.get("selected_weapon_id")) == "clockglass_dartcaster", "Weapon form must select a stable ranged item ID.")
	var magazine_value: Variant = studio.get("weapon_magazine")
	var reload_value: Variant = studio.get("weapon_reload")
	var weapon_color_value: Variant = studio.get("weapon_color")
	if magazine_value is SpinBox:
		check(int((magazine_value as SpinBox).value) == 4, "Weapon form must preserve the authored four-round magazine.")
	if reload_value is SpinBox:
		check(is_equal_approx(float((reload_value as SpinBox).value), 0.85), "Weapon form must preserve authored reload timing.")
	if weapon_color_value is LineEdit:
		check(Color.html_is_valid((weapon_color_value as LineEdit).text), "Weapon form must expose a valid projectile colour.")

	studio.call("select_ammunition_id", "archive_bolts")
	check(str(studio.get("selected_ammunition_id")) == "archive_bolts", "Ammunition form must select a stable item ID.")
	var stack_value: Variant = studio.get("ammunition_stack")
	if stack_value is SpinBox:
		check(int((stack_value as SpinBox).value) == 60, "Ammunition form must preserve the authored stack limit.")

	studio.call("select_enemy_id", "underworks_sentinel")
	check(str(studio.get("selected_enemy_id")) == "underworks_sentinel", "Enemy form must select the authored ranged enemy.")
	var enabled_value: Variant = studio.get("enemy_ranged_enabled")
	var range_value: Variant = studio.get("enemy_projectile_range")
	if enabled_value is CheckBox:
		check((enabled_value as CheckBox).button_pressed, "Underworks Sentinel must expose its ranged profile.")
	if range_value is SpinBox:
		check(float((range_value as SpinBox).value) == 240.0, "Enemy form must preserve its projectile range.")

	# Invalid item edits must restore both the file and in-memory catalogue.
	var item_path := str(studio.get("active_item_path"))
	var valid_item_read := Repository.read_json(item_path)
	check(bool(valid_item_read.get("ok", false)), "Arsenal rollback test must read the valid item catalogue.")
	var invalid_items: Dictionary = (studio.get("active_item_catalog") as Dictionary).duplicate(true)
	for index in range((invalid_items.get("items", []) as Array).size()):
		var candidate: Dictionary = (invalid_items.get("items", []) as Array)[index]
		if str(candidate.get("id", "")) == "clockglass_dartcaster":
			var equipment: Dictionary = candidate.get("equipment", {})
			var ranged: Dictionary = equipment.get("ranged", {})
			ranged["ammo_item_id"] = "missing_ammunition"
			equipment["ranged"] = ranged
			candidate["equipment"] = equipment
			(invalid_items.get("items", []) as Array)[index] = candidate
	studio.set("active_item_catalog", invalid_items)
	check(not bool(studio.call("save_item_catalog")), "Invalid ranged item edit must be rejected.")
	var restored_item_read := Repository.read_json(item_path)
	check(bool(restored_item_read.get("ok", false)), "Rejected item edit must leave a readable catalogue.")
	var restored_item_catalog: Dictionary = restored_item_read.get("data", {})
	var restored_ammo_id := ""
	for record_value in restored_item_catalog.get("items", []):
		if typeof(record_value) == TYPE_DICTIONARY and str((record_value as Dictionary).get("id", "")) == "clockglass_dartcaster":
			restored_ammo_id = str((((record_value as Dictionary).get("equipment", {}) as Dictionary).get("ranged", {}) as Dictionary).get("ammo_item_id", ""))
	check(restored_ammo_id == "archive_bolts", "Invalid ranged item edit must restore the prior ammunition reference.")

	# Invalid enemy profiles receive the same transactional rollback.
	var object_path := str(studio.get("active_object_path"))
	var invalid_objects: Dictionary = (studio.get("active_object_catalog") as Dictionary).duplicate(true)
	for index in range((invalid_objects.get("objects", []) as Array).size()):
		var candidate: Dictionary = (invalid_objects.get("objects", []) as Array)[index]
		if str(candidate.get("id", "")) == "underworks_sentinel":
			candidate["attack_radius"] = 500
			(invalid_objects.get("objects", []) as Array)[index] = candidate
	studio.set("active_object_catalog", invalid_objects)
	check(not bool(studio.call("save_object_catalog")), "Invalid ranged enemy edit must be rejected.")
	var restored_object_read := Repository.read_json(object_path)
	check(bool(restored_object_read.get("ok", false)), "Rejected enemy edit must leave a readable catalogue.")
	var restored_attack_radius := 0.0
	for record_value in (restored_object_read.get("data", {}) as Dictionary).get("objects", []):
		if typeof(record_value) == TYPE_DICTIONARY and str((record_value as Dictionary).get("id", "")) == "underworks_sentinel":
			restored_attack_radius = float((record_value as Dictionary).get("attack_radius", 0.0))
	check(restored_attack_radius == 160.0, "Invalid enemy edit must restore the prior attack radius.")

	var default_ammo := ArsenalCatalog.default_ammunition("test_bolts", "Test Bolts")
	check(ArsenalCatalog.is_ammunition(default_ammo), "Default ammunition helper must create a valid ammunition item.")
	var default_equipment := ArsenalCatalog.default_ranged_equipment("test_bolts")
	check(str((default_equipment.get("ranged", {}) as Dictionary).get("ammo_item_id", "")) == "test_bolts", "Default ranged equipment must preserve its ammunition reference.")

	root.remove_child(studio)
	studio.free()
	finish()


func finish() -> void:
	if failures.is_empty():
		print("Arsenal Studio smoke test passed: campaigns, weapons, ammunition, enemy projectiles and editor forms are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
