@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const Validator = preload("res://src/content/epochbound_validator.gd")
const MapModel = preload("res://src/content/map_model.gd")
const EncounterCanvas = preload("res://addons/epochbound_encounter_studio/encounter_canvas.gd")
const HISTORY_LIMIT := 40

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_campaign_path := ""
var active_map: Dictionary = {}
var active_map_path := ""
var active_catalog: Dictionary = {}
var active_catalog_path := ""
var catalog_files: Array = []
var definitions: Dictionary = {}
var ordered_definition_ids := PackedStringArray()
var selected_definition_id := ""
var selected_placement_index := -1
var map_undo_stack: Array = []
var map_redo_stack: Array = []

var campaign_selector: OptionButton
var map_selector: OptionButton
var era_selector: OptionButton
var definition_list: ItemList
var new_definition_id: LineEdit
var placement_object_selector: OptionButton
var tool_selector: OptionButton
var placement_era_only: CheckBox
var show_collision: CheckBox
var show_navigation: CheckBox
var show_world_markers: CheckBox
var canvas
var undo_button: Button
var redo_button: Button
var status_label: RichTextLabel

var definition_id_edit: LineEdit
var definition_name_edit: LineEdit
var definition_kind_selector: OptionButton
var definition_shape_selector: OptionButton
var definition_color_edit: LineEdit
var definition_accent_edit: LineEdit
var definition_solid: CheckBox
var definition_collision_radius: SpinBox
var definition_interaction_radius: SpinBox
var definition_dialogue: TextEdit
var definition_max_health: SpinBox
var definition_move_speed: SpinBox
var definition_awareness_radius: SpinBox
var definition_attack_radius: SpinBox
var definition_attack_damage: SpinBox
var definition_attack_cooldown: SpinBox
var definition_value: SpinBox
var definition_pickup_label: LineEdit
var definition_apply_button: Button
var definition_delete_button: Button

var placement_id_edit: LineEdit
var placement_definition_selector: OptionButton
var placement_x: SpinBox
var placement_y: SpinBox
var placement_facing_selector: OptionButton
var placement_state_key: LineEdit
var placement_scope_only: CheckBox
var placement_apply_button: Button
var placement_delete_button: Button


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
	title.text = "Epochbound Encounter Studio"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 165
	campaign_selector.item_selected.connect(_on_campaign_selected)
	header.add_child(campaign_selector)
	map_selector = OptionButton.new()
	map_selector.custom_minimum_size.x = 155
	map_selector.item_selected.connect(_on_map_selected)
	header.add_child(map_selector)
	era_selector = OptionButton.new()
	era_selector.custom_minimum_size.x = 125
	era_selector.item_selected.connect(_on_era_selected)
	header.add_child(era_selector)
	header.add_child(make_button("Refresh", refresh_campaigns))
	header.add_child(make_button("Validate All", validate_all_campaigns))
	header.add_child(make_button("Open Folder", open_campaign_folder))

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 235
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)
	left.add_child(make_heading("OBJECT CATALOG"))
	definition_list = ItemList.new()
	definition_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	definition_list.item_selected.connect(_on_definition_selected)
	left.add_child(definition_list)
	new_definition_id = LineEdit.new()
	new_definition_id.placeholder_text = "new_object_id"
	left.add_child(new_definition_id)
	left.add_child(make_button("Add Object Type", add_definition))
	left.add_child(make_button("Save Catalog", save_catalog))
	var catalog_hint := Label.new()
	catalog_hint.text = "Object types are reusable. Stable IDs cannot be renamed after creation; display names remain editable."
	catalog_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	catalog_hint.modulate = Color("7f8c95")
	left.add_child(catalog_hint)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 3.0
	center.add_theme_constant_override("separation", 5)
	split.add_child(center)
	var toolbar := HBoxContainer.new()
	center.add_child(toolbar)
	toolbar.add_child(make_heading("TOOL"))
	tool_selector = OptionButton.new()
	tool_selector.add_item("Select")
	tool_selector.set_item_metadata(0, "select")
	tool_selector.add_item("Place Object")
	tool_selector.set_item_metadata(1, "place_object")
	tool_selector.item_selected.connect(_on_tool_selected)
	toolbar.add_child(tool_selector)
	toolbar.add_child(make_heading("OBJECT"))
	placement_object_selector = OptionButton.new()
	placement_object_selector.custom_minimum_size.x = 170
	toolbar.add_child(placement_object_selector)
	placement_era_only = CheckBox.new()
	placement_era_only.text = "Selected era only"
	toolbar.add_child(placement_era_only)
	var toolbar_spacer := Control.new()
	toolbar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(toolbar_spacer)
	undo_button = make_button("Undo", undo_map_change)
	redo_button = make_button("Redo", redo_map_change)
	toolbar.add_child(undo_button)
	toolbar.add_child(redo_button)
	toolbar.add_child(make_button("Save Map", save_map))

	var overlay_bar := HBoxContainer.new()
	center.add_child(overlay_bar)
	overlay_bar.add_child(make_heading("OVERLAYS"))
	show_collision = make_check("Collision", false, _on_overlay_changed)
	show_navigation = make_check("Navigation", false, _on_overlay_changed)
	show_world_markers = make_check("World markers", true, _on_overlay_changed)
	overlay_bar.add_child(show_collision)
	overlay_bar.add_child(show_navigation)
	overlay_bar.add_child(show_world_markers)
	var overlay_spacer := Control.new()
	overlay_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_bar.add_child(overlay_spacer)
	overlay_bar.add_child(make_button("Reset View", reset_canvas_view))

	canvas = EncounterCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.canvas_action.connect(_on_canvas_action)
	center.add_child(canvas)

	var inspector := TabContainer.new()
	inspector.custom_minimum_size.x = 345
	split.add_child(inspector)
	var definition_scroll := ScrollContainer.new()
	definition_scroll.name = "Object Type"
	definition_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(definition_scroll)
	var definition_panel := VBoxContainer.new()
	definition_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	definition_panel.add_theme_constant_override("separation", 6)
	definition_scroll.add_child(definition_panel)
	build_definition_inspector(definition_panel)
	var placement_scroll := ScrollContainer.new()
	placement_scroll.name = "Placement"
	placement_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(placement_scroll)
	var placement_panel := VBoxContainer.new()
	placement_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placement_panel.add_theme_constant_override("separation", 6)
	placement_scroll.add_child(placement_panel)
	build_placement_inspector(placement_panel)

	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = false
	status_label.fit_content = true
	status_label.custom_minimum_size.y = 68
	status_label.text = "Encounter Studio ready."
	status_label.modulate = Color("9aa8b5")
	root.add_child(status_label)
	set_definition_inspector_enabled(false)
	set_placement_inspector_enabled(false)
	update_history_buttons()


func build_definition_inspector(parent: VBoxContainer) -> void:
	parent.add_child(make_heading("REUSABLE OBJECT TYPE"))
	definition_id_edit = add_line_field(parent, "Stable ID", "")
	definition_id_edit.editable = false
	definition_name_edit = add_line_field(parent, "Display name", "")
	definition_kind_selector = add_option_field(parent, "Kind", ObjectCatalog.ALLOWED_KINDS)
	definition_kind_selector.item_selected.connect(_on_definition_kind_changed)
	definition_shape_selector = add_option_field(parent, "Blockout shape", ObjectCatalog.ALLOWED_SHAPES)
	definition_color_edit = add_line_field(parent, "Base colour", "66717a")
	definition_accent_edit = add_line_field(parent, "Accent colour", "d4c68f")
	definition_solid = CheckBox.new()
	definition_solid.text = "Solid collision object"
	parent.add_child(definition_solid)
	definition_collision_radius = add_spin_field(parent, "Collision radius", 0.0, 256.0, 1.0)
	definition_interaction_radius = add_spin_field(parent, "Interaction radius", 0.0, 512.0, 1.0)
	parent.add_child(make_field_label("Dialogue or description"))
	definition_dialogue = TextEdit.new()
	definition_dialogue.custom_minimum_size.y = 110
	parent.add_child(definition_dialogue)
	parent.add_child(make_heading("ENEMY / PICKUP VALUES"))
	definition_max_health = add_spin_field(parent, "Max health", 1.0, 9999.0, 1.0)
	definition_move_speed = add_spin_field(parent, "Move speed", 1.0, 1000.0, 1.0)
	definition_awareness_radius = add_spin_field(parent, "Awareness radius", 1.0, 2048.0, 1.0)
	definition_attack_radius = add_spin_field(parent, "Attack radius", 1.0, 512.0, 1.0)
	definition_attack_damage = add_spin_field(parent, "Attack damage", 1.0, 9999.0, 1.0)
	definition_attack_cooldown = add_spin_field(parent, "Attack cooldown", 0.05, 30.0, 0.05)
	definition_value = add_spin_field(parent, "Reward / pickup value", 0.0, 99999.0, 1.0)
	definition_pickup_label = add_line_field(parent, "Pickup message", "")
	definition_apply_button = make_button("Apply Object Type", apply_definition)
	definition_delete_button = make_button("Delete Object Type", delete_definition)
	parent.add_child(definition_apply_button)
	parent.add_child(definition_delete_button)
	var hint := Label.new()
	hint.text = "Enemy fields are used only by enemy types. Pickup value and message are used only by pickups."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color("7f8c95")
	parent.add_child(hint)


func build_placement_inspector(parent: VBoxContainer) -> void:
	parent.add_child(make_heading("MAP INSTANCE"))
	placement_id_edit = add_line_field(parent, "Placement ID", "")
	placement_definition_selector = add_option_field(parent, "Object type", [])
	placement_x = add_spin_field(parent, "Position X", 0.0, 8192.0, 1.0)
	placement_y = add_spin_field(parent, "Position Y", 0.0, 8192.0, 1.0)
	placement_facing_selector = add_option_field(parent, "Facing", ["up", "down", "left", "right"])
	placement_state_key = add_line_field(parent, "Persistent state key", "")
	placement_scope_only = CheckBox.new()
	placement_scope_only.text = "Available only in selected era"
	parent.add_child(placement_scope_only)
	placement_apply_button = make_button("Apply Placement", apply_placement)
	placement_delete_button = make_button("Delete Placement", delete_placement)
	parent.add_child(placement_apply_button)
	parent.add_child(placement_delete_button)
	var hint := Label.new()
	hint.text = "An empty state key automatically becomes map_id:placement_id. Defeated enemies and collected pickups use this key during the session."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color("7f8c95")
	parent.add_child(hint)


func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func make_check(text: String, enabled: bool, callback: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = enabled
	check.toggled.connect(callback)
	return check


func make_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color("d5c17d")
	return label


func make_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color("aeb8c2")
	return label


func add_line_field(parent: VBoxContainer, label_text: String, placeholder: String) -> LineEdit:
	parent.add_child(make_field_label(label_text))
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	parent.add_child(edit)
	return edit


func add_option_field(parent: VBoxContainer, label_text: String, values: Array) -> OptionButton:
	parent.add_child(make_field_label(label_text))
	var option := OptionButton.new()
	for value in values:
		option.add_item(String(value))
	parent.add_child(option)
	return option


func add_spin_field(
	parent: VBoxContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float
) -> SpinBox:
	parent.add_child(make_field_label(label_text))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin


func refresh_campaigns(preferred_id: String = "") -> void:
	var current_id := preferred_id
	if current_id.is_empty() and not active_campaign.is_empty():
		current_id = String(active_campaign.get("id", ""))
	campaigns = Repository.scan_campaigns()
	campaign_selector.clear()
	var selected := 0
	for index in range(campaigns.size()):
		var entry: Dictionary = campaigns[index]
		campaign_selector.add_item(String(entry.get("title", entry.get("id", "Campaign"))))
		campaign_selector.set_item_metadata(index, String(entry.get("path", "")))
		if String(entry.get("id", "")) == current_id:
			selected = index
	if campaigns.is_empty():
		clear_all()
		set_status("No source campaigns found under res://campaigns.", true)
		return
	campaign_selector.select(selected)
	_on_campaign_selected(selected)


func _on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = String(campaign_selector.get_item_metadata(index))
	var result := Repository.read_json(active_campaign_path)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	if not ensure_object_catalog():
		return
	load_catalog()
	populate_maps()
	set_status("Loaded encounter content for '%s'." % active_campaign.get("title", "campaign"), false)


func ensure_object_catalog() -> bool:
	var files_value: Variant = active_campaign.get("object_files", [])
	if typeof(files_value) == TYPE_ARRAY and not Array(files_value).is_empty():
		return true
	var relative_path := "objects/core.json"
	var catalog_path := active_campaign_path.get_base_dir().path_join(relative_path)
	var catalog_result := Repository.save_json(catalog_path, ObjectCatalog.default_catalog())
	if not catalog_result.get("ok", false):
		set_status(format_messages(catalog_result.get("errors", [])), true)
		return false
	active_campaign["object_files"] = [relative_path]
	var campaign_result := Repository.save_json(active_campaign_path, active_campaign)
	if not campaign_result.get("ok", false):
		set_status(format_messages(campaign_result.get("errors", [])), true)
		return false
	rescan_editor_files()
	return true


func load_catalog() -> void:
	var result := ObjectCatalog.load_catalogs(active_campaign_path, active_campaign)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
	catalog_files = result.get("files", [])
	definitions = result.get("definitions", {})
	ordered_definition_ids = result.get("ordered_ids", PackedStringArray())
	active_catalog_path = ObjectCatalog.primary_catalog_path(active_campaign_path, active_campaign)
	active_catalog = {}
	for value in catalog_files:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var file_record: Dictionary = value
		if String(file_record.get("path", "")) == active_catalog_path:
			active_catalog = Dictionary(file_record.get("data", {})).duplicate(true)
			break
	if active_catalog.is_empty():
		active_catalog = ObjectCatalog.default_catalog()
	refresh_definition_list(selected_definition_id)
	refresh_object_selectors()
	refresh_canvas()


func populate_maps() -> void:
	var previous_map_id := String(active_map.get("id", ""))
	map_selector.clear()
	var selected := 0
	for relative_value in active_campaign.get("map_files", []):
		var path := active_campaign_path.get_base_dir().path_join(String(relative_value))
		var result := Repository.read_json(path)
		if not result.get("ok", false):
			continue
		var map_data: Dictionary = result.get("data", {})
		var index := map_selector.item_count
		map_selector.add_item(String(map_data.get("display_name", map_data.get("id", "Map"))))
		map_selector.set_item_metadata(index, path)
		if String(map_data.get("id", "")) == previous_map_id:
			selected = index
	if map_selector.item_count > 0:
		map_selector.select(selected)
		_on_map_selected(selected)
	else:
		active_map = {}
		active_map_path = ""
		canvas.set_map_data({})


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= map_selector.item_count:
		return
	active_map_path = String(map_selector.get_item_metadata(index))
	var result := Repository.read_json(active_map_path)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_map = result.get("data", {})
	if not active_map.has("object_placements"):
		active_map["object_placements"] = []
	populate_eras()
	selected_placement_index = -1
	map_undo_stack.clear()
	map_redo_stack.clear()
	refresh_canvas()
	clear_placement_inspector()
	update_history_buttons()


func populate_eras() -> void:
	var previous := selected_era_id()
	era_selector.clear()
	var selected := 0
	var eras: Array = active_map.get("eras", [])
	for index in range(eras.size()):
		var era: Dictionary = eras[index]
		era_selector.add_item(String(era.get("display_name", era.get("id", "Era"))))
		era_selector.set_item_metadata(index, String(era.get("id", "")))
		if String(era.get("id", "")) == previous:
			selected = index
	if era_selector.item_count > 0:
		era_selector.select(selected)
		canvas.set_era(String(era_selector.get_item_metadata(selected)))


func _on_era_selected(index: int) -> void:
	if index < 0 or index >= era_selector.item_count:
		return
	canvas.set_era(String(era_selector.get_item_metadata(index)))
	if selected_placement_index >= 0:
		populate_placement_inspector()


func selected_era_id() -> String:
	if era_selector == null or era_selector.item_count == 0:
		return ""
	return String(era_selector.get_item_metadata(era_selector.selected))


func refresh_definition_list(preferred_id: String = "") -> void:
	definition_list.clear()
	var selected := -1
	for object_id in ordered_definition_ids:
		var definition_data := ObjectCatalog.definition(definitions, object_id)
		var label := "%s  [%s]" % [
			definition_data.get("display_name", object_id),
			String(definition_data.get("kind", "prop")).to_upper()
		]
		var index := definition_list.add_item(label)
		definition_list.set_item_metadata(index, object_id)
		if object_id == preferred_id:
			selected = index
	if selected < 0 and definition_list.item_count > 0:
		selected = 0
	if selected >= 0:
		definition_list.select(selected)
		_on_definition_selected(selected)
	else:
		selected_definition_id = ""
		set_definition_inspector_enabled(false)


func _on_definition_selected(index: int) -> void:
	if index < 0 or index >= definition_list.item_count:
		return
	selected_definition_id = String(definition_list.get_item_metadata(index))
	populate_definition_inspector()


func populate_definition_inspector() -> void:
	var definition_data := ObjectCatalog.definition(definitions, selected_definition_id)
	if definition_data.is_empty():
		set_definition_inspector_enabled(false)
		return
	set_definition_inspector_enabled(true)
	definition_id_edit.text = selected_definition_id
	definition_name_edit.text = String(definition_data.get("display_name", ""))
	select_option_text(definition_kind_selector, String(definition_data.get("kind", "prop")))
	var appearance: Dictionary = definition_data.get("appearance", {})
	select_option_text(definition_shape_selector, String(appearance.get("shape", "marker")))
	definition_color_edit.text = String(appearance.get("color", "66717a"))
	definition_accent_edit.text = String(appearance.get("accent", "d4c68f"))
	definition_solid.button_pressed = bool(definition_data.get("solid", false))
	definition_collision_radius.value = float(definition_data.get("collision_radius", 0.0))
	definition_interaction_radius.value = float(definition_data.get("interaction_radius", 0.0))
	var dialogue: Variant = definition_data.get("dialogue", "")
	definition_dialogue.text = String(dialogue.get("default", "")) if typeof(dialogue) == TYPE_DICTIONARY else String(dialogue)
	definition_max_health.value = float(definition_data.get("max_health", 12))
	definition_move_speed.value = float(definition_data.get("move_speed", 58))
	definition_awareness_radius.value = float(definition_data.get("awareness_radius", 132))
	definition_attack_radius.value = float(definition_data.get("attack_radius", 20))
	definition_attack_damage.value = float(definition_data.get("attack_damage", 4))
	definition_attack_cooldown.value = float(definition_data.get("attack_cooldown", 1.05))
	var kind := String(definition_data.get("kind", "prop"))
	definition_value.value = float(definition_data.get("pickup_value", definition_data.get("reward", 0)))
	definition_pickup_label.text = String(definition_data.get("pickup_label", ""))
	update_definition_kind_fields(kind)


func _on_definition_kind_changed(index: int) -> void:
	if index >= 0 and index < definition_kind_selector.item_count:
		update_definition_kind_fields(definition_kind_selector.get_item_text(index))


func update_definition_kind_fields(kind: String) -> void:
	var enemy := kind == "enemy"
	var pickup := kind == "pickup"
	definition_max_health.editable = enemy
	definition_move_speed.editable = enemy
	definition_awareness_radius.editable = enemy
	definition_attack_radius.editable = enemy
	definition_attack_damage.editable = enemy
	definition_attack_cooldown.editable = enemy
	definition_value.editable = enemy or pickup
	definition_pickup_label.editable = pickup
	definition_dialogue.editable = kind in ["prop", "npc"]


func set_definition_inspector_enabled(enabled: bool) -> void:
	for control in [
		definition_name_edit, definition_kind_selector, definition_shape_selector,
		definition_color_edit, definition_accent_edit, definition_solid,
		definition_collision_radius, definition_interaction_radius, definition_dialogue,
		definition_max_health, definition_move_speed, definition_awareness_radius,
		definition_attack_radius, definition_attack_damage, definition_attack_cooldown,
		definition_value, definition_pickup_label, definition_apply_button,
		definition_delete_button
	]:
		if control is LineEdit or control is TextEdit or control is SpinBox:
			control.editable = enabled
		elif control is OptionButton or control is CheckBox or control is Button:
			control.disabled = not enabled
	definition_id_edit.editable = false
	if enabled:
		update_definition_kind_fields(definition_kind_selector.get_item_text(definition_kind_selector.selected))


func add_definition() -> void:
	var object_id := Repository.normalise_id(new_definition_id.text)
	if object_id.is_empty():
		set_status("Enter a valid object type ID.", true)
		return
	if definitions.has(object_id):
		set_status("Object type '%s' already exists." % object_id, true)
		return
	var objects: Array = active_catalog.get("objects", [])
	objects.append(ObjectCatalog.default_definition(object_id, object_id.replace("_", " ").capitalize()))
	active_catalog["objects"] = objects
	new_definition_id.clear()
	rebuild_definitions_from_files()
	selected_definition_id = object_id
	refresh_definition_list(object_id)
	if save_catalog():
		set_status("Created object type '%s'." % object_id, false)


func apply_definition() -> void:
	if selected_definition_id.is_empty():
		return
	var objects: Array = active_catalog.get("objects", [])
	var found := false
	for index in range(objects.size()):
		if typeof(objects[index]) != TYPE_DICTIONARY:
			continue
		var definition_data: Dictionary = objects[index]
		if String(definition_data.get("id", "")) != selected_definition_id:
			continue
		definition_data["display_name"] = definition_name_edit.text.strip_edges()
		definition_data["kind"] = definition_kind_selector.get_item_text(definition_kind_selector.selected)
		definition_data["appearance"] = {
			"shape": definition_shape_selector.get_item_text(definition_shape_selector.selected),
			"color": definition_color_edit.text.strip_edges(),
			"accent": definition_accent_edit.text.strip_edges()
		}
		definition_data["solid"] = definition_solid.button_pressed
		definition_data["collision_radius"] = definition_collision_radius.value
		definition_data["interaction_radius"] = definition_interaction_radius.value
		for field in [
			"max_health", "move_speed", "awareness_radius", "attack_radius",
			"attack_damage", "attack_cooldown", "reward", "pickup_value",
			"pickup_label", "dialogue"
		]:
			definition_data.erase(field)
		var kind := String(definition_data.get("kind", "prop"))
		if kind in ["prop", "npc"]:
			definition_data["dialogue"] = definition_dialogue.text
		elif kind == "enemy":
			definition_data["max_health"] = int(definition_max_health.value)
			definition_data["move_speed"] = definition_move_speed.value
			definition_data["awareness_radius"] = definition_awareness_radius.value
			definition_data["attack_radius"] = definition_attack_radius.value
			definition_data["attack_damage"] = int(definition_attack_damage.value)
			definition_data["attack_cooldown"] = definition_attack_cooldown.value
			definition_data["reward"] = int(definition_value.value)
		elif kind == "pickup":
			definition_data["pickup_value"] = maxi(1, int(definition_value.value))
			definition_data["pickup_label"] = definition_pickup_label.text.strip_edges()
		objects[index] = definition_data
		found = true
		break
	if not found:
		set_status("The selected definition is not in the editable primary catalog.", true)
		return
	active_catalog["objects"] = objects
	rebuild_definitions_from_files()
	if save_catalog():
		refresh_definition_list(selected_definition_id)
		set_status("Updated object type '%s'." % selected_definition_id, false)


func delete_definition() -> void:
	if selected_definition_id.is_empty():
		return
	var usages := find_definition_usages(selected_definition_id)
	if not usages.is_empty():
		set_status(
			"Cannot delete '%s'; it is used by %s." % [selected_definition_id, ", ".join(usages)],
			true
		)
		return
	var objects: Array = active_catalog.get("objects", [])
	var removed := false
	for index in range(objects.size() - 1, -1, -1):
		if typeof(objects[index]) == TYPE_DICTIONARY and String(Dictionary(objects[index]).get("id", "")) == selected_definition_id:
			objects.remove_at(index)
			removed = true
			break
	if not removed:
		set_status("Definitions from secondary catalog files are read-only in this editor slice.", true)
		return
	var deleted_id := selected_definition_id
	active_catalog["objects"] = objects
	selected_definition_id = ""
	rebuild_definitions_from_files()
	if save_catalog():
		refresh_definition_list()
		set_status("Deleted object type '%s'." % deleted_id, false)


func find_definition_usages(object_id: String) -> PackedStringArray:
	var usages := PackedStringArray()
	for relative_value in active_campaign.get("map_files", []):
		var path := active_campaign_path.get_base_dir().path_join(String(relative_value))
		var map_data: Dictionary = active_map if path == active_map_path else {}
		if map_data.is_empty():
			var result := Repository.read_json(path)
			if result.get("ok", false):
				map_data = result.get("data", {})
		for placement_value in map_data.get("object_placements", []):
			if typeof(placement_value) == TYPE_DICTIONARY:
				var placement: Dictionary = placement_value
				if String(placement.get("object_id", "")) == object_id:
					usages.append("%s/%s" % [map_data.get("id", "map"), placement.get("id", "placement")])
	return usages


func rebuild_definitions_from_files() -> void:
	definitions = {}
	ordered_definition_ids = PackedStringArray()
	for file_value in catalog_files:
		if typeof(file_value) != TYPE_DICTIONARY:
			continue
		var file_record: Dictionary = file_value
		var data: Dictionary = active_catalog if String(file_record.get("path", "")) == active_catalog_path else file_record.get("data", {})
		for definition_value in data.get("objects", []):
			if typeof(definition_value) != TYPE_DICTIONARY:
				continue
			var definition_data: Dictionary = definition_value
			var object_id := String(definition_data.get("id", ""))
			if object_id.is_empty() or definitions.has(object_id):
				continue
			definitions[object_id] = definition_data
			ordered_definition_ids.append(object_id)
	if catalog_files.is_empty():
		for definition_value in active_catalog.get("objects", []):
			if typeof(definition_value) == TYPE_DICTIONARY:
				var definition_data: Dictionary = definition_value
				var object_id := String(definition_data.get("id", ""))
				definitions[object_id] = definition_data
				ordered_definition_ids.append(object_id)
	refresh_object_selectors()
	refresh_canvas()


func refresh_object_selectors() -> void:
	var placement_choice := selected_option_metadata(placement_object_selector)
	var inspector_choice := selected_option_metadata(placement_definition_selector)
	for selector_value in [placement_object_selector, placement_definition_selector]:
		var selector: OptionButton = selector_value
		selector.clear()
		for object_id in ordered_definition_ids:
			var definition_data := ObjectCatalog.definition(definitions, object_id)
			var index: int = selector.item_count
			selector.add_item(str(definition_data.get("display_name", object_id)))
			selector.set_item_metadata(index, object_id)
	select_option_metadata(placement_object_selector, placement_choice)
	select_option_metadata(placement_definition_selector, inspector_choice)


func save_catalog() -> bool:
	var report := validate_editor_content()
	if not report.get("ok", false):
		set_status(format_report(report), true)
		return false
	var result := Repository.save_json(active_catalog_path, active_catalog)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return false
	rescan_editor_files()
	if not report.get("warnings", []).is_empty():
		set_status(format_report(report), false)
	return true


func _on_tool_selected(index: int) -> void:
	if index >= 0 and index < tool_selector.item_count:
		canvas.set_tool(String(tool_selector.get_item_metadata(index)))


func _on_overlay_changed(_enabled: bool) -> void:
	canvas.set_overlay_visibility(
		show_collision.button_pressed,
		show_navigation.button_pressed,
		show_world_markers.button_pressed
	)


func reset_canvas_view() -> void:
	canvas.reset_view()


func _on_canvas_action(world_position: Vector2, _cell: Vector2i, tool: String, _erase: bool) -> void:
	match tool:
		"place_object":
			add_placement(world_position)
		_:
			select_placement_near(world_position)


func add_placement(world_position: Vector2) -> void:
	var object_id := selected_option_metadata(placement_object_selector)
	if object_id.is_empty():
		set_status("Select an object type before placing it.", true)
		return
	push_map_undo()
	var placements: Array = active_map.get("object_placements", [])
	var placement_id := unique_placement_id(object_id, placements)
	var placement := ObjectCatalog.default_placement(placement_id, object_id, world_position)
	placement["available_eras"] = MapModel.scope_for_era(selected_era_id(), placement_era_only.button_pressed)
	placements.append(placement)
	active_map["object_placements"] = placements
	selected_placement_index = placements.size() - 1
	map_redo_stack.clear()
	refresh_canvas()
	populate_placement_inspector()
	update_history_buttons()
	save_map()


func select_placement_near(world_position: Vector2) -> void:
	var placements: Array = active_map.get("object_placements", [])
	var best_index := -1
	var best_distance := 28.0
	for index in range(placements.size()):
		if typeof(placements[index]) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = placements[index]
		if not ObjectCatalog.placement_is_available(placement, selected_era_id()):
			continue
		var position := Repository.data_to_vector(placement.get("position"), Vector2.ZERO)
		var distance := position.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	selected_placement_index = best_index
	if best_index < 0:
		clear_placement_inspector()
	else:
		populate_placement_inspector()
	refresh_canvas()


func populate_placement_inspector() -> void:
	var placements: Array = active_map.get("object_placements", [])
	if selected_placement_index < 0 or selected_placement_index >= placements.size():
		clear_placement_inspector()
		return
	var placement: Dictionary = placements[selected_placement_index]
	set_placement_inspector_enabled(true)
	placement_id_edit.text = String(placement.get("id", ""))
	select_option_metadata(placement_definition_selector, String(placement.get("object_id", "")))
	var position := Repository.data_to_vector(placement.get("position"), Vector2.ZERO)
	placement_x.value = position.x
	placement_y.value = position.y
	select_option_text(placement_facing_selector, String(placement.get("facing", "down")))
	placement_state_key.text = String(placement.get("state_key", ""))
	var available: Array = placement.get("available_eras", [])
	placement_scope_only.button_pressed = available.size() == 1 and available.has(selected_era_id())
	canvas.set_selected_placement(String(placement.get("id", "")))


func clear_placement_inspector() -> void:
	selected_placement_index = -1
	placement_id_edit.text = ""
	placement_state_key.text = ""
	set_placement_inspector_enabled(false)
	if canvas != null:
		canvas.set_selected_placement("")


func set_placement_inspector_enabled(enabled: bool) -> void:
	placement_id_edit.editable = enabled
	placement_definition_selector.disabled = not enabled
	placement_x.editable = enabled
	placement_y.editable = enabled
	placement_facing_selector.disabled = not enabled
	placement_state_key.editable = enabled
	placement_scope_only.disabled = not enabled
	placement_apply_button.disabled = not enabled
	placement_delete_button.disabled = not enabled


func apply_placement() -> void:
	var placements: Array = active_map.get("object_placements", [])
	if selected_placement_index < 0 or selected_placement_index >= placements.size():
		return
	var requested_id := Repository.normalise_id(placement_id_edit.text)
	if requested_id.is_empty():
		set_status("Placement ID cannot be empty.", true)
		return
	for index in range(placements.size()):
		if index != selected_placement_index and typeof(placements[index]) == TYPE_DICTIONARY and String(Dictionary(placements[index]).get("id", "")) == requested_id:
			set_status("Placement ID '%s' is already used on this map." % requested_id, true)
			return
	var object_id := selected_option_metadata(placement_definition_selector)
	if object_id.is_empty() or not definitions.has(object_id):
		set_status("Placement must reference a valid object type.", true)
		return
	push_map_undo()
	var placement: Dictionary = placements[selected_placement_index]
	placement["id"] = requested_id
	placement["object_id"] = object_id
	placement["position"] = Repository.vector_to_data(Vector2(placement_x.value, placement_y.value))
	placement["facing"] = placement_facing_selector.get_item_text(placement_facing_selector.selected)
	placement["state_key"] = placement_state_key.text.strip_edges()
	placement["available_eras"] = MapModel.scope_for_era(selected_era_id(), placement_scope_only.button_pressed)
	placements[selected_placement_index] = placement
	active_map["object_placements"] = placements
	map_redo_stack.clear()
	refresh_canvas()
	update_history_buttons()
	if save_map():
		set_status("Updated placement '%s'." % requested_id, false)


func delete_placement() -> void:
	var placements: Array = active_map.get("object_placements", [])
	if selected_placement_index < 0 or selected_placement_index >= placements.size():
		return
	var deleted_id := String(Dictionary(placements[selected_placement_index]).get("id", "placement"))
	push_map_undo()
	placements.remove_at(selected_placement_index)
	active_map["object_placements"] = placements
	map_redo_stack.clear()
	clear_placement_inspector()
	refresh_canvas()
	update_history_buttons()
	if save_map():
		set_status("Deleted placement '%s'." % deleted_id, false)


func unique_placement_id(object_id: String, placements: Array) -> String:
	var used: Dictionary = {}
	for value in placements:
		if typeof(value) == TYPE_DICTIONARY:
			used[String(Dictionary(value).get("id", ""))] = true
	var index := 1
	var candidate := "%s_%03d" % [object_id, index]
	while used.has(candidate):
		index += 1
		candidate = "%s_%03d" % [object_id, index]
	return candidate


func push_map_undo() -> void:
	if active_map.is_empty():
		return
	map_undo_stack.append(active_map.duplicate(true))
	if map_undo_stack.size() > HISTORY_LIMIT:
		map_undo_stack.pop_front()


func undo_map_change() -> void:
	if map_undo_stack.is_empty():
		return
	map_redo_stack.append(active_map.duplicate(true))
	active_map = Dictionary(map_undo_stack.pop_back()).duplicate(true)
	clear_placement_inspector()
	refresh_canvas()
	update_history_buttons()
	save_map()


func redo_map_change() -> void:
	if map_redo_stack.is_empty():
		return
	map_undo_stack.append(active_map.duplicate(true))
	active_map = Dictionary(map_redo_stack.pop_back()).duplicate(true)
	clear_placement_inspector()
	refresh_canvas()
	update_history_buttons()
	save_map()


func update_history_buttons() -> void:
	if undo_button != null:
		undo_button.disabled = map_undo_stack.is_empty()
	if redo_button != null:
		redo_button.disabled = map_redo_stack.is_empty()


func save_map() -> bool:
	if active_map_path.is_empty() or active_map.is_empty():
		set_status("No map is loaded.", true)
		return false
	var report := Validator.validate_map(active_map, active_map_path, definitions)
	if not report.get("ok", false):
		set_status(format_report(report), true)
		return false
	var result := Repository.save_json(active_map_path, active_map)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return false
	rescan_editor_files()
	if not report.get("warnings", []).is_empty():
		set_status(format_report(report), false)
	return true


func validate_editor_content() -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var sources: Dictionary = {}
	Validator.validate_catalog_file(
		active_catalog,
		active_catalog_path,
		definitions,
		sources,
		errors,
		warnings
	)
	for relative_value in active_campaign.get("map_files", []):
		var path := active_campaign_path.get_base_dir().path_join(String(relative_value))
		var map_data: Dictionary = active_map if path == active_map_path else {}
		if map_data.is_empty():
			var result := Repository.read_json(path)
			if not result.get("ok", false):
				ObjectCatalog.append_messages(errors, result.get("errors", []))
				continue
			map_data = result.get("data", {})
		var report := Validator.validate_object_placements(map_data, path, definitions)
		ObjectCatalog.append_messages(errors, report.get("errors", []))
		ObjectCatalog.append_messages(warnings, report.get("warnings", []))
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


func validate_all_campaigns() -> void:
	var report := Validator.validate_all()
	set_status(format_report(report), not report.get("ok", false))


func refresh_canvas() -> void:
	if canvas == null:
		return
	canvas.set_map_data(active_map)
	canvas.set_encounter_data(definitions, selected_placement_id())
	canvas.set_overlay_visibility(
		show_collision.button_pressed,
		show_navigation.button_pressed,
		show_world_markers.button_pressed
	)


func selected_placement_id() -> String:
	var placements: Array = active_map.get("object_placements", [])
	if selected_placement_index < 0 or selected_placement_index >= placements.size():
		return ""
	return String(Dictionary(placements[selected_placement_index]).get("id", ""))


func selected_option_metadata(option: OptionButton) -> String:
	if option == null or option.item_count == 0 or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func select_option_metadata(option: OptionButton, requested: String) -> void:
	if option.item_count == 0:
		return
	var selected := 0
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == requested:
			selected = index
			break
	option.select(selected)


func select_option_text(option: OptionButton, requested: String) -> void:
	if option.item_count == 0:
		return
	var selected := 0
	for index in range(option.item_count):
		if option.get_item_text(index) == requested:
			selected = index
			break
	option.select(selected)


func clear_all() -> void:
	active_campaign = {}
	active_campaign_path = ""
	active_map = {}
	active_map_path = ""
	active_catalog = {}
	active_catalog_path = ""
	definitions = {}
	ordered_definition_ids = PackedStringArray()
	definition_list.clear()
	map_selector.clear()
	era_selector.clear()
	if canvas != null:
		canvas.set_map_data({})
	set_definition_inspector_enabled(false)
	clear_placement_inspector()


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	if report.has("campaign_count"):
		lines.append(
			"%d campaign(s), %d map(s), %d object type(s), %d placement(s), %d warning(s), %d error(s)." % [
				report.get("campaign_count", 0), report.get("map_count", 0),
				report.get("definition_count", 0), report.get("placement_count", 0),
				report.get("warnings", []).size(), report.get("errors", []).size()
			]
		)
	else:
		lines.append("%d warning(s), %d error(s)." % [report.get("warnings", []).size(), report.get("errors", []).size()])
	for warning in report.get("warnings", []):
		lines.append("WARNING: %s" % warning)
	for error in report.get("errors", []):
		lines.append("ERROR: %s" % error)
	return "\n".join(lines)


func format_messages(messages: Array) -> String:
	var lines := PackedStringArray()
	for message in messages:
		lines.append(String(message))
	return "\n".join(lines)


func set_status(message: String, is_error: bool) -> void:
	status_label.text = message
	status_label.modulate = Color("ff8f8f") if is_error else Color("a9d5b0")


func rescan_editor_files() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func open_campaign_folder() -> void:
	var absolute := ProjectSettings.globalize_path(Repository.DEFAULT_ROOT)
	DirAccess.make_dir_recursive_absolute(absolute)
	OS.shell_open(absolute)
