@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")

const SUPPORTED_SCHEMA := 1
const DEFAULT_PROFILE_ID := "museum_after_hours"
const REST_STEP := -99


static func default_catalog() -> Dictionary:
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"title_profile_id": DEFAULT_PROFILE_ID,
		"profiles": [default_profile()],
		"boss_stems": [],
		"bindings": []
	}


static func default_profile() -> Dictionary:
	return {
		"id": DEFAULT_PROFILE_ID,
		"display_name": "Museum After Hours",
		"music": {
			"tempo_bpm": 78.0,
			"root_midi": 45,
			"scale": [0, 2, 3, 7, 9],
			"melody_steps": [0, REST_STEP, 2, REST_STEP, 4, 3, 2, REST_STEP],
			"bass_steps": [0, REST_STEP, REST_STEP, REST_STEP, 3, REST_STEP, 1, REST_STEP],
			"waveform": "triangle",
			"pulse_width": 0.35,
			"gain": 0.16,
			"combat_gain": 0.06
		},
		"ambience": {
			"kind": "room_tone",
			"gain": 0.055,
			"tone_hz": 52.0,
			"motion": 0.22
		},
		"mix": {
			"menu_duck": 0.45,
			"cinematic_duck": 0.28,
			"pause_duck": 0.20,
			"crossfade_seconds": 0.90
		}
	}


static func safe_relative_json_path(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or not path.ends_with(".json"):
		return false
	for part in path.replace("\\", "/").split("/", false):
		if part.is_empty() or part == "." or part == "..":
			return false
	return true


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var files: Array[Dictionary] = []
	var definitions: Dictionary = {}
	var bindings: Array[Dictionary] = []
	var sources: Dictionary = {}
	var boss_stems: Dictionary = {}
	var boss_stem_sources: Dictionary = {}
	var title_profile_id := DEFAULT_PROFILE_ID
	var value: Variant = campaign.get("audio_files", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: audio_files must be an array." % campaign.get("id", campaign_path))
		return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)
	var relative_files: Array = value as Array
	if relative_files.is_empty():
		warnings.append("%s: no audio catalogue is declared; the built-in audio profile will be used." % campaign.get("id", campaign_path))
		merge_profile(default_profile(), "built-in default", definitions, sources, errors)
		return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)
	for relative_value in relative_files:
		var relative_path := str(relative_value)
		if not safe_relative_json_path(relative_path):
			errors.append("%s: unsafe audio catalogue path '%s'." % [campaign.get("id", campaign_path), relative_path])
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result: Dictionary = Repository.read_json(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		if int(data.get("schema_version", 0)) != SUPPORTED_SCHEMA:
			errors.append("%s: unsupported audio catalogue schema version." % path)
			continue
		files.append({"path": path, "relative_path": relative_path, "data": data})
		var authored_title := str(data.get("title_profile_id", "")).strip_edges()
		if not authored_title.is_empty():
			title_profile_id = authored_title
		var profiles_value: Variant = data.get("profiles", [])
		if typeof(profiles_value) != TYPE_ARRAY:
			errors.append("%s: profiles must be an array." % path)
		else:
			for profile_value in profiles_value as Array:
				if typeof(profile_value) != TYPE_DICTIONARY:
					errors.append("%s: every audio profile must be an object." % path)
					continue
				merge_profile(profile_value as Dictionary, path, definitions, sources, errors)
		var stems_value: Variant = data.get("boss_stems", [])
		if typeof(stems_value) != TYPE_ARRAY:
			errors.append("%s: boss_stems must be an array." % path)
		else:
			for stem_value in stems_value as Array:
				if typeof(stem_value) != TYPE_DICTIONARY:
					errors.append("%s: every boss stem must be an object." % path)
					continue
				merge_boss_stem(
					stem_value as Dictionary,
					path,
					boss_stems,
					boss_stem_sources,
					errors
				)
		var bindings_value: Variant = data.get("bindings", [])
		if typeof(bindings_value) != TYPE_ARRAY:
			errors.append("%s: bindings must be an array." % path)
		else:
			for binding_value in bindings_value as Array:
				if typeof(binding_value) != TYPE_DICTIONARY:
					errors.append("%s: every audio binding must be an object." % path)
					continue
				var binding: Dictionary = (binding_value as Dictionary).duplicate(true)
				binding["_source"] = path
				bindings.append(binding)
	if definitions.is_empty():
		warnings.append("No valid audio profiles were loaded; the built-in audio profile will be used.")
		merge_profile(default_profile(), "built-in default", definitions, sources, errors)
	if not definitions.has(title_profile_id):
		warnings.append("Title audio profile '%s' is unavailable; the default profile will be used." % title_profile_id)
		title_profile_id = DEFAULT_PROFILE_ID
	return make_result(errors, warnings, files, definitions, bindings, sources, title_profile_id, boss_stems, boss_stem_sources)


static func merge_profile(
	profile_data: Dictionary,
	source: String,
	definitions: Dictionary,
	sources: Dictionary,
	errors: Array[String]
) -> void:
	var profile_id := str(profile_data.get("id", "")).strip_edges()
	if profile_id.is_empty():
		errors.append("%s: audio profile id is required." % source)
		return
	if definitions.has(profile_id):
		errors.append("%s: audio profile '%s' is also declared by %s." % [source, profile_id, sources.get(profile_id, "another catalogue")])
		return
	definitions[profile_id] = profile_data.duplicate(true)
	sources[profile_id] = source


static func boss_stem_key(boss_id: String, phase_id: String) -> String:
	return "%s|%s" % [boss_id.strip_edges(), phase_id.strip_edges()]


static func merge_boss_stem(
	stem_data: Dictionary,
	source: String,
	definitions: Dictionary,
	sources: Dictionary,
	errors: Array[String]
) -> void:
	var boss_id := str(stem_data.get("boss_id", "")).strip_edges()
	var phase_id := str(stem_data.get("phase_id", "")).strip_edges()
	var key := boss_stem_key(boss_id, phase_id)
	if boss_id.is_empty() or phase_id.is_empty():
		errors.append("%s: boss stem requires boss_id and phase_id." % source)
		return
	if definitions.has(key):
		errors.append("%s: boss stem '%s' is also declared by %s." % [source, key, sources.get(key, "another catalogue")])
		return
	definitions[key] = stem_data.duplicate(true)
	sources[key] = source


static func boss_stem(definitions: Dictionary, boss_id: String, phase_id: String) -> Dictionary:
	var value: Variant = definitions.get(boss_stem_key(boss_id, phase_id), {})
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func boss_stem_number(stem_data: Dictionary, key: String, fallback: float) -> float:
	return float(stem_data.get(key, fallback))


static func boss_stem_text(stem_data: Dictionary, key: String, fallback: String) -> String:
	return str(stem_data.get(key, fallback))


static func boss_stem_integer_array(
	stem_data: Dictionary,
	key: String,
	fallback: Array[int]
) -> Array[int]:
	var output: Array[int] = []
	var value: Variant = stem_data.get(key, [])
	if typeof(value) == TYPE_ARRAY:
		for entry_value in value as Array:
			output.append(int(entry_value))
	if output.is_empty():
		for entry in fallback:
			output.append(entry)
	return output


static func make_result(
	errors: Array[String],
	warnings: Array[String],
	files: Array[Dictionary],
	definitions: Dictionary,
	bindings: Array[Dictionary],
	sources: Dictionary,
	title_profile_id: String,
	boss_stems: Dictionary,
	boss_stem_sources: Dictionary
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"files": files,
		"definitions": definitions,
		"bindings": bindings,
		"sources": sources,
		"title_profile_id": title_profile_id,
		"boss_stems": boss_stems,
		"boss_stem_sources": boss_stem_sources
	}


static func primary_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	var value: Variant = campaign.get("audio_files", [])
	if typeof(value) == TYPE_ARRAY:
		for relative_value in value as Array:
			var relative_path := str(relative_value)
			if safe_relative_json_path(relative_path):
				return campaign_path.get_base_dir().path_join(relative_path)
	return campaign_path.get_base_dir().path_join("audio").path_join("core.json")


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
		var bound_profile := profile(definitions, best_profile_id)
		if not bound_profile.is_empty():
			return bound_profile
	var fallback := profile(definitions, DEFAULT_PROFILE_ID)
	if not fallback.is_empty():
		return fallback
	var ids := PackedStringArray()
	for profile_id_value in definitions.keys():
		ids.append(str(profile_id_value))
	ids.sort()
	if not ids.is_empty():
		return profile(definitions, ids[0])
	return default_profile()


static func title_profile(definitions: Dictionary, title_profile_id: String) -> Dictionary:
	var value := profile(definitions, title_profile_id)
	if not value.is_empty():
		return value
	return resolved_profile(definitions, [], "", "")


static func number(profile_data: Dictionary, section: String, key: String, fallback: float) -> float:
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) != TYPE_DICTIONARY:
		return fallback
	return float((section_value as Dictionary).get(key, fallback))


static func integer(profile_data: Dictionary, section: String, key: String, fallback: int) -> int:
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) != TYPE_DICTIONARY:
		return fallback
	return int((section_value as Dictionary).get(key, fallback))


static func text(profile_data: Dictionary, section: String, key: String, fallback: String) -> String:
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) != TYPE_DICTIONARY:
		return fallback
	return str((section_value as Dictionary).get(key, fallback))


static func integer_array(profile_data: Dictionary, section: String, key: String, fallback: Array[int]) -> Array[int]:
	var output: Array[int] = []
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) == TYPE_DICTIONARY:
		var value: Variant = (section_value as Dictionary).get(key, [])
		if typeof(value) == TYPE_ARRAY:
			for entry_value in value as Array:
				output.append(int(entry_value))
	if output.is_empty():
		for entry in fallback:
			output.append(entry)
	return output


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value as Array:
		target.append(str(message))
