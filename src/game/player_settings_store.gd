@tool
extends RefCounted

const PlayerSettings = preload("res://src/game/player_settings.gd")

const ROOT := "user://settings"
const SETTINGS_PATH := ROOT + "/player_settings.json"
const TEMP_PATH := SETTINGS_PATH + ".tmp"
const BACKUP_PATH := SETTINGS_PATH + ".bak"


static func settings_path() -> String:
	return SETTINGS_PATH


static func backup_path() -> String:
	return BACKUP_PATH


static func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return {
			"ok": true,
			"settings": PlayerSettings.default_settings(),
			"path": SETTINGS_PATH,
			"migrated": false,
			"recovered_from_backup": false,
			"used_defaults": true,
			"errors": []
		}
	var primary := read_settings_path(SETTINGS_PATH)
	if bool(primary.get("ok", false)):
		return primary
	if FileAccess.file_exists(BACKUP_PATH):
		var backup := read_settings_path(BACKUP_PATH)
		if bool(backup.get("ok", false)):
			backup["recovered_from_backup"] = true
			backup["used_defaults"] = false
			backup["errors"] = []
			return backup
	return {
		"ok": true,
		"settings": PlayerSettings.default_settings(),
		"path": SETTINGS_PATH,
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


static func write_settings(settings: Dictionary) -> Dictionary:
	var sanitized := PlayerSettings.sanitize(settings)
	var validation := PlayerSettings.validate(sanitized)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "path": SETTINGS_PATH, "errors": validation.get("errors", [])}
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "path": SETTINGS_PATH, "errors": ["Could not create the player settings directory (error %d)." % directory_error]}
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": SETTINGS_PATH, "errors": ["Could not open the temporary player settings file."]}
	file.store_string(JSON.stringify(sanitized, "\t", true) + "\n")
	file.flush()
	file.close()

	var absolute_final := ProjectSettings.globalize_path(SETTINGS_PATH)
	var absolute_temp := ProjectSettings.globalize_path(TEMP_PATH)
	var absolute_backup := ProjectSettings.globalize_path(BACKUP_PATH)
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(absolute_backup)
	var had_existing := FileAccess.file_exists(SETTINGS_PATH)
	if had_existing:
		var backup_error := DirAccess.rename_absolute(absolute_final, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temp)
			return {"ok": false, "path": SETTINGS_PATH, "errors": ["Could not rotate the previous player settings into a backup (error %d)." % backup_error]}
	var promote_error := DirAccess.rename_absolute(absolute_temp, absolute_final)
	if promote_error != OK:
		if had_existing and FileAccess.file_exists(BACKUP_PATH):
			DirAccess.rename_absolute(absolute_backup, absolute_final)
		return {"ok": false, "path": SETTINGS_PATH, "errors": ["Could not promote the temporary player settings file (error %d)." % promote_error]}
	return {
		"ok": true,
		"path": SETTINGS_PATH,
		"backup_path": BACKUP_PATH if had_existing else "",
		"settings": sanitized,
		"errors": []
	}


static func rewrite_loaded_settings(read_result: Dictionary) -> Dictionary:
	if not bool(read_result.get("ok", false)):
		return {"ok": false, "path": SETTINGS_PATH, "errors": ["Cannot rewrite invalid player settings."]}
	var value: Variant = read_result.get("settings", {})
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "path": SETTINGS_PATH, "errors": ["Loaded player settings are missing."]}
	return write_settings(value as Dictionary)


static func delete_settings() -> Dictionary:
	var removed := false
	for path in [SETTINGS_PATH, BACKUP_PATH, TEMP_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			return {"ok": false, "removed": removed, "errors": ["Could not remove %s (error %d)." % [path, error]]}
		removed = true
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
