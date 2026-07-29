@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/combat_director_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EncounterZoneModel = preload("res://src/game/encounter_zone_model.gd")
const CombatDirectorCanvas = preload("res://addons/epochbound_combat_director/combat_director_canvas.gd")

const HISTORY_LIMIT := 40

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_map: Dictionary = {}
var active_catalog: Dictionary = {}
var definitions: Dictionary = {}
var active_campaign_path := ""
var active_map_path := ""
var active_catalog_path := ""
var selected_zone_index := -1
var undo_stack: Array = []
var redo_stack: Array = []

var campaign_selector: OptionButton
var map_selector: OptionButton
var era_selector: OptionButton
var canvas
var zone_list: ItemList
var zone_id_edit: LineEdit
var zone_display_edit: LineEdit
var zone_x: SpinBox
var zone_y: SpinBox
var zone_radius: SpinBox
var zone_activation: SpinBox
var zone_leash: SpinBox
var zone_state_key: LineEdit
var zone_era_only: CheckBox
var zone_enemy_list: ItemList
var apply_zone_button: Button
var delete_zone_button: Button
var enemy_definition_selector: OptionButton
var patrol_radius: SpinBox
var leash_radius: SpinBox
var stagger_duration: SpinBox
var knockback_distance: SpinBox
var attack_windup: SpinBox
var return_speed_multiplier: SpinBox
var target_memory: SpinBox
var contact_knockback: SpinBox
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
	title.text = "Epochbound Combat Director"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(make_button("Undo", undo))
	header.add_child(make_button("Redo", redo))
	header.add_child(make_button("Validate All", validate_all))
	header.add_child(make_button("Open Campaign Folder", open_campaign_folder))

	var selectors := HBoxContainer.new()
	root.add_child(selectors)
	selectors.add_child(make_heading("CAMPAIGN"))
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 240
	campaign_selector.item_selected.connect(on_campaign_selected)
	selectors.add_child(campaign_selector)
	selectors.add_child(make_heading("MAP"))
	map_selector = OptionButton.new()
	map_selector.custom_minimum_size.x = 220
	map_selector.item_selected.connect(on_map_selected)
	selectors.add_child(map_selector)
	selectors.add_child(make_heading("ERA"))
	era_selector = OptionButton.new()
	era_selector.custom_minimum_size.x = 160
	era_selector.item_selected.connect(on_era_selected)
	selectors.add_child(era_selector)
	var selector_spacer := Control.new()
	selector_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_child(selector_spacer)
	selectors.add_child(make_button("Place Zone", begin_place_zone))
	selectors.add_child(make_button("Select", begin_select_zone))
	selectors.add_child(make_button("Save Map", save_active_map))

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 230
	left.add_theme_constant_override("separation", 5)
	split.add_child(left)
	left.add_child(make_heading("ENCOUNTER ZONES"))
	zone_list = ItemList.new()
	zone_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	zone_list.item_selected.connect(select_zone)
	left.add_child(zone_list)
	left.add_child(make_field_label("Zone identifier"))
	zone_id_edit = LineEdit.new()
	left.add_child(zone_id_edit)
	left.add_child(make_field_label("Display name"))
	zone_display_edit = LineEdit.new()
	left.add_child(zone_display_edit)
	var position_row := HBoxContainer.new()
	left.add_child(position_row)
	zone_x = make_spin(0.0, 4096.0, 1.0, 0.0)
	zone_y = make_spin(0.0, 4096.0, 1.0, 0.0)
	position_row.add_child(make_labeled_control("X", zone_x))
	position_row.add_child(make_labeled_control("Y", zone_y))
	zone_radius = make_spin(8.0, 1024.0, 1.0, 96.0)
	zone_activation = make_spin(8.0, 1536.0, 1.0, 144.0)
	zone_leash = make_spin(0.0, 512.0, 1.0, 36.0)
	left.add_child(make_labeled_control("Zone radius", zone_radius))
	left.add_child(make_labeled_control("Activation radius", zone_activation))
	left.add_child(make_labeled_control("Leash padding", zone_leash))
	left.add_child(make_field_label("Clear state key (optional)"))
	zone_state_key = LineEdit.new()
	left.add_child(zone_state_key)
	zone_era_only = CheckBox.new()
	zone_era_only.text = "Only available in selected era"
	left.add_child(zone_era_only)
	left.add_child(make_field_label("Enemy placements in this zone"))
	zone_enemy_list = ItemList.new()
	zone_enemy_list.select_mode = ItemList.SELECT_MULTI
	zone_enemy_list.custom_minimum_size.y = 150
	left.add_child(zone_enemy_list)
	apply_zone_button = make_button("Apply Zone", apply_zone)
	delete_zone_button = make_button("Delete Zone", delete_zone)
	left.add_child(apply_zone_button)
	left.add_child(delete_zone_button)
	set_zone_inspector_enabled(false)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 3.0
	center.add_theme_constant_override("separation", 5)
	split.add_child(center)
	var canvas_hint := Label.new()
	canvas_hint.text = "LEFT: place/select   RIGHT: erase scoped cell   MIDDLE: pan   WHEEL: zoom"
	canvas_hint.modulate = Color("8f9ca7")
	center.add_child(canvas_hint)
	canvas = CombatDirectorCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.canvas_clicked.connect(on_canvas_clicked)
	center.add_child(canvas)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 280
	right.add_theme_constant_override("separation", 5)
	split.add_child(right)
	right.add_child(make_heading("ENEMY BEHAVIOUR TUNING"))
	enemy_definition_selector = OptionButton.new()
	enemy_definition_selector.item_selected.connect(on_enemy_definition_selected)
	right.add_child(enemy_definition_selector)
	patrol_radius = make_spin(0.0, 512.0, 1.0, 24.0)
	leash_radius = make_spin(0.0, 1536.0, 1.0, 0.0)
	stagger_duration = make_spin(0.05, 2.0, 0.01, 0.18)
	knockback_distance = make_spin(0.0, 256.0, 1.0, 22.0)
	attack_windup = make_spin(0.05, 2.0, 0.01, 0.24)
	return_speed_multiplier = make_spin(0.1, 3.0, 0.05, 0.9)
	target_memory = make_spin(0.0, 10.0, 0.05, 0.8)
	contact_knockback = make_spin(0.0, 256.0, 1.0, 20.0)
	right.add_child(make_labeled_control("Patrol radius", patrol_radius))
	right.add_child(make_labeled_control("Leash radius (0 = zone)", leash_radius))
	right.add_child(make_labeled_control("Stagger duration", stagger_duration))
	right.add_child(make_labeled_control("Knockback distance", knockback_distance))
	right.add_child(make_labeled_control("Attack windup", attack_windup))
	right.add_child(make_labeled_control("Return speed multiplier", return_speed_multiplier))
	right.add_child(make_labeled_control("Target memory", target_memory))
	right.add_child(make_labeled_control("Contact knockback", contact_knockback))
	right.add_child(make_button("Apply Enemy Tuning", apply_enemy_tuning))
	var behaviour_help := RichTextLabel.new()
	behaviour_help.fit_content = true
	behaviour_help.bbcode_enabled = true
	behaviour_help.text = "[color=#9da9b3]Zones activate groups and provide a shared leash. Enemy definitions control patrol, telegraph, stagger, return speed and hit response. Use explicit zones for production encounters rather than relying on awareness radius alone.[/color]"
	right.add_child(behaviour_help)

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 66
	status_label.text = "[color=#9aa8b5]Combat Director ready.[/color]"
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
		set_status("No source campaigns found under res://campaigns.", true)
		return
	campaign_selector.select(selected_index)
	on_campaign_selected(selected_index)


func on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = str(campaign_selector.get_item_metadata(index))
	var result := Repository.read_json(active_campaign_path)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	load_primary_catalog()
	populate_maps()
	populate_enemy_definitions()
	set_status("Loaded combat data for '%s'." % active_campaign.get("title", active_campaign.get("id", "campaign")), false)


func load_primary_catalog() -> void:
	var catalog_result := ObjectCatalog.load_catalogs(active_campaign_path, active_campaign)
	definitions = catalog_result.get("definitions", {})
	var files: Array = catalog_result.get("files", [])
	if files.is_empty():
		active_catalog = ObjectCatalog.default_catalog()
		active_catalog_path = ObjectCatalog.primary_catalog_path(active_campaign_path, active_campaign)
		return
	var record: Dictionary = files[0]
	active_catalog_path = str(record.get("path", ""))
	active_catalog = record.get("data", {})


func populate_maps() -> void:
	map_selector.clear()
	var map_files: Array = active_campaign.get("map_files", [])
	for relative_value in map_files:
		var relative_path := str(relative_value)
		var path := active_campaign_path.get_base_dir().path_join(relative_path)
		var result := Repository.read_json(path)
		if not result.get("ok", false):
			continue
		var data: Dictionary = result.get("data", {})
		var index := map_selector.item_count
		map_selector.add_item(str(data.get("display_name", data.get("id", "Map"))))
		map_selector.set_item_metadata(index, path)
	if map_selector.item_count > 0:
		map_selector.select(0)
		on_map_selected(0)
	else:
		active_map = {}
		active_map_path = ""
		refresh_map_ui()


func on_map_selected(index: int) -> void:
	if index < 0 or index >= map_selector.item_count:
		return
	active_map_path = str(map_selector.get_item_metadata(index))
	var result := Repository.read_json(active_map_path)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_map = result.get("data", {})
	undo_stack.clear()
	redo_stack.clear()
	selected_zone_index = -1
	populate_eras()
	refresh_map_ui()


func populate_eras() -> void:
	era_selector.clear()
	var eras: Array = active_map.get("eras", [])
	for era_value in eras:
		if typeof(era_value) != TYPE_DICTIONARY:
			continue
		var era: Dictionary = era_value
		var index := era_selector.item_count
		era_selector.add_item(str(era.get("display_name", era.get("id", "Era"))))
		era_selector.set_item_metadata(index, str(era.get("id", "")))
	if era_selector.item_count > 0:
		era_selector.select(0)


func on_era_selected(index: int) -> void:
	if index < 0 or index >= era_selector.item_count:
		return
	canvas.set_era(selected_era_id())
	refresh_zone_list()
	populate_zone_enemy_list()
	if selected_zone_index >= 0:
		populate_zone_inspector(selected_zone_index)


func selected_era_id() -> String:
	if era_selector == null or era_selector.item_count == 0:
		return ""
	return str(era_selector.get_item_metadata(era_selector.selected))


func refresh_map_ui() -> void:
	canvas.set_map_data(active_map)
	canvas.set_encounter_data(definitions)
	canvas.set_era(selected_era_id())
	canvas.set_selected_zone("")
	refresh_zone_list()
	populate_zone_enemy_list()
	select_zone(-1)


func refresh_zone_list() -> void:
	zone_list.clear()
	var zones: Array = active_map.get("encounter_zones", [])
	for index in range(zones.size()):
		if typeof(zones[index]) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zones[index]
		if not EncounterZoneModel.record_is_available(zone, selected_era_id()):
			continue
		var item_index := zone_list.item_count
		zone_list.add_item(str(zone.get("display_name", zone.get("id", "Encounter"))))
		zone_list.set_item_metadata(item_index, index)


func populate_zone_enemy_list() -> void:
	zone_enemy_list.clear()
	var placements: Array = active_map.get("object_placements", [])
	for placement_value in placements:
		if typeof(placement_value) != TYPE_DICTIONARY:
			continue
		var placement: Dictionary = placement_value
		var object_id := str(placement.get("object_id", ""))
		var definition_data: Dictionary = definitions.get(object_id, {})
		if str(definition_data.get("kind", "")) != "enemy":
			continue
		var item_index := zone_enemy_list.item_count
		var placement_id := str(placement.get("id", "enemy"))
		zone_enemy_list.add_item("%s  ·  %s" % [placement_id, definition_data.get("display_name", object_id)])
		zone_enemy_list.set_item_metadata(item_index, placement_id)


func begin_place_zone() -> void:
	canvas.set_tool("zone_place")
	set_status("Click the map to place a new encounter zone.", false)


func begin_select_zone() -> void:
	canvas.set_tool("zone_select")
	set_status("Click near a zone centre to select it.", false)


func on_canvas_clicked(world_position: Vector2, tool: String) -> void:
	if active_map.is_empty():
		return
	if tool == "zone_place":
		add_zone(world_position)
	else:
		select_zone_near(world_position)


func add_zone(world_position: Vector2) -> void:
	push_history()
	var zones: Array = active_map.get("encounter_zones", [])
	var identifier := next_zone_id(zones)
	var zone := EncounterZoneModel.default_zone(identifier, world_position)
	zone["display_name"] = identifier.replace("_", " ").capitalize()
	if not selected_era_id().is_empty():
		zone["available_eras"] = [selected_era_id()]
	zones.append(zone)
	active_map["encounter_zones"] = zones
	selected_zone_index = zones.size() - 1
	canvas.set_tool("zone_select")
	refresh_zone_list()
	select_zone_by_record_index(selected_zone_index)
	save_active_map()
	set_status("Added encounter zone '%s'." % identifier, false)


func next_zone_id(zones: Array) -> String:
	var used: Dictionary = {}
	for value in zones:
		if typeof(value) == TYPE_DICTIONARY:
			used[str((value as Dictionary).get("id", ""))] = true
	var number := 1
	var candidate := "encounter_%03d" % number
	while used.has(candidate):
		number += 1
		candidate = "encounter_%03d" % number
	return candidate


func select_zone_near(world_position: Vector2) -> void:
	var zones: Array = active_map.get("encounter_zones", [])
	var best_index := -1
	var best_distance := 48.0
	for index in range(zones.size()):
		if typeof(zones[index]) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zones[index]
		if not EncounterZoneModel.record_is_available(zone, selected_era_id()):
			continue
		var distance := EncounterZoneModel.center(zone).distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	select_zone_by_record_index(best_index)


func select_zone(item_index: int) -> void:
	if item_index < 0 or item_index >= zone_list.item_count:
		select_zone_by_record_index(-1)
		return
	select_zone_by_record_index(int(zone_list.get_item_metadata(item_index)))


func select_zone_by_record_index(record_index: int) -> void:
	selected_zone_index = record_index
	var zones: Array = active_map.get("encounter_zones", [])
	if record_index < 0 or record_index >= zones.size() or typeof(zones[record_index]) != TYPE_DICTIONARY:
		selected_zone_index = -1
		canvas.set_selected_zone("")
		set_zone_inspector_enabled(false)
		clear_zone_fields()
		return
	var zone: Dictionary = zones[record_index]
	canvas.set_selected_zone(str(zone.get("id", "")))
	set_zone_inspector_enabled(true)
	populate_zone_inspector(record_index)
	for item_index in range(zone_list.item_count):
		if int(zone_list.get_item_metadata(item_index)) == record_index:
			zone_list.select(item_index)
			break


func populate_zone_inspector(record_index: int) -> void:
	var zones: Array = active_map.get("encounter_zones", [])
	if record_index < 0 or record_index >= zones.size():
		return
	var zone: Dictionary = zones[record_index]
	var position := EncounterZoneModel.center(zone)
	zone_id_edit.text = str(zone.get("id", ""))
	zone_display_edit.text = str(zone.get("display_name", ""))
	zone_x.value = position.x
	zone_y.value = position.y
	zone_radius.value = EncounterZoneModel.radius(zone)
	zone_activation.value = EncounterZoneModel.activation_radius(zone)
	zone_leash.value = EncounterZoneModel.leash_padding(zone)
	zone_state_key.text = str(zone.get("clear_state_key", ""))
	var available_value: Variant = zone.get("available_eras", [])
	var available: Array = available_value if typeof(available_value) == TYPE_ARRAY else []
	zone_era_only.button_pressed = available.size() == 1 and available.has(selected_era_id())
	var enemy_ids := EncounterZoneModel.enemy_placement_ids(zone)
	zone_enemy_list.deselect_all()
	for item_index in range(zone_enemy_list.item_count):
		if enemy_ids.has(str(zone_enemy_list.get_item_metadata(item_index))):
			zone_enemy_list.select(item_index, false)


func apply_zone() -> void:
	var zones: Array = active_map.get("encounter_zones", [])
	if selected_zone_index < 0 or selected_zone_index >= zones.size():
		return
	var identifier := Repository.normalise_id(zone_id_edit.text)
	if identifier.is_empty():
		set_status("Zone identifier cannot be empty.", true)
		return
	for index in range(zones.size()):
		if index == selected_zone_index or typeof(zones[index]) != TYPE_DICTIONARY:
			continue
		if str((zones[index] as Dictionary).get("id", "")) == identifier:
			set_status("Zone identifier '%s' is already used." % identifier, true)
			return
	push_history()
	var zone: Dictionary = zones[selected_zone_index]
	zone["id"] = identifier
	zone["display_name"] = zone_display_edit.text.strip_edges() if not zone_display_edit.text.strip_edges().is_empty() else identifier.replace("_", " ").capitalize()
	zone["position"] = Repository.vector_to_data(Vector2(zone_x.value, zone_y.value))
	zone["radius"] = zone_radius.value
	zone["activation_radius"] = zone_activation.value
	zone["leash_padding"] = zone_leash.value
	zone["clear_state_key"] = zone_state_key.text.strip_edges()
	zone["available_eras"] = [selected_era_id()] if zone_era_only.button_pressed else []
	var selected_enemies: Array = []
	for item_index in range(zone_enemy_list.item_count):
		if zone_enemy_list.is_selected(item_index):
			selected_enemies.append(str(zone_enemy_list.get_item_metadata(item_index)))
	zone["enemy_placements"] = selected_enemies
	zones[selected_zone_index] = zone
	active_map["encounter_zones"] = zones
	if save_active_map():
		refresh_map_ui()
		select_zone_by_record_index(selected_zone_index)
		set_status("Updated encounter zone '%s'." % identifier, false)


func delete_zone() -> void:
	var zones: Array = active_map.get("encounter_zones", [])
	if selected_zone_index < 0 or selected_zone_index >= zones.size():
		return
	var zone: Dictionary = zones[selected_zone_index]
	var identifier := str(zone.get("id", "encounter"))
	push_history()
	zones.remove_at(selected_zone_index)
	active_map["encounter_zones"] = zones
	selected_zone_index = -1
	if save_active_map():
		refresh_map_ui()
		set_status("Deleted encounter zone '%s'." % identifier, false)


func set_zone_inspector_enabled(enabled: bool) -> void:
	zone_id_edit.editable = enabled
	zone_display_edit.editable = enabled
	zone_x.editable = enabled
	zone_y.editable = enabled
	zone_radius.editable = enabled
	zone_activation.editable = enabled
	zone_leash.editable = enabled
	zone_state_key.editable = enabled
	zone_era_only.disabled = not enabled
	zone_enemy_list.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	apply_zone_button.disabled = not enabled
	delete_zone_button.disabled = not enabled


func clear_zone_fields() -> void:
	zone_id_edit.text = ""
	zone_display_edit.text = ""
	zone_x.value = 0.0
	zone_y.value = 0.0
	zone_state_key.text = ""
	zone_era_only.button_pressed = false
	zone_enemy_list.deselect_all()


func populate_enemy_definitions() -> void:
	enemy_definition_selector.clear()
	var ids := PackedStringArray()
	for object_id in definitions.keys():
		var definition_data: Dictionary = definitions.get(object_id, {})
		if str(definition_data.get("kind", "")) == "enemy":
			ids.append(str(object_id))
	ids.sort()
	for object_id in ids:
		var definition_data: Dictionary = definitions.get(object_id, {})
		var index := enemy_definition_selector.item_count
		enemy_definition_selector.add_item(str(definition_data.get("display_name", object_id)))
		enemy_definition_selector.set_item_metadata(index, object_id)
	if enemy_definition_selector.item_count > 0:
		enemy_definition_selector.select(0)
		on_enemy_definition_selected(0)


func on_enemy_definition_selected(index: int) -> void:
	if index < 0 or index >= enemy_definition_selector.item_count:
		return
	var object_id := str(enemy_definition_selector.get_item_metadata(index))
	var definition_data: Dictionary = definitions.get(object_id, {})
	patrol_radius.value = float(definition_data.get("patrol_radius", 24.0))
	leash_radius.value = float(definition_data.get("leash_radius", 0.0))
	stagger_duration.value = float(definition_data.get("stagger_duration", 0.18))
	knockback_distance.value = float(definition_data.get("knockback_distance", 22.0))
	attack_windup.value = float(definition_data.get("attack_windup", 0.24))
	return_speed_multiplier.value = float(definition_data.get("return_speed_multiplier", 0.9))
	target_memory.value = float(definition_data.get("target_memory", 0.8))
	contact_knockback.value = float(definition_data.get("contact_knockback", 20.0))


func apply_enemy_tuning() -> void:
	if enemy_definition_selector.item_count == 0:
		return
	var object_id := str(enemy_definition_selector.get_item_metadata(enemy_definition_selector.selected))
	var objects_value: Variant = active_catalog.get("objects", [])
	if typeof(objects_value) != TYPE_ARRAY:
		set_status("Active object catalog has no objects array.", true)
		return
	var objects: Array = objects_value
	var changed := false
	for index in range(objects.size()):
		if typeof(objects[index]) != TYPE_DICTIONARY:
			continue
		var definition_data: Dictionary = objects[index]
		if str(definition_data.get("id", "")) != object_id:
			continue
		definition_data["patrol_radius"] = patrol_radius.value
		definition_data["leash_radius"] = leash_radius.value
		definition_data["stagger_duration"] = stagger_duration.value
		definition_data["knockback_distance"] = knockback_distance.value
		definition_data["attack_windup"] = attack_windup.value
		definition_data["return_speed_multiplier"] = return_speed_multiplier.value
		definition_data["target_memory"] = target_memory.value
		definition_data["contact_knockback"] = contact_knockback.value
		objects[index] = definition_data
		changed = true
		break
	if not changed:
		set_status("Enemy definition '%s' is not in the editable primary catalog." % object_id, true)
		return
	active_catalog["objects"] = objects
	var result := Repository.save_json(active_catalog_path, active_catalog)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	load_primary_catalog()
	populate_enemy_definitions()
	canvas.set_encounter_data(definitions)
	rescan_editor_files()
	var report := Validator.validate_campaign_path(active_campaign_path)
	set_status(format_report(report), not report.get("ok", false))


func save_active_map() -> bool:
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
	canvas.set_map_data(active_map)
	rescan_editor_files()
	if not report.get("warnings", []).is_empty():
		set_status(format_report(report), false)
	return true


func validate_all() -> void:
	var report := Validator.validate_all()
	set_status(format_report(report), not report.get("ok", false))


func push_history() -> void:
	if active_map.is_empty():
		return
	undo_stack.append(active_map.duplicate(true))
	if undo_stack.size() > HISTORY_LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()


func undo() -> void:
	if undo_stack.is_empty() or active_map.is_empty():
		return
	redo_stack.append(active_map.duplicate(true))
	active_map = undo_stack.pop_back()
	selected_zone_index = -1
	save_active_map()
	refresh_map_ui()
	set_status("Undid the latest combat-director map edit.", false)


func redo() -> void:
	if redo_stack.is_empty() or active_map.is_empty():
		return
	undo_stack.append(active_map.duplicate(true))
	active_map = redo_stack.pop_back()
	selected_zone_index = -1
	save_active_map()
	refresh_map_ui()
	set_status("Redid the combat-director map edit.", false)


func clear_all() -> void:
	active_campaign = {}
	active_map = {}
	active_catalog = {}
	definitions = {}
	active_campaign_path = ""
	active_map_path = ""
	active_catalog_path = ""
	map_selector.clear()
	era_selector.clear()
	zone_list.clear()
	enemy_definition_selector.clear()
	canvas.set_map_data({})
	select_zone_by_record_index(-1)


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(
		"%d campaign(s), %d map(s), %d object definition(s), %d placement(s), %d encounter zone(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 1 if not active_campaign.is_empty() else 0),
			report.get("map_count", 1 if not active_map.is_empty() else 0),
			report.get("definition_count", definitions.size()),
			report.get("placement_count", active_map.get("object_placements", []).size()),
			report.get("zone_count", active_map.get("encounter_zones", []).size()),
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
