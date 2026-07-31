@tool
extends Control

const Repository = preload("res://src/content/campaign_repository.gd")
const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")
const AudioMoodValidator = preload("res://src/content/audio_mood_validator.gd")

const WAVEFORMS := ["pulse", "triangle", "sine"]
const AMBIENCE_KINDS := ["room_tone", "pollen", "insects", "embers", "cinders", "machinery", "furnace", "wind", "rain"]

var campaign_selector: OptionButton
var profile_selector: OptionButton
var status_label: Label
var binding_label: Label
var tempo: SpinBox
var root_midi: SpinBox
var waveform: OptionButton
var pulse_width: SpinBox
var music_gain: SpinBox
var combat_gain: SpinBox
var scale_edit: LineEdit
var melody_edit: LineEdit
var bass_edit: LineEdit
var ambience_kind: OptionButton
var ambience_gain: SpinBox
var ambience_tone: SpinBox
var ambience_motion: SpinBox
var menu_duck: SpinBox
var cinematic_duck: SpinBox
var pause_duck: SpinBox
var crossfade: SpinBox

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
	title.text = "AUDIO & MOOD STUDIO"
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
	navigation.custom_minimum_size.x = 245
	split.add_child(navigation)
	var profile_heading := Label.new()
	profile_heading.text = "PROFILE"
	navigation.add_child(profile_heading)
	profile_selector = OptionButton.new()
	profile_selector.item_selected.connect(Callable(self, "_on_profile_selected"))
	navigation.add_child(profile_selector)
	var create_button := Button.new()
	create_button.text = "Create Default Catalogue"
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
	add_heading(form, "MUSIC")
	tempo = add_spin(form, "Tempo (BPM)", 40.0, 200.0, 1.0)
	root_midi = add_spin(form, "Root MIDI note", 24.0, 84.0, 1.0)
	waveform = add_option(form, "Waveform", WAVEFORMS)
	pulse_width = add_spin(form, "Pulse width", 0.10, 0.90, 0.01)
	music_gain = add_spin(form, "Exploration gain", 0.0, 0.45, 0.01)
	combat_gain = add_spin(form, "Combat layer gain", 0.0, 0.30, 0.01)
	scale_edit = add_line(form, "Scale semitones")
	melody_edit = add_line(form, "Melody scale degrees")
	bass_edit = add_line(form, "Bass scale degrees")
	var pattern_help := Label.new()
	pattern_help.text = "Use spaces or commas. Use - or -99 for a rest."
	pattern_help.modulate = Color("8f9aa2")
	form.add_child(pattern_help)
	add_heading(form, "AMBIENCE")
	ambience_kind = add_option(form, "Kind", AMBIENCE_KINDS)
	ambience_gain = add_spin(form, "Gain", 0.0, 0.30, 0.01)
	ambience_tone = add_spin(form, "Tone frequency", 20.0, 1200.0, 1.0)
	ambience_motion = add_spin(form, "Motion", 0.0, 1.0, 0.01)
	add_heading(form, "MIX AND DUCKING")
	menu_duck = add_spin(form, "Menu/dialogue multiplier", 0.05, 1.0, 0.01)
	cinematic_duck = add_spin(form, "Cinematic multiplier", 0.05, 1.0, 0.01)
	pause_duck = add_spin(form, "Pause multiplier", 0.05, 1.0, 0.01)
	crossfade = add_spin(form, "Transition seconds", 0.05, 4.0, 0.05)
	var save_button := Button.new()
	save_button.text = "Save Audio Profile"
	save_button.pressed.connect(Callable(self, "save_current_profile"))
	form.add_child(save_button)
	status_label = Label.new()
	status_label.text = "Select a campaign."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(status_label)


func add_heading(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)


func add_spin(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 200
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size.x = 140
	row.add_child(spin)
	return spin


func add_option(parent: VBoxContainer, label_text: String, values: Array) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 200
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size.x = 180
	for value in values:
		option.add_item(str(value).replace("_", " ").capitalize())
		option.set_item_metadata(option.item_count - 1, str(value))
	row.add_child(option)
	return option


func add_line(parent: VBoxContainer, label_text: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 200
	row.add_child(label)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


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
	load_campaign_path(str(campaigns[index].get("path", "")))


func load_campaign_path(path: String) -> bool:
	current_campaign_path = path
	var result: Dictionary = Repository.read_json(path)
	if not bool(result.get("ok", false)):
		status_label.text = "Could not read the selected campaign."
		return false
	current_campaign = result.get("data", {})
	load_catalog()
	return not current_catalog.is_empty()


func load_catalog() -> void:
	current_catalog_path = AudioMoodCatalog.primary_catalog_path(current_campaign_path, current_campaign)
	var result: Dictionary = Repository.read_json(current_catalog_path)
	if not bool(result.get("ok", false)):
		current_catalog = {}
		profile_selector.clear()
		profile_ids.clear()
		binding_label.text = "No audio catalogue exists yet."
		status_label.text = "Create a default catalogue or add audio_files to the campaign."
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
	binding_label.text = "%d map/era binding(s)\nTitle profile: %s" % [binding_count, str(current_catalog.get("title_profile_id", AudioMoodCatalog.DEFAULT_PROFILE_ID))]
	if profile_ids.is_empty():
		status_label.text = "The catalogue has no audio profiles."
		return
	profile_selector.select(0)
	_on_profile_selected(0)
	status_label.text = "Loaded %d original audio profile(s)." % profile_ids.size()


func _on_profile_selected(index: int) -> void:
	if index < 0 or index >= profile_ids.size():
		return
	var profile_data := profile_by_id(profile_ids[index])
	if not profile_data.is_empty():
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
	tempo.value = AudioMoodCatalog.number(profile_data, "music", "tempo_bpm", 78.0)
	root_midi.value = AudioMoodCatalog.integer(profile_data, "music", "root_midi", 45)
	select_metadata(waveform, AudioMoodCatalog.text(profile_data, "music", "waveform", "triangle"))
	pulse_width.value = AudioMoodCatalog.number(profile_data, "music", "pulse_width", 0.35)
	music_gain.value = AudioMoodCatalog.number(profile_data, "music", "gain", 0.16)
	combat_gain.value = AudioMoodCatalog.number(profile_data, "music", "combat_gain", 0.06)
	scale_edit.text = pattern_text(AudioMoodCatalog.integer_array(profile_data, "music", "scale", [0, 2, 3, 7, 9]), false)
	melody_edit.text = pattern_text(AudioMoodCatalog.integer_array(profile_data, "music", "melody_steps", [0, -99, 2, -99]), true)
	bass_edit.text = pattern_text(AudioMoodCatalog.integer_array(profile_data, "music", "bass_steps", [0, -99, -99, -99]), true)
	select_metadata(ambience_kind, AudioMoodCatalog.text(profile_data, "ambience", "kind", "room_tone"))
	ambience_gain.value = AudioMoodCatalog.number(profile_data, "ambience", "gain", 0.055)
	ambience_tone.value = AudioMoodCatalog.number(profile_data, "ambience", "tone_hz", 52.0)
	ambience_motion.value = AudioMoodCatalog.number(profile_data, "ambience", "motion", 0.22)
	menu_duck.value = AudioMoodCatalog.number(profile_data, "mix", "menu_duck", 0.45)
	cinematic_duck.value = AudioMoodCatalog.number(profile_data, "mix", "cinematic_duck", 0.28)
	pause_duck.value = AudioMoodCatalog.number(profile_data, "mix", "pause_duck", 0.20)
	crossfade.value = AudioMoodCatalog.number(profile_data, "mix", "crossfade_seconds", 0.90)


func select_metadata(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func parse_pattern(text: String) -> Array[int]:
	var output: Array[int] = []
	var normalized := text.replace(",", " ").replace("\t", " ")
	for token_value in normalized.split(" ", false):
		var token := str(token_value).strip_edges().to_lower()
		if token.is_empty():
			continue
		if token == "-" or token == "r" or token == "rest":
			output.append(AudioMoodCatalog.REST_STEP)
		elif token.is_valid_int():
			output.append(int(token))
	return output


func pattern_text(values: Array[int], rest_symbol: bool) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append("-" if rest_symbol and value == AudioMoodCatalog.REST_STEP else str(value))
	return " ".join(parts)


func save_current_profile() -> void:
	if current_catalog.is_empty() or profile_selector.selected < 0 or profile_selector.selected >= profile_ids.size():
		status_label.text = "Select a valid profile first."
		return
	var profile_id := profile_ids[profile_selector.selected]
	var profile_data := profile_by_id(profile_id)
	if profile_data.is_empty():
		status_label.text = "The selected profile no longer exists."
		return
	var scale := parse_pattern(scale_edit.text)
	var melody := parse_pattern(melody_edit.text)
	var bass := parse_pattern(bass_edit.text)
	if scale.is_empty() or melody.is_empty() or bass.is_empty():
		status_label.text = "Scale, melody and bass patterns cannot be empty."
		return
	var snapshot := read_text(current_catalog_path)
	profile_data["music"] = {"tempo_bpm": tempo.value, "root_midi": int(root_midi.value), "scale": scale, "melody_steps": melody, "bass_steps": bass, "waveform": str(waveform.get_item_metadata(waveform.selected)), "pulse_width": pulse_width.value, "gain": music_gain.value, "combat_gain": combat_gain.value}
	profile_data["ambience"] = {"kind": str(ambience_kind.get_item_metadata(ambience_kind.selected)), "gain": ambience_gain.value, "tone_hz": ambience_tone.value, "motion": ambience_motion.value}
	profile_data["mix"] = {"menu_duck": menu_duck.value, "cinematic_duck": cinematic_duck.value, "pause_duck": pause_duck.value, "crossfade_seconds": crossfade.value}
	var save_result := Repository.save_json(current_catalog_path, current_catalog)
	if not bool(save_result.get("ok", false)):
		status_label.text = "Could not write the audio catalogue."
		return
	var validation := AudioMoodValidator.validate_campaign_path(current_campaign_path)
	if not bool(validation.get("ok", false)):
		write_text(current_catalog_path, snapshot)
		load_catalog()
		status_label.text = "Audio save rolled back: %s" % join_messages(validation.get("errors", []))
		return
	status_label.text = "Saved %s with %d warning(s)." % [profile_id, message_count(validation.get("warnings", []))]


func create_default_catalog() -> void:
	if current_campaign_path.is_empty():
		return
	var campaign_snapshot := read_text(current_campaign_path)
	var catalogue_path := current_campaign_path.get_base_dir().path_join("audio").path_join("core.json")
	var catalogue_existed := FileAccess.file_exists(catalogue_path)
	var catalogue_snapshot := read_text(catalogue_path) if catalogue_existed else ""
	var save_result := Repository.save_json(catalogue_path, AudioMoodCatalog.default_catalog())
	if not bool(save_result.get("ok", false)):
		status_label.text = "Could not create the default audio catalogue."
		return
	current_campaign["audio_files"] = ["audio/core.json"]
	var campaign_save := Repository.save_json(current_campaign_path, current_campaign)
	if not bool(campaign_save.get("ok", false)):
		restore_catalogue_creation(campaign_snapshot, catalogue_path, catalogue_existed, catalogue_snapshot)
		status_label.text = "Could not bind the audio catalogue to the campaign."
		return
	var validation := AudioMoodValidator.validate_campaign_path(current_campaign_path)
	if not bool(validation.get("ok", false)):
		restore_catalogue_creation(campaign_snapshot, catalogue_path, catalogue_existed, catalogue_snapshot)
		status_label.text = "Default audio catalogue rolled back: %s" % join_messages(validation.get("errors", []))
		return
	load_catalog()
	status_label.text = "Created and validated audio/core.json."


func restore_catalogue_creation(campaign_snapshot: String, catalogue_path: String, existed: bool, snapshot: String) -> void:
	write_text(current_campaign_path, campaign_snapshot)
	if existed:
		write_text(catalogue_path, snapshot)
	else:
		DirAccess.remove_absolute(catalogue_path)


func validate_campaign() -> void:
	if current_campaign_path.is_empty():
		return
	var validation := AudioMoodValidator.validate_campaign_path(current_campaign_path)
	if bool(validation.get("ok", false)):
		status_label.text = "Audio validation passed with %d profile(s), %d binding(s), and %d warning(s)." % [int(validation.get("audio_profile_count", 0)), int(validation.get("audio_binding_count", 0)), message_count(validation.get("warnings", []))]
	else:
		status_label.text = "Audio validation failed: %s" % join_messages(validation.get("errors", []))


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
