@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/campaign_validator.gd")
const MapCanvas = preload("res://addons/epochbound_campaign_studio/map_canvas.gd")

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_map: Dictionary = {}
var active_campaign_path := ""
var active_map_path := ""
var selected_interaction_index := -1

var campaign_selector: OptionButton
var campaign_id_edit: LineEdit
var map_list: ItemList
var map_id_edit: LineEdit
var era_selector: OptionButton
var tool_selector: OptionButton
var map_canvas
var interaction_id_edit: LineEdit
var interaction_kind_selector: OptionButton
var interaction_radius: SpinBox
var interaction_era_only: CheckBox
var interaction_dialogue: TextEdit
var apply_interaction_button: Button
var delete_interaction_button: Button
var status_label: RichTextLabel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_ui()
	refresh_campaigns()

func build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
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
	campaign_id_edit.custom_minimum_size.x = 180
	header.add_child(campaign_id_edit)
	header.add_child(make_button("New Campaign", create_campaign))
	header.add_child(make_button("Refresh", refresh_campaigns))
	header.add_child(make_button("Validate All", validate_all_campaigns))
	header.add_child(make_button("Open Folder", open_campaign_folder))

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 220
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
	map_list.custom_minimum_size.y = 260
	map_list.item_selected.connect(_on_map_selected)
	left.add_child(map_list)
	map_id_edit = LineEdit.new()
	map_id_edit.placeholder_text = "new_map_id"
	left.add_child(map_id_edit)
	left.add_child(make_button("Add Map", create_map))

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 3.0
	center.add_theme_constant_override("separation", 6)
	split.add_child(center)
	var toolbar := HBoxContainer.new()
	center.add_child(toolbar)
	toolbar.add_child(make_heading("ERA"))
	era_selector = OptionButton.new()
	era_selector.custom_minimum_size.x = 150
	era_selector.item_selected.connect(_on_era_selected)
	toolbar.add_child(era_selector)
	toolbar.add_child(make_heading("TOOL"))
	tool_selector = OptionButton.new()
	for tool in [
		{"label": "Select", "id": "select"},
		{"label": "Place Player", "id": "player_spawn"},
		{"label": "Place Companion", "id": "companion_spawn"},
		{"label": "Add Interaction", "id": "interaction"}
	]:
		var tool_index := tool_selector.item_count
		tool_selector.add_item(String(tool.get("label", "")))
		tool_selector.set_item_metadata(tool_index, String(tool.get("id", "select")))
	tool_selector.item_selected.connect(_on_tool_selected)
	toolbar.add_child(tool_selector)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	toolbar.add_child(make_button("Save Map", save_active_map))

	map_canvas = MapCanvas.new()
	map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_canvas.canvas_clicked.connect(_on_canvas_clicked)
	center.add_child(map_canvas)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 280
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	right.add_child(make_heading("INTERACTION INSPECTOR"))
	right.add_child(make_field_label("Identifier"))
	interaction_id_edit = LineEdit.new()
	right.add_child(interaction_id_edit)
	right.add_child(make_field_label("Kind"))
	interaction_kind_selector = OptionButton.new()
	for kind in ["marker", "well", "dial", "gate", "npc", "chest", "switch"]:
		interaction_kind_selector.add_item(kind)
	right.add_child(interaction_kind_selector)
	right.add_child(make_field_label("Interaction radius"))
	interaction_radius = SpinBox.new()
	interaction_radius.min_value = 8.0
	interaction_radius.max_value = 256.0
	interaction_radius.step = 1.0
	interaction_radius.value = 48.0
	right.add_child(interaction_radius)
	interaction_era_only = CheckBox.new()
	interaction_era_only.text = "Available only in selected era"
	right.add_child(interaction_era_only)
	right.add_child(make_field_label("Dialogue for selected era"))
	interaction_dialogue = TextEdit.new()
	interaction_dialogue.custom_minimum_size.y = 150
	interaction_dialogue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(interaction_dialogue)
	apply_interaction_button = make_button("Apply Interaction", apply_interaction)
	delete_interaction_button = make_button("Delete Interaction", delete_interaction)
	right.add_child(apply_interaction_button)
	right.add_child(delete_interaction_button)
	set_inspector_enabled(false)

	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = false
	status_label.fit_content = true
	status_label.custom_minimum_size.y = 72
	status_label.text = "Campaign Studio ready."
	status_label.modulate = Color("9aa8b5")
	root.add_child(status_label)

func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button

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

func refresh_campaigns(preferred_id: String = "") -> void:
	var current_id := preferred_id
	if current_id.is_empty() and not active_campaign.is_empty():
		current_id = String(active_campaign.get("id", ""))
	campaigns = Repository.scan_campaigns()
	campaign_selector.clear()
	var selected_index := 0
	for index in range(campaigns.size()):
		var entry: Dictionary = campaigns[index]
		campaign_selector.add_item(String(entry.get("title", entry.get("id", "Campaign"))))
		campaign_selector.set_item_metadata(index, String(entry.get("path", "")))
		if String(entry.get("id", "")) == current_id:
			selected_index = index
	if campaigns.is_empty():
		clear_campaign()
		set_status("No campaigns found. Create one to begin.", false)
		return
	campaign_selector.select(selected_index)
	_on_campaign_selected(selected_index)

func clear_campaign() -> void:
	active_campaign = {}
	active_map = {}
	active_campaign_path = ""
	active_map_path = ""
	map_list.clear()
	era_selector.clear()
	map_canvas.set_map_data({})
	select_interaction(-1)

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
		var item_index := map_list.add_item(display)
		map_list.set_item_metadata(item_index, String(relative_path))
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
	map_canvas.set_map_data(active_map)
	populate_eras()
	select_interaction(-1)
	set_status("Loaded map '%s'." % active_map.get("display_name", active_map.get("id", "")), false)

func populate_eras() -> void:
	var previous := selected_era_id()
	era_selector.clear()
	var selected_index := 0
	var eras: Array = active_map.get("eras", [])
	for index in range(eras.size()):
		var era: Dictionary = eras[index]
		era_selector.add_item(String(era.get("display_name", era.get("id", "Era"))))
		era_selector.set_item_metadata(index, String(era.get("id", "")))
		if String(era.get("id", "")) == previous:
			selected_index = index
	if era_selector.item_count > 0:
		era_selector.select(selected_index)
		map_canvas.set_era(String(era_selector.get_item_metadata(selected_index)))

func selected_era_id() -> String:
	if era_selector == null or era_selector.item_count == 0:
		return ""
	return String(era_selector.get_item_metadata(era_selector.selected))

func _on_era_selected(index: int) -> void:
	if index < 0 or index >= era_selector.item_count:
		return
	map_canvas.set_era(String(era_selector.get_item_metadata(index)))
	if selected_interaction_index >= 0:
		populate_interaction_inspector(selected_interaction_index)

func _on_tool_selected(index: int) -> void:
	if index < 0 or index >= tool_selector.item_count:
		return
	map_canvas.set_tool(String(tool_selector.get_item_metadata(index)))

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
	set_status("Created campaign '%s' with a starter map." % campaign_id, false)

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

func _on_canvas_clicked(world_position: Vector2, tool: String) -> void:
	if active_map.is_empty():
		return
	match tool:
		"player_spawn":
			set_spawn("player", world_position)
		"companion_spawn":
			set_spawn("companion", world_position)
		"interaction":
			add_interaction(world_position)
		_:
			select_interaction_near(world_position)

func set_spawn(spawn_id: String, world_position: Vector2) -> void:
	var spawns: Dictionary = active_map.get("spawns", {})
	spawns[spawn_id] = Repository.vector_to_data(world_position)
	active_map["spawns"] = spawns
	if save_active_map():
		set_status("Placed %s spawn at %s." % [spawn_id, world_position], false)

func add_interaction(world_position: Vector2) -> void:
	var interactions: Array = active_map.get("interactions", [])
	var index := 1
	var candidate := "interaction_%03d" % index
	var ids: Dictionary = {}
	for value in interactions:
		var interaction: Dictionary = value
		ids[String(interaction.get("id", ""))] = true
	while ids.has(candidate):
		index += 1
		candidate = "interaction_%03d" % index
	interactions.append({
		"id": candidate,
		"kind": "marker",
		"position": Repository.vector_to_data(world_position),
		"radius": 48,
		"available_eras": [],
		"dialogue": {"default": "This interaction still needs authored dialogue."}
	})
	active_map["interactions"] = interactions
	select_interaction(interactions.size() - 1)
	if save_active_map():
		set_status("Added interaction '%s' at %s." % [candidate, world_position], false)

func select_interaction_near(world_position: Vector2) -> void:
	var interactions: Array = active_map.get("interactions", [])
	var best_index := -1
	var best_distance := 28.0
	for index in range(interactions.size()):
		var interaction: Dictionary = interactions[index]
		var position := Repository.data_to_vector(interaction.get("position"), Vector2.ZERO)
		var distance := position.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	select_interaction(best_index)

func select_interaction(index: int) -> void:
	selected_interaction_index = index
	var interactions: Array = active_map.get("interactions", [])
	if index < 0 or index >= interactions.size():
		selected_interaction_index = -1
		map_canvas.set_selected_interaction("")
		set_inspector_enabled(false)
		interaction_id_edit.text = ""
		interaction_dialogue.text = ""
		return
	var interaction: Dictionary = interactions[index]
	map_canvas.set_selected_interaction(String(interaction.get("id", "")))
	set_inspector_enabled(true)
	populate_interaction_inspector(index)

func populate_interaction_inspector(index: int) -> void:
	var interactions: Array = active_map.get("interactions", [])
	if index < 0 or index >= interactions.size():
		return
	var interaction: Dictionary = interactions[index]
	interaction_id_edit.text = String(interaction.get("id", ""))
	var kind := String(interaction.get("kind", "marker"))
	for item_index in range(interaction_kind_selector.item_count):
		if interaction_kind_selector.get_item_text(item_index) == kind:
			interaction_kind_selector.select(item_index)
			break
	interaction_radius.value = float(interaction.get("radius", 48.0))
	var available: Array = interaction.get("available_eras", [])
	interaction_era_only.button_pressed = available.size() == 1 and available.has(selected_era_id())
	var dialogue_value: Variant = interaction.get("dialogue", "")
	if typeof(dialogue_value) == TYPE_DICTIONARY:
		var dialogue_by_era: Dictionary = dialogue_value
		interaction_dialogue.text = String(dialogue_by_era.get(selected_era_id(), dialogue_by_era.get("default", "")))
	else:
		interaction_dialogue.text = String(dialogue_value)

func set_inspector_enabled(enabled: bool) -> void:
	interaction_id_edit.editable = enabled
	interaction_kind_selector.disabled = not enabled
	interaction_radius.editable = enabled
	interaction_era_only.disabled = not enabled
	interaction_dialogue.editable = enabled
	apply_interaction_button.disabled = not enabled
	delete_interaction_button.disabled = not enabled

func apply_interaction() -> void:
	var interactions: Array = active_map.get("interactions", [])
	if selected_interaction_index < 0 or selected_interaction_index >= interactions.size():
		return
	var interaction: Dictionary = interactions[selected_interaction_index]
	var requested_id := Repository.normalise_id(interaction_id_edit.text)
	if requested_id.is_empty():
		set_status("Interaction ID cannot be empty.", true)
		return
	for index in range(interactions.size()):
		var other: Dictionary = interactions[index]
		if index != selected_interaction_index and String(other.get("id", "")) == requested_id:
			set_status("Interaction ID '%s' is already used." % requested_id, true)
			return
	interaction["id"] = requested_id
	interaction["kind"] = interaction_kind_selector.get_item_text(interaction_kind_selector.selected)
	interaction["radius"] = interaction_radius.value
	interaction["available_eras"] = [selected_era_id()] if interaction_era_only.button_pressed else []
	var existing_dialogue: Variant = interaction.get("dialogue", {})
	var dialogue_by_era: Dictionary = {}
	if typeof(existing_dialogue) == TYPE_DICTIONARY:
		dialogue_by_era = existing_dialogue
	else:
		dialogue_by_era["default"] = String(existing_dialogue)
	var era_key := selected_era_id()
	if era_key.is_empty():
		era_key = "default"
	dialogue_by_era[era_key] = interaction_dialogue.text
	interaction["dialogue"] = dialogue_by_era
	interactions[selected_interaction_index] = interaction
	active_map["interactions"] = interactions
	map_canvas.set_selected_interaction(requested_id)
	if save_active_map():
		set_status("Updated interaction '%s'." % requested_id, false)

func delete_interaction() -> void:
	var interactions: Array = active_map.get("interactions", [])
	if selected_interaction_index < 0 or selected_interaction_index >= interactions.size():
		return
	var interaction: Dictionary = interactions[selected_interaction_index]
	var deleted_id := String(interaction.get("id", "interaction"))
	interactions.remove_at(selected_interaction_index)
	active_map["interactions"] = interactions
	select_interaction(-1)
	if save_active_map():
		set_status("Deleted interaction '%s'." % deleted_id, false)

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
	if not report.get("warnings", []).is_empty():
		set_status(format_report(report), false)
	return true

func validate_all_campaigns() -> void:
	var report := Validator.validate_all()
	set_status(format_report(report), not report.get("ok", false))

func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(
		"%d campaign(s), %d map(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", campaigns.size()),
			report.get("map_count", 0),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
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
