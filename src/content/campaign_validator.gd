@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const SUPPORTED_SCHEMA := 1
const ALLOWED_LAYER_TYPES := ["terrain", "objects", "collision", "navigation", "effects"]

static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_count := 0
	var map_count := 0
	for entry in Repository.scan_campaigns(root):
		campaign_count += 1
		var report := validate_campaign_path(String(entry.get("path", "")))
		errors.append_array(report.get("errors", []))
		warnings.append_array(report.get("warnings", []))
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
		errors.append_array(campaign_result.get("errors", []))
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
	var map_files_value: Variant = campaign.get("map_files", [])
	if typeof(map_files_value) != TYPE_ARRAY or map_files_value.is_empty():
		errors.append("%s: map_files must contain at least one relative JSON path." % prefix)
		return {"ok": false, "errors": errors, "warnings": warnings, "map_count": 0}
	var map_ids: Dictionary = {}
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
			errors.append_array(map_result.get("errors", []))
			continue
		map_count += 1
		var map_data: Dictionary = map_result.get("data", {})
		var report := validate_map(map_data, map_path)
		errors.append_array(report.get("errors", []))
		warnings.append_array(report.get("warnings", []))
		var map_id := String(map_data.get("id", ""))
		if map_ids.has(map_id):
			errors.append("%s: duplicate map id '%s'." % [prefix, map_id])
		else:
			map_ids[map_id] = true
		map_reports.append({"path": map_path, "data": map_data})
	var start_map := String(campaign.get("start_map", ""))
	if not map_ids.has(start_map):
		errors.append("%s: start_map '%s' does not resolve to a declared map." % [prefix, start_map])
	else:
		for record in map_reports:
			var data: Dictionary = record.get("data", {})
			if String(data.get("id", "")) == start_map:
				var era_ids := _collect_ids(data.get("eras", []))
				var start_era := String(campaign.get("start_era", ""))
				if not era_ids.has(start_era):
					errors.append("%s: start_era '%s' does not exist in start_map." % [prefix, start_era])
				break
	for record in map_reports:
		var data: Dictionary = record.get("data", {})
		for connection in data.get("connections", []):
			var target := String(connection.get("target_map", ""))
			if target.is_empty() or not map_ids.has(target):
				errors.append("%s/%s: connection target '%s' is missing." % [prefix, data.get("id", "map"), target])
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
	var canvas: Dictionary = map_data.get("canvas", {})
	var width := int(canvas.get("width", 0))
	var height := int(canvas.get("height", 0))
	var grid_size := int(canvas.get("grid_size", 0))
	if width < 160 or height < 90:
		errors.append("%s: canvas must be at least 160 by 90 pixels." % prefix)
	if grid_size < 1 or grid_size > 128:
		errors.append("%s: grid_size must be between 1 and 128." % prefix)
	var bounds: Dictionary = map_data.get("bounds", {})
	if float(bounds.get("left", 0)) >= float(bounds.get("right", width)):
		errors.append("%s: bounds left must be less than right." % prefix)
	if float(bounds.get("top", 0)) >= float(bounds.get("bottom", height)):
		errors.append("%s: bounds top must be less than bottom." % prefix)
	var era_ids := _collect_ids(map_data.get("eras", []))
	if era_ids.is_empty():
		errors.append("%s: at least one era is required." % prefix)
	elif era_ids.size() == 1:
		warnings.append("%s: only one era is defined; era shifting will have no effect." % prefix)
	_validate_unique_entries(map_data.get("eras", []), "era", prefix, errors)
	_validate_layers(map_data.get("layers", []), prefix, errors)
	var spawns: Dictionary = map_data.get("spawns", {})
	for spawn_name in ["player", "companion"]:
		if not spawns.has(spawn_name):
			errors.append("%s: missing %s spawn." % [prefix, spawn_name])
		else:
			_validate_position(spawns.get(spawn_name), "%s %s spawn" % [prefix, spawn_name], width, height, errors)
	var interaction_ids: Dictionary = {}
	for interaction in map_data.get("interactions", []):
		var interaction_id := String(interaction.get("id", ""))
		if interaction_id.is_empty():
			errors.append("%s: interaction id is required." % prefix)
		elif interaction_ids.has(interaction_id):
			errors.append("%s: duplicate interaction id '%s'." % [prefix, interaction_id])
		else:
			interaction_ids[interaction_id] = true
		_validate_position(interaction.get("position"), "%s interaction %s" % [prefix, interaction_id], width, height, errors)
		if float(interaction.get("radius", 0.0)) <= 0.0:
			errors.append("%s/%s: radius must be positive." % [prefix, interaction_id])
		for era_id in interaction.get("available_eras", []):
			if not era_ids.has(String(era_id)):
				errors.append("%s/%s: unknown available era '%s'." % [prefix, interaction_id, era_id])
		var dialogue: Variant = interaction.get("dialogue", "")
		if typeof(dialogue) == TYPE_STRING and String(dialogue).strip_edges().is_empty():
			warnings.append("%s/%s: interaction has no dialogue." % [prefix, interaction_id])
		elif typeof(dialogue) != TYPE_STRING and typeof(dialogue) != TYPE_DICTIONARY:
			errors.append("%s/%s: dialogue must be text or an era-keyed object." % [prefix, interaction_id])
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}

static func _validate_layers(value: Variant, prefix: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		errors.append("%s: layers must contain at least one layer." % prefix)
		return
	var ids: Dictionary = {}
	for layer in value:
		var layer_id := String(layer.get("id", ""))
		if layer_id.is_empty() or ids.has(layer_id):
			errors.append("%s: layer ids must be present and unique." % prefix)
		else:
			ids[layer_id] = true
		if not ALLOWED_LAYER_TYPES.has(String(layer.get("type", ""))):
			errors.append("%s/%s: unsupported layer type '%s'." % [prefix, layer_id, layer.get("type", "")])

static func _validate_unique_entries(value: Variant, label: String, prefix: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: %ss must be an array." % [prefix, label])
		return
	var ids: Dictionary = {}
	for entry in value:
		var entry_id := String(entry.get("id", ""))
		if entry_id.is_empty() or ids.has(entry_id):
			errors.append("%s: %s ids must be present and unique." % [prefix, label])
		else:
			ids[entry_id] = true

static func _validate_position(value: Variant, label: String, width: int, height: int, errors: Array[String]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s must be a position object." % label)
		return
	var x := float(value.get("x", -1.0))
	var y := float(value.get("y", -1.0))
	if x < 0.0 or y < 0.0 or x > width or y > height:
		errors.append("%s lies outside the canvas." % label)

static func _collect_ids(value: Variant) -> Dictionary:
	var ids: Dictionary = {}
	if typeof(value) == TYPE_ARRAY:
		for entry in value:
			var entry_id := String(entry.get("id", ""))
			if not entry_id.is_empty():
				ids[entry_id] = true
	return ids

static func _is_safe_relative_path(path: String) -> bool:
	return (
		not path.is_empty()
		and not path.begins_with("/")
		and not path.begins_with("\\")
		and not path.contains("..")
		and not path.contains("://")
		and path.get_extension().to_lower() == "json"
	)
