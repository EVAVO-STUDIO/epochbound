@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/arsenal_validator.gd")
const BossCatalog = preload("res://src/content/boss_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const EncounterZoneModel = preload("res://src/game/encounter_zone_model.gd")

const MIN_ATTACK_WINDUP := 0.35
const MIN_SAFE_PAUSE := 0.35
const MAX_CONSECUTIVE_ATTACK_STEPS := 3
const MAX_PROJECTILE_SPEED := 520.0
const MAX_PROJECTILE_RADIUS := 10.0
const MIN_ARENA_WIDTH := 180.0
const MIN_ARENA_HEIGHT := 120.0
const MAX_STATE_KEY_LENGTH := 160


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var boss_count := 0
	var boss_placement_count := 0
	var boss_phase_count := 0
	var boss_pattern_step_count := 0
	var reinforcement_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := validate_boss_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		boss_count += int(report.get("boss_count", 0))
		boss_placement_count += int(report.get("boss_placement_count", 0))
		boss_phase_count += int(report.get("boss_phase_count", 0))
		boss_pattern_step_count += int(report.get("boss_pattern_step_count", 0))
		reinforcement_count += int(report.get("boss_reinforcement_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["boss_count"] = boss_count
	output["boss_placement_count"] = boss_placement_count
	output["boss_phase_count"] = boss_phase_count
	output["boss_pattern_step_count"] = boss_pattern_step_count
	output["boss_reinforcement_count"] = reinforcement_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_campaign_path(campaign_path)
	var boss_report := validate_boss_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, boss_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, boss_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	for field in ["boss_count", "boss_placement_count", "boss_phase_count", "boss_pattern_step_count", "boss_reinforcement_count"]:
		output[field] = boss_report.get(field, 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	return BaseValidator.validate_profile(profile, campaign_path)


static func validate_boss_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return make_report(errors, warnings, 0, 0, 0, 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id := str(campaign.get("id", campaign_path))
	var object_result := ObjectCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, object_result.get("errors", []))
	var definitions: Dictionary = object_result.get("definitions", {})
	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	var items: Dictionary = item_result.get("definitions", {})
	var economy_result := EconomyCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, economy_result.get("errors", []))
	var currencies: Dictionary = economy_result.get("currencies", {})
	var maps := load_maps(campaign_path, campaign, errors)

	var boss_count := 0
	var phase_count := 0
	var pattern_count := 0
	var boss_ids: Dictionary = {}
	for object_id_value in definitions.keys():
		var object_id := str(object_id_value)
		var definition_data: Dictionary = ObjectCatalog.definition(definitions, object_id)
		if not BossCatalog.is_boss(definition_data):
			continue
		boss_count += 1
		boss_ids[object_id] = true
		var report := validate_boss_definition(
			definition_data,
			"%s/boss/%s" % [campaign_id, object_id],
			items,
			currencies,
			errors,
			warnings
		)
		phase_count += int(report.get("phase_count", 0))
		pattern_count += int(report.get("pattern_count", 0))

	var placement_count := 0
	var reinforcement_count := 0
	var placed_boss_ids: Dictionary = {}
	for map_value in maps:
		if typeof(map_value) != TYPE_DICTIONARY:
			continue
		var map_data: Dictionary = map_value
		var report := validate_map_bosses(map_data, definitions, boss_ids, errors, warnings)
		placement_count += int(report.get("boss_placement_count", 0))
		reinforcement_count += int(report.get("reinforcement_count", 0))
		for object_id in report.get("placed_boss_ids", {}).keys():
			placed_boss_ids[str(object_id)] = true

	for object_id in boss_ids.keys():
		if not placed_boss_ids.has(object_id):
			warnings.append("%s: boss definition '%s' is not placed on any declared map." % [campaign_id, object_id])

	return make_report(errors, warnings, boss_count, placement_count, phase_count, pattern_count, reinforcement_count)


static func validate_boss_definition(
	definition_data: Dictionary,
	prefix: String,
	items: Dictionary,
	currencies: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> Dictionary:
	if str(definition_data.get("kind", "")) != "enemy":
		errors.append("%s: boss definitions must use kind 'enemy'." % prefix)
	var boss := BossCatalog.boss_record(definition_data)
	var outcome_key := BossCatalog.outcome_state_key(definition_data)
	if outcome_key.is_empty():
		errors.append("%s: outcome_state_key is required." % prefix)
	elif outcome_key.length() > MAX_STATE_KEY_LENGTH:
		errors.append("%s: outcome_state_key exceeds %d characters." % [prefix, MAX_STATE_KEY_LENGTH])
	if BossCatalog.arena_zone_id(definition_data).is_empty():
		errors.append("%s: arena_zone_id is required." % prefix)
	if BossCatalog.intro_message(definition_data).strip_edges().is_empty():
		errors.append("%s: intro_message is required." % prefix)
	if BossCatalog.defeat_message(definition_data).strip_edges().is_empty():
		errors.append("%s: defeat_message is required." % prefix)
	var arena := BossCatalog.arena_bounds(definition_data)
	if arena.size.x < MIN_ARENA_WIDTH or arena.size.y < MIN_ARENA_HEIGHT:
		errors.append("%s: arena_bounds must provide at least %.0f x %.0f pixels of movement space." % [prefix, MIN_ARENA_WIDTH, MIN_ARENA_HEIGHT])
	if int(definition_data.get("max_health", 0)) < 20:
		warnings.append("%s: max_health below 20 may not support readable phase transitions." % prefix)

	var phases := BossCatalog.phases(definition_data)
	if phases.size() < 2:
		errors.append("%s: bosses require at least two phase records." % prefix)
	var ids: Dictionary = {}
	var pattern_count := 0
	var coverage_all := false
	var coverage_by_era: Dictionary = {}
	for phase_index in range(phases.size()):
		var value: Variant = phases[phase_index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s/phases/%d: phase must be an object." % [prefix, phase_index])
			continue
		var phase: Dictionary = value
		var phase_id := str(phase.get("id", ""))
		var phase_prefix := "%s/phase/%s" % [prefix, phase_id if not phase_id.is_empty() else phase_index]
		if phase_id.is_empty() or Repository.normalise_id(phase_id) != phase_id:
			errors.append("%s: id must be a normalised lowercase identifier." % phase_prefix)
		elif ids.has(phase_id):
			errors.append("%s: duplicate phase id '%s'." % [prefix, phase_id])
		else:
			ids[phase_id] = true
		if BossCatalog.phase_name(phase).strip_edges().is_empty():
			errors.append("%s: display_name is required." % phase_prefix)
		var threshold := float(phase.get("health_ratio_at_or_below", -1.0))
		if threshold <= 0.0 or threshold > 1.0:
			errors.append("%s: health_ratio_at_or_below must be greater than zero and at most one." % phase_prefix)
		var eras_value: Variant = phase.get("available_eras", [])
		if typeof(eras_value) != TYPE_ARRAY:
			errors.append("%s: available_eras must be an array." % phase_prefix)
		elif (eras_value as Array).is_empty() and threshold >= 0.999:
			coverage_all = true
		else:
			for era_value in eras_value:
				if threshold >= 0.999:
					coverage_by_era[str(era_value)] = true
		var windup := float(phase.get("attack_windup", definition_data.get("attack_windup", 0.0)))
		if windup < MIN_ATTACK_WINDUP:
			errors.append("%s: attack_windup must be at least %.2f seconds for a readable response window." % [phase_prefix, MIN_ATTACK_WINDUP])
		for multiplier_field in ["move_speed_multiplier", "attack_cooldown_multiplier", "attack_damage_multiplier"]:
			if float(phase.get(multiplier_field, 1.0)) <= 0.0:
				errors.append("%s: %s must be positive." % [phase_prefix, multiplier_field])
		var pattern_report := validate_pattern(phase, phase_prefix, definition_data, errors, warnings)
		pattern_count += int(pattern_report.get("pattern_count", 0))
		validate_string_id_list(phase.get("reinforcement_placements", []), phase_prefix + "/reinforcement_placements", errors)
	if not coverage_all and coverage_by_era.is_empty():
		errors.append("%s: at least one opening phase must cover full health." % prefix)
	validate_defeat_effects(BossCatalog.defeat_effects(definition_data), prefix + "/defeat_effects", items, currencies, errors)
	if typeof(boss.get("lock_connection_ids", [])) != TYPE_ARRAY:
		errors.append("%s: lock_connection_ids must be an array." % prefix)
	return {"phase_count": phases.size(), "pattern_count": pattern_count}


static func validate_pattern(
	phase: Dictionary,
	prefix: String,
	definition_data: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> Dictionary:
	var pattern := BossCatalog.phase_pattern(phase)
	if pattern.is_empty():
		errors.append("%s: attack_pattern must contain at least one step." % prefix)
		return {"pattern_count": 0}
	var consecutive_attacks := 0
	var maximum_attack_run := 0
	var safe_pause_found := false
	var ranged_value: Variant = definition_data.get("ranged_attack", {})
	var ranged: Dictionary = ranged_value if typeof(ranged_value) == TYPE_DICTIONARY else {}
	var override_value: Variant = phase.get("ranged_attack_override", {})
	if typeof(override_value) == TYPE_DICTIONARY:
		for key in (override_value as Dictionary).keys():
			ranged[key] = (override_value as Dictionary).get(key)
	var projectile_speed := float(ranged.get("projectile_speed", 0.0))
	var projectile_radius := float(ranged.get("projectile_radius", 0.0))
	if projectile_speed > MAX_PROJECTILE_SPEED:
		errors.append("%s: projectile speed %.0f exceeds the boss readability limit of %.0f." % [prefix, projectile_speed, MAX_PROJECTILE_SPEED])
	if projectile_radius > MAX_PROJECTILE_RADIUS:
		errors.append("%s: projectile radius %.1f exceeds the boss readability limit of %.1f." % [prefix, projectile_radius, MAX_PROJECTILE_RADIUS])
	for step_index in range(pattern.size()):
		var value: Variant = pattern[step_index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s/attack_pattern/%d: step must be an object." % [prefix, step_index])
			continue
		var step: Dictionary = value
		var step_type := BossCatalog.pattern_step_type(step)
		var step_prefix := "%s/attack_pattern/%d" % [prefix, step_index]
		if not BossCatalog.ALLOWED_PATTERN_TYPES.has(step_type):
			errors.append("%s: unsupported pattern type '%s'." % [step_prefix, step_type])
			continue
		if step_type == "pause":
			consecutive_attacks = 0
			var duration := float(step.get("duration", 0.0))
			if duration < MIN_SAFE_PAUSE:
				errors.append("%s: pause duration must be at least %.2f seconds." % [step_prefix, MIN_SAFE_PAUSE])
			else:
				safe_pause_found = true
			continue
		consecutive_attacks += 1
		maximum_attack_run = maxi(maximum_attack_run, consecutive_attacks)
		var count := int(step.get("count", 1))
		if step_type == "fan_shot" and (count < 2 or count > 5):
			errors.append("%s: fan_shot count must be between 2 and 5." % step_prefix)
		if step_type == "radial_burst" and (count < 4 or count > 10):
			errors.append("%s: radial_burst count must be between 4 and 10." % step_prefix)
		if step_type in ["fan_shot", "radial_burst"]:
			var spread := float(step.get("spread_degrees", 0.0))
			if step_type == "fan_shot" and (spread < 5.0 or spread > 120.0):
				errors.append("%s: fan_shot spread_degrees must be between 5 and 120." % step_prefix)
			if step_type == "radial_burst" and spread < 300.0:
				warnings.append("%s: radial_burst usually needs at least 300 degrees of coverage." % step_prefix)
		if float(step.get("damage_multiplier", 1.0)) <= 0.0:
			errors.append("%s: damage_multiplier must be positive." % step_prefix)
	if maximum_attack_run > MAX_CONSECUTIVE_ATTACK_STEPS:
		errors.append("%s: attack pattern contains %d consecutive attacks without a safe pause; maximum is %d." % [prefix, maximum_attack_run, MAX_CONSECUTIVE_ATTACK_STEPS])
	if not safe_pause_found:
		errors.append("%s: attack pattern must include a readable pause step." % prefix)
	if projectile_radius > 0.0:
		for value in pattern:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var step: Dictionary = value
			if BossCatalog.pattern_step_type(step) != "radial_burst":
				continue
			var count := maxi(1, int(step.get("count", 8)))
			var arc_gap := TAU * 64.0 / float(count) - projectile_radius * 2.0
			if arc_gap < 16.0:
				errors.append("%s: radial burst leaves less than 16 pixels of escape space at the fairness probe radius." % prefix)
	return {"pattern_count": pattern.size()}


static func validate_map_bosses(
	map_data: Dictionary,
	definitions: Dictionary,
	boss_ids: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> Dictionary:
	var map_id := str(map_data.get("id", "map"))
	var placements: Dictionary = {}
	for value in map_data.get("object_placements", []):
		if typeof(value) == TYPE_DICTIONARY:
			var placement: Dictionary = value
			placements[str(placement.get("id", ""))] = placement
	var zones: Dictionary = {}
	for value in map_data.get("encounter_zones", []):
		if typeof(value) == TYPE_DICTIONARY:
			var zone: Dictionary = value
			zones[str(zone.get("id", ""))] = zone
	var connections: Dictionary = {}
	for value in map_data.get("connections", []):
		if typeof(value) == TYPE_DICTIONARY:
			var connection: Dictionary = value
			connections[str(connection.get("id", ""))] = connection
	var boss_placement_count := 0
	var reinforcement_count := 0
	var placed_boss_ids: Dictionary = {}
	for placement_id_value in placements.keys():
		var placement_id := str(placement_id_value)
		var placement: Dictionary = placements[placement_id]
		var object_id := str(placement.get("object_id", ""))
		if boss_ids.has(object_id):
			boss_placement_count += 1
			placed_boss_ids[object_id] = true
			validate_boss_placement(map_data, placement, definitions, placements, zones, connections, errors, warnings)
		var reinforcement_value: Variant = placement.get("boss_reinforcement", {})
		if typeof(reinforcement_value) == TYPE_DICTIONARY and not (reinforcement_value as Dictionary).is_empty():
			reinforcement_count += 1
	return {
		"boss_placement_count": boss_placement_count,
		"reinforcement_count": reinforcement_count,
		"placed_boss_ids": placed_boss_ids
	}


static func validate_boss_placement(
	map_data: Dictionary,
	placement: Dictionary,
	definitions: Dictionary,
	placements: Dictionary,
	zones: Dictionary,
	connections: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var map_id := str(map_data.get("id", "map"))
	var placement_id := str(placement.get("id", "boss"))
	var object_id := str(placement.get("object_id", ""))
	var definition_data := ObjectCatalog.definition(definitions, object_id)
	var prefix := "%s/boss_placement/%s" % [map_id, placement_id]
	var zone_id := BossCatalog.arena_zone_id(definition_data)
	if not zones.has(zone_id):
		errors.append("%s: arena zone '%s' does not exist on this map." % [prefix, zone_id])
	else:
		var zone: Dictionary = zones[zone_id]
		if not EncounterZoneModel.enemy_placement_ids(zone).has(placement_id):
			errors.append("%s: arena zone '%s' must include the boss placement." % [prefix, zone_id])
	var arena := BossCatalog.arena_bounds(definition_data)
	var bounds_value: Variant = map_data.get("bounds", {})
	var bounds: Dictionary = bounds_value if typeof(bounds_value) == TYPE_DICTIONARY else {}
	if arena.position.x < float(bounds.get("left", 0.0)) or arena.end.x > float(bounds.get("right", 640.0)) or arena.position.y < float(bounds.get("top", 0.0)) or arena.end.y > float(bounds.get("bottom", 360.0)):
		errors.append("%s: arena_bounds must remain inside the playable map bounds." % prefix)
	for connection_id in BossCatalog.locked_connections(definition_data):
		if not connections.has(connection_id):
			errors.append("%s: lock_connection_ids references unknown connection '%s'." % [prefix, connection_id])
	var boss_position := Repository.data_to_vector(placement.get("position"), Vector2.ZERO)
	var immediate_range := float(definition_data.get("attack_radius", 0.0)) + 32.0
	for entry_value in map_data.get("entry_points", []):
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var entry_position := Repository.data_to_vector(entry.get("player"), Vector2.ZERO)
		if entry_position.distance_to(boss_position) < immediate_range:
			errors.append("%s: entry '%s' begins inside the boss's immediate attack envelope." % [prefix, entry.get("id", "entry")])
	var phase_ids: Dictionary = {}
	var referenced_reinforcements: Dictionary = {}
	for phase_value in BossCatalog.phases(definition_data):
		if typeof(phase_value) != TYPE_DICTIONARY:
			continue
		var phase: Dictionary = phase_value
		var phase_id := BossCatalog.phase_id(phase)
		phase_ids[phase_id] = true
		for reinforcement_id in BossCatalog.phase_reinforcements(phase):
			referenced_reinforcements[reinforcement_id] = phase_id
			if not placements.has(reinforcement_id):
				errors.append("%s/phase/%s: reinforcement placement '%s' does not exist." % [prefix, phase_id, reinforcement_id])
				continue
			var reinforcement: Dictionary = placements[reinforcement_id]
			var reinforcement_definition := ObjectCatalog.definition(definitions, str(reinforcement.get("object_id", "")))
			if str(reinforcement_definition.get("kind", "")) != "enemy" or BossCatalog.is_boss(reinforcement_definition):
				errors.append("%s/phase/%s: reinforcement '%s' must reference a non-boss enemy." % [prefix, phase_id, reinforcement_id])
	for reinforcement_id in referenced_reinforcements.keys():
		var reinforcement: Dictionary = placements.get(reinforcement_id, {})
		var metadata_value: Variant = reinforcement.get("boss_reinforcement", {})
		if typeof(metadata_value) != TYPE_DICTIONARY:
			errors.append("%s: reinforcement '%s' requires boss_reinforcement metadata." % [prefix, reinforcement_id])
			continue
		var metadata: Dictionary = metadata_value
		if str(metadata.get("boss_placement_id", "")) != placement_id:
			errors.append("%s: reinforcement '%s' must reference boss placement '%s'." % [prefix, reinforcement_id, placement_id])
		if str(metadata.get("phase_id", "")) != str(referenced_reinforcements[reinforcement_id]):
			errors.append("%s: reinforcement '%s' phase metadata does not match its authored phase." % [prefix, reinforcement_id])
	if referenced_reinforcements.is_empty():
		warnings.append("%s: no phase activates reinforcements." % prefix)


static func validate_defeat_effects(
	value: Variant,
	prefix: String,
	items: Dictionary,
	currencies: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an array." % prefix)
		return
	for index in range((value as Array).size()):
		var effect_value: Variant = (value as Array)[index]
		if typeof(effect_value) != TYPE_DICTIONARY:
			errors.append("%s/%d: effect must be an object." % [prefix, index])
			continue
		var effect: Dictionary = effect_value
		var effect_type := str(effect.get("type", ""))
		var effect_prefix := "%s/%d" % [prefix, index]
		match effect_type:
			"grant_clock_shards":
				if int(effect.get("amount", 0)) <= 0:
					errors.append("%s: amount must be positive." % effect_prefix)
			"grant_item":
				if not items.has(str(effect.get("item_id", ""))):
					errors.append("%s: unknown item '%s'." % [effect_prefix, effect.get("item_id", "")])
				if int(effect.get("quantity", 0)) <= 0:
					errors.append("%s: quantity must be positive." % effect_prefix)
			"grant_currency":
				if not currencies.has(str(effect.get("currency_id", ""))):
					errors.append("%s: unknown currency '%s'." % [effect_prefix, effect.get("currency_id", "")])
				if int(effect.get("amount", 0)) <= 0:
					errors.append("%s: amount must be positive." % effect_prefix)
			"set_state":
				if str(effect.get("key", "")).strip_edges().is_empty():
					errors.append("%s: key is required." % effect_prefix)
			_:
				errors.append("%s: unsupported boss defeat effect '%s'." % [effect_prefix, effect_type])


static func validate_string_id_list(value: Variant, prefix: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an array." % prefix)
		return
	var seen: Dictionary = {}
	for item in value:
		var identifier := str(item).strip_edges()
		if identifier.is_empty():
			errors.append("%s contains an empty identifier." % prefix)
		elif seen.has(identifier):
			errors.append("%s repeats '%s'." % [prefix, identifier])
		seen[identifier] = true


static func load_maps(campaign_path: String, campaign: Dictionary, errors: Array[String]) -> Array:
	var output: Array = []
	var value: Variant = campaign.get("map_files", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for relative_value in value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			continue
		var result := Repository.read_json(campaign_path.get_base_dir().path_join(relative_path))
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		output.append(result.get("data", {}))
	return output


static func make_report(
	errors: Array[String],
	warnings: Array[String],
	boss_count: int,
	placement_count: int,
	phase_count: int,
	pattern_count: int,
	reinforcement_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"boss_count": boss_count,
		"boss_placement_count": placement_count,
		"boss_phase_count": phase_count,
		"boss_pattern_step_count": pattern_count,
		"boss_reinforcement_count": reinforcement_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
