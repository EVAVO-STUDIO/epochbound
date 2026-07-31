@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/package_release_validator.gd")
const PresentationCatalog = preload("res://src/content/presentation_catalog.gd")

const PROFILE_ID_PATTERN := "^[a-z0-9][a-z0-9_-]*$"
const COLOR_PATTERN := "^[0-9A-Fa-f]{6}$"
const PALETTE_KEYS := [
	"ink", "shadow", "midtone", "light", "accent", "danger",
	"ui_fill", "ui_frame", "ui_text"
]
const ATMOSPHERE_KINDS := ["none", "motes", "pollen", "fireflies", "dust", "embers", "cinders"]


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var profile_count := 0
	var binding_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := validate_presentation_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		profile_count += int(report.get("presentation_profile_count", 0))
		binding_count += int(report.get("presentation_binding_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["presentation_profile_count"] = profile_count
	output["presentation_binding_count"] = binding_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_campaign_path(campaign_path)
	var presentation_report := validate_presentation_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, presentation_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, presentation_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["presentation_profile_count"] = presentation_report.get("presentation_profile_count", 0)
	output["presentation_binding_count"] = presentation_report.get("presentation_binding_count", 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	return BaseValidator.validate_profile(profile, campaign_path)


static func validate_presentation_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var result: Dictionary = Repository.read_json(campaign_path)
	if not bool(result.get("ok", false)):
		append_messages(errors, result.get("errors", []))
		return make_report(errors, warnings, 0, 0)
	var campaign: Dictionary = result.get("data", {})
	var campaign_id := str(campaign.get("id", campaign_path))
	var files_value: Variant = campaign.get("presentation_files", [])
	if typeof(files_value) != TYPE_ARRAY:
		errors.append("%s: presentation_files must be an array." % campaign_id)
		return make_report(errors, warnings, 0, 0)
	var seen_paths: Dictionary = {}
	for relative_value in files_value:
		var relative_path := str(relative_value)
		if not PresentationCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe presentation catalog path '%s'." % [campaign_id, relative_path])
		elif seen_paths.has(relative_path):
			errors.append("%s: presentation_files repeats '%s'." % [campaign_id, relative_path])
		seen_paths[relative_path] = true
	var catalog_result := PresentationCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, catalog_result.get("errors", []))
	append_messages(warnings, catalog_result.get("warnings", []))
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var bindings_value: Variant = catalog_result.get("bindings", [])
	var bindings: Array = bindings_value if typeof(bindings_value) == TYPE_ARRAY else []
	var profile_ids := PackedStringArray()
	for profile_id_value in definitions.keys():
		profile_ids.append(str(profile_id_value))
	profile_ids.sort()
	for profile_id in profile_ids:
		var profile_data: Dictionary = definitions.get(profile_id, {})
		validate_profile_record(profile_data, str(catalog_result.get("sources", {}).get(profile_id, campaign_id)), errors, warnings)
	var map_index := load_map_index(campaign_path, campaign, errors)
	var covered: Dictionary = {}
	var seen_bindings: Dictionary = {}
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
			errors.append("%s: presentation binding map_id is required." % source)
		elif map_id != "*" and not map_index.has(map_id):
			errors.append("%s: presentation binding references unknown map '%s'." % [source, map_id])
		if profile_id.is_empty() or not definitions.has(profile_id):
			errors.append("%s: presentation binding references unknown profile '%s'." % [source, profile_id])
		if seen_bindings.has(key):
			errors.append("%s: presentation binding repeats map/era '%s'." % [source, key])
		seen_bindings[key] = true
		if map_id != "*" and map_index.has(map_id):
			var eras: Dictionary = map_index.get(map_id, {})
			if era_id != "*" and not eras.has(era_id):
				errors.append("%s: presentation binding references unknown era '%s' on map '%s'." % [source, era_id, map_id])
			elif era_id == "*":
				for known_era_value in eras.keys():
					covered["%s|%s" % [map_id, str(known_era_value)]] = true
			else:
				covered[key] = true
	for map_id_value in map_index.keys():
		var map_id := str(map_id_value)
		var eras: Dictionary = map_index.get(map_id, {})
		for era_id_value in eras.keys():
			var era_id := str(era_id_value)
			if not covered.has("%s|%s" % [map_id, era_id]) and not seen_bindings.has("*|*"):
				warnings.append("%s: map '%s' era '%s' has no explicit presentation binding." % [campaign_id, map_id, era_id])
	return make_report(errors, warnings, definitions.size(), bindings.size())


static func validate_profile_record(
	profile_data: Dictionary,
	source: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var profile_id := str(profile_data.get("id", ""))
	if not matches(PROFILE_ID_PATTERN, profile_id):
		errors.append("%s: presentation profile id '%s' is invalid." % [source, profile_id])
	if str(profile_data.get("display_name", "")).strip_edges().is_empty():
		errors.append("%s/%s: display_name is required." % [source, profile_id])
	var palette_value: Variant = profile_data.get("palette", {})
	if typeof(palette_value) != TYPE_DICTIONARY:
		errors.append("%s/%s: palette must be an object." % [source, profile_id])
	else:
		var palette: Dictionary = palette_value
		for key in PALETTE_KEYS:
			var color_value := str(palette.get(key, ""))
			if not matches(COLOR_PATTERN, color_value):
				errors.append("%s/%s/palette/%s must be a six-digit hexadecimal colour." % [source, profile_id, key])
	validate_number(profile_data, "camera", "follow_strength", 1.0, 30.0, source, profile_id, errors)
	validate_number(profile_data, "camera", "deadzone", 0.0, 80.0, source, profile_id, errors)
	validate_number(profile_data, "camera", "look_ahead", 0.0, 80.0, source, profile_id, errors)
	validate_number(profile_data, "camera", "maximum_shake", 0.0, 20.0, source, profile_id, errors)
	var atmosphere_kind := PresentationCatalog.text(profile_data, "atmosphere", "kind", "none")
	if not ATMOSPHERE_KINDS.has(atmosphere_kind):
		errors.append("%s/%s/atmosphere: unsupported kind '%s'." % [source, profile_id, atmosphere_kind])
	validate_integer(profile_data, "atmosphere", "density", 0, 128, source, profile_id, errors)
	validate_number(profile_data, "atmosphere", "speed", 0.0, 80.0, source, profile_id, errors)
	validate_number(profile_data, "atmosphere", "opacity", 0.0, 1.0, source, profile_id, errors)
	validate_number(profile_data, "screen", "scanline_alpha", 0.0, 0.25, source, profile_id, errors)
	validate_number(profile_data, "screen", "vignette_alpha", 0.0, 0.8, source, profile_id, errors)
	validate_number(profile_data, "screen", "dither_alpha", 0.0, 0.25, source, profile_id, errors)
	validate_number(profile_data, "actors", "movement_bob", 0.0, 6.0, source, profile_id, errors)
	validate_number(profile_data, "actors", "shadow_scale", 0.5, 2.0, source, profile_id, errors)
	if PresentationCatalog.number(profile_data, "screen", "vignette_alpha", 0.0) > 0.55:
		warnings.append("%s/%s: strong vignette may hide edge interactions on small displays." % [source, profile_id])


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
	for relative_value in value:
		var path := campaign_path.get_base_dir().path_join(str(relative_value))
		var result: Dictionary = Repository.read_json(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var map_data: Dictionary = result.get("data", {})
		var map_id := str(map_data.get("id", ""))
		var eras: Dictionary = {}
		for era_value in map_data.get("eras", []):
			if typeof(era_value) == TYPE_DICTIONARY:
				eras[str((era_value as Dictionary).get("id", ""))] = true
		if not map_id.is_empty():
			output[map_id] = eras
	return output


static func matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func make_report(
	errors: Array[String],
	warnings: Array[String],
	profile_count: int,
	binding_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"presentation_profile_count": profile_count,
		"presentation_binding_count": binding_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
