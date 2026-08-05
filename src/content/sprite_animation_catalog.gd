@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")

const SUPPORTED_SCHEMA := 1
const DEFAULT_PROFILE_ID := "eli_procedural"
const TARGET_FALLBACK := "*"
const DIRECTIONS := ["down", "left", "right", "up"]
const STATES := ["idle", "walk", "attack", "hurt"]
const FALLBACK_STYLES := ["hero", "dog", "humanoid", "beast", "orb", "prop"]


static func default_catalog() -> Dictionary:
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"profiles": [
			default_profile(),
			profile_template("morrow_procedural", "Morrow", "dog", Vector2i(40, 28), Vector2i(20, 21), 4, 6, 4, 2),
			profile_template("humanoid_procedural", "Humanoid", "humanoid", Vector2i(28, 38), Vector2i(14, 33), 4, 6, 4, 2),
			profile_template("beast_procedural", "Beast", "beast", Vector2i(36, 28), Vector2i(18, 22), 4, 6, 4, 2),
			profile_template("orb_procedural", "Orb", "orb", Vector2i(24, 24), Vector2i(12, 18), 4, 4, 4, 2),
			profile_template("prop_procedural", "Prop", "prop", Vector2i(28, 28), Vector2i(14, 22), 1, 1, 1, 1)
		],
		"bindings": [
			{"target": "player", "profile_id": "eli_procedural"},
			{"target": "companion", "profile_id": "morrow_procedural"},
			{"target": "shape:person", "profile_id": "humanoid_procedural"},
			{"target": "shape:beast", "profile_id": "beast_procedural"},
			{"target": "shape:orb", "profile_id": "orb_procedural"},
			{"target": TARGET_FALLBACK, "profile_id": "prop_procedural"}
		]
	}


static func default_profile() -> Dictionary:
	return profile_template("eli_procedural", "Eli Vale", "hero", Vector2i(32, 40), Vector2i(16, 34), 4, 6, 5, 2)


static func profile_template(
	profile_id: String,
	display_name: String,
	fallback_style: String,
	frame_size: Vector2i,
	pivot: Vector2i,
	idle_frames: int,
	walk_frames: int,
	attack_frames: int,
	hurt_frames: int
) -> Dictionary:
	var direction_count := 1 if fallback_style in ["orb", "prop"] else 4
	var row_stride := direction_count
	return {
		"id": profile_id,
		"display_name": display_name,
		"atlas": "",
		"frame_size": {"x": frame_size.x, "y": frame_size.y},
		"render_size": {"x": frame_size.x, "y": frame_size.y},
		"pivot": {"x": pivot.x, "y": pivot.y},
		"directions": direction_count,
		"fallback_style": fallback_style,
		"animations": {
			"idle": {"row": 0, "frames": idle_frames, "fps": 3.0, "loop": true},
			"walk": {"row": row_stride, "frames": walk_frames, "fps": 12.0 if fallback_style == "dog" else 10.0, "loop": true},
			"attack": {"row": row_stride * 2, "frames": attack_frames, "fps": 15.0, "loop": false},
			"hurt": {"row": row_stride * 3, "frames": hurt_frames, "fps": 12.0, "loop": false}
		}
	}


static func safe_relative_json_path(path: String) -> bool:
	return safe_relative_path(path, PackedStringArray(["json"]))


static func safe_relative_atlas_path(path: String) -> bool:
	if path.strip_edges().is_empty():
		return true
	return safe_relative_path(path, PackedStringArray(["png"]))


static func safe_relative_path(path: String, extensions: PackedStringArray) -> bool:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.is_empty() or normalized.is_absolute_path() or normalized.contains(":"):
		return false
	var extension := normalized.get_extension().to_lower()
	if not extensions.has(extension):
		return false
	for part in normalized.split("/", false):
		if part.is_empty() or part == "." or part == "..":
			return false
	return true


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var files: Array[Dictionary] = []
	var definitions: Dictionary = {}
	var bindings: Array[Dictionary] = []
	var sources: Dictionary = {}
	var files_value: Variant = campaign.get("animation_files", [])
	if typeof(files_value) != TYPE_ARRAY:
		errors.append("%s: animation_files must be an array." % campaign.get("id", campaign_path))
		return make_result(errors, warnings, files, definitions, bindings, sources)
	var relative_files: Array = files_value as Array
	if relative_files.is_empty():
		warnings.append("%s: no animation catalogue is declared; original procedural animation profiles will be used." % campaign.get("id", campaign_path))
		return fallback_result(errors, warnings)
	for relative_value in relative_files:
		var relative_path := str(relative_value)
		if not safe_relative_json_path(relative_path):
			errors.append("%s: unsafe animation catalogue path '%s'." % [campaign.get("id", campaign_path), relative_path])
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result: Dictionary = Repository.read_json(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		var data: Dictionary = result.get("data", {})
		if int(data.get("schema_version", 0)) != SUPPORTED_SCHEMA:
			errors.append("%s: unsupported animation catalogue schema version." % path)
			continue
		files.append({"path": path, "relative_path": relative_path, "data": data})
		load_profiles(data, path, definitions, sources, errors)
		load_bindings(data, path, bindings, errors)
	if definitions.is_empty():
		warnings.append("No valid animation profiles were loaded; original procedural animation profiles will be used.")
		return fallback_result(errors, warnings)
	return make_result(errors, warnings, files, definitions, bindings, sources)


static func load_profiles(
	data: Dictionary,
	path: String,
	definitions: Dictionary,
	sources: Dictionary,
	errors: Array[String]
) -> void:
	var profiles_value: Variant = data.get("profiles", [])
	if typeof(profiles_value) != TYPE_ARRAY:
		errors.append("%s: profiles must be an array." % path)
		return
	for profile_value in profiles_value as Array:
		if typeof(profile_value) != TYPE_DICTIONARY:
			errors.append("%s: every animation profile must be an object." % path)
			continue
		merge_profile(profile_value as Dictionary, path, definitions, sources, errors)


static func load_bindings(
	data: Dictionary,
	path: String,
	bindings: Array[Dictionary],
	errors: Array[String]
) -> void:
	var bindings_value: Variant = data.get("bindings", [])
	if typeof(bindings_value) != TYPE_ARRAY:
		errors.append("%s: bindings must be an array." % path)
		return
	for binding_value in bindings_value as Array:
		if typeof(binding_value) != TYPE_DICTIONARY:
			errors.append("%s: every animation binding must be an object." % path)
			continue
		var binding: Dictionary = (binding_value as Dictionary).duplicate(true)
		binding["_source"] = path
		bindings.append(binding)


static func fallback_result(errors: Array[String], warnings: Array[String]) -> Dictionary:
	var catalog := default_catalog()
	var definitions: Dictionary = {}
	var sources: Dictionary = {}
	for value in catalog.get("profiles", []):
		if typeof(value) == TYPE_DICTIONARY:
			merge_profile(value as Dictionary, "built-in animation fallback", definitions, sources, errors)
	var bindings: Array[Dictionary] = []
	for value in catalog.get("bindings", []):
		if typeof(value) == TYPE_DICTIONARY:
			bindings.append((value as Dictionary).duplicate(true))
	return make_result(errors, warnings, [], definitions, bindings, sources)


static func merge_profile(
	profile_data: Dictionary,
	source: String,
	definitions: Dictionary,
	sources: Dictionary,
	errors: Array[String]
) -> void:
	var profile_id := str(profile_data.get("id", "")).strip_edges()
	if profile_id.is_empty():
		errors.append("%s: animation profile id is required." % source)
		return
	if definitions.has(profile_id):
		errors.append("%s: animation profile '%s' is also declared by %s." % [source, profile_id, sources.get(profile_id, "another catalogue")])
		return
	definitions[profile_id] = profile_data.duplicate(true)
	sources[profile_id] = source


static func resolved_profile(definitions: Dictionary, bindings: Array, targets: PackedStringArray) -> Dictionary:
	var best_profile_id := ""
	var best_score := -1
	for binding_value in bindings:
		if typeof(binding_value) != TYPE_DICTIONARY:
			continue
		var binding: Dictionary = binding_value as Dictionary
		var score := binding_score(str(binding.get("target", "")), targets)
		if score > best_score:
			best_score = score
			best_profile_id = str(binding.get("profile_id", ""))
	if not best_profile_id.is_empty() and definitions.has(best_profile_id):
		return (definitions[best_profile_id] as Dictionary).duplicate(true)
	if definitions.has(DEFAULT_PROFILE_ID):
		return (definitions[DEFAULT_PROFILE_ID] as Dictionary).duplicate(true)
	var ids := PackedStringArray()
	for value in definitions.keys():
		ids.append(str(value))
	ids.sort()
	return (definitions[ids[0]] as Dictionary).duplicate(true) if not ids.is_empty() else default_profile()


static func binding_score(target: String, targets: PackedStringArray) -> int:
	if target == TARGET_FALLBACK:
		return 0
	for index in range(targets.size()):
		if target == targets[index]:
			return 100 - index
	return -1


static func animation(profile_data: Dictionary, state: String) -> Dictionary:
	var animations_value: Variant = profile_data.get("animations", {})
	if typeof(animations_value) != TYPE_DICTIONARY:
		return {}
	var animations: Dictionary = animations_value as Dictionary
	var value: Variant = animations.get(state, animations.get("idle", {}))
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func vector2i_value(profile_data: Dictionary, key: String, fallback: Vector2i) -> Vector2i:
	var value: Variant = profile_data.get(key, {})
	if typeof(value) != TYPE_DICTIONARY:
		return fallback
	var data: Dictionary = value as Dictionary
	return Vector2i(int(data.get("x", fallback.x)), int(data.get("y", fallback.y)))


static func atlas_path(campaign_path: String, profile_data: Dictionary) -> String:
	var relative_path := str(profile_data.get("atlas", "")).strip_edges()
	if relative_path.is_empty() or not safe_relative_atlas_path(relative_path):
		return ""
	return campaign_path.get_base_dir().path_join(relative_path)


static func primary_catalog_path(campaign_path: String, campaign: Dictionary) -> String:
	var value: Variant = campaign.get("animation_files", [])
	if typeof(value) == TYPE_ARRAY:
		for relative_value in value as Array:
			var relative_path := str(relative_value)
			if safe_relative_json_path(relative_path):
				return campaign_path.get_base_dir().path_join(relative_path)
	return campaign_path.get_base_dir().path_join("animation").path_join("core.json")


static func make_result(
	errors: Array[String],
	warnings: Array[String],
	files: Array[Dictionary],
	definitions: Dictionary,
	bindings: Array[Dictionary],
	sources: Dictionary
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"files": files,
		"definitions": definitions,
		"bindings": bindings,
		"sources": sources
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value as Array:
		target.append(str(message))
