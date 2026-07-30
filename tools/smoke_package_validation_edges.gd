extends SceneTree

const CampaignPackage = preload("res://src/content/campaign_package.gd")

const ROOT := "user://package_validation_edges"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	CampaignPackage.remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)
	check(not CampaignPackage.safe_archive_path("campaign/../escape.json"), "Path traversal entries must be rejected.")

	var script_path: String = ROOT + "/script.zip"
	var script_data: PackedByteArray = "extends Node".to_utf8_buffer()
	write_zip(script_path, {
		CampaignPackage.MANIFEST_PATH: manifest_bytes([file_record("logic.gd", script_data)]),
		"campaign/logic.gd": script_data
	})
	check(not bool(CampaignPackage.inspect_package(script_path).get("ok", false)), "Executable script content must be rejected.")

	var mismatch_path: String = ROOT + "/mismatch.zip"
	var campaign_data: PackedByteArray = "{\"schema_version\":1,\"id\":\"edge_test\"}".to_utf8_buffer()
	var mismatch_record: Dictionary = file_record("campaign.json", campaign_data)
	mismatch_record["sha256"] = "00"
	write_zip(mismatch_path, {
		CampaignPackage.MANIFEST_PATH: manifest_bytes([mismatch_record]),
		"campaign/campaign.json": campaign_data
	})
	check(not bool(CampaignPackage.inspect_package(mismatch_path).get("ok", false)), "Hash mismatches must be rejected before extraction.")
	CampaignPackage.remove_tree(ROOT)
	finish()


func file_record(path: String, data: PackedByteArray) -> Dictionary:
	return {"path": path, "size": data.size(), "sha256": CampaignPackage.sha256_bytes(data)}


func manifest_bytes(records: Array) -> PackedByteArray:
	return (JSON.stringify({
		"package_schema": CampaignPackage.PACKAGE_SCHEMA,
		"format": CampaignPackage.PACKAGE_FORMAT,
		"campaign_id": "edge_test",
		"campaign_schema": 1,
		"title": "Edge Test",
		"author": "Test",
		"release": CampaignPackage.default_release("edge_test"),
		"files": records
	}, "\t", true) + "\n").to_utf8_buffer()


func write_zip(path: String, entries: Dictionary) -> void:
	var writer := ZIPPacker.new()
	check(writer.open(path) == OK, "Malformed-package fixture must open for writing.")
	var names := PackedStringArray()
	for key in entries.keys():
		names.append(str(key))
	names.sort()
	for name in names:
		var data_value: Variant = entries.get(name, PackedByteArray())
		var data: PackedByteArray = data_value as PackedByteArray if data_value is PackedByteArray else PackedByteArray()
		check(writer.start_file(name, 420, CampaignPackage.FIXED_ZIP_TIME) == OK, "Fixture entry must start.")
		check(writer.write_file(data) == OK, "Fixture entry must write.")
		check(writer.close_file() == OK, "Fixture entry must close.")
	check(writer.close() == OK, "Fixture package must close.")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Package validation edge smoke test passed: traversal, executable content and hash tampering are rejected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
