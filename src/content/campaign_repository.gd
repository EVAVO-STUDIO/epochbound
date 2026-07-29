@tool
extends RefCounted

const DEFAULT_ROOT := "res://campaigns"
const SCHEMA_VERSION := 1

static func normalise_id(raw_id: String) -> String:
	var source := raw_id.strip_edges().to_lower().replace(" ", "_")
	var output := ""
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789_-"
	for index in range(source.length()):
		var character := source.substr(index, 1)
		if allowed.contains(character):
			output += character
	while output.contains("__"):
		output = output.replace("__", "_")
	return output.trim_prefix("_").trim_suffix("_")

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "errors": ["File does not exist: %s" % path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}, "errors": ["Could not open file: %s" % path]}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		return {
			"ok": false,
			"data": {},
			"errors": ["%s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()]]
		}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "errors": ["Root value must be an object: %s" % path]}
	return {"ok": true, "data": parser.data, "errors": []}

static func save_json(path: String, data: Dictionary) -> Dictionary:
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "errors": ["Could not create directory for %s (error %d)" % [path, directory_error]]}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["Could not write file: %s" % path]}
	file.store_string(JSON.stringify(data, "\t", true) + "\n")
	file.flush()
	return {"ok": true, "errors": []}

static func scan_campaigns(root: String = DEFAULT_ROOT) -> Array:
	var campaigns: Array = []
	var directory := DirAccess.open(root)
	if directory == null:
		return campaigns
	var folders := PackedStringArray()
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and not entry.begins_with("."):
			folders.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	folders.sort()
	for folder in folders:
		var campaign_path := root.path_join(folder).path_join("campaign.json")
		var result := read_json(campaign_path)
		if result.get("ok", false):
			var data: Dictionary = result.get("data", {})
			campaigns.append({
				"id": String(data.get("id", folder)),
				"title": String(data.get("title", folder.capitalize())),
				"path": campaign_path,
				"data": data
			})
	return campaigns

static func create_campaign(raw_id: String, display_name: String = "") -> Dictionary:
	var campaign_id := normalise_id(raw_id)
	if campaign_id.is_empty():
		return {"ok": false, "errors": ["Campaign ID must contain a letter or number."]}
	var campaign_directory := DEFAULT_ROOT.path_join(campaign_id)
	var campaign_path := campaign_directory.path_join("campaign.json")
	if FileAccess.file_exists(campaign_path):
		return {"ok": false, "errors": ["Campaign already exists: %s" % campaign_id]}
	var title := display_name.strip_edges()
	if title.is_empty():
		title = campaign_id.replace("_", " ").capitalize()
	var map_id := "first_crossing"
	var map_path := campaign_directory.path_join("maps").path_join(map_id + ".json")
	var map_result := save_json(map_path, default_map(map_id, "First Crossing"))
	if not map_result.get("ok", false):
		return map_result
	var campaign_result := save_json(campaign_path, default_campaign(campaign_id, title))
	if not campaign_result.get("ok", false):
		return campaign_result
	return {
		"ok": true,
		"campaign_path": campaign_path,
		"map_path": map_path,
		"errors": []
	}

static func create_map(campaign_path: String, raw_id: String, display_name: String = "") -> Dictionary:
	var map_id := normalise_id(raw_id)
	if map_id.is_empty():
		return {"ok": false, "errors": ["Map ID must contain a letter or number."]}
	var campaign_result := read_json(campaign_path)
	if not campaign_result.get("ok", false):
		return campaign_result
	var campaign: Dictionary = campaign_result.get("data", {})
	var title := display_name.strip_edges()
	if title.is_empty():
		title = map_id.replace("_", " ").capitalize()
	var relative_path := "maps/%s.json" % map_id
	var map_path := campaign_path.get_base_dir().path_join(relative_path)
	if FileAccess.file_exists(map_path):
		return {"ok": false, "errors": ["Map already exists: %s" % map_id]}
	var map_result := save_json(map_path, default_map(map_id, title))
	if not map_result.get("ok", false):
		return map_result
	var map_files: Array = campaign.get("map_files", [])
	map_files.append(relative_path)
	campaign["map_files"] = map_files
	if String(campaign.get("start_map", "")).is_empty():
		campaign["start_map"] = map_id
	var save_result := save_json(campaign_path, campaign)
	if not save_result.get("ok", false):
		return save_result
	return {"ok": true, "map_path": map_path, "errors": []}

static func find_map_path(campaign_path: String, campaign: Dictionary, map_id: String) -> String:
	var first_path := ""
	for relative_path in campaign.get("map_files", []):
		var candidate := campaign_path.get_base_dir().path_join(String(relative_path))
		if first_path.is_empty():
			first_path = candidate
		var result := read_json(candidate)
		if result.get("ok", false):
			var map_data: Dictionary = result.get("data", {})
			if String(map_data.get("id", "")) == map_id:
				return candidate
	return first_path

static func vector_to_data(value: Vector2) -> Dictionary:
	return {"x": snappedf(value.x, 0.001), "y": snappedf(value.y, 0.001)}

static func data_to_vector(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if typeof(value) != TYPE_DICTIONARY:
		return fallback
	return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))

static func default_campaign(campaign_id: String, title: String) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": campaign_id,
		"title": title,
		"subtitle": "A New Journey",
		"author": "Campaign Author",
		"description": "An original Epochbound campaign.",
		"start_map": "first_crossing",
		"start_era": "verdant",
		"map_files": ["maps/first_crossing.json"],
		"intro": [
			"A forgotten road waits beyond the last familiar hour.",
			"One traveller and one loyal companion cross the threshold.",
			"What changes in one age will be remembered by the next."
		],
		"actors": {
			"player": {"name": "HERO", "max_health": 32},
			"companion": {"name": "COMPANION", "max_health": 24}
		},
		"ruleset": {
			"combat_model": "action",
			"companion_enabled": true,
			"era_shifting_enabled": true
		}
	}

static func default_map(map_id: String, display_name: String) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": map_id,
		"display_name": display_name,
		"canvas": {"width": 640, "height": 360, "grid_size": 16},
		"bounds": {"left": 32, "right": 608, "top": 96, "bottom": 328},
		"spawns": {
			"player": {"x": 320, "y": 224},
			"companion": {"x": 280, "y": 232}
		},
		"eras": [
			{
				"id": "verdant",
				"display_name": "Verdant Age",
				"palette": {
					"sky": "819a91",
					"ground": "4f6550",
					"accent": "e5d89f",
					"structure": "53625b"
				},
				"landmarks": [
					{"id": "sun", "kind": "sun", "position": {"x": 530, "y": 65}, "size": 28},
					{"id": "ruin", "kind": "ruin", "position": {"x": 500, "y": 150}, "size": 56}
				]
			},
			{
				"id": "ashen",
				"display_name": "Ashen Age",
				"palette": {
					"sky": "5e4541",
					"ground": "52443a",
					"accent": "d77850",
					"structure": "392f2d"
				},
				"landmarks": [
					{"id": "sun", "kind": "sun", "position": {"x": 530, "y": 65}, "size": 28},
					{"id": "ruin", "kind": "ruin", "position": {"x": 500, "y": 150}, "size": 56}
				]
			}
		],
		"layers": [
			{"id": "ground", "type": "terrain", "z_index": 0, "visible": true, "locked": false},
			{"id": "objects", "type": "objects", "z_index": 10, "visible": true, "locked": false},
			{"id": "collision", "type": "collision", "z_index": 20, "visible": true, "locked": false}
		],
		"interactions": [],
		"connections": []
	}
