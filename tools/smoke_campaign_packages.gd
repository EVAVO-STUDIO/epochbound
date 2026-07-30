extends SceneTree

const CampaignPackage = preload("res://src/content/campaign_package.gd")
const Validator = preload("res://src/content/package_release_validator.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const TEST_ROOT := "user://package_release_smoke"
const INSTALL_ROOT := TEST_ROOT + "/installed"
const PACKAGE_A := TEST_ROOT + "/epochbound-a.epochbound.zip"
const PACKAGE_B := TEST_ROOT + "/epochbound-b.epochbound.zip"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	CampaignPackage.remove_tree(TEST_ROOT)
	DirAccess.make_dir_recursive_absolute(TEST_ROOT)
	var report := Validator.validate_campaign_path(CAMPAIGN_PATH)
	check(bool(report.get("ok", false)), "Reference campaign must pass release validation.")
	var export_a := CampaignPackage.export_campaign(CAMPAIGN_PATH, PACKAGE_A)
	var export_b := CampaignPackage.export_campaign(CAMPAIGN_PATH, PACKAGE_B)
	check(bool(export_a.get("ok", false)), "Reference campaign must export to a package.")
	check(bool(export_b.get("ok", false)), "Reference campaign must export deterministically a second time.")
	check(str(export_a.get("sha256", "")) == str(export_b.get("sha256", "")), "Identical campaign inputs must produce identical package bytes.")
	var inspection := CampaignPackage.inspect_package(PACKAGE_A)
	check(bool(inspection.get("ok", false)), "Exported package must pass manifest and hash inspection.")
	check(int(inspection.get("file_count", 0)) > 10, "Reference package must include the complete campaign tree.")
	var install := CampaignPackage.install_package(PACKAGE_A, false, INSTALL_ROOT)
	check(bool(install.get("ok", false)), "Validated package must install into an isolated root.")
	if bool(install.get("ok", false)):
		var installed_validation := Validator.validate_campaign_path(str(install.get("campaign_path", "")))
		check(bool(installed_validation.get("ok", false)), "Installed campaign must pass the complete runtime validator.")
	var duplicate := CampaignPackage.install_package(PACKAGE_A, false, INSTALL_ROOT)
	check(not bool(duplicate.get("ok", false)), "Existing campaign installation must not be overwritten without permission.")
	var replacement := CampaignPackage.install_package(PACKAGE_A, true, INSTALL_ROOT)
	check(bool(replacement.get("ok", false)), "Explicit replacement must use the validated atomic install path.")
	CampaignPackage.remove_tree(TEST_ROOT)
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Campaign package smoke test passed: deterministic export, manifest inspection, validation, install and replacement are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
