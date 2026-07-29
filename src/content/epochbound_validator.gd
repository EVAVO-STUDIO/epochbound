@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/campaign_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const MapModel = preload("res://src/content/map_model.gd")
const SUPPORTED_SCHEMA := 1
const ALLOWED_FACING := ["up", "down", "left", "right"]


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_count := 0
	var map_count := 0
	var definition_count := 0
	var placement_count := 0
	for value in Repository.scan_campaigns(root):
		var entry: Dictionary = value
		campaign_count += 1
		var report := validate_campaign_path(String(entry.get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		map_count += int(report.get("map_count", 0))
		definition_count += int(report.get("definition_count", 0))
		placement_count += int(report.get("placement_count", 0))
	if campaign_count == 0:
		warnings.append("No campaigns were found under %s." % root)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"campaign_count": campaign_count,
		"map_count": map_count,
		"definition_count": definition_count,
		"placement_count": placement_count
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
		return make_report(errors, warnings, int(base_report.get("map_count", 0)), 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id := String(campaign.get("id", campaign_path))
	var object_files_value: Variant = campaign.get("object_files", [])
	if typeof(object_files_value) != TYPE_ARRAY:
		errors.append("%s: object_files must be an array of safe relative JSON paths." % campaign_id)
		object_files_value = []
	if Array(object_files_value).is_empty():
		warnings.append("%s: no object catalog is declared; Encounter Studio has no reusable objects." % campaign_id)
	var catalog_result := ObjectCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, catalog_result.get("errors", []))
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var definition_sources: Dictionary = {}
	for file_value in catalog_result.get("files", []):
		if typeof(file_value) != TYPE_DICTIONARY:
			continue
		var file_record: Dictionary = file_value
		var data: Dictionary = file_record.get("data", {})
		validate_catalog_file(
			data,
			String(file_record.get("path", "object catalog")),
			definitions,
			definition_sources,
			errors,
			warnings
		)
	var used_definitions: Dictionary = {}
	var state_keys: Dictionary = {}
	var placement_count := 0
	var map_files_value: Variant = campaign.get("map_files", [])
	if typeof(map_files_value) == TYPE_ARRAY:
		for relative_value in map_files_value:
			var relative_path := String(relative_value)
			if not ObjectCatalog.safe_relative_json_path(relative_path):
				continue
			var map_path := campaign_path.get_base_dir().path_join(relative_path)
			var map_result := Repository.read_json(map_path)
			if not map_result.get("ok", false):
				continue
			var map_data: Dictionary = map_result.get("data", {})
			var placement_report := validate_object_placements(map_data, map_path, definitions)
			append_messages(errors, placement_report.get("errors", []))
			append_messages(warnings, placement_report.get("warnings", []))
			placement_count += int(placement_report.get("placement_count", 0))
			for object_id in placement_report.get("used_definitions", {}).keys():
				used_definitions[String(object_id)] = true
			for placement_value in map_data.get("object_placements", []):
				if typeof(placement_value) != TYPE_DICTIONARY:
					continue
				var placement: Dictionary = placement_value
				var key := ObjectCatalog.state_key(String(map_data.get("id", "map")), placement)
				if state_keys.has(key):
					errors.append(
					"%s: object state key '%s' is shared by placements '%s' and '%s'." % [
						campaign_id,
						key,
						state_keys[key],
						placement.get("id", "placement")
					]
				)
				else:
					state_keys[key] = "%s/%s" % [map_data.get("id", "map"), placement.get("id", "placement")]
	for object_id in definitions.keys():
		if not used_definitions.has(object_id):
			warnings.append("%s: object definition '%s' is not placed on any declared map." % [campaign_id, object_id])
	return make_report(
		errors,
		warnings,
		int(base_report.get("map_count", 0)),
		definitions.size(),
		placement_count
	)


static func validate_map(
	map_data: Dictionary,
	path: String = "",
	definitions: Dictionary = {}
) -> Dictionary:
	var base_report := BaseValidator.validate_map(map_data, path)
	var placement_report := validate_object_placements(map_data, path, definitions)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, placement_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, placement_report.get("warnings", []))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"placement_count": placement_report.get("placement_count", 0)
	}


static func validate_catalog_file(
	catalog: Dictionary,
	path: String,
	all_definitions: Dictionary,
	definition_sources: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if int(catalog.get("schema_version", 0)) != SUPPORTED_SCHEMA:
		errors.append("%s: unsupported object catalog schema_version." % path)
	var objects_value: Variant = catalog.get("objects", [])
	if typeof(objects_value) != TYPE_ARRAY:
		errors.append("%s: objects must be an array." % path)
		return
	if Array(objects_value).is_empty():
		warnings.append("%s: object catalog is empty." % path)
	var local_ids: Dictionary = {}
	for definition_value in objects_value:
		if typeof(definition_value) != TYPE_DICTIONARY:
			errors.append("%s: every object definition must be an object." % path)
			continue
		var definition_data: Dictionary = definition_value
		var object_id := String(definition_data.get("id", ""))
		var prefix := "%s/%s" % [path, object_id if not object_id.is_empty() else "object"]
		if object_id.is_empty() or Repository.normalise_id(object_id) != object_id:
			errors.append("%s: id must be a normalised lowercase identifier." % prefix)
		elif local_ids.has(object_id):
			errors.append("%s: duplicate definition id '%s'." % [path, object_id])
		else:
			local_ids[object_id] = true
			definition_sources[object_id] = path
		if String(definition_data.get("display_name", "")).strip_edges().is_empty():
			errors.append("%s: display_name is required." % prefix)
		var kind := String(definition_data.get("kind", ""))
		if not ObjectCatalog.ALLOWED_KINDS.has(kind):
			errors.append("%s: unsupported kind '%s'." % [prefix, kind])
		validate_appearance(definition_data.get("appearance", {}), prefix, errors)
		if typeof(definition_data.get("solid", false)) != TYPE_BOOL:
			errors.append("%s: solid must be boolean." % prefix)
		for radius_name in ["collision_radius", "interaction_radius"]:
			if float(definition_data.get(radius_name, 0.0)) < 0.0:
				errors.append("%s: %s cannot be negative." % [prefix, radius_name])
		validate_dialogue(definition_data.get("dialogue", ""), prefix, kind, errors, warnings)
		match kind:
			"enemy":
				validate_positive_number(definition_data, "max_health", prefix, errors)
				validate_positive_number(definition_data, "move_speed", prefix, errors)
				validate_positive_number(definition_data, "awareness_radius", prefix, errors)
				validate_positive_number(definition_data, "attack_radius", prefix, errors)
				validate_positive_number(definition_data, "attack_damage", prefix, errors)
				validate_positive_number(definition_data, "attack_cooldown", prefix, errors)
				if int(definition_data.get("reward", 0)) < 0:
					errors.append("%s: reward cannot be negative." % prefix)
			"pickup":
				if int(definition_data.get("pickup_value", 0)) < 1:
					errors.append("%s: pickup_value must be at least 1." % prefix)
				if String(definition_data.get("pickup_label", "")).strip_edges().is_empty():
					errors.append("%s: pickup_label is required." % prefix)
			"npc", "prop":
				if String(definition_data.get("dialogue", "")).strip_edges().is_empty() and typeof(definition_data.get("dialogue", "")) == TYPE_STRING:
					warnings.append("%s: interactive object has no dialogue." % prefix)
			_:
				pass
	if all_definitions.size() < local_ids.size():
		errors.append("%s: catalog definitions could not be merged consistently." % path)


static func validate_object_placements(
	map_data: Dictionary,
	path: String,
	definitions: Dictionary
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var used_definitions: Dictionary = {}
	var placements_value: Variant = map_data.get("object_placements", [])
	var map_id := String(map_data.get("id", path))
	if typeof(placements_value) != TYPE_ARRAY:
		errors.append("%s: object_placements must be an array." % map_id)
		return {
			"ok": false,
			"errors": errors,
			"warnings": warnings,
			"placement_count": 0,
			"used_definitions": used_definitions
		}
	var canvas: Dictionary = map_data.get("canvas", {})
	var width := float(canvas.get("width", 0.0))
	var height := float(canvas.get("height", 0.0))
	var era_ids := collect_ids(map_data.get("eras", []))
	var ids: Dictionary = {}
	for placement_value in placements_value:
		if typeof(placement_value) != TYPE_DICTIONARY:
			errors.append("%s: object placement entries must be objects." % map_id)
			continue
		var placement: Dictionary = placement_value
		var placement_id := String(placement.get("id", ""))
		var prefix := "%s/%s" % [map_id, placement_id if not placement_id.is_empty() else "placement"]
		if placement_id.is_empty() or Repository.normalise_id(placement_id) != placement_id:
			errors.append("%s: placement id must be a normalised lowercase identifier." % prefix)
		elif ids.has(placement_id):
			errors.append("%s: duplicate object placement id '%s'." % [map_id, placement_id])
		else:
			ids[placement_id] = true
		var object_id := String(placement.get("object_id", ""))
		if object_id.is_empty() or not definitions.has(object_id):
			errors.append("%s: unknown object definition '%s'." % [prefix, object_id])
		else:
			used_definitions[object_id] = true
		validate_position(placement.get("position"), prefix, width, height, errors)
		var facing := String(placement.get("facing", "down"))
		if not ALLOWED_FACING.has(facing):
			errors.append("%s: unsupported facing '%s'." % [prefix, facing])
		validate_available_eras(placement, prefix, era_ids, errors)
		var authored_state_key := String(placement.get("state_key", ""))
		if authored_state_key.length() > 160:
			errors.append("%s: state_key exceeds 160 characters." % prefix)
		if definitions.has(object_id):
			var definition_data: Dictionary = definitions[object_id]
			var kind := String(definition_data.get("kind", "prop"))
			if kind == "enemy" and map_data.get("navigation_cells", []).is_empty():
				warnings.append("%s: enemy is placed on a map without navigation cells." % prefix)
			for era_id in applicable_eras(placement, era_ids):
				var position := data_to_vector(placement.get("position"), Vector2.ZERO)
				if MapModel.is_position_blocked(
					map_data,
					position,
					String(era_id),
					float(definition_data.get("collision_radius", 4.0))
				):
					warnings.append("%s: placement begins in blocked space during era '%s'." % [prefix, era_id])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"placement_count": Array(placements_value).size(),
		"used_definitions": used_definitions
	}


static func validate_appearance(value: Variant, prefix: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: appearance must be an object." % prefix)
		return
	var appearance: Dictionary = value
	var shape := String(appearance.get("shape", ""))
	if not ObjectCatalog.ALLOWED_SHAPES.has(shape):
		errors.append("%s: unsupported appearance shape '%s'." % [prefix, shape])
	for color_key in ["color", "accent"]:
		if not Color.html_is_valid(String(appearance.get(color_key, ""))):
			errors.append("%s: appearance %s is not a valid HTML colour." % [prefix, color_key])


static func validate_dialogue(
	value: Variant,
	prefix: String,
	kind: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(value) == TYPE_STRING:
		if String(value).strip_edges().is_empty() and kind in ["npc", "prop"]:
			warnings.append("%s: dialogue is empty." % prefix)
		return
	if typeof(value) != TYPE_DICTIONARY:
		if kind in ["npc", "prop"]:
			errors.append("%s: dialogue must be text or an era-keyed object." % prefix)
		return
	var by_era: Dictionary = value
	for key in by_era.keys():
		if String(by_era.get(key, "")).strip_edges().is_empty():
			warnings.append("%s: dialogue for '%s' is empty." % [prefix, key])


static func validate_positive_number(
	definition_data: Dictionary,
	field: String,
	prefix: String,
	errors: Array[String]
) -> void:
	if float(definition_data.get(field, 0.0)) <= 0.0:
		errors.append("%s: %s must be positive." % [prefix, field])


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
	var position: Dictionary = value
	var x := float(position.get("x", -1.0))
	var y := float(position.get("y", -1.0))
	if x < 0.0 or y < 0.0 or x > width or y > height:
		errors.append("%s: position lies outside the map canvas." % prefix)


static func validate_available_eras(
	record: Dictionary,
	prefix: String,
	era_ids: Dictionary,
	errors: Array[String]
) -> void:
	var available_value: Variant = record.get("available_eras", [])
	if typeof(available_value) != TYPE_ARRAY:
		errors.append("%s: available_eras must be an array." % prefix)
		return
	var seen: Dictionary = {}
	for era_value in available_value:
		var era_id := String(era_value)
		if seen.has(era_id):
			errors.append("%s: available_eras repeats '%s'." % [prefix, era_id])
		elif not era_ids.has(era_id):
			errors.append("%s: available_eras references unknown era '%s'." % [prefix, era_id])
		seen[era_id] = true


static func applicable_eras(placement: Dictionary, era_ids: Dictionary) -> Array:
	var available_value: Variant = placement.get("available_eras", [])
	if typeof(available_value) == TYPE_ARRAY and not Array(available_value).is_empty():
		return Array(available_value)
	return era_ids.keys()


static func collect_ids(value: Variant) -> Dictionary:
	var ids: Dictionary = {}
	if typeof(value) != TYPE_ARRAY:
		return ids
	for entry_value in value:
		if typeof(entry_value) == TYPE_DICTIONARY:
			var entry: Dictionary = entry_value
			var entry_id := String(entry.get("id", ""))
			if not entry_id.is_empty():
				ids[entry_id] = true
	return ids


static func data_to_vector(value: Variant, fallback: Vector2) -> Vector2:
	if typeof(value) != TYPE_DICTIONARY:
		return fallback
	var data: Dictionary = value
	return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))


static func make_report(
	errors: Array[String],
	warnings: Array[String],
	map_count: int,
	definition_count: int,
	placement_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"map_count": map_count,
		"definition_count": definition_count,
		"placement_count": placement_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(String(message))
