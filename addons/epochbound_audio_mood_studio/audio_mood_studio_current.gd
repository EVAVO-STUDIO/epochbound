@tool
extends "res://addons/epochbound_audio_mood_studio/audio_mood_studio.gd"

const CurrentRepository = preload("res://src/content/campaign_repository.gd")
const Catalog = preload("res://src/content/audio_mood_catalog.gd")
const StrictValidator = preload("res://src/content/audio_mood_strict_validator.gd")


func save_current_profile() -> void:
	if current_catalog.is_empty() or profile_selector.selected < 0 or profile_selector.selected >= profile_ids.size():
		status_label.text = "Select a valid profile first."
		return
	var profile_id := profile_ids[profile_selector.selected]
	var profile_data: Dictionary = profile_by_id(profile_id)
	if profile_data.is_empty():
		status_label.text = "The selected profile no longer exists."
		return
	var scale: Array[int] = parse_pattern(scale_edit.text)
	var melody: Array[int] = parse_pattern(melody_edit.text)
	var bass: Array[int] = parse_pattern(bass_edit.text)
	if scale.is_empty() or melody.is_empty() or bass.is_empty():
		status_label.text = "Scale, melody and bass patterns cannot be empty."
		return
	var snapshot := read_text(current_catalog_path)
	profile_data["music"] = {
		"tempo_bpm": tempo.value,
		"root_midi": int(root_midi.value),
		"scale": scale,
		"melody_steps": melody,
		"bass_steps": bass,
		"waveform": str(waveform.get_item_metadata(waveform.selected)),
		"pulse_width": pulse_width.value,
		"gain": music_gain.value,
		"combat_gain": combat_gain.value
	}
	profile_data["ambience"] = {
		"kind": str(ambience_kind.get_item_metadata(ambience_kind.selected)),
		"gain": ambience_gain.value,
		"tone_hz": ambience_tone.value,
		"motion": ambience_motion.value
	}
	profile_data["mix"] = {
		"menu_duck": menu_duck.value,
		"cinematic_duck": cinematic_duck.value,
		"pause_duck": pause_duck.value,
		"crossfade_seconds": crossfade.value
	}
	var save_result: Dictionary = CurrentRepository.save_json(current_catalog_path, current_catalog)
	if not bool(save_result.get("ok", false)):
		status_label.text = "Could not write the audio catalogue."
		return
	var validation: Dictionary = StrictValidator.validate_campaign_path(current_campaign_path)
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
	var save_result: Dictionary = CurrentRepository.save_json(catalogue_path, Catalog.default_catalog())
	if not bool(save_result.get("ok", false)):
		status_label.text = "Could not create the default audio catalogue."
		return
	current_campaign["audio_files"] = ["audio/core.json"]
	var campaign_save: Dictionary = CurrentRepository.save_json(current_campaign_path, current_campaign)
	if not bool(campaign_save.get("ok", false)):
		restore_catalogue_creation(campaign_snapshot, catalogue_path, catalogue_existed, catalogue_snapshot)
		status_label.text = "Could not bind the audio catalogue to the campaign."
		return
	var validation: Dictionary = StrictValidator.validate_campaign_path(current_campaign_path)
	if not bool(validation.get("ok", false)):
		restore_catalogue_creation(campaign_snapshot, catalogue_path, catalogue_existed, catalogue_snapshot)
		status_label.text = "Default audio catalogue rolled back: %s" % join_messages(validation.get("errors", []))
		return
	load_catalog()
	status_label.text = "Created and strictly validated audio/core.json."


func validate_campaign() -> void:
	if current_campaign_path.is_empty():
		return
	var validation: Dictionary = StrictValidator.validate_campaign_path(current_campaign_path)
	if bool(validation.get("ok", false)):
		status_label.text = "Audio validation passed with %d profile(s), %d binding(s), and %d warning(s)." % [
			int(validation.get("audio_profile_count", 0)),
			int(validation.get("audio_binding_count", 0)),
			message_count(validation.get("warnings", []))
		]
	else:
		status_label.text = "Audio validation failed: %s" % join_messages(validation.get("errors", []))
