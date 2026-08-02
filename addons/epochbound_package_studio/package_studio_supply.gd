@tool
extends "res://addons/epochbound_package_studio/package_studio_current.gd"

const SupplyRepository = preload("res://src/content/campaign_repository.gd")
const SupplyCompleteValidator = preload("res://src/content/complete_content_validator.gd")


func save_release_metadata() -> bool:
	if active_campaign_path.is_empty() or active_campaign.is_empty():
		return false
	var previous := active_campaign.duplicate(true)
	active_campaign["release"] = authored_release()
	var save_result := SupplyRepository.save_json(active_campaign_path, active_campaign)
	if not bool(save_result.get("ok", false)):
		active_campaign = previous
		set_status(format_messages(save_result.get("errors", [])), true)
		return false
	var report := SupplyCompleteValidator.validate_campaign_path(active_campaign_path)
	if not bool(report.get("ok", false)):
		SupplyRepository.save_json(active_campaign_path, previous)
		active_campaign = previous
		populate_release_fields()
		set_status(format_report(report), true)
		return false
	EditorInterface.get_resource_filesystem().scan()
	set_status(format_report(report), false)
	return true


func validate_all_campaigns() -> void:
	var report := SupplyCompleteValidator.validate_all()
	set_status(format_report(report), not bool(report.get("ok", false)))
