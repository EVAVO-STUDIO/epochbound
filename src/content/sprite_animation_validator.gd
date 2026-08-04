@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/audio_mood_strict_validator.gd")
const SpriteAnimationCatalog = preload("res://src/content/sprite_animation_catalog.gd")

const PROFILE_ID_PATTERN := "^[a-z0-9][a-z0-9_-]*$"
const TARGET_PREFIXES := ["player", "companion", "placement:", "object:", "shape:", "kind:", "*"]
const MAX_ATLAS_DIMENSION := 8192


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var output: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, output.get("errors", []))
	append_messages(warnings, output.get("warnings", []))
	var profile_count := 0
	var binding_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report: Dictionary = validate_animation_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		profile_count += int(report.get("animation_profile_count", 0))
		binding_count += int(report.get("animation_binding_count", 0))
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["animation_profile_count"] = profile_count
	output["animation_binding_count"] = binding_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var output: Dictionary = BaseValidator.validate_campaign_path(campaign_path)
	var animation_report: Dictionary = validate_animation_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, output.get("errors", []))
	append_messages(errors, animation_report.get("errors", []))
	append_messages(warnings, output.get("warnings", []))
	append_messages(warnings, animation_report.get("warnings", []))
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["animation_profile_count"] = animation_report.get("animation_profile_count", 0)
	output["animation_binding_count"] = animation_report.get("animation_binding_count", 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	return BaseValidator.validate_profile(profile, campaign_path)


static func validate_animation_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result: Dictionary = Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return make_report(errors, warnings, 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id := str(campaign.get("id", campaign_path))
	var files_value: Variant = campaign.get("animation_files", [])
	if typeof(files_value) != TYPE_ARRAY:
		errors.append("%s: animation_files must be an array." % campaign_id)
		return make_report(errors, warnings, 0, 0)
	var seen_paths: Dictionary = {}
	for relative_value in files_value as Array:
		var relative_path := str(relative_value)
		if not SpriteAnimationCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe animation catalogue path '%s'." % [campaign_id, relative_path])
		elif seen_paths.has(relative_path):
			errors.append("%s: animation_files repeats '%s'." % [campaign_id, relative_path])
		seen_paths[relative_path] = true
	var catalog_result: Dictionary = SpriteAnimationCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, catalog_result.get("errors", []))
	append_messages(warnings, catalog_result.get("warnings", []))
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var sources_value: Variant = catalog_result.get("sources", {})
	var sources: Dictionary = sources_value as Dictionary if typeof(sources_value) == TYPE_DICTIONARY else {}
	var profile_ids := PackedStringArray()
	for profile_id_value in definitions.keys():
		profile_ids.append(str(profile_id_value))
	profile_ids.sort()
	for profile_id in profile_ids:
		var profile_value: Variant = definitions.get(profile_id, {})
		if typeof(profile_value) == TYPE_DICTIONARY:
			validate_profile_record(profile_value as Dictionary, str(sources.get(profile_id, campaign_id)), campaign_path, errors, warnings)
	var bindings_value: Variant = catalog_result.get("bindings", [])
	var bindings: Array = bindings_value as Array if typeof(bindings_value) == TYPE_ARRAY else []
	validate_bindings(bindings, definitions, errors)
	validate_required_runtime_bindings(bindings, warnings)
	return make_report(errors, warnings, definitions.size(), bindings.size())


static func validate_profile_record(
	profile_data: Dictionary,
	source: String,
	campaign_path: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var profile_id := str(profile_data.get("id", ""))
	if not matches(PROFILE_ID_PATTERN, profile_id):
		errors.append("%s: animation profile id '%s' is invalid." % [source, profile_id])
	if str(profile_data.get("display_name", "")).strip_edges().is_empty():
		errors.append("%s/%s: display_name is required." % [source, profile_id])
	var directions := int(profile_data.get("directions", 0))
	if directions != 1 and directions != 4 and directions != 8:
		errors.append("%s/%s: directions must be 1, 4 or 8." % [source, profile_id])
	var style := str(profile_data.get("fallback_style", ""))
	if not SpriteAnimationCatalog.FALLBACK_STYLES.has(style):
		errors.append("%s/%s: unsupported fallback_style '%s'." % [source, profile_id, style])
	var frame_size := validate_vector(profile_data, "frame_size", 8, 256, source, profile_id, errors)
	validate_vector(profile_data, "render_size", 8, 256, source, profile_id, errors)
	validate_vector(profile_data, "pivot", 0, 256, source, profile_id, errors)
	var animations_value: Variant = profile_data.get("animations", {})
	if typeof(animations_value) != TYPE_DICTIONARY:
		errors.append("%s/%s: animations must be an object." % [source, profile_id])
		return
	var animations: Dictionary = animations_value as Dictionary
	var maximum_column := 0
	var maximum_row := 0
	for state in SpriteAnimationCatalog.STATES:
		if not animations.has(state):
			errors.append("%s/%s: animation state '%s' is required." % [source, profile_id, state])
			continue
		var record_value: Variant = animations.get(state, {})
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("%s/%s/%s: animation record must be an object." % [source, profile_id, state])
			continue
		var record: Dictionary = record_value as Dictionary
		var row := int(record.get("row", -1))
		var frames := int(record.get("frames", 0))
		var fps := float(record.get("fps", 0.0))
		if row < 0:
			errors.append("%s/%s/%s: row cannot be negative." % [source, profile_id, state])
		if frames < 1 or frames > 32:
			errors.append("%s/%s/%s: frames must be between 1 and 32." % [source, profile_id, state])
		if fps < 1.0 or fps > 30.0:
			errors.append("%s/%s/%s: fps must be between 1 and 30." % [source, profile_id, state])
		if typeof(record.get("loop", null)) != TYPE_BOOL:
			errors.append("%s/%s/%s: loop must be boolean." % [source, profile_id, state])
		maximum_column = maxi(maximum_column, frames)
		maximum_row = maxi(maximum_row, row + directions)
	var atlas_relative := str(profile_data.get("atlas", "")).strip_edges()
	if not SpriteAnimationCatalog.safe_relative_atlas_path(atlas_relative):
		errors.append("%s/%s: atlas must be an empty value or a safe relative PNG path." % [source, profile_id])
	elif not atlas_relative.is_empty():
		validate_atlas(campaign_path, atlas_relative, frame_size, maximum_column, maximum_row, source, profile_id, errors, warnings)


static func validate_vector(
	profile_data: Dictionary,
	key: String,
	minimum: int,
	maximum: int,
	source: String,
	profile_id: String,
	errors: Array[String]
) -> Vector2i:
	var value: Variant = profile_data.get(key, {})
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s/%s: %s must be an object." % [source, profile_id, key])
		return Vector2i.ZERO
	var data: Dictionary = value as Dictionary
	for axis in ["x", "y"]:
		var axis_value: Variant = data.get(axis, null)
		if typeof(axis_value) != TYPE_INT and typeof(axis_value) != TYPE_FLOAT:
			errors.append("%s/%s/%s/%s must be numeric." % [source, profile_id, key, axis])
			continue
		var number := float(axis_value)
		if not is_equal_approx(number, float(int(number))):
			errors.append("%s/%s/%s/%s must be an integer." % [source, profile_id, key, axis])
		elif int(number) < minimum or int(number) > maximum:
			errors.append("%s/%s/%s/%s must be between %d and %d." % [source, profile_id, key, axis, minimum, maximum])
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))


static func validate_atlas(
	campaign_path: String,
	relative_path: String,
	frame_size: Vector2i,
	minimum_columns: int,
	minimum_rows: int,
	source: String,
	profile_id: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var path := campaign_path.get_base_dir().path_join(relative_path)
	if not FileAccess.file_exists(path):
		errors.append("%s/%s: atlas file does not exist: %s." % [source, profile_id, relative_path])
		return
	var image := Image.new()
	var load_error := image.load(path)
	if load_error != OK:
		errors.append("%s/%s: atlas could not be decoded as PNG." % [source, profile_id])
		return
	var size := image.get_size()
	if size.x > MAX_ATLAS_DIMENSION or size.y > MAX_ATLAS_DIMENSION:
		errors.append("%s/%s: atlas exceeds the %d pixel dimension limit." % [source, profile_id, MAX_ATLAS_DIMENSION])
	if frame_size.x <= 0 or frame_size.y <= 0:
		return
	if size.x % frame_size.x != 0 or size.y % frame_size.y != 0:
		errors.append("%s/%s: atlas dimensions must divide evenly by frame_size." % [source, profile_id])
	var columns := size.x / frame_size.x
	var rows := size.y / frame_size.y
	if columns < minimum_columns or rows < minimum_rows:
		errors.append("%s/%s: atlas grid is too small for the declared animation rows and frames." % [source, profile_id])
	if image.detect_alpha() == Image.ALPHA_NONE:
		warnings.append("%s/%s: atlas has no alpha channel; confirm opaque backgrounds are intentional." % [source, profile_id])


static func validate_bindings(bindings: Array, definitions: Dictionary, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for binding_value in bindings:
		if typeof(binding_value) != TYPE_DICTIONARY:
			continue
		var binding: Dictionary = binding_value
		var source := str(binding.get("_source", "animation catalogue"))
		var target := str(binding.get("target", "")).strip_edges()
		var profile_id := str(binding.get("profile_id", "")).strip_edges()
		if target.is_empty() or not valid_target(target):
			errors.append("%s: animation binding target '%s' is invalid." % [source, target])
		if seen.has(target):
			errors.append("%s: animation binding repeats target '%s'." % [source, target])
		seen[target] = true
		if profile_id.is_empty() or not definitions.has(profile_id):
			errors.append("%s: animation binding references unknown profile '%s'." % [source, profile_id])


static func validate_required_runtime_bindings(bindings: Array, warnings: Array[String]) -> void:
	var targets: Dictionary = {}
	for binding_value in bindings:
		if typeof(binding_value) == TYPE_DICTIONARY:
			targets[str((binding_value as Dictionary).get("target", ""))] = true
	for required in ["player", "companion"]:
		if not targets.has(required):
			warnings.append("Animation catalogue has no explicit '%s' binding; fallback resolution will be used." % required)


static func valid_target(target: String) -> bool:
	if target == "player" or target == "companion" or target == "*":
		return true
	for prefix in ["placement:", "object:", "shape:", "kind:"]:
		if target.begins_with(prefix) and not target.trim_prefix(prefix).is_empty():
			return true
	return false


static func matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func make_report(errors: Array[String], warnings: Array[String], profile_count: int, binding_count: int) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"animation_profile_count": profile_count,
		"animation_binding_count": binding_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value as Array:
		target.append(str(message))
