@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/audio_mood_validator.gd")
const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")

const INTEGER_SEQUENCE_KEYS := ["scale", "melody_steps", "bass_steps"]


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var output: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, output.get("errors", []))
	append_messages(warnings, output.get("warnings", []))
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report: Dictionary = validate_audio_integrity_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var output: Dictionary = BaseValidator.validate_campaign_path(campaign_path)
	var integrity: Dictionary = validate_audio_integrity_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, output.get("errors", []))
	append_messages(errors, integrity.get("errors", []))
	append_messages(warnings, output.get("warnings", []))
	append_messages(warnings, integrity.get("warnings", []))
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	return output


static func validate_audio_only(campaign_path: String) -> Dictionary:
	var output: Dictionary = BaseValidator.validate_audio_only(campaign_path)
	var integrity: Dictionary = validate_audio_integrity_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, output.get("errors", []))
	append_messages(errors, integrity.get("errors", []))
	append_messages(warnings, output.get("warnings", []))
	append_messages(warnings, integrity.get("warnings", []))
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	return BaseValidator.validate_profile(profile, campaign_path)


static func validate_profile_record(
	profile_data: Dictionary,
	source: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	BaseValidator.validate_profile_record(profile_data, source, errors, warnings)
	validate_integral_music_values(profile_data, source, errors)


static func validate_boss_stem_record(
	stem_data: Dictionary,
	source: String,
	object_definitions: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	BaseValidator.validate_boss_stem_record(stem_data, source, object_definitions, errors, warnings)
	validate_boss_stem_integral_values(stem_data, source, errors)


static func validate_audio_integrity_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result: Dictionary = Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings}
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog_result: Dictionary = AudioMoodCatalog.load_catalogs(campaign_path, campaign)
	if not bool(catalog_result.get("ok", false)):
		return {"ok": true, "errors": errors, "warnings": warnings}
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var sources_value: Variant = catalog_result.get("sources", {})
	var sources: Dictionary = sources_value as Dictionary if typeof(sources_value) == TYPE_DICTIONARY else {}
	var profile_ids := PackedStringArray()
	for profile_id_value in definitions.keys():
		profile_ids.append(str(profile_id_value))
	profile_ids.sort()
	for profile_id in profile_ids:
		var profile_value: Variant = definitions.get(profile_id, {})
		if typeof(profile_value) != TYPE_DICTIONARY:
			continue
		validate_integral_music_values(
			profile_value as Dictionary,
			str(sources.get(profile_id, campaign_path)),
			errors
		)
	var stems_value: Variant = catalog_result.get("boss_stems", {})
	var stems: Dictionary = stems_value as Dictionary if typeof(stems_value) == TYPE_DICTIONARY else {}
	var stem_sources_value: Variant = catalog_result.get("boss_stem_sources", {})
	var stem_sources: Dictionary = stem_sources_value as Dictionary if typeof(stem_sources_value) == TYPE_DICTIONARY else {}
	var stem_keys := PackedStringArray()
	for stem_key_value in stems.keys():
		stem_keys.append(str(stem_key_value))
	stem_keys.sort()
	for stem_key in stem_keys:
		var stem_value: Variant = stems.get(stem_key, {})
		if typeof(stem_value) != TYPE_DICTIONARY:
			continue
		validate_boss_stem_integral_values(
			stem_value as Dictionary,
			str(stem_sources.get(stem_key, campaign_path)),
			errors
		)
	validate_authored_title_profiles(campaign_path, campaign, definitions, errors)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func validate_authored_title_profiles(
	campaign_path: String,
	campaign: Dictionary,
	definitions: Dictionary,
	errors: Array[String]
) -> void:
	var files_value: Variant = campaign.get("audio_files", [])
	if typeof(files_value) != TYPE_ARRAY:
		return
	for relative_value in files_value as Array:
		var relative_path := str(relative_value)
		if not AudioMoodCatalog.safe_relative_json_path(relative_path):
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result: Dictionary = Repository.read_json(path)
		if not bool(result.get("ok", false)):
			continue
		var data: Dictionary = result.get("data", {})
		var authored_title := str(data.get("title_profile_id", "")).strip_edges()
		if not authored_title.is_empty() and not definitions.has(authored_title):
			errors.append("%s: title_profile_id references unknown audio profile '%s'." % [path, authored_title])


static func validate_integral_music_values(
	profile_data: Dictionary,
	source: String,
	errors: Array[String]
) -> void:
	var music_value: Variant = profile_data.get("music", {})
	if typeof(music_value) != TYPE_DICTIONARY:
		return
	var music: Dictionary = music_value as Dictionary
	validate_integral_number(music.get("root_midi", null), "%s/music/root_midi" % source, errors)
	for key in INTEGER_SEQUENCE_KEYS:
		var sequence_value: Variant = music.get(key, [])
		if typeof(sequence_value) != TYPE_ARRAY:
			continue
		for index in range((sequence_value as Array).size()):
			validate_integral_number(
				(sequence_value as Array)[index],
				"%s/music/%s[%d]" % [source, key, index],
				errors
			)


static func validate_boss_stem_integral_values(
	stem_data: Dictionary,
	source: String,
	errors: Array[String]
) -> void:
	validate_integral_number(stem_data.get("root_offset", null), "%s/boss_stem/root_offset" % source, errors)
	for key in ["melody_steps", "bass_steps"]:
		var sequence_value: Variant = stem_data.get(key, [])
		if typeof(sequence_value) != TYPE_ARRAY:
			continue
		for index in range((sequence_value as Array).size()):
			validate_integral_number(
				(sequence_value as Array)[index],
				"%s/boss_stem/%s[%d]" % [source, key, index],
				errors
			)


static func validate_integral_number(value: Variant, label: String, errors: Array[String]) -> void:
	if typeof(value) == TYPE_INT:
		return
	if typeof(value) != TYPE_FLOAT:
		return
	var number := float(value)
	if not is_equal_approx(number, float(int(number))):
		errors.append("%s must be an integer value." % label)


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value as Array:
		target.append(str(message))
