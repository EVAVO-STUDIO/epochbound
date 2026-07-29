@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const SUPPORTED_SCHEMA := 1
const ALLOWED_LAYER_TYPES := ["terrain", "objects", "collision", "navigation", "effects"]
const ALLOWED_LANDMARK_KINDS := ["marker", "sun", "ruin", "well", "tree", "dead_tree"]
const ALLOWED_CONNECTION_TRIGGERS := ["interact", "touch"]
const REQUIRED_PALETTE_KEYS := ["sky", "ground", "accent", "structure"]

static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_count := 0
	var map_count := 0
	for value in Repository.scan_campaigns(root):
		var entry: Dictionary = value
		campaign_count += 1
		var report := validate_campaign_path(String(entry.get("path", "")))
		_append_messages(errors, report.get("errors", []))
		_append_messages(warnings, report.get("warnings", []))
		map_count += int(report.get("map_count", 0))
	if campaign_count == 0:
		warnings.append("No campaigns were found under %s." % root)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"campaign_count": campaign_count,
		"map_count": map_count
	}

static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not campaign_result.get("ok", false):
		_append_messages(errors, campaign_result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings, "map_count": 0}
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id := String(campaign.get("id", ""))
	var prefix := campaign_id if not campaign_id.is_empty() else campaign_path
	if int(campaign.get("schema_version", 0)) != SUPPORTED_SCHEMA:
		errors.append("%s: unsupported campaign schema_version." % prefix)
	if campaign_id.is_empty() or Repository.normalise_id(campaign_id) != campaign_id:
		errors.append("%s: campaign id must be a normalised lowercase identifier." % prefix)
	if String(campaign.get("title", "")).strip_edges().is_empty():
		errors.append("%s: title is required." % prefix)
	if typeof(campaign.get("intro", [])) != TYPE_ARRAY:
		errors.append("%s: intro must be an array of text pages." % prefix)
	else:
		for page in campaign.get("intro", []):
			if typeof(page) != TYPE_STRING or String(page).strip_edges().is_empty():
				errors.append("%s: every intro page must contain text." % prefix)
	var companion_required := true
	var ruleset_value: Variant = campaign.get("ruleset", {})
	if typeof(ruleset_value) != TYPE_DICTIONARY:
		errors.append("%s: ruleset must be an object." % prefix)
	else:
		var ruleset: Dictionary = ruleset_value
		companion_required = bool(ruleset.get("companion_enabled", true))
		if String(ruleset.get("combat_model", "action")) != "action":
			errors.append("%s: unsupported combat_model '%s'." % [prefix, ruleset.get("combat_model", "")])
		for flag_name in ["companion_enabled", "era_shifting_enabled"]:
			if ruleset.has(flag_name) and typeof(ruleset.get(flag_name)) != TYPE_BOOL:
				errors.append("%s: ruleset flag '%s' must be boolean." % [prefix, flag_name])
	var actors_value: Variant = campaign.get("actors", {})
	if typeof(actors_value) != TYPE_DICTIONARY:
		errors.append("%s: actors must be an object." % prefix)
	else:
		var actors: Dictionary = actors_value
		_validate_actor(actors.get("player", {}), "%s/player" % prefix, errors)
		if companion_required:
			_validate_actor(actors.get("companion", {}), "%s/companion" % prefix, errors)
	var map_files_value: Variant = campaign.get("map_files", [])
	if typeof(map_files_value) != TYPE_ARRAY or Array(map_files_value).is_empty():
		errors.append("%s: map_files must contain at least one relative JSON path." % prefix)
		return {"ok": false, "errors": errors, "warnings": warnings, "map_count": 0}
	var map_ids: Dictionary = {}
	var maps_by_id: Dictionary = {}
	var map_reports: Array = []
	var map_count := 0
	for relative_value in map_files_value:
		var relative_path := String(relative_value)
		if not _is_safe_relative_path(relative_path):
			errors.append("%s: unsafe map path '%s'." % [prefix, relative_path])
			continue
		var map_path := campaign_path.get_base_dir().path_join(relative_path)
		var map_result := Repository.read_json(map_path)
		if not map_result.get("ok", false):
			_append_messages(errors, map_result.get("errors", []))
			continue
		map_count += 1
		var map_data: Dictionary = map_result.get("data", {})
		var report := validate_map(map_data, map_path)
		_append_messages(errors, report.get("errors", []))
		_append_messages(warnings, report.get("warnings", []))
		var map_id := String(map_data.get("id", ""))
		if map_ids.has(map_id):
			errors.append("%s: duplicate map id '%s'." % [prefix, map_id])
		else:
			map_ids[map_id] = true
			maps_by_id[map_id] = map_data
		map_reports.append({"path": map_path, "data": map_data})
	var start_map := String(campaign.get("start_map", ""))
	if not map_ids.has(start_map):
		errors.append("%s: start_map '%s' does not resolve to a declared map." % [prefix, start_map])
	else:
		var start_data: Dictionary = maps_by_id.get(start_map, {})
		var start_era := String(campaign.get("start_era", ""))
		if not _collect_ids(start_data.get("eras", [])).has(start_era):
			errors.append("%s: start_era '%s' does not exist in start_map." % [prefix, start_era])
	_validate_cross_map_connections(prefix, map_reports, maps_by_id, errors, warnings)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"map_count": map_count
	}

static func validate_map(map_data: Dictionary, path: String = "") -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var map_id := String(map_data.get("id", ""))
	var prefix := map_id if not map_id.is_empty() else path
	if int(map_data.get("schema_version", 0)) != SUPPORTED_SCHEMA:
		errors.append("%s: unsupported map schema_version." % prefix)
	if map_id.is_empty() or Repository.normalise_id(map_id) != map_id:
		errors.append("%s: map id must be a normalised lowercase identifier." % prefix)
	if String(map_data.get("display_name", "")).strip_edges().is_empty():
		errors.append("%s: display_name is required." % prefix)
	var canvas_value: Variant = map_data.get("canvas", {})
	if typeof(canvas_value) != TYPE_DICTIONARY:
		errors.append("%s: canvas must be an object." % prefix)
		canvas_value = {}
	var canvas: Dictionary = canvas_value
	var width := int(canvas.get("width", 0))
	var height := int(canvas.get("height", 0))
	var grid_size := int(canvas.get("grid_size", 0))
	if width < 160 or height < 90:
		errors.append("%s: canvas must be at least 160 by 90 pixels." % prefix)
	if grid_size < 1 or grid_size > 128:
		errors.append("%s: grid_size must be between 1 and 128." % prefix)
	var bounds_value: Variant = map_data.get("bounds", {})
	if typeof(bounds_value) != TYPE_DICTIONARY:
		errors.append("%s: bounds must be an object." % prefix)
		bounds_value = {}
	var bounds: Dictionary = bounds_value
	var left := float(bounds.get("left", 0))
	var right := float(bounds.get("right", width))
	var top := float(bounds.get("top", 0))
	var bottom := float(bounds.get("bottom", height))
	if left < 0.0 or top < 0.0 or right > width or bottom > height:
		errors.append("%s: movement bounds must remain inside the canvas." % prefix)
	if left >= right:
		errors.append("%s: bounds left must be less than right." % prefix)
	if top >= bottom:
		errors.append("%s: bounds top must be less than bottom." % prefix)
	var era_ids := _collect_ids(map_data.get("eras", []))
	if era_ids.is_empty():
		errors.append("%s: at least one era is required." % prefix)
	elif era_ids.size() == 1:
		warnings.append("%s: only one era is defined; era shifting will have no effect." % prefix)
	_validate_unique_entries(map_data.get("eras", []), "era", prefix, errors)
	_validate_eras(map_data.get("eras", []), prefix, width, height, errors, warnings)
	_validate_layers(map_data.get("layers", []), prefix, errors)
	var spawns_value: Variant = map_data.get("spawns", {})
	if typeof(spawns_value) != TYPE_DICTIONARY:
		errors.append("%s: spawns must be an object." % prefix)
		spawns_value = {}
	var spawns: Dictionary = spawns_value
	for spawn_name in ["player", "companion"]:
		if not spawns.has(spawn_name):
			errors.append("%s: missing %s spawn." % [prefix, spawn_name])
		else:
			_validate_position(spawns.get(spawn_name), "%s %s spawn" % [prefix, spawn_name], width, height, errors)
	var terrain_ids := _validate_terrain_palette(map_data.get("terrain_palette", []), prefix, era_ids, errors, warnings)
	_validate_cell_collection(
		map_data.get("terrain_cells", []),
		"terrain_cells",
		prefix,
		width,
		height,
		grid_size,
		era_ids,
		terrain_ids,
		errors,
		warnings
	)
	_validate_cell_collection(
		map_data.get("collision_cells", []),
		"collision_cells",
		prefix,
		width,
		height,
		grid_size,
		era_ids,
		{},
		errors,
		warnings
	)
	_validate_cell_collection(
		map_data.get("navigation_cells", []),
		"navigation_cells",
		prefix,
		width,
		height,
		grid_size,
		era_ids,
		{},
		errors,
		warnings
	)
	_validate_position_markers(
		map_data.get("recovery_anchors", []),
		"recovery anchor",
		prefix,
		width,
		height,
		era_ids,
		errors,
		warnings
	)
	_validate_entry_points(
		map_data.get("entry_points", []),
		prefix,
		width,
		height,
		era_ids,
		errors,
		warnings
	)
	_validate_interactions(map_data.get("interactions", []), prefix, width, height, era_ids, errors, warnings)
	_validate_connections(map_data.get("connections", []), prefix, width, height, era_ids, errors, warnings)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}

static func _validate_actor(value: Variant, prefix: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: actor data is required." % prefix)
		return
	var actor: Dictionary = value
	if String(actor.get("name", "")).strip_edges().is_empty():
		errors.append("%s: actor name is required." % prefix)
	if int(actor.get("max_health", 0)) < 1:
		errors.append("%s: max_health must be positive." % prefix)

static func _validate_eras(
	value: Variant,
	prefix: String,
	width: int,
	height: int,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for era_value in value:
		if typeof(era_value) != TYPE_DICTIONARY:
			errors.append("%s: era entries must be objects." % prefix)
			continue
		var era: Dictionary = era_value
		var era_id := String(era.get("id", ""))
		if String(era.get("display_name", "")).strip_edges().is_empty():
			errors.append("%s/%s: era display_name is required." % [prefix, era_id])
		var palette_value: Variant = era.get("palette", {})
		if typeof(palette_value) != TYPE_DICTIONARY:
			errors.append("%s/%s: palette must be an object." % [prefix, era_id])
		else:
			var palette: Dictionary = palette_value
			for key in REQUIRED_PALETTE_KEYS:
				var color_value := String(palette.get(key, ""))
				if not Color.html_is_valid(color_value):
					errors.append("%s/%s: palette '%s' is not a valid HTML colour." % [prefix, era_id, key])
		var landmark_ids: Dictionary = {}
		for landmark_value in era.get("landmarks", []):
			if typeof(landmark_value) != TYPE_DICTIONARY:
				errors.append("%s/%s: landmark entries must be objects." % [prefix, era_id])
				continue
			var landmark: Dictionary = landmark_value
			var landmark_id := String(landmark.get("id", ""))
			if landmark_id.is_empty() or Repository.normalise_id(landmark_id) != landmark_id:
				errors.append("%s/%s: landmark ids must be normalised lowercase identifiers." % [prefix, era_id])
			elif landmark_ids.has(landmark_id):
				errors.append("%s/%s: duplicate landmark id '%s'." % [prefix, era_id, landmark_id])
			else:
				landmark_ids[landmark_id] = true
			var kind := String(landmark.get("kind", "marker"))
			if not ALLOWED_LANDMARK_KINDS.has(kind):
				errors.append("%s/%s/%s: unsupported landmark kind '%s'." % [prefix, era_id, landmark_id, kind])
			_validate_position(landmark.get("position"), "%s/%s landmark %s" % [prefix, era_id, landmark_id], width, height, errors)
			if float(landmark.get("size", 0.0)) <= 0.0:
				errors.append("%s/%s/%s: landmark size must be positive." % [prefix, era_id, landmark_id])
		if landmark_ids.is_empty():
			warnings.append("%s/%s: era has no landmarks." % [prefix, era_id])

static func _validate_terrain_palette(
	value: Variant,
	prefix: String,
	era_ids: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> Dictionary:
	var ids: Dictionary = {}
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: terrain_palette must be an array." % prefix)
		return ids
	if Array(value).is_empty():
		warnings.append("%s: no terrain palette is defined; terrain painting is unavailable." % prefix)
	for definition_value in value:
		if typeof(definition_value) != TYPE_DICTIONARY:
			errors.append("%s: terrain palette entries must be objects." % prefix)
			continue
		var definition: Dictionary = definition_value
		var terrain_id := String(definition.get("id", ""))
		if terrain_id.is_empty() or Repository.normalise_id(terrain_id) != terrain_id:
			errors.append("%s: terrain ids must be normalised lowercase identifiers." % prefix)
		elif ids.has(terrain_id):
			errors.append("%s: duplicate terrain id '%s'." % [prefix, terrain_id])
		else:
			ids[terrain_id] = true
		if String(definition.get("display_name", "")).strip_edges().is_empty():
			errors.append("%s/%s: terrain display_name is required." % [prefix, terrain_id])
		if definition.has("blocked") and typeof(definition.get("blocked")) != TYPE_BOOL:
			errors.append("%s/%s: terrain blocked must be boolean." % [prefix, terrain_id])
		var colors_value: Variant = definition.get("colors", {})
		if typeof(colors_value) != TYPE_DICTIONARY:
			errors.append("%s/%s: terrain colors must be an object." % [prefix, terrain_id])
			continue
		var colors: Dictionary = colors_value
		if not colors.has("default"):
			warnings.append("%s/%s: terrain has no default colour." % [prefix, terrain_id])
		for key in colors.keys():
			var color_key := String(key)
			if color_key != "default" and not era_ids.has(color_key):
				errors.append("%s/%s: terrain colour references unknown era '%s'." % [prefix, terrain_id, color_key])
			if not Color.html_is_valid(String(colors.get(key, ""))):
				errors.append("%s/%s: terrain colour '%s' is invalid." % [prefix, terrain_id, color_key])
	return ids

static func _validate_cell_collection(
	value: Variant,
	collection: String,
	prefix: String,
	width: int,
	height: int,
	grid_size: int,
	era_ids: Dictionary,
	terrain_ids: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: %s must be an array." % [prefix, collection])
		return
	if grid_size <= 0:
		return
	var grid_width := ceili(float(width) / float(grid_size))
	var grid_height := ceili(float(height) / float(grid_size))
	var occupied: Dictionary = {}
	for record_value in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("%s: %s entries must be objects." % [prefix, collection])
			continue
		var record: Dictionary = record_value
		var x_value := float(record.get("x", -1))
		var y_value := float(record.get("y", -1))
		var x := int(x_value)
		var y := int(y_value)
		if x_value != float(x) or y_value != float(y):
			errors.append("%s/%s: cell coordinates must be integers." % [prefix, collection])
		if x < 0 or y < 0 or x >= grid_width or y >= grid_height:
			errors.append("%s/%s: cell (%d, %d) lies outside the grid." % [prefix, collection, x, y])
		_validate_available_eras(record, "%s/%s cell (%d, %d)" % [prefix, collection, x, y], era_ids, errors)
		var signature := "%d:%d:%s" % [x, y, _scope_signature(record.get("available_eras", []))]
		if occupied.has(signature):
			errors.append("%s/%s: duplicate cell (%d, %d) for the same era scope." % [prefix, collection, x, y])
		else:
			occupied[signature] = true
		if collection == "terrain_cells":
			var terrain_id := String(record.get("tile", ""))
			if terrain_id.is_empty() or not terrain_ids.has(terrain_id):
				errors.append("%s/terrain_cells: unknown terrain tile '%s'." % [prefix, terrain_id])
	if collection == "navigation_cells" and Array(value).is_empty():
		warnings.append("%s: navigation_cells is empty; companion movement will use direct fallback steering." % prefix)

static func _validate_position_markers(
	value: Variant,
	label: String,
	prefix: String,
	width: int,
	height: int,
	era_ids: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: %ss must be an array." % [prefix, label])
		return
	var ids: Dictionary = {}
	for marker_value in value:
		if typeof(marker_value) != TYPE_DICTIONARY:
			errors.append("%s: %s entries must be objects." % [prefix, label])
			continue
		var marker: Dictionary = marker_value
		var marker_id := String(marker.get("id", ""))
		if marker_id.is_empty() or Repository.normalise_id(marker_id) != marker_id:
			errors.append("%s: %s ids must be normalised lowercase identifiers." % [prefix, label])
		elif ids.has(marker_id):
			errors.append("%s: duplicate %s id '%s'." % [prefix, label, marker_id])
		else:
			ids[marker_id] = true
		_validate_position(marker.get("position"), "%s %s %s" % [prefix, label, marker_id], width, height, errors)
		_validate_available_eras(marker, "%s/%s" % [prefix, marker_id], era_ids, errors)
	if ids.is_empty():
		warnings.append("%s: no %ss are defined." % [prefix, label])

static func _validate_entry_points(
	value: Variant,
	prefix: String,
	width: int,
	height: int,
	era_ids: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: entry_points must be an array." % prefix)
		return
	var ids: Dictionary = {}
	for entry_value in value:
		if typeof(entry_value) != TYPE_DICTIONARY:
			errors.append("%s: entry point records must be objects." % prefix)
			continue
		var entry: Dictionary = entry_value
		var entry_id := String(entry.get("id", ""))
		if entry_id.is_empty() or Repository.normalise_id(entry_id) != entry_id:
			errors.append("%s: entry point ids must be normalised lowercase identifiers." % prefix)
		elif ids.has(entry_id):
			errors.append("%s: duplicate entry point id '%s'." % [prefix, entry_id])
		else:
			ids[entry_id] = true
		_validate_position(entry.get("player"), "%s entry %s player" % [prefix, entry_id], width, height, errors)
		_validate_position(entry.get("companion"), "%s entry %s companion" % [prefix, entry_id], width, height, errors)
		_validate_available_eras(entry, "%s/%s" % [prefix, entry_id], era_ids, errors)
	if ids.is_empty():
		warnings.append("%s: no entry_points are defined; incoming connections cannot target this map." % prefix)

static func _validate_interactions(
	value: Variant,
	prefix: String,
	width: int,
	height: int,
	era_ids: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: interactions must be an array." % prefix)
		return
	var ids: Dictionary = {}
	for interaction_value in value:
		if typeof(interaction_value) != TYPE_DICTIONARY:
			errors.append("%s: interaction entries must be objects." % prefix)
			continue
		var interaction: Dictionary = interaction_value
		var interaction_id := String(interaction.get("id", ""))
		if interaction_id.is_empty() or Repository.normalise_id(interaction_id) != interaction_id:
			errors.append("%s: interaction ids must be normalised lowercase identifiers." % prefix)
		elif ids.has(interaction_id):
			errors.append("%s: duplicate interaction id '%s'." % [prefix, interaction_id])
		else:
			ids[interaction_id] = true
		_validate_position(interaction.get("position"), "%s interaction %s" % [prefix, interaction_id], width, height, errors)
		if float(interaction.get("radius", 0.0)) <= 0.0:
			errors.append("%s/%s: radius must be positive." % [prefix, interaction_id])
		_validate_available_eras(interaction, "%s/%s" % [prefix, interaction_id], era_ids, errors)
		var dialogue: Variant = interaction.get("dialogue", "")
		if typeof(dialogue) == TYPE_STRING and String(dialogue).strip_edges().is_empty():
			warnings.append("%s/%s: interaction has no dialogue." % [prefix, interaction_id])
		elif typeof(dialogue) == TYPE_DICTIONARY:
			var dialogue_by_era: Dictionary = dialogue
			for key in dialogue_by_era.keys():
				if String(key) != "default" and not era_ids.has(String(key)):
					errors.append("%s/%s: dialogue references unknown era '%s'." % [prefix, interaction_id, key])
				if String(dialogue_by_era.get(key, "")).strip_edges().is_empty():
					warnings.append("%s/%s: dialogue for '%s' is empty." % [prefix, interaction_id, key])
		else:
			errors.append("%s/%s: dialogue must be text or an era-keyed object." % [prefix, interaction_id])

static func _validate_connections(
	value: Variant,
	prefix: String,
	width: int,
	height: int,
	era_ids: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: connections must be an array." % prefix)
		return
	var ids: Dictionary = {}
	for connection_value in value:
		if typeof(connection_value) != TYPE_DICTIONARY:
			errors.append("%s: connection entries must be objects." % prefix)
			continue
		var connection: Dictionary = connection_value
		var connection_id := String(connection.get("id", ""))
		if connection_id.is_empty() or Repository.normalise_id(connection_id) != connection_id:
			errors.append("%s: connection ids must be normalised lowercase identifiers." % prefix)
		elif ids.has(connection_id):
			errors.append("%s: duplicate connection id '%s'." % [prefix, connection_id])
		else:
			ids[connection_id] = true
		_validate_position(connection.get("position"), "%s connection %s" % [prefix, connection_id], width, height, errors)
		if float(connection.get("radius", 0.0)) <= 0.0:
			errors.append("%s/%s: connection radius must be positive." % [prefix, connection_id])
		var trigger := String(connection.get("trigger", "interact"))
		if not ALLOWED_CONNECTION_TRIGGERS.has(trigger):
			errors.append("%s/%s: unsupported connection trigger '%s'." % [prefix, connection_id, trigger])
		if String(connection.get("target_map", "")).is_empty():
			errors.append("%s/%s: target_map is required." % [prefix, connection_id])
		if String(connection.get("target_entry", "")).is_empty():
			errors.append("%s/%s: target_entry is required." % [prefix, connection_id])
		_validate_available_eras(connection, "%s/%s" % [prefix, connection_id], era_ids, errors)
		if trigger == "touch" and float(connection.get("radius", 0.0)) < 8.0:
			warnings.append("%s/%s: touch connection radius is very small." % [prefix, connection_id])

static func _validate_cross_map_connections(
	campaign_prefix: String,
	map_reports: Array,
	maps_by_id: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	for record_value in map_reports:
		var record: Dictionary = record_value
		var source_map: Dictionary = record.get("data", {})
		var source_id := String(source_map.get("id", "map"))
		for connection_value in source_map.get("connections", []):
			if typeof(connection_value) != TYPE_DICTIONARY:
				continue
			var connection: Dictionary = connection_value
			var connection_id := String(connection.get("id", "connection"))
			var target_map_id := String(connection.get("target_map", ""))
			if not maps_by_id.has(target_map_id):
				errors.append("%s/%s/%s: target map '%s' is missing." % [campaign_prefix, source_id, connection_id, target_map_id])
				continue
			var target_map: Dictionary = maps_by_id[target_map_id]
			var target_entry_id := String(connection.get("target_entry", ""))
			var entry_ids := _collect_ids(target_map.get("entry_points", []))
			if not entry_ids.has(target_entry_id):
				errors.append("%s/%s/%s: target entry '%s' is missing from map '%s'." % [campaign_prefix, source_id, connection_id, target_entry_id, target_map_id])
			var target_era := String(connection.get("target_era", "same"))
			if target_era.is_empty():
				target_era = "same"
			if target_era != "same" and not _collect_ids(target_map.get("eras", [])).has(target_era):
				errors.append("%s/%s/%s: target era '%s' is missing from map '%s'." % [campaign_prefix, source_id, connection_id, target_era, target_map_id])
			if target_map_id == source_id and target_entry_id.is_empty():
				warnings.append("%s/%s/%s: self connection has no target entry." % [campaign_prefix, source_id, connection_id])

static func _validate_layers(value: Variant, prefix: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY or Array(value).is_empty():
		errors.append("%s: layers must contain at least one layer." % prefix)
		return
	var ids: Dictionary = {}
	for layer_value in value:
		if typeof(layer_value) != TYPE_DICTIONARY:
			errors.append("%s: layer entries must be objects." % prefix)
			continue
		var layer: Dictionary = layer_value
		var layer_id := String(layer.get("id", ""))
		if layer_id.is_empty() or ids.has(layer_id):
			errors.append("%s: layer ids must be present and unique." % prefix)
		else:
			ids[layer_id] = true
		if not ALLOWED_LAYER_TYPES.has(String(layer.get("type", ""))):
			errors.append("%s/%s: unsupported layer type '%s'." % [prefix, layer_id, layer.get("type", "")])
		for flag_name in ["visible", "locked"]:
			if layer.has(flag_name) and typeof(layer.get(flag_name)) != TYPE_BOOL:
				errors.append("%s/%s: layer flag '%s' must be boolean." % [prefix, layer_id, flag_name])

static func _validate_unique_entries(value: Variant, label: String, prefix: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: %ss must be an array." % [prefix, label])
		return
	var ids: Dictionary = {}
	for entry_value in value:
		if typeof(entry_value) != TYPE_DICTIONARY:
			errors.append("%s: %s entries must be objects." % [prefix, label])
			continue
		var entry: Dictionary = entry_value
		var entry_id := String(entry.get("id", ""))
		if entry_id.is_empty() or Repository.normalise_id(entry_id) != entry_id or ids.has(entry_id):
			errors.append("%s: %s ids must be normalised and unique." % [prefix, label])
		else:
			ids[entry_id] = true

static func _validate_available_eras(
	record: Dictionary,
	label: String,
	era_ids: Dictionary,
	errors: Array[String]
) -> void:
	var available_value: Variant = record.get("available_eras", [])
	if typeof(available_value) != TYPE_ARRAY:
		errors.append("%s: available_eras must be an array." % label)
		return
	var seen: Dictionary = {}
	for era_value in available_value:
		var era_id := String(era_value)
		if seen.has(era_id):
			errors.append("%s: available_eras contains duplicate '%s'." % [label, era_id])
		elif not era_ids.has(era_id):
			errors.append("%s: available_eras references unknown era '%s'." % [label, era_id])
		seen[era_id] = true

static func _validate_position(value: Variant, label: String, width: int, height: int, errors: Array[String]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be a position object." % label)
		return
	var position: Dictionary = value
	var x := float(position.get("x", -1.0))
	var y := float(position.get("y", -1.0))
	if x < 0.0 or y < 0.0 or x > width or y > height:
		errors.append("%s lies outside the canvas." % label)

static func _collect_ids(value: Variant) -> Dictionary:
	var ids: Dictionary = {}
	if typeof(value) == TYPE_ARRAY:
		for entry_value in value:
			if typeof(entry_value) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_value
			var entry_id := String(entry.get("id", ""))
			if not entry_id.is_empty():
				ids[entry_id] = true
	return ids

static func _scope_signature(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return ""
	var identifiers := PackedStringArray()
	for entry in value:
		identifiers.append(String(entry))
	identifiers.sort()
	return "|".join(identifiers)

static func _append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(String(message))

static func _is_safe_relative_path(path: String) -> bool:
	return (
		not path.is_empty()
		and not path.begins_with("/")
		and not path.begins_with("\\")
		and not path.contains("..")
		and not path.contains("://")
		and path.get_extension().to_lower() == "json"
	)
