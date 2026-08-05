@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/sprite_animation_validator.gd")
const SpriteAnimationCatalog = preload("res://src/content/sprite_animation_catalog.gd")

const SUPPORTED_DIRECTION_COUNTS := [1, 4]
const MAX_RENDER_DIMENSION := 128


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var output: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, output.get("errors", []))
	append_messages(warnings, output.get("warnings", []))
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := validate_animation_integrity_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var output: Dictionary = BaseValidator.validate_campaign_path(campaign_path)
	var integrity := validate_animation_integrity_only(campaign_path)
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


static func validate_animation_only(campaign_path: String) -> Dictionary:
	var output: Dictionary = BaseValidator.validate_animation_only(campaign_path)
	var integrity := validate_animation_integrity_only(campaign_path)
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


static func validate_animation_integrity_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings}
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog_result := SpriteAnimationCatalog.load_catalogs(campaign_path, campaign)
	if not bool(catalog_result.get("ok", false)):
		return {"ok": true, "errors": errors, "warnings": warnings}
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var sources_value: Variant = catalog_result.get("sources", {})
	var sources: Dictionary = sources_value as Dictionary if typeof(sources_value) == TYPE_DICTIONARY else {}
	var ids := PackedStringArray()
	for value in definitions.keys():
		ids.append(str(value))
	ids.sort()
	for profile_id in ids:
		var profile_value: Variant = definitions.get(profile_id, {})
		if typeof(profile_value) != TYPE_DICTIONARY:
			continue
		validate_profile_integrity(
			profile_value as Dictionary,
			str(sources.get(profile_id, campaign_path)),
			errors,
			warnings
		)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func validate_profile_integrity(
	profile: Dictionary,
	source: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var profile_id := str(profile.get("id", "profile"))
	var directions := int(profile.get("directions", 0))
	if not SUPPORTED_DIRECTION_COUNTS.has(directions):
		errors.append("%s/%s: production runtime currently supports 1 or 4 directional rows, not %d." % [source, profile_id, directions])
	var frame_size := SpriteAnimationCatalog.vector2i_value(profile, "frame_size", Vector2i.ZERO)
	var render_size := SpriteAnimationCatalog.vector2i_value(profile, "render_size", Vector2i.ZERO)
	var pivot := SpriteAnimationCatalog.vector2i_value(profile, "pivot", Vector2i.ZERO)
	if pivot.x < 0 or pivot.y < 0 or pivot.x > frame_size.x or pivot.y > frame_size.y:
		errors.append("%s/%s: pivot must remain inside the source frame." % [source, profile_id])
	if render_size.x > MAX_RENDER_DIMENSION or render_size.y > MAX_RENDER_DIMENSION:
		errors.append("%s/%s: render_size exceeds the %d pixel production limit." % [source, profile_id, MAX_RENDER_DIMENSION])
	var atlas := str(profile.get("atlas", "")).strip_edges()
	if atlas.is_empty() and str(profile.get("fallback_style", "")) == "prop":
		var walk := SpriteAnimationCatalog.animation(profile, "walk")
		if int(walk.get("frames", 1)) > 1:
			warnings.append("%s/%s: procedural props declare multiple walk frames that will not be visually distinct." % [source, profile_id])
	var occupied_rows: Dictionary = {}
	var animations_value: Variant = profile.get("animations", {})
	if typeof(animations_value) != TYPE_DICTIONARY:
		return
	for state in SpriteAnimationCatalog.STATES:
		var record := SpriteAnimationCatalog.animation(profile, state)
		var base_row := int(record.get("row", 0))
		for row in range(base_row, base_row + maxi(1, directions)):
			if occupied_rows.has(row):
				warnings.append("%s/%s: animation states '%s' and '%s' share atlas row %d." % [source, profile_id, occupied_rows[row], state, row])
			else:
				occupied_rows[row] = state


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value as Array:
		target.append(str(message))
