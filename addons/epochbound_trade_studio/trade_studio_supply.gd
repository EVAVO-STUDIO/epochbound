@tool
extends "res://addons/epochbound_trade_studio/trade_studio.gd"

const SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")
const SupplyValidator = preload("res://src/content/supply_region_validator.gd")

var supply_region_definitions: Dictionary = {}
var selected_supply_region_id := ""

var supply_region_list: ItemList
var new_supply_region_id: LineEdit
var supply_region_id_edit: LineEdit
var supply_region_name_edit: LineEdit
var supply_region_interval: SpinBox
var supply_region_catchup: SpinBox
var supply_region_apply_button: Button
var supply_region_delete_button: Button
var merchant_supply_region_selector: OptionButton


func build_ui() -> void:
	super.build_ui()
	var tabs := main_tab_container()
	if tabs != null:
		tabs.add_child(build_supply_regions_tab())


func build_merchants_tab() -> Control:
	var tab := super.build_merchants_tab()
	merchant_supply_region_selector = OptionButton.new()
	merchant_supply_region_selector.disabled = true
	var region_box := make_labeled_control("Supply route", merchant_supply_region_selector)
	var scroll := tab.get_child(1) as ScrollContainer
	if scroll != null and scroll.get_child_count() > 0:
		var inspector := scroll.get_child(0) as VBoxContainer
		if inspector != null:
			inspector.add_child(region_box)
			inspector.move_child(region_box, 4)
			var help := RichTextLabel.new()
			help.fit_content = true
			help.bbcode_enabled = true
			help.text = "[color=#8f9ba4]Finite consumables, materials and ammunition may define restock_quantity and restock_target in their stock JSON. Equipment and progression stock remain scarce.[/color]"
			inspector.add_child(help)
			inspector.move_child(help, 5)
	return tab


func build_supply_regions_tab() -> Control:
	var tab := HSplitContainer.new()
	tab.name = "Supply Routes"
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 285
	left.add_theme_constant_override("separation", 5)
	tab.add_child(left)
	left.add_child(make_heading("SUPPLY REGION DEFINITIONS"))
	supply_region_list = ItemList.new()
	supply_region_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	supply_region_list.item_selected.connect(on_supply_region_selected)
	left.add_child(supply_region_list)
	new_supply_region_id = LineEdit.new()
	new_supply_region_id.placeholder_text = "new_supply_route"
	left.add_child(new_supply_region_id)
	left.add_child(make_button("Add Supply Route", add_supply_region))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 7)
	tab.add_child(right)
	right.add_child(make_heading("SUPPLY ROUTE INSPECTOR"))
	supply_region_id_edit = LineEdit.new()
	supply_region_id_edit.editable = false
	right.add_child(make_labeled_control("Stable supply route ID", supply_region_id_edit))
	supply_region_name_edit = LineEdit.new()
	right.add_child(make_labeled_control("Display name", supply_region_name_edit))
	supply_region_interval = make_spin(
		SupplyCatalog.MIN_INTERVAL_SECONDS,
		SupplyCatalog.MAX_INTERVAL_SECONDS,
		30.0,
		180.0
	)
	supply_region_interval.suffix = " sec"
	supply_region_catchup = make_spin(1, SupplyCatalog.MAX_CATCHUP_CYCLES, 1, 4)
	var timing := HBoxContainer.new()
	timing.add_child(make_labeled_control("Restock interval", supply_region_interval))
	timing.add_child(make_labeled_control("Maximum catch-up cycles", supply_region_catchup))
	right.add_child(timing)
	var help := RichTextLabel.new()
	help.fit_content = true
	help.bbcode_enabled = true
	help.text = (
		"[color=#8f9ba4]Supply cycles use durable gameplay time, not wall-clock time. "
		+ "Catch-up is bounded, old saves begin at their current cycle, and every elapsed cycle is consumed even when stock is already full. "
		+ "This prevents offline windfalls and reload duplication.[/color]"
	)
	right.add_child(help)
	var actions := HBoxContainer.new()
	supply_region_apply_button = make_button("Apply Supply Route", apply_supply_region)
	supply_region_delete_button = make_button("Delete Supply Route", delete_supply_region)
	actions.add_child(supply_region_apply_button)
	actions.add_child(supply_region_delete_button)
	right.add_child(actions)
	set_supply_region_form_enabled(false)
	return tab


func main_tab_container() -> TabContainer:
	for child in get_children():
		for grandchild in child.get_children():
			if grandchild is TabContainer:
				return grandchild as TabContainer
	return null


func rebuild_definitions() -> void:
	super.rebuild_definitions()
	var result := SupplyCatalog.load_catalogs(active_campaign_path, active_campaign)
	supply_region_definitions = result.get("definitions", {})


func refresh_all_forms() -> void:
	refresh_supply_region_list(selected_supply_region_id)
	refresh_supply_region_selector()
	super.refresh_all_forms()


func refresh_supply_region_list(preferred_id: String = "") -> void:
	if supply_region_list == null:
		return
	supply_region_list.clear()
	var ids := sorted_ids(supply_region_definitions)
	for region_id in ids:
		var data := SupplyCatalog.region(supply_region_definitions, region_id)
		var index := supply_region_list.item_count
		supply_region_list.add_item(
			"%s  ·  %s" % [
				SupplyCatalog.region_name(supply_region_definitions, region_id),
				SupplyCatalog.format_duration(SupplyCatalog.interval_seconds(data))
			]
		)
		supply_region_list.set_item_metadata(index, region_id)
	if preferred_id.is_empty() and not ids.is_empty():
		preferred_id = ids[0]
	select_supply_region_id(preferred_id)


func refresh_supply_region_selector() -> void:
	if merchant_supply_region_selector == null:
		return
	var requested := selected_option_metadata(merchant_supply_region_selector)
	merchant_supply_region_selector.clear()
	merchant_supply_region_selector.add_item("Static stock / no route")
	merchant_supply_region_selector.set_item_metadata(0, "")
	for region_id in sorted_ids(supply_region_definitions):
		var index := merchant_supply_region_selector.item_count
		merchant_supply_region_selector.add_item(SupplyCatalog.region_name(supply_region_definitions, region_id))
		merchant_supply_region_selector.set_item_metadata(index, region_id)
	select_option_metadata(merchant_supply_region_selector, requested)


func on_supply_region_selected(index: int) -> void:
	if supply_region_list != null and index >= 0 and index < supply_region_list.item_count:
		select_supply_region_id(str(supply_region_list.get_item_metadata(index)))


func select_supply_region_id(region_id: String) -> void:
	selected_supply_region_id = region_id if supply_region_definitions.has(region_id) else ""
	if supply_region_list != null:
		for index in range(supply_region_list.item_count):
			if str(supply_region_list.get_item_metadata(index)) == selected_supply_region_id:
				supply_region_list.select(index)
				break
	populate_supply_region_form()


func populate_supply_region_form() -> void:
	var data := SupplyCatalog.region(supply_region_definitions, selected_supply_region_id)
	if data.is_empty():
		set_supply_region_form_enabled(false)
		supply_region_id_edit.text = ""
		supply_region_name_edit.text = ""
		return
	set_supply_region_form_enabled(true)
	supply_region_id_edit.text = selected_supply_region_id
	supply_region_name_edit.text = str(data.get("display_name", ""))
	supply_region_interval.value = SupplyCatalog.interval_seconds(data)
	supply_region_catchup.value = SupplyCatalog.max_catchup_cycles(data)


func set_supply_region_form_enabled(enabled: bool) -> void:
	if supply_region_name_edit == null:
		return
	supply_region_name_edit.editable = enabled
	supply_region_interval.editable = enabled
	supply_region_catchup.editable = enabled
	supply_region_apply_button.disabled = not enabled
	supply_region_delete_button.disabled = not enabled


func add_supply_region() -> void:
	var region_id := Repository.normalise_id(new_supply_region_id.text)
	if region_id.is_empty() or supply_region_definitions.has(region_id):
		set_status("Enter a unique valid supply route ID.", true)
		return
	var regions_value: Variant = active_economy_catalog.get("supply_regions", [])
	var regions: Array = regions_value if typeof(regions_value) == TYPE_ARRAY else []
	regions.append(SupplyCatalog.default_region(region_id, region_id.replace("_", " ").capitalize()))
	var previous := active_economy_catalog.duplicate(true)
	active_economy_catalog["supply_regions"] = regions
	new_supply_region_id.clear()
	if save_economy_catalog(previous):
		rebuild_definitions()
		refresh_all_forms()
		select_supply_region_id(region_id)
		set_status("Created supply route '%s'." % region_id, false)


func apply_supply_region() -> void:
	if selected_supply_region_id.is_empty():
		return
	var regions_value: Variant = active_economy_catalog.get("supply_regions", [])
	var regions: Array = regions_value if typeof(regions_value) == TYPE_ARRAY else []
	var found := false
	for index in range(regions.size()):
		if typeof(regions[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = regions[index]
		if str(data.get("id", "")) != selected_supply_region_id:
			continue
		data["display_name"] = supply_region_name_edit.text.strip_edges()
		data["restock_interval_seconds"] = supply_region_interval.value
		data["max_catchup_cycles"] = int(supply_region_catchup.value)
		regions[index] = data
		found = true
		break
	if not found:
		set_status("The selected supply route is not in the editable primary catalogue.", true)
		return
	var previous := active_economy_catalog.duplicate(true)
	active_economy_catalog["supply_regions"] = regions
	if save_economy_catalog(previous):
		rebuild_definitions()
		refresh_all_forms()
		select_supply_region_id(selected_supply_region_id)
		set_status("Updated supply route '%s'." % selected_supply_region_id, false)


func delete_supply_region() -> void:
	if selected_supply_region_id.is_empty():
		return
	for merchant_id in merchant_definitions.keys():
		var merchant := EconomyCatalog.merchant(merchant_definitions, str(merchant_id))
		if SupplyCatalog.merchant_region_id(merchant) == selected_supply_region_id:
			set_status("Cannot delete '%s'; merchant '%s' uses it." % [selected_supply_region_id, merchant_id], true)
			return
	var regions_value: Variant = active_economy_catalog.get("supply_regions", [])
	var regions: Array = regions_value if typeof(regions_value) == TYPE_ARRAY else []
	var found := false
	for index in range(regions.size() - 1, -1, -1):
		if typeof(regions[index]) != TYPE_DICTIONARY:
			continue
		if str((regions[index] as Dictionary).get("id", "")) != selected_supply_region_id:
			continue
		regions.remove_at(index)
		found = true
		break
	if not found:
		set_status("The selected supply route is not in the editable primary catalogue.", true)
		return
	var previous := active_economy_catalog.duplicate(true)
	var deleted := selected_supply_region_id
	active_economy_catalog["supply_regions"] = regions
	selected_supply_region_id = ""
	if save_economy_catalog(previous):
		rebuild_definitions()
		refresh_all_forms()
		set_status("Deleted supply route '%s'." % deleted, false)


func populate_merchant_form() -> void:
	super.populate_merchant_form()
	if merchant_supply_region_selector == null:
		return
	var data := EconomyCatalog.merchant(merchant_definitions, selected_merchant_id)
	select_option_metadata(
		merchant_supply_region_selector,
		SupplyCatalog.merchant_region_id(data)
	)


func set_merchant_form_enabled(enabled: bool) -> void:
	super.set_merchant_form_enabled(enabled)
	if merchant_supply_region_selector != null:
		merchant_supply_region_selector.disabled = not enabled


func apply_merchant() -> void:
	if selected_merchant_id.is_empty():
		return
	var conditions_result := parse_json_lines(merchant_conditions_edit.text, "merchant conditions")
	var stock_result := parse_json_lines(merchant_stock_edit.text, "merchant stock")
	var accepted_result := parse_id_lines(merchant_accepted_kinds_edit.text, "accepted kinds")
	var refused_result := parse_id_lines(merchant_refused_items_edit.text, "refused item IDs")
	for result in [conditions_result, stock_result, accepted_result, refused_result]:
		if not bool((result as Dictionary).get("ok", false)):
			set_status(format_messages((result as Dictionary).get("errors", [])), true)
			return
	var currency_id := selected_option_metadata(merchant_currency_selector)
	if currency_id.is_empty():
		set_status("Select a valid transaction currency.", true)
		return
	var supply_region_id := selected_option_metadata(merchant_supply_region_selector)
	if not supply_region_id.is_empty() and not supply_region_definitions.has(supply_region_id):
		set_status("Select a valid supply route.", true)
		return
	var merchants: Array = active_economy_catalog.get("merchants", [])
	var found := false
	for index in range(merchants.size()):
		if typeof(merchants[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = merchants[index]
		if str(data.get("id", "")) != selected_merchant_id:
			continue
		data["display_name"] = merchant_name_edit.text.strip_edges()
		data["currency_id"] = currency_id
		if supply_region_id.is_empty():
			data.erase("supply_region_id")
		else:
			data["supply_region_id"] = supply_region_id
		data["greeting"] = merchant_greeting_edit.text.strip_edges()
		data["farewell"] = merchant_farewell_edit.text.strip_edges()
		data["buy_multiplier"] = merchant_buy_multiplier.value
		data["sell_multiplier"] = merchant_sell_multiplier.value
		data["accepts_sales"] = merchant_accepts_sales.button_pressed
		data["resell_player_goods"] = merchant_resells_goods.button_pressed
		data["accepted_kinds"] = accepted_result.get("entries", [])
		data["refused_items"] = refused_result.get("entries", [])
		data["conditions"] = conditions_result.get("entries", [])
		data["stock"] = stock_result.get("entries", [])
		merchants[index] = data
		found = true
		break
	if not found:
		set_status("The selected merchant is not in the editable primary catalogue.", true)
		return
	var previous := active_economy_catalog.duplicate(true)
	active_economy_catalog["merchants"] = merchants
	if save_economy_catalog(previous):
		rebuild_definitions()
		refresh_all_forms()
		select_merchant_id(selected_merchant_id)
		set_status("Updated merchant '%s'." % selected_merchant_id, false)


func save_economy_catalog(previous: Dictionary) -> bool:
	var result := Repository.save_json(active_economy_path, active_economy_catalog)
	if not bool(result.get("ok", false)):
		active_economy_catalog = previous
		set_status(format_messages(result.get("errors", [])), true)
		return false
	var report := SupplyValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		active_economy_catalog = previous
		Repository.save_json(active_economy_path, active_economy_catalog)
		set_status("Change rolled back. %s" % format_messages(report.get("errors", [])), true)
		return false
	rescan_editor_files()
	return true


func validate_all_campaigns() -> void:
	var report := SupplyValidator.validate_all()
	set_status(format_report(report), not bool(report.get("ok", false)))


func format_report(report: Dictionary) -> String:
	return (
		super.format_report(report)
		+ "\n%d supply route(s), %d renewable stock entr%s." % [
			int(report.get("supply_region_count", 0)),
			int(report.get("renewable_stock_count", 0)),
			"y" if int(report.get("renewable_stock_count", 0)) == 1 else "ies"
		]
	)


func clear_all() -> void:
	super.clear_all()
	supply_region_definitions = {}
	selected_supply_region_id = ""
	if supply_region_list != null:
		supply_region_list.clear()
	set_supply_region_form_enabled(false)
