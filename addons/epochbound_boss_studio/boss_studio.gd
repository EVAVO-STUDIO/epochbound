@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const BossCatalog = preload("res://src/content/boss_catalog.gd")
const BossValidator = preload("res://src/content/boss_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_campaign_path := ""
var active_object_catalog: Dictionary = {}
var active_object_path := ""
var object_definitions: Dictionary = {}
var maps: Array = []
var selected_object_id := ""
var selected_map: Dictionary = {}

var campaign_selector: OptionButton
var boss_list: ItemList
var boss_enabled: CheckBox
var boss_map_label: Label
var arena_zone_selector: OptionButton
var outcome_key_edit: LineEdit
var intro_edit: TextEdit
var defeat_edit: TextEdit
var allow_era_shift_check: CheckBox
var arena_left: SpinBox
var arena_right: SpinBox
var arena_top: SpinBox
var arena_bottom: SpinBox
var connection_list: ItemList
var defeat_effects_edit: TextEdit
var phases_edit: TextEdit
var apply_button: Button
var remove_button: Button
var phase_summary: ItemList
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
	title.text = "Epochbound Boss & Phase Studio"
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

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	left.add_theme_constant_override("separation", 5)
	split.add_child(left)
	left.add_child(make_heading("ENEMY DEFINITIONS"))
	boss_list = ItemList.new()
	boss_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	boss_list.item_selected.connect(on_boss_selected)
	left.add_child(boss_list)
	var help := RichTextLabel.new()
	help.fit_content = true
	help.bbcode_enabled = true
	help.text = "[color=#87949b]Select an existing reusable enemy, enable its boss contract, then author arena locks and complete phase records. Phase and effect fields use one JSON object per line so no authored keys are flattened.[/color]"
	left.add_child(help)

	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(inspector_scroll)
	var inspector := VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 6)
	inspector_scroll.add_child(inspector)

	boss_enabled = CheckBox.new()
	boss_enabled.text = "Boss contract enabled"
	boss_enabled.toggled.connect(on_enabled_toggled)
	inspector.add_child(boss_enabled)
	boss_map_label = Label.new()
	boss_map_label.modulate = Color("8fa0aa")
	inspector.add_child(boss_map_label)
	arena_zone_selector = OptionButton.new()
	inspector.add_child(make_labeled_control("Authored encounter arena", arena_zone_selector))
	outcome_key_edit = LineEdit.new()
	outcome_key_edit.placeholder_text = "map:boss:defeated"
	inspector.add_child(make_labeled_control("Durable outcome state key", outcome_key_edit))
	intro_edit = TextEdit.new()
	intro_edit.custom_minimum_size.y = 58
	intro_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	inspector.add_child(make_labeled_control("Arena introduction", intro_edit))
	defeat_edit = TextEdit.new()
	defeat_edit.custom_minimum_size.y = 58
	defeat_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	inspector.add_child(make_labeled_control("Arena completion message", defeat_edit))
	allow_era_shift_check = CheckBox.new()
	allow_era_shift_check.text = "Allow era shifting while the arena is active"
	inspector.add_child(allow_era_shift_check)

	inspector.add_child(make_heading("ARENA BOUNDS"))
	var bounds_row := HBoxContainer.new()
	arena_left = make_spin(0, 4096, 1, 128)
	arena_right = make_spin(0, 4096, 1, 560)
	arena_top = make_spin(0, 4096, 1, 112)
	arena_bottom = make_spin(0, 4096, 1, 312)
	bounds_row.add_child(make_labeled_control("Left", arena_left))
	bounds_row.add_child(make_labeled_control("Right", arena_right))
	bounds_row.add_child(make_labeled_control("Top", arena_top))
	bounds_row.add_child(make_labeled_control("Bottom", arena_bottom))
	inspector.add_child(bounds_row)

	inspector.add_child(make_heading("LOCKED CONNECTIONS"))
	connection_list = ItemList.new()
	connection_list.select_mode = ItemList.SELECT_MULTI
	connection_list.custom_minimum_size.y = 96
	inspector.add_child(connection_list)

	defeat_effects_edit = TextEdit.new()
	defeat_effects_edit.custom_minimum_size.y = 112
	defeat_effects_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	defeat_effects_edit.placeholder_text = '{"type":"grant_clock_shards","amount":3}\n{"type":"grant_currency","currency_id":"archive_chits","amount":15}'
	inspector.add_child(make_labeled_control("Defeat effects — one complete JSON object per line", defeat_effects_edit))

	phases_edit = TextEdit.new()
	phases_edit.custom_minimum_size.y = 260
	phases_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	phases_edit.placeholder_text = JSON.stringify(BossCatalog.default_boss_profile().get("phases", [])[0])
	phases_edit.text_changed.connect(refresh_phase_summary)
	inspector.add_child(make_labeled_control("Phases — one complete JSON object per line", phases_edit))
	phase_summary = ItemList.new()
	phase_summary.custom_minimum_size.y = 112
	inspector.add_child(make_labeled_control("Phase and fairness preview", phase_summary))

	var actions := HBoxContainer.new()
	apply_button = make_button("Apply Boss Contract", apply_boss_contract)
	remove_button = make_button("Remove Boss Contract", remove_boss_contract)
	actions.add_child(apply_button)
	actions.add_child(remove_button)
	inspector.add_child(actions)
	set_form_enabled(false)

	status_label = RichTextLabel.new()
	status_label.fit_content = true
	status_label.bbcode_enabled = true
	status_label.custom_minimum_size.y = 72
	status_label.text = "[color=#9aa8b5]Boss & Phase Studio ready.[/color]"
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
	load_primary_object_catalog()
	load_maps()
	rebuild_definitions()
	refresh_boss_list()
	validate_campaign()


func load_primary_object_catalog() -> void:
	var result := ObjectCatalog.load_catalogs(active_campaign_path, active_campaign)
	var files: Array = result.get("files", [])
	if files.is_empty():
		active_object_path = active_campaign_path.get_base_dir().path_join("objects/core.json")
		active_object_catalog = ObjectCatalog.default_catalog()
		return
	var record: Dictionary = files[0]
	active_object_path = str(record.get("path", ""))
	active_object_catalog = (record.get("data", {}) as Dictionary).duplicate(true)


func load_maps() -> void:
	maps.clear()
	var value: Variant = active_campaign.get("map_files", [])
	if typeof(value) != TYPE_ARRAY:
		return
	for relative_value in value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			continue
		var result := Repository.read_json(active_campaign_path.get_base_dir().path_join(relative_path))
		if bool(result.get("ok", false)):
			maps.append(result.get("data", {}))


func rebuild_definitions() -> void:
	var result := ObjectCatalog.load_catalogs(active_campaign_path, active_campaign)
	object_definitions = result.get("definitions", {})


func refresh_boss_list() -> void:
	boss_list.clear()
	var ids: Array[String] = []
	for object_id_value in object_definitions.keys():
		var object_id := str(object_id_value)
		var definition_data := ObjectCatalog.definition(object_definitions, object_id)
		if str(definition_data.get("kind", "")) == "enemy":
			ids.append(object_id)
	ids.sort_custom(func(left: String, right: String) -> bool:
		return str(ObjectCatalog.definition(object_definitions, left).get("display_name", left)).naturalnocasecmp_to(str(ObjectCatalog.definition(object_definitions, right).get("display_name", right))) < 0
	)
	for object_id in ids:
		var definition_data := ObjectCatalog.definition(object_definitions, object_id)
		var prefix := "[BOSS] " if BossCatalog.is_boss(definition_data) else ""
		var item_index := boss_list.item_count
		boss_list.add_item(prefix + str(definition_data.get("display_name", object_id)))
		boss_list.set_item_metadata(item_index, object_id)
	if boss_list.item_count > 0:
		boss_list.select(0)
		on_boss_selected(0)
	else:
		selected_object_id = ""
		set_form_enabled(false)


func on_boss_selected(index: int) -> void:
	if index < 0 or index >= boss_list.item_count:
		return
	selected_object_id = str(boss_list.get_item_metadata(index))
	selected_map = first_map_for_object(selected_object_id)
	populate_map_sources()
	populate_boss_form()


func first_map_for_object(object_id: String) -> Dictionary:
	for map_value in maps:
		if typeof(map_value) != TYPE_DICTIONARY:
			continue
		var map_data: Dictionary = map_value
		for placement_value in map_data.get("object_placements", []):
			if typeof(placement_value) == TYPE_DICTIONARY and str((placement_value as Dictionary).get("object_id", "")) == object_id:
				return map_data
	return {}


func populate_map_sources() -> void:
	arena_zone_selector.clear()
	connection_list.clear()
	if selected_map.is_empty():
		boss_map_label.text = "Not placed on a source map. Arena references cannot be selected until a placement exists."
		return
	boss_map_label.text = "SOURCE MAP  %s" % str(selected_map.get("display_name", selected_map.get("id", "Map"))).to_upper()
	for zone_value in selected_map.get("encounter_zones", []):
		if typeof(zone_value) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_value
		var index := arena_zone_selector.item_count
		arena_zone_selector.add_item(str(zone.get("display_name", zone.get("id", "Encounter"))))
		arena_zone_selector.set_item_metadata(index, str(zone.get("id", "")))
	for connection_value in selected_map.get("connections", []):
		if typeof(connection_value) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = connection_value
		var index := connection_list.item_count
		connection_list.add_item(str(connection.get("id", "connection")).replace("_", " ").capitalize())
		connection_list.set_item_metadata(index, str(connection.get("id", "")))


func populate_boss_form() -> void:
	var definition_data := ObjectCatalog.definition(object_definitions, selected_object_id)
	var enabled := BossCatalog.is_boss(definition_data)
	var boss := BossCatalog.boss_record(definition_data).duplicate(true) if enabled else BossCatalog.default_boss_profile()
	boss_enabled.button_pressed = enabled
	select_option_metadata(arena_zone_selector, str(boss.get("arena_zone_id", "")))
	outcome_key_edit.text = str(boss.get("outcome_state_key", ""))
	intro_edit.text = str(boss.get("intro_message", ""))
	defeat_edit.text = str(boss.get("defeat_message", ""))
	allow_era_shift_check.button_pressed = bool(boss.get("allow_era_shift", true))
	var bounds_value: Variant = boss.get("arena_bounds", {})
	var bounds: Dictionary = bounds_value if typeof(bounds_value) == TYPE_DICTIONARY else {}
	arena_left.value = float(bounds.get("left", 128))
	arena_right.value = float(bounds.get("right", 560))
	arena_top.value = float(bounds.get("top", 112))
	arena_bottom.value = float(bounds.get("bottom", 312))
	var locked := BossCatalog.locked_connections(definition_data) if enabled else PackedStringArray()
	connection_list.deselect_all()
	for index in range(connection_list.item_count):
		if locked.has(str(connection_list.get_item_metadata(index))):
			connection_list.select(index, false)
	defeat_effects_edit.text = format_json_lines(boss.get("defeat_effects", []))
	phases_edit.text = format_json_lines(boss.get("phases", []))
	set_form_enabled(true)
	refresh_phase_summary()


func on_enabled_toggled(enabled: bool) -> void:
	apply_button.text = "Apply Boss Contract" if enabled else "Apply Disabled State"


func apply_boss_contract() -> void:
	if selected_object_id.is_empty():
		return
	var phase_parse := parse_json_lines(phases_edit.text, "phases")
	if not bool(phase_parse.get("ok", false)):
		set_status(format_messages(phase_parse.get("errors", [])), true)
		return
	var effect_parse := parse_json_lines(defeat_effects_edit.text, "defeat effects")
	if not bool(effect_parse.get("ok", false)):
		set_status(format_messages(effect_parse.get("errors", [])), true)
		return
	var arena_id := selected_option_metadata(arena_zone_selector)
	if boss_enabled.button_pressed and arena_id.is_empty():
		set_status("Place the enemy on a map with an encounter zone before enabling its boss contract.", true)
		return
	var objects_value: Variant = active_object_catalog.get("objects", [])
	if typeof(objects_value) != TYPE_ARRAY:
		set_status("Primary object catalog has no objects array.", true)
		return
	var objects: Array = objects_value
	var found := false
	for index in range(objects.size()):
		if typeof(objects[index]) != TYPE_DICTIONARY:
			continue
		var definition_data: Dictionary = objects[index]
		if str(definition_data.get("id", "")) != selected_object_id:
			continue
		if boss_enabled.button_pressed:
			definition_data["boss"] = {
				"enabled": true,
				"arena_zone_id": arena_id,
				"outcome_state_key": outcome_key_edit.text.strip_edges(),
				"intro_message": intro_edit.text.strip_edges(),
				"defeat_message": defeat_edit.text.strip_edges(),
				"lock_connection_ids": selected_connection_ids(),
				"allow_era_shift": allow_era_shift_check.button_pressed,
				"arena_bounds": {
					"left": arena_left.value,
					"right": arena_right.value,
					"top": arena_top.value,
					"bottom": arena_bottom.value
				},
				"defeat_effects": effect_parse.get("entries", []),
				"phases": phase_parse.get("entries", [])
			}
		else:
			definition_data.erase("boss")
		objects[index] = definition_data
		found = true
		break
	if not found:
		set_status("The selected enemy is from a secondary read-only catalog.", true)
		return
	active_object_catalog["objects"] = objects
	if save_object_catalog():
		rebuild_definitions()
		refresh_boss_list()
		select_boss_id(selected_object_id)
		set_status("Updated boss contract for '%s'." % selected_object_id, false)


func remove_boss_contract() -> void:
	boss_enabled.button_pressed = false
	apply_boss_contract()


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
	var report := BossValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		var rollback := Repository.save_json(active_object_path, previous)
		active_object_catalog = previous
		rebuild_definitions()
		rescan_editor_files()
		if not bool(rollback.get("ok", false)):
			set_status("Invalid Boss Studio edit and rollback failed: %s" % format_messages(rollback.get("errors", [])), true)
		else:
			set_status("Invalid Boss Studio edit was rolled back. %s" % format_report(report), true)
		return false
	return true


func refresh_phase_summary() -> void:
	phase_summary.clear()
	var parsed := parse_json_lines(phases_edit.text, "phases")
	if not bool(parsed.get("ok", false)):
		for error in parsed.get("errors", []):
			phase_summary.add_item("ERROR  " + str(error))
		return
	for value in parsed.get("entries", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var phase: Dictionary = value
		var pattern := BossCatalog.phase_pattern(phase)
		var attack_steps := 0
		var pause_steps := 0
		for step_value in pattern:
			if typeof(step_value) == TYPE_DICTIONARY and BossCatalog.pattern_step_type(step_value) == "pause":
				pause_steps += 1
			else:
				attack_steps += 1
		phase_summary.add_item(
			"%s  ≤ %.0f%%  %d attack / %d pause  %d reinforcement(s)" % [
				BossCatalog.phase_name(phase),
				BossCatalog.phase_threshold(phase) * 100.0,
				attack_steps,
				pause_steps,
				BossCatalog.phase_reinforcements(phase).size()
			]
		)
	if phase_summary.item_count == 0:
		phase_summary.add_item("No valid phase records.")


func selected_connection_ids() -> Array:
	var output: Array = []
	for index in range(connection_list.item_count):
		if connection_list.is_selected(index):
			output.append(str(connection_list.get_item_metadata(index)))
	return output


func parse_json_lines(text: String, label: String) -> Dictionary:
	var entries: Array = []
	var errors: Array[String] = []
	for line_index in range(text.split("\n").size()):
		var line := str(text.split("\n")[line_index]).strip_edges()
		if line.is_empty():
			continue
		var parser := JSON.new()
		var parse_error := parser.parse(line)
		if parse_error != OK:
			errors.append("%s line %d is invalid JSON: %s" % [label, line_index + 1, parser.get_error_message()])
			continue
		var data: Variant = parser.data
		if typeof(data) != TYPE_DICTIONARY:
			errors.append("%s line %d must be a JSON object." % [label, line_index + 1])
			continue
		entries.append(data)
	return {"ok": errors.is_empty(), "entries": entries, "errors": errors}


func format_json_lines(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return ""
	var lines := PackedStringArray()
	for entry in value:
		if typeof(entry) == TYPE_DICTIONARY:
			lines.append(JSON.stringify(entry, "", false))
	return "\n".join(lines)


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


func select_boss_id(object_id: String) -> void:
	for index in range(boss_list.item_count):
		if str(boss_list.get_item_metadata(index)) == object_id:
			boss_list.select(index)
			on_boss_selected(index)
			return


func set_form_enabled(enabled: bool) -> void:
	boss_enabled.disabled = not enabled
	arena_zone_selector.disabled = not enabled
	outcome_key_edit.editable = enabled
	intro_edit.editable = enabled
	defeat_edit.editable = enabled
	allow_era_shift_check.disabled = not enabled
	arena_left.editable = enabled
	arena_right.editable = enabled
	arena_top.editable = enabled
	arena_bottom.editable = enabled
	connection_list.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	defeat_effects_edit.editable = enabled
	phases_edit.editable = enabled
	apply_button.disabled = not enabled
	remove_button.disabled = not enabled


func clear_campaign() -> void:
	active_campaign = {}
	active_campaign_path = ""
	active_object_catalog = {}
	active_object_path = ""
	object_definitions = {}
	maps.clear()
	selected_object_id = ""
	selected_map = {}
	boss_list.clear()
	set_form_enabled(false)


func validate_campaign() -> void:
	if active_campaign_path.is_empty():
		return
	var report := BossValidator.validate_campaign_path(active_campaign_path)
	set_status(format_report(report), not bool(report.get("ok", false)))


func validate_all_campaigns() -> void:
	var report := BossValidator.validate_all()
	set_status(format_report(report), not bool(report.get("ok", false)))


func format_report(report: Dictionary) -> String:
	var errors_value: Variant = report.get("errors", [])
	var warnings_value: Variant = report.get("warnings", [])
	var lines := PackedStringArray()
	lines.append(
		"%d boss definition(s), %d placement(s), %d phase(s), %d pattern step(s), %d reinforcement(s), %d warning(s), %d error(s)." % [
			report.get("boss_count", 0),
			report.get("boss_placement_count", 0),
			report.get("boss_phase_count", 0),
			report.get("boss_pattern_step_count", 0),
			report.get("boss_reinforcement_count", 0),
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
