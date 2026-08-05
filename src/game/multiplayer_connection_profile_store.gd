@tool
extends RefCounted

const MultiplayerConnectionProfile = preload("res://src/game/multiplayer_connection_profile.gd")

const ROOT := "user://settings"
const PROFILE_FILENAME := "multiplayer_connection.json"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"


static func profile_path(root_path: String = ROOT) -> String:
	return root_path.path_join(PROFILE_FILENAME)


static func backup_path(root_path: String = ROOT) -> String:
	return profile_path(root_path) + BACKUP_SUFFIX


static func temp_path(root_path: String = ROOT) -> String:
	return profile_path(root_path) + TEMP_SUFFIX


static func load_profile(
	default_port: int = MultiplayerConnectionProfile.DEFAULT_PORT,
	default_name: String = "WANDERER",
	root_path: String = ROOT
) -> Dictionary:
	var final_path := profile_path(root_path)
	var fallback_path := backup_path(root_path)
	if not FileAccess.file_exists(final_path):
		if FileAccess.file_exists(fallback_path):
			var backup_only := read_profile_path(
				fallback_path,
				default_port,
				default_name
			)
			if bool(backup_only.get("ok", false)):
				backup_only["recovered_from_backup"] = true
				backup_only["used_defaults"] = false
				backup_only["errors"] = []
				return backup_only
		return {
			"ok": true,
			"profile": MultiplayerConnectionProfile.default_profile(
				default_port,
				default_name
			),
			"path": final_path,
			"migrated": false,
			"recovered_from_backup": false,
			"used_defaults": true,
			"errors": []
		}
	var primary := read_profile_path(final_path, default_port, default_name)
	if bool(primary.get("ok", false)):
		return primary
	if FileAccess.file_exists(fallback_path):
		var backup := read_profile_path(fallback_path, default_port, default_name)
		if bool(backup.get("ok", false)):
			backup["recovered_from_backup"] = true
			backup["used_defaults"] = false
			backup["errors"] = []
			return backup
	return {
		"ok": true,
		"profile": MultiplayerConnectionProfile.default_profile(
			default_port,
			default_name
		),
		"path": final_path,
		"migrated": false,
		"recovered_from_backup": false,
		"used_defaults": true,
		"errors": primary.get("errors", [])
	}


static func read_profile_path(
	path: String,
	default_port: int = MultiplayerConnectionProfile.DEFAULT_PORT,
	default_name: String = "WANDERER"
) -> Dictionary:
	var raw := read_json(path)
	if not bool(raw.get("ok", false)):
		return {
			"ok": false,
			"profile": {},
			"path": path,
			"migrated": false,
			"recovered_from_backup": false,
			"used_defaults": false,
			"errors": raw.get("errors", [])
		}
	var migration := MultiplayerConnectionProfile.migrate(
		normalize_json_profile(raw.get("data", {})),
		default_port,
		default_name
	)
	if not bool(migration.get("ok", false)):
		return {
			"ok": false,
			"profile": {},
			"path": path,
			"migrated": false,
			"recovered_from_backup": false,
			"used_defaults": false,
			"errors": migration.get("errors", [])
		}
	return {
		"ok": true,
		"profile": migration.get(
			"profile",
			MultiplayerConnectionProfile.default_profile(
				default_port,
				default_name
			)
		),
		"path": path,
		"migrated": bool(migration.get("migrated", false)),
		"from_version": int(
			migration.get(
				"from_version",
				MultiplayerConnectionProfile.CURRENT_SCHEMA
			)
		),
		"recovered_from_backup": false,
		"used_defaults": false,
		"errors": []
	}


static func write_profile(
	profile: Dictionary,
	default_port: int = MultiplayerConnectionProfile.DEFAULT_PORT,
	default_name: String = "WANDERER",
	root_path: String = ROOT
) -> Dictionary:
	var final_path := profile_path(root_path)
	var temporary_path := temp_path(root_path)
	var fallback_path := backup_path(root_path)
	var validation := MultiplayerConnectionProfile.validate(profile)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"path": final_path,
			"errors": validation.get("errors", [])
		}
	var sanitized := MultiplayerConnectionProfile.sanitize(
		profile,
		default_port,
		default_name
	)
	var sanitized_validation := MultiplayerConnectionProfile.validate(sanitized)
	if not bool(sanitized_validation.get("ok", false)):
		return {
			"ok": false,
			"path": final_path,
			"errors": sanitized_validation.get("errors", [])
		}
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(root_path)
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {
			"ok": false,
			"path": final_path,
			"errors": [
				"Could not create the multiplayer connection settings directory (error %d)." % directory_error
			]
		}
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"path": final_path,
			"errors": ["Could not open the temporary multiplayer connection profile."]
		}
	file.store_string(JSON.stringify(sanitized, "\t", true) + "\n")
	file.flush()
	file.close()

	var absolute_final := ProjectSettings.globalize_path(final_path)
	var absolute_temp := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(fallback_path)
	var rotated_valid_existing := false
	if FileAccess.file_exists(final_path):
		var existing := read_profile_path(
			final_path,
			default_port,
			default_name
		)
		if bool(existing.get("ok", false)):
			if FileAccess.file_exists(fallback_path):
				DirAccess.remove_absolute(absolute_backup)
			var backup_error := DirAccess.rename_absolute(
				absolute_final,
				absolute_backup
			)
			if backup_error != OK:
				DirAccess.remove_absolute(absolute_temp)
				return {
					"ok": false,
					"path": final_path,
					"errors": [
						"Could not rotate the previous multiplayer connection profile into a backup (error %d)." % backup_error
					]
				}
			rotated_valid_existing = true
		else:
			var remove_invalid_error := DirAccess.remove_absolute(
				absolute_final
			)
			if remove_invalid_error != OK:
				DirAccess.remove_absolute(absolute_temp)
				return {
					"ok": false,
					"path": final_path,
					"errors": [
						"Could not remove the invalid multiplayer connection profile (error %d)." % remove_invalid_error
					]
				}
	var promote_error := DirAccess.rename_absolute(
		absolute_temp,
		absolute_final
	)
	if promote_error != OK:
		if rotated_valid_existing and FileAccess.file_exists(fallback_path):
			DirAccess.rename_absolute(absolute_backup, absolute_final)
		return {
			"ok": false,
			"path": final_path,
			"errors": [
				"Could not promote the multiplayer connection profile (error %d)." % promote_error
			]
		}
	return {
		"ok": true,
		"path": final_path,
		"backup_path": (
			fallback_path if FileAccess.file_exists(fallback_path) else ""
		),
		"profile": sanitized,
		"errors": []
	}


static func delete_profile(root_path: String = ROOT) -> Dictionary:
	var removed := false
	for path in [
		profile_path(root_path),
		backup_path(root_path),
		temp_path(root_path)
	]:
		if not FileAccess.file_exists(path):
			continue
		var error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path)
		)
		if error != OK:
			return {
				"ok": false,
				"removed": removed,
				"errors": [
					"Could not remove %s (error %d)." % [path, error]
				]
			}
		removed = true
	var absolute_root := ProjectSettings.globalize_path(root_path)
	if DirAccess.dir_exists_absolute(absolute_root):
		DirAccess.remove_absolute(absolute_root)
	return {"ok": true, "removed": removed, "errors": []}


static func normalize_json_profile(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return value
	var output: Dictionary = (value as Dictionary).duplicate(true)
	normalize_integer_field(output, "schema_version")
	normalize_integer_field(output, "port")
	return output


static func normalize_integer_field(source: Dictionary, key: String) -> void:
	if not source.has(key):
		return
	var value: Variant = source.get(key)
	if typeof(value) != TYPE_FLOAT:
		return
	var number := float(value)
	if (
		not is_nan(number)
		and not is_inf(number)
		and floor(number) == number
	):
		source[key] = int(number)


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"data": {},
			"errors": [
				"Multiplayer connection profile does not exist: %s" % path
			]
		}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"data": {},
			"errors": [
				"Could not open multiplayer connection profile: %s" % path
			]
		}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		return {
			"ok": false,
			"data": {},
			"errors": [
				"%s:%d: %s" % [
					path,
					parser.get_error_line(),
					parser.get_error_message()
				]
			]
		}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"data": {},
			"errors": [
				"Multiplayer connection profile root must be an object: %s" % path
			]
		}
	return {"ok": true, "data": parser.data, "errors": []}
