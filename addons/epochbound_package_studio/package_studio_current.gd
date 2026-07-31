@tool
extends "res://addons/epochbound_package_studio/package_studio.gd"

const CampaignInstallService = preload("res://src/content/campaign_install_service.gd")


func install_selected_package() -> void:
	var result: Dictionary = CampaignInstallService.install_package(
		resolved_import_path(),
		replace_check.button_pressed
	)
	if bool(result.get("ok", false)):
		EditorInterface.get_resource_filesystem().scan()
	set_status(format_install_report(result), not bool(result.get("ok", false)))
