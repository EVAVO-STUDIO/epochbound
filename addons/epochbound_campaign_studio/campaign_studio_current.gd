@tool
extends "res://addons/epochbound_campaign_studio/world_builder_studio.gd"

const CurrentRepository = preload("res://src/content/campaign_repository.gd")
const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")
const CurrentValidator = preload("res://src/content/audio_mood_strict_validator.gd")
const CampaignPackage = preload("res://src/content/campaign_package.gd")


func create_campaign() -> void:
	var requested_id := campaign_id_edit.text
	var result: Dictionary = CurrentRepository.create_campaign(requested_id)
	if not bool(result.get("ok", false)):
		set_status(format_messages(result.get("errors", [])), true)
		return
	var campaign_id := CurrentRepository.normalise_id(requested_id)
	var campaign_path := str(result.get("campaign_path", ""))
	var campaign_root := campaign_path.get_base_dir()
	var audio_path := campaign_root.path_join("audio").path_join("core.json")
	var audio_result: Dictionary = CurrentRepository.save_json(audio_path, AudioMoodCatalog.default_catalog())
	if not bool(audio_result.get("ok", false)):
		CampaignPackage.remove_tree(campaign_root)
		set_status("Campaign creation rolled back: %s" % format_messages(audio_result.get("errors", [])), true)
		return
	var campaign_result: Dictionary = CurrentRepository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		CampaignPackage.remove_tree(campaign_root)
		set_status("Campaign creation rolled back: %s" % format_messages(campaign_result.get("errors", [])), true)
		return
	var campaign_data: Dictionary = campaign_result.get("data", {})
	campaign_data["audio_files"] = ["audio/core.json"]
	var save_result: Dictionary = CurrentRepository.save_json(campaign_path, campaign_data)
	if not bool(save_result.get("ok", false)):
		CampaignPackage.remove_tree(campaign_root)
		set_status("Campaign creation rolled back: %s" % format_messages(save_result.get("errors", [])), true)
		return
	var validation: Dictionary = CurrentValidator.validate_campaign_path(campaign_path)
	if not bool(validation.get("ok", false)):
		CampaignPackage.remove_tree(campaign_root)
		set_status("Campaign creation rolled back: %s" % format_messages(validation.get("errors", [])), true)
		return
	campaign_id_edit.clear()
	rescan_editor_files()
	refresh_campaigns(campaign_id)
	set_status(
		"Created campaign '%s' with world-builder, presentation fallback, and Audio & Mood scaffolding." % campaign_id,
		false
	)
