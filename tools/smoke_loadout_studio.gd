extends SceneTree

const LoadoutStudio = preload("res://addons/epochbound_loadout_studio/loadout_studio.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var studio := LoadoutStudio.new()
	root.add_child(studio)
	var campaign_selector_value: Variant = studio.get("campaign_selector")
	var equipment_list_value: Variant = studio.get("equipment_list")
	var capability_list_value: Variant = studio.get("capability_list")
	var slot_lines_value: Variant = studio.get("slot_lines_edit")
	var starting_equipment_value: Variant = studio.get("starting_equipment_edit")
	var gate_map_selector_value: Variant = studio.get("gate_map_selector")
	var gate_record_selector_value: Variant = studio.get("gate_record_selector")
	var gate_capability_list_value: Variant = studio.get("gate_capability_list")
	var gate_dialogue_value: Variant = studio.get("gate_blocked_dialogue")
	check(campaign_selector_value is OptionButton, "Loadout Studio must create a campaign selector.")
	check(equipment_list_value is ItemList, "Loadout Studio must create an equipment list.")
	check(capability_list_value is ItemList, "Loadout Studio must create a capability list.")
	check(slot_lines_value is TextEdit, "Loadout Studio must create campaign slot source fields.")
	check(starting_equipment_value is TextEdit, "Loadout Studio must create starting-equipment source fields.")
	check(gate_map_selector_value is OptionButton, "Loadout Studio must create a gate map selector.")
	check(gate_record_selector_value is OptionButton, "Loadout Studio must create a gate record selector.")
	check(gate_capability_list_value is ItemList, "Loadout Studio must create a gate capability list.")
	check(gate_dialogue_value is TextEdit, "Loadout Studio must create a blocked-dialogue field.")
	if campaign_selector_value is OptionButton:
		check((campaign_selector_value as OptionButton).item_count >= 1, "Loadout Studio must discover the reference campaign.")
	if equipment_list_value is ItemList:
		check((equipment_list_value as ItemList).item_count == 6, "Reference campaign must expose six equipment items in the editor.")
	if capability_list_value is ItemList:
		check((capability_list_value as ItemList).item_count == 3, "Reference campaign must expose three capability definitions in the editor.")
	if slot_lines_value is TextEdit:
		check("weapon = Weapon" in (slot_lines_value as TextEdit).text, "Campaign form must expose the authored Weapon slot.")
		check("tool = Tool" in (slot_lines_value as TextEdit).text, "Campaign form must expose the authored Tool slot.")
	if starting_equipment_value is TextEdit:
		check("weapon = brass_hook" in (starting_equipment_value as TextEdit).text, "Campaign form must expose starting weapon equipment.")
		check("tool = museum_flashlight" in (starting_equipment_value as TextEdit).text, "Campaign form must expose starting tool equipment.")
	if gate_map_selector_value is OptionButton:
		check((gate_map_selector_value as OptionButton).item_count == 4, "Gate editor must discover all four reference maps.")

	studio.call("select_equipment_id", "museum_coat")
	check(str(studio.get("selected_equipment_id")) == "museum_coat", "Equipment form must select a stable item ID.")
	var equipment_health_value: Variant = studio.get("equipment_health")
	if equipment_health_value is SpinBox:
		check(int((equipment_health_value as SpinBox).value) == 4, "Equipment form must expose the authored maximum-health bonus.")
	var equipment_caps_value: Variant = studio.get("equipment_capability_list")
	if equipment_caps_value is ItemList:
		check((equipment_caps_value as ItemList).item_count == 3, "Equipment form must expose every capability option.")

	studio.call("select_capability_id", "clockglass_sight")
	check(str(studio.get("selected_capability_id")) == "clockglass_sight", "Capability form must select a stable capability ID.")
	var capability_name_value: Variant = studio.get("capability_name_edit")
	if capability_name_value is LineEdit:
		check((capability_name_value as LineEdit).text == "Clockglass Sight", "Capability form must preserve the authored display name.")

	studio.call("select_gate_record", "bellweather_crossing", "connections", "stairs_to_underworks")
	var selected_gate: Dictionary = studio.call("selected_gate_record")
	check(str(selected_gate.get("id", "")) == "stairs_to_underworks", "Gate editor must select the authored Underworks connection.")
	check(EquipmentCatalog.required_capabilities(selected_gate).has("illuminate_dark"), "Gate editor must preserve the Underworks light requirement.")
	if gate_dialogue_value is TextEdit:
		check("dark" in (gate_dialogue_value as TextEdit).text.to_lower(), "Gate editor must expose player-facing blocked dialogue.")

	var valid_parse: Dictionary = LoadoutStudio.parse_assignment_lines("weapon = Weapon\nbody = Body", "slots")
	check(bool(valid_parse.get("ok", false)), "Assignment parser must accept valid slot records.")
	check((valid_parse.get("entries", []) as Array).size() == 2, "Assignment parser must retain every valid row.")
	var invalid_parse: Dictionary = LoadoutStudio.parse_assignment_lines("weapon Weapon\nweapon = Duplicate", "slots")
	check(not bool(invalid_parse.get("ok", true)), "Assignment parser must reject malformed rows.")
	check(not (invalid_parse.get("errors", []) as Array).is_empty(), "Malformed assignment input must return actionable errors.")

	root.remove_child(studio)
	studio.free()
	finish()


func finish() -> void:
	if failures.is_empty():
		print("Loadout Studio smoke test passed: campaigns, gear, capabilities, loadouts, gates and source parsing are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
