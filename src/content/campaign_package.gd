@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const CampaignValidator = preload("res://src/content/cinematic_validator.gd")

const PACKAGE_SCHEMA := 1
const PACKAGE_FORMAT := "epochbound-campaign"
const MANIFEST_PATH := "epochbound-package.json"
const CAMPAIGN_PREFIX := "campaign/"
const EXPORT_ROOT := "user://campaign_exports"
const STAGING_ROOT := "user://campaign_import_staging"
const MAX_FILES := 2048
const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_TOTAL_BYTES := 128 * 1024 * 1024
const MAX_PATH_LENGTH := 240
const FIXED_ZIP_TIME := 315532800
const ALLOWED_EXTENSIONS := PackedStringArray([
	"json", "png", "jpg", "jpeg", "webp", "ogg", "wav", "mp3", "txt", "md"
])
const RELEASE_FIELDS := PackedStringArray([
	"version", "channel", "package_name", "minimum_runtime", "license"
])


static func default_release(campaign_id: String) -> Dictionary:
	return {
		"version": "0.1.0",
		"channel": "development",
		"package_name": Repository.normalise_id(campaign_id),
		"minimum_runtime": "0.1.0",
		"license": "All Rights Reserved"
	}


static func release_record(campaign: Dictionary) -> Dictionary:
	var output: Dictionary = default_release(str(campaign.get("id", "campaign")))
	var value: Variant = campaign.get("release", {})
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary).keys():
			output[key] = (value as Dictionary)[key]
	return output


static func package_filename(campaign: Dictionary) -> String:
	var release: Dictionary = release_record(campaign)
	var package_name := Repository.normalise_id(str(release.get("package_name", campaign.get("id", "campaign"))))
	if package_name.is_empty():
		package_name = Repository.normalise_id(str(campaign.get("id", "campaign")))
	return "%s-%s.epochbound.zip" % [package_name, release.get("version", "0.1.0")]


static func export_campaign(campaign_path: String, output_path: String = "") -> Dictionary:
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		return campaign_result
	var campaign: Dictionary = campaign_result.get("data", {})
	var collected := collect_campaign_files(campaign_path)
	if not bool(collected.get("ok", false)):
		return collected
	var files: Array = collected.get("files", [])
	var destination := output_path.strip_edges()
	if destination.is_empty():
		destination = EXPORT_ROOT.path_join(package_filename(campaign))
	if not destination.to_lower().ends_with(".zip"):
		destination += ".epochbound.zip"
	var directory_error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return fail("Could not create export directory for %s." % destination)
	var temporary := destination + ".tmp"
	DirAccess.remove_absolute(temporary)
	var writer := ZIPPacker.new()
	var error := writer.open(temporary)
	if error != OK:
		return fail("Could not open package for writing (error %d)." % error)
	for value in files:
		var record: Dictionary = value
		var archive_path := CAMPAIGN_PREFIX + str(record.get("relative_path", ""))
		error = writer.start_file(archive_path, 420, FIXED_ZIP_TIME)
		if error == OK:
			error = writer.write_file(FileAccess.get_file_as_bytes(str(record.get("source_path", ""))))
		if error == OK:
			error = writer.close_file()
		if error != OK:
			writer.close()
			DirAccess.remove_absolute(temporary)
			return fail("Could not write package entry '%s'." % archive_path)
	var manifest: Dictionary = build_manifest(campaign, files)
	error = writer.start_file(MANIFEST_PATH, 420, FIXED_ZIP_TIME)
	if error == OK:
		error = writer.write_file((JSON.stringify(manifest, "\t", true) + "\n").to_utf8_buffer())
	if error == OK:
		error = writer.close_file()
	var close_error := writer.close()
	if error != OK or close_error != OK:
		DirAccess.remove_absolute(temporary)
		return fail("Could not finalise campaign package.")
	DirAccess.remove_absolute(destination)
	if DirAccess.rename_absolute(temporary, destination) != OK:
		DirAccess.remove_absolute(temporary)
		return fail("Could not promote the completed package.")
	return {
		"ok": true,
		"path": destination,
		"manifest": manifest,
		"file_count": files.size(),
		"total_bytes": int(collected.get("total_bytes", 0)),
		"sha256": FileAccess.get_sha256(destination),
		"errors": []
	}


static func inspect_package(package_path: String) -> Dictionary:
	if not FileAccess.file_exists(package_path):
		return fail("Package does not exist: %s" % package_path)
	var reader := ZIPReader.new()
	var error := reader.open(package_path)
	if error != OK:
		return fail("Could not open package (error %d)." % error)
	var errors: Array[String] = []
	var archive_files: PackedStringArray = reader.get_files()
	if archive_files.size() > MAX_FILES + 1:
		errors.append("Package contains too many entries.")
	var archive_lookup: Dictionary = {}
	var folded_paths: Dictionary = {}
	for path_value in archive_files:
		var archive_path := str(path_value)
		if not safe_archive_path(archive_path):
			errors.append("Unsafe archive path '%s'." % archive_path)
		var folded := archive_path.to_lower()
		if folded_paths.has(folded):
			errors.append("Case-colliding archive paths '%s' and '%s'." % [folded_paths[folded], archive_path])
		folded_paths[folded] = archive_path
		archive_lookup[archive_path] = true
	if not archive_lookup.has(MANIFEST_PATH):
		errors.append("Package manifest is missing.")
	if not errors.is_empty():
		reader.close()
		return {"ok": false, "errors": errors}
	var manifest_bytes: PackedByteArray = reader.read_file(MANIFEST_PATH)
	if manifest_bytes.size() > MAX_FILE_BYTES:
		reader.close()
		return fail("Package manifest exceeds the configured size limit.")
	var manifest_result := parse_json_bytes(manifest_bytes, MANIFEST_PATH)
	if not bool(manifest_result.get("ok", false)):
		reader.close()
		return manifest_result
	var manifest: Dictionary = manifest_result.get("data", {})
	validate_manifest_header(manifest, errors)
	var records_value: Variant = manifest.get("files", [])
	var records: Array = []
	if typeof(records_value) == TYPE_ARRAY:
		records = records_value as Array
	else:
		errors.append("Package manifest files must be an array.")
	if records.size() > MAX_FILES:
		errors.append("Manifest declares too many files.")
	var declared: Dictionary = {}
	var total_bytes := 0
	for record_value in records:
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("Every manifest file record must be an object.")
			continue
		var record: Dictionary = record_value
		var relative_path := str(record.get("path", ""))
		var archive_path := CAMPAIGN_PREFIX + relative_path
		if not safe_relative_campaign_path(relative_path):
			errors.append("Unsafe campaign file path '%s'." % relative_path)
			continue
		if not extension_allowed(relative_path):
			errors.append("Disallowed package file type '%s'." % relative_path)
		if declared.has(archive_path):
			errors.append("Manifest repeats '%s'." % relative_path)
		declared[archive_path] = true
		if not archive_lookup.has(archive_path):
			errors.append("Manifest file is missing: %s." % relative_path)
			continue
		var data: PackedByteArray = reader.read_file(archive_path)
		var size := data.size()
		total_bytes += size
		if size > MAX_FILE_BYTES:
			errors.append("Package file exceeds size limit: %s." % relative_path)
		if int(record.get("size", -1)) != size:
			errors.append("Size mismatch for '%s'." % relative_path)
		if str(record.get("sha256", "")) != sha256_bytes(data):
			errors.append("SHA-256 mismatch for '%s'." % relative_path)
	if total_bytes > MAX_TOTAL_BYTES:
		errors.append("Package expanded size exceeds the configured limit.")
	for archive_path_value in archive_lookup.keys():
		var archive_path := str(archive_path_value)
		if archive_path != MANIFEST_PATH and not declared.has(archive_path):
			errors.append("Archive contains undeclared entry '%s'." % archive_path)
	if not declared.has(CAMPAIGN_PREFIX + "campaign.json"):
		errors.append("Package must contain campaign/campaign.json.")
	var campaign: Dictionary = {}
	if declared.has(CAMPAIGN_PREFIX + "campaign.json"):
		var campaign_result := parse_json_bytes(reader.read_file(CAMPAIGN_PREFIX + "campaign.json"), "campaign/campaign.json")
		if bool(campaign_result.get("ok", false)):
			campaign = campaign_result.get("data", {})
			if str(campaign.get("id", "")) != str(manifest.get("campaign_id", "")):
				errors.append("Campaign ID does not match package manifest.")
			var manifest_release_value: Variant = manifest.get("release", {})
			if typeof(manifest_release_value) != TYPE_DICTIONARY or not release_records_match(release_record(campaign), manifest_release_value as Dictionary):
				errors.append("Campaign release metadata does not match package manifest.")
		else:
			append_messages(errors, campaign_result.get("errors", []))
	reader.close()
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"manifest": manifest,
		"campaign": campaign,
		"file_count": records.size(),
		"total_bytes": total_bytes,
		"sha256": FileAccess.get_sha256(package_path)
	}


static func install_package(package_path: String, replace_existing: bool = false, install_root: String = Repository.USER_ROOT) -> Dictionary:
	var inspection := inspect_package(package_path)
	if not bool(inspection.get("ok", false)):
		return inspection
	var manifest: Dictionary = inspection.get("manifest", {})
	var campaign_id := str(manifest.get("campaign_id", ""))
	if install_root == Repository.USER_ROOT and FileAccess.file_exists(Repository.BUILTIN_ROOT.path_join(campaign_id).path_join("campaign.json")):
		return fail("Package ID '%s' would shadow a built-in campaign." % campaign_id)
	DirAccess.make_dir_recursive_absolute(install_root)
	var target := install_root.path_join(campaign_id)
	if DirAccess.open(target) != null and not replace_existing:
		return fail("Campaign is already installed: %s." % campaign_id)
	var staging := STAGING_ROOT.path_join("%s-%d" % [campaign_id, Time.get_ticks_usec()])
	remove_tree(staging)
	DirAccess.make_dir_recursive_absolute(staging)
	var reader := ZIPReader.new()
	if reader.open(package_path) != OK:
		remove_tree(staging)
		return fail("Could not reopen package for installation.")
	for record_value in (manifest.get("files", []) as Array):
		var record: Dictionary = record_value
		var relative_path := str(record.get("path", ""))
		var destination := staging.path_join(relative_path)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			reader.close()
			remove_tree(staging)
			return fail("Could not extract '%s'." % relative_path)
		file.store_buffer(reader.read_file(CAMPAIGN_PREFIX + relative_path))
		file.flush()
	reader.close()
	var staged_campaign_path := staging.path_join("campaign.json")
	var validation := CampaignValidator.validate_campaign_path(staged_campaign_path)
	if not bool(validation.get("ok", false)):
		remove_tree(staging)
		return {"ok": false, "errors": validation.get("errors", []), "warnings": validation.get("warnings", [])}
	var backup := target + ".backup"
	remove_tree(backup)
	if DirAccess.open(target) != null and DirAccess.rename_absolute(target, backup) != OK:
		remove_tree(staging)
		return fail("Could not preserve the existing campaign before replacement.")
	if DirAccess.rename_absolute(staging, target) != OK:
		if DirAccess.open(backup) != null:
			DirAccess.rename_absolute(backup, target)
		remove_tree(staging)
		return fail("Could not promote the validated campaign installation.")
	remove_tree(backup)
	return {
		"ok": true,
		"campaign_id": campaign_id,
		"campaign_path": target.path_join("campaign.json"),
		"target": target,
		"validation": validation,
		"errors": []
	}


static func collect_campaign_files(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var files: Array = []
	var folded_paths: Dictionary = {}
	collect_directory(campaign_path.get_base_dir(), "", files, errors, folded_paths)
	var total_bytes := 0
	for value in files:
		total_bytes += int((value as Dictionary).get("size", 0))
	if files.size() > MAX_FILES:
		errors.append("Campaign contains too many package files.")
	if total_bytes > MAX_TOTAL_BYTES:
		errors.append("Campaign package exceeds the expanded-byte limit.")
	return {"ok": errors.is_empty(), "files": files, "total_bytes": total_bytes, "errors": errors}


static func collect_directory(root: String, relative_directory: String, files: Array, errors: Array[String], folded_paths: Dictionary) -> void:
	var current := root if relative_directory.is_empty() else root.path_join(relative_directory)
	var directory := DirAccess.open(current)
	if directory == null:
		errors.append("Could not inspect campaign directory: %s." % current)
		return
	var directories := PackedStringArray()
	var filenames := PackedStringArray()
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			errors.append("Hidden package content is not allowed: %s." % entry)
		elif directory.is_link(entry):
			errors.append("Symbolic links are not allowed: %s." % entry)
		elif directory.current_is_dir():
			directories.append(entry)
		else:
			filenames.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	directories.sort()
	filenames.sort()
	for directory_name in directories:
		var child := directory_name if relative_directory.is_empty() else relative_directory.path_join(directory_name)
		collect_directory(root, child, files, errors, folded_paths)
	for filename in filenames:
		var relative_path := (filename if relative_directory.is_empty() else relative_directory.path_join(filename)).replace("\\", "/")
		if not safe_relative_campaign_path(relative_path) or not extension_allowed(relative_path):
			errors.append("Disallowed campaign package path '%s'." % relative_path)
			continue
		var folded := relative_path.to_lower()
		if folded_paths.has(folded):
			errors.append("Case-colliding campaign paths '%s' and '%s'." % [folded_paths[folded], relative_path])
			continue
		folded_paths[folded] = relative_path
		var source_path := root.path_join(relative_path)
		var data := FileAccess.get_file_as_bytes(source_path)
		if data.size() > MAX_FILE_BYTES:
			errors.append("Campaign file exceeds size limit: %s." % relative_path)
			continue
		files.append({"relative_path": relative_path, "source_path": source_path, "size": data.size(), "sha256": sha256_bytes(data)})


static func build_manifest(campaign: Dictionary, files: Array) -> Dictionary:
	var manifest_files: Array = []
	for value in files:
		var record: Dictionary = value
		manifest_files.append({"path": record.get("relative_path", ""), "size": record.get("size", 0), "sha256": record.get("sha256", "")})
	return {
		"package_schema": PACKAGE_SCHEMA,
		"format": PACKAGE_FORMAT,
		"campaign_id": str(campaign.get("id", "")),
		"campaign_schema": int(campaign.get("schema_version", 0)),
		"title": str(campaign.get("title", "")),
		"author": str(campaign.get("author", "")),
		"release": release_record(campaign),
		"files": manifest_files
	}


static func validate_manifest_header(manifest: Dictionary, errors: Array[String]) -> void:
	if int(manifest.get("package_schema", 0)) != PACKAGE_SCHEMA:
		errors.append("Unsupported package schema version.")
	if str(manifest.get("format", "")) != PACKAGE_FORMAT:
		errors.append("Unsupported package format.")
	var campaign_id := str(manifest.get("campaign_id", ""))
	if campaign_id.is_empty() or Repository.normalise_id(campaign_id) != campaign_id:
		errors.append("Manifest campaign_id must be a normalised identifier.")
	var release_value: Variant = manifest.get("release", {})
	if typeof(release_value) != TYPE_DICTIONARY:
		errors.append("Manifest release must be an object.")
		return
	var release: Dictionary = release_value as Dictionary
	if not semantic_version_valid(str(release.get("version", ""))) or not semantic_version_valid(str(release.get("minimum_runtime", ""))):
		errors.append("Manifest release versions are invalid.")
	if not ["development", "alpha", "beta", "release"].has(str(release.get("channel", ""))):
		errors.append("Manifest release channel is invalid.")
	var package_name := str(release.get("package_name", ""))
	if package_name.is_empty() or Repository.normalise_id(package_name) != package_name:
		errors.append("Manifest package_name must be a normalised identifier.")
	if str(release.get("license", "")).strip_edges().is_empty():
		errors.append("Manifest licence is required.")


static func release_records_match(left: Dictionary, right: Dictionary) -> bool:
	for field in RELEASE_FIELDS:
		if str(left.get(field, "")) != str(right.get(field, "")):
			return false
	return true


static func safe_archive_path(path: String) -> bool:
	if path.is_empty() or path.length() > MAX_PATH_LENGTH or path.contains("\\") or path.contains(":") or path.begins_with("/"):
		return false
	for part in path.split("/"):
		if part.is_empty() or part == "." or part == "..":
			return false
	return true


static func safe_relative_campaign_path(path: String) -> bool:
	return safe_archive_path(path) and not path.begins_with(CAMPAIGN_PREFIX)


static func extension_allowed(path: String) -> bool:
	return ALLOWED_EXTENSIONS.has(path.get_extension().to_lower())


static func semantic_version_valid(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?$") == OK and regex.search(value) != null


static func sha256_bytes(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(data) != OK:
		return ""
	return context.finish().hex_encode()


static func parse_json_bytes(data: PackedByteArray, label: String) -> Dictionary:
	var parser := JSON.new()
	var error := parser.parse(data.get_string_from_utf8())
	if error != OK:
		return {"ok": false, "errors": ["%s:%d: %s" % [label, parser.get_error_line(), parser.get_error_message()]], "data": {}}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["%s must contain a JSON object." % label], "data": {}}
	return {"ok": true, "errors": [], "data": parser.data}


static func remove_tree(path: String) -> Error:
	var directory := DirAccess.open(path)
	if directory == null:
		return DirAccess.remove_absolute(path) if FileAccess.file_exists(path) else OK
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.is_link(entry) or not directory.current_is_dir():
			DirAccess.remove_absolute(child)
		else:
			remove_tree(child)
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(path)


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) == TYPE_ARRAY:
		for message in value:
			target.append(str(message))


static func fail(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
