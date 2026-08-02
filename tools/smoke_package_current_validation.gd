extends SceneTree

const CampaignPackage = preload("res://src/content/campaign_package.gd")
const CampaignInstallService = preload("res://src/content/campaign_install_service.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const ROOT := "user://package_current_validation"
const VALID_PACKAGE := ROOT + "/valid.epochbound.zip"
const INVALID_AUDIO_PACKAGE := ROOT + "/invalid-audio.epochbound.zip"
const INVALID_SUPPLY_PACKAGE := ROOT + "/invalid-supply.epochbound.zip"
const INSTALL_ROOT := ROOT + "/installed"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	CampaignPackage.remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)
	var exported: Dictionary = CampaignPackage.export_campaign(CAMPAIGN_PATH, VALID_PACKAGE)
	check(bool(exported.get("ok", false)), "Reference campaign must export before current-validator tampering.")

	check(rewrite_with_invalid_content(VALID_PACKAGE, INVALID_AUDIO_PACKAGE, "audio"), "Hash-valid invalid-audio package fixture must be created.")
	var audio_inspection: Dictionary = CampaignPackage.inspect_package(INVALID_AUDIO_PACKAGE)
	check(bool(audio_inspection.get("ok", false)), "Invalid-audio package must remain structurally and cryptographically valid.")
	var audio_install: Dictionary = CampaignInstallService.install_package(INVALID_AUDIO_PACKAGE, false, INSTALL_ROOT)
	check(not bool(audio_install.get("ok", false)), "Current install service must reject invalid Audio content after extraction.")
	check(contains_text(audio_install.get("errors", []), "tempo_bpm"), "Audio rejection must identify the invalid tempo.")
	check(DirAccess.open(INSTALL_ROOT.path_join("epochbound_demo")) == null, "Rejected Audio package must never be promoted.")

	check(rewrite_with_invalid_content(VALID_PACKAGE, INVALID_SUPPLY_PACKAGE, "supply"), "Hash-valid invalid-supply package fixture must be created.")
	var supply_inspection: Dictionary = CampaignPackage.inspect_package(INVALID_SUPPLY_PACKAGE)
	check(bool(supply_inspection.get("ok", false)), "Invalid-supply package must remain structurally and cryptographically valid.")
	var supply_install: Dictionary = CampaignInstallService.install_package(INVALID_SUPPLY_PACKAGE, false, INSTALL_ROOT)
	check(not bool(supply_install.get("ok", false)), "Current install service must reject invalid regional supply content after extraction.")
	check(contains_text(supply_install.get("errors", []), "supply_region_id"), "Supply rejection must identify the unknown merchant route.")
	check(DirAccess.open(INSTALL_ROOT.path_join("epochbound_demo")) == null, "Rejected supply package must never be promoted.")

	CampaignPackage.remove_tree(ROOT)
	finish()


func rewrite_with_invalid_content(source_path: String, destination_path: String, fixture_kind: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(source_path) != OK:
		return false
	var manifest_result: Dictionary = CampaignPackage.parse_json_bytes(
		reader.read_file(CampaignPackage.MANIFEST_PATH),
		CampaignPackage.MANIFEST_PATH
	)
	if not bool(manifest_result.get("ok", false)):
		reader.close()
		return false
	var manifest_value: Variant = manifest_result.get("data", {})
	var manifest: Dictionary = manifest_value if typeof(manifest_value) == TYPE_DICTIONARY else {}
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
		if fixture_kind == "audio" and relative_path == "audio/core.json":
			data = invalid_audio_bytes(data, archive_path)
		elif fixture_kind == "supply" and relative_path == "economy/core.json":
			data = invalid_supply_bytes(data, archive_path)
		if data.is_empty():
			writer.close()
			reader.close()
			return false
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


func invalid_audio_bytes(data: PackedByteArray, archive_path: String) -> PackedByteArray:
	var parsed: Dictionary = CampaignPackage.parse_json_bytes(data, archive_path)
	if not bool(parsed.get("ok", false)):
		return PackedByteArray()
	var audio_value: Variant = parsed.get("data", {})
	var audio_data: Dictionary = audio_value if typeof(audio_value) == TYPE_DICTIONARY else {}
	var profiles_value: Variant = audio_data.get("profiles", [])
	if typeof(profiles_value) != TYPE_ARRAY or (profiles_value as Array).is_empty():
		return PackedByteArray()
	var profiles: Array = profiles_value as Array
	var profile_value: Variant = profiles[0]
	if typeof(profile_value) != TYPE_DICTIONARY:
		return PackedByteArray()
	var profile: Dictionary = (profile_value as Dictionary).duplicate(true)
	var music_value: Variant = profile.get("music", {})
	var music: Dictionary = (music_value as Dictionary).duplicate(true) if typeof(music_value) == TYPE_DICTIONARY else {}
	music["tempo_bpm"] = 999.0
	profile["music"] = music
	profiles[0] = profile
	audio_data["profiles"] = profiles
	return (JSON.stringify(audio_data, "\t", true) + "\n").to_utf8_buffer()


func invalid_supply_bytes(data: PackedByteArray, archive_path: String) -> PackedByteArray:
	var parsed: Dictionary = CampaignPackage.parse_json_bytes(data, archive_path)
	if not bool(parsed.get("ok", false)):
		return PackedByteArray()
	var economy_value: Variant = parsed.get("data", {})
	var economy: Dictionary = economy_value if typeof(economy_value) == TYPE_DICTIONARY else {}
	var merchants_value: Variant = economy.get("merchants", [])
	if typeof(merchants_value) != TYPE_ARRAY or (merchants_value as Array).is_empty():
		return PackedByteArray()
	var merchants: Array = merchants_value as Array
	var merchant_value: Variant = merchants[0]
	if typeof(merchant_value) != TYPE_DICTIONARY:
		return PackedByteArray()
	var merchant: Dictionary = (merchant_value as Dictionary).duplicate(true)
	merchant["supply_region_id"] = "missing_route"
	merchants[0] = merchant
	economy["merchants"] = merchants
	return (JSON.stringify(economy, "\t", true) + "\n").to_utf8_buffer()


func contains_text(value: Variant, fragment: String) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for message in value as Array:
		if fragment in str(message):
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Current package validation smoke test passed: hash-valid invalid Audio and regional supply content are rejected before promotion.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
