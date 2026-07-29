@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const EconomyValidator = preload("res://src/content/economy_validator.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_campaign_path := ""
var active_economy_catalog: Dictionary = {}
var active_economy_path := ""
var active_object_catalog: Dictionary = {}
var active_object_path := ""
var currency_definitions: Dictionary = {}
var merchant_definitions: Dictionary = {}
var item_definitions: Dictionary = {}
var object_definitions: Dictionary = {}
var selected_currency_id := ""
var selected_merchant_id := ""
var selected_object_id := ""

var campaign_selector: OptionButton
var currency_list: ItemList
var new_currency_id: LineEdit
var currency_id_edit: LineEdit
var currency_name_edit: LineEdit
var currency_symbol_edit: LineEdit
var currency_starting_balance: SpinBox
var currency_max_balance: SpinBox
var currency_apply_button: Button
var currency_delete_button: Button
var merchant_list: ItemList
var new_merchant_id: LineEdit
var merchant_id_edit: LineEdit
var merchant_name_edit: LineEdit
var merchant_currency_selector: OptionButton
var merchant_greeting_edit: TextEdit
var merchant_farewell_edit: TextEdit
var merchant_buy_multiplier: SpinBox
var merchant_sell_multiplier: SpinBox
var merchant_accepts_sales: CheckBox
var merchant_resells_goods: CheckBox
var merchant_accepted_kinds_edit: TextEdit
var merchant_refused_items_edit: TextEdit
var merchant_conditions_edit: TextEdit
var merchant_stock_edit: TextEdit
var merchant_apply_button: Button
var merchant_delete_button: Button
var binding_object_list: ItemList
var binding_merchant_selector: OptionButton
var binding_summary: RichTextLabel
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
	title.text = "Epochbound Merchant & Economy Studio"
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
	tabs.add_child(build_currencies_tab())
	tabs.add_child(build_merchants_tab())
	tabs.add_child(build_bindings_tab())

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 68
	status_label.text = "[color=#9aa8b5]Merchant & Economy Studio ready.[/color]"
	root.add_child(status_label)


func build_currencies_tab() -> Control:
	var tab := HSplitContainer.new()
	tab.name = "Currencies"
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	left.add_theme_constant_override("separation", 5)
	tab.add_child(left)
	left.add_child(make_heading("CURRENCY DEFINITIONS"))
	currency_list = ItemList.new()
	currency_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	currency_list.item_selected.connect(on_currency_selected)
	left.add_child(currency_list)
	new_currency_id = LineEdit.new()
	new_currency_id.placeholder_text = "new_currency_id"
	left.add_child(new_currency_id)
	left.add_child(make_button("Add Currency", add_currency))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	tab.add_child(right)
	right.add_child(make_heading("CURRENCY INSPECTOR"))
	currency_id_edit = LineEdit.new()
	currency_id_edit.editable = false
	right.add_child(make_labeled_control("Stable currency ID", currency_id_edit))
	currency_name_edit = LineEdit.new()
	right.add_child(make_labeled_control("Display name", currency_name_edit))
	currency_symbol_edit = LineEdit.new()
	right.add_child(make_labeled_control("Short symbol", currency_symbol_edit))
	currency_starting_balance = make_spin(0, EconomyCatalog.MAX_BALANCE, 1, 0)
	currency_max_balance = make_spin(1, EconomyCatalog.MAX_BALANCE, 1, EconomyCatalog.MAX_BALANCE)
	var numbers := HBoxContainer.new()
	numbers.add_child(make_labeled_control("Starting balance", currency_starting_balance))
	numbers.add_child(make_labeled_control("Maximum balance", currency_max_balance))
	right.add_child(numbers)
	var help := RichTextLabel.new()
	help.fit_content = true
	help.bbcode_enabled = true
	help.text = "[color=#8f9ba4]Currency is durable campaign state. Starting balance is applied only when a new economy is initialised or a pre-economy save is migrated.[/color]"
	right.add_child(help)
	var actions := HBoxContainer.new()
	currency_apply_button = make_button("Apply Currency", apply_currency)
	currency_delete_button = make_button("Delete Currency", delete_currency)
	actions.add_child(currency_apply_button)
	actions.add_child(currency_delete_button)
	right.add_child(actions)
	set_currency_form_enabled(false)
	return tab


func build_merchants_tab() -> Control:
	var tab := HSplitContainer.new()
	tab.name = "Merchants"
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 275
	left.add_theme_constant_override("separation", 5)
	tab.add_child(left)
	left.add_child(make_heading("MERCHANT DEFINITIONS"))
	merchant_list = ItemList.new()
	merchant_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	merchant_list.item_selected.connect(on_merchant_selected)
	left.add_child(merchant_list)
	new_merchant_id = LineEdit.new()
	new_merchant_id.placeholder_text = "new_merchant_id"
	left.add_child(new_merchant_id)
	left.add_child(make_button("Add Merchant", add_merchant))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	scroll.add_child(right)
	right.add_child(make_heading("MERCHANT INSPECTOR"))
	merchant_id_edit = LineEdit.new()
	merchant_id_edit.editable = false
	right.add_child(make_labeled_control("Stable merchant ID", merchant_id_edit))
	merchant_name_edit = LineEdit.new()
	right.add_child(make_labeled_control("Display name", merchant_name_edit))
	merchant_currency_selector = OptionButton.new()
	right.add_child(make_labeled_control("Transaction currency", merchant_currency_selector))
	merchant_greeting_edit = make_text_edit(58, "A player-facing greeting shown when trade opens.")
	merchant_farewell_edit = make_text_edit(58, "A player-facing farewell shown when trade closes.")
	right.add_child(make_labeled_control("Greeting", merchant_greeting_edit))
	right.add_child(make_labeled_control("Farewell", merchant_farewell_edit))
	merchant_buy_multiplier = make_spin(0.01, 100.0, 0.05, 1.0)
	merchant_sell_multiplier = make_spin(0.0, 100.0, 0.05, 0.5)
	var multiplier_row := HBoxContainer.new()
	multiplier_row.add_child(make_labeled_control("Buy multiplier", merchant_buy_multiplier))
	multiplier_row.add_child(make_labeled_control("Sell multiplier", merchant_sell_multiplier))
	right.add_child(multiplier_row)
	merchant_accepts_sales = CheckBox.new()
	merchant_accepts_sales.text = "Accepts items from the player"
	right.add_child(merchant_accepts_sales)
	merchant_resells_goods = CheckBox.new()
	merchant_resells_goods.text = "Sold player goods become merchant stock"
	right.add_child(merchant_resells_goods)
	merchant_accepted_kinds_edit = make_text_edit(78, "consumable\nmaterial\nequipment")
	merchant_refused_items_edit = make_text_edit(78, "One item_id per line")
	var kind_row := HBoxContainer.new()
	kind_row.add_child(make_labeled_control("Accepted kinds — one per line", merchant_accepted_kinds_edit))
	kind_row.add_child(make_labeled_control("Refused item IDs — one per line", merchant_refused_items_edit))
	right.add_child(kind_row)
	merchant_conditions_edit = make_text_edit(90, '{"type":"quest_status","quest_id":"quest_id","status":"active"}')
	right.add_child(make_labeled_control("Availability conditions — one JSON object per line", merchant_conditions_edit))
	merchant_stock_edit = make_text_edit(180, '{"item_id":"museum_tonic","quantity":3,"unlimited":false,"buy_price":20,"sell_price":0,"conditions":[]}')
	right.add_child(make_labeled_control("Stock — one complete JSON object per line", merchant_stock_edit))
	var merchant_help := RichTextLabel.new()
	merchant_help.fit_content = true
	merchant_help.bbcode_enabled = true
	merchant_help.text = "[color=#8f9ba4]A zero price override derives from the item value and merchant multiplier. Finite stock persists in save profiles. Unlimited stock uses the authored item forever. Failed validation restores the previous complete catalogue.[/color]"
	right.add_child(merchant_help)
	var actions := HBoxContainer.new()
	merchant_apply_button = make_button("Apply Merchant", apply_merchant)
	merchant_delete_button = make_button("Delete Merchant", delete_merchant)
	actions.add_child(merchant_apply_button)
	actions.add_child(merchant_delete_button)
	right.add_child(actions)
	set_merchant_form_enabled(false)
	return tab


func build_bindings_tab() -> Control:
	var tab := HSplitContainer.new()
	tab.name = "NPC Bindings"
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 340
	left.add_theme_constant_override("separation", 5)
	tab.add_child(left)
	left.add_child(make_heading("REUSABLE NPC DEFINITIONS"))
	binding_object_list = ItemList.new()
	binding_object_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	binding_object_list.item_selected.connect(on_binding_object_selected)
	left.add_child(binding_object_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	tab.add_child(right)
	right.add_child(make_heading("MERCHANT BINDING"))
	binding_summary = RichTextLabel.new()
	binding_summary.fit_content = true
	binding_summary.bbcode_enabled = true
	binding_summary.text = "[color=#87949b]Select an NPC definition to bind it to a merchant record.[/color]"
	right.add_child(binding_summary)
	binding_merchant_selector = OptionButton.new()
	right.add_child(make_labeled_control("Merchant opened by this NPC", binding_merchant_selector))
	var actions := HBoxContainer.new()
	actions.add_child(make_button("Apply Binding", apply_binding))
	actions.add_child(make_button("Clear Binding", clear_binding))
	right.add_child(actions)
	var help := RichTextLabel.new()
	help.fit_content = true
	help.bbcode_enabled = true
	help.text = "[color=#8f9ba4]Map placements continue to reference the reusable NPC definition. The definition then opens the selected merchant, allowing one merchant contract to be reused across maps and eras.[/color]"
	right.add_child(help)
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


func make_text_edit(height: float, placeholder: String) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size.y = height
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit


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
	if not bool(campaign_result.get("ok", false)):
		clear_all()
		set_status(format_messages(campaign_result.get("errors", [])), true)
		return
	active_campaign = campaign_result.get("data", {})
	active_economy_path = EconomyCatalog.primary_catalog_path(active_campaign_path, active_campaign)
	active_object_path = ObjectCatalog.primary_catalog_path(active_campaign_path, active_campaign)
	var economy_result := Repository.read_json(active_economy_path)
	var object_result := Repository.read_json(active_object_path)
	if not bool(economy_result.get("ok", false)) or not bool(object_result.get("ok", false)):
		var errors: Array[String] = []
		EconomyCatalog.append_messages(errors, economy_result.get("errors", []))
		EconomyCatalog.append_messages(errors, object_result.get("errors", []))
		clear_all()
		set_status(format_messages(errors), true)
		return
	active_economy_catalog = economy_result.get("data", {})
	active_object_catalog = object_result.get("data", {})
	rebuild_definitions()
	refresh_all_forms()
	set_status("Loaded economy data for '%s'." % active_campaign.get("title", active_campaign.get("id", "campaign")), false)


func rebuild_definitions() -> void:
	var economy_result := EconomyCatalog.load_catalogs(active_campaign_path, active_campaign)
	currency_definitions = economy_result.get("currencies", {})
	merchant_definitions = economy_result.get("merchants", {})
	var item_result := ItemCatalog.load_item_catalogs(active_campaign_path, active_campaign)
	item_definitions = item_result.get("definitions", {})
	var object_result := ObjectCatalog.load_catalogs(active_campaign_path, active_campaign)
	object_definitions = object_result.get("definitions", {})


func refresh_all_forms() -> void:
	refresh_currency_list()
	refresh_currency_selectors()
	refresh_merchant_list()
	refresh_binding_list()


func sorted_ids(definitions: Dictionary, name_field: String = "display_name") -> PackedStringArray:
	var ids: Array[String] = []
	for identifier in definitions.keys():
		ids.append(str(identifier))
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_data: Dictionary = definitions.get(left, {})
		var right_data: Dictionary = definitions.get(right, {})
		return str(left_data.get(name_field, left)).naturalnocasecmp_to(str(right_data.get(name_field, right))) < 0
	)
	return PackedStringArray(ids)


func refresh_currency_list(preferred_id: String = "") -> void:
	currency_list.clear()
	var ids := sorted_ids(currency_definitions)
	for currency_id in ids:
		var data := EconomyCatalog.currency(currency_definitions, currency_id)
		var index := currency_list.item_count
		currency_list.add_item("%s  ·  %s" % [str(data.get("display_name", currency_id)), str(data.get("symbol", ""))])
		currency_list.set_item_metadata(index, currency_id)
	if preferred_id.is_empty() and not ids.is_empty():
		preferred_id = ids[0]
	select_currency_id(preferred_id)


func on_currency_selected(index: int) -> void:
	if index >= 0 and index < currency_list.item_count:
		select_currency_id(str(currency_list.get_item_metadata(index)))


func select_currency_id(currency_id: String) -> void:
	selected_currency_id = currency_id if currency_definitions.has(currency_id) else ""
	for index in range(currency_list.item_count):
		if str(currency_list.get_item_metadata(index)) == selected_currency_id:
			currency_list.select(index)
			break
	populate_currency_form()


func populate_currency_form() -> void:
	var data := EconomyCatalog.currency(currency_definitions, selected_currency_id)
	if data.is_empty():
		set_currency_form_enabled(false)
		currency_id_edit.text = ""
		currency_name_edit.text = ""
		currency_symbol_edit.text = ""
		return
	set_currency_form_enabled(true)
	currency_id_edit.text = selected_currency_id
	currency_name_edit.text = str(data.get("display_name", ""))
	currency_symbol_edit.text = str(data.get("symbol", ""))
	currency_starting_balance.value = float(data.get("starting_balance", 0))
	currency_max_balance.value = float(data.get("max_balance", EconomyCatalog.MAX_BALANCE))


func set_currency_form_enabled(enabled: bool) -> void:
	currency_name_edit.editable = enabled
	currency_symbol_edit.editable = enabled
	currency_starting_balance.editable = enabled
	currency_max_balance.editable = enabled
	currency_apply_button.disabled = not enabled
	currency_delete_button.disabled = not enabled


func add_currency() -> void:
	var currency_id := Repository.normalise_id(new_currency_id.text)
	if currency_id.is_empty() or currency_definitions.has(currency_id):
		set_status("Enter a unique valid currency ID.", true)
		return
	var currencies: Array = active_economy_catalog.get("currencies", [])
	currencies.append(EconomyCatalog.default_currency(currency_id, currency_id.replace("_", " ").capitalize(), currency_id.left(3).to_upper()))
	var previous := active_economy_catalog.duplicate(true)
	active_economy_catalog["currencies"] = currencies
	new_currency_id.clear()
	if save_economy_catalog(previous):
		rebuild_definitions()
		refresh_all_forms()
		select_currency_id(currency_id)
		set_status("Created currency '%s'." % currency_id, false)


func apply_currency() -> void:
	if selected_currency_id.is_empty():
		return
	var currencies: Array = active_economy_catalog.get("currencies", [])
	var found := false
	for index in range(currencies.size()):
		if typeof(currencies[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = currencies[index]
		if str(data.get("id", "")) != selected_currency_id:
			continue
		data["display_name"] = currency_name_edit.text.strip_edges()
		data["symbol"] = currency_symbol_edit.text.strip_edges()
		data["starting_balance"] = int(currency_starting_balance.value)
		data["max_balance"] = int(currency_max_balance.value)
		currencies[index] = data
		found = true
		break
	if not found:
		set_status("The selected currency is not in the editable primary catalogue.", true)
		return
	var previous := active_economy_catalog.duplicate(true)
	active_economy_catalog["currencies"] = currencies
	if save_economy_catalog(previous):
		rebuild_definitions()
		refresh_all_forms()
		select_currency_id(selected_currency_id)
		set_status("Updated currency '%s'." % selected_currency_id, false)


func delete_currency() -> void:
	if selected_currency_id.is_empty():
		return
	for merchant_id in merchant_definitions.keys():
		if EconomyCatalog.merchant_currency_id(EconomyCatalog.merchant(merchant_definitions, str(merchant_id))) == selected_currency_id:
			set_status("Cannot delete '%s'; merchant '%s' uses it." % [selected_currency_id, merchant_id], true)
			return
	var currencies: Array = active_economy_catalog.get("currencies", [])
	var previous := active_economy_catalog.duplicate(true)
	for index in range(currencies.size() - 1, -1, -1):
		if typeof(currencies[index]) == TYPE_DICTIONARY and str((currencies[index] as Dictionary).get("id", "")) == selected_currency_id:
			currencies.remove_at(index)
			break
	var deleted := selected_currency_id
	active_economy_catalog["currencies"] = currencies
	selected_currency_id = ""
	if save_economy_catalog(previous):
		rebuild_definitions()
		refresh_all_forms()
		set_status("Deleted currency '%s'." % deleted, false)


func refresh_currency_selectors() -> void:
	var requested := selected_option_metadata(merchant_currency_selector)
	merchant_currency_selector.clear()
	for currency_id in sorted_ids(currency_definitions):
		var data := EconomyCatalog.currency(currency_definitions, currency_id)
		var index := merchant_currency_selector.item_count
		merchant_currency_selector.add_item(str(data.get("display_name", currency_id)))
		merchant_currency_selector.set_item_metadata(index, currency_id)
	select_option_metadata(merchant_currency_selector, requested)


func refresh_merchant_list(preferred_id: String = "") -> void:
	merchant_list.clear()
	var ids := sorted_ids(merchant_definitions)
	for merchant_id in ids:
		var data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
		var index := merchant_list.item_count
		merchant_list.add_item(str(data.get("display_name", merchant_id)))
		merchant_list.set_item_metadata(index, merchant_id)
	if preferred_id.is_empty() and not ids.is_empty():
		preferred_id = ids[0]
	select_merchant_id(preferred_id)


func on_merchant_selected(index: int) -> void:
	if index >= 0 and index < merchant_list.item_count:
		select_merchant_id(str(merchant_list.get_item_metadata(index)))


func select_merchant_id(merchant_id: String) -> void:
	selected_merchant_id = merchant_id if merchant_definitions.has(merchant_id) else ""
	for index in range(merchant_list.item_count):
		if str(merchant_list.get_item_metadata(index)) == selected_merchant_id:
			merchant_list.select(index)
			break
	populate_merchant_form()


func populate_merchant_form() -> void:
	var data := EconomyCatalog.merchant(merchant_definitions, selected_merchant_id)
	if data.is_empty():
		set_merchant_form_enabled(false)
		merchant_id_edit.text = ""
		merchant_name_edit.text = ""
		merchant_stock_edit.text = ""
		return
	set_merchant_form_enabled(true)
	merchant_id_edit.text = selected_merchant_id
	merchant_name_edit.text = str(data.get("display_name", ""))
	select_option_metadata(merchant_currency_selector, str(data.get("currency_id", "")))
	merchant_greeting_edit.text = str(data.get("greeting", ""))
	merchant_farewell_edit.text = str(data.get("farewell", ""))
	merchant_buy_multiplier.value = float(data.get("buy_multiplier", 1.0))
	merchant_sell_multiplier.value = float(data.get("sell_multiplier", 0.5))
	merchant_accepts_sales.button_pressed = bool(data.get("accepts_sales", true))
	merchant_resells_goods.button_pressed = bool(data.get("resell_player_goods", true))
	merchant_accepted_kinds_edit.text = "\n".join(Array(EconomyCatalog.accepted_kinds(data)))
	merchant_refused_items_edit.text = "\n".join(Array(EconomyCatalog.refused_items(data)))
	merchant_conditions_edit.text = format_json_lines(StoryCatalog.conditions(data))
	merchant_stock_edit.text = format_json_lines(EconomyCatalog.stock_entries(data))


func set_merchant_form_enabled(enabled: bool) -> void:
	merchant_name_edit.editable = enabled
	merchant_currency_selector.disabled = not enabled
	merchant_greeting_edit.editable = enabled
	merchant_farewell_edit.editable = enabled
	merchant_buy_multiplier.editable = enabled
	merchant_sell_multiplier.editable = enabled
	merchant_accepts_sales.disabled = not enabled
	merchant_resells_goods.disabled = not enabled
	merchant_accepted_kinds_edit.editable = enabled
	merchant_refused_items_edit.editable = enabled
	merchant_conditions_edit.editable = enabled
	merchant_stock_edit.editable = enabled
	merchant_apply_button.disabled = not enabled
	merchant_delete_button.disabled = not enabled


func add_merchant() -> void:
	var merchant_id := Repository.normalise_id(new_merchant_id.text)
	if merchant_id.is_empty() or merchant_definitions.has(merchant_id):
		set_status("Enter a unique valid merchant ID.", true)
		return
	if currency_definitions.is_empty() or item_definitions.is_empty():
		set_status("Create at least one currency and item before adding a merchant.", true)
		return
	var currency_id := str(sorted_ids(currency_definitions)[0])
	var item_id := str(sorted_ids(item_definitions)[0])
	var merchants: Array = active_economy_catalog.get("merchants", [])
	merchants.append(EconomyCatalog.default_merchant(merchant_id, merchant_id.replace("_", " ").capitalize(), currency_id, item_id))
	var previous := active_economy_catalog.duplicate(true)
	active_economy_catalog["merchants"] = merchants
	new_merchant_id.clear()
	if save_economy_catalog(previous):
		rebuild_definitions()
		refresh_all_forms()
		select_merchant_id(merchant_id)
		set_status("Created merchant '%s'." % merchant_id, false)


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


func delete_merchant() -> void:
	if selected_merchant_id.is_empty():
		return
	for object_id in object_definitions.keys():
		var data: Dictionary = object_definitions.get(object_id, {})
		if str(data.get("merchant_id", "")) == selected_merchant_id:
			set_status("Cannot delete '%s'; NPC definition '%s' uses it." % [selected_merchant_id, object_id], true)
			return
	var merchants: Array = active_economy_catalog.get("merchants", [])
	var previous := active_economy_catalog.duplicate(true)
	for index in range(merchants.size() - 1, -1, -1):
		if typeof(merchants[index]) == TYPE_DICTIONARY and str((merchants[index] as Dictionary).get("id", "")) == selected_merchant_id:
			merchants.remove_at(index)
			break
	var deleted := selected_merchant_id
	active_economy_catalog["merchants"] = merchants
	selected_merchant_id = ""
	if save_economy_catalog(previous):
		rebuild_definitions()
		refresh_all_forms()
		set_status("Deleted merchant '%s'." % deleted, false)


func refresh_binding_list() -> void:
	binding_object_list.clear()
	var ids: Array[String] = []
	for object_id in object_definitions.keys():
		var data: Dictionary = object_definitions.get(object_id, {})
		if str(data.get("kind", "")) == "npc":
			ids.append(str(object_id))
	ids.sort_custom(func(left: String, right: String) -> bool:
		return str(object_definitions.get(left, {}).get("display_name", left)).naturalnocasecmp_to(str(object_definitions.get(right, {}).get("display_name", right))) < 0
	)
	for object_id in ids:
		var data: Dictionary = object_definitions.get(object_id, {})
		var merchant_id := str(data.get("merchant_id", ""))
		var label := str(data.get("display_name", object_id))
		if not merchant_id.is_empty():
			label += "  →  " + str(EconomyCatalog.merchant(merchant_definitions, merchant_id).get("display_name", merchant_id))
		var index := binding_object_list.item_count
		binding_object_list.add_item(label)
		binding_object_list.set_item_metadata(index, object_id)
	refresh_binding_merchant_selector()
	if not ids.is_empty():
		select_binding_object(str(ids[0]))
	else:
		select_binding_object("")


func refresh_binding_merchant_selector() -> void:
	binding_merchant_selector.clear()
	binding_merchant_selector.add_item("No merchant")
	binding_merchant_selector.set_item_metadata(0, "")
	for merchant_id in sorted_ids(merchant_definitions):
		var data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
		var index := binding_merchant_selector.item_count
		binding_merchant_selector.add_item(str(data.get("display_name", merchant_id)))
		binding_merchant_selector.set_item_metadata(index, merchant_id)


func on_binding_object_selected(index: int) -> void:
	if index >= 0 and index < binding_object_list.item_count:
		select_binding_object(str(binding_object_list.get_item_metadata(index)))


func select_binding_object(object_id: String) -> void:
	selected_object_id = object_id if object_definitions.has(object_id) else ""
	for index in range(binding_object_list.item_count):
		if str(binding_object_list.get_item_metadata(index)) == selected_object_id:
			binding_object_list.select(index)
			break
	var data := ObjectCatalog.definition(object_definitions, selected_object_id)
	if data.is_empty():
		binding_summary.text = "[color=#87949b]Select an NPC definition to bind it to a merchant record.[/color]"
		select_option_metadata(binding_merchant_selector, "")
		return
	var merchant_id := str(data.get("merchant_id", ""))
	binding_summary.text = "[font_size=18][color=#f0dfad]%s[/color][/font_size]\n[color=#8fa9a5]Object ID[/color]  %s\n[color=#8fa9a5]Current merchant[/color]  %s" % [str(data.get("display_name", selected_object_id)), selected_object_id, merchant_id if not merchant_id.is_empty() else "None"]
	select_option_metadata(binding_merchant_selector, merchant_id)


func apply_binding() -> void:
	if selected_object_id.is_empty():
		return
	set_object_merchant_binding(selected_option_metadata(binding_merchant_selector))


func clear_binding() -> void:
	if selected_object_id.is_empty():
		return
	set_object_merchant_binding("")


func set_object_merchant_binding(merchant_id: String) -> void:
	var objects: Array = active_object_catalog.get("objects", [])
	var found := false
	for index in range(objects.size()):
		if typeof(objects[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = objects[index]
		if str(data.get("id", "")) != selected_object_id:
			continue
		if merchant_id.is_empty():
			data.erase("merchant_id")
		else:
			data["merchant_id"] = merchant_id
		objects[index] = data
		found = true
		break
	if not found:
		set_status("The selected NPC is not in the editable primary object catalogue.", true)
		return
	var previous := active_object_catalog.duplicate(true)
	active_object_catalog["objects"] = objects
	if save_object_catalog(previous):
		rebuild_definitions()
		refresh_binding_list()
		select_binding_object(selected_object_id)
		set_status("Updated merchant binding for '%s'." % selected_object_id, false)


func save_economy_catalog(previous: Dictionary) -> bool:
	var result := Repository.save_json(active_economy_path, active_economy_catalog)
	if not bool(result.get("ok", false)):
		active_economy_catalog = previous
		set_status(format_messages(result.get("errors", [])), true)
		return false
	var report := EconomyValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		active_economy_catalog = previous
		Repository.save_json(active_economy_path, active_economy_catalog)
		set_status("Change rolled back. %s" % format_messages(report.get("errors", [])), true)
		return false
	rescan_editor_files()
	return true


func save_object_catalog(previous: Dictionary) -> bool:
	var result := Repository.save_json(active_object_path, active_object_catalog)
	if not bool(result.get("ok", false)):
		active_object_catalog = previous
		set_status(format_messages(result.get("errors", [])), true)
		return false
	var report := EconomyValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		active_object_catalog = previous
		Repository.save_json(active_object_path, active_object_catalog)
		set_status("Binding rolled back. %s" % format_messages(report.get("errors", [])), true)
		return false
	rescan_editor_files()
	return true


func parse_json_lines(text: String, label: String) -> Dictionary:
	var entries: Array = []
	var errors: Array[String] = []
	for raw_line in text.split("\n"):
		var line := str(raw_line).strip_edges()
		if line.is_empty():
			continue
		var parser := JSON.new()
		var error := parser.parse(line)
		if error != OK or typeof(parser.data) != TYPE_DICTIONARY:
			errors.append("%s line must be a complete JSON object: %s" % [label, line])
			continue
		entries.append(parser.data)
	return {"ok": errors.is_empty(), "entries": entries, "errors": errors}


func parse_id_lines(text: String, label: String) -> Dictionary:
	var entries: Array = []
	var errors: Array[String] = []
	for raw_line in text.split("\n"):
		var entry := str(raw_line).strip_edges()
		if entry.is_empty():
			continue
		if entries.has(entry):
			errors.append("%s repeats '%s'." % [label, entry])
		else:
			entries.append(entry)
	return {"ok": errors.is_empty(), "entries": entries, "errors": errors}


func format_json_lines(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return ""
	var lines := PackedStringArray()
	for entry in value:
		lines.append(JSON.stringify(entry, "", true))
	return "\n".join(lines)


func select_option_metadata(option: OptionButton, requested: String) -> void:
	if option == null or option.item_count == 0:
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


func validate_all_campaigns() -> void:
	var report := EconomyValidator.validate_all()
	set_status(format_report(report), not bool(report.get("ok", false)))


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(
		"%d currency definition(s), %d merchant(s), %d NPC binding(s), %d stock entry(s), %d warning(s), %d error(s)." % [
			report.get("currency_count", currency_definitions.size()),
			report.get("merchant_count", merchant_definitions.size()),
			report.get("merchant_binding_count", 0),
			report.get("merchant_stock_count", 0),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
	for warning in report.get("warnings", []):
		lines.append("WARNING: %s" % warning)
	for error in report.get("errors", []):
		lines.append("ERROR: %s" % error)
	return "\n".join(lines)


func format_messages(value: Variant) -> String:
	var lines := PackedStringArray()
	if typeof(value) == TYPE_ARRAY:
		for message in value:
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
	active_economy_catalog = {}
	active_economy_path = ""
	active_object_catalog = {}
	active_object_path = ""
	currency_definitions = {}
	merchant_definitions = {}
	item_definitions = {}
	object_definitions = {}
	selected_currency_id = ""
	selected_merchant_id = ""
	selected_object_id = ""
	currency_list.clear()
	merchant_list.clear()
	binding_object_list.clear()
	set_currency_form_enabled(false)
	set_merchant_form_enabled(false)
