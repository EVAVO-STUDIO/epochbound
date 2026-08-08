@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/presentation_validator.gd")
const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const BossCatalog = preload("res://src/content/boss_catalog.gd")

const PROFILE_ID_PATTERN := "^[a-z0-9][a-z0-9_-]*$"
const WAVEFORMS := ["pulse", "triangle", "sine"]
const AMBIENCE_KINDS := ["room_tone", "pollen", "insects", "embers", "cinders", "machinery", "furnace", "wind", "rain"]


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var profile_count := 0
	var binding_count := 0
	var boss_stem_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := validate_audio_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		profile_count += int(report.get("audio_profile_count", 0))
		binding_count += int(report.get("audio_binding_count", 0))
		boss_stem_count += int(report.get("boss_stem_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["audio_profile_count"] = profile_count
	output["audio_binding_count"] = binding_count
	output["boss_stem_count"] = boss_stem_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_campaign_path(campaign_path)
	var audio_report := validate_audio_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, audio_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, audio_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["audio_profile_count"] = audio_report.get("audio_profile_count", 0)
	output["audio_binding_count"] = audio_report.get("audio_binding_count", 0)
	output["boss_stem_count"] = audio_report.get("boss_stem_count", 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	return BaseValidator.validate_profile(profile, campaign_path)


static func validate_audio_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var result: Dictionary = Repository.read_json(campaign_path)
	if not bool(result.get("ok", false)):
		append_messages(errors, result.get("errors", []))
		return make_report(errors, warnings, 0, 0)
	var campaign: Dictionary = result.get("data", {})
	var campaign_id := str(campaign.get("id", campaign_path))
	var files_value: Variant = campaign.get("audio_files", [])
	if typeof(files_value) != TYPE_ARRAY:
		errors.append("%s: audio_files must be an array." % campaign_id)
		return make_report(errors, warnings, 0, 0)
	var seen_paths: Dictionary = {}
	for relative_value in files_value as Array:
		var relative_path := str(relative_value)
		if not AudioMoodCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe audio catalogue path '%s'." % [campaign_id, relative_path])
		elif seen_paths.has(relative_path):
			errors.append("%s: audio_files repeats '%s'." % [campaign_id, relative_path])
		seen_paths[relative_path] = true
	var catalog_result := AudioMoodCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, catalog_result.get("errors", []))
	append_messages(warnings, catalog_result.get("warnings", []))
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var stems_value: Variant = catalog_result.get("boss_stems", {})
	var boss_stems: Dictionary = stems_value as Dictionary if typeof(stems_value) == TYPE_DICTIONARY else {}
	var stem_sources_value: Variant = catalog_result.get("boss_stem_sources", {})
	var boss_stem_sources: Dictionary = stem_sources_value as Dictionary if typeof(stem_sources_value) == TYPE_DICTIONARY else {}
	var object_result: Dictionary = ObjectCatalog.load_catalogs(campaign_path, campaign)
	var object_definitions_value: Variant = object_result.get("definitions", {})
	var object_definitions: Dictionary = object_definitions_value as Dictionary if typeof(object_definitions_value) == TYPE_DICTIONARY else {}
	if not bool(object_result.get("ok", false)):
		errors.append("%s: boss music stems could not resolve object definitions." % campaign_id)
	var stem_keys := PackedStringArray()
	for stem_key_value in boss_stems.keys():
		stem_keys.append(str(stem_key_value))
	stem_keys.sort()
	for stem_key in stem_keys:
		var stem_value: Variant = boss_stems.get(stem_key, {})
		if typeof(stem_value) != TYPE_DICTIONARY:
			continue
		validate_boss_stem_record(
			stem_value as Dictionary,
			str(boss_stem_sources.get(stem_key, campaign_id)),
			object_definitions,
			errors,
			warnings
		)
	for object_id_value in object_definitions.keys():
		var object_id := str(object_id_value)
		var definition_value: Variant = object_definitions.get(object_id, {})
		if typeof(definition_value) != TYPE_DICTIONARY:
			continue
		var definition_data: Dictionary = definition_value as Dictionary
		if not BossCatalog.is_boss(definition_data):
			continue
		for phase_value in BossCatalog.phases(definition_data):
			if typeof(phase_value) != TYPE_DICTIONARY:
				continue
			var phase_id := BossCatalog.phase_id(phase_value as Dictionary)
			if phase_id.is_empty():
				continue
			var stem_key := AudioMoodCatalog.boss_stem_key(object_id, phase_id)
			if not boss_stems.has(stem_key):
				warnings.append("%s: enabled boss phase '%s' has no authored boss music stem." % [campaign_id, stem_key])
	var bindings_value: Variant = catalog_result.get("bindings", [])
	var bindings: Array = bindings_value as Array if typeof(bindings_value) == TYPE_ARRAY else []
	var ids := PackedStringArray()
	for profile_id_value in definitions.keys():
		ids.append(str(profile_id_value))
	ids.sort()
	for profile_id in ids:
		var profile_data: Dictionary = definitions.get(profile_id, {})
		validate_profile_record(profile_data, str(catalog_result.get("sources", {}).get(profile_id, campaign_id)), errors, warnings)
	var title_profile_id := str(catalog_result.get("title_profile_id", ""))
	if title_profile_id.is_empty() or not definitions.has(title_profile_id):
		errors.append("%s: title_profile_id must reference a loaded audio profile." % campaign_id)
	var map_index := load_map_index(campaign_path, campaign, errors)
	var seen_bindings: Dictionary = {}
	var covered: Dictionary = {}
	for binding_value in bindings:
		if typeof(binding_value) != TYPE_DICTIONARY:
			continue
		var binding: Dictionary = binding_value
		var source := str(binding.get("_source", campaign_id))
		var map_id := str(binding.get("map_id", ""))
		var era_id := str(binding.get("era_id", "*"))
		var profile_id := str(binding.get("profile_id", ""))
		var key := "%s|%s" % [map_id, era_id]
		if map_id.is_empty():
			errors.append("%s: audio binding map_id is required." % source)
		elif map_id != "*" and not map_index.has(map_id):
			errors.append("%s: audio binding references unknown map '%s'." % [source, map_id])
		if profile_id.is_empty() or not definitions.has(profile_id):
			errors.append("%s: audio binding references unknown profile '%s'." % [source, profile_id])
		if seen_bindings.has(key):
			errors.append("%s: audio binding repeats map/era '%s'." % [source, key])
		seen_bindings[key] = true
		if map_id == "*":
			for known_map_value in map_index.keys():
				mark_coverage(covered, str(known_map_value), era_id, map_index)
		elif map_index.has(map_id):
			var eras: Dictionary = map_index.get(map_id, {})
			if era_id != "*" and not eras.has(era_id):
				errors.append("%s: audio binding references unknown era '%s' on map '%s'." % [source, era_id, map_id])
			else:
				mark_coverage(covered, map_id, era_id, map_index)
	for map_id_value in map_index.keys():
		var map_id := str(map_id_value)
		var eras: Dictionary = map_index.get(map_id, {})
		for era_id_value in eras.keys():
			var era_id := str(era_id_value)
			if not covered.has("%s|%s" % [map_id, era_id]):
				warnings.append("%s: map '%s' era '%s' has no explicit audio binding." % [campaign_id, map_id, era_id])
	return make_report(errors, warnings, definitions.size(), bindings.size(), boss_stems.size())


static func validate_profile_record(
	profile_data: Dictionary,
	source: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var profile_id := str(profile_data.get("id", ""))
	if not matches(PROFILE_ID_PATTERN, profile_id):
		errors.append("%s: audio profile id '%s' is invalid." % [source, profile_id])
	if str(profile_data.get("display_name", "")).strip_edges().is_empty():
		errors.append("%s/%s: display_name is required." % [source, profile_id])
	validate_number(profile_data, "music", "tempo_bpm", 40.0, 200.0, source, profile_id, errors)
	validate_integer(profile_data, "music", "root_midi", 24, 84, source, profile_id, errors)
	validate_number(profile_data, "music", "pulse_width", 0.10, 0.90, source, profile_id, errors)
	validate_number(profile_data, "music", "gain", 0.0, 0.45, source, profile_id, errors)
	validate_number(profile_data, "music", "combat_gain", 0.0, 0.30, source, profile_id, errors)
	var waveform := AudioMoodCatalog.text(profile_data, "music", "waveform", "")
	if not WAVEFORMS.has(waveform):
		errors.append("%s/%s/music: unsupported waveform '%s'." % [source, profile_id, waveform])
	validate_integer_sequence(profile_data, "music", "scale", 3, 8, -12, 24, false, source, profile_id, errors)
	validate_integer_sequence(profile_data, "music", "melody_steps", 4, 64, -99, 31, true, source, profile_id, errors)
	validate_integer_sequence(profile_data, "music", "bass_steps", 4, 64, -99, 31, true, source, profile_id, errors)
	var ambience_kind := AudioMoodCatalog.text(profile_data, "ambience", "kind", "")
	if not AMBIENCE_KINDS.has(ambience_kind):
		errors.append("%s/%s/ambience: unsupported kind '%s'." % [source, profile_id, ambience_kind])
	validate_number(profile_data, "ambience", "gain", 0.0, 0.30, source, profile_id, errors)
	validate_number(profile_data, "ambience", "tone_hz", 20.0, 1200.0, source, profile_id, errors)
	validate_number(profile_data, "ambience", "motion", 0.0, 1.0, source, profile_id, errors)
	validate_number(profile_data, "mix", "menu_duck", 0.05, 1.0, source, profile_id, errors)
	validate_number(profile_data, "mix", "cinematic_duck", 0.05, 1.0, source, profile_id, errors)
	validate_number(profile_data, "mix", "pause_duck", 0.05, 1.0, source, profile_id, errors)
	validate_number(profile_data, "mix", "crossfade_seconds", 0.05, 4.0, source, profile_id, errors)
	if AudioMoodCatalog.number(profile_data, "music", "gain", 0.0) + AudioMoodCatalog.number(profile_data, "music", "combat_gain", 0.0) > 0.42:
		warnings.append("%s/%s: combined exploration and combat music gain may clip on small speakers." % [source, profile_id])


static func validate_boss_stem_record(
	stem_data: Dictionary,
	source: String,
	object_definitions: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var boss_id := str(stem_data.get("boss_id", "")).strip_edges()
	var phase_id := str(stem_data.get("phase_id", "")).strip_edges()
	var stem_key := AudioMoodCatalog.boss_stem_key(boss_id, phase_id)
	if not matches(PROFILE_ID_PATTERN, boss_id):
		errors.append("%s: boss stem boss_id '%s' is invalid." % [source, boss_id])
	if not matches(PROFILE_ID_PATTERN, phase_id):
		errors.append("%s: boss stem phase_id '%s' is invalid." % [source, phase_id])
	if str(stem_data.get("display_name", "")).strip_edges().is_empty():
		errors.append("%s/%s: display_name is required." % [source, stem_key])
	var definition_value: Variant = object_definitions.get(boss_id, {})
	var definition_data: Dictionary = definition_value as Dictionary if typeof(definition_value) == TYPE_DICTIONARY else {}
	if definition_data.is_empty():
		errors.append("%s/%s: boss_id references unknown object '%s'." % [source, stem_key, boss_id])
	else:
		if not BossCatalog.is_boss(definition_data):
			errors.append("%s/%s: boss_id must reference an enabled boss." % [source, stem_key])
		if BossCatalog.phase_by_id(definition_data, phase_id).is_empty():
			errors.append("%s/%s: phase_id references unknown boss phase '%s'." % [source, stem_key, phase_id])
	validate_boss_stem_number(stem_data, "tempo_multiplier", 0.5, 2.0, source, stem_key, errors)
	validate_boss_stem_integer(stem_data, "root_offset", -24, 24, source, stem_key, errors)
	validate_boss_stem_sequence(stem_data, "melody_steps", 4, 64, -99, 31, source, stem_key, errors)
	validate_boss_stem_sequence(stem_data, "bass_steps", 4, 64, -99, 31, source, stem_key, errors)
	var waveform := str(stem_data.get("waveform", ""))
	if not WAVEFORMS.has(waveform):
		errors.append("%s/%s: unsupported boss stem waveform '%s'." % [source, stem_key, waveform])
	validate_boss_stem_number(stem_data, "pulse_width", 0.10, 0.90, source, stem_key, errors)
	validate_boss_stem_number(stem_data, "gain", 0.0, 0.25, source, stem_key, errors)
	validate_boss_stem_number(stem_data, "percussion_gain", 0.0, 0.20, source, stem_key, errors)
	if float(stem_data.get("gain", 0.0)) + float(stem_data.get("percussion_gain", 0.0)) > 0.28:
		warnings.append("%s/%s: combined boss stem gain may mask combat feedback on small speakers." % [source, stem_key])


static func validate_boss_stem_sequence(
	stem_data: Dictionary,
	key: String,
	minimum_count: int,
	maximum_count: int,
	minimum_value: int,
	maximum_value: int,
	source: String,
	stem_key: String,
	errors: Array[String]
) -> void:
	var value: Variant = stem_data.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s/%s/%s must be an array." % [source, stem_key, key])
		return
	var entries: Array = value as Array
	if entries.size() < minimum_count or entries.size() > maximum_count:
		errors.append("%s/%s/%s must contain between %d and %d entries." % [source, stem_key, key, minimum_count, maximum_count])
	for entry_value in entries:
		if typeof(entry_value) != TYPE_INT and typeof(entry_value) != TYPE_FLOAT:
			errors.append("%s/%s/%s must contain only integers." % [source, stem_key, key])
			continue
		var entry := int(entry_value)
		if entry == AudioMoodCatalog.REST_STEP:
			continue
		if entry < minimum_value or entry > maximum_value:
			errors.append("%s/%s/%s entry %d is outside the supported range." % [source, stem_key, key, entry])


static func validate_boss_stem_number(
	stem_data: Dictionary,
	key: String,
	minimum: float,
	maximum: float,
	source: String,
	stem_key: String,
	errors: Array[String]
) -> void:
	var value: Variant = stem_data.get(key, null)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("%s/%s/%s must be numeric." % [source, stem_key, key])
		return
	var number_value := float(value)
	if number_value < minimum or number_value > maximum:
		errors.append("%s/%s/%s must be between %.2f and %.2f." % [source, stem_key, key, minimum, maximum])


static func validate_boss_stem_integer(
	stem_data: Dictionary,
	key: String,
	minimum: int,
	maximum: int,
	source: String,
	stem_key: String,
	errors: Array[String]
) -> void:
	var value: Variant = stem_data.get(key, null)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		errors.append("%s/%s/%s must be numeric." % [source, stem_key, key])
		return
	var integer_value := int(value)
	if integer_value < minimum or integer_value > maximum:
		errors.append("%s/%s/%s must be between %d and %d." % [source, stem_key, key, minimum, maximum])


static func validate_integer_sequence(
	profile_data: Dictionary,
	section: String,
	key: String,
	minimum_count: int,
	maximum_count: int,
	minimum_value: int,
	maximum_value: int,
	allow_rest: bool,
	source: String,
	profile_id: String,
	errors: Array[String]
) -> void:
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) != TYPE_DICTIONARY:
		errors.append("%s/%s: %s must be an object." % [source, profile_id, section])
		return
	var value: Variant = (section_value as Dictionary).get(key, [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s/%s/%s/%s must be an array." % [source, profile_id, section, key])
		return
	var entries: Array = value as Array
	if entries.size() < minimum_count or entries.size() > maximum_count:
		errors.append("%s/%s/%s/%s must contain between %d and %d entries." % [source, profile_id, section, key, minimum_count, maximum_count])
	for entry_value in entries:
		if typeof(entry_value) != TYPE_INT and typeof(entry_value) != TYPE_FLOAT:
			errors.append("%s/%s/%s/%s must contain only integers." % [source, profile_id, section, key])
			continue
		var entry := int(entry_value)
		if allow_rest and entry == AudioMoodCatalog.REST_STEP:
			continue
		if entry < minimum_value or entry > maximum_value:
			errors.append("%s/%s/%s/%s entry %d is outside the supported range." % [source, profile_id, section, key, entry])


static func validate_number(
	profile_data: Dictionary,
	section: String,
	key: String,
	minimum: float,
	maximum: float,
	source: String,
	profile_id: String,
	errors: Array[String]
) -> void:
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) != TYPE_DICTIONARY:
		errors.append("%s/%s: %s must be an object." % [source, profile_id, section])
		return
	var value: Variant = (section_value as Dictionary).get(key, null)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("%s/%s/%s/%s must be numeric." % [source, profile_id, section, key])
		return
	var number_value := float(value)
	if number_value < minimum or number_value > maximum:
		errors.append("%s/%s/%s/%s must be between %.2f and %.2f." % [source, profile_id, section, key, minimum, maximum])


static func validate_integer(
	profile_data: Dictionary,
	section: String,
	key: String,
	minimum: int,
	maximum: int,
	source: String,
	profile_id: String,
	errors: Array[String]
) -> void:
	var section_value: Variant = profile_data.get(section, {})
	if typeof(section_value) != TYPE_DICTIONARY:
		errors.append("%s/%s: %s must be an object." % [source, profile_id, section])
		return
	var value: Variant = (section_value as Dictionary).get(key, null)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		errors.append("%s/%s/%s/%s must be numeric." % [source, profile_id, section, key])
		return
	var integer_value := int(value)
	if integer_value < minimum or integer_value > maximum:
		errors.append("%s/%s/%s/%s must be between %d and %d." % [source, profile_id, section, key, minimum, maximum])


static func load_map_index(campaign_path: String, campaign: Dictionary, errors: Array[String]) -> Dictionary:
	var output: Dictionary = {}
	var value: Variant = campaign.get("map_files", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for relative_value in value as Array:
		var path := campaign_path.get_base_dir().path_join(str(relative_value))
		var result: Dictionary = Repository.read_json(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var map_data: Dictionary = result.get("data", {})
		var map_id := str(map_data.get("id", ""))
		var eras: Dictionary = {}
		var eras_value: Variant = map_data.get("eras", [])
		if typeof(eras_value) == TYPE_ARRAY:
			for era_value in eras_value as Array:
				if typeof(era_value) == TYPE_DICTIONARY:
					var era_id := str((era_value as Dictionary).get("id", ""))
					if not era_id.is_empty():
						eras[era_id] = true
		if not map_id.is_empty():
			output[map_id] = eras
	return output


static func mark_coverage(covered: Dictionary, map_id: String, era_id: String, map_index: Dictionary) -> void:
	var eras: Dictionary = map_index.get(map_id, {})
	if era_id == "*":
		for known_era_value in eras.keys():
			covered["%s|%s" % [map_id, str(known_era_value)]] = true
	elif eras.has(era_id):
		covered["%s|%s" % [map_id, era_id]] = true


static func matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func make_report(errors: Array[String], warnings: Array[String], profile_count: int, binding_count: int, boss_stem_count: int = 0) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"audio_profile_count": profile_count,
		"audio_binding_count": binding_count,
		"boss_stem_count": boss_stem_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value as Array:
		target.append(str(message))
