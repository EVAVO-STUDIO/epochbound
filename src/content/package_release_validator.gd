@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/cinematic_validator.gd")
const CampaignPackage = preload("res://src/content/campaign_package.gd")
const HideawayValidator = preload("res://src/content/hideaway_stewardship_validator.gd")

const CHANNELS := ["development", "alpha", "beta", "release"]
const SEMVER_PATTERN := "^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?$"


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var release_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := validate_release_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		release_count += int(report.get("release_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["release_count"] = release_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_campaign_path(campaign_path)
	var release_report := validate_release_only(campaign_path)
	var hideaway_report := HideawayValidator.validate_hideaway_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, release_report.get("errors", []))
	append_messages(errors, hideaway_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, release_report.get("warnings", []))
	append_messages(warnings, hideaway_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["release_count"] = release_report.get("release_count", 0)
	output["hideaway_memento_count"] = hideaway_report.get("hideaway_memento_count", 0)
	output["hideaway_quiet_moment_count"] = hideaway_report.get("hideaway_quiet_moment_count", 0)
	output["hideaway_morrow_routine_count"] = hideaway_report.get("hideaway_morrow_routine_count", 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	return BaseValidator.validate_profile(profile, campaign_path)


static func validate_package(package_path: String) -> Dictionary:
	return CampaignPackage.inspect_package(package_path)


static func validate_release_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var result := Repository.read_json(campaign_path)
	if not bool(result.get("ok", false)):
		append_messages(errors, result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings, "release_count": 0}
	var campaign: Dictionary = result.get("data", {})
	var campaign_id := str(campaign.get("id", campaign_path))
	var release_value: Variant = campaign.get("release", {})
	var release: Dictionary
	if typeof(release_value) != TYPE_DICTIONARY or (release_value as Dictionary).is_empty():
		release = CampaignPackage.default_release(campaign_id)
		warnings.append("%s: release metadata is not authored yet; Package Studio will use development defaults until it is saved." % campaign_id)
	else:
		release = release_value as Dictionary
	validate_semver(str(release.get("version", "")), "%s/release/version" % campaign_id, errors)
	validate_semver(str(release.get("minimum_runtime", "")), "%s/release/minimum_runtime" % campaign_id, errors)
	var channel := str(release.get("channel", ""))
	if not CHANNELS.has(channel):
		errors.append("%s/release: unsupported channel '%s'." % [campaign_id, channel])
	var package_name := str(release.get("package_name", ""))
	if package_name.is_empty() or Repository.normalise_id(package_name) != package_name:
		errors.append("%s/release: package_name must be a normalised identifier." % campaign_id)
	if package_name != campaign_id:
		warnings.append("%s/release: package_name differs from campaign id; confirm this is intentional." % campaign_id)
	if str(release.get("license", "")).strip_edges().is_empty():
		errors.append("%s/release: license is required." % campaign_id)
	var collected := CampaignPackage.collect_campaign_files(campaign_path)
	append_messages(errors, collected.get("errors", []))
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "release_count": 1}


static func validate_semver(value: String, prefix: String, errors: Array[String]) -> void:
	var regex := RegEx.new()
	if regex.compile(SEMVER_PATTERN) != OK or regex.search(value) == null:
		errors.append("%s must use semantic version syntax such as 1.2.3 or 1.2.3-beta.1." % prefix)


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) == TYPE_ARRAY:
		for message in value:
			target.append(str(message))
