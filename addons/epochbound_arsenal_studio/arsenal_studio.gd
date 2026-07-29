@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const ArsenalCatalog = preload("res://src/content/arsenal_catalog.gd")
const ArsenalValidator = preload("res://src/content/arsenal_validator.gd")

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_campaign_path := ""
var active_item_catalog: Dictionary = {}
var active_item_path := ""
var active_object_catalog: Dictionary = {}
var active_object_path := ""
var item_definitions: Dictionary = {}
var object_definitions: Dictionary = {}
var selected_weapon_id := ""
var selected_ammunition_id := ""
var selected_enemy_id := ""

var campaign_selector: OptionButton
var weapon_list: ItemList
var ammunition_list: ItemList
var enemy_list: ItemList
var new_weapon_id: LineEdit
var new_ammunition_id: LineEdit
var weapon_name: LineEdit
var weapon_description: TextEdit
var weapon_ammo_selector: OptionButton
var weapon_magazine: SpinBox
var weapon_damage: SpinBox
var weapon_speed: SpinBox
var weapon_range: SpinBox
var weapon_radius: SpinBox
var weapon_cooldown: SpinBox
var weapon_reload: SpinBox
var weapon_knockback: SpinBox
var weapon_muzzle: SpinBox
var weapon_color: LineEdit
var ammunition_name: LineEdit
var ammunition_description: TextEdit
var ammunition_stack: SpinBox
var ammunition_value: SpinBox
var ammunition_damage: SpinBox
var ammunition_knockback: SpinBox
var ammunition_color: LineEdit
var enemy_ranged_enabled: CheckBox
var enemy_attack_radius: SpinBox
var enemy_attack_damage: SpinBox
var enemy_attack_cooldown: SpinBox
var enemy_attack_windup: SpinBox
var enemy_projectile_speed: SpinBox
var enemy_projectile_range: SpinBox
var enemy_projectile_radius: SpinBox
var enemy_projectile_knockback: SpinBox
var enemy_projectile_color: LineEdit
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
	title.text = "Epochbound Arsenal Studio"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
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
	hint.text = "Ranged weapons, ammunition and enemy projectile profiles share Item Forge, Encounter Studio and save-state IDs."
	hint.modulate = Color("87949b")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_row.add_child(hint)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	build_weapon_tab(tabs)
	build_ammunition_tab(tabs)
	build_enemy_tab(tabs)

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 64
	status_label.text = "[color=#9aa8b5]Arsenal Studio ready.[/color]"
	root.add_child(status_label)


func build_weapon_tab(tabs: TabContainer) -> void:
	var panel := HSplitContainer.new()
	panel.name = "Ranged Weapons"
	tabs.add_child(panel)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260
	panel.add_child(left)
	left.add_child(make_heading("RANGED WEAPONS"))
	weapon_list = ItemList.new()
	weapon_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	weapon_list.item_selected.connect(on_weapon_selected)
	left.add_child(weapon_list)
	new_weapon_id = LineEdit.new()
	new_weapon_id.placeholder_text = "new_weapon_id"
	left.add_child(new_weapon_id)
	left.add_child(make_button("Create Ranged Weapon", create_ranged_weapon))
	left.add_child(make_button("Delete Selected Weapon", delete_selected_weapon))

	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 5)
	panel.add_child(form)
	weapon_name = add_line_field(form, "Display name")
	weapon_description = add_text_field(form, "Description", 72)
	weapon_ammo_selector = OptionButton.new()
	form.add_child(make_labeled_control("Ammunition item", weapon_ammo_selector))
	var grid := GridContainer.new()
	grid.columns = 3
	form.add_child(grid)
	weapon_magazine = add_spin_to_grid(grid, "Magazine", 1, ArsenalCatalog.MAX_MAGAZINE_SIZE, 1, 4)
	weapon_damage = add_spin_to_grid(grid, "Damage bonus", 0, ArsenalCatalog.MAX_DAMAGE_BONUS, 1, 1)
	weapon_speed = add_spin_to_grid(grid, "Projectile speed", 1, ArsenalCatalog.MAX_PROJECTILE_SPEED, 1, 340)
	weapon_range = add_spin_to_grid(grid, "Projectile range", 1, ArsenalCatalog.MAX_PROJECTILE_RANGE, 1, 270)
	weapon_radius = add_spin_to_grid(grid, "Projectile radius", 1, ArsenalCatalog.MAX_PROJECTILE_RADIUS, 0.5, 4)
	weapon_cooldown = add_spin_to_grid(grid, "Fire cooldown", 0.05, 10, 0.01, 0.42)
	weapon_reload = add_spin_to_grid(grid, "Reload time", 0.05, 20, 0.01, 0.85)
	weapon_knockback = add_spin_to_grid(grid, "Knockback", 0, ArsenalCatalog.MAX_KNOCKBACK, 1, 14)
	weapon_muzzle = add_spin_to_grid(grid, "Muzzle offset", 0, 64, 1, 15)
	weapon_color = add_line_field(form, "Projectile colour (HTML)")
	form.add_child(make_button("Apply Weapon Profile", apply_weapon_profile))


func build_ammunition_tab(tabs: TabContainer) -> void:
	var panel := HSplitContainer.new()
	panel.name = "Ammunition"
	tabs.add_child(panel)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260
	panel.add_child(left)
	left.add_child(make_heading("AMMUNITION"))
	ammunition_list = ItemList.new()
	ammunition_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ammunition_list.item_selected.connect(on_ammunition_selected)
	left.add_child(ammunition_list)
	new_ammunition_id = LineEdit.new()
	new_ammunition_id.placeholder_text = "new_ammunition_id"
	left.add_child(new_ammunition_id)
	left.add_child(make_button("Create Ammunition", create_ammunition))
	left.add_child(make_button("Delete Selected Ammunition", delete_selected_ammunition))

	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 5)
	panel.add_child(form)
	ammunition_name = add_line_field(form, "Display name")
	ammunition_description = add_text_field(form, "Description", 90)
	var grid := GridContainer.new()
	grid.columns = 3
	form.add_child(grid)
	ammunition_stack = add_spin_to_grid(grid, "Stack limit", 2, 999, 1, 60)
	ammunition_value = add_spin_to_grid(grid, "Economy value", 0, 999999, 1, 2)
	ammunition_damage = add_spin_to_grid(grid, "Damage bonus", 0, ArsenalCatalog.MAX_DAMAGE_BONUS, 1, 0)
	ammunition_knockback = add_spin_to_grid(grid, "Knockback bonus", 0, ArsenalCatalog.MAX_KNOCKBACK, 1, 0)
	ammunition_color = add_line_field(form, "Projectile colour (HTML)")
	form.add_child(make_button("Apply Ammunition", apply_ammunition_profile))


func build_enemy_tab(tabs: TabContainer) -> void:
	var panel := HSplitContainer.new()
	panel.name = "Ranged Enemies"
	tabs.add_child(panel)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	panel.add_child(left)
	left.add_child(make_heading("ENEMY DEFINITIONS"))
	enemy_list = ItemList.new()
	enemy_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_list.item_selected.connect(on_enemy_selected)
	left.add_child(enemy_list)

	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 5)
	panel.add_child(form)
	enemy_ranged_enabled = CheckBox.new()
	enemy_ranged_enabled.text = "Enable projectile attack"
	form.add_child(enemy_ranged_enabled)
	var grid := GridContainer.new()
	grid.columns = 3
	form.add_child(grid)
	enemy_attack_radius = add_spin_to_grid(grid, "Attack radius", 1, 2400, 1, 160)
	enemy_attack_damage = add_spin_to_grid(grid, "Attack damage", 1, 999, 1, 3)
	enemy_attack_cooldown = add_spin_to_grid(grid, "Attack cooldown", 0.05, 20, 0.01, 1.4)
	enemy_attack_windup = add_spin_to_grid(grid, "Attack windup", 0.05, 10, 0.01, 0.45)
	enemy_projectile_speed = add_spin_to_grid(grid, "Projectile speed", 1, ArsenalCatalog.MAX_PROJECTILE_SPEED, 1, 210)
	enemy_projectile_range = add_spin_to_grid(grid, "Projectile range", 1, ArsenalCatalog.MAX_PROJECTILE_RANGE, 1, 220)
	enemy_projectile_radius = add_spin_to_grid(grid, "Projectile radius", 1, ArsenalCatalog.MAX_PROJECTILE_RADIUS, 0.5, 4)
	enemy_projectile_knockback = add_spin_to_grid(grid, "Knockback", 0, ArsenalCatalog.MAX_KNOCKBACK, 1, 18)
	enemy_projectile_color = add_line_field(form, "Projectile colour (HTML)")
	form.add_child(make_button("Apply Enemy Projectile Profile", apply_enemy_profile))
	var help := RichTextLabel.new()
	help.fit_content = true
	help.bbcode_enabled = true
	help.text = "[color=#87949b]Enemy attack radius determines when its existing windup begins. Damage is applied only when the authored projectile reaches the player or companion.[/color]"
	form.add_child(help)


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


func add_line_field(parent: Control, label: String) -> LineEdit:
	var edit := LineEdit.new()
	parent.add_child(make_labeled_control(label, edit))
	return edit


func add_text_field(parent: Control, label: String, height: float) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size.y = height
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(make_labeled_control(label, edit))
	return edit


func add_spin_to_grid(
	grid: GridContainer,
	label: String,
	minimum: float,
	maximum: float,
	step: float,
	initial: float
) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = initial
	spin.custom_minimum_size.x = 150
	grid.add_child(make_labeled_control(label, spin))
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
		clear_campaign()
		set_status("No source campaigns were found under res://campaigns.", true)
		return
	campaign_selector.select(selected_index)
	on_campaign_selected(selected_index)


func on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = str(campaign_selector.get_item_metadata(index))
	var result := Repository.read_json(active_campaign_path)
	if not bool(result.get("ok", false)):
		clear_campaign()
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	load_primary_catalogs()
	rebuild_definitions()
	refresh_all_lists()
	var report := ArsenalValidator.validate_campaign_path(active_campaign_path)
	set_status(format_report(report), not bool(report.get("ok", false)))


func load_primary_catalogs() -> void:
	active_item_path = ItemCatalog.primary_item_catalog_path(active_campaign_path, active_campaign)
	var item_result := Repository.read_json(active_item_path)
	active_item_catalog = item_result.get("data", ItemCatalog.default_item_catalog()) if bool(item_result.get("ok", false)) else ItemCatalog.default_item_catalog()
	active_object_path = ObjectCatalog.primary_catalog_path(active_campaign_path, active_campaign)
	var object_result := Repository.read_json(active_object_path)
	active_object_catalog = object_result.get("data", ObjectCatalog.default_catalog()) if bool(object_result.get("ok", false)) else ObjectCatalog.default_catalog()


func rebuild_definitions() -> void:
	var item_result := ItemCatalog.load_item_catalogs(active_campaign_path, active_campaign)
	item_definitions = item_result.get("definitions", {})
	var object_result := ObjectCatalog.load_catalogs(active_campaign_path, active_campaign)
	object_definitions = object_result.get("definitions", {})


func refresh_all_lists() -> void:
	refresh_ammunition_selector()
	refresh_weapon_list()
	refresh_ammunition_list()
	refresh_enemy_list()


func refresh_weapon_list() -> void:
	weapon_list.clear()
	for weapon_id in ArsenalCatalog.ranged_weapon_ids(item_definitions):
		var item_data := ItemCatalog.item(item_definitions, weapon_id)
		var index := weapon_list.item_count
		weapon_list.add_item(ItemCatalog.item_name(item_data, weapon_id))
		weapon_list.set_item_metadata(index, weapon_id)
	if weapon_list.item_count > 0:
		weapon_list.select(0)
		on_weapon_selected(0)
	else:
		selected_weapon_id = ""
		clear_weapon_form()


func refresh_ammunition_list() -> void:
	ammunition_list.clear()
	for ammunition_id in ArsenalCatalog.ammunition_ids(item_definitions):
		var item_data := ItemCatalog.item(item_definitions, ammunition_id)
		var index := ammunition_list.item_count
		ammunition_list.add_item(ItemCatalog.item_name(item_data, ammunition_id))
		ammunition_list.set_item_metadata(index, ammunition_id)
	if ammunition_list.item_count > 0:
		ammunition_list.select(0)
		on_ammunition_selected(0)
	else:
		selected_ammunition_id = ""
		clear_ammunition_form()


func refresh_enemy_list() -> void:
	enemy_list.clear()
	var ids: Array[String] = []
	for object_id_value in object_definitions.keys():
		var object_id := str(object_id_value)
		if str((object_definitions.get(object_id, {}) as Dictionary).get("kind", "")) == "enemy":
			ids.append(object_id)
	ids.sort()
	for object_id in ids:
		var data: Dictionary = object_definitions.get(object_id, {})
		var label := str(data.get("display_name", object_id))
		if ArsenalCatalog.is_ranged_enemy(data):
			label += "  •  RANGED"
		var index := enemy_list.item_count
		enemy_list.add_item(label)
		enemy_list.set_item_metadata(index, object_id)
	if enemy_list.item_count > 0:
		enemy_list.select(0)
		on_enemy_selected(0)
	else:
		selected_enemy_id = ""
		clear_enemy_form()


func refresh_ammunition_selector(requested: String = "") -> void:
	weapon_ammo_selector.clear()
	for ammunition_id in ArsenalCatalog.ammunition_ids(item_definitions):
		var data := ItemCatalog.item(item_definitions, ammunition_id)
		var index := weapon_ammo_selector.item_count
		weapon_ammo_selector.add_item(ItemCatalog.item_name(data, ammunition_id))
		weapon_ammo_selector.set_item_metadata(index, ammunition_id)
	select_option_metadata(weapon_ammo_selector, requested)


func on_weapon_selected(index: int) -> void:
	if index < 0 or index >= weapon_list.item_count:
		return
	select_weapon_id(str(weapon_list.get_item_metadata(index)))


func select_weapon_id(weapon_id: String) -> void:
	selected_weapon_id = weapon_id
	var item_data := ItemCatalog.item(item_definitions, weapon_id)
	if item_data.is_empty():
		clear_weapon_form()
		return
	var ranged := ArsenalCatalog.ranged_data(item_data)
	weapon_name.text = ItemCatalog.item_name(item_data, weapon_id)
	weapon_description.text = str(item_data.get("description", ""))
	refresh_ammunition_selector(str(ranged.get("ammo_item_id", "")))
	weapon_magazine.value = float(ranged.get("magazine_size", 4))
	weapon_damage.value = float(ranged.get("damage_bonus", 1))
	weapon_speed.value = float(ranged.get("projectile_speed", 340.0))
	weapon_range.value = float(ranged.get("projectile_range", 270.0))
	weapon_radius.value = float(ranged.get("projectile_radius", 4.0))
	weapon_cooldown.value = float(ranged.get("fire_cooldown", 0.42))
	weapon_reload.value = float(ranged.get("reload_time", 0.85))
	weapon_knockback.value = float(ranged.get("knockback_distance", 14.0))
	weapon_muzzle.value = float(ranged.get("muzzle_offset", 15.0))
	weapon_color.text = str(ranged.get("projectile_color", ArsenalCatalog.DEFAULT_PROJECTILE_COLOR))


func on_ammunition_selected(index: int) -> void:
	if index < 0 or index >= ammunition_list.item_count:
		return
	select_ammunition_id(str(ammunition_list.get_item_metadata(index)))


func select_ammunition_id(ammunition_id: String) -> void:
	selected_ammunition_id = ammunition_id
	var item_data := ItemCatalog.item(item_definitions, ammunition_id)
	if item_data.is_empty():
		clear_ammunition_form()
		return
	var ammunition := ArsenalCatalog.ammunition_data(item_data)
	ammunition_name.text = ItemCatalog.item_name(item_data, ammunition_id)
	ammunition_description.text = str(item_data.get("description", ""))
	ammunition_stack.value = ItemCatalog.stack_limit(item_data)
	ammunition_value.value = int(item_data.get("value", 0))
	ammunition_damage.value = int(ammunition.get("damage_bonus", 0))
	ammunition_knockback.value = float(ammunition.get("knockback_bonus", 0.0))
	ammunition_color.text = str(ammunition.get("projectile_color", ArsenalCatalog.DEFAULT_PROJECTILE_COLOR))


func on_enemy_selected(index: int) -> void:
	if index < 0 or index >= enemy_list.item_count:
		return
	select_enemy_id(str(enemy_list.get_item_metadata(index)))


func select_enemy_id(enemy_id: String) -> void:
	selected_enemy_id = enemy_id
	var data: Dictionary = object_definitions.get(enemy_id, {})
	if data.is_empty():
		clear_enemy_form()
		return
	var ranged := ArsenalCatalog.enemy_ranged_data(data)
	enemy_ranged_enabled.button_pressed = not ranged.is_empty()
	enemy_attack_radius.value = float(data.get("attack_radius", 160.0))
	enemy_attack_damage.value = float(data.get("attack_damage", 3))
	enemy_attack_cooldown.value = float(data.get("attack_cooldown", 1.4))
	enemy_attack_windup.value = float(data.get("attack_windup", 0.45))
	enemy_projectile_speed.value = float(ranged.get("projectile_speed", 210.0))
	enemy_projectile_range.value = float(ranged.get("projectile_range", 220.0))
	enemy_projectile_radius.value = float(ranged.get("projectile_radius", 4.0))
	enemy_projectile_knockback.value = float(ranged.get("knockback_distance", 18.0))
	enemy_projectile_color.text = str(ranged.get("projectile_color", ArsenalCatalog.DEFAULT_ENEMY_PROJECTILE_COLOR))


func create_ammunition() -> void:
	var item_id := Repository.normalise_id(new_ammunition_id.text)
	if item_id.is_empty():
		set_status("Enter a valid ammunition ID.", true)
		return
	if item_definitions.has(item_id):
		set_status("Item '%s' already exists." % item_id, true)
		return
	var items: Array = active_item_catalog.get("items", [])
	items.append(ArsenalCatalog.default_ammunition(item_id, item_id.replace("_", " ").capitalize()))
	active_item_catalog["items"] = items
	new_ammunition_id.clear()
	if save_item_catalog():
		rebuild_definitions()
		refresh_all_lists()
		select_ammunition_id(item_id)
		set_status("Created ammunition '%s'." % item_id, false)


func create_ranged_weapon() -> void:
	var item_id := Repository.normalise_id(new_weapon_id.text)
	if item_id.is_empty():
		set_status("Enter a valid weapon ID.", true)
		return
	if item_definitions.has(item_id):
		set_status("Item '%s' already exists." % item_id, true)
		return
	var ammunition_ids := ArsenalCatalog.ammunition_ids(item_definitions)
	if ammunition_ids.is_empty():
		set_status("Create at least one ammunition item first.", true)
		return
	var data := ItemCatalog.default_item(item_id, item_id.replace("_", " ").capitalize())
	data["kind"] = "equipment"
	data["stack_limit"] = 1
	data["value"] = 45
	data["equipment"] = ArsenalCatalog.default_ranged_equipment(str(ammunition_ids[0]))
	var items: Array = active_item_catalog.get("items", [])
	items.append(data)
	active_item_catalog["items"] = items
	new_weapon_id.clear()
	if save_item_catalog():
		rebuild_definitions()
		refresh_all_lists()
		select_weapon_id(item_id)
		set_status("Created ranged weapon '%s'." % item_id, false)


func apply_weapon_profile() -> void:
	if selected_weapon_id.is_empty():
		return
	var ammo_item_id := selected_option_metadata(weapon_ammo_selector)
	if ammo_item_id.is_empty():
		set_status("Select an ammunition item.", true)
		return
	if not Color.html_is_valid(weapon_color.text.strip_edges()):
		set_status("Weapon projectile colour is invalid.", true)
		return
	var items: Array = active_item_catalog.get("items", [])
	var changed := false
	for index in range(items.size()):
		if typeof(items[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = items[index]
		if str(data.get("id", "")) != selected_weapon_id:
			continue
		data["display_name"] = weapon_name.text.strip_edges()
		data["description"] = weapon_description.text.strip_edges()
		data["kind"] = "equipment"
		data["stack_limit"] = 1
		var equipment := EquipmentCatalog.equipment_data(data).duplicate(true)
		if equipment.is_empty():
			equipment = EquipmentCatalog.default_equipment("weapon")
		equipment["slot"] = "weapon"
		equipment["ranged"] = {
			"ammo_item_id": ammo_item_id,
			"magazine_size": int(weapon_magazine.value),
			"damage_bonus": int(weapon_damage.value),
			"projectile_speed": weapon_speed.value,
			"projectile_range": weapon_range.value,
			"projectile_radius": weapon_radius.value,
			"fire_cooldown": weapon_cooldown.value,
			"reload_time": weapon_reload.value,
			"knockback_distance": weapon_knockback.value,
			"muzzle_offset": weapon_muzzle.value,
			"projectile_color": weapon_color.text.strip_edges()
		}
		data["equipment"] = equipment
		items[index] = data
		changed = true
		break
	if not changed:
		set_status("Selected weapon is not in the editable primary catalogue.", true)
		return
	active_item_catalog["items"] = items
	if save_item_catalog():
		rebuild_definitions()
		refresh_all_lists()
		select_weapon_id(selected_weapon_id)
		set_status("Updated ranged weapon '%s'." % selected_weapon_id, false)


func apply_ammunition_profile() -> void:
	if selected_ammunition_id.is_empty():
		return
	if not Color.html_is_valid(ammunition_color.text.strip_edges()):
		set_status("Ammunition projectile colour is invalid.", true)
		return
	var items: Array = active_item_catalog.get("items", [])
	var changed := false
	for index in range(items.size()):
		if typeof(items[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = items[index]
		if str(data.get("id", "")) != selected_ammunition_id:
			continue
		data["display_name"] = ammunition_name.text.strip_edges()
		data["description"] = ammunition_description.text.strip_edges()
		data["kind"] = "ammunition"
		data["stack_limit"] = int(ammunition_stack.value)
		data["value"] = int(ammunition_value.value)
		data["use_effect"] = {"type": "none"}
		data["ammunition"] = {
			"damage_bonus": int(ammunition_damage.value),
			"knockback_bonus": ammunition_knockback.value,
			"projectile_color": ammunition_color.text.strip_edges()
		}
		data.erase("equipment")
		items[index] = data
		changed = true
		break
	if not changed:
		set_status("Selected ammunition is not in the editable primary catalogue.", true)
		return
	active_item_catalog["items"] = items
	if save_item_catalog():
		rebuild_definitions()
		refresh_all_lists()
		select_ammunition_id(selected_ammunition_id)
		set_status("Updated ammunition '%s'." % selected_ammunition_id, false)


func apply_enemy_profile() -> void:
	if selected_enemy_id.is_empty():
		return
	if enemy_ranged_enabled.button_pressed and not Color.html_is_valid(enemy_projectile_color.text.strip_edges()):
		set_status("Enemy projectile colour is invalid.", true)
		return
	var objects: Array = active_object_catalog.get("objects", [])
	var changed := false
	for index in range(objects.size()):
		if typeof(objects[index]) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = objects[index]
		if str(data.get("id", "")) != selected_enemy_id:
			continue
		data["attack_radius"] = enemy_attack_radius.value
		data["attack_damage"] = int(enemy_attack_damage.value)
		data["attack_cooldown"] = enemy_attack_cooldown.value
		data["attack_windup"] = enemy_attack_windup.value
		if enemy_ranged_enabled.button_pressed:
			data["ranged_attack"] = {
				"projectile_speed": enemy_projectile_speed.value,
				"projectile_range": enemy_projectile_range.value,
				"projectile_radius": enemy_projectile_radius.value,
				"knockback_distance": enemy_projectile_knockback.value,
				"projectile_color": enemy_projectile_color.text.strip_edges()
			}
		else:
			data.erase("ranged_attack")
		objects[index] = data
		changed = true
		break
	if not changed:
		set_status("Selected enemy is not in the editable primary catalogue.", true)
		return
	active_object_catalog["objects"] = objects
	if save_object_catalog():
		rebuild_definitions()
		refresh_enemy_list()
		select_enemy_id(selected_enemy_id)
		set_status("Updated enemy projectile profile '%s'." % selected_enemy_id, false)


func delete_selected_ammunition() -> void:
	if selected_ammunition_id.is_empty():
		return
	var usages := item_usages(selected_ammunition_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; used by %s." % [selected_ammunition_id, ", ".join(usages)], true)
		return
	delete_primary_item(selected_ammunition_id)


func delete_selected_weapon() -> void:
	if selected_weapon_id.is_empty():
		return
	var usages := item_usages(selected_weapon_id)
	if not usages.is_empty():
		set_status("Cannot delete '%s'; used by %s." % [selected_weapon_id, ", ".join(usages)], true)
		return
	delete_primary_item(selected_weapon_id)


func delete_primary_item(item_id: String) -> void:
	var items: Array = active_item_catalog.get("items", [])
	var removed := false
	for index in range(items.size() - 1, -1, -1):
		if typeof(items[index]) == TYPE_DICTIONARY and str((items[index] as Dictionary).get("id", "")) == item_id:
			items.remove_at(index)
			removed = true
			break
	if not removed:
		set_status("Items from secondary catalogues are read-only in this slice.", true)
		return
	active_item_catalog["items"] = items
	if save_item_catalog():
		rebuild_definitions()
		refresh_all_lists()
		set_status("Deleted item '%s'." % item_id, false)


func item_usages(item_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	for weapon_id in ArsenalCatalog.ranged_weapon_ids(item_definitions):
		if weapon_id != item_id and ArsenalCatalog.weapon_ammunition_id(ItemCatalog.item(item_definitions, weapon_id)) == item_id:
			usages.append("ranged weapon %s ammunition" % weapon_id)
	for entry_value in ItemCatalog.starting_inventory(active_campaign):
		if typeof(entry_value) == TYPE_DICTIONARY and str((entry_value as Dictionary).get("item_id", "")) == item_id:
			usages.append("starting inventory")
	var starting_equipment_value: Variant = active_campaign.get("starting_equipment", {})
	if typeof(starting_equipment_value) == TYPE_DICTIONARY and (starting_equipment_value as Dictionary).values().has(item_id):
		usages.append("starting equipment")
	var economy_result := EconomyCatalog.load_catalogs(active_campaign_path, active_campaign)
	var merchants: Dictionary = economy_result.get("merchants", {})
	for merchant_id_value in merchants.keys():
		var merchant_id := str(merchant_id_value)
		var merchant_data := EconomyCatalog.merchant(merchants, merchant_id)
		if EconomyCatalog.stock_entry_index(merchant_data).has(item_id):
			usages.append("merchant %s stock" % merchant_id)
		if EconomyCatalog.refused_items(merchant_data).has(item_id):
			usages.append("merchant %s refusal rule" % merchant_id)
	return usages


func save_item_catalog() -> bool:
	var previous_result := Repository.read_json(active_item_path)
	if not bool(previous_result.get("ok", false)):
		set_status(format_messages(previous_result.get("errors", [])), true)
		return false
	var previous: Dictionary = (previous_result.get("data", {}) as Dictionary).duplicate(true)
	var result := Repository.save_json(active_item_path, active_item_catalog)
	if not bool(result.get("ok", false)):
		set_status(format_messages(result.get("errors", [])), true)
		return false
	rescan_editor_files()
	var report := ArsenalValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		var rollback := Repository.save_json(active_item_path, previous)
		active_item_catalog = previous
		rebuild_definitions()
		rescan_editor_files()
		if not bool(rollback.get("ok", false)):
			set_status("Invalid Arsenal edit and rollback failed: %s" % format_messages(rollback.get("errors", [])), true)
		else:
			set_status("Invalid Arsenal item edit was rolled back. %s" % format_report(report), true)
		return false
	return true


func save_object_catalog() -> bool:
	var previous_result := Repository.read_json(active_object_path)
	if not bool(previous_result.get("ok", false)):
		set_status(format_messages(previous_result.get("errors", [])), true)
		return false
	var previous: Dictionary = (previous_result.get("data", {}) as Dictionary).duplicate(true)
	var result := Repository.save_json(active_object_path, active_object_catalog)
	if not bool(result.get("ok", false)):
		set_status(format_messages(result.get("errors", [])), true)
		return false
	rescan_editor_files()
	var report := ArsenalValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		var rollback := Repository.save_json(active_object_path, previous)
		active_object_catalog = previous
		rebuild_definitions()
		rescan_editor_files()
		if not bool(rollback.get("ok", false)):
			set_status("Invalid enemy-profile edit and rollback failed: %s" % format_messages(rollback.get("errors", [])), true)
		else:
			set_status("Invalid enemy-profile edit was rolled back. %s" % format_report(report), true)
		return false
	return true


func selected_option_metadata(option: OptionButton) -> String:
	if option.item_count == 0 or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func select_option_metadata(option: OptionButton, requested: String) -> void:
	if option.item_count == 0:
		return
	var selected_index := 0
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == requested:
			selected_index = index
			break
	option.select(selected_index)


func clear_weapon_form() -> void:
	weapon_name.text = ""
	weapon_description.text = ""
	weapon_color.text = ArsenalCatalog.DEFAULT_PROJECTILE_COLOR


func clear_ammunition_form() -> void:
	ammunition_name.text = ""
	ammunition_description.text = ""
	ammunition_color.text = ArsenalCatalog.DEFAULT_PROJECTILE_COLOR


func clear_enemy_form() -> void:
	enemy_ranged_enabled.button_pressed = false
	enemy_projectile_color.text = ArsenalCatalog.DEFAULT_ENEMY_PROJECTILE_COLOR


func clear_campaign() -> void:
	active_campaign = {}
	active_campaign_path = ""
	active_item_catalog = {}
	active_item_path = ""
	active_object_catalog = {}
	active_object_path = ""
	item_definitions = {}
	object_definitions = {}
	weapon_list.clear()
	ammunition_list.clear()
	enemy_list.clear()


func validate_all_campaigns() -> void:
	var report := ArsenalValidator.validate_all()
	set_status(format_report(report), not bool(report.get("ok", false)))


func format_report(report: Dictionary) -> String:
	var errors_value: Variant = report.get("errors", [])
	var warnings_value: Variant = report.get("warnings", [])
	var lines := PackedStringArray()
	lines.append(
		"%d ammunition type(s), %d ranged weapon(s), %d ranged enemy profile(s), %d warning(s), %d error(s)." % [
			report.get("ammunition_count", 0),
			report.get("ranged_weapon_count", 0),
			report.get("ranged_enemy_count", 0),
			warnings_value.size() if typeof(warnings_value) == TYPE_ARRAY else 0,
			errors_value.size() if typeof(errors_value) == TYPE_ARRAY else 0
		]
	)
	if typeof(warnings_value) == TYPE_ARRAY:
		for warning in warnings_value:
			lines.append("WARNING: %s" % warning)
	if typeof(errors_value) == TYPE_ARRAY:
		for error in errors_value:
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
