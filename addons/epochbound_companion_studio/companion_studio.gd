@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const CompanionModel = preload("res://src/game/companion_model.gd")
const Validator = preload("res://src/content/companion_validator.gd")
const CompanionCanvas = preload("res://addons/epochbound_companion_studio/companion_canvas.gd")

const HISTORY_LIMIT := 40

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_map: Dictionary = {}
var definitions: Dictionary = {}
var active_campaign_path := ""
var active_map_path := ""
var selected_cue_index := -1
var undo_stack: Array = []
var redo_stack: Array = []

var campaign_selector: OptionButton
var map_selector: OptionButton
var era_selector: OptionButton
var canvas
var cue_list: ItemList
var cue_id_edit: LineEdit
var cue_kind_selector: OptionButton
var cue_x: SpinBox
var cue_y: SpinBox
var cue_radius: SpinBox
var cue_message: TextEdit
var cue_reward: SpinBox
var cue_visible: CheckBox
var cue_era_only: CheckBox
var cue_state_key: LineEdit
var apply_cue_button: Button
var delete_cue_button: Button
var profile_name: LineEdit
var profile_health: SpinBox
var profile_follow_distance: SpinBox
var profile_guard_distance: SpinBox
var profile_recovery_distance: SpinBox
var profile_seek_radius: SpinBox
var profile_seek_speed: SpinBox
var profile_guard_range: SpinBox
var command_checks: Dictionary = {}
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
	title.text = "Epochbound Companion Studio"
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
	campaign_selector.custom_minimum_size.x = 230
	campaign_selector.item_selected.connect(on_campaign_selected)
	selectors.add_child(campaign_selector)
	selectors.add_child(make_heading("MAP"))
	map_selector = OptionButton.new()
	map_selector.custom_minimum_size.x = 210
	map_selector.item_selected.connect(on_map_selected)
	selectors.add_child(map_selector)
	selectors.add_child(make_heading("ERA"))
	era_selector = OptionButton.new()
	era_selector.custom_minimum_size.x = 150
	era_selector.item_selected.connect(on_era_selected)
	selectors.add_child(era_selector)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_child(spacer)
	selectors.add_child(make_button("Place Cue", begin_place_cue))
	selectors.add_child(make_button("Select", begin_select_cue))
	selectors.add_child(make_button("Save Map", save_active_map))

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 275
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 5)
	left_scroll.add_child(left)
	left.add_child(make_heading("SCENT, CLUE AND TRAIL CUES"))
	cue_list = ItemList.new()
	cue_list.custom_minimum_size.y = 180
	cue_list.item_selected.connect(select_cue)
	left.add_child(cue_list)
	left.add_child(make_field_label("Stable cue ID"))
	cue_id_edit = LineEdit.new()
	left.add_child(cue_id_edit)
	left.add_child(make_field_label("Cue kind"))
	cue_kind_selector = OptionButton.new()
	for kind in CompanionModel.ALLOWED_CUE_KINDS:
		cue_kind_selector.add_item(kind.capitalize())
		cue_kind_selector.set_item_metadata(cue_kind_selector.item_count - 1, kind)
	left.add_child(cue_kind_selector)
	var position_row := HBoxContainer.new()
	position_row.add_child(make_labeled_control("X", assign_spin(0.0, 8192.0, 1.0, 0.0, "cue_x")))
	position_row.add_child(make_labeled_control("Y", assign_spin(0.0, 8192.0, 1.0, 0.0, "cue_y")))
	left.add_child(position_row)
	cue_radius = make_spin(4.0, 512.0, 1.0, 22.0)
	left.add_child(make_labeled_control("Reveal radius", cue_radius))
	left.add_child(make_field_label("Discovery message"))
	cue_message = TextEdit.new()
	cue_message.custom_minimum_size.y = 105
	left.add_child(cue_message)
	cue_reward = make_spin(0.0, 9999.0, 1.0, 0.0)
	left.add_child(make_labeled_control("Clock-shard reward", cue_reward))
	cue_visible = CheckBox.new()
	cue_visible.text = "Visible before companion discovery"
	left.add_child(cue_visible)
	cue_era_only = CheckBox.new()
	cue_era_only.text = "Available only in selected era"
	left.add_child(cue_era_only)
	left.add_child(make_field_label("Persistent state key (optional)"))
	cue_state_key = LineEdit.new()
	left.add_child(cue_state_key)
	apply_cue_button = make_button("Apply Cue", apply_cue)
	delete_cue_button = make_button("Delete Cue", delete_cue)
	left.add_child(apply_cue_button)
	left.add_child(delete_cue_button)
	set_cue_inspector_enabled(false)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 3.0
	center.add_theme_constant_override("separation", 5)
	split.add_child(center)
	var canvas_hint := Label.new()
	canvas_hint.text = "LEFT: place/select   MIDDLE: pan   WHEEL: zoom"
	canvas_hint.modulate = Color("8f9ca7")
	center.add_child(canvas_hint)
	canvas = CompanionCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.connect("canvas_action", Callable(self, "on_canvas_action"))
	center.add_child(canvas)

	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size.x = 300
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	right_scroll.add_child(right)
	right.add_child(make_heading("COMPANION PROFILE"))
	profile_name = add_line_field(right, "Display name")
	profile_health = add_spin_field(right, "Maximum health", 1.0, 9999.0, 1.0, 24.0)
	profile_follow_distance = add_spin_field(right, "Follow distance", 8.0, 512.0, 1.0, 34.0)
	profile_guard_distance = add_spin_field(right, "Guard distance", 8.0, 512.0, 1.0, 24.0)
	profile_recovery_distance = add_spin_field(right, "Recovery distance", 32.0, 4096.0, 1.0, 300.0)
	profile_seek_radius = add_spin_field(right, "Seek radius", 16.0, 4096.0, 1.0, 280.0)
	profile_seek_speed = add_spin_field(right, "Seek speed", 16.0, 1000.0, 1.0, 145.0)
	profile_guard_range = add_spin_field(right, "Guard attack range", 16.0, 1000.0, 1.0, 52.0)
	right.add_child(make_heading("AVAILABLE COMMANDS"))
	for command in CompanionModel.ALLOWED_COMMANDS:
		var check := CheckBox.new()
		check.text = CompanionModel.command_label(command)
		command_checks[command] = check
		right.add_child(check)
	right.add_child(make_button("Save Companion Profile", save_profile))
	var profile_help := RichTextLabel.new()
	profile_help.fit_content = true
	profile_help.bbcode_enabled = true
	profile_help.text = "[color=#9ca8b1]Follow keeps the companion on the player trail. Stay holds an authored position. Seek resolves the nearest undiscovered cue. Guard follows closely and extends combat assistance. Recall remains available as a safety action.[/color]"
	right.add_child(profile_help)

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 66
	status_label.text = "[color=#9aa8b5]Companion Studio ready.[/color]"
	root.add_child(status_label)


func assign_spin(minimum: float, maximum: float, step: float, initial: float, field_name: String) -> SpinBox:
	var spin := make_spin(minimum, maximum, step, initial)
	if field_name == "cue_x":
		cue_x = spin
	else:
		cue_y = spin
	return spin


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


func add_line_field(parent: VBoxContainer, label_text: String) -> LineEdit:
	parent.add_child(make_field_label(label_text))
	var edit := LineEdit.new()
	parent.add_child(edit)
	return edit


func add_spin_field(
	parent: VBoxContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	initial: float
) -> SpinBox:
	var spin := make_spin(minimum, maximum, step, initial)
	parent.add_child(make_labeled_control(label_text, spin))
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
	var result := Repository.read_json(active_campaign_path)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	load_definitions()
	populate_profile()
	populate_maps()
	set_status("Loaded companion content for '%s'." % active_campaign.get("title", active_campaign.get("id", "campaign")), false)


func load_definitions() -> void:
	var result := ObjectCatalog.load_catalogs(active_campaign_path, active_campaign)
	definitions = result.get("definitions", {})


func populate_profile() -> void:
	var profile := CompanionModel.profile(active_campaign)
	profile_name.text = str(profile.get("name", "COMPANION"))
	profile_health.value = float(profile.get("max_health", 24))
	profile_follow_distance.value = CompanionModel.follow_distance(profile)
	profile_guard_distance.value = CompanionModel.guard_distance(profile)
	profile_recovery_distance.value = CompanionModel.recovery_distance(profile)
	profile_seek_radius.value = CompanionModel.seek_radius(profile)
	profile_seek_speed.value = CompanionModel.seek_speed(profile)
	profile_guard_range.value = CompanionModel.guard_attack_range(profile)
	var commands := CompanionModel.allowed_commands(profile)
	for command in command_checks.keys():
		var check: CheckBox = command_checks[command]
		check.button_pressed = commands.has(str(command))


func save_profile() -> void:
	var commands: Array = []
	for command in CompanionModel.ALLOWED_COMMANDS:
		var check: CheckBox = command_checks.get(command)
		if check != null and check.button_pressed:
			commands.append(command)
	if not commands.has("follow"):
		commands.push_front("follow")
	var profile := {
		"name": profile_name.text.strip_edges(),
		"max_health": int(profile_health.value),
		"commands": commands,
		"follow_distance": profile_follow_distance.value,
		"guard_distance": profile_guard_distance.value,
		"recovery_distance": profile_recovery_distance.value,
		"seek_radius": profile_seek_radius.value,
		"seek_speed": profile_seek_speed.value,
		"guard_attack_range": profile_guard_range.value
	}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	Validator.validate_profile(profile, str(active_campaign.get("id", "campaign")), errors, warnings)
	if not errors.is_empty():
		set_status(format_messages(errors), true)
		return
	var actors: Dictionary = active_campaign.get("actors", {})
	actors["companion"] = profile
	active_campaign["actors"] = actors
	var result := Repository.save_json(active_campaign_path, active_campaign)
	if not result.get("ok", false):
		set_status(format_messages(result.get("errors", [])), true)
		return
	rescan_editor_files()
	var report := Validator.validate_campaign_path(active_campaign_path)
	set_status(format_report(report), not report.get("ok", false))


func populate_maps() -> void:
	map_selector.clear()
	var map_files: Array = active_campaign.get("map_files", [])
	for relative_value in map_files:
		var path := active_campaign_path.get_base_dir().path_join(str(relative_value))
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
	if not active_map.has("companion_cues"):
		active_map["companion_cues"] = []
	undo_stack.clear()
	redo_stack.clear()
	selected_cue_index = -1
	populate_eras()
	refresh_map_ui()


func populate_eras() -> void:
	era_selector.clear()
	for value in active_map.get("eras", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var era: Dictionary = value
		var index := era_selector.item_count
		era_selector.add_item(str(era.get("display_name", era.get("id", "Era"))))
		era_selector.set_item_metadata(index, str(era.get("id", "")))
	if era_selector.item_count > 0:
		era_selector.select(0)


func on_era_selected(index: int) -> void:
	if index < 0 or index >= era_selector.item_count:
		return
	canvas.set_era(selected_era_id())
	refresh_cue_list()
	if selected_cue_index >= 0:
		populate_cue_inspector(selected_cue_index)


func selected_era_id() -> String:
	if era_selector == null or era_selector.item_count == 0:
		return ""
	return str(era_selector.get_item_metadata(era_selector.selected))


func refresh_map_ui() -> void:
	canvas.set_map_data(active_map)
	canvas.set_encounter_data(definitions)
	canvas.set_era(selected_era_id())
	canvas.set_selected_cue("")
	refresh_cue_list()
	select_cue_by_record_index(-1)


func refresh_cue_list() -> void:
	cue_list.clear()
	var cues: Array = active_map.get("companion_cues", [])
	for index in range(cues.size()):
		if typeof(cues[index]) != TYPE_DICTIONARY:
			continue
		var cue: Dictionary = cues[index]
		if not CompanionModel.cue_is_available(cue, selected_era_id()):
			continue
		var item_index := cue_list.item_count
		cue_list.add_item("%s  [%s]" % [cue.get("id", "cue"), str(cue.get("kind", "clue")).to_upper()])
		cue_list.set_item_metadata(item_index, index)


func begin_place_cue() -> void:
	canvas.set_tool("companion_cue_place")
	set_status("Click the map to place a new companion cue.", false)


func begin_select_cue() -> void:
	canvas.set_tool("companion_cue_select")
	set_status("Click near a companion cue to select it.", false)


func on_canvas_action(world_position: Vector2, _cell: Vector2i, tool: String, _erase: bool) -> void:
	if active_map.is_empty():
		return
	if tool == "companion_cue_place":
		add_cue(world_position)
	else:
		select_cue_near(world_position)


func add_cue(world_position: Vector2) -> void:
	push_history()
	var cues: Array = active_map.get("companion_cues", [])
	var identifier := next_cue_id(cues)
	var cue := CompanionModel.default_cue(identifier, world_position)
	if not selected_era_id().is_empty():
		cue["available_eras"] = [selected_era_id()]
	cues.append(cue)
	active_map["companion_cues"] = cues
	selected_cue_index = cues.size() - 1
	canvas.set_tool("companion_cue_select")
	if save_active_map():
		refresh_map_ui()
		select_cue_by_record_index(selected_cue_index)
		set_status("Added companion cue '%s'." % identifier, false)


func next_cue_id(cues: Array) -> String:
	var used: Dictionary = {}
	for value in cues:
		if typeof(value) == TYPE_DICTIONARY:
			used[str((value as Dictionary).get("id", ""))] = true
	var number := 1
	var candidate := "companion_cue_%03d" % number
	while used.has(candidate):
		number += 1
		candidate = "companion_cue_%03d" % number
	return candidate


func select_cue_near(world_position: Vector2) -> void:
	var cues: Array = active_map.get("companion_cues", [])
	var best_index := -1
	var best_distance := 40.0
	for index in range(cues.size()):
		if typeof(cues[index]) != TYPE_DICTIONARY:
			continue
		var cue: Dictionary = cues[index]
		if not CompanionModel.cue_is_available(cue, selected_era_id()):
			continue
		var distance := CompanionModel.cue_position(cue).distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	select_cue_by_record_index(best_index)


func select_cue(item_index: int) -> void:
	if item_index < 0 or item_index >= cue_list.item_count:
		select_cue_by_record_index(-1)
		return
	select_cue_by_record_index(int(cue_list.get_item_metadata(item_index)))


func select_cue_by_record_index(record_index: int) -> void:
	selected_cue_index = record_index
	var cues: Array = active_map.get("companion_cues", [])
	if record_index < 0 or record_index >= cues.size() or typeof(cues[record_index]) != TYPE_DICTIONARY:
		selected_cue_index = -1
		canvas.set_selected_cue("")
		set_cue_inspector_enabled(false)
		clear_cue_fields()
		return
	var cue: Dictionary = cues[record_index]
	canvas.set_selected_cue(str(cue.get("id", "")))
	set_cue_inspector_enabled(true)
	populate_cue_inspector(record_index)
	for item_index in range(cue_list.item_count):
		if int(cue_list.get_item_metadata(item_index)) == record_index:
			cue_list.select(item_index)
			break


func populate_cue_inspector(record_index: int) -> void:
	var cues: Array = active_map.get("companion_cues", [])
	if record_index < 0 or record_index >= cues.size():
		return
	var cue: Dictionary = cues[record_index]
	var position := CompanionModel.cue_position(cue)
	cue_id_edit.text = str(cue.get("id", ""))
	select_option_metadata(cue_kind_selector, str(cue.get("kind", "clue")))
	cue_x.value = position.x
	cue_y.value = position.y
	cue_radius.value = CompanionModel.cue_radius(cue)
	cue_message.text = str(cue.get("message", ""))
	cue_reward.value = float(cue.get("reward", 0))
	cue_visible.button_pressed = bool(cue.get("visible_before_discovery", false))
	var available_value: Variant = cue.get("available_eras", [])
	var available: Array = available_value if typeof(available_value) == TYPE_ARRAY else []
	cue_era_only.button_pressed = available.size() == 1 and available.has(selected_era_id())
	cue_state_key.text = str(cue.get("state_key", ""))


func apply_cue() -> void:
	var cues: Array = active_map.get("companion_cues", [])
	if selected_cue_index < 0 or selected_cue_index >= cues.size():
		return
	var identifier := Repository.normalise_id(cue_id_edit.text)
	if identifier.is_empty():
		set_status("Cue ID cannot be empty.", true)
		return
	for index in range(cues.size()):
		if index == selected_cue_index or typeof(cues[index]) != TYPE_DICTIONARY:
			continue
		if str((cues[index] as Dictionary).get("id", "")) == identifier:
			set_status("Cue ID '%s' is already used on this map." % identifier, true)
			return
	push_history()
	var cue: Dictionary = cues[selected_cue_index]
	cue["id"] = identifier
	cue["kind"] = selected_option_metadata(cue_kind_selector)
	cue["position"] = Repository.vector_to_data(Vector2(cue_x.value, cue_y.value))
	cue["reveal_radius"] = cue_radius.value
	cue["message"] = cue_message.text.strip_edges()
	cue["reward"] = int(cue_reward.value)
	cue["visible_before_discovery"] = cue_visible.button_pressed
	cue["available_eras"] = [selected_era_id()] if cue_era_only.button_pressed else []
	cue["state_key"] = cue_state_key.text.strip_edges()
	cues[selected_cue_index] = cue
	active_map["companion_cues"] = cues
	if save_active_map():
		refresh_map_ui()
		select_cue_by_record_index(selected_cue_index)
		set_status("Updated companion cue '%s'." % identifier, false)


func delete_cue() -> void:
	var cues: Array = active_map.get("companion_cues", [])
	if selected_cue_index < 0 or selected_cue_index >= cues.size():
		return
	var identifier := str((cues[selected_cue_index] as Dictionary).get("id", "cue"))
	push_history()
	cues.remove_at(selected_cue_index)
	active_map["companion_cues"] = cues
	selected_cue_index = -1
	if save_active_map():
		refresh_map_ui()
		set_status("Deleted companion cue '%s'." % identifier, false)


func set_cue_inspector_enabled(enabled: bool) -> void:
	cue_id_edit.editable = enabled
	cue_kind_selector.disabled = not enabled
	cue_x.editable = enabled
	cue_y.editable = enabled
	cue_radius.editable = enabled
	cue_message.editable = enabled
	cue_reward.editable = enabled
	cue_visible.disabled = not enabled
	cue_era_only.disabled = not enabled
	cue_state_key.editable = enabled
	apply_cue_button.disabled = not enabled
	delete_cue_button.disabled = not enabled


func clear_cue_fields() -> void:
	cue_id_edit.text = ""
	cue_x.value = 0.0
	cue_y.value = 0.0
	cue_message.text = ""
	cue_reward.value = 0.0
	cue_visible.button_pressed = false
	cue_era_only.button_pressed = false
	cue_state_key.text = ""


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
	selected_cue_index = -1
	save_active_map()
	refresh_map_ui()
	set_status("Undid the latest companion-cue edit.", false)


func redo() -> void:
	if redo_stack.is_empty() or active_map.is_empty():
		return
	undo_stack.append(active_map.duplicate(true))
	active_map = redo_stack.pop_back()
	selected_cue_index = -1
	save_active_map()
	refresh_map_ui()
	set_status("Redid the companion-cue edit.", false)


func selected_option_metadata(option: OptionButton) -> String:
	if option == null or option.item_count == 0 or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func select_option_metadata(option: OptionButton, requested: String) -> void:
	if option.item_count == 0:
		return
	var selected := 0
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == requested:
			selected = index
			break
	option.select(selected)


func clear_all() -> void:
	active_campaign = {}
	active_map = {}
	definitions = {}
	active_campaign_path = ""
	active_map_path = ""
	map_selector.clear()
	era_selector.clear()
	cue_list.clear()
	canvas.set_map_data({})
	select_cue_by_record_index(-1)


func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(
		"%d campaign(s), %d map(s), %d definition(s), %d placement(s), %d encounter zone(s), %d companion cue(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 1 if not active_campaign.is_empty() else 0),
			report.get("map_count", 1 if not active_map.is_empty() else 0),
			report.get("definition_count", definitions.size()),
			report.get("placement_count", active_map.get("object_placements", []).size()),
			report.get("zone_count", active_map.get("encounter_zones", []).size()),
			report.get("cue_count", active_map.get("companion_cues", []).size()),
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
