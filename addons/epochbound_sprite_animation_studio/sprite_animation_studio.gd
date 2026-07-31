@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const SpriteAnimationCatalog = preload("res://src/content/sprite_animation_catalog.gd")
const SpriteAnimationValidator = preload("res://src/content/sprite_animation_validator.gd")

var campaign_selector: OptionButton
var profile_selector: OptionButton
var status_label: Label
var summary_label: Label
var atlas_edit: LineEdit
var frame_width: SpinBox
var frame_height: SpinBox
var render_width: SpinBox
var render_height: SpinBox
var pivot_x: SpinBox
var pivot_y: SpinBox
var directions: OptionButton
var fallback_style: OptionButton
var state_rows: Dictionary = {}
var state_frames: Dictionary = {}
var state_fps: Dictionary = {}
var state_loop: Dictionary = {}

var campaigns: Array[Dictionary] = []
var current_campaign_path := ""
var current_campaign: Dictionary = {}
var current_catalog_path := ""
var current_catalog: Dictionary = {}
var profile_ids := PackedStringArray()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_ui()
	refresh_campaigns()


func build_ui() -> void:
	var root_box := VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 8)
	add_child(root_box)
	var header := HBoxContainer.new()
	root_box.add_child(header)
	var title := Label.new()
	title.text = "SPRITE & ANIMATION STUDIO"
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	campaign_selector = OptionButton.new()
	campaign_selector.custom_minimum_size.x = 260
	campaign_selector.item_selected.connect(Callable(self, "_on_campaign_selected"))
	header.add_child(campaign_selector)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(Callable(self, "refresh_campaigns"))
	header.add_child(refresh_button)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(split)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 250
	navigation.add_theme_constant_override("separation", 7)
	split.add_child(navigation)
	navigation.add_child(make_heading("PROFILE"))
	profile_selector = OptionButton.new()
	profile_selector.item_selected.connect(Callable(self, "_on_profile_selected"))
	navigation.add_child(profile_selector)
	var create_button := Button.new()
	create_button.text = "Create Default Catalogue"
	create_button.pressed.connect(Callable(self, "create_default_catalog"))
	navigation.add_child(create_button)
	var validate_button := Button.new()
	validate_button.text = "Validate Campaign"
	validate_button.pressed.connect(Callable(self, "validate_campaign"))
	navigation.add_child(validate_button)
	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.modulate = Color("9ca9b3")
	navigation.add_child(summary_label)
	var help := Label.new()
	help.text = "Atlas rows are state base rows. Four-direction sheets use Down, Left, Right, Up rows from each base. Empty atlas paths use the original procedural fallback."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color("7f8d98")
	navigation.add_child(help)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	scroll.add_child(form)
	form.add_child(make_heading("ATLAS AND FRAME CONTRACT"))
	atlas_edit = add_line(form, "Relative PNG atlas")
	frame_width = add_spin(form, "Frame width", 8, 256, 1)
	frame_height = add_spin(form, "Frame height", 8, 256, 1)
	render_width = add_spin(form, "Render width", 8, 256, 1)
	render_height = add_spin(form, "Render height", 8, 256, 1)
	pivot_x = add_spin(form, "Pivot X", 0, 256, 1)
	pivot_y = add_spin(form, "Pivot Y", 0, 256, 1)
	directions = add_option(form, "Directional rows", ["1", "4", "8"])
	fallback_style = add_option(form, "Procedural fallback", Array(SpriteAnimationCatalog.FALLBACK_STYLES))
	form.add_child(make_heading("ANIMATION STATES"))
	for state in SpriteAnimationCatalog.STATES:
		add_state_row(form, state)
	var save_button := Button.new()
	save_button.text = "Save Animation Profile"
	save_button.pressed.connect(Callable(self, "save_current_profile"))
	form.add_child(save_button)
	status_label = Label.new()
	status_label.text = "Select a campaign."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(status_label)


func make_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color("dfc46f")
	return label


func add_line(parent: VBoxContainer, label_text: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 190
	row.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func add_spin(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 190
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size.x = 150
	row.add_child(spin)
	return spin


func add_option(parent: VBoxContainer, label_text: String, values: Array) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 190
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size.x = 180
	for value in values:
		var text := str(value)
		option.add_item(text.replace("_", " ").capitalize())
		option.set_item_metadata(option.item_count - 1, text)
	row.add_child(option)
	return option


func add_state_row(parent: VBoxContainer, state: String) -> void:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 4)
	parent.add_child(panel)
	panel.add_child(make_heading(state.to_upper()))
	var row := HBoxContainer.new()
	panel.add_child(row)
	var row_spin := make_small_spin("Base row", 0, 256, 1)
	var frames_spin := make_small_spin("Frames", 1, 32, 1)
	var fps_spin := make_small_spin("FPS", 1, 30, 0.5)
	row.add_child(row_spin.get_parent())
	row.add_child(frames_spin.get_parent())
	row.add_child(fps_spin.get_parent())
	var loop_check := CheckBox.new()
	loop_check.text = "Loop"
	row.add_child(loop_check)
	state_rows[state] = row_spin
	state_frames[state] = frames_spin
	state_fps[state] = fps_spin
	state_loop[state] = loop_check


func make_small_spin(label_text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	box.add_child(spin)
	return spin


func refresh_campaigns() -> void:
	campaigns.clear()
	campaign_selector.clear()
	for value in Repository.scan_playable_campaigns():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value as Dictionary
		campaigns.append(entry)
		campaign_selector.add_item("%s  [%s]" % [str(entry.get("title", entry.get("id", "Campaign"))), str(entry.get("source", "built_in")).to_upper()])
	if campaigns.is_empty():
		status_label.text = "No campaigns were discovered."
		return
	campaign_selector.select(0)
	_on_campaign_selected(0)


func _on_campaign_selected(index: int) -> void:
	if index < 0 or index >= campaigns.size():
		return
	load_campaign_path(str(campaigns[index].get("path", "")))


func load_campaign_path(path: String) -> bool:
	current_campaign_path = path
	var result := Repository.read_json(path)
	if not bool(result.get("ok", false)):
		status_label.text = "Could not read the selected campaign."
		return false
	current_campaign = result.get("data", {})
	load_catalog()
	return not current_catalog.is_empty()


func load_catalog() -> void:
	current_catalog_path = SpriteAnimationCatalog.primary_catalog_path(current_campaign_path, current_campaign)
	var result := Repository.read_json(current_catalog_path)
	if not bool(result.get("ok", false)):
		current_catalog = {}
		profile_selector.clear()
		profile_ids.clear()
		summary_label.text = "No sprite animation catalogue exists yet."
		status_label.text = "Create a default catalogue or add animation_files to the campaign."
		return
	current_catalog = result.get("data", {})
	refresh_profiles()


func refresh_profiles() -> void:
	profile_selector.clear()
	profile_ids.clear()
	var profiles_value: Variant = current_catalog.get("profiles", [])
	if typeof(profiles_value) == TYPE_ARRAY:
		for profile_value in profiles_value as Array:
			if typeof(profile_value) != TYPE_DICTIONARY:
				continue
			var profile: Dictionary = profile_value as Dictionary
			var profile_id := str(profile.get("id", ""))
			if profile_id.is_empty():
				continue
			profile_ids.append(profile_id)
			profile_selector.add_item(str(profile.get("display_name", profile_id)))
	var bindings_value: Variant = current_catalog.get("bindings", [])
	var binding_count := (bindings_value as Array).size() if typeof(bindings_value) == TYPE_ARRAY else 0
	summary_label.text = "%d animation profile(s)\n%d target binding(s)" % [profile_ids.size(), binding_count]
	if profile_ids.is_empty():
		status_label.text = "The catalogue has no animation profiles."
		return
	profile_selector.select(0)
	_on_profile_selected(0)
	status_label.text = "Loaded %d animation profile(s)." % profile_ids.size()


func _on_profile_selected(index: int) -> void:
	if index < 0 or index >= profile_ids.size():
		return
	var profile := profile_by_id(profile_ids[index])
	if not profile.is_empty():
		load_profile_into_form(profile)


func profile_by_id(profile_id: String) -> Dictionary:
	var profiles_value: Variant = current_catalog.get("profiles", [])
	if typeof(profiles_value) != TYPE_ARRAY:
		return {}
	for profile_value in profiles_value as Array:
		if typeof(profile_value) == TYPE_DICTIONARY and str((profile_value as Dictionary).get("id", "")) == profile_id:
			return profile_value as Dictionary
	return {}


func load_profile_into_form(profile: Dictionary) -> void:
	atlas_edit.text = str(profile.get("atlas", ""))
	var frame := SpriteAnimationCatalog.vector2i_value(profile, "frame_size", Vector2i(32, 32))
	var render := SpriteAnimationCatalog.vector2i_value(profile, "render_size", frame)
	var pivot := SpriteAnimationCatalog.vector2i_value(profile, "pivot", Vector2i(frame.x / 2, frame.y - 4))
	frame_width.value = frame.x
	frame_height.value = frame.y
	render_width.value = render.x
	render_height.value = render.y
	pivot_x.value = pivot.x
	pivot_y.value = pivot.y
	select_metadata(directions, str(profile.get("directions", 4)))
	select_metadata(fallback_style, str(profile.get("fallback_style", "prop")))
	for state in SpriteAnimationCatalog.STATES:
		var record := SpriteAnimationCatalog.animation(profile, state)
		(state_rows[state] as SpinBox).value = int(record.get("row", 0))
		(state_frames[state] as SpinBox).value = int(record.get("frames", 1))
		(state_fps[state] as SpinBox).value = float(record.get("fps", 1.0))
		(state_loop[state] as CheckBox).button_pressed = bool(record.get("loop", state in ["idle", "walk"]))


func save_current_profile() -> void:
	if current_catalog.is_empty() or profile_selector.selected < 0 or profile_selector.selected >= profile_ids.size():
		status_label.text = "Select a valid profile first."
		return
	var profile_id := profile_ids[profile_selector.selected]
	var profile := profile_by_id(profile_id)
	if profile.is_empty():
		status_label.text = "The selected profile no longer exists."
		return
	var atlas := atlas_edit.text.strip_edges().replace("\\", "/")
	if not SpriteAnimationCatalog.safe_relative_atlas_path(atlas):
		status_label.text = "Atlas must be empty or a safe relative PNG path."
		return
	var snapshot := read_text(current_catalog_path)
	profile["atlas"] = atlas
	profile["frame_size"] = {"x": int(frame_width.value), "y": int(frame_height.value)}
	profile["render_size"] = {"x": int(render_width.value), "y": int(render_height.value)}
	profile["pivot"] = {"x": int(pivot_x.value), "y": int(pivot_y.value)}
	profile["directions"] = int(str(directions.get_item_metadata(directions.selected)))
	profile["fallback_style"] = str(fallback_style.get_item_metadata(fallback_style.selected))
	var animations: Dictionary = {}
	for state in SpriteAnimationCatalog.STATES:
		animations[state] = {
			"row": int((state_rows[state] as SpinBox).value),
			"frames": int((state_frames[state] as SpinBox).value),
			"fps": (state_fps[state] as SpinBox).value,
			"loop": (state_loop[state] as CheckBox).button_pressed
		}
	profile["animations"] = animations
	var save_result := Repository.save_json(current_catalog_path, current_catalog)
	if not bool(save_result.get("ok", false)):
		status_label.text = "Could not write the animation catalogue."
		return
	var validation := SpriteAnimationValidator.validate_campaign_path(current_campaign_path)
	if not bool(validation.get("ok", false)):
		write_text(current_catalog_path, snapshot)
		load_catalog()
		status_label.text = "Animation save rolled back: %s" % join_messages(validation.get("errors", []))
		return
	status_label.text = "Saved %s with %d warning(s)." % [profile_id, message_count(validation.get("warnings", []))]


func create_default_catalog() -> void:
	if current_campaign_path.is_empty():
		return
	var campaign_snapshot := read_text(current_campaign_path)
	var catalogue_path := current_campaign_path.get_base_dir().path_join("animation").path_join("core.json")
	var catalogue_existed := FileAccess.file_exists(catalogue_path)
	var catalogue_snapshot := read_text(catalogue_path) if catalogue_existed else ""
	var save_result := Repository.save_json(catalogue_path, SpriteAnimationCatalog.default_catalog())
	if not bool(save_result.get("ok", false)):
		status_label.text = "Could not create the default animation catalogue."
		return
	current_campaign["animation_files"] = ["animation/core.json"]
	var campaign_save := Repository.save_json(current_campaign_path, current_campaign)
	if not bool(campaign_save.get("ok", false)):
		restore_catalogue_creation(campaign_snapshot, catalogue_path, catalogue_existed, catalogue_snapshot)
		status_label.text = "Could not bind the animation catalogue to the campaign."
		return
	var validation := SpriteAnimationValidator.validate_campaign_path(current_campaign_path)
	if not bool(validation.get("ok", false)):
		restore_catalogue_creation(campaign_snapshot, catalogue_path, catalogue_existed, catalogue_snapshot)
		status_label.text = "Default animation catalogue rolled back: %s" % join_messages(validation.get("errors", []))
		return
	load_catalog()
	status_label.text = "Created and validated animation/core.json."


func restore_catalogue_creation(campaign_snapshot: String, catalogue_path: String, existed: bool, snapshot: String) -> void:
	write_text(current_campaign_path, campaign_snapshot)
	if existed:
		write_text(catalogue_path, snapshot)
	else:
		DirAccess.remove_absolute(catalogue_path)


func validate_campaign() -> void:
	if current_campaign_path.is_empty():
		return
	var validation := SpriteAnimationValidator.validate_campaign_path(current_campaign_path)
	if bool(validation.get("ok", false)):
		status_label.text = "Animation validation passed with %d profile(s), %d binding(s), and %d warning(s)." % [int(validation.get("animation_profile_count", 0)), int(validation.get("animation_binding_count", 0)), message_count(validation.get("warnings", []))]
	else:
		status_label.text = "Animation validation failed: %s" % join_messages(validation.get("errors", []))


func select_metadata(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func write_text(path: String, value: String) -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.flush()
	return true


func join_messages(value: Variant) -> String:
	var messages := PackedStringArray()
	if typeof(value) == TYPE_ARRAY:
		for message in value as Array:
			messages.append(str(message))
	return " | ".join(messages)


func message_count(value: Variant) -> int:
	return (value as Array).size() if typeof(value) == TYPE_ARRAY else 0


func profile_count() -> int:
	return profile_ids.size()
