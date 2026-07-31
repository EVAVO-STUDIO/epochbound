@tool
extends "res://addons/epochbound_campaign_studio/campaign_studio_current.gd"

const AnimationRepository = preload("res://src/content/campaign_repository.gd")
const SpriteAnimationCatalog = preload("res://src/content/sprite_animation_catalog.gd")
const SpriteAnimationValidator = preload("res://src/content/sprite_animation_validator.gd")
const AnimationCampaignPackage = preload("res://src/content/campaign_package.gd")


func create_campaign() -> void:
	var requested_id := campaign_id_edit.text
	var campaign_id := AnimationRepository.normalise_id(requested_id)
	if campaign_id.is_empty():
		super.create_campaign()
		return
	var campaign_root := AnimationRepository.DEFAULT_ROOT.path_join(campaign_id)
	var campaign_path := campaign_root.path_join("campaign.json")
	var existed_before := FileAccess.file_exists(campaign_path)
	super.create_campaign()
	if existed_before or not FileAccess.file_exists(campaign_path):
		return
	var animation_path := campaign_root.path_join("animation").path_join("core.json")
	var animation_result := AnimationRepository.save_json(animation_path, SpriteAnimationCatalog.default_catalog())
	if not bool(animation_result.get("ok", false)):
		rollback_campaign(campaign_root, "Could not create animation/core.json.")
		return
	var campaign_result := AnimationRepository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		rollback_campaign(campaign_root, "Could not reopen the new campaign manifest.")
		return
	var campaign: Dictionary = campaign_result.get("data", {})
	campaign["animation_files"] = ["animation/core.json"]
	var save_result := AnimationRepository.save_json(campaign_path, campaign)
	if not bool(save_result.get("ok", false)):
		rollback_campaign(campaign_root, "Could not bind the animation catalogue.")
		return
	var validation := SpriteAnimationValidator.validate_campaign_path(campaign_path)
	if not bool(validation.get("ok", false)):
		rollback_campaign(campaign_root, "Animation-aware campaign validation failed: %s" % format_messages(validation.get("errors", [])))
		return
	rescan_editor_files()
	refresh_campaigns(campaign_id)
	set_status("Created campaign '%s' with world, presentation, audio, and sprite-animation scaffolding." % campaign_id, false)


func rollback_campaign(campaign_root: String, message: String) -> void:
	AnimationCampaignPackage.remove_tree(campaign_root)
	rescan_editor_files()
	refresh_campaigns()
	set_status("Campaign creation rolled back: %s" % message, true)
