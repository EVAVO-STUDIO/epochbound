@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")

const SUPPORTED_SCHEMA := 1
const DEFAULT_PROFILE_ID := "heritage_adventure"


static func default_catalog() -> Dictionary:
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"profiles": [default_profile()],
		"bindings": []
	}


static func default_profile() -> Dictionary:
	return {
		"id": DEFAULT_PROFILE_ID,
		"display_name": "Heritage Adventure",
		"palette": {
			"ink": "13161a",
			"shadow": "263033",
			"midtone": "59665c",
			"light": "d7c99b",
			"accent": "d49a45",
			"danger": "b94d45",
			"ui_fill": "15191b",
			"ui_frame": "9f8651",
			"ui_text": "eee3c6"
		},
		"camera": {
			"follow_strength": 8.0,
			"deadzone": 20.0,
			"look_ahead": 18.0,
			"maximum_shake": 5.0
		},
		"atmosphere": {
			"kind": "motes",
			"density": 18,
			"speed": 8.0,
			"opacity": 0.24
		},
		"screen": {
			"scanline_alpha": 0.035,
			"vignette_alpha": 0.24,
			"dither_alpha": 0.07
		},
		"actors": {
			"movement_bob": 1.6,
			"shadow_scale": 1.0
		}
	}


static func safe_relative_json_path(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or not path.ends_with(".json"):
		return false
	for part in path.replace("\\", "/").split("/", false):
		if part == "." or part == ".." or part.is_empty():
			return false
	return true


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var files: Array[Dictionary] = []
	var definitions: Dictionary = {}
	var bindings: Array[Dictionary] = []
	var sources: Dictionary = {}
	var file_value: Variant = campaign.get("presentation_files", [])
	if typeof(file_value) != TYPE_ARRAY:
		errors.append("%s: presentation_files must be an array." % campaign.get("id", campaign_path))
		return make_result(errors, warnings, files, definitions, bindings, sources)
	var relative_files: Array = file_value as Array
	if relative_files.is_empty():
		warnings.append("%s: no presentation catalog is declared; the built-in heritage profile will be used." % campaign.get("id", campaign_path))
		merge_profile(default_profile(), "built-in default", definitions, sources, errors)
		return make_result(errors, warnings, files, definitions, bindings, sources)
	for relative_value in relative_files:
		var relative_path := str(relative_value)
		if not safe_relative_json_path(relative_path):
			errors.append("%s: unsafe presentation catalog path '%s'." % [campaign.get("id", campaign_path), relative_path])
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result: Dictionary = Repository.read_json(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		if int(data.get("schema_version", 0)) != SUPPORTED_SCHEMA:
			errors.append("%s: unsupported presentation schema %s; expected %d." % [path, data.get("schema_version", "missing"), SUPPORTED_SCHEMA])
		files.append({"path": path, "relative_path": relative_path, "data": data})
		var profiles_value: Variant = data.get("profiles", [])
		if typeof(profiles_value) != TYPE_ARRAY:
			errors.append("%s: profiles must be an array." % path)
		else:
			for profile_value in profiles_value as Array:
				if typeof(profile_value) != TYPE_DICTIONARY:
					errors.append("%s: every presentation profile must be an object." % path)
					continue
				merge_profile(profile_value as Dictionary, path, definitions, sources, errors)
		var bindings_value: Variant = data.get("bindings", [])
		if typeof(bindings_value) != TYPE_ARRAY:
			errors.append("%s: bindings must be an array." % path)
		else:
			for binding_value in bindings_value as Array:
				if typeof(binding_value) == TYPE_DICTIONARY:
					var binding: Dictionary = (binding_value as Dictionary).duplicate(true)
					binding["_source"] = path
					bindings.append(binding)
				else:
					errors.append("%s: every presentation binding must be an object." % path)
	if definitions.is_empty():
		warnings.append("No valid presentation profiles were loaded; the built-in heritage profile will be used.")
		merge_profile(default_profile(), "built-in default", definitions, sources, errors)
	return make_result(errors, warnings, files, definitions, bindings, sources)


static func merge_profile(
	profile_data: Dictionary,
	source: String,
	definitions: Dictionary,
	sources: Dictionary,
	errors: Array[String]
) -> void:
	var profile_id := str(profile_data.get("id", ""))
	if profile_id.is_empty():
		errors.append("%s: presentation profile id is required." % source)
		return
	if definitions.has(profile_id):
		errors.append("%s: presentation profile '%s' is also declared by %s." % [source, profile_id, sources.get(profile_id, "another catalog")])
		return
	definitions[profile_id] = profile_data.duplicate(true)
	sources[profile_id] = source


static func make_result(
	errors: Array[String],
	warnings: Array[String],
	files: Array[Dictionary],
	definitions: Dictionary,
	bindings: Array[Dictionary],
	sources: Dictionary
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"files": files,
		"definitions": definitions,
		"bindings": bindings,
		"sources": sources
	}


static func primary_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	var value: Variant = campaign.get("presentation_files", [])
	if typeof(value) == TYPE_ARRAY:
		for relative_value in value as Array:
			var relative_path := str(relative_value)
			if safe_relative_json_path(relative_path):
				return campaign_path.get_base_dir().path_join(relative_path)
	return campaign_path.get_base_dir().path_join("presentation").path_join("core.json")


static func profile(definitions: Dictionary, profile_id: String) -> Dictionary:
	var value: Variant = definitions.get(profile_id, {})
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func resolved_profile(
	definitions: Dictionary,
	bindings: Array,
	map_id: String,
	era_id: String
) -> Dictionary:
	var best_profile_id := ""
	var best_score := -1
	for binding_value in bindings:
		if typeof(binding_value) != TYPE_DICTIONARY:
			continue
		var binding: Dictionary = binding_value
		var bound_map := str(binding.get("map_id", "*"))
		var bound_era := str(binding.get("era_id", "*"))
		if bound_map != "*" and bound_map != map_id:
			continue
		if bound_era != "*" and bound_era != era_id:
			continue
		var score := 0
		if bound_map == map_id:
			score += 2
		if bound_era == era_id:
			score += 1
		if score > best_score:
			best_score = score
			best_profile_id = str(binding.get("profile_id", ""))
	if not best_profile_id.is_empty():
		var bound_profile: Dictionary = profile(definitions, best_profile_id)
		if not bound_profile.is_empty():
			return bound_profile
	var fallback: Dictionary = profile(definitions, DEFAULT_PROFILE_ID)
	if not fallback.is_empty():
		return fallback
	var ids := PackedStringArray()
	for profile_id_value in definitions.keys():
		ids.append(str(profile_id_value))
	ids.sort()
	if not ids.is_empty():
		return profile(definitions, ids[0])
	return default_profile()


static func palette_color(profile_data: Dictionary, key: String, fallback: String) -> Color:
	var palette_value: Variant = profile_data.get("palette", {})
	if typeof(palette_value) != TYPE_DICTIONARY:
		return Color.from_string(fallback, Color.WHITE)
	var value := str((palette_value as Dictionary).get(key, fallback))
	return Color.from_string(value, Color.from_string(fallback, Color.WHITE))


static func number(
	profile_data: Dictionary,
	section: String,
	key: String,
	fallback: float
) -> float:
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) != TYPE_DICTIONARY:
		return fallback
	return float((section_value as Dictionary).get(key, fallback))


static func integer(
	profile_data: Dictionary,
	section: String,
	key: String,
	fallback: int
) -> int:
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) != TYPE_DICTIONARY:
		return fallback
	return int((section_value as Dictionary).get(key, fallback))


static func text(
	profile_data: Dictionary,
	section: String,
	key: String,
	fallback: String
) -> String:
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) != TYPE_DICTIONARY:
		return fallback
	return str((section_value as Dictionary).get(key, fallback))


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value as Array:
		target.append(str(message))
