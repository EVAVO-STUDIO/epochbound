@tool
extends RefCounted

const PlayerInputBindings = preload("res://src/game/player_input_bindings.gd")
const PlayerSettings = preload("res://src/game/player_settings.gd")

const ROOT := "user://settings"
const SETTINGS_FILENAME := "player_settings.json"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"


static func settings_path(root_path: String = ROOT) -> String:
	return root_path.path_join(SETTINGS_FILENAME)


static func backup_path(root_path: String = ROOT) -> String:
	return settings_path(root_path) + BACKUP_SUFFIX


static func temp_path(root_path: String = ROOT) -> String:
	return settings_path(root_path) + TEMP_SUFFIX


static func load_settings(root_path: String = ROOT) -> Dictionary:
	var final_path := settings_path(root_path)
	var fallback_path := backup_path(root_path)
	if not FileAccess.file_exists(final_path):
		if FileAccess.file_exists(fallback_path):
			var backup_only := read_settings_path(fallback_path)
			if bool(backup_only.get("ok", false)):
				backup_only["recovered_from_backup"] = true
				backup_only["used_defaults"] = false
				backup_only["errors"] = []
				return backup_only
		return {
			"ok": true,
			"settings": PlayerSettings.default_settings(),
			"path": final_path,
			"migrated": false,
			"recovered_from_backup": false,
			"used_defaults": true,
			"errors": []
		}
	var primary := read_settings_path(final_path)
	if bool(primary.get("ok", false)):
		return primary
	if FileAccess.file_exists(fallback_path):
		var backup := read_settings_path(fallback_path)
		if bool(backup.get("ok", false)):
			backup["recovered_from_backup"] = true
			backup["used_defaults"] = false
			backup["errors"] = []
			return backup
	return {
		"ok": true,
		"settings": PlayerSettings.default_settings(),
		"path": final_path,
		"migrated": false,
		"recovered_from_backup": false,
		"used_defaults": true,
		"errors": primary.get("errors", [])
	}


static func read_settings_path(path: String) -> Dictionary:
	var raw := read_json(path)
	if not bool(raw.get("ok", false)):
		return {
			"ok": false,
			"settings": {},
			"path": path,
			"migrated": false,
			"recovered_from_backup": false,
			"used_defaults": false,
			"errors": raw.get("errors", [])
		}
	var migration := PlayerSettings.migrate(raw.get("data", {}))
	if not bool(migration.get("ok", false)):
		return {
			"ok": false,
			"settings": {},
			"path": path,
			"migrated": false,
			"recovered_from_backup": false,
			"used_defaults": false,
			"errors": migration.get("errors", [])
		}
	return {
		"ok": true,
		"settings": migration.get("settings", PlayerSettings.default_settings()),
		"path": path,
		"migrated": bool(migration.get("migrated", false)),
		"from_version": int(migration.get("from_version", PlayerSettings.CURRENT_SCHEMA)),
		"recovered_from_backup": false,
		"used_defaults": false,
		"errors": []
	}


static func validate_raw_input_bindings(settings: Dictionary, final_path: String) -> Dictionary:
	if not settings.has("input_bindings"):
		return {"ok": true, "errors": []}
	var validation := PlayerInputBindings.validate_profile(settings.get("input_bindings"))
	if bool(validation.get("ok", false)):
		return {"ok": true, "errors": []}
	return {
		"ok": false,
		"path": final_path,
		"errors": validation.get("errors", ["Input bindings are invalid."])
	}


static func write_settings(settings: Dictionary, root_path: String = ROOT) -> Dictionary:
	var final_path := settings_path(root_path)
	var temporary_path := temp_path(root_path)
	var fallback_path := backup_path(root_path)
	# Range and boolean preferences are intentionally sanitized, but controls
	# fail closed before sanitization so malformed descriptors cannot be silently
	# replaced and promoted over a known-good player profile.
	var binding_validation := validate_raw_input_bindings(settings, final_path)
	if not bool(binding_validation.get("ok", false)):
		return binding_validation
	var sanitized := PlayerSettings.sanitize(settings)
	var validation := PlayerSettings.validate(sanitized)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "path": final_path, "errors": validation.get("errors", [])}
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "path": final_path, "errors": ["Could not create the player settings directory (error %d)." % directory_error]}
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": final_path, "errors": ["Could not open the temporary player settings file."]}
	file.store_string(JSON.stringify(sanitized, "\t", true) + "\n")
	file.flush()
	file.close()

	var absolute_final := ProjectSettings.globalize_path(final_path)
	var absolute_temp := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(fallback_path)
	var had_existing := FileAccess.file_exists(final_path)
	var rotated_valid_existing := false
	if had_existing:
		var existing_result := read_settings_path(final_path)
		if bool(existing_result.get("ok", false)):
			if FileAccess.file_exists(fallback_path):
				DirAccess.remove_absolute(absolute_backup)
			var backup_error := DirAccess.rename_absolute(absolute_final, absolute_backup)
			if backup_error != OK:
				DirAccess.remove_absolute(absolute_temp)
				return {"ok": false, "path": final_path, "errors": ["Could not rotate the previous player settings into a backup (error %d)." % backup_error]}
			rotated_valid_existing = true
		else:
			var remove_invalid_error := DirAccess.remove_absolute(absolute_final)
			if remove_invalid_error != OK:
				DirAccess.remove_absolute(absolute_temp)
				return {"ok": false, "path": final_path, "errors": ["Could not remove invalid player settings before recovery (error %d)." % remove_invalid_error]}
	var promote_error := DirAccess.rename_absolute(absolute_temp, absolute_final)
	if promote_error != OK:
		if rotated_valid_existing and FileAccess.file_exists(fallback_path):
			DirAccess.rename_absolute(absolute_backup, absolute_final)
		return {"ok": false, "path": final_path, "errors": ["Could not promote the temporary player settings file (error %d)." % promote_error]}
	return {
		"ok": true,
		"path": final_path,
		"backup_path": fallback_path if FileAccess.file_exists(fallback_path) else "",
		"settings": sanitized,
		"errors": []
	}


static func rewrite_loaded_settings(read_result: Dictionary, root_path: String = ROOT) -> Dictionary:
	if not bool(read_result.get("ok", false)):
		return {"ok": false, "path": settings_path(root_path), "errors": ["Cannot rewrite invalid player settings."]}
	var value: Variant = read_result.get("settings", {})
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "path": settings_path(root_path), "errors": ["Loaded player settings are missing."]}
	return write_settings(value as Dictionary, root_path)


static func delete_settings(root_path: String = ROOT) -> Dictionary:
	var removed := false
	for path in [settings_path(root_path), backup_path(root_path), temp_path(root_path)]:
		if not FileAccess.file_exists(path):
			continue
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			return {"ok": false, "removed": removed, "errors": ["Could not remove %s (error %d)." % [path, error]]}
		removed = true
	var absolute_root := ProjectSettings.globalize_path(root_path)
	if DirAccess.dir_exists_absolute(absolute_root):
		DirAccess.remove_absolute(absolute_root)
	return {"ok": true, "removed": removed, "errors": []}


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "errors": ["Player settings file does not exist: %s" % path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}, "errors": ["Could not open player settings file: %s" % path]}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		return {"ok": false, "data": {}, "errors": ["%s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()]]}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "errors": ["Player settings root must be an object: %s" % path]}
	return {"ok": true, "data": parser.data, "errors": []}
