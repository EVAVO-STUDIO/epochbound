@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const CampaignPackage = preload("res://src/content/campaign_package.gd")
const CurrentValidator = preload("res://src/content/sprite_animation_strict_validator.gd")

const VERIFIED_STAGING_ROOT := "user://campaign_verified_install"


static func install_package(
	package_path: String,
	replace_existing: bool = false,
	install_root: String = Repository.USER_ROOT
) -> Dictionary:
	var inspection: Dictionary = CampaignPackage.inspect_package(package_path)
	if not bool(inspection.get("ok", false)):
		return inspection
	var manifest: Dictionary = inspection.get("manifest", {})
	var campaign_id := str(manifest.get("campaign_id", ""))
	if campaign_id.is_empty():
		return fail("Package manifest does not declare a campaign ID.")
	if (
		install_root == Repository.USER_ROOT
		and FileAccess.file_exists(Repository.BUILTIN_ROOT.path_join(campaign_id).path_join("campaign.json"))
	):
		return fail("Package ID '%s' would shadow a built-in campaign." % campaign_id)
	var target := install_root.path_join(campaign_id)
	if DirAccess.open(target) != null and not replace_existing:
		return fail("Campaign is already installed: %s." % campaign_id)
	var transaction_root := VERIFIED_STAGING_ROOT.path_join("%s-%d" % [campaign_id, Time.get_ticks_usec()])
	CampaignPackage.remove_tree(transaction_root)
	DirAccess.make_dir_recursive_absolute(transaction_root)
	var staged_result: Dictionary = CampaignPackage.install_package(package_path, false, transaction_root)
	if not bool(staged_result.get("ok", false)):
		CampaignPackage.remove_tree(transaction_root)
		return staged_result
	var staged_campaign_root := transaction_root.path_join(campaign_id)
	var staged_campaign_path := staged_campaign_root.path_join("campaign.json")
	var validation: Dictionary = CurrentValidator.validate_campaign_path(staged_campaign_path)
	if not bool(validation.get("ok", false)):
		CampaignPackage.remove_tree(transaction_root)
		return {
			"ok": false,
			"errors": validation.get("errors", []),
			"warnings": validation.get("warnings", []),
			"validation": validation
		}
	DirAccess.make_dir_recursive_absolute(install_root)
	var backup := target + ".backup"
	CampaignPackage.remove_tree(backup)
	if DirAccess.open(target) != null and DirAccess.rename_absolute(target, backup) != OK:
		CampaignPackage.remove_tree(transaction_root)
		return fail("Could not preserve the existing campaign before replacement.")
	if DirAccess.rename_absolute(staged_campaign_root, target) != OK:
		if DirAccess.open(backup) != null:
			DirAccess.rename_absolute(backup, target)
		CampaignPackage.remove_tree(transaction_root)
		return fail("Could not promote the fully validated campaign installation.")
	CampaignPackage.remove_tree(backup)
	CampaignPackage.remove_tree(transaction_root)
	return {
		"ok": true,
		"campaign_id": campaign_id,
		"campaign_path": target.path_join("campaign.json"),
		"target": target,
		"validation": validation,
		"errors": [],
		"warnings": validation.get("warnings", [])
	}


static func fail(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "warnings": []}
