extends SceneTree

const CampaignPackage = preload("res://src/content/campaign_package.gd")
const CampaignInstallService = preload("res://src/content/campaign_install_service.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const ROOT := "user://sprite_package_validation"
const VALID_PACKAGE := ROOT + "/valid.epochbound.zip"
const INVALID_PACKAGE := ROOT + "/invalid-animation.epochbound.zip"
const INSTALL_ROOT := ROOT + "/installed"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	CampaignPackage.remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)
	var exported := CampaignPackage.export_campaign(CAMPAIGN_PATH, VALID_PACKAGE)
	check(bool(exported.get("ok", false)), "Reference campaign must export before animation tampering.")
	check(rewrite_with_invalid_animation(VALID_PACKAGE, INVALID_PACKAGE), "Hash-valid invalid-animation package fixture must be created.")
	var inspection := CampaignPackage.inspect_package(INVALID_PACKAGE)
	check(bool(inspection.get("ok", false)), "Animation-tampered package must remain structurally and cryptographically valid.")
	var install := CampaignInstallService.install_package(INVALID_PACKAGE, false, INSTALL_ROOT)
	check(not bool(install.get("ok", false)), "Current install service must reject invalid animation content after extraction.")
	check(contains_text(install.get("errors", []), "1 or 4 directional"), "Install rejection must identify the unsupported direction count.")
	check(DirAccess.open(INSTALL_ROOT.path_join("epochbound_demo")) == null, "Rejected animation package must never be promoted into the install root.")
	CampaignPackage.remove_tree(ROOT)
	finish()


func rewrite_with_invalid_animation(source_path: String, destination_path: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(source_path) != OK:
		return false
	var manifest_result := CampaignPackage.parse_json_bytes(reader.read_file(CampaignPackage.MANIFEST_PATH), CampaignPackage.MANIFEST_PATH)
	if not bool(manifest_result.get("ok", false)):
		reader.close()
		return false
	var manifest: Dictionary = manifest_result.get("data", {})
	var records_value: Variant = manifest.get("files", [])
	if typeof(records_value) != TYPE_ARRAY:
		reader.close()
		return false
	var writer := ZIPPacker.new()
	if writer.open(destination_path) != OK:
		reader.close()
		return false
	var rewritten_records: Array = []
	for record_value in records_value as Array:
		if typeof(record_value) != TYPE_DICTIONARY:
			writer.close()
			reader.close()
			return false
		var record: Dictionary = (record_value as Dictionary).duplicate(true)
		var relative_path := str(record.get("path", ""))
		var archive_path := CampaignPackage.CAMPAIGN_PREFIX + relative_path
		var data: PackedByteArray = reader.read_file(archive_path)
		if relative_path == "animation/core.json":
			var parsed := CampaignPackage.parse_json_bytes(data, archive_path)
			if not bool(parsed.get("ok", false)):
				writer.close()
				reader.close()
				return false
			var animation_data: Dictionary = parsed.get("data", {})
			var profiles_value: Variant = animation_data.get("profiles", [])
			if typeof(profiles_value) != TYPE_ARRAY or (profiles_value as Array).is_empty():
				writer.close()
				reader.close()
				return false
			var profiles: Array = profiles_value as Array
			var profile: Dictionary = (profiles[0] as Dictionary).duplicate(true)
			profile["directions"] = 8
			profiles[0] = profile
			animation_data["profiles"] = profiles
			data = (JSON.stringify(animation_data, "\t", true) + "\n").to_utf8_buffer()
		record["size"] = data.size()
		record["sha256"] = CampaignPackage.sha256_bytes(data)
		rewritten_records.append(record)
		if writer.start_file(archive_path, 420, CampaignPackage.FIXED_ZIP_TIME) != OK:
			writer.close()
			reader.close()
			return false
		if writer.write_file(data) != OK or writer.close_file() != OK:
			writer.close()
			reader.close()
			return false
	manifest["files"] = rewritten_records
	var manifest_bytes := (JSON.stringify(manifest, "\t", true) + "\n").to_utf8_buffer()
	if writer.start_file(CampaignPackage.MANIFEST_PATH, 420, CampaignPackage.FIXED_ZIP_TIME) != OK:
		writer.close()
		reader.close()
		return false
	var manifest_ok := writer.write_file(manifest_bytes) == OK and writer.close_file() == OK
	var writer_ok := writer.close() == OK
	reader.close()
	return manifest_ok and writer_ok


func contains_text(value: Variant, fragment: String) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for message in value as Array:
		if str(message).contains(fragment):
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Sprite package validation smoke test passed: hash-valid invalid animation content is rejected before promotion.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
