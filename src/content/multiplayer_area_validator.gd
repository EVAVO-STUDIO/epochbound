@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const MultiplayerCatalog = preload("res://src/content/multiplayer_catalog.gd")


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_count := 0
	var area_count := 0
	var pvp_area_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := validate_multiplayer_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		campaign_count += int(report.get("multiplayer_campaign_count", 0))
		area_count += int(report.get("multiplayer_area_count", 0))
		pvp_area_count += int(report.get("pvp_area_count", 0))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"multiplayer_campaign_count": campaign_count,
		"multiplayer_area_count": area_count,
		"pvp_area_count": pvp_area_count
	}


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	return validate_multiplayer_only(campaign_path)


static func validate_multiplayer_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return base_report(errors, warnings, 0, 0, 0)
	var campaign_value: Variant = campaign_result.get("data", {})
	if typeof(campaign_value) != TYPE_DICTIONARY:
		errors.append("Campaign root must be an object: %s" % campaign_path)
		return base_report(errors, warnings, 0, 0, 0)
	var campaign: Dictionary = campaign_value
	var campaign_id := str(campaign.get("id", campaign_path))
	var raw_policy_value: Variant = campaign.get("multiplayer", {})
	if campaign.has("multiplayer") and typeof(raw_policy_value) != TYPE_DICTIONARY:
		errors.append("%s/multiplayer must be an object." % campaign_id)
	var raw_policy: Dictionary = raw_policy_value if typeof(raw_policy_value) == TYPE_DICTIONARY else {}
	validate_policy(raw_policy, "%s/multiplayer" % campaign_id, errors)
	var policy := MultiplayerCatalog.policy(campaign)
	var enabled := bool(policy.get("enabled", false))

	var files_value: Variant = campaign.get("multiplayer_files", [])
	if campaign.has("multiplayer_files") and typeof(files_value) != TYPE_ARRAY:
		errors.append("%s/multiplayer_files must be an array." % campaign_id)
	var map_lookup := load_map_lookup(campaign_path, campaign, errors)
	var catalog_result := MultiplayerCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, catalog_result.get("errors", []))
	var definitions_value: Variant = catalog_result.get("definitions", {})
	var definitions: Dictionary = definitions_value if typeof(definitions_value) == TYPE_DICTIONARY else {}

	var map_area_counts: Dictionary = {}
	var pvp_count := 0
	var ids := PackedStringArray()
	for key in definitions.keys():
		ids.append(str(key))
	ids.sort()
	for area_id in ids:
		var area_value: Variant = definitions.get(area_id, {})
		if typeof(area_value) != TYPE_DICTIONARY:
			continue
		var area: Dictionary = area_value
		validate_area(area, "%s/multiplayer_area/%s" % [campaign_id, area_id], map_lookup, errors, warnings)
		var map_id := str(area.get("map_id", ""))
		map_area_counts[map_id] = int(map_area_counts.get(map_id, 0)) + 1
		if MultiplayerCatalog.area_kind(area) == MultiplayerCatalog.AREA_PVP:
			pvp_count += 1

	if enabled:
		if definitions.is_empty():
			errors.append("%s: multiplayer is enabled but no multiplayer areas are authored." % campaign_id)
		for map_id in map_lookup.keys():
			if int(map_area_counts.get(str(map_id), 0)) <= 0:
				errors.append("%s: multiplayer-enabled map '%s' has no authored online area." % [campaign_id, map_id])
		if int(policy.get("max_invaders", 0)) > 0 and pvp_count <= 0:
			errors.append("%s: max_invaders is positive but no PvP area is authored." % campaign_id)
	elif not definitions.is_empty():
		warnings.append("%s: multiplayer areas are authored while the campaign multiplayer policy is disabled." % campaign_id)

	return base_report(
		errors,
		warnings,
		1 if enabled else 0,
		definitions.size(),
		pvp_count
	)


static func validate_profile_multiplayer(payload: Dictionary, errors: Array[String]) -> void:
	for forbidden_key in [
		"multiplayer_session",
		"multiplayer_peers",
		"network_players",
		"peer_roles",
		"invasion_state",
		"online_area_id",
		"online_role"
	]:
		if payload.has(forbidden_key):
			errors.append("Save payload must not persist ephemeral multiplayer field '%s'." % forbidden_key)


static func validate_policy(policy: Dictionary, prefix: String, errors: Array[String]) -> void:
	validate_optional_bool(policy, "enabled", prefix, errors)
	validate_optional_string(policy, "transport", prefix, errors)
	if policy.has("transport") and typeof(policy.get("transport")) == TYPE_STRING and str(policy.get("transport")) != MultiplayerCatalog.TRANSPORT_ENET:
		errors.append("%s/transport must be '%s'." % [prefix, MultiplayerCatalog.TRANSPORT_ENET])
	validate_optional_int_range(policy, "default_port", 1024, 65535, prefix, errors)
	validate_optional_int_range(policy, "max_allies", 0, 2, prefix, errors)
	validate_optional_int_range(policy, "max_invaders", 0, 1, prefix, errors)
	validate_optional_int_range(policy, "snapshot_rate_hz", 4, 30, prefix, errors)
	validate_optional_int_range(policy, "input_rate_hz", 10, 60, prefix, errors)
	validate_optional_string(policy, "shared_progression", prefix, errors)
	if policy.has("shared_progression") and typeof(policy.get("shared_progression")) == TYPE_STRING and str(policy.get("shared_progression")) != MultiplayerCatalog.PROGRESSION_HOST_ONLY:
		errors.append("%s/shared_progression must be '%s'." % [prefix, MultiplayerCatalog.PROGRESSION_HOST_ONLY])
	validate_optional_string(policy, "pvp_rewards", prefix, errors)
	if policy.has("pvp_rewards") and typeof(policy.get("pvp_rewards")) == TYPE_STRING and str(policy.get("pvp_rewards")) != MultiplayerCatalog.REWARD_SESSION_ONLY:
		errors.append("%s/pvp_rewards must be '%s'." % [prefix, MultiplayerCatalog.REWARD_SESSION_ONLY])
	validate_optional_bool(policy, "friendly_fire", prefix, errors)


static func validate_area(
	area: Dictionary,
	prefix: String,
	map_lookup: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	validate_required_string(area, "id", prefix, errors)
	validate_required_string(area, "display_name", prefix, errors)
	validate_required_string(area, "map_id", prefix, errors)
	validate_required_string(area, "kind", prefix, errors)
	var area_id := str(area.get("id", ""))
	if not area_id.is_empty() and Repository.normalise_id(area_id) != area_id:
		errors.append("%s/id must be a normalised identifier." % prefix)
	var kind := str(area.get("kind", ""))
	if not MultiplayerCatalog.AREA_KINDS.has(kind):
		errors.append("%s/kind must be sanctuary, co_op or pvp." % prefix)
	if area.has("priority") and typeof(area.get("priority")) != TYPE_INT:
		errors.append("%s/priority must be an integer." % prefix)
	elif int(area.get("priority", 0)) < -100 or int(area.get("priority", 0)) > 100:
		errors.append("%s/priority must be between -100 and 100." % prefix)
	validate_optional_bool(area, "allow_allies", prefix, errors)
	validate_optional_bool(area, "allow_invaders", prefix, errors)
	validate_optional_bool(area, "friendly_fire", prefix, errors)
	if kind != MultiplayerCatalog.AREA_PVP and bool(area.get("allow_invaders", false)):
		errors.append("%s: only PvP areas may allow invaders." % prefix)
	if kind == MultiplayerCatalog.AREA_SANCTUARY and bool(area.get("friendly_fire", false)):
		errors.append("%s: sanctuary areas cannot enable friendly fire." % prefix)

	var map_id := str(area.get("map_id", ""))
	var map_value: Variant = map_lookup.get(map_id, {})
	if typeof(map_value) != TYPE_DICTIONARY or (map_value as Dictionary).is_empty():
		errors.append("%s/map_id references unknown map '%s'." % [prefix, map_id])
		return
	var map_data: Dictionary = map_value
	var bounds := validate_bounds(area.get("bounds"), "%s/bounds" % prefix, errors)
	var map_bounds := map_rect(map_data)
	if not bounds.has_area():
		return
	if (
		bounds.position.x < map_bounds.position.x
		or bounds.position.y < map_bounds.position.y
		or bounds.end.x > map_bounds.end.x
		or bounds.end.y > map_bounds.end.y
	):
		errors.append("%s/bounds must remain inside map '%s'." % [prefix, map_id])
	var era_ids := map_era_ids(map_data)
	var eras_value: Variant = area.get("available_eras", [])
	if typeof(eras_value) != TYPE_ARRAY:
		errors.append("%s/available_eras must be an array." % prefix)
	else:
		for era_value in eras_value as Array:
			if typeof(era_value) != TYPE_STRING:
				errors.append("%s/available_eras entries must be strings." % prefix)
			elif not era_ids.has(str(era_value)):
				errors.append("%s/available_eras references unknown era '%s'." % [prefix, era_value])
	validate_spawn(area, "ally_spawn", bounds, prefix, errors)
	if kind == MultiplayerCatalog.AREA_PVP or bool(area.get("allow_invaders", false)):
		validate_spawn(area, "invader_spawn", bounds, prefix, errors)
	elif area.has("invader_spawn"):
		warnings.append("%s: invader_spawn is authored for a non-PvP area." % prefix)


static func validate_spawn(
	area: Dictionary,
	key: String,
	bounds: Rect2,
	prefix: String,
	errors: Array[String]
) -> void:
	if not area.has(key):
		errors.append("%s/%s is required." % [prefix, key])
		return
	var value: Variant = area.get(key)
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s/%s must be an object with numeric x and y." % [prefix, key])
		return
	var data: Dictionary = value
	if typeof(data.get("x")) not in [TYPE_INT, TYPE_FLOAT] or typeof(data.get("y")) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s/%s x and y must be numeric." % [prefix, key])
		return
	var position := Vector2(float(data.get("x")), float(data.get("y")))
	if not bounds.has_point(position):
		errors.append("%s/%s must remain inside the multiplayer area bounds." % [prefix, key])


static func validate_bounds(value: Variant, prefix: String, errors: Array[String]) -> Rect2:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be an object." % prefix)
		return Rect2()
	var data: Dictionary = value
	for key in ["left", "right", "top", "bottom"]:
		if typeof(data.get(key)) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("%s/%s must be numeric." % [prefix, key])
			return Rect2()
	var left := float(data.get("left"))
	var right := float(data.get("right"))
	var top := float(data.get("top"))
	var bottom := float(data.get("bottom"))
	if right <= left or bottom <= top:
		errors.append("%s must have positive width and height." % prefix)
		return Rect2()
	return Rect2(left, top, right - left, bottom - top)


static func load_map_lookup(
	campaign_path: String,
	campaign: Dictionary,
	errors: Array[String]
) -> Dictionary:
	var output: Dictionary = {}
	var files_value: Variant = campaign.get("map_files", [])
	if typeof(files_value) != TYPE_ARRAY:
		return output
	for relative_value in files_value as Array:
		if typeof(relative_value) != TYPE_STRING:
			continue
		var result := Repository.read_json(campaign_path.get_base_dir().path_join(str(relative_value)))
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var map_value: Variant = result.get("data", {})
		if typeof(map_value) != TYPE_DICTIONARY:
			continue
		var map_data: Dictionary = map_value
		output[str(map_data.get("id", ""))] = map_data
	return output


static func map_rect(map_data: Dictionary) -> Rect2:
	var bounds_value: Variant = map_data.get("bounds", {})
	var bounds: Dictionary = bounds_value if typeof(bounds_value) == TYPE_DICTIONARY else {}
	var left := float(bounds.get("left", 0.0))
	var right := float(bounds.get("right", left))
	var top := float(bounds.get("top", 0.0))
	var bottom := float(bounds.get("bottom", top))
	return Rect2(left, top, maxf(0.0, right - left), maxf(0.0, bottom - top))


static func map_era_ids(map_data: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var eras_value: Variant = map_data.get("eras", [])
	if typeof(eras_value) != TYPE_ARRAY:
		return output
	for era_value in eras_value as Array:
		if typeof(era_value) == TYPE_DICTIONARY:
			output.append(str((era_value as Dictionary).get("id", "")))
	return output


static func validate_required_string(
	source: Dictionary,
	key: String,
	prefix: String,
	errors: Array[String]
) -> void:
	if typeof(source.get(key)) != TYPE_STRING or str(source.get(key)).strip_edges().is_empty():
		errors.append("%s/%s must be a non-empty string." % [prefix, key])


static func validate_optional_string(
	source: Dictionary,
	key: String,
	prefix: String,
	errors: Array[String]
) -> void:
	if source.has(key) and typeof(source.get(key)) != TYPE_STRING:
		errors.append("%s/%s must be a string." % [prefix, key])


static func validate_optional_bool(
	source: Dictionary,
	key: String,
	prefix: String,
	errors: Array[String]
) -> void:
	if source.has(key) and typeof(source.get(key)) != TYPE_BOOL:
		errors.append("%s/%s must be boolean." % [prefix, key])


static func validate_optional_int_range(
	source: Dictionary,
	key: String,
	minimum: int,
	maximum: int,
	prefix: String,
	errors: Array[String]
) -> void:
	if not source.has(key):
		return
	if typeof(source.get(key)) != TYPE_INT:
		errors.append("%s/%s must be an integer." % [prefix, key])
		return
	var value := int(source.get(key))
	if value < minimum or value > maximum:
		errors.append("%s/%s must be between %d and %d." % [prefix, key, minimum, maximum])


static func base_report(
	errors: Array[String],
	warnings: Array[String],
	campaign_count: int,
	area_count: int,
	pvp_area_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"multiplayer_campaign_count": campaign_count,
		"multiplayer_area_count": area_count,
		"pvp_area_count": pvp_area_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value as Array:
		target.append(str(message))
