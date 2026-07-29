@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const ItemValidator = preload("res://src/content/item_validator.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const ArsenalCatalog = preload("res://src/content/arsenal_catalog.gd")

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_campaign_path := ""
var active_item_catalog: Dictionary = {}
var active_item_catalog_path := ""
var active_recipe_catalog: Dictionary = {}
var active_recipe_catalog_path := ""
var item_definitions: Dictionary = {}
var recipe_definitions: Dictionary = {}
var selected_item_id := ""
var selected_recipe_id := ""

var campaign_selector: OptionButton
var item_list: ItemList
var new_item_id: LineEdit
var item_id_edit: LineEdit
var item_name_edit: LineEdit
var item_kind_selector: OptionButton
var item_description_edit: TextEdit
var item_stack_limit: SpinBox
var item_value: SpinBox
var item_effect_selector: OptionButton
var item_effect_amount: SpinBox
var item_apply_button: Button
var item_delete_button: Button
var recipe_list: ItemList
var new_recipe_id: LineEdit
var recipe_id_edit: LineEdit
var recipe_name_edit: LineEdit
var recipe_description_edit: TextEdit
var recipe_output_selector: OptionButton
var recipe_output_quantity: SpinBox
var recipe_ingredients_edit: TextEdit
var recipe_unlocked_default: CheckBox
var recipe_apply_button: Button
var recipe_delete_button: Button
var starting_inventory_edit: TextEdit
var starting_recipe_list: ItemList
var status_label: RichTextLabel


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
	title.text = "Epochbound Item Forge"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(make_heading("CAMPAIGN"))
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 250
	campaign_selector.item_selected.connect(on_campaign_selected)
	header.add_child(campaign_selector)
	header.add_child(make_button("Validate All", validate_all_campaigns))
	header.add_child(make_button("Open Campaign Folder", open_campaign_folder))

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(build_items_tab())
	tabs.add_child(build_recipes_tab())
	tabs.add_child(build_loadout_tab())

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 72
	status_label.text = "[color=#9aa8b5]Item Forge ready.[/color]"
	root.add_child(status_label)


func build_items_tab() -> Control:
	var tab := HSplitContainer.new()
	tab.name = "Items"
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260
	left.add_theme_constant_override("separation", 5)
	tab.add_child(left)
	left.add_child(make_heading("ITEM DEFINITIONS"))
	item_list = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.item_selected.connect(on_item_selected)
	left.add_child(item_list)
	new_item_id = LineEdit.new()
	new_item_id.placeholder_text = "new_item_id"
	left.add_child(new_item_id)
	left.add_child(make_button("Add Item", add_item))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 5)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(right)
	right.add_child(make_heading("ITEM INSPECTOR"))
	item_id_edit = LineEdit.new()
	item_id_edit.editable = false
	right.add_child(make_labeled_control("Stable item ID", item_id_edit))
	item_name_edit = LineEdit.new()
	right.add_child(make_labeled_control("Display name", item_name_edit))
	item_kind_selector = OptionButton.new()
	for kind in ItemCatalog.ALLOWED_ITEM_KINDS:
		item_kind_selector.add_item(kind)
	item_kind_selector.item_selected.connect(on_item_kind_changed)
	right.add_child(make_labeled_control("Kind", item_kind_selector))
	item_description_edit = TextEdit.new()
	item_description_edit.custom_minimum_size.y = 96
	item_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right.add_child(make_labeled_control("Description", item_description_edit))
	var numbers := HBoxContainer.new()
	numbers.add_child(make_labeled_control("Stack limit", make_assigned_spin("item_stack_limit", 1, 999, 1, 1)))
	numbers.add_child(make_labeled_control("Value", make_assigned_spin("item_value", 0, 999999, 1, 0)))
	right.add_child(numbers)
	item_effect_selector = OptionButton.new()
	for effect_type in ItemCatalog.ALLOWED_EFFECT_TYPES:
		item_effect_selector.add_item(effect_type)
	item_effect_selector.item_selected.connect(on_item_effect_changed)
	right.add_child(make_labeled_control("Use effect", item_effect_selector))
	item_effect_amount = make_spin(0, 9999, 1, 0)
	right.add_child(make_labeled_control("Effect amount", item_effect_amount))
	var item_actions := HBoxContainer.new()
	item_apply_button = make_button("Apply Item", apply_item)
	item_delete_button = make_button("Delete Item", delete_item)
	item_actions.add_child(item_apply_button)
	item_actions.add_child(item_delete_button)
	right.add_child(item_actions)
	set_item_form_enabled(false)
	return tab


func build_recipes_tab() -> Control:
	var tab := HSplitContainer.new()
	tab.name = "Recipes"
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260
	left.add_theme_constant_override("separation", 5)
	tab.add_child(left)
	left.add_child(make_heading("RECIPE DEFINITIONS"))
	recipe_list = ItemList.new()
	recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_list.item_selected.connect(on_recipe_selected)
	left.add_child(recipe_list)
	new_recipe_id = LineEdit.new()
	new_recipe_id.placeholder_text = "new_recipe_id"
	left.add_child(new_recipe_id)
	left.add_child(make_button("Add Recipe", add_recipe))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 5)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(right)
	right.add_child(make_heading("RECIPE INSPECTOR"))
	recipe_id_edit = LineEdit.new()
	recipe_id_edit.editable = false
	right.add_child(make_labeled_control("Stable recipe ID", recipe_id_edit))
	recipe_name_edit = LineEdit.new()
	right.add_child(make_labeled_control("Display name", recipe_name_edit))
	recipe_description_edit = TextEdit.new()
	recipe_description_edit.custom_minimum_size.y = 72
	recipe_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right.add_child(make_labeled_control("Description", recipe_description_edit))
	var output_row := HBoxContainer.new()
	recipe_output_selector = OptionButton.new()
	recipe_output_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_row.add_child(make_labeled_control("Output item", recipe_output_selector))
	recipe_output_quantity = make_spin(1, 999, 1, 1)
	output_row.add_child(make_labeled_control("Quantity", recipe_output_quantity))
	right.add_child(output_row)
	recipe_ingredients_edit = TextEdit.new()
	recipe_ingredients_edit.custom_minimum_size.y = 130
	recipe_ingredients_edit.placeholder_text = "brass_filings = 2\nashen_resin = 1"
	right.add_child(make_labeled_control("Ingredients — one item_id = quantity per line", recipe_ingredients_edit))
	recipe_unlocked_default = CheckBox.new()
	recipe_unlocked_default.text = "Unlocked by default"
	right.add_child(recipe_unlocked_default)
	var recipe_actions := HBoxContainer.new()
	recipe_apply_button = make_button("Apply Recipe", apply_recipe)
	recipe_delete_button = make_button("Delete Recipe", delete_recipe)
	recipe_actions.add_child(recipe_apply_button)
	recipe_actions.add_child(recipe_delete_button)
	right.add_child(recipe_actions)
	set_recipe_form_enabled(false)
	return tab


func build_loadout_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Starting Loadout"
	tab.add_theme_constant_override("separation", 6)
	tab.add_child(make_heading("STARTING INVENTORY"))
	var help := Label.new()
	help.text = "One item_id = quantity per line. Quantities must fit the authored stack limit."
	help.modulate = Color("8f9ba4")
	tab.add_child(help)
	starting_inventory_edit = TextEdit.new()
	starting_inventory_edit.custom_minimum_size.y = 150
	starting_inventory_edit.placeholder_text = "museum_tonic = 1\nbrass_filings = 1"
	tab.add_child(starting_inventory_edit)
	tab.add_child(make_heading("STARTING RECIPES"))
	starting_recipe_list = ItemList.new()
	starting_recipe_list.select_mode = ItemList.SELECT_MULTI
	starting_recipe_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(starting_recipe_list)
	tab.add_child(make_button("Apply Starting Loadout", apply_starting_loadout))
	return tab


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


func make_labeled_control(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(make_field_label(text))
	box.add_child(control)
	return box


func make_spin(minimum: float, maximum: float, step: float, initial: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func make_assigned_spin(property_name: String, minimum: float, maximum: float, step: float, initial: float) -> SpinBox:
	var spin := make_spin(minimum, maximum, step, initial)
	set(property_name, spin)
	return spin


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
		set_status("No source campaigns found under res://campaigns.", true)
		return
	campaign_selector.select(selected_index)
	on_campaign_selected(selected_index)


func on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = str(campaign_selector.get_item_metadata(index))
	var campaign_result := Repository.read_json(active_campaign_path)
	if not campaign_result.get("ok", false):
		set_status(format_messages(campaign_result.get("errors", [])), true)
		return
	active_campaign = campaign_result.get("data", {})
	if not load_primary_catalogs():
		return
	rebuild_definitions()
	refresh_all_forms()
	set_status("Loaded item data for '%s'." % active_campaign.get("title", active_campaign.get("id", "campaign")), false)


func load_primary_catalogs() -> bool:
	active_item_catalog_path = ItemCatalog.primary_item_catalog_path(active_campaign_path, active_campaign)
	active_recipe_catalog_path = ItemCatalog.primary_recipe_catalog_path(active_campaign_path, active_campaign)
	var item_result := Repository.read_json(active_item_catalog_path)
	var recipe_result := Repository.read_json(active_recipe_catalog_path)
	if not item_result.get("ok", false) or not recipe_result.get("ok", false):
		var errors: Array[String] = []
		ItemCatalog.append_messages(errors, item_result.get("errors", []))
		ItemCatalog.append_messages(errors, recipe_result.get("errors", []))
		set_status(format_messages(errors), true)
		return false
	active_item_catalog = item_result.get("data", {})
	active_recipe_catalog = recipe_result.get("data", {})
	return true


func rebuild_definitions() -> void:
	var item_result := ItemCatalog.load_item_catalogs(active_campaign_path, active_campaign)
	var recipe_result := ItemCatalog.load_recipe_catalogs(active_campaign_path, active_campaign)
	item_definitions = item_result.get("definitions", {})
	recipe_definitions = recipe_result.get("definitions", {})


func refresh_all_forms() -> void:
	refresh_item_list()
	refresh_item_selectors()
	refresh_recipe_list()
	refresh_starting_loadout()


func refresh_item_list(preferred_id: String = "") -> void:
	item_list.clear()
	var ids := sorted_definition_ids(item_definitions, "display_name")
	for item_id in ids:
		var data := ItemCatalog.item(item_definitions, item_id)
		var index := item_list.item_count
		item_list.add_item(ItemCatalog.item_name(data, item_id))
		item_list.set_item_metadata(index, item_id)
	if preferred_id.is_empty() and not ids.is_empty():
		preferred_id = ids[0]
	select_item_id(preferred_id)


func refresh_recipe_list(preferred_id: String = "") -> void:
	recipe_list.clear()
	var ids := sorted_definition_ids(recipe_definitions, "display_name")
	for recipe_id in ids:
		var data := ItemCatalog.recipe(recipe_definitions, recipe_id)
		var index := recipe_list.item_count
		recipe_list.add_item(str(data.get("display_name", recipe_id)))
		recipe_list.set_item_metadata(index, recipe_id)
	if preferred_id.is_empty() and not ids.is_empty():
		preferred_id = ids[0]
	select_recipe_id(preferred_id)


func sorted_definition_ids(definitions: Dictionary, name_field: String) -> PackedStringArray:
	var ids: Array[String] = []
	for identifier in definitions.keys():
		ids.append(str(identifier))
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_data: Dictionary = definitions.get(left, {})
		var right_data: Dictionary = definitions.get(right, {})
		return str(left_data.get(name_field, left)).naturalnocasecmp_to(str(right_data.get(name_field, right))) < 0
	)
	return PackedStringArray(ids)


func on_item_selected(index: int) -> void:
	if index >= 0 and index < item_list.item_count:
		select_item_id(str(item_list.get_item_metadata(index)))


func select_item_id(item_id: String) -> void:
	selected_item_id = item_id if item_definitions.has(item_id) else ""
	for index in range(item_list.item_count):
		if str(item_list.get_item_metadata(index)) == selected_item_id:
			item_list.select(index)
			break
	populate_item_form()


func populate_item_form() -> void:
	var data := ItemCatalog.item(item_definitions, selected_item_id)
	if data.is_empty():
		set_item_form_enabled(false)
		clear_item_form()
		return
	set_item_form_enabled(true)
	item_id_edit.text = selected_item_id
	item_name_edit.text = str(data.get("display_name", ""))
	select_option_text(item_kind_selector, str(data.get("kind", "material")))
	item_description_edit.text = str(data.get("description", ""))
	item_stack_limit.value = float(data.get("stack_limit", 1))
	item_value.value = float(data.get("value", 0))
	var effect := ItemCatalog.use_effect(data)
	select_option_text(item_effect_selector, str(effect.get("type", "none")))
	item_effect_amount.value = float(effect.get("amount", 0))
	on_item_effect_changed(item_effect_selector.selected)


func clear_item_form() -> void:
	item_id_edit.text = ""
	item_name_edit.text = ""
	item_description_edit.text = ""
	item_stack_limit.value = 1
	item_value.value = 0
	item_effect_amount.value = 0


func set_item_form_enabled(enabled: bool) -> void:
	item_name_edit.editable = enabled
	item_kind_selector.disabled = not enabled
	item_description_edit.editable = enabled
	item_stack_limit.editable = enabled
	item_value.editable = enabled
	item_effect_selector.disabled = not enabled
	item_effect_amount.editable = enabled
	item_apply_button.disabled = not enabled
	item_delete_button.disabled = not enabled


func on_item_kind_changed(_index: int) -> void:
	if item_kind_selector == null or item_effect_selector == null:
		return
	var kind := item_kind_selector.get_item_text(item_kind_selector.selected)
	if kind != "consumable":
		select_option_text(item_effect_selector, "none")
	on_item_effect_changed(item_effect_selector.selected)


func on_item_effect_changed(_index: int) -> void:
	if item_effect_selector == null or item_effect_amount == null:
		return
	item_effect_amount.editable = not item_effect_selector.disabled and item_effect_selector.get_item_text(item_effect_selector.selected) == "heal"


func add_item() -> void:
	var item_id := Repository.normalise_id(new_item_id.text)
	if item_id.is_empty():
		set_status("Enter a valid item ID.", true)
		return
	if item_definitions.has(item_id):
		set_status("Item '%s' already exists." % item_id, true)
		return
	var items: Array = active_item_catalog.get("items", [])
	items.append(ItemCatalog.default_item(item_id, item_id.replace("_", " ").capitalize()))
	active_item_catalog["items"] = items
	new_item_id.clear()
	if save_item_catalog():
		rebuild_definitions()
		refresh_all_forms()
		select_item_id(item_id)
		set_status("Created item '%s'." % item_id, false)


func apply_item() -> void:
	if selected_item_id.is_empty():
		return
	var items: Array = active_item_catalog.get("items", [])
	var found := false
	for index in range(items.size()):
		if typeof(items[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = items[index]
		if str(data.get("id", "")) != selected_item_id:
			continue
		data["display_name"] = item_name_edit.text.strip_edges()
		data["kind"] = item_kind_selector.get_item_text(item_kind_selector.selected)
		data["description"] = item_description_edit.text.strip_edges()
		data["stack_limit"] = int(item_stack_limit.value)
		data["value"] = int(item_value.value)
		var effect_type := item_effect_selector.get_item_text(item_effect_selector.selected)
		data["use_effect"] = {"type": effect_type}
		if effect_type == "heal":
			data["use_effect"]["amount"] = int(item_effect_amount.value)
		items[index] = data
		found = true
		break
	if not found:
		set_status("The selected item is not in the editable primary catalog.", true)
		return
	active_item_catalog["items"] = items
	if save_item_catalog():
		rebuild_definitions()
		refresh_all_forms()
		select_item_id(selected_item_id)
		set_status("Updated item '%s'." % selected_item_id, false)


func delete_item() -> void:
	if selected_item_id.is_empty():
		return
	var usages := find_item_usages(selected_item_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; used by %s." % [selected_item_id, ", ".join(usages)], true)
		return
	var items: Array = active_item_catalog.get("items", [])
	var removed := false
	for index in range(items.size() - 1, -1, -1):
		if typeof(items[index]) == TYPE_DICTIONARY and str((items[index] as Dictionary).get("id", "")) == selected_item_id:
			items.remove_at(index)
			removed = true
			break
	if not removed:
		set_status("Items from secondary catalogs are read-only in this slice.", true)
		return
	var deleted_id := selected_item_id
	active_item_catalog["items"] = items
	selected_item_id = ""
	if save_item_catalog():
		rebuild_definitions()
		refresh_all_forms()
		set_status("Deleted item '%s'." % deleted_id, false)


func on_recipe_selected(index: int) -> void:
	if index >= 0 and index < recipe_list.item_count:
		select_recipe_id(str(recipe_list.get_item_metadata(index)))


func select_recipe_id(recipe_id: String) -> void:
	selected_recipe_id = recipe_id if recipe_definitions.has(recipe_id) else ""
	for index in range(recipe_list.item_count):
		if str(recipe_list.get_item_metadata(index)) == selected_recipe_id:
			recipe_list.select(index)
			break
	populate_recipe_form()


func populate_recipe_form() -> void:
	var data := ItemCatalog.recipe(recipe_definitions, selected_recipe_id)
	if data.is_empty():
		set_recipe_form_enabled(false)
		clear_recipe_form()
		return
	set_recipe_form_enabled(true)
	recipe_id_edit.text = selected_recipe_id
	recipe_name_edit.text = str(data.get("display_name", ""))
	recipe_description_edit.text = str(data.get("description", ""))
	var output := InventoryModel.recipe_output(data)
	select_option_metadata(recipe_output_selector, str(output.get("item_id", "")))
	recipe_output_quantity.value = float(output.get("quantity", 1))
	var lines := PackedStringArray()
	for ingredient_value in InventoryModel.ingredients(data):
		var ingredient: Dictionary = ingredient_value
		lines.append("%s = %d" % [ingredient.get("item_id", ""), int(ingredient.get("quantity", 1))])
	recipe_ingredients_edit.text = "\n".join(lines)
	recipe_unlocked_default.button_pressed = bool(data.get("unlocked_by_default", false))


func clear_recipe_form() -> void:
	recipe_id_edit.text = ""
	recipe_name_edit.text = ""
	recipe_description_edit.text = ""
	recipe_ingredients_edit.text = ""
	recipe_output_quantity.value = 1
	recipe_unlocked_default.button_pressed = false


func set_recipe_form_enabled(enabled: bool) -> void:
	recipe_name_edit.editable = enabled
	recipe_description_edit.editable = enabled
	recipe_output_selector.disabled = not enabled
	recipe_output_quantity.editable = enabled
	recipe_ingredients_edit.editable = enabled
	recipe_unlocked_default.disabled = not enabled
	recipe_apply_button.disabled = not enabled
	recipe_delete_button.disabled = not enabled


func add_recipe() -> void:
	var recipe_id := Repository.normalise_id(new_recipe_id.text)
	if recipe_id.is_empty():
		set_status("Enter a valid recipe ID.", true)
		return
	if recipe_definitions.has(recipe_id):
		set_status("Recipe '%s' already exists." % recipe_id, true)
		return
	if item_definitions.is_empty():
		set_status("Create at least one item before adding a recipe.", true)
		return
	var item_ids := sorted_definition_ids(item_definitions, "display_name")
	var first_item_id := item_ids[0]
	var recipes: Array = active_recipe_catalog.get("recipes", [])
	recipes.append(ItemCatalog.default_recipe(recipe_id, recipe_id.replace("_", " ").capitalize(), first_item_id))
	active_recipe_catalog["recipes"] = recipes
	new_recipe_id.clear()
	if save_recipe_catalog():
		rebuild_definitions()
		refresh_all_forms()
		select_recipe_id(recipe_id)
		set_status("Created recipe '%s'." % recipe_id, false)


func apply_recipe() -> void:
	if selected_recipe_id.is_empty():
		return
	var parsed := parse_quantity_lines(recipe_ingredients_edit.text, "recipe ingredients")
	if not parsed.get("ok", false):
		set_status(format_messages(parsed.get("errors", [])), true)
		return
	var output_id := selected_option_metadata(recipe_output_selector)
	if output_id.is_empty():
		set_status("Select a valid output item.", true)
		return
	var recipes: Array = active_recipe_catalog.get("recipes", [])
	var found := false
	for index in range(recipes.size()):
		if typeof(recipes[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = recipes[index]
		if str(data.get("id", "")) != selected_recipe_id:
			continue
		data["display_name"] = recipe_name_edit.text.strip_edges()
		data["description"] = recipe_description_edit.text.strip_edges()
		data["ingredients"] = parsed.get("entries", [])
		data["output"] = {"item_id": output_id, "quantity": int(recipe_output_quantity.value)}
		data["unlocked_by_default"] = recipe_unlocked_default.button_pressed
		recipes[index] = data
		found = true
		break
	if not found:
		set_status("The selected recipe is not in the editable primary catalog.", true)
		return
	active_recipe_catalog["recipes"] = recipes
	if save_recipe_catalog():
		rebuild_definitions()
		refresh_all_forms()
		select_recipe_id(selected_recipe_id)
		set_status("Updated recipe '%s'." % selected_recipe_id, false)


func delete_recipe() -> void:
	if selected_recipe_id.is_empty():
		return
	var usages := find_recipe_usages(selected_recipe_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; used by %s." % [selected_recipe_id, ", ".join(usages)], true)
		return
	var recipes: Array = active_recipe_catalog.get("recipes", [])
	var removed := false
	for index in range(recipes.size() - 1, -1, -1):
		if typeof(recipes[index]) == TYPE_DICTIONARY and str((recipes[index] as Dictionary).get("id", "")) == selected_recipe_id:
			recipes.remove_at(index)
			removed = true
			break
	if not removed:
		set_status("Recipes from secondary catalogs are read-only in this slice.", true)
		return
	var deleted_id := selected_recipe_id
	active_recipe_catalog["recipes"] = recipes
	selected_recipe_id = ""
	if save_recipe_catalog():
		rebuild_definitions()
		refresh_all_forms()
		set_status("Deleted recipe '%s'." % deleted_id, false)


func refresh_item_selectors() -> void:
	var requested := selected_option_metadata(recipe_output_selector)
	recipe_output_selector.clear()
	for item_id in sorted_definition_ids(item_definitions, "display_name"):
		var data := ItemCatalog.item(item_definitions, item_id)
		var index := recipe_output_selector.item_count
		recipe_output_selector.add_item(ItemCatalog.item_name(data, item_id))
		recipe_output_selector.set_item_metadata(index, item_id)
	select_option_metadata(recipe_output_selector, requested)


func refresh_starting_loadout() -> void:
	var lines := PackedStringArray()
	for entry_value in ItemCatalog.starting_inventory(active_campaign):
		var entry: Dictionary = entry_value
		lines.append("%s = %d" % [entry.get("item_id", ""), int(entry.get("quantity", 1))])
	starting_inventory_edit.text = "\n".join(lines)
	starting_recipe_list.clear()
	var starting := ItemCatalog.starting_recipes(active_campaign)
	for recipe_id in sorted_definition_ids(recipe_definitions, "display_name"):
		var data := ItemCatalog.recipe(recipe_definitions, recipe_id)
		var index := starting_recipe_list.item_count
		starting_recipe_list.add_item(str(data.get("display_name", recipe_id)))
		starting_recipe_list.set_item_metadata(index, recipe_id)
		if starting.has(recipe_id):
			starting_recipe_list.select(index, false)


func apply_starting_loadout() -> void:
	var parsed := parse_quantity_lines(starting_inventory_edit.text, "starting inventory")
	if not parsed.get("ok", false):
		set_status(format_messages(parsed.get("errors", [])), true)
		return
	var entries: Array = parsed.get("entries", [])
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var item_id := str(entry.get("item_id", ""))
		if not item_definitions.has(item_id):
			set_status("Starting inventory references unknown item '%s'." % item_id, true)
			return
		if int(entry.get("quantity", 0)) > ItemCatalog.stack_limit(ItemCatalog.item(item_definitions, item_id)):
			set_status("Starting quantity for '%s' exceeds its stack limit." % item_id, true)
			return
	var recipe_ids: Array = []
	for index in range(starting_recipe_list.item_count):
		if starting_recipe_list.is_selected(index):
			recipe_ids.append(str(starting_recipe_list.get_item_metadata(index)))
	active_campaign["starting_inventory"] = entries
	active_campaign["starting_recipes"] = recipe_ids
	var result := Repository.save_json(active_campaign_path, active_campaign)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	rescan_editor_files()
	var report := ItemValidator.validate_campaign_path(active_campaign_path)
	set_status(format_report(report), not report.get("ok", false))


func parse_quantity_lines(text: String, label: String) -> Dictionary:
	var entries: Array = []
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			continue
		var separator := "=" if line.contains("=") else ":"
		var parts := line.split(separator, false, 1)
		if parts.size() != 2:
			errors.append("%s line '%s' must use item_id = quantity." % [label, line])
			continue
		var item_id := Repository.normalise_id(str(parts[0]))
		var quantity_text := str(parts[1]).strip_edges()
		if item_id.is_empty() or not quantity_text.is_valid_int():
			errors.append("%s line '%s' is invalid." % [label, line])
			continue
		var quantity := int(quantity_text)
		if quantity <= 0:
			errors.append("%s quantity for '%s' must be positive." % [label, item_id])
			continue
		if seen.has(item_id):
			errors.append("%s repeats '%s'." % [label, item_id])
			continue
		seen[item_id] = true
		entries.append({"item_id": item_id, "quantity": quantity})
	return {"ok": errors.is_empty(), "entries": entries, "errors": errors}


func save_item_catalog() -> bool:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	ItemValidator.validate_item_catalog_file(active_item_catalog, active_item_catalog_path, {}, errors, warnings)
	if not errors.is_empty():
		set_status(format_messages(errors), true)
		return false
	var result := Repository.save_json(active_item_catalog_path, active_item_catalog)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return false
	rescan_editor_files()
	return true


func save_recipe_catalog() -> bool:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var used_items: Dictionary = {}
	ItemValidator.validate_recipe_catalog_file(active_recipe_catalog, active_recipe_catalog_path, item_definitions, {}, used_items, errors, warnings)
	if not errors.is_empty():
		set_status(format_messages(errors), true)
		return false
	var result := Repository.save_json(active_recipe_catalog_path, active_recipe_catalog)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return false
	rescan_editor_files()
	return true


func find_item_usages(item_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	for recipe_id in recipe_definitions.keys():
		var recipe_data := ItemCatalog.recipe(recipe_definitions, str(recipe_id))
		var output := InventoryModel.recipe_output(recipe_data)
		if str(output.get("item_id", "")) == item_id:
			usages.append("recipe %s output" % recipe_id)
		for ingredient_value in InventoryModel.ingredients(recipe_data):
			var ingredient: Dictionary = ingredient_value
			if str(ingredient.get("item_id", "")) == item_id:
				usages.append("recipe %s ingredient" % recipe_id)
	for entry_value in ItemCatalog.starting_inventory(active_campaign):
		var entry: Dictionary = entry_value
		if str(entry.get("item_id", "")) == item_id:
			usages.append("starting inventory")
	var starting_equipment_value: Variant = active_campaign.get("starting_equipment", {})
	if typeof(starting_equipment_value) == TYPE_DICTIONARY:
		for equipped_value in (starting_equipment_value as Dictionary).values():
			if str(equipped_value) == item_id:
				usages.append("starting equipment")
	for weapon_id in ArsenalCatalog.ranged_weapon_ids(item_definitions):
		if ArsenalCatalog.weapon_ammunition_id(ItemCatalog.item(item_definitions, weapon_id)) == item_id:
			usages.append("ranged weapon %s ammunition" % weapon_id)
	var object_result := ObjectCatalog.load_catalogs(active_campaign_path, active_campaign)
	var object_definitions: Dictionary = object_result.get("definitions", {})
	for object_id in object_definitions.keys():
		for grant_value in ItemCatalog.item_grants(object_definitions.get(object_id, {})):
			var grant: Dictionary = grant_value
			if str(grant.get("item_id", "")) == item_id:
				usages.append("object %s grant" % object_id)
	for map_data in campaign_maps():
		for cue_value in map_data.get("companion_cues", []):
			if typeof(cue_value) != TYPE_DICTIONARY:
				continue
			var cue: Dictionary = cue_value
			for grant_value in ItemCatalog.item_grants(cue, "reward_items"):
				var grant: Dictionary = grant_value
				if str(grant.get("item_id", "")) == item_id:
					usages.append("cue %s grant" % cue.get("id", "cue"))
	var economy_result := EconomyCatalog.load_catalogs(active_campaign_path, active_campaign)
	var merchants: Dictionary = economy_result.get("merchants", {})
	for merchant_id in merchants.keys():
		var merchant_data := EconomyCatalog.merchant(merchants, str(merchant_id))
		if EconomyCatalog.stock_entry_index(merchant_data).has(item_id):
			usages.append("merchant %s stock" % merchant_id)
		if EconomyCatalog.refused_items(merchant_data).has(item_id):
			usages.append("merchant %s refusal rule" % merchant_id)
	return usages


func find_recipe_usages(recipe_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	if ItemCatalog.starting_recipes(active_campaign).has(recipe_id):
		usages.append("starting recipes")
	for map_data in campaign_maps():
		for cue_value in map_data.get("companion_cues", []):
			if typeof(cue_value) != TYPE_DICTIONARY:
				continue
			var cue: Dictionary = cue_value
			if ItemCatalog.recipe_unlocks(cue).has(recipe_id):
				usages.append("cue %s unlock" % cue.get("id", "cue"))
	return usages


func campaign_maps() -> Array:
	var maps: Array = []
	var value: Variant = active_campaign.get("map_files", [])
	if typeof(value) != TYPE_ARRAY:
		return maps
	for relative_value in value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			continue
		var result := Repository.read_json(active_campaign_path.get_base_dir().path_join(relative_path))
		if result.get("ok", false):
			maps.append(result.get("data", {}))
	return maps


func validate_all_campaigns() -> void:
	var report := ItemValidator.validate_all()
	set_status(format_report(report), not report.get("ok", false))


func select_option_text(option: OptionButton, requested: String) -> void:
	if option.item_count == 0:
		return
	var selection := 0
	for index in range(option.item_count):
		if option.get_item_text(index) == requested:
			selection = index
			break
	option.select(selection)


func select_option_metadata(option: OptionButton, requested: String) -> void:
	if option.item_count == 0:
		return
	var selection := 0
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == requested:
			selection = index
			break
	option.select(selection)


func selected_option_metadata(option: OptionButton) -> String:
	if option == null or option.item_count == 0 or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(
		"%d campaign(s), %d map(s), %d object definition(s), %d placement(s), %d zone(s), %d companion cue(s), %d item(s), %d recipe(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 1 if not active_campaign.is_empty() else 0),
			report.get("map_count", 0),
			report.get("definition_count", 0),
			report.get("placement_count", 0),
			report.get("zone_count", 0),
			report.get("cue_count", 0),
			report.get("item_count", item_definitions.size()),
			report.get("recipe_count", recipe_definitions.size()),
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
	active_item_catalog_path = ""
	active_recipe_catalog = {}
	active_recipe_catalog_path = ""
	item_definitions = {}
	recipe_definitions = {}
	selected_item_id = ""
	selected_recipe_id = ""
	item_list.clear()
	recipe_list.clear()
	starting_recipe_list.clear()
	set_item_form_enabled(false)
	set_recipe_form_enabled(false)
