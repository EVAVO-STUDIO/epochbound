@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const CinematicCatalog = preload("res://src/content/cinematic_catalog.gd")
const CinematicValidator = preload("res://src/content/cinematic_validator.gd")

var campaigns: Array = []
var active_campaign: Dictionary = {}
var active_campaign_path := ""
var active_catalog: Dictionary = {}
var active_catalog_path := ""
var definitions: Dictionary = {}
var selected_cinematic_id := ""

var campaign_selector: OptionButton
var cinematic_list: ItemList
var new_id: LineEdit
var id_edit: LineEdit
var name_edit: LineEdit
var map_selector: OptionButton
var era_edit: LineEdit
var completion_key_edit: LineEdit
var skippable_check: CheckBox
var letterbox_check: CheckBox
var trigger_once_check: CheckBox
var steps_edit: TextEdit
var completion_effects_edit: TextEdit
var skip_effects_edit: TextEdit
var timeline_list: ItemList
var apply_button: Button
var delete_button: Button
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
	title.text = "Epochbound Cinematic & Timeline Studio"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(make_heading("CAMPAIGN"))
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 245
	campaign_selector.item_selected.connect(on_campaign_selected)
	header.add_child(campaign_selector)
	header.add_child(make_button("Validate All", validate_all_campaigns))
	header.add_child(make_button("Open Folder", open_campaign_folder))

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 235
	left.add_theme_constant_override("separation", 5)
	split.add_child(left)
	left.add_child(make_heading("CINEMATICS"))
	cinematic_list = ItemList.new()
	cinematic_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cinematic_list.item_selected.connect(on_cinematic_selected)
	left.add_child(cinematic_list)
	new_id = LineEdit.new()
	new_id.placeholder_text = "new_cinematic_id"
	left.add_child(new_id)
	left.add_child(make_button("Add Cinematic", add_cinematic))
	left.add_child(make_button("Duplicate Selected", duplicate_cinematic))

	var center_scroll := ScrollContainer.new()
	center_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_scroll.size_flags_stretch_ratio = 2.3
	split.add_child(center_scroll)
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 520
	form.add_theme_constant_override("separation", 5)
	center_scroll.add_child(form)
	form.add_child(make_heading("SEQUENCE CONTRACT"))
	id_edit = LineEdit.new()
	id_edit.editable = false
	form.add_child(make_labeled("Stable ID", id_edit))
	name_edit = LineEdit.new()
	form.add_child(make_labeled("Display name", name_edit))
	map_selector = OptionButton.new()
	form.add_child(make_labeled("Authored map", map_selector))
	era_edit = LineEdit.new()
	era_edit.placeholder_text = "verdant, ashen  (blank = all eras)"
	form.add_child(make_labeled("Available eras", era_edit))
	completion_key_edit = LineEdit.new()
	completion_key_edit.placeholder_text = "cinematic:sequence_id"
	form.add_child(make_labeled("Completion state key", completion_key_edit))
	var flags := HBoxContainer.new()
	skippable_check = CheckBox.new()
	skippable_check.text = "Skippable"
	letterbox_check = CheckBox.new()
	letterbox_check.text = "Letterbox"
	trigger_once_check = CheckBox.new()
	trigger_once_check.text = "Trigger once"
	flags.add_child(skippable_check)
	flags.add_child(letterbox_check)
	flags.add_child(trigger_once_check)
	form.add_child(flags)
	form.add_child(make_heading("TIMELINE STEPS — ONE JSON OBJECT PER LINE"))
	steps_edit = TextEdit.new()
	steps_edit.custom_minimum_size.y = 260
	steps_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	steps_edit.text_changed.connect(refresh_timeline_preview)
	form.add_child(steps_edit)
	form.add_child(make_heading("COMPLETION EFFECTS — ONE JSON OBJECT PER LINE"))
	completion_effects_edit = TextEdit.new()
	completion_effects_edit.custom_minimum_size.y = 120
	form.add_child(completion_effects_edit)
	form.add_child(make_heading("SKIP-ONLY EFFECTS — ONE JSON OBJECT PER LINE"))
	skip_effects_edit = TextEdit.new()
	skip_effects_edit.custom_minimum_size.y = 90
	form.add_child(skip_effects_edit)
	var actions := HBoxContainer.new()
	apply_button = make_button("Apply Cinematic", apply_cinematic)
	delete_button = make_button("Delete Cinematic", delete_cinematic)
	actions.add_child(apply_button)
	actions.add_child(delete_button)
	form.add_child(actions)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 285
	right.add_theme_constant_override("separation", 5)
	split.add_child(right)
	right.add_child(make_heading("TIMELINE PREVIEW"))
	timeline_list = ItemList.new()
	timeline_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(timeline_list)
	var help := RichTextLabel.new()
	help.bbcode_enabled = true
	help.fit_content = true
	help.text = "[color=#9da9b3]Supported steps: wait, dialogue, camera, move_actor, set_era, fade, effects and checkpoint. Skipping always applies completion effects and the durable completion key.[/color]"
	right.add_child(help)

	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	status_label.custom_minimum_size.y = 68
	status_label.text = "[color=#9aa8b5]Cinematic Studio ready.[/color]"
	root.add_child(status_label)
	set_form_enabled(false)


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


func make_labeled(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.modulate = Color("aeb8c2")
	box.add_child(label)
	box.add_child(control)
	return box


func refresh_campaigns(preferred_id: String = "") -> void:
	campaigns = Repository.scan_campaigns()
	campaign_selector.clear()
	var selected := 0
	for index in range(campaigns.size()):
		var entry: Dictionary = campaigns[index]
		campaign_selector.add_item(str(entry.get("title", entry.get("id", "Campaign"))))
		campaign_selector.set_item_metadata(index, str(entry.get("path", "")))
		if str(entry.get("id", "")) == preferred_id:
			selected = index
	if campaigns.is_empty():
		clear_campaign()
		set_status("No source campaigns found under res://campaigns.", true)
		return
	campaign_selector.select(selected)
	on_campaign_selected(selected)


func on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaign_selector.item_count:
		return
	active_campaign_path = str(campaign_selector.get_item_metadata(index))
	var result := Repository.read_json(active_campaign_path)
	if not bool(result.get("ok", false)):
		set_status(format_messages(result.get("errors", [])), true)
		return
	active_campaign = result.get("data", {})
	load_catalog()
	populate_maps()
	refresh_cinematic_list()


func load_catalog() -> void:
	var result := CinematicCatalog.load_catalogs(active_campaign_path, active_campaign)
	definitions = result.get("definitions", {})
	var files: Array = result.get("files", [])
	if files.is_empty():
		active_catalog_path = CinematicCatalog.primary_catalog_path(active_campaign_path, active_campaign)
		active_catalog = CinematicCatalog.default_catalog()
		return
	var record: Dictionary = files[0]
	active_catalog_path = str(record.get("path", ""))
	active_catalog = record.get("data", {})


func populate_maps() -> void:
	map_selector.clear()
	for relative_value in active_campaign.get("map_files", []):
		var path := active_campaign_path.get_base_dir().path_join(str(relative_value))
		var result := Repository.read_json(path)
		if not bool(result.get("ok", false)):
			continue
		var data: Dictionary = result.get("data", {})
		var index := map_selector.item_count
		map_selector.add_item(str(data.get("display_name", data.get("id", "Map"))))
		map_selector.set_item_metadata(index, str(data.get("id", "")))


func refresh_cinematic_list(preferred_id: String = "") -> void:
	cinematic_list.clear()
	var ids := PackedStringArray()
	for cinematic_id in definitions.keys():
		ids.append(str(cinematic_id))
	ids.sort()
	for cinematic_id in ids:
		var sequence := CinematicCatalog.cinematic(definitions, cinematic_id)
		var index := cinematic_list.item_count
		cinematic_list.add_item(CinematicCatalog.display_name(sequence))
		cinematic_list.set_item_metadata(index, cinematic_id)
	if ids.is_empty():
		select_cinematic_id("")
		return
	select_cinematic_id(preferred_id if definitions.has(preferred_id) else ids[0])


func on_cinematic_selected(index: int) -> void:
	if index >= 0 and index < cinematic_list.item_count:
		select_cinematic_id(str(cinematic_list.get_item_metadata(index)))


func select_cinematic_id(cinematic_id: String) -> void:
	selected_cinematic_id = cinematic_id
	var sequence := CinematicCatalog.cinematic(definitions, cinematic_id)
	set_form_enabled(not sequence.is_empty())
	if sequence.is_empty():
		clear_form()
		return
	id_edit.text = cinematic_id
	name_edit.text = CinematicCatalog.display_name(sequence)
	select_map(CinematicCatalog.map_id(sequence))
	era_edit.text = ", ".join(PackedStringArray(sequence.get("available_eras", [])))
	completion_key_edit.text = CinematicCatalog.completion_state_key(sequence)
	skippable_check.button_pressed = CinematicCatalog.is_skippable(sequence)
	letterbox_check.button_pressed = CinematicCatalog.is_letterboxed(sequence)
	trigger_once_check.button_pressed = CinematicCatalog.trigger_once(sequence)
	steps_edit.text = json_lines(CinematicCatalog.steps(sequence))
	completion_effects_edit.text = json_lines(CinematicCatalog.effects(sequence, "completion_effects"))
	skip_effects_edit.text = json_lines(CinematicCatalog.effects(sequence, "skip_effects"))
	refresh_timeline_preview()
	for index in range(cinematic_list.item_count):
		if str(cinematic_list.get_item_metadata(index)) == cinematic_id:
			cinematic_list.select(index)
			break


func select_map(map_id: String) -> void:
	if map_selector.item_count == 0:
		return
	var selected := 0
	for index in range(map_selector.item_count):
		if str(map_selector.get_item_metadata(index)) == map_id:
			selected = index
			break
	map_selector.select(selected)


func add_cinematic() -> void:
	var cinematic_id := Repository.normalise_id(new_id.text)
	if cinematic_id.is_empty() or definitions.has(cinematic_id):
		set_status("Provide a unique normalised cinematic ID.", true)
		return
	var sequences: Array = active_catalog.get("cinematics", [])
	var sequence := CinematicCatalog.default_sequence(cinematic_id, cinematic_id.replace("_", " ").capitalize())
	if map_selector.item_count > 0:
		sequence["map_id"] = str(map_selector.get_item_metadata(map_selector.selected))
	sequences.append(sequence)
	active_catalog["cinematics"] = sequences
	if save_catalog_transactional():
		new_id.text = ""
		load_catalog()
		refresh_cinematic_list(cinematic_id)


func duplicate_cinematic() -> void:
	var source := CinematicCatalog.cinematic(definitions, selected_cinematic_id)
	if source.is_empty():
		return
	var cinematic_id := Repository.normalise_id(new_id.text)
	if cinematic_id.is_empty() or definitions.has(cinematic_id):
		set_status("Enter a unique new ID before duplicating.", true)
		return
	var copy := source.duplicate(true)
	copy["id"] = cinematic_id
	copy["display_name"] = cinematic_id.replace("_", " ").capitalize()
	copy["completion_state_key"] = "cinematic:%s" % cinematic_id
	var sequences: Array = active_catalog.get("cinematics", [])
	sequences.append(copy)
	active_catalog["cinematics"] = sequences
	if save_catalog_transactional():
		load_catalog()
		refresh_cinematic_list(cinematic_id)


func apply_cinematic() -> void:
	if selected_cinematic_id.is_empty():
		return
	var step_result := parse_json_lines(steps_edit.text, "timeline steps")
	var completion_result := parse_json_lines(completion_effects_edit.text, "completion effects")
	var skip_result := parse_json_lines(skip_effects_edit.text, "skip effects")
	for result in [step_result, completion_result, skip_result]:
		if not bool(result.get("ok", false)):
			set_status(format_messages(result.get("errors", [])), true)
			return
	var sequences: Array = active_catalog.get("cinematics", [])
	for index in range(sequences.size()):
		if typeof(sequences[index]) != TYPE_DICTIONARY:
			continue
		var sequence: Dictionary = sequences[index]
		if str(sequence.get("id", "")) != selected_cinematic_id:
			continue
		sequence["display_name"] = name_edit.text.strip_edges()
		sequence["map_id"] = str(map_selector.get_item_metadata(map_selector.selected)) if map_selector.item_count > 0 else ""
		sequence["available_eras"] = parse_csv_ids(era_edit.text)
		sequence["completion_state_key"] = completion_key_edit.text.strip_edges()
		sequence["skippable"] = skippable_check.button_pressed
		sequence["letterbox"] = letterbox_check.button_pressed
		sequence["trigger_once"] = trigger_once_check.button_pressed
		sequence["steps"] = step_result.get("entries", [])
		sequence["completion_effects"] = completion_result.get("entries", [])
		sequence["skip_effects"] = skip_result.get("entries", [])
		sequences[index] = sequence
		break
	active_catalog["cinematics"] = sequences
	if save_catalog_transactional():
		load_catalog()
		refresh_cinematic_list(selected_cinematic_id)


func delete_cinematic() -> void:
	if selected_cinematic_id.is_empty():
		return
	var sequences: Array = active_catalog.get("cinematics", [])
	for index in range(sequences.size() - 1, -1, -1):
		if typeof(sequences[index]) == TYPE_DICTIONARY and str((sequences[index] as Dictionary).get("id", "")) == selected_cinematic_id:
			sequences.remove_at(index)
	active_catalog["cinematics"] = sequences
	if save_catalog_transactional():
		load_catalog()
		refresh_cinematic_list()


func save_catalog_transactional() -> bool:
	var previous_result := Repository.read_json(active_catalog_path)
	var previous: Dictionary = previous_result.get("data", {}) if bool(previous_result.get("ok", false)) else {}
	var save_result := Repository.save_json(active_catalog_path, active_catalog)
	if not bool(save_result.get("ok", false)):
		set_status(format_messages(save_result.get("errors", [])), true)
		return false
	var report := CinematicValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		if not previous.is_empty():
			Repository.save_json(active_catalog_path, previous)
			active_catalog = previous
		set_status("Invalid cinematic edit was rolled back. %s" % format_report(report), true)
		return false
	rescan_editor_files()
	set_status(format_report(report), false)
	return true


func refresh_timeline_preview() -> void:
	if timeline_list == null:
		return
	timeline_list.clear()
	var result := parse_json_lines(steps_edit.text, "timeline steps")
	if not bool(result.get("ok", false)):
		timeline_list.add_item("INVALID TIMELINE SOURCE")
		return
	for index in range((result.get("entries", []) as Array).size()):
		var step: Dictionary = (result.get("entries", []) as Array)[index]
		var label := "%02d  %-12s  %s" % [index + 1, str(step.get("type", "wait")).to_upper(), str(step.get("id", "step"))]
		if step.has("duration"):
			label += "  %.2fs" % float(step.get("duration", 0.0))
		timeline_list.add_item(label)


func parse_json_lines(source: String, label: String) -> Dictionary:
	var entries: Array = []
	var errors: Array[String] = []
	var line_number := 0
	for raw_line in source.split("\n"):
		line_number += 1
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s line %d must be one JSON object." % [label, line_number])
		else:
			entries.append(parsed)
	return {"ok": errors.is_empty(), "entries": entries, "errors": errors}


func parse_csv_ids(source: String) -> Array:
	var output: Array = []
	for value in source.split(","):
		var identifier := value.strip_edges()
		if not identifier.is_empty() and not output.has(identifier):
			output.append(identifier)
	return output


func json_lines(entries: Array) -> String:
	var lines := PackedStringArray()
	for entry in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			lines.append(JSON.stringify(entry))
	return "\n".join(lines)


func set_form_enabled(enabled: bool) -> void:
	for control in [name_edit, era_edit, completion_key_edit, steps_edit, completion_effects_edit, skip_effects_edit]:
		if control is LineEdit:
			(control as LineEdit).editable = enabled
		elif control is TextEdit:
			(control as TextEdit).editable = enabled
	map_selector.disabled = not enabled
	skippable_check.disabled = not enabled
	letterbox_check.disabled = not enabled
	trigger_once_check.disabled = not enabled
	apply_button.disabled = not enabled
	delete_button.disabled = not enabled


func clear_form() -> void:
	id_edit.text = ""
	name_edit.text = ""
	era_edit.text = ""
	completion_key_edit.text = ""
	steps_edit.text = ""
	completion_effects_edit.text = ""
	skip_effects_edit.text = ""
	timeline_list.clear()


func clear_campaign() -> void:
	active_campaign = {}
	active_campaign_path = ""
	active_catalog = {}
	active_catalog_path = ""
	definitions = {}
	cinematic_list.clear()
	map_selector.clear()
	select_cinematic_id("")


func validate_all_campaigns() -> void:
	var report := CinematicValidator.validate_all()
	set_status(format_report(report), not bool(report.get("ok", false)))


func format_report(report: Dictionary) -> String:
	var errors_value: Variant = report.get("errors", [])
	var warnings_value: Variant = report.get("warnings", [])
	var lines := PackedStringArray()
	lines.append("%d cinematic(s), %d step(s), %d trigger(s), %d warning(s), %d error(s)." % [
		report.get("cinematic_count", 0),
		report.get("cinematic_step_count", 0),
		report.get("cinematic_trigger_count", 0),
		warnings_value.size() if typeof(warnings_value) == TYPE_ARRAY else 0,
		errors_value.size() if typeof(errors_value) == TYPE_ARRAY else 0
	])
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
	var path := ProjectSettings.globalize_path(active_campaign_path.get_base_dir() if not active_campaign_path.is_empty() else Repository.DEFAULT_ROOT)
	OS.shell_open(path)
