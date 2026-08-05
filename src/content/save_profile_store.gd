extends RefCounted

const SaveProfile = preload("res://src/content/save_profile.gd")

const ROOT := "user://save_profiles"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"


static func campaign_directory(campaign_id: String) -> String:
	return ROOT.path_join(normalise_component(campaign_id))


static func slot_path(campaign_id: String, slot_id: String) -> String:
	return campaign_directory(campaign_id).path_join("%s.json" % slot_id)


static func backup_path(campaign_id: String, slot_id: String) -> String:
	return slot_path(campaign_id, slot_id) + BACKUP_SUFFIX


static func write_profile(profile: Dictionary) -> Dictionary:
	var structural: Dictionary = SaveProfile.validate_structure(profile)
	if not bool(structural.get("ok", false)):
		return {"ok": false, "path": "", "errors": structural.get("errors", [])}
	var campaign_id: String = str(profile.get("campaign_id", ""))
	var slot_id: String = str(profile.get("slot_id", ""))
	if normalise_component(campaign_id) != campaign_id:
		return {"ok": false, "path": "", "errors": ["Save profile campaign_id is not a safe path component."]}
	if not SaveProfile.valid_slot_id(slot_id):
		return {"ok": false, "path": "", "errors": ["Save slot '%s' is invalid." % slot_id]}

	var directory: String = campaign_directory(campaign_id)
	var directory_error: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "path": "", "errors": ["Could not create save directory (error %d)." % directory_error]}

	var final_path: String = slot_path(campaign_id, slot_id)
	var temporary_path: String = final_path + TEMP_SUFFIX
	var existing_backup: String = backup_path(campaign_id, slot_id)
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": final_path, "errors": ["Could not open temporary save file for writing."]}
	file.store_string(JSON.stringify(SaveProfile.canonicalize(profile), "\t", true) + "\n")
	file.flush()
	file.close()

	var absolute_final: String = ProjectSettings.globalize_path(final_path)
	var absolute_temp: String = ProjectSettings.globalize_path(temporary_path)
	var absolute_backup: String = ProjectSettings.globalize_path(existing_backup)
	if FileAccess.file_exists(existing_backup):
		DirAccess.remove_absolute(absolute_backup)
	var had_existing: bool = FileAccess.file_exists(final_path)
	if had_existing:
		var backup_error: int = DirAccess.rename_absolute(absolute_final, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temp)
			return {"ok": false, "path": final_path, "errors": ["Could not rotate the previous save into a backup (error %d)." % backup_error]}
	var promote_error: int = DirAccess.rename_absolute(absolute_temp, absolute_final)
	if promote_error != OK:
		if had_existing and FileAccess.file_exists(existing_backup):
			DirAccess.rename_absolute(absolute_backup, absolute_final)
		return {"ok": false, "path": final_path, "errors": ["Could not promote the temporary save file (error %d)." % promote_error]}
	return {"ok": true, "path": final_path, "backup_path": existing_backup if had_existing else "", "errors": []}


static func read_profile(campaign_id: String, slot_id: String) -> Dictionary:
	if normalise_component(campaign_id) != campaign_id or not SaveProfile.valid_slot_id(slot_id):
		return {"ok": false, "profile": {}, "path": "", "migrated": false, "errors": ["Unsafe campaign or slot identifier."]}
	var path: String = slot_path(campaign_id, slot_id)
	var result: Dictionary = read_profile_path(path)
	if bool(result.get("ok", false)):
		return result
	var fallback_path: String = backup_path(campaign_id, slot_id)
	if not FileAccess.file_exists(fallback_path):
		return result
	var backup_result: Dictionary = read_profile_path(fallback_path)
	if bool(backup_result.get("ok", false)):
		backup_result["recovered_from_backup"] = true
		backup_result["errors"] = []
		return backup_result
	return result


static func read_profile_path(path: String) -> Dictionary:
	var raw_result: Dictionary = read_json(path)
	if not bool(raw_result.get("ok", false)):
		return {"ok": false, "profile": {}, "path": path, "migrated": false, "errors": raw_result.get("errors", [])}
	var raw_profile: Dictionary = raw_result.get("data", {})
	var migration: Dictionary = SaveProfile.migrate(raw_profile)
	if not bool(migration.get("ok", false)):
		return {"ok": false, "profile": {}, "path": path, "migrated": false, "errors": migration.get("errors", [])}
	var profile: Dictionary = migration.get("profile", {})
	var structural: Dictionary = SaveProfile.validate_structure(profile)
	if not bool(structural.get("ok", false)):
		return {"ok": false, "profile": profile, "path": path, "migrated": bool(migration.get("migrated", false)), "errors": structural.get("errors", [])}
	return {
		"ok": true,
		"profile": profile,
		"path": path,
		"migrated": bool(migration.get("migrated", false)),
		"from_version": int(migration.get("from_version", SaveProfile.CURRENT_SCHEMA)),
		"recovered_from_backup": false,
		"errors": []
	}


static func rewrite_migrated_profile(read_result: Dictionary) -> Dictionary:
	if not bool(read_result.get("ok", false)):
		return {"ok": false, "path": "", "errors": ["Cannot rewrite an invalid save profile."]}
	var profile_value: Variant = read_result.get("profile", {})
	if typeof(profile_value) != TYPE_DICTIONARY:
		return {"ok": false, "path": "", "errors": ["Save profile data is missing."]}
	var profile: Dictionary = profile_value
	SaveProfile.refresh_checksum(profile)
	return write_profile(profile)


static func delete_profile(campaign_id: String, slot_id: String) -> Dictionary:
	if normalise_component(campaign_id) != campaign_id or not SaveProfile.valid_slot_id(slot_id):
		return {"ok": false, "errors": ["Unsafe campaign or slot identifier."]}
	var removed_any := false
	for path in [slot_path(campaign_id, slot_id), backup_path(campaign_id, slot_id), slot_path(campaign_id, slot_id) + TEMP_SUFFIX]:
		if not FileAccess.file_exists(path):
			continue
		var error: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			return {"ok": false, "errors": ["Could not remove %s (error %d)." % [path, error]]}
		removed_any = true
	return {"ok": true, "removed": removed_any, "errors": []}


static func list_campaign_profiles(campaign_id: String) -> Array:
	var output: Array = []
	var directory_path: String = campaign_directory(campaign_id)
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return output
	directory.list_dir_begin()
	var filename: String = directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.ends_with(".json"):
			var filename_slot := filename.trim_suffix(".json")
			if SaveProfile.valid_slot_id(filename_slot):
				var result: Dictionary = read_profile_path(directory_path.path_join(filename))
				if bool(result.get("ok", false)):
					var profile: Dictionary = result.get("profile", {})
					if (
						str(profile.get("campaign_id", "")) == campaign_id
						and str(profile.get("slot_id", "")) == filename_slot
					):
						output.append({
							"slot_id": filename_slot,
							"path": str(result.get("path", "")),
							"profile": profile,
							"summary": SaveProfile.profile_summary(profile),
							"migrated": bool(result.get("migrated", false)),
							"recovered_from_backup": bool(result.get("recovered_from_backup", false))
						})
		filename = directory.get_next()
	directory.list_dir_end()
	output.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_summary: Dictionary = left.get("summary", {})
		var right_summary: Dictionary = right.get("summary", {})
		return int(left_summary.get("saved_at_unix", 0)) > int(right_summary.get("saved_at_unix", 0))
	)
	return output


static func list_all_profiles() -> Array:
	var output: Array = []
	var root_directory: DirAccess = DirAccess.open(ROOT)
	if root_directory == null:
		return output
	root_directory.list_dir_begin()
	var campaign_id: String = root_directory.get_next()
	while not campaign_id.is_empty():
		if root_directory.current_is_dir() and not campaign_id.begins_with("."):
			for record_value in list_campaign_profiles(campaign_id):
				if typeof(record_value) == TYPE_DICTIONARY:
					output.append(record_value)
		campaign_id = root_directory.get_next()
	root_directory.list_dir_end()
	output.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_summary: Dictionary = left.get("summary", {})
		var right_summary: Dictionary = right.get("summary", {})
		return int(left_summary.get("saved_at_unix", 0)) > int(right_summary.get("saved_at_unix", 0))
	)
	return output


static func latest_profile() -> Dictionary:
	var profiles: Array = list_all_profiles()
	if profiles.is_empty():
		return {"ok": false, "profile": {}, "path": "", "errors": ["No valid save profiles were found."]}
	var record: Dictionary = profiles[0]
	return {"ok": true, "profile": record.get("profile", {}), "path": record.get("path", ""), "errors": []}


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "errors": ["Save file does not exist: %s" % path]}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}, "errors": ["Could not open save file: %s" % path]}
	var parser: JSON = JSON.new()
	var error: int = parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		return {"ok": false, "data": {}, "errors": ["%s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()]]}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "errors": ["Save profile root must be an object: %s" % path]}
	return {"ok": true, "data": parser.data, "errors": []}


static func normalise_component(value: String) -> String:
	var source := value.strip_edges().to_lower()
	var output := ""
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789_-"
	for index in range(source.length()):
		var character := source.substr(index, 1)
		if allowed.contains(character):
			output += character
	return output.trim_prefix("_").trim_suffix("_")
