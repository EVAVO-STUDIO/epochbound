@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const PresentationCatalog = preload("res://src/content/presentation_catalog.gd")
const PresentationValidator = preload("res://src/content/presentation_validator.gd")

const PALETTE_KEYS := [
	"ink", "shadow", "midtone", "light", "accent", "danger",
	"ui_fill", "ui_frame", "ui_text"
]
const ATMOSPHERE_KINDS := ["none", "motes", "pollen", "fireflies", "dust", "embers", "cinders"]

var campaign_selector: OptionButton
var profile_selector: OptionButton
var status_label: Label
var binding_label: Label
var palette_buttons: Dictionary = {}
var palette_value_labels: Dictionary = {}
var follow_strength: SpinBox
var deadzone: SpinBox
var look_ahead: SpinBox
var maximum_shake: SpinBox
var atmosphere_kind: OptionButton
var atmosphere_density: SpinBox
var atmosphere_speed: SpinBox
var atmosphere_opacity: SpinBox
var scanline_alpha: SpinBox
var vignette_alpha: SpinBox
var dither_alpha: SpinBox
var movement_bob: SpinBox
var shadow_scale: SpinBox
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
	title.text = "PRESENTATION & FEEL STUDIO"
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
	navigation.custom_minimum_size.x = 240
	split.add_child(navigation)
	var profile_heading := Label.new()
	profile_heading.text = "PROFILE"
	navigation.add_child(profile_heading)
	profile_selector = OptionButton.new()
	profile_selector.item_selected.connect(Callable(self, "_on_profile_selected"))
	navigation.add_child(profile_selector)
	var create_button := Button.new()
	create_button.text = "Create Default Catalog"
	create_button.pressed.connect(Callable(self, "create_default_catalog"))
	navigation.add_child(create_button)
	binding_label = Label.new()
	binding_label.text = "No bindings loaded."
	binding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	navigation.add_child(binding_label)
	var validate_button := Button.new()
	validate_button.text = "Validate Campaign"
	validate_button.pressed.connect(Callable(self, "validate_campaign"))
	navigation.add_child(validate_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	scroll.add_child(form)

	var palette_heading := Label.new()
	palette_heading.text = "PALETTE"
	palette_heading.add_theme_font_size_override("font_size", 15)
	form.add_child(palette_heading)
	var palette_grid := GridContainer.new()
	palette_grid.columns = 3
	palette_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(palette_grid)
	for key_value in PALETTE_KEYS:
		var key := str(key_value)
		var label := Label.new()
		label.text = key.replace("_", " ").capitalize()
		palette_grid.add_child(label)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(120, 26)
		palette_grid.add_child(picker)
		var value_label := Label.new()
		value_label.text = "#000000"
		palette_grid.add_child(value_label)
		picker.color_changed.connect(Callable(self, "_on_palette_color_changed").bind(value_label))
		palette_buttons[key] = picker
		palette_value_labels[key] = value_label

	add_section_heading(form, "CAMERA FEEL")
	follow_strength = add_spin(form, "Follow strength", 1.0, 30.0, 0.1)
	deadzone = add_spin(form, "Deadzone", 0.0, 80.0, 1.0)
	look_ahead = add_spin(form, "Look ahead", 0.0, 80.0, 1.0)
	maximum_shake = add_spin(form, "Maximum shake", 0.0, 20.0, 0.5)

	add_section_heading(form, "ATMOSPHERE")
	var atmosphere_row := HBoxContainer.new()
	form.add_child(atmosphere_row)
	var atmosphere_label := Label.new()
	atmosphere_label.text = "Kind"
	atmosphere_label.custom_minimum_size.x = 180
	atmosphere_row.add_child(atmosphere_label)
	atmosphere_kind = OptionButton.new()
	for kind_value in ATMOSPHERE_KINDS:
		var kind := str(kind_value)
		atmosphere_kind.add_item(kind.capitalize())
		atmosphere_kind.set_item_metadata(atmosphere_kind.item_count - 1, kind)
	atmosphere_row.add_child(atmosphere_kind)
	atmosphere_density = add_spin(form, "Particle density", 0.0, 128.0, 1.0)
	atmosphere_speed = add_spin(form, "Particle speed", 0.0, 80.0, 0.5)
	atmosphere_opacity = add_spin(form, "Particle opacity", 0.0, 1.0, 0.01)

	add_section_heading(form, "SCREEN TEXTURE")
	scanline_alpha = add_spin(form, "Scanline alpha", 0.0, 0.25, 0.005)
	vignette_alpha = add_spin(form, "Vignette alpha", 0.0, 0.8, 0.01)
	dither_alpha = add_spin(form, "Dither alpha", 0.0, 0.25, 0.005)

	add_section_heading(form, "ACTOR MOTION")
	movement_bob = add_spin(form, "Movement bob", 0.0, 6.0, 0.1)
	shadow_scale = add_spin(form, "Shadow scale", 0.5, 2.0, 0.05)
	var save_button := Button.new()
	save_button.text = "Save Presentation Profile"
	save_button.pressed.connect(Callable(self, "save_current_profile"))
	form.add_child(save_button)

	status_label = Label.new()
	status_label.text = "Select a campaign."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(status_label)


func _on_palette_color_changed(color: Color, value_label: Label) -> void:
	if is_instance_valid(value_label):
		value_label.text = "#" + color.to_html(false)


func add_section_heading(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)


func add_spin(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 180
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size.x = 130
	row.add_child(spin)
	return spin


func refresh_campaigns() -> void:
	campaigns.clear()
	campaign_selector.clear()
	for value in Repository.scan_playable_campaigns():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
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
	var entry: Dictionary = campaigns[index]
	current_campaign_path = str(entry.get("path", ""))
	var result: Dictionary = Repository.read_json(current_campaign_path)
	if not bool(result.get("ok", false)):
		status_label.text = "Could not read the selected campaign."
		return
	current_campaign = result.get("data", {})
	load_catalog()


func load_catalog() -> void:
	current_catalog_path = PresentationCatalog.primary_catalog_path(current_campaign_path, current_campaign)
	var result: Dictionary = Repository.read_json(current_catalog_path)
	if not bool(result.get("ok", false)):
		current_catalog = {}
		profile_selector.clear()
		profile_ids.clear()
		binding_label.text = "No presentation catalog exists yet."
		status_label.text = "Create a default catalog or add presentation_files to the campaign."
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
			var profile_data: Dictionary = profile_value
			var profile_id := str(profile_data.get("id", ""))
			if profile_id.is_empty():
				continue
			profile_ids.append(profile_id)
			profile_selector.add_item(str(profile_data.get("display_name", profile_id)))
	var bindings_value: Variant = current_catalog.get("bindings", [])
	var binding_count := (bindings_value as Array).size() if typeof(bindings_value) == TYPE_ARRAY else 0
	binding_label.text = "%d map/era binding(s)\nProfiles are resolved most-specific first." % binding_count
	if profile_ids.is_empty():
		status_label.text = "The catalog has no presentation profiles."
		return
	profile_selector.select(0)
	_on_profile_selected(0)
	status_label.text = "Loaded %d presentation profile(s)." % profile_ids.size()


func _on_profile_selected(index: int) -> void:
	if index < 0 or index >= profile_ids.size():
		return
	var profile_data: Dictionary = profile_by_id(profile_ids[index])
	if profile_data.is_empty():
		return
	load_profile_into_form(profile_data)


func profile_by_id(profile_id: String) -> Dictionary:
	var profiles_value: Variant = current_catalog.get("profiles", [])
	if typeof(profiles_value) != TYPE_ARRAY:
		return {}
	for profile_value in profiles_value as Array:
		if typeof(profile_value) == TYPE_DICTIONARY and str((profile_value as Dictionary).get("id", "")) == profile_id:
			return profile_value as Dictionary
	return {}


func load_profile_into_form(profile_data: Dictionary) -> void:
	var palette_value: Variant = profile_data.get("palette", {})
	var palette: Dictionary = palette_value as Dictionary if typeof(palette_value) == TYPE_DICTIONARY else {}
	for key_value in PALETTE_KEYS:
		var key := str(key_value)
		var picker := palette_buttons.get(key) as ColorPickerButton
		var value_label := palette_value_labels.get(key) as Label
		if picker == null:
			continue
		picker.color = Color.from_string(str(palette.get(key, "000000")), Color.BLACK)
		if value_label != null:
			value_label.text = "#" + picker.color.to_html(false)
	follow_strength.value = PresentationCatalog.number(profile_data, "camera", "follow_strength", 8.0)
	deadzone.value = PresentationCatalog.number(profile_data, "camera", "deadzone", 20.0)
	look_ahead.value = PresentationCatalog.number(profile_data, "camera", "look_ahead", 18.0)
	maximum_shake.value = PresentationCatalog.number(profile_data, "camera", "maximum_shake", 5.0)
	var kind := PresentationCatalog.text(profile_data, "atmosphere", "kind", "motes")
	for index in range(atmosphere_kind.item_count):
		if str(atmosphere_kind.get_item_metadata(index)) == kind:
			atmosphere_kind.select(index)
			break
	atmosphere_density.value = PresentationCatalog.integer(profile_data, "atmosphere", "density", 18)
	atmosphere_speed.value = PresentationCatalog.number(profile_data, "atmosphere", "speed", 8.0)
	atmosphere_opacity.value = PresentationCatalog.number(profile_data, "atmosphere", "opacity", 0.24)
	scanline_alpha.value = PresentationCatalog.number(profile_data, "screen", "scanline_alpha", 0.035)
	vignette_alpha.value = PresentationCatalog.number(profile_data, "screen", "vignette_alpha", 0.24)
	dither_alpha.value = PresentationCatalog.number(profile_data, "screen", "dither_alpha", 0.07)
	movement_bob.value = PresentationCatalog.number(profile_data, "actors", "movement_bob", 1.6)
	shadow_scale.value = PresentationCatalog.number(profile_data, "actors", "shadow_scale", 1.0)


func save_current_profile() -> void:
	if current_catalog.is_empty() or profile_selector.selected < 0 or profile_selector.selected >= profile_ids.size():
		status_label.text = "Select a valid profile first."
		return
	var profile_id := profile_ids[profile_selector.selected]
	var profile_data: Dictionary = profile_by_id(profile_id)
	if profile_data.is_empty():
		status_label.text = "The selected profile no longer exists."
		return
	var snapshot := read_text(current_catalog_path)
	var palette: Dictionary = {}
	for key_value in PALETTE_KEYS:
		var key := str(key_value)
		var picker := palette_buttons.get(key) as ColorPickerButton
		if picker != null:
			palette[key] = picker.color.to_html(false)
	profile_data["palette"] = palette
	profile_data["camera"] = {
		"follow_strength": follow_strength.value,
		"deadzone": deadzone.value,
		"look_ahead": look_ahead.value,
		"maximum_shake": maximum_shake.value
	}
	profile_data["atmosphere"] = {
		"kind": str(atmosphere_kind.get_item_metadata(atmosphere_kind.selected)),
		"density": int(atmosphere_density.value),
		"speed": atmosphere_speed.value,
		"opacity": atmosphere_opacity.value
	}
	profile_data["screen"] = {
		"scanline_alpha": scanline_alpha.value,
		"vignette_alpha": vignette_alpha.value,
		"dither_alpha": dither_alpha.value
	}
	profile_data["actors"] = {
		"movement_bob": movement_bob.value,
		"shadow_scale": shadow_scale.value
	}
	var save_result: Dictionary = Repository.save_json(current_catalog_path, current_catalog)
	if not bool(save_result.get("ok", false)):
		status_label.text = "Could not write the presentation catalog."
		return
	var validation: Dictionary = PresentationValidator.validate_campaign_path(current_campaign_path)
	if not bool(validation.get("ok", false)):
		write_text(current_catalog_path, snapshot)
		load_catalog()
		status_label.text = "Presentation save rolled back: %s" % join_messages(validation.get("errors", []))
		return
	status_label.text = "Saved %s. %d warning(s)." % [profile_id, message_count(validation.get("warnings", []))]


func create_default_catalog() -> void:
	if current_campaign_path.is_empty():
		return
	var campaign_snapshot := read_text(current_campaign_path)
	var catalog_path := current_campaign_path.get_base_dir().path_join("presentation").path_join("core.json")
	var catalog_existed := FileAccess.file_exists(catalog_path)
	var catalog_snapshot := read_text(catalog_path) if catalog_existed else ""
	var save_result: Dictionary = Repository.save_json(catalog_path, PresentationCatalog.default_catalog())
	if not bool(save_result.get("ok", false)):
		status_label.text = "Could not create the default presentation catalog."
		return
	current_campaign["presentation_files"] = ["presentation/core.json"]
	var campaign_save: Dictionary = Repository.save_json(current_campaign_path, current_campaign)
	if not bool(campaign_save.get("ok", false)):
		write_text(current_campaign_path, campaign_snapshot)
		restore_catalog_file(catalog_path, catalog_existed, catalog_snapshot)
		status_label.text = "Could not bind the presentation catalog to the campaign."
		return
	var validation: Dictionary = PresentationValidator.validate_campaign_path(current_campaign_path)
	if not bool(validation.get("ok", false)):
		write_text(current_campaign_path, campaign_snapshot)
		restore_catalog_file(catalog_path, catalog_existed, catalog_snapshot)
		status_label.text = "Default catalog creation rolled back: %s" % join_messages(validation.get("errors", []))
		return
	load_catalog()
	status_label.text = "Created and validated presentation/core.json."


func restore_catalog_file(path: String, existed: bool, snapshot: String) -> void:
	if existed:
		write_text(path, snapshot)
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func validate_campaign() -> void:
	if current_campaign_path.is_empty():
		return
	var validation: Dictionary = PresentationValidator.validate_campaign_path(current_campaign_path)
	if bool(validation.get("ok", false)):
		status_label.text = "Presentation validation passed with %d profile(s), %d binding(s), and %d warning(s)." % [
			int(validation.get("presentation_profile_count", 0)),
			int(validation.get("presentation_binding_count", 0)),
			message_count(validation.get("warnings", []))
		]
	else:
		status_label.text = "Presentation validation failed: %s" % join_messages(validation.get("errors", []))


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


func message_count(value: Variant) -> int:
	return (value as Array).size() if typeof(value) == TYPE_ARRAY else 0


func join_messages(value: Variant) -> String:
	var messages := PackedStringArray()
	if typeof(value) == TYPE_ARRAY:
		for message in value as Array:
			messages.append(str(message))
	return " | ".join(messages)
