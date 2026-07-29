@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const EquipmentValidator = preload("res://src/content/equipment_validator.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_campaign_path := ""
var active_item_catalog: Dictionary = {}
var active_item_catalog_path := ""
var active_capability_catalog: Dictionary = {}
var active_capability_catalog_path := ""
var item_definitions: Dictionary = {}
var capability_definitions: Dictionary = {}
var recipe_definitions: Dictionary = {}
var story_definitions: Dictionary = {}
var map_records: Dictionary = {}
var selected_equipment_id := ""
var selected_capability_id := ""

var campaign_selector: OptionButton
var status_label: RichTextLabel

var equipment_list: ItemList
var new_equipment_id: LineEdit
var equipment_id_label: Label
var equipment_name_edit: LineEdit
var equipment_description_edit: TextEdit
var equipment_slot_selector: OptionButton
var equipment_attack: SpinBox
var equipment_defense: SpinBox
var equipment_health: SpinBox
var equipment_speed: SpinBox
var equipment_capability_list: ItemList
var equipment_apply_button: Button
var equipment_delete_button: Button

var capability_list: ItemList
var new_capability_id: LineEdit
var capability_id_label: Label
var capability_name_edit: LineEdit
var capability_description_edit: TextEdit
var capability_apply_button: Button
var capability_delete_button: Button

var slot_lines_edit: TextEdit
var starting_equipment_edit: TextEdit
var base_capability_list: ItemList

var gate_map_selector: OptionButton
var gate_kind_selector: OptionButton
var gate_record_selector: OptionButton
var gate_capability_list: ItemList
var gate_blocked_dialogue: TextEdit
var gate_apply_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_ui()
	refresh_campaigns()


func build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 7)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Epochbound Loadout Studio"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(make_button("Refresh", refresh_campaigns))
	header.add_child(make_button("Validate All", validate_all_campaigns))
	header.add_child(make_button("Open Campaign Folder", open_campaign_folder))

	var campaign_row := HBoxContainer.new()
	root.add_child(campaign_row)
	campaign_row.add_child(make_heading("CAMPAIGN"))
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 300
	campaign_selector.item_selected.connect(on_campaign_selected)
	campaign_row.add_child(campaign_selector)
	var hint := Label.new()
	hint.text = "Equipment stays in Item Forge inventory; this tool authors loadout, modifiers and capabilities."
	hint.modulate = Color("87949b")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_row.add_child(hint)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	build_equipment_tab(tabs)
	build_capabilities_tab(tabs)
	build_campaign_tab(tabs)
	build_gates_tab(tabs)

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 62
	status_label.text = "[color=#9aa8b5]Loadout Studio ready.[/color]"
	root.add_child(status_label)


func build_equipment_tab(tabs: TabContainer) -> void:
	var split := HSplitContainer.new()
	split.name = "Equipment"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	left.add_theme_constant_override("separation", 5)
	split.add_child(left)
	left.add_child(make_heading("EQUIPMENT ITEMS"))
	equipment_list = ItemList.new()
	equipment_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipment_list.item_selected.connect(select_equipment_item)
	left.add_child(equipment_list)
	var add_row := HBoxContainer.new()
	left.add_child(add_row)
	new_equipment_id = LineEdit.new()
	new_equipment_id.placeholder_text = "new_equipment_id"
	new_equipment_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(new_equipment_id)
	add_row.add_child(make_button("Add", create_equipment_item))

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 500
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	right_scroll.add_child(right)
	right.add_child(make_heading("EQUIPMENT DEFINITION"))
	equipment_id_label = Label.new()
	equipment_id_label.text = "No equipment selected"
	equipment_id_label.modulate = Color("8fa9a5")
	right.add_child(equipment_id_label)
	right.add_child(make_field_label("Display name"))
	equipment_name_edit = LineEdit.new()
	right.add_child(equipment_name_edit)
	right.add_child(make_field_label("Description"))
	equipment_description_edit = TextEdit.new()
	equipment_description_edit.custom_minimum_size.y = 86
	equipment_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right.add_child(equipment_description_edit)
	right.add_child(make_field_label("Equipment slot"))
	equipment_slot_selector = OptionButton.new()
	right.add_child(equipment_slot_selector)
	var stats := GridContainer.new()
	stats.columns = 2
	right.add_child(stats)
	equipment_attack = make_spin(0, 999, 1, 0)
	equipment_defense = make_spin(0, 999, 1, 0)
	equipment_health = make_spin(0, 999, 1, 0)
	equipment_speed = make_spin(0, 300, 1, 0)
	stats.add_child(make_labeled_control("Attack bonus", equipment_attack))
	stats.add_child(make_labeled_control("Defense bonus", equipment_defense))
	stats.add_child(make_labeled_control("Maximum-health bonus", equipment_health))
	stats.add_child(make_labeled_control("Movement-speed bonus", equipment_speed))
	right.add_child(make_field_label("Granted capabilities"))
	equipment_capability_list = ItemList.new()
	equipment_capability_list.select_mode = ItemList.SELECT_MULTI
	equipment_capability_list.custom_minimum_size.y = 150
	right.add_child(equipment_capability_list)
	var action_row := HBoxContainer.new()
	right.add_child(action_row)
	equipment_apply_button = make_button("Apply Equipment", apply_equipment_item)
	equipment_delete_button = make_button("Delete Equipment", delete_equipment_item)
	action_row.add_child(equipment_apply_button)
	action_row.add_child(equipment_delete_button)
	set_equipment_form_enabled(false)


func build_capabilities_tab(tabs: TabContainer) -> void:
	var split := HSplitContainer.new()
	split.name = "Capabilities"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	left.add_theme_constant_override("separation", 5)
	split.add_child(left)
	left.add_child(make_heading("CAPABILITY DEFINITIONS"))
	capability_list = ItemList.new()
	capability_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	capability_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	capability_list.item_selected.connect(select_capability)
	left.add_child(capability_list)
	var add_row := HBoxContainer.new()
	left.add_child(add_row)
	new_capability_id = LineEdit.new()
	new_capability_id.placeholder_text = "new_capability_id"
	new_capability_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(new_capability_id)
	add_row.add_child(make_button("Add", create_capability))

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 500
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	split.add_child(right)
	right.add_child(make_heading("CAPABILITY DEFINITION"))
	capability_id_label = Label.new()
	capability_id_label.text = "No capability selected"
	capability_id_label.modulate = Color("8fa9a5")
	right.add_child(capability_id_label)
	right.add_child(make_field_label("Display name"))
	capability_name_edit = LineEdit.new()
	right.add_child(capability_name_edit)
	right.add_child(make_field_label("Player-facing production description"))
	capability_description_edit = TextEdit.new()
	capability_description_edit.custom_minimum_size.y = 160
	capability_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right.add_child(capability_description_edit)
	var action_row := HBoxContainer.new()
	right.add_child(action_row)
	capability_apply_button = make_button("Apply Capability", apply_capability)
	capability_delete_button = make_button("Delete Capability", delete_capability)
	action_row.add_child(capability_apply_button)
	action_row.add_child(capability_delete_button)
	set_capability_form_enabled(false)


func build_campaign_tab(tabs: TabContainer) -> void:
	var panel := VBoxContainer.new()
	panel.name = "Campaign Loadout"
	panel.add_theme_constant_override("separation", 6)
	tabs.add_child(panel)
	panel.add_child(make_heading("CAMPAIGN EQUIPMENT SLOTS"))
	var slot_help := Label.new()
	slot_help.text = "One per line: slot_id = Display Name"
	slot_help.modulate = Color("87949b")
	panel.add_child(slot_help)
	slot_lines_edit = TextEdit.new()
	slot_lines_edit.custom_minimum_size.y = 120
	panel.add_child(slot_lines_edit)
	panel.add_child(make_heading("STARTING EQUIPMENT"))
	var start_help := Label.new()
	start_help.text = "One per line: slot_id = item_id. The item must also exist in starting inventory."
	start_help.modulate = Color("87949b")
	panel.add_child(start_help)
	starting_equipment_edit = TextEdit.new()
	starting_equipment_edit.custom_minimum_size.y = 120
	panel.add_child(starting_equipment_edit)
	panel.add_child(make_heading("BASE CAPABILITIES"))
	base_capability_list = ItemList.new()
	base_capability_list.select_mode = ItemList.SELECT_MULTI
	base_capability_list.custom_minimum_size.y = 150
	panel.add_child(base_capability_list)
	panel.add_child(make_button("Apply Campaign Loadout", apply_campaign_loadout))


func build_gates_tab(tabs: TabContainer) -> void:
	var panel := VBoxContainer.new()
	panel.name = "Capability Gates"
	panel.add_theme_constant_override("separation", 6)
	tabs.add_child(panel)
	var selectors := HBoxContainer.new()
	panel.add_child(selectors)
	selectors.add_child(make_heading("MAP"))
	gate_map_selector = OptionButton.new()
	gate_map_selector.custom_minimum_size.x = 240
	gate_map_selector.item_selected.connect(on_gate_map_selected)
	selectors.add_child(gate_map_selector)
	selectors.add_child(make_heading("RECORD TYPE"))
	gate_kind_selector = OptionButton.new()
	gate_kind_selector.add_item("Connections")
	gate_kind_selector.set_item_metadata(0, "connections")
	gate_kind_selector.add_item("Interactions")
	gate_kind_selector.set_item_metadata(1, "interactions")
	gate_kind_selector.item_selected.connect(on_gate_kind_selected)
	selectors.add_child(gate_kind_selector)
	selectors.add_child(make_heading("RECORD"))
	gate_record_selector = OptionButton.new()
	gate_record_selector.custom_minimum_size.x = 260
	gate_record_selector.item_selected.connect(on_gate_record_selected)
	selectors.add_child(gate_record_selector)
	panel.add_child(make_field_label("Required capabilities"))
	gate_capability_list = ItemList.new()
	gate_capability_list.select_mode = ItemList.SELECT_MULTI
	gate_capability_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gate_capability_list.custom_minimum_size.y = 190
	panel.add_child(gate_capability_list)
	panel.add_child(make_field_label("Blocked dialogue"))
	gate_blocked_dialogue = TextEdit.new()
	gate_blocked_dialogue.custom_minimum_size.y = 100
	gate_blocked_dialogue.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	panel.add_child(gate_blocked_dialogue)
	gate_apply_button = make_button("Apply Gate", apply_gate)
	panel.add_child(gate_apply_button)
	gate_apply_button.disabled = true


func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func make_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color("e0c16c")
	return label


func make_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color("aeb8c2")
	return label


func make_spin(minimum: float, maximum: float, step: float, initial: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func make_labeled_control(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(make_field_label(text))
	box.add_child(control)
	return box


func refresh_campaigns(preferred_id: String = "") -> void:
	campaigns = Repository.scan_campaigns()
	campaign_selector.clear()
	var selected_index := 0
	for index in range(campaigns.size()):
		var entry: Dictionary = campaigns[index]
		campaign_selector.add_item(str(entry.get("title", entry.get("id", "Campaign"))))
		campaign_selector.set_item_metadata(index, str(entry.get("path", "")))
		if str(entry.get("id", "")) == preferred_id:
			selected_index = index
	if campaigns.is_empty():
		clear_all()
		set_status("No source campaigns were found under res://campaigns.", true)
		return
	campaign_selector.select(selected_index)
	on_campaign_selected(selected_index)


func on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = str(campaign_selector.get_item_metadata(index))
	var result: Dictionary = Repository.read_json(active_campaign_path)
	if not bool(result.get("ok", false)):
		clear_all()
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	load_catalogs()
	load_maps()
	refresh_all_forms()
	var report: Dictionary = EquipmentValidator.validate_campaign_path(active_campaign_path)
	set_status(format_report(report), not bool(report.get("ok", false)))


func load_catalogs() -> void:
	var item_result: Dictionary = ItemCatalog.load_item_catalogs(active_campaign_path, active_campaign)
	item_definitions = item_result.get("definitions", {})
	var item_files: Array = item_result.get("files", [])
	if item_files.is_empty():
		active_item_catalog_path = ItemCatalog.primary_item_catalog_path(active_campaign_path, active_campaign)
		active_item_catalog = ItemCatalog.default_item_catalog()
	else:
		var item_file: Dictionary = item_files[0]
		active_item_catalog_path = str(item_file.get("path", ""))
		active_item_catalog = item_file.get("data", {})
	var capability_result: Dictionary = EquipmentCatalog.load_capability_catalogs(active_campaign_path, active_campaign)
	capability_definitions = capability_result.get("definitions", {})
	var capability_files: Array = capability_result.get("files", [])
	if capability_files.is_empty():
		active_capability_catalog_path = EquipmentCatalog.primary_capability_catalog_path(active_campaign_path, active_campaign)
		active_capability_catalog = EquipmentCatalog.default_capability_catalog()
	else:
		var capability_file: Dictionary = capability_files[0]
		active_capability_catalog_path = str(capability_file.get("path", ""))
		active_capability_catalog = capability_file.get("data", {})
	var recipe_result: Dictionary = ItemCatalog.load_recipe_catalogs(active_campaign_path, active_campaign)
	recipe_definitions = recipe_result.get("definitions", {})
	var story_result: Dictionary = StoryCatalog.load_catalogs(active_campaign_path, active_campaign)
	story_definitions = {
		"conversations": story_result.get("conversations", {}),
		"quests": story_result.get("quests", {})
	}


func rebuild_definitions() -> void:
	load_catalogs()


func load_maps() -> void:
	map_records = {}
	var value: Variant = active_campaign.get("map_files", [])
	if typeof(value) != TYPE_ARRAY:
		return
	for relative_value in value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			continue
		var path := active_campaign_path.get_base_dir().path_join(relative_path)
		var result: Dictionary = Repository.read_json(path)
		if not bool(result.get("ok", false)):
			continue
		var map_data: Dictionary = result.get("data", {})
		map_records[str(map_data.get("id", relative_path))] = {"path": path, "data": map_data}


func refresh_all_forms() -> void:
	refresh_equipment_list()
	refresh_capability_list()
	refresh_campaign_form()
	refresh_gate_selectors()


func refresh_equipment_list() -> void:
	equipment_list.clear()
	for item_id in EquipmentCatalog.equipment_item_ids(item_definitions):
		var data: Dictionary = ItemCatalog.item(item_definitions, item_id)
		var item_index := equipment_list.item_count
		equipment_list.add_item(ItemCatalog.item_name(data, item_id))
		equipment_list.set_item_metadata(item_index, item_id)
	populate_slot_selector()
	populate_capability_selector(equipment_capability_list)
	if not selected_equipment_id.is_empty():
		select_equipment_id(selected_equipment_id)
	else:
		clear_equipment_form()


func populate_slot_selector() -> void:
	var requested := selected_option_metadata(equipment_slot_selector)
	equipment_slot_selector.clear()
	for slot_id in EquipmentCatalog.slot_ids(active_campaign):
		var index := equipment_slot_selector.item_count
		equipment_slot_selector.add_item(EquipmentCatalog.slot_name(active_campaign, slot_id))
		equipment_slot_selector.set_item_metadata(index, slot_id)
	select_option_metadata(equipment_slot_selector, requested)


func populate_capability_selector(selector: ItemList) -> void:
	selector.clear()
	var ids: Array[String] = []
	for capability_id_value in capability_definitions.keys():
		ids.append(str(capability_id_value))
	ids.sort()
	for capability_id in ids:
		var index := selector.item_count
		selector.add_item(EquipmentCatalog.capability_name(capability_definitions, capability_id))
		selector.set_item_metadata(index, capability_id)


func select_equipment_item(index: int) -> void:
	if index < 0 or index >= equipment_list.item_count:
		return
	select_equipment_id(str(equipment_list.get_item_metadata(index)))


func select_equipment_id(item_id: String) -> void:
	var data: Dictionary = ItemCatalog.item(item_definitions, item_id)
	if data.is_empty() or ItemCatalog.item_kind(data) != "equipment":
		clear_equipment_form()
		return
	selected_equipment_id = item_id
	equipment_id_label.text = item_id
	equipment_name_edit.text = str(data.get("display_name", item_id))
	equipment_description_edit.text = str(data.get("description", ""))
	var equipment_data: Dictionary = EquipmentCatalog.equipment_data(data)
	select_option_metadata(equipment_slot_selector, str(equipment_data.get("slot", "")))
	equipment_attack.value = float(equipment_data.get("attack_bonus", 0))
	equipment_defense.value = float(equipment_data.get("defense_bonus", 0))
	equipment_health.value = float(equipment_data.get("max_health_bonus", 0))
	equipment_speed.value = float(equipment_data.get("move_speed_bonus", 0.0))
	equipment_capability_list.deselect_all()
	var selected_caps := EquipmentCatalog.granted_capabilities(data)
	for index in range(equipment_capability_list.item_count):
		if selected_caps.has(str(equipment_capability_list.get_item_metadata(index))):
			equipment_capability_list.select(index, false)
	set_equipment_form_enabled(true)
	for index in range(equipment_list.item_count):
		if str(equipment_list.get_item_metadata(index)) == item_id:
			equipment_list.select(index)
			break


func create_equipment_item() -> void:
	var item_id := Repository.normalise_id(new_equipment_id.text)
	if item_id.is_empty():
		set_status("Equipment ID must contain a letter or number.", true)
		return
	if item_definitions.has(item_id):
		set_status("Item '%s' already exists." % item_id, true)
		return
	var slots := EquipmentCatalog.slot_ids(active_campaign)
	if slots.is_empty():
		set_status("Define at least one campaign equipment slot first.", true)
		return
	var previous := active_item_catalog.duplicate(true)
	var items: Array = active_item_catalog.get("items", [])
	items.append({
		"id": item_id,
		"display_name": item_id.replace("_", " ").capitalize(),
		"kind": "equipment",
		"description": "An authored piece of equipment.",
		"stack_limit": 1,
		"value": 0,
		"use_effect": {"type": "none"},
		"equipment": EquipmentCatalog.default_equipment(str(slots[0]))
	})
	active_item_catalog["items"] = items
	if persist_with_rollback(active_item_catalog_path, active_item_catalog, previous):
		selected_equipment_id = item_id
		new_equipment_id.text = ""
		rebuild_definitions()
		refresh_all_forms()
		select_equipment_id(item_id)
		set_status("Created equipment '%s'." % item_id, false)


func apply_equipment_item() -> void:
	if selected_equipment_id.is_empty():
		return
	var slot_id := selected_option_metadata(equipment_slot_selector)
	if slot_id.is_empty():
		set_status("Equipment slot is required.", true)
		return
	var name := equipment_name_edit.text.strip_edges()
	if name.is_empty():
		set_status("Display name is required.", true)
		return
	var capabilities: Array = selected_item_metadata(equipment_capability_list)
	var previous := active_item_catalog.duplicate(true)
	var items: Array = active_item_catalog.get("items", [])
	var found := false
	for index in range(items.size()):
		if typeof(items[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = items[index]
		if str(data.get("id", "")) != selected_equipment_id:
			continue
		data["display_name"] = name
		data["kind"] = "equipment"
		data["description"] = equipment_description_edit.text.strip_edges()
		data["stack_limit"] = 1
		data["use_effect"] = {"type": "none"}
		data["equipment"] = {
			"slot": slot_id,
			"attack_bonus": int(equipment_attack.value),
			"defense_bonus": int(equipment_defense.value),
			"max_health_bonus": int(equipment_health.value),
			"move_speed_bonus": equipment_speed.value,
			"capabilities": capabilities
		}
		items[index] = data
		found = true
		break
	if not found:
		set_status("The selected equipment is in a read-only secondary item catalog.", true)
		return
	active_item_catalog["items"] = items
	if persist_with_rollback(active_item_catalog_path, active_item_catalog, previous):
		rebuild_definitions()
		refresh_all_forms()
		select_equipment_id(selected_equipment_id)
		set_status("Updated equipment '%s'." % selected_equipment_id, false)


func delete_equipment_item() -> void:
	if selected_equipment_id.is_empty():
		return
	var usages := find_item_usages(selected_equipment_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; used by %s." % [selected_equipment_id, ", ".join(usages)], true)
		return
	var previous := active_item_catalog.duplicate(true)
	var items: Array = active_item_catalog.get("items", [])
	var removed := false
	for index in range(items.size() - 1, -1, -1):
		if typeof(items[index]) == TYPE_DICTIONARY and str((items[index] as Dictionary).get("id", "")) == selected_equipment_id:
			items.remove_at(index)
			removed = true
			break
	if not removed:
		set_status("Equipment from secondary catalogs is read-only.", true)
		return
	var deleted_id := selected_equipment_id
	active_item_catalog["items"] = items
	if persist_with_rollback(active_item_catalog_path, active_item_catalog, previous):
		selected_equipment_id = ""
		rebuild_definitions()
		refresh_all_forms()
		set_status("Deleted equipment '%s'." % deleted_id, false)


func set_equipment_form_enabled(enabled: bool) -> void:
	equipment_name_edit.editable = enabled
	equipment_description_edit.editable = enabled
	equipment_slot_selector.disabled = not enabled
	equipment_attack.editable = enabled
	equipment_defense.editable = enabled
	equipment_health.editable = enabled
	equipment_speed.editable = enabled
	equipment_capability_list.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	equipment_apply_button.disabled = not enabled
	equipment_delete_button.disabled = not enabled


func clear_equipment_form() -> void:
	selected_equipment_id = ""
	equipment_id_label.text = "No equipment selected"
	equipment_name_edit.text = ""
	equipment_description_edit.text = ""
	equipment_attack.value = 0
	equipment_defense.value = 0
	equipment_health.value = 0
	equipment_speed.value = 0
	equipment_capability_list.deselect_all()
	set_equipment_form_enabled(false)


func refresh_capability_list() -> void:
	capability_list.clear()
	var ids: Array[String] = []
	for capability_id_value in capability_definitions.keys():
		ids.append(str(capability_id_value))
	ids.sort()
	for capability_id in ids:
		var index := capability_list.item_count
		capability_list.add_item(EquipmentCatalog.capability_name(capability_definitions, capability_id))
		capability_list.set_item_metadata(index, capability_id)
	populate_capability_selector(equipment_capability_list)
	populate_capability_selector(base_capability_list)
	populate_capability_selector(gate_capability_list)
	if not selected_capability_id.is_empty():
		select_capability_id(selected_capability_id)
	else:
		clear_capability_form()


func select_capability(index: int) -> void:
	if index < 0 or index >= capability_list.item_count:
		return
	select_capability_id(str(capability_list.get_item_metadata(index)))


func select_capability_id(capability_id: String) -> void:
	var data := EquipmentCatalog.capability(capability_definitions, capability_id)
	if data.is_empty():
		clear_capability_form()
		return
	selected_capability_id = capability_id
	capability_id_label.text = capability_id
	capability_name_edit.text = str(data.get("display_name", capability_id))
	capability_description_edit.text = str(data.get("description", ""))
	set_capability_form_enabled(true)
	for index in range(capability_list.item_count):
		if str(capability_list.get_item_metadata(index)) == capability_id:
			capability_list.select(index)
			break


func create_capability() -> void:
	var capability_id := Repository.normalise_id(new_capability_id.text)
	if capability_id.is_empty():
		set_status("Capability ID must contain a letter or number.", true)
		return
	if capability_definitions.has(capability_id):
		set_status("Capability '%s' already exists." % capability_id, true)
		return
	var previous := active_capability_catalog.duplicate(true)
	var records: Array = active_capability_catalog.get("capabilities", [])
	records.append(EquipmentCatalog.default_capability(capability_id, capability_id.replace("_", " ").capitalize(), "An authored gameplay capability."))
	active_capability_catalog["capabilities"] = records
	if persist_with_rollback(active_capability_catalog_path, active_capability_catalog, previous):
		selected_capability_id = capability_id
		new_capability_id.text = ""
		rebuild_definitions()
		refresh_all_forms()
		select_capability_id(capability_id)
		set_status("Created capability '%s'." % capability_id, false)


func apply_capability() -> void:
	if selected_capability_id.is_empty():
		return
	var name := capability_name_edit.text.strip_edges()
	if name.is_empty():
		set_status("Capability display name is required.", true)
		return
	var previous := active_capability_catalog.duplicate(true)
	var records: Array = active_capability_catalog.get("capabilities", [])
	var found := false
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = records[index]
		if str(data.get("id", "")) != selected_capability_id:
			continue
		data["display_name"] = name
		data["description"] = capability_description_edit.text.strip_edges()
		records[index] = data
		found = true
		break
	if not found:
		set_status("The selected capability is in a read-only secondary catalog.", true)
		return
	active_capability_catalog["capabilities"] = records
	if persist_with_rollback(active_capability_catalog_path, active_capability_catalog, previous):
		rebuild_definitions()
		refresh_all_forms()
		select_capability_id(selected_capability_id)
		set_status("Updated capability '%s'." % selected_capability_id, false)


func delete_capability() -> void:
	if selected_capability_id.is_empty():
		return
	var usages := find_capability_usages(selected_capability_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; used by %s." % [selected_capability_id, ", ".join(usages)], true)
		return
	var previous := active_capability_catalog.duplicate(true)
	var records: Array = active_capability_catalog.get("capabilities", [])
	var removed := false
	for index in range(records.size() - 1, -1, -1):
		if typeof(records[index]) == TYPE_DICTIONARY and str((records[index] as Dictionary).get("id", "")) == selected_capability_id:
			records.remove_at(index)
			removed = true
			break
	if not removed:
		set_status("Capabilities from secondary catalogs are read-only.", true)
		return
	var deleted_id := selected_capability_id
	active_capability_catalog["capabilities"] = records
	if persist_with_rollback(active_capability_catalog_path, active_capability_catalog, previous):
		selected_capability_id = ""
		rebuild_definitions()
		refresh_all_forms()
		set_status("Deleted capability '%s'." % deleted_id, false)


func set_capability_form_enabled(enabled: bool) -> void:
	capability_name_edit.editable = enabled
	capability_description_edit.editable = enabled
	capability_apply_button.disabled = not enabled
	capability_delete_button.disabled = not enabled


func clear_capability_form() -> void:
	selected_capability_id = ""
	capability_id_label.text = "No capability selected"
	capability_name_edit.text = ""
	capability_description_edit.text = ""
	set_capability_form_enabled(false)


func refresh_campaign_form() -> void:
	var slot_lines := PackedStringArray()
	for slot_value in EquipmentCatalog.slot_records(active_campaign):
		var slot_data: Dictionary = slot_value
		slot_lines.append("%s = %s" % [slot_data.get("id", ""), slot_data.get("display_name", "")])
	slot_lines_edit.text = "\n".join(slot_lines)
	var starting_lines := PackedStringArray()
	var starting := EquipmentCatalog.starting_equipment(active_campaign)
	for slot_id in EquipmentCatalog.slot_ids(active_campaign):
		var item_id := str(starting.get(slot_id, ""))
		if not item_id.is_empty():
			starting_lines.append("%s = %s" % [slot_id, item_id])
	starting_equipment_edit.text = "\n".join(starting_lines)
	base_capability_list.deselect_all()
	var base := EquipmentCatalog.base_capabilities(active_campaign)
	for index in range(base_capability_list.item_count):
		if base.has(str(base_capability_list.get_item_metadata(index))):
			base_capability_list.select(index, false)


func apply_campaign_loadout() -> void:
	var slot_result := parse_assignment_lines(slot_lines_edit.text, "equipment slots")
	if not bool(slot_result.get("ok", false)):
		set_status(format_messages(slot_result.get("errors", [])), true)
		return
	var slot_records: Array = []
	for entry_value in slot_result.get("entries", []):
		var entry: Dictionary = entry_value
		slot_records.append({"id": entry.get("key", ""), "display_name": entry.get("value", "")})
	if slot_records.is_empty():
		set_status("At least one equipment slot is required.", true)
		return
	var starting_result := parse_assignment_lines(starting_equipment_edit.text, "starting equipment")
	if not bool(starting_result.get("ok", false)):
		set_status(format_messages(starting_result.get("errors", [])), true)
		return
	var starting: Dictionary = {}
	for entry_value in starting_result.get("entries", []):
		var entry: Dictionary = entry_value
		starting[str(entry.get("key", ""))] = str(entry.get("value", ""))
	var base: Array = selected_item_metadata(base_capability_list)
	var previous := active_campaign.duplicate(true)
	active_campaign["equipment_slots"] = slot_records
	active_campaign["starting_equipment"] = starting
	active_campaign["base_capabilities"] = base
	if persist_with_rollback(active_campaign_path, active_campaign, previous):
		var campaign_id := str(active_campaign.get("id", ""))
		var result: Dictionary = Repository.read_json(active_campaign_path)
		active_campaign = result.get("data", active_campaign)
		load_catalogs()
		refresh_all_forms()
		set_status("Updated campaign loadout for '%s'." % campaign_id, false)


func refresh_gate_selectors() -> void:
	gate_map_selector.clear()
	var map_ids: Array[String] = []
	for map_id_value in map_records.keys():
		map_ids.append(str(map_id_value))
	map_ids.sort()
	for map_id in map_ids:
		var record: Dictionary = map_records.get(map_id, {})
		var map_data: Dictionary = record.get("data", {})
		var index := gate_map_selector.item_count
		gate_map_selector.add_item(str(map_data.get("display_name", map_id)))
		gate_map_selector.set_item_metadata(index, map_id)
	if gate_map_selector.item_count > 0:
		gate_map_selector.select(0)
	populate_gate_records()


func on_gate_map_selected(_index: int) -> void:
	populate_gate_records()


func on_gate_kind_selected(_index: int) -> void:
	populate_gate_records()


func populate_gate_records() -> void:
	gate_record_selector.clear()
	gate_capability_list.deselect_all()
	gate_blocked_dialogue.text = ""
	gate_apply_button.disabled = true
	if gate_map_selector.item_count == 0:
		return
	var map_id := str(gate_map_selector.get_item_metadata(gate_map_selector.selected))
	var map_record: Dictionary = map_records.get(map_id, {})
	var map_data: Dictionary = map_record.get("data", {})
	var field := selected_option_metadata(gate_kind_selector)
	var value: Variant = map_data.get(field, [])
	if typeof(value) != TYPE_ARRAY:
		return
	for record_value in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = record_value
		var record_id := str(data.get("id", field.trim_suffix("s")))
		var index := gate_record_selector.item_count
		gate_record_selector.add_item(record_id.replace("_", " ").capitalize())
		gate_record_selector.set_item_metadata(index, record_id)
	if gate_record_selector.item_count > 0:
		gate_record_selector.select(0)
		on_gate_record_selected(0)


func on_gate_record_selected(_index: int) -> void:
	var record := selected_gate_record()
	gate_capability_list.deselect_all()
	gate_blocked_dialogue.text = str(record.get("blocked_dialogue", ""))
	var required := EquipmentCatalog.required_capabilities(record)
	for index in range(gate_capability_list.item_count):
		if required.has(str(gate_capability_list.get_item_metadata(index))):
			gate_capability_list.select(index, false)
	gate_apply_button.disabled = record.is_empty()


func selected_gate_record() -> Dictionary:
	if gate_map_selector.item_count == 0 or gate_record_selector.item_count == 0:
		return {}
	var map_id := str(gate_map_selector.get_item_metadata(gate_map_selector.selected))
	var map_record: Dictionary = map_records.get(map_id, {})
	var map_data: Dictionary = map_record.get("data", {})
	var field := selected_option_metadata(gate_kind_selector)
	var requested_id := str(gate_record_selector.get_item_metadata(gate_record_selector.selected))
	for record_value in map_data.get(field, []):
		if typeof(record_value) == TYPE_DICTIONARY and str((record_value as Dictionary).get("id", "")) == requested_id:
			return record_value
	return {}


func apply_gate() -> void:
	if gate_map_selector.item_count == 0 or gate_record_selector.item_count == 0:
		return
	var map_id := str(gate_map_selector.get_item_metadata(gate_map_selector.selected))
	var map_record: Dictionary = map_records.get(map_id, {})
	var path := str(map_record.get("path", ""))
	var current_data: Dictionary = map_record.get("data", {})
	var previous := current_data.duplicate(true)
	var field := selected_option_metadata(gate_kind_selector)
	var requested_id := str(gate_record_selector.get_item_metadata(gate_record_selector.selected))
	var records: Array = current_data.get(field, [])
	var capabilities: Array = selected_item_metadata(gate_capability_list)
	var blocked := gate_blocked_dialogue.text.strip_edges()
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = records[index]
		if str(data.get("id", "")) != requested_id:
			continue
		if capabilities.is_empty():
			data.erase("required_capabilities")
		else:
			data["required_capabilities"] = capabilities
		data["blocked_dialogue"] = blocked
		records[index] = data
		break
	current_data[field] = records
	if persist_with_rollback(path, current_data, previous):
		load_maps()
		refresh_gate_selectors()
		select_gate_record(map_id, field, requested_id)
		set_status("Updated capability gate '%s'." % requested_id, false)


func select_gate_record(map_id: String, field: String, record_id: String) -> void:
	select_option_metadata(gate_map_selector, map_id)
	select_option_metadata(gate_kind_selector, field)
	populate_gate_records()
	select_option_metadata(gate_record_selector, record_id)
	on_gate_record_selected(gate_record_selector.selected)


func persist_with_rollback(path: String, data: Dictionary, previous: Dictionary) -> bool:
	var result: Dictionary = Repository.save_json(path, data)
	if not bool(result.get("ok", false)):
		set_status(format_messages(result.get("errors", [])), true)
		return false
	var report: Dictionary = EquipmentValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		Repository.save_json(path, previous)
		set_status("Change was rolled back. %s" % format_report(report), true)
		return false
	rescan_editor_files()
	return true


func find_item_usages(item_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	for entry_value in ItemCatalog.starting_inventory(active_campaign):
		var entry: Dictionary = entry_value
		if str(entry.get("item_id", "")) == item_id:
			usages.append("starting inventory")
	for slot_id in EquipmentCatalog.starting_equipment(active_campaign).keys():
		if str(EquipmentCatalog.starting_equipment(active_campaign).get(slot_id, "")) == item_id:
			usages.append("starting equipment")
	for recipe_id_value in recipe_definitions.keys():
		var recipe_id := str(recipe_id_value)
		var recipe_data := ItemCatalog.recipe(recipe_definitions, recipe_id)
		var output := InventoryModel.recipe_output(recipe_data)
		if str(output.get("item_id", "")) == item_id:
			usages.append("recipe %s output" % recipe_id)
		for ingredient_value in InventoryModel.ingredients(recipe_data):
			var ingredient: Dictionary = ingredient_value
			if str(ingredient.get("item_id", "")) == item_id:
				usages.append("recipe %s ingredient" % recipe_id)
	for usage in recursive_reference_labels(story_definitions, "item_id", item_id, "story"):
		usages.append(usage)
	return usages


func find_capability_usages(capability_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	if EquipmentCatalog.base_capabilities(active_campaign).has(capability_id):
		usages.append("base capabilities")
	for item_id in EquipmentCatalog.equipment_item_ids(item_definitions):
		if EquipmentCatalog.granted_capabilities(ItemCatalog.item(item_definitions, item_id)).has(capability_id):
			usages.append("equipment %s" % item_id)
	for map_id_value in map_records.keys():
		var map_id := str(map_id_value)
		var record: Dictionary = map_records.get(map_id, {})
		var map_data: Dictionary = record.get("data", {})
		for field in ["connections", "interactions"]:
			for value in map_data.get(field, []):
				if typeof(value) == TYPE_DICTIONARY and EquipmentCatalog.required_capabilities(value).has(capability_id):
					usages.append("%s %s %s" % [map_id, field.trim_suffix("s"), (value as Dictionary).get("id", "record")])
	for usage in recursive_reference_labels(story_definitions, "capability_id", capability_id, "story"):
		usages.append(usage)
	return usages


func recursive_reference_labels(value: Variant, key_name: String, requested: String, prefix: String) -> PackedStringArray:
	var output := PackedStringArray()
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		if str(data.get(key_name, "")) == requested:
			output.append(prefix)
		for key in data.keys():
			for match_value in recursive_reference_labels(data.get(key), key_name, requested, "%s/%s" % [prefix, key]):
				if not output.has(match_value):
					output.append(match_value)
	elif typeof(value) == TYPE_ARRAY:
		var index := 0
		for child in value:
			for match_value in recursive_reference_labels(child, key_name, requested, "%s/%d" % [prefix, index]):
				if not output.has(match_value):
					output.append(match_value)
			index += 1
	return output


static func parse_assignment_lines(text: String, label: String) -> Dictionary:
	var entries: Array = []
	var errors: Array[String] = []
	var seen: Dictionary = {}
	var line_number := 0
	for raw_line in text.split("\n"):
		line_number += 1
		var line := str(raw_line).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split("=", false, 1)
		if parts.size() != 2:
			errors.append("%s line %d must use key = value." % [label, line_number])
			continue
		var key := Repository.normalise_id(str(parts[0]))
		var value := str(parts[1]).strip_edges()
		if key.is_empty() or value.is_empty():
			errors.append("%s line %d requires a non-empty key and value." % [label, line_number])
		elif seen.has(key):
			errors.append("%s repeats '%s'." % [label, key])
		else:
			seen[key] = true
			entries.append({"key": key, "value": value})
	return {"ok": errors.is_empty(), "entries": entries, "errors": errors}


func selected_item_metadata(list: ItemList) -> Array:
	var output: Array = []
	for index in range(list.item_count):
		if list.is_selected(index):
			output.append(str(list.get_item_metadata(index)))
	return output


func select_option_metadata(option: OptionButton, requested: String) -> void:
	if option == null or option.item_count == 0:
		return
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == requested:
			option.select(index)
			return
	option.select(0)


func selected_option_metadata(option: OptionButton) -> String:
	if option == null or option.item_count == 0 or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func validate_all_campaigns() -> void:
	var report: Dictionary = EquipmentValidator.validate_all()
	set_status(format_report(report), not bool(report.get("ok", false)))


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(
		"%d campaign(s), %d item(s), %d recipe(s), %d equipment item(s), %d slot(s), %d capability definition(s), %d gate(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 1 if not active_campaign.is_empty() else 0),
			report.get("item_count", item_definitions.size()),
			report.get("recipe_count", recipe_definitions.size()),
			report.get("equipment_item_count", 0),
			report.get("equipment_slot_count", EquipmentCatalog.slot_ids(active_campaign).size()),
			report.get("capability_count", capability_definitions.size()),
			report.get("capability_gate_count", 0),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
	for warning in report.get("warnings", []):
		lines.append("WARNING: %s" % warning)
	for error in report.get("errors", []):
		lines.append("ERROR: %s" % error)
	return "\n".join(lines)


func format_messages(messages: Variant) -> String:
	var lines := PackedStringArray()
	if typeof(messages) == TYPE_ARRAY:
		for message in messages:
			lines.append(str(message))
	return "\n".join(lines)


func set_status(message: String, is_error: bool) -> void:
	var color := "#ff9797" if is_error else "#acd8b2"
	status_label.text = "[color=%s]%s[/color]" % [color, message]


func rescan_editor_files() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func open_campaign_folder() -> void:
	var absolute_path := ProjectSettings.globalize_path(Repository.DEFAULT_ROOT)
	DirAccess.make_dir_recursive_absolute(absolute_path)
	OS.shell_open(absolute_path)


func clear_all() -> void:
	active_campaign = {}
	active_campaign_path = ""
	active_item_catalog = {}
	active_capability_catalog = {}
	item_definitions = {}
	capability_definitions = {}
	recipe_definitions = {}
	story_definitions = {}
	map_records = {}
	equipment_list.clear()
	capability_list.clear()
	gate_map_selector.clear()
	clear_equipment_form()
	clear_capability_form()
