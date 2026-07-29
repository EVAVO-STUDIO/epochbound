@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/combat_director_validator.gd")
const CompanionModel = preload("res://src/game/companion_model.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

const MAX_STATE_KEY_LENGTH := 160
const PROFILE_POSITIVE_FIELDS := [
	"follow_distance",
	"guard_distance",
	"recovery_distance",
	"seek_radius",
	"seek_speed",
	"guard_attack_range"
]


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_count := 0
	var map_count := 0
	var definition_count := 0
	var placement_count := 0
	var zone_count := 0
	var cue_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		campaign_count += 1
		var report := validate_campaign_path(str(entry.get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		map_count += int(report.get("map_count", 0))
		definition_count += int(report.get("definition_count", 0))
		placement_count += int(report.get("placement_count", 0))
		zone_count += int(report.get("zone_count", 0))
		cue_count += int(report.get("cue_count", 0))
	if campaign_count == 0:
		warnings.append("No campaigns were found under %s." % root)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"campaign_count": campaign_count,
		"map_count": map_count,
		"definition_count": definition_count,
		"placement_count": placement_count,
		"zone_count": zone_count,
		"cue_count": cue_count
	}


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_campaign_path(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var campaign_result := Repository.read_json(campaign_path)
	if not campaign_result.get("ok", false):
		append_messages(errors, campaign_result.get("errors", []))
		return make_report(errors, warnings, base_report, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var companion_profile := CompanionModel.profile(campaign)
	validate_profile(companion_profile, str(campaign.get("id", campaign_path)), errors, warnings)
	var cue_count := 0
	var state_keys: Dictionary = {}
	var map_files_value: Variant = campaign.get("map_files", [])
	if typeof(map_files_value) == TYPE_ARRAY:
		for relative_value in map_files_value:
			var relative_path := str(relative_value)
			if not ObjectCatalog.safe_relative_json_path(relative_path):
				continue
			var map_path := campaign_path.get_base_dir().path_join(relative_path)
			var map_result := Repository.read_json(map_path)
			if not map_result.get("ok", false):
				continue
			var map_data: Dictionary = map_result.get("data", {})
			var report := validate_cues(map_data, map_path)
			append_messages(errors, report.get("errors", []))
			append_messages(warnings, report.get("warnings", []))
			cue_count += int(report.get("cue_count", 0))
			for key in report.get("state_keys", {}).keys():
				var state_key := str(key)
				if state_keys.has(state_key):
					errors.append(
						"%s: companion cue state key '%s' is shared by '%s' and '%s'." % [
							campaign.get("id", "campaign"),
							state_key,
							state_keys[state_key],
							report.get("state_keys", {}).get(state_key, "cue")
						]
					)
				else:
					state_keys[state_key] = report.get("state_keys", {}).get(state_key, "cue")
	if CompanionModel.allowed_commands(companion_profile).has("seek") and cue_count == 0:
		warnings.append("%s: companion supports seek but no companion cues are authored." % campaign.get("id", "campaign"))
	return make_report(errors, warnings, base_report, cue_count)


static func validate_map(map_data: Dictionary, path: String = "") -> Dictionary:
	var base_report := BaseValidator.validate_map(map_data, path)
	var cue_report := validate_cues(map_data, path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, cue_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, cue_report.get("warnings", []))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"placement_count": base_report.get("placement_count", 0),
		"zone_count": base_report.get("zone_count", 0),
		"cue_count": cue_report.get("cue_count", 0)
	}


static func validate_profile(
	companion_profile: Dictionary,
	campaign_id: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var prefix := "%s/actors/companion" % campaign_id
	if companion_profile.is_empty():
		errors.append("%s: companion actor record is required." % prefix)
		return
	if str(companion_profile.get("name", "")).strip_edges().is_empty():
		errors.append("%s: name is required." % prefix)
	if int(companion_profile.get("max_health", 0)) <= 0:
		errors.append("%s: max_health must be positive." % prefix)
	var commands_value: Variant = companion_profile.get("commands", CompanionModel.DEFAULT_COMMANDS)
	if typeof(commands_value) != TYPE_ARRAY:
		errors.append("%s: commands must be an array." % prefix)
	else:
		var seen: Dictionary = {}
		for command_value in commands_value:
			var command := str(command_value)
			if not CompanionModel.ALLOWED_COMMANDS.has(command):
				errors.append("%s: unsupported command '%s'." % [prefix, command])
			elif seen.has(command):
				errors.append("%s: command '%s' is repeated." % [prefix, command])
			else:
				seen[command] = true
		if not seen.has("follow"):
			warnings.append("%s: commands omit 'follow'; runtime recovery will still fall back to follow." % prefix)
	for field in PROFILE_POSITIVE_FIELDS:
		if float(companion_profile.get(field, 0.0)) <= 0.0:
			errors.append("%s: %s must be positive." % [prefix, field])
	if float(companion_profile.get("guard_distance", 24.0)) > float(companion_profile.get("follow_distance", 34.0)):
		warnings.append("%s: guard_distance is greater than follow_distance." % prefix)
	if float(companion_profile.get("seek_radius", 280.0)) > float(companion_profile.get("recovery_distance", 300.0)) * 2.0:
		warnings.append("%s: seek_radius is unusually large relative to recovery_distance." % prefix)


static func validate_cues(map_data: Dictionary, path: String = "") -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var state_keys: Dictionary = {}
	var map_id := str(map_data.get("id", path))
	var cues_value: Variant = map_data.get("companion_cues", [])
	if typeof(cues_value) != TYPE_ARRAY:
		errors.append("%s: companion_cues must be an array." % map_id)
		return {
			"ok": false,
			"errors": errors,
			"warnings": warnings,
			"cue_count": 0,
			"state_keys": state_keys
		}
	var cues: Array = cues_value
	var ids: Dictionary = {}
	var era_ids := collect_ids(map_data.get("eras", []))
	var canvas: Dictionary = map_data.get("canvas", {})
	var width := float(canvas.get("width", 0.0))
	var height := float(canvas.get("height", 0.0))
	for cue_value in cues:
		if typeof(cue_value) != TYPE_DICTIONARY:
			errors.append("%s: companion cue entries must be objects." % map_id)
			continue
		var cue: Dictionary = cue_value
		var cue_id := str(cue.get("id", ""))
		var prefix := "%s/%s" % [map_id, cue_id if not cue_id.is_empty() else "companion_cue"]
		if cue_id.is_empty() or Repository.normalise_id(cue_id) != cue_id:
			errors.append("%s: cue id must be a normalised lowercase identifier." % prefix)
		elif ids.has(cue_id):
			errors.append("%s: duplicate companion cue id '%s'." % [map_id, cue_id])
		else:
			ids[cue_id] = true
		var kind := str(cue.get("kind", ""))
		if not CompanionModel.ALLOWED_CUE_KINDS.has(kind):
			errors.append("%s: unsupported cue kind '%s'." % [prefix, kind])
		validate_position(cue.get("position"), prefix, width, height, errors)
		if float(cue.get("reveal_radius", 0.0)) <= 0.0:
			errors.append("%s: reveal_radius must be positive." % prefix)
		if str(cue.get("message", "")).strip_edges().is_empty():
			errors.append("%s: message is required." % prefix)
		if int(cue.get("reward", 0)) < 0:
			errors.append("%s: reward cannot be negative." % prefix)
		if typeof(cue.get("visible_before_discovery", false)) != TYPE_BOOL:
			errors.append("%s: visible_before_discovery must be boolean." % prefix)
		validate_available_eras(cue, prefix, era_ids, errors)
		var state_key := CompanionModel.cue_state_key(map_id, cue)
		if state_key.length() > MAX_STATE_KEY_LENGTH:
			errors.append("%s: state key exceeds %d characters." % [prefix, MAX_STATE_KEY_LENGTH])
		elif state_keys.has(state_key):
			errors.append("%s: state key '%s' is duplicated on this map." % [prefix, state_key])
		else:
			state_keys[state_key] = "%s/%s" % [map_id, cue_id]
		if CompanionModel.visible_before_discovery(cue) and kind == "warning":
			warnings.append("%s: visible warning cue may reveal danger without using the companion command." % prefix)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"cue_count": cues.size(),
		"state_keys": state_keys
	}


static func validate_position(
	value: Variant,
	prefix: String,
	width: float,
	height: float,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: position must be an object." % prefix)
		return
	var data: Dictionary = value
	var x := float(data.get("x", -1.0))
	var y := float(data.get("y", -1.0))
	if x < 0.0 or y < 0.0 or x > width or y > height:
		errors.append("%s: position lies outside the map canvas." % prefix)


static func validate_available_eras(
	record: Dictionary,
	prefix: String,
	era_ids: Dictionary,
	errors: Array[String]
) -> void:
	var value: Variant = record.get("available_eras", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: available_eras must be an array." % prefix)
		return
	var seen: Dictionary = {}
	for era_value in value:
		var era_id := str(era_value)
		if seen.has(era_id):
			errors.append("%s: available_eras repeats '%s'." % [prefix, era_id])
		elif not era_ids.has(era_id):
			errors.append("%s: available_eras references unknown era '%s'." % [prefix, era_id])
		seen[era_id] = true


static func collect_ids(value: Variant) -> Dictionary:
	var output: Dictionary = {}
	if typeof(value) != TYPE_ARRAY:
		return output
	for item in value:
		if typeof(item) == TYPE_DICTIONARY:
			var record: Dictionary = item
			var identifier := str(record.get("id", ""))
			if not identifier.is_empty():
				output[identifier] = true
	return output


static func make_report(
	errors: Array[String],
	warnings: Array[String],
	base_report: Dictionary,
	cue_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"map_count": base_report.get("map_count", 0),
		"definition_count": base_report.get("definition_count", 0),
		"placement_count": base_report.get("placement_count", 0),
		"zone_count": base_report.get("zone_count", 0),
		"cue_count": cue_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
