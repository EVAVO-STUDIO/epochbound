@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/campaign_validator.gd")
const MapModel = preload("res://src/content/map_model.gd")
const MapCanvas = preload("res://addons/epochbound_campaign_studio/map_canvas.gd")
const HISTORY_LIMIT := 50

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_map: Dictionary = {}
var active_campaign_path := ""
var active_map_path := ""
var selected_kind := ""
var selected_index := -1
var undo_stack: Array = []
var redo_stack: Array = []
var pending_snapshot: Dictionary = {}
var dirty := false

var campaign_selector: OptionButton
var campaign_id_edit: LineEdit
var map_list: ItemList
var map_id_edit: LineEdit
var era_selector: OptionButton
var tool_selector: OptionButton
var terrain_selector: OptionButton
var paint_era_only: CheckBox
var collision_overlay: CheckBox
var navigation_overlay: CheckBox
var marker_overlay: CheckBox
var map_canvas
var save_button: Button
var undo_button: Button
var redo_button: Button
var inspector_type: Label
var marker_id_edit: LineEdit
var position_row: Control
var position_x: SpinBox
var position_y: SpinBox
var secondary_row: Control
var secondary_x: SpinBox
var secondary_y: SpinBox
var radius_row: Control
var marker_radius: SpinBox
var target_map_row: Control
var target_map_selector: OptionButton
var target_entry_row: Control
var target_entry_edit: LineEdit
var target_era_row: Control
var target_era_edit: LineEdit
var trigger_row: Control
var trigger_selector: OptionButton
var marker_era_only: CheckBox
var dialogue_group: Control
var marker_dialogue: TextEdit
var apply_marker_button: Button
var delete_marker_button: Button
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
	title.text = "Epochbound Campaign Studio"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	campaign_id_edit = LineEdit.new()
	campaign_id_edit.placeholder_text = "new_campaign_id"
	campaign_id_edit.custom_minimum_size.x = 165
	header.add_child(campaign_id_edit)
	header.add_child(make_button("New Campaign", create_campaign))
	header.add_child(make_button("Refresh", refresh_campaigns))
	header.add_child(make_button("Validate All", validate_all_campaigns))
	header.add_child(make_button("Open Folder", open_campaign_folder))
	undo_button = make_button("Undo", undo_change)
	redo_button = make_button("Redo", redo_change)
	save_button = make_button("Save Map", save_active_map)
	header.add_child(undo_button)
	header.add_child(redo_button)
	header.add_child(save_button)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 210
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)
	left.add_child(make_heading("CAMPAIGNS"))
	campaign_selector = OptionButton.new()
	campaign_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_selector.item_selected.connect(_on_campaign_selected)
	left.add_child(campaign_selector)
	left.add_child(make_heading("MAPS"))
	map_list = ItemList.new()
	map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_list.custom_minimum_size.y = 250
	map_list.item_selected.connect(_on_map_selected)
	left.add_child(map_list)
	map_id_edit = LineEdit.new()
	map_id_edit.placeholder_text = "new_map_id"
	left.add_child(map_id_edit)
	left.add_child(make_button("Add Map", create_map))
	var left_hint := Label.new()
	left_hint.text = "Maps use stable IDs. Display names and final art can change without breaking links."
	left_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_hint.modulate = Color("7f8c95")
	left.add_child(left_hint)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 3.0
	center.add_theme_constant_override("separation", 5)
	split.add_child(center)
	var toolbar := HBoxContainer.new()
	center.add_child(toolbar)
	toolbar.add_child(make_heading("ERA"))
	era_selector = OptionButton.new()
	era_selector.custom_minimum_size.x = 135
	era_selector.item_selected.connect(_on_era_selected)
	toolbar.add_child(era_selector)
	toolbar.add_child(make_heading("TOOL"))
	tool_selector = OptionButton.new()
	tool_selector.custom_minimum_size.x = 160
	for tool in [
		{"label": "Select", "id": "select"},
		{"label": "Paint Terrain", "id": "terrain_paint"},
		{"label": "Paint Collision", "id": "collision_paint"},
		{"label": "Paint Navigation", "id": "navigation_paint"},
		{"label": "Place Player", "id": "player_spawn"},
		{"label": "Place Companion", "id": "companion_spawn"},
		{"label": "Add Interaction", "id": "interaction"},
		{"label": "Add Connection", "id": "connection"},
		{"label": "Add Entry Point", "id": "entry"},
		{"label": "Add Recovery Anchor", "id": "recovery"}
	]:
		var index := tool_selector.item_count
		tool_selector.add_item(String(tool.get("label", "")))
		tool_selector.set_item_metadata(index, String(tool.get("id", "select")))
	tool_selector.item_selected.connect(_on_tool_selected)
	toolbar.add_child(tool_selector)
	toolbar.add_child(make_heading("BRUSH"))
	terrain_selector = OptionButton.new()
	terrain_selector.custom_minimum_size.x = 110
	toolbar.add_child(terrain_selector)
	paint_era_only = CheckBox.new()
	paint_era_only.text = "Selected era only"
	paint_era_only.tooltip_text = "When enabled, painted cells or markers exist only in the selected era."
	toolbar.add_child(paint_era_only)

	var overlay_bar := HBoxContainer.new()
	center.add_child(overlay_bar)
	overlay_bar.add_child(make_heading("OVERLAYS"))
	collision_overlay = make_check("Collision", true, _on_overlay_changed)
	navigation_overlay = make_check("Navigation", true, _on_overlay_changed)
	marker_overlay = make_check("Markers", true, _on_overlay_changed)
	overlay_bar.add_child(collision_overlay)
	overlay_bar.add_child(navigation_overlay)
	overlay_bar.add_child(marker_overlay)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_bar.add_child(spacer)
	overlay_bar.add_child(make_button("Reset View", reset_canvas_view))

	map_canvas = MapCanvas.new()
	map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_canvas.canvas_action.connect(_on_canvas_action)
	map_canvas.stroke_started.connect(_on_stroke_started)
	map_canvas.stroke_finished.connect(_on_stroke_finished)
	center.add_child(map_canvas)

	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.custom_minimum_size.x = 320
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(inspector_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	inspector_scroll.add_child(right)
	right.add_child(make_heading("SELECTION INSPECTOR"))
	inspector_type = Label.new()
	inspector_type.text = "Nothing selected"
	inspector_type.add_theme_font_size_override("font_size", 16)
	inspector_type.modulate = Color("e8d79f")
	right.add_child(inspector_type)
	right.add_child(make_field_label("Stable identifier"))
	marker_id_edit = LineEdit.new()
	right.add_child(marker_id_edit)
	var position_controls := make_coordinate_row("Position")
	position_row = position_controls.get("row")
	position_x = position_controls.get("x")
	position_y = position_controls.get("y")
	right.add_child(position_row)
	var secondary_controls := make_coordinate_row("Companion position")
	secondary_row = secondary_controls.get("row")
	secondary_x = secondary_controls.get("x")
	secondary_y = secondary_controls.get("y")
	right.add_child(secondary_row)
	radius_row = HBoxContainer.new()
	var radius_label := Label.new()
	radius_label.text = "Radius"
	radius_label.custom_minimum_size.x = 118
	radius_row.add_child(radius_label)
	marker_radius = make_spin_box(4.0, 512.0, 1.0)
	radius_row.add_child(marker_radius)
	right.add_child(radius_row)
	target_map_row = HBoxContainer.new()
	var target_map_label := Label.new()
	target_map_label.text = "Target map"
	target_map_label.custom_minimum_size.x = 118
	target_map_row.add_child(target_map_label)
	target_map_selector = OptionButton.new()
	target_map_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_map_row.add_child(target_map_selector)
	right.add_child(target_map_row)
	target_entry_row = make_line_edit_row("Target entry", "entry_id")
	target_entry_edit = target_entry_row.get_child(1)
	right.add_child(target_entry_row)
	target_era_row = make_line_edit_row("Target era", "same or era_id")
	target_era_edit = target_era_row.get_child(1)
	right.add_child(target_era_row)
	trigger_row = HBoxContainer.new()
	var trigger_label := Label.new()
	trigger_label.text = "Trigger"
	trigger_label.custom_minimum_size.x = 118
	trigger_row.add_child(trigger_label)
	trigger_selector = OptionButton.new()
	trigger_selector.add_item("interact")
	trigger_selector.add_item("touch")
	trigger_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trigger_row.add_child(trigger_selector)
	right.add_child(trigger_row)
	marker_era_only = CheckBox.new()
	marker_era_only.text = "Available only in selected era"
	right.add_child(marker_era_only)
	dialogue_group = VBoxContainer.new()
	dialogue_group.add_child(make_field_label("Dialogue for selected era"))
	marker_dialogue = TextEdit.new()
	marker_dialogue.custom_minimum_size.y = 150
	marker_dialogue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_group.add_child(marker_dialogue)
	right.add_child(dialogue_group)
	apply_marker_button = make_button("Apply Selection", apply_selected_marker)
	delete_marker_button = make_button("Delete Selection", delete_selected_marker)
	right.add_child(apply_marker_button)
	right.add_child(delete_marker_button)
	var inspector_hint := Label.new()
	inspector_hint.text = "Connections must target a declared map and entry point. Validation blocks broken links before play."
	inspector_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector_hint.modulate = Color("7f8c95")
	right.add_child(inspector_hint)

	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = false
	status_label.fit_content = true
	status_label.custom_minimum_size.y = 64
	status_label.text = "Campaign Studio ready."
	status_label.modulate = Color("9aa8b5")
	root.add_child(status_label)
	clear_selection()
	update_history_buttons()


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


func make_spin_box(minimum: float, maximum: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func make_coordinate_row(label_text: String) -> Dictionary:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 118
	row.add_child(label)
	var x_spin := make_spin_box(0.0, 8192.0, 1.0)
	var y_spin := make_spin_box(0.0, 8192.0, 1.0)
	x_spin.prefix = "X "
	y_spin.prefix = "Y "
	row.add_child(x_spin)
	row.add_child(y_spin)
	return {"row": row, "x": x_spin, "y": y_spin}


func make_line_edit_row(label_text: String, placeholder: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 118
	row.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return row


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
		clear_campaign()
		set_status("No campaigns found. Create one to begin.", false)
		return
	campaign_selector.select(selected)
	_on_campaign_selected(selected)


func clear_campaign() -> void:
	active_campaign = {}
	active_map = {}
	active_campaign_path = ""
	active_map_path = ""
	map_list.clear()
	era_selector.clear()
	terrain_selector.clear()
	map_canvas.set_map_data({})
	clear_selection()
	clear_history()


func _on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = String(campaign_selector.get_item_metadata(index))
	var result := Repository.read_json(active_campaign_path)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	map_list.clear()
	for relative_path in active_campaign.get("map_files", []):
		var display := String(relative_path).get_file().get_basename().replace("_", " ").capitalize()
		var item := map_list.add_item(display)
		map_list.set_item_metadata(item, String(relative_path))
	populate_target_maps()
	if map_list.item_count > 0:
		map_list.select(0)
		_on_map_selected(0)
	else:
		active_map = {}
		active_map_path = ""
		map_canvas.set_map_data({})
	set_status("Loaded campaign '%s'." % active_campaign.get("title", active_campaign.get("id", "")), false)


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= map_list.item_count or active_campaign_path.is_empty():
		return
	var relative_path := String(map_list.get_item_metadata(index))
	active_map_path = active_campaign_path.get_base_dir().path_join(relative_path)
	var result := Repository.read_json(active_map_path)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_map = result.get("data", {})
	var upgraded := ensure_world_defaults(active_map)
	map_canvas.set_map_data(active_map)
	populate_eras()
	populate_terrain_palette()
	populate_target_maps()
	clear_selection()
	clear_history()
	set_dirty(upgraded)
	if upgraded:
		set_status("Loaded and upgraded '%s' in memory. Save Map to persist the world-builder fields." % active_map.get("display_name", "map"), false)
	else:
		set_status("Loaded map '%s'." % active_map.get("display_name", active_map.get("id", "")), false)


func ensure_world_defaults(data: Dictionary) -> bool:
	var defaults := Repository.default_map("template", "Template")
	var changed := false
	for key in [
		"terrain_palette", "terrain_cells", "collision_cells", "navigation_cells",
		"recovery_anchors", "entry_points", "connections"
	]:
		if not data.has(key):
			data[key] = defaults.get(key, []).duplicate(true)
			changed = true
	return changed


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
		map_canvas.set_era(String(era_selector.get_item_metadata(selected)))


func populate_terrain_palette() -> void:
	var previous := selected_terrain_id()
	terrain_selector.clear()
	var selected := 0
	var definitions: Array = active_map.get("terrain_palette", [])
	for index in range(definitions.size()):
		var definition: Dictionary = definitions[index]
		terrain_selector.add_item(String(definition.get("display_name", definition.get("id", "Terrain"))))
		terrain_selector.set_item_metadata(index, String(definition.get("id", "")))
		if String(definition.get("id", "")) == previous:
			selected = index
	if terrain_selector.item_count > 0:
		terrain_selector.select(selected)


func populate_target_maps() -> void:
	if target_map_selector == null:
		return
	var previous := selected_target_map_id()
	target_map_selector.clear()
	var selected := 0
	for relative_path in active_campaign.get("map_files", []):
		var path := active_campaign_path.get_base_dir().path_join(String(relative_path))
		var result := Repository.read_json(path)
		if not result.get("ok", false):
			continue
		var map_record: Dictionary = result.get("data", {})
		var index := target_map_selector.item_count
		target_map_selector.add_item(String(map_record.get("display_name", map_record.get("id", "Map"))))
		target_map_selector.set_item_metadata(index, String(map_record.get("id", "")))
		if String(map_record.get("id", "")) == previous:
			selected = index
	if target_map_selector.item_count > 0:
		target_map_selector.select(selected)


func selected_era_id() -> String:
	if era_selector == null or era_selector.item_count == 0:
		return ""
	return String(era_selector.get_item_metadata(era_selector.selected))


func selected_terrain_id() -> String:
	if terrain_selector == null or terrain_selector.item_count == 0:
		return ""
	return String(terrain_selector.get_item_metadata(terrain_selector.selected))


func selected_target_map_id() -> String:
	if target_map_selector == null or target_map_selector.item_count == 0:
		return ""
	return String(target_map_selector.get_item_metadata(target_map_selector.selected))


func _on_era_selected(index: int) -> void:
	if index < 0 or index >= era_selector.item_count:
		return
	map_canvas.set_era(String(era_selector.get_item_metadata(index)))
	if selected_index >= 0:
		populate_selection_inspector()


func _on_tool_selected(index: int) -> void:
	if index < 0 or index >= tool_selector.item_count:
		return
	map_canvas.set_tool(String(tool_selector.get_item_metadata(index)))


func _on_overlay_changed(_enabled: bool) -> void:
	map_canvas.set_overlay_visibility(
		collision_overlay.button_pressed,
		navigation_overlay.button_pressed,
		marker_overlay.button_pressed
	)


func reset_canvas_view() -> void:
	map_canvas.reset_view()


func create_campaign() -> void:
	var requested_id := campaign_id_edit.text
	var result := Repository.create_campaign(requested_id)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	var campaign_id := Repository.normalise_id(requested_id)
	campaign_id_edit.clear()
	rescan_editor_files()
	refresh_campaigns(campaign_id)
	set_status("Created campaign '%s' with a world-builder-ready starter map." % campaign_id, false)


func create_map() -> void:
	if active_campaign_path.is_empty():
		set_status("Select a campaign before creating a map.", true)
		return
	var requested_id := map_id_edit.text
	var result := Repository.create_map(active_campaign_path, requested_id)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	map_id_edit.clear()
	rescan_editor_files()
	var campaign_id := String(active_campaign.get("id", ""))
	refresh_campaigns(campaign_id)
	select_map_by_id(Repository.normalise_id(requested_id))
	set_status("Created map '%s'." % Repository.normalise_id(requested_id), false)


func select_map_by_id(map_id: String) -> void:
	for index in range(map_list.item_count):
		var relative_path := String(map_list.get_item_metadata(index))
		if relative_path.get_file().get_basename() == map_id:
			map_list.select(index)
			_on_map_selected(index)
			return


func _on_stroke_started() -> void:
	begin_change()


func _on_stroke_finished() -> void:
	if commit_change("Paint %s" % current_tool_id().replace("_", " ")):
		save_active_map()


func current_tool_id() -> String:
	if tool_selector.item_count == 0:
		return "select"
	return String(tool_selector.get_item_metadata(tool_selector.selected))


func _on_canvas_action(world_position: Vector2, cell: Vector2i, tool: String, erase: bool) -> void:
	if active_map.is_empty():
		return
	var scope := MapModel.scope_for_era(selected_era_id(), paint_era_only.button_pressed)
	match tool:
		"terrain_paint":
			if erase:
				MapModel.erase_cell(active_map, MapModel.TERRAIN_CELLS, cell, scope)
			else:
				MapModel.set_cell(active_map, MapModel.TERRAIN_CELLS, cell, {"tile": selected_terrain_id()}, scope)
			refresh_canvas_only()
		"collision_paint":
			if erase:
				MapModel.erase_cell(active_map, MapModel.COLLISION_CELLS, cell, scope)
			else:
				MapModel.set_cell(active_map, MapModel.COLLISION_CELLS, cell, {}, scope)
			refresh_canvas_only()
		"navigation_paint":
			if erase:
				MapModel.erase_cell(active_map, MapModel.NAVIGATION_CELLS, cell, scope)
			else:
				MapModel.set_cell(active_map, MapModel.NAVIGATION_CELLS, cell, {}, scope)
			refresh_canvas_only()
		"player_spawn":
			perform_discrete_change("Place player spawn", set_spawn.bind("player", world_position))
		"companion_spawn":
			perform_discrete_change("Place companion spawn", set_spawn.bind("companion", world_position))
		"interaction":
			perform_discrete_change("Add interaction", add_interaction.bind(world_position))
		"connection":
			perform_discrete_change("Add connection", add_connection.bind(world_position))
		"entry":
			perform_discrete_change("Add entry point", add_entry.bind(world_position))
		"recovery":
			perform_discrete_change("Add recovery anchor", add_recovery.bind(world_position))
		_:
			select_nearest_marker(world_position)


func perform_discrete_change(label: String, operation: Callable) -> void:
	begin_change()
	operation.call()
	if commit_change(label):
		save_active_map()


func set_spawn(spawn_id: String, world_position: Vector2) -> void:
	var spawns: Dictionary = active_map.get("spawns", {})
	spawns[spawn_id] = Repository.vector_to_data(world_position)
	active_map["spawns"] = spawns
	refresh_canvas_only()
	set_status("Placed %s spawn at %s." % [spawn_id, world_position], false)


func add_interaction(world_position: Vector2) -> void:
	var interactions: Array = active_map.get("interactions", [])
	var identifier := unique_identifier(interactions, "interaction")
	interactions.append({
		"id": identifier,
		"kind": "marker",
		"position": Repository.vector_to_data(world_position),
		"radius": 48,
		"available_eras": MapModel.scope_for_era(selected_era_id(), paint_era_only.button_pressed),
		"dialogue": {"default": "This interaction still needs authored dialogue."}
	})
	active_map["interactions"] = interactions
	select_marker("interaction", interactions.size() - 1)


func add_connection(world_position: Vector2) -> void:
	var connections: Array = active_map.get("connections", [])
	var identifier := unique_identifier(connections, "connection")
	var entries: Array = active_map.get("entry_points", [])
	var target_entry := "start"
	if not entries.is_empty():
		var first_entry: Dictionary = entries[0]
		target_entry = String(first_entry.get("id", "start"))
	connections.append({
		"id": identifier,
		"position": Repository.vector_to_data(world_position),
		"radius": 28,
		"target_map": String(active_map.get("id", "")),
		"target_entry": target_entry,
		"target_era": "same",
		"trigger": "interact",
		"available_eras": MapModel.scope_for_era(selected_era_id(), paint_era_only.button_pressed)
	})
	active_map["connections"] = connections
	select_marker("connection", connections.size() - 1)


func add_entry(world_position: Vector2) -> void:
	var entries: Array = active_map.get("entry_points", [])
	var identifier := unique_identifier(entries, "entry")
	var companion_position := world_position + Vector2(-MapModel.grid_size(active_map), MapModel.grid_size(active_map))
	var canvas_size := Vector2(MapModel.canvas_size(active_map))
	companion_position.x = clampf(companion_position.x, 0.0, canvas_size.x)
	companion_position.y = clampf(companion_position.y, 0.0, canvas_size.y)
	entries.append({
		"id": identifier,
		"player": Repository.vector_to_data(world_position),
		"companion": Repository.vector_to_data(companion_position),
		"available_eras": MapModel.scope_for_era(selected_era_id(), paint_era_only.button_pressed)
	})
	active_map["entry_points"] = entries
	select_marker("entry", entries.size() - 1)


func add_recovery(world_position: Vector2) -> void:
	var anchors: Array = active_map.get("recovery_anchors", [])
	var identifier := unique_identifier(anchors, "recovery")
	anchors.append({
		"id": identifier,
		"position": Repository.vector_to_data(world_position),
		"available_eras": MapModel.scope_for_era(selected_era_id(), paint_era_only.button_pressed)
	})
	active_map["recovery_anchors"] = anchors
	select_marker("recovery", anchors.size() - 1)


func unique_identifier(records: Array, prefix: String) -> String:
	var used: Dictionary = {}
	for value in records:
		if typeof(value) == TYPE_DICTIONARY:
			used[String(Dictionary(value).get("id", ""))] = true
	var index := 1
	var candidate := "%s_%03d" % [prefix, index]
	while used.has(candidate):
		index += 1
		candidate = "%s_%03d" % [prefix, index]
	return candidate


func select_nearest_marker(world_position: Vector2) -> void:
	var best_kind := ""
	var best_index := -1
	var best_distance := 28.0
	for kind in ["interaction", "connection", "entry", "recovery"]:
		var records := records_for_kind(kind)
		for index in range(records.size()):
			var record: Dictionary = records[index]
			var position := marker_position(kind, record)
			var distance := position.distance_to(world_position)
			if distance < best_distance:
				best_distance = distance
				best_kind = kind
				best_index = index
	select_marker(best_kind, best_index)


func marker_position(kind: String, record: Dictionary) -> Vector2:
	if kind == "entry":
		return Repository.data_to_vector(record.get("player"), Vector2.ZERO)
	return Repository.data_to_vector(record.get("position"), Vector2.ZERO)


func collection_for_kind(kind: String) -> String:
	match kind:
		"interaction": return "interactions"
		"connection": return "connections"
		"entry": return "entry_points"
		"recovery": return "recovery_anchors"
	return ""


func records_for_kind(kind: String) -> Array:
	var collection := collection_for_kind(kind)
	return active_map.get(collection, []) if not collection.is_empty() else []


func select_marker(kind: String, index: int) -> void:
	selected_kind = kind
	selected_index = index
	var records := records_for_kind(kind)
	if kind.is_empty() or index < 0 or index >= records.size():
		clear_selection()
		return
	var record: Dictionary = records[index]
	map_canvas.set_selected_marker(kind, String(record.get("id", "")))
	populate_selection_inspector()


func clear_selection() -> void:
	selected_kind = ""
	selected_index = -1
	if map_canvas != null:
		map_canvas.set_selected_marker("", "")
	if inspector_type == null:
		return
	inspector_type.text = "Nothing selected"
	marker_id_edit.text = ""
	marker_dialogue.text = ""
	set_inspector_enabled(false)
	set_inspector_rows(false, false, false, false, false, false)


func selected_record() -> Dictionary:
	var records := records_for_kind(selected_kind)
	if selected_index < 0 or selected_index >= records.size():
		return {}
	return records[selected_index]


func populate_selection_inspector() -> void:
	var record := selected_record()
	if record.is_empty():
		clear_selection()
		return
	inspector_type.text = selected_kind.replace("_", " ").capitalize()
	marker_id_edit.text = String(record.get("id", ""))
	var position := marker_position(selected_kind, record)
	position_x.value = position.x
	position_y.value = position.y
	var available: Array = record.get("available_eras", [])
	marker_era_only.button_pressed = available.size() == 1 and available.has(selected_era_id())
	set_inspector_enabled(true)
	match selected_kind:
		"interaction":
			set_inspector_rows(true, false, true, false, false, true)
			marker_radius.value = float(record.get("radius", 48.0))
			var dialogue_value: Variant = record.get("dialogue", "")
			if typeof(dialogue_value) == TYPE_DICTIONARY:
				var by_era: Dictionary = dialogue_value
				marker_dialogue.text = String(by_era.get(selected_era_id(), by_era.get("default", "")))
			else:
				marker_dialogue.text = String(dialogue_value)
		"connection":
			set_inspector_rows(true, false, true, true, true, false)
			marker_radius.value = float(record.get("radius", 28.0))
			select_option_by_metadata(target_map_selector, String(record.get("target_map", "")))
			target_entry_edit.text = String(record.get("target_entry", ""))
			target_era_edit.text = String(record.get("target_era", "same"))
			select_option_by_text(trigger_selector, String(record.get("trigger", "interact")))
		"entry":
			set_inspector_rows(true, true, false, false, false, false)
			var companion_position := Repository.data_to_vector(record.get("companion"), position)
			secondary_x.value = companion_position.x
			secondary_y.value = companion_position.y
		"recovery":
			set_inspector_rows(true, false, false, false, false, false)


func set_inspector_rows(
	position_visible: bool,
	secondary_visible: bool,
	radius_visible: bool,
	target_visible: bool,
	trigger_visible: bool,
	dialogue_visible: bool
) -> void:
	position_row.visible = position_visible
	secondary_row.visible = secondary_visible
	radius_row.visible = radius_visible
	target_map_row.visible = target_visible
	target_entry_row.visible = target_visible
	target_era_row.visible = target_visible
	trigger_row.visible = trigger_visible
	dialogue_group.visible = dialogue_visible


func set_inspector_enabled(enabled: bool) -> void:
	marker_id_edit.editable = enabled
	position_x.editable = enabled
	position_y.editable = enabled
	secondary_x.editable = enabled
	secondary_y.editable = enabled
	marker_radius.editable = enabled
	target_map_selector.disabled = not enabled
	target_entry_edit.editable = enabled
	target_era_edit.editable = enabled
	trigger_selector.disabled = not enabled
	marker_era_only.disabled = not enabled
	marker_dialogue.editable = enabled
	apply_marker_button.disabled = not enabled
	delete_marker_button.disabled = not enabled


func apply_selected_marker() -> void:
	var records := records_for_kind(selected_kind)
	if selected_index < 0 or selected_index >= records.size():
		return
	var requested_id := Repository.normalise_id(marker_id_edit.text)
	if requested_id.is_empty():
		set_status("Selection ID cannot be empty.", true)
		return
	for index in range(records.size()):
		if index == selected_index or typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var other: Dictionary = records[index]
		if String(other.get("id", "")) == requested_id:
			set_status("ID '%s' is already used in this collection." % requested_id, true)
			return
	begin_change()
	var record: Dictionary = records[selected_index]
	record["id"] = requested_id
	var position := Vector2(position_x.value, position_y.value)
	if selected_kind == "entry":
		record["player"] = Repository.vector_to_data(position)
		record["companion"] = Repository.vector_to_data(Vector2(secondary_x.value, secondary_y.value))
	else:
		record["position"] = Repository.vector_to_data(position)
	record["available_eras"] = MapModel.scope_for_era(selected_era_id(), marker_era_only.button_pressed)
	if selected_kind in ["interaction", "connection"]:
		record["radius"] = marker_radius.value
	if selected_kind == "interaction":
		var existing: Variant = record.get("dialogue", {})
		var by_era: Dictionary = existing if typeof(existing) == TYPE_DICTIONARY else {"default": String(existing)}
		var key := selected_era_id()
		if key.is_empty():
			key = "default"
		by_era[key] = marker_dialogue.text
		record["dialogue"] = by_era
	elif selected_kind == "connection":
		var target_entry := Repository.normalise_id(target_entry_edit.text)
		if target_entry.is_empty():
			pending_snapshot = {}
			set_status("A connection requires a target entry ID.", true)
			return
		record["target_map"] = selected_target_map_id()
		record["target_entry"] = target_entry
		var target_era := target_era_edit.text.strip_edges().to_lower()
		record["target_era"] = "same" if target_era.is_empty() else target_era
		record["trigger"] = trigger_selector.get_item_text(trigger_selector.selected)
	records[selected_index] = record
	active_map[collection_for_kind(selected_kind)] = records
	map_canvas.set_selected_marker(selected_kind, requested_id)
	if commit_change("Update %s" % selected_kind):
		if save_active_map():
			set_status("Updated '%s'." % requested_id, false)


func delete_selected_marker() -> void:
	var records := records_for_kind(selected_kind)
	if selected_index < 0 or selected_index >= records.size():
		return
	var record: Dictionary = records[selected_index]
	var deleted_id := String(record.get("id", selected_kind))
	begin_change()
	records.remove_at(selected_index)
	active_map[collection_for_kind(selected_kind)] = records
	clear_selection()
	if commit_change("Delete %s" % selected_kind):
		if save_active_map():
			set_status("Deleted '%s'." % deleted_id, false)


func select_option_by_metadata(option: OptionButton, requested: String) -> void:
	for index in range(option.item_count):
		if String(option.get_item_metadata(index)) == requested:
			option.select(index)
			return


func select_option_by_text(option: OptionButton, requested: String) -> void:
	for index in range(option.item_count):
		if option.get_item_text(index) == requested:
			option.select(index)
			return


func begin_change() -> void:
	if pending_snapshot.is_empty() and not active_map.is_empty():
		pending_snapshot = active_map.duplicate(true)


func commit_change(_label: String) -> bool:
	if pending_snapshot.is_empty():
		return false
	if JSON.stringify(pending_snapshot) == JSON.stringify(active_map):
		pending_snapshot = {}
		return false
	undo_stack.append(pending_snapshot)
	if undo_stack.size() > HISTORY_LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()
	pending_snapshot = {}
	set_dirty(true)
	update_history_buttons()
	return true


func undo_change() -> void:
	if undo_stack.is_empty() or active_map.is_empty():
		return
	redo_stack.append(active_map.duplicate(true))
	active_map = undo_stack.pop_back().duplicate(true)
	pending_snapshot = {}
	clear_selection()
	refresh_editor_from_map()
	set_dirty(true)
	update_history_buttons()
	save_active_map()


func redo_change() -> void:
	if redo_stack.is_empty() or active_map.is_empty():
		return
	undo_stack.append(active_map.duplicate(true))
	active_map = redo_stack.pop_back().duplicate(true)
	pending_snapshot = {}
	clear_selection()
	refresh_editor_from_map()
	set_dirty(true)
	update_history_buttons()
	save_active_map()


func clear_history() -> void:
	undo_stack.clear()
	redo_stack.clear()
	pending_snapshot = {}
	update_history_buttons()


func update_history_buttons() -> void:
	if undo_button != null:
		undo_button.disabled = undo_stack.is_empty()
	if redo_button != null:
		redo_button.disabled = redo_stack.is_empty()


func set_dirty(value: bool) -> void:
	dirty = value
	if save_button != null:
		save_button.text = "Save Map *" if dirty else "Save Map"


func refresh_canvas_only() -> void:
	map_canvas.set_map_data(active_map)
	set_dirty(true)


func refresh_editor_from_map() -> void:
	map_canvas.set_map_data(active_map)
	populate_eras()
	populate_terrain_palette()
	populate_target_maps()


func save_active_map() -> bool:
	if active_map_path.is_empty() or active_map.is_empty():
		set_status("No map is loaded.", true)
		return false
	var report := Validator.validate_map(active_map, active_map_path)
	if not report.get("ok", false):
		set_status(format_report(report), true)
		return false
	var result := Repository.save_json(active_map_path, active_map)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return false
	map_canvas.set_map_data(active_map)
	rescan_editor_files()
	set_dirty(false)
	if not report.get("warnings", []).is_empty():
		set_status(format_report(report), false)
	return true


func validate_all_campaigns() -> void:
	var report := Validator.validate_all()
	set_status(format_report(report), not report.get("ok", false))


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	if report.has("campaign_count"):
		lines.append("%d campaign(s), %d map(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 0), report.get("map_count", 0),
			report.get("warnings", []).size(), report.get("errors", []).size()
		])
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
	var absolute_path := ProjectSettings.globalize_path(Repository.DEFAULT_ROOT)
	DirAccess.make_dir_recursive_absolute(absolute_path)
	OS.shell_open(absolute_path)
