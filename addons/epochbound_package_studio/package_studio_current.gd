@tool
extends "res://addons/epochbound_package_studio/package_studio.gd"

const CurrentRepository = preload("res://src/content/campaign_repository.gd")
const CurrentValidator = preload("res://src/content/sprite_animation_strict_validator.gd")
const CampaignInstallService = preload("res://src/content/campaign_install_service.gd")


func save_release_metadata() -> bool:
	if active_campaign_path.is_empty() or active_campaign.is_empty():
		return false
	var previous := active_campaign.duplicate(true)
	active_campaign["release"] = authored_release()
	var save_result := CurrentRepository.save_json(active_campaign_path, active_campaign)
	if not bool(save_result.get("ok", false)):
		active_campaign = previous
		set_status(format_messages(save_result.get("errors", [])), true)
		return false
	var report := CurrentValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		CurrentRepository.save_json(active_campaign_path, previous)
		active_campaign = previous
		populate_release_fields()
		set_status(format_report(report), true)
		return false
	EditorInterface.get_resource_filesystem().scan()
	set_status(format_report(report), false)
	return true


func install_selected_package() -> void:
	var result: Dictionary = CampaignInstallService.install_package(
		resolved_import_path(),
		replace_check.button_pressed
	)
	if bool(result.get("ok", false)):
		EditorInterface.get_resource_filesystem().scan()
	set_status(format_install_report(result), not bool(result.get("ok", false)))


func validate_all_campaigns() -> void:
	var report := CurrentValidator.validate_all()
	set_status(format_report(report), not bool(report.get("ok", false)))
