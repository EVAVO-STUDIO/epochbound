@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/epochbound_validator.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const EncounterZoneModel = preload("res://src/game/encounter_zone_model.gd")

const MAX_STATE_KEY_LENGTH := 160
const ENEMY_POSITIVE_FIELDS := [
	"patrol_radius",
	"leash_radius",
	"stagger_duration",
	"knockback_distance",
	"attack_windup",
	"return_speed_multiplier",
	"target_memory",
	"contact_knockback"
]


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_count := 0
	var map_count := 0
	var definition_count := 0
	var placement_count := 0
	var zone_count := 0
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
		"zone_count": zone_count
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
	var catalog_result := ObjectCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, catalog_result.get("errors", []))
	var definitions: Dictionary = catalog_result.get("definitions", {})
	validate_enemy_definitions(definitions, errors, warnings)

	var zone_count := 0
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
			var report := validate_director_map(map_data, definitions, map_path)
			append_messages(errors, report.get("errors", []))
			append_messages(warnings, report.get("warnings", []))
			zone_count += int(report.get("zone_count", 0))
	return make_report(errors, warnings, base_report, zone_count)


static func validate_map(
	map_data: Dictionary,
	path: String = "",
	definitions: Dictionary = {}
) -> Dictionary:
	var base_report := BaseValidator.validate_map(map_data, path, definitions)
	var director_report := validate_director_map(map_data, definitions, path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, director_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, director_report.get("warnings", []))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"placement_count": base_report.get("placement_count", 0),
		"zone_count": director_report.get("zone_count", 0)
	}


static func validate_enemy_definitions(
	definitions: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	for object_id in definitions.keys():
		var value: Variant = definitions.get(object_id, {})
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var definition_data: Dictionary = value
		if str(definition_data.get("kind", "")) != "enemy":
			continue
		var prefix := "enemy definition %s" % object_id
		for field in ENEMY_POSITIVE_FIELDS:
			if definition_data.has(field) and float(definition_data.get(field, 0.0)) < 0.0:
				errors.append("%s: %s cannot be negative." % [prefix, field])
		if float(definition_data.get("attack_windup", 0.24)) > 2.0:
			warnings.append("%s: attack_windup exceeds two seconds and may feel unresponsive." % prefix)
		if float(definition_data.get("leash_radius", 0.0)) > 0.0 and float(definition_data.get("leash_radius", 0.0)) < float(definition_data.get("awareness_radius", 0.0)):
			warnings.append("%s: leash_radius is smaller than awareness_radius." % prefix)
		if float(definition_data.get("return_speed_multiplier", 0.9)) <= 0.0:
			errors.append("%s: return_speed_multiplier must be positive." % prefix)


static func validate_director_map(
	map_data: Dictionary,
	definitions: Dictionary,
	path: String = ""
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var map_id := str(map_data.get("id", path))
	var zones_value: Variant = map_data.get("encounter_zones", [])
	if typeof(zones_value) != TYPE_ARRAY:
		errors.append("%s: encounter_zones must be an array." % map_id)
		return {"ok": false, "errors": errors, "warnings": warnings, "zone_count": 0}
	var zones: Array = zones_value
	var era_ids := collect_ids(map_data.get("eras", []))
	var canvas: Dictionary = map_data.get("canvas", {})
	var width := float(canvas.get("width", 0.0))
	var height := float(canvas.get("height", 0.0))
	var placements := placement_records(map_data)
	var placement_by_id: Dictionary = {}
	var enemy_ids: Dictionary = {}
	for placement in placements:
		var placement_id := str(placement.get("id", ""))
		placement_by_id[placement_id] = placement
		var definition_data: Dictionary = definitions.get(str(placement.get("object_id", "")), {})
		if str(definition_data.get("kind", "")) == "enemy":
			enemy_ids[placement_id] = true

	var zone_ids: Dictionary = {}
	var assigned_enemies: Dictionary = {}
	var state_keys: Dictionary = {}
	for zone_value in zones:
		if typeof(zone_value) != TYPE_DICTIONARY:
			errors.append("%s: encounter zone entries must be objects." % map_id)
			continue
		var zone: Dictionary = zone_value
		var zone_id := str(zone.get("id", ""))
		var prefix := "%s/%s" % [map_id, zone_id if not zone_id.is_empty() else "encounter_zone"]
		if zone_id.is_empty() or Repository.normalise_id(zone_id) != zone_id:
			errors.append("%s: zone id must be a normalised lowercase identifier." % prefix)
		elif zone_ids.has(zone_id):
			errors.append("%s: duplicate encounter zone id '%s'." % [map_id, zone_id])
		else:
			zone_ids[zone_id] = true
		validate_position(zone.get("position"), prefix, width, height, errors)
		var radius := float(zone.get("radius", 0.0))
		var activation := float(zone.get("activation_radius", 0.0))
		if radius <= 0.0:
			errors.append("%s: radius must be positive." % prefix)
		if activation < radius:
			errors.append("%s: activation_radius must be at least the zone radius." % prefix)
		if float(zone.get("leash_padding", 0.0)) < 0.0:
			errors.append("%s: leash_padding cannot be negative." % prefix)
		validate_available_eras(zone, prefix, era_ids, errors)
		var ids := EncounterZoneModel.enemy_placement_ids(zone)
		if ids.is_empty():
			warnings.append("%s: zone has no enemy placements." % prefix)
		for placement_id in ids:
			if not placement_by_id.has(placement_id):
				errors.append("%s: enemy placement '%s' does not exist." % [prefix, placement_id])
				continue
			if not enemy_ids.has(placement_id):
				errors.append("%s: placement '%s' does not reference an enemy definition." % [prefix, placement_id])
			if assigned_enemies.has(placement_id):
				errors.append("%s: enemy placement '%s' is already assigned to zone '%s'." % [prefix, placement_id, assigned_enemies[placement_id]])
			else:
				assigned_enemies[placement_id] = zone_id
			var placement: Dictionary = placement_by_id[placement_id]
			var position := Repository.data_to_vector(placement.get("position"), Vector2.ZERO)
			if not EncounterZoneModel.contains(zone, position, float(zone.get("leash_padding", 0.0))):
				warnings.append("%s: enemy placement '%s' begins outside the zone leash." % [prefix, placement_id])
		var state_key := EncounterZoneModel.zone_state_key(map_id, zone)
		if state_key.length() > MAX_STATE_KEY_LENGTH:
			errors.append("%s: clear state key exceeds %d characters." % [prefix, MAX_STATE_KEY_LENGTH])
		elif state_keys.has(state_key):
			errors.append("%s: clear state key '%s' is duplicated." % [prefix, state_key])
		else:
			state_keys[state_key] = zone_id

	for enemy_id in enemy_ids.keys():
		if not assigned_enemies.has(enemy_id):
			warnings.append("%s: enemy placement '%s' is not assigned to an encounter zone." % [map_id, enemy_id])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"zone_count": zones.size()
	}


static func placement_records(map_data: Dictionary) -> Array:
	var output: Array = []
	var value: Variant = map_data.get("object_placements", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for placement_value in value:
		if typeof(placement_value) == TYPE_DICTIONARY:
			output.append(placement_value)
	return output


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
	zone_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"map_count": base_report.get("map_count", 0),
		"definition_count": base_report.get("definition_count", 0),
		"placement_count": base_report.get("placement_count", 0),
		"zone_count": zone_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
