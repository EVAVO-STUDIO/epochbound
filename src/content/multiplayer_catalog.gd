@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")

const SCHEMA_VERSION := 1
const TRANSPORT_ENET := "enet"
const PROGRESSION_HOST_ONLY := "host_only"
const REWARD_SESSION_ONLY := "session_only"
const AREA_SANCTUARY := "sanctuary"
const AREA_CO_OP := "co_op"
const AREA_PVP := "pvp"
const AREA_KINDS := [AREA_SANCTUARY, AREA_CO_OP, AREA_PVP]


static func default_policy() -> Dictionary:
	return {
		"enabled": false,
		"transport": TRANSPORT_ENET,
		"default_port": 27491,
		"max_allies": 2,
		"max_invaders": 1,
		"snapshot_rate_hz": 12,
		"input_rate_hz": 30,
		"shared_progression": PROGRESSION_HOST_ONLY,
		"pvp_rewards": REWARD_SESSION_ONLY,
		"friendly_fire": false
	}


static func policy(campaign: Dictionary) -> Dictionary:
	var output := default_policy()
	var raw_value: Variant = campaign.get("multiplayer", {})
	if typeof(raw_value) != TYPE_DICTIONARY:
		return output
	var raw: Dictionary = raw_value
	if typeof(raw.get("enabled")) == TYPE_BOOL:
		output["enabled"] = bool(raw.get("enabled"))
	if typeof(raw.get("transport")) == TYPE_STRING:
		output["transport"] = str(raw.get("transport"))
	if typeof(raw.get("default_port")) == TYPE_INT:
		output["default_port"] = clampi(int(raw.get("default_port")), 1024, 65535)
	if typeof(raw.get("max_allies")) == TYPE_INT:
		output["max_allies"] = clampi(int(raw.get("max_allies")), 0, 2)
	if typeof(raw.get("max_invaders")) == TYPE_INT:
		output["max_invaders"] = clampi(int(raw.get("max_invaders")), 0, 1)
	if typeof(raw.get("snapshot_rate_hz")) == TYPE_INT:
		output["snapshot_rate_hz"] = clampi(int(raw.get("snapshot_rate_hz")), 4, 30)
	if typeof(raw.get("input_rate_hz")) == TYPE_INT:
		output["input_rate_hz"] = clampi(int(raw.get("input_rate_hz")), 10, 60)
	if typeof(raw.get("shared_progression")) == TYPE_STRING:
		output["shared_progression"] = str(raw.get("shared_progression"))
	if typeof(raw.get("pvp_rewards")) == TYPE_STRING:
		output["pvp_rewards"] = str(raw.get("pvp_rewards"))
	if typeof(raw.get("friendly_fire")) == TYPE_BOOL:
		output["friendly_fire"] = bool(raw.get("friendly_fire"))
	return output


static func default_catalog() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "areas": []}


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var definitions: Dictionary = {}
	var errors: Array[String] = []
	var paths_value: Variant = campaign.get("multiplayer_files", [])
	if typeof(paths_value) != TYPE_ARRAY:
		return {
			"ok": false,
			"definitions": definitions,
			"errors": ["Campaign multiplayer_files must be an array."]
		}
	for relative_value in paths_value as Array:
		if typeof(relative_value) != TYPE_STRING:
			errors.append("Every multiplayer_files entry must be a string.")
			continue
		var relative_path := str(relative_value)
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result := Repository.read_json(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var catalog_value: Variant = result.get("data", {})
		if typeof(catalog_value) != TYPE_DICTIONARY:
			errors.append("Multiplayer catalog root must be an object: %s" % path)
			continue
		var catalog: Dictionary = catalog_value
		var areas_value: Variant = catalog.get("areas", [])
		if typeof(areas_value) != TYPE_ARRAY:
			errors.append("Multiplayer catalog areas must be an array: %s" % path)
			continue
		for area_value in areas_value as Array:
			if typeof(area_value) != TYPE_DICTIONARY:
				errors.append("Every multiplayer area must be an object: %s" % path)
				continue
			var area: Dictionary = (area_value as Dictionary).duplicate(true)
			var area_id := str(area.get("id", ""))
			if area_id.is_empty():
				errors.append("Multiplayer area is missing an ID: %s" % path)
				continue
			if definitions.has(area_id):
				errors.append("Multiplayer area ID is duplicated: %s" % area_id)
				continue
			area["source_path"] = relative_path
			definitions[area_id] = area
	return {"ok": errors.is_empty(), "definitions": definitions, "errors": errors}


static func areas_for_map(definitions: Dictionary, map_id: String) -> Array:
	var ids := PackedStringArray()
	for key in definitions.keys():
		ids.append(str(key))
	ids.sort()
	var output: Array = []
	for area_id in ids:
		var value: Variant = definitions.get(area_id, {})
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var area: Dictionary = value
		if str(area.get("map_id", "")) == map_id:
			output.append(area.duplicate(true))
	return output


static func area_bounds(area: Dictionary) -> Rect2:
	var value: Variant = area.get("bounds", {})
	if typeof(value) != TYPE_DICTIONARY:
		return Rect2()
	var bounds: Dictionary = value
	var left := float(bounds.get("left", 0.0))
	var right := float(bounds.get("right", left))
	var top := float(bounds.get("top", 0.0))
	var bottom := float(bounds.get("bottom", top))
	return Rect2(left, top, maxf(0.0, right - left), maxf(0.0, bottom - top))


static func available_in_era(area: Dictionary, era_id: String) -> bool:
	var value: Variant = area.get("available_eras", [])
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return true
	for candidate in value as Array:
		if typeof(candidate) == TYPE_STRING and str(candidate) == era_id:
			return true
	return false


static func area_contains(area: Dictionary, position: Vector2, era_id: String) -> bool:
	return available_in_era(area, era_id) and area_bounds(area).has_point(position)


static func active_area(
	definitions: Dictionary,
	map_id: String,
	era_id: String,
	position: Vector2
) -> Dictionary:
	var best: Dictionary = {}
	var best_priority := -2147483648
	var best_size := INF
	for area_value in areas_for_map(definitions, map_id):
		var area: Dictionary = area_value
		if not area_contains(area, position, era_id):
			continue
		var priority := int(area.get("priority", 0))
		var rect := area_bounds(area)
		var size := rect.size.x * rect.size.y
		var area_id := str(area.get("id", ""))
		var best_id := str(best.get("id", ""))
		if (
			best.is_empty()
			or priority > best_priority
			or (priority == best_priority and size < best_size)
			or (priority == best_priority and is_equal_approx(size, best_size) and area_id < best_id)
		):
			best = area.duplicate(true)
			best_priority = priority
			best_size = size
	return best


static func first_available_area(
	definitions: Dictionary,
	map_id: String,
	era_id: String
) -> Dictionary:
	var best: Dictionary = {}
	var best_priority := -2147483648
	for area_value in areas_for_map(definitions, map_id):
		var area: Dictionary = area_value
		if not available_in_era(area, era_id):
			continue
		var priority := int(area.get("priority", 0))
		if best.is_empty() or priority > best_priority:
			best = area.duplicate(true)
			best_priority = priority
	return best


static func spawn_position(area: Dictionary, role: String, fallback: Vector2) -> Vector2:
	var key := "invader_spawn" if role == "invader" else "ally_spawn"
	return Repository.data_to_vector(area.get(key), fallback)


static func area_kind(area: Dictionary) -> String:
	return str(area.get("kind", AREA_CO_OP))


static func area_name(area: Dictionary) -> String:
	return str(area.get("display_name", area.get("id", "Online Area")))


static func allies_allowed(area: Dictionary) -> bool:
	return bool(area.get("allow_allies", true))


static func invaders_allowed(area: Dictionary) -> bool:
	return area_kind(area) == AREA_PVP and bool(area.get("allow_invaders", false))


static func friendly_fire_allowed(area: Dictionary, campaign_policy: Dictionary) -> bool:
	return bool(area.get("friendly_fire", campaign_policy.get("friendly_fire", false)))


static func area_summary(area: Dictionary) -> String:
	if area.is_empty():
		return "OFFLINE WORLD"
	match area_kind(area):
		AREA_SANCTUARY:
			return "%s  •  SANCTUARY" % area_name(area).to_upper()
		AREA_PVP:
			return "%s  •  INVASION AREA" % area_name(area).to_upper()
	return "%s  •  CO-OP" % area_name(area).to_upper()


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value as Array:
		target.append(str(message))
