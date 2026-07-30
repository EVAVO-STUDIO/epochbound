@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/boss_validator.gd")
const CinematicCatalog = preload("res://src/content/cinematic_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")

const MAX_STATE_KEY_LENGTH := 160
const MAX_STEPS := 256
const MAX_DURATION := 30.0
const ALLOWED_EFFECT_TYPES := [
	"set_state",
	"message",
	"grant_clock_shards",
	"grant_item",
	"remove_item",
	"unlock_recipe",
	"start_quest",
	"advance_quest",
	"complete_quest",
	"grant_currency",
	"remove_currency"
]


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var cinematic_count := 0
	var step_count := 0
	var trigger_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var report := validate_cinematics_only(str((value as Dictionary).get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		cinematic_count += int(report.get("cinematic_count", 0))
		step_count += int(report.get("cinematic_step_count", 0))
		trigger_count += int(report.get("cinematic_trigger_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["cinematic_count"] = cinematic_count
	output["cinematic_step_count"] = step_count
	output["cinematic_trigger_count"] = trigger_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_campaign_path(campaign_path)
	var cinematic_report := validate_cinematics_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, cinematic_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, cinematic_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	for field in ["cinematic_count", "cinematic_step_count", "cinematic_trigger_count"]:
		output[field] = cinematic_report.get(field, 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	return BaseValidator.validate_profile(profile, campaign_path)


static func validate_cinematics_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return make_report(errors, warnings, 0, 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id := str(campaign.get("id", campaign_path))
	validate_file_list(campaign, campaign_id, errors, warnings)
	var catalog_result := CinematicCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, catalog_result.get("errors", []))
	var definitions: Dictionary = catalog_result.get("definitions", {})
	var maps := load_maps(campaign_path, campaign, errors)
	var maps_by_id: Dictionary = {}
	var eras_by_map: Dictionary = {}
	var placements_by_map: Dictionary = {}
	for map_value in maps:
		if typeof(map_value) != TYPE_DICTIONARY:
			continue
		var map_data: Dictionary = map_value
		var map_id := str(map_data.get("id", ""))
		maps_by_id[map_id] = map_data
		var eras: Dictionary = {}
		for era_value in map_data.get("eras", []):
			if typeof(era_value) == TYPE_DICTIONARY:
				eras[str((era_value as Dictionary).get("id", ""))] = true
		eras_by_map[map_id] = eras
		var placements: Dictionary = {}
		for placement_value in map_data.get("object_placements", []):
			if typeof(placement_value) == TYPE_DICTIONARY:
				placements[str((placement_value as Dictionary).get("id", ""))] = true
		placements_by_map[map_id] = placements

	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	var items: Dictionary = item_result.get("definitions", {})
	var recipe_result := ItemCatalog.load_recipe_catalogs(campaign_path, campaign)
	append_messages(errors, recipe_result.get("errors", []))
	var recipes: Dictionary = recipe_result.get("definitions", {})
	var story_result := StoryCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, story_result.get("errors", []))
	var quests: Dictionary = story_result.get("quests", {})
	var economy_result := EconomyCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, economy_result.get("errors", []))
	var currencies: Dictionary = economy_result.get("currencies", {})

	var cinematic_count := 0
	var step_count := 0
	var state_keys: Dictionary = {}
	for file_value in catalog_result.get("files", []):
		if typeof(file_value) != TYPE_DICTIONARY:
			continue
		var file_record: Dictionary = file_value
		var report := validate_catalog_file(
			file_record.get("data", {}),
			str(file_record.get("path", "cinematic catalog")),
			maps_by_id,
			eras_by_map,
			placements_by_map,
			items,
			recipes,
			quests,
			currencies,
			state_keys,
			errors,
			warnings
		)
		cinematic_count += int(report.get("cinematic_count", 0))
		step_count += int(report.get("step_count", 0))

	var trigger_count := validate_triggers(campaign, maps, definitions, catalog_result, errors, warnings)
	return make_report(errors, warnings, cinematic_count, step_count, trigger_count)


static func validate_file_list(campaign: Dictionary, campaign_id: String, errors: Array[String], warnings: Array[String]) -> void:
	var value: Variant = campaign.get("cinematic_files", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: cinematic_files must be an array." % campaign_id)
		return
	if (value as Array).is_empty():
		warnings.append("%s: no cinematic catalogs are declared." % campaign_id)
	var seen: Dictionary = {}
	for path_value in value:
		var relative_path := str(path_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe cinematic catalog path '%s'." % [campaign_id, relative_path])
		elif seen.has(relative_path):
			errors.append("%s: cinematic_files repeats '%s'." % [campaign_id, relative_path])
		seen[relative_path] = true


static func validate_catalog_file(
	catalog: Dictionary,
	path: String,
	maps_by_id: Dictionary,
	eras_by_map: Dictionary,
	placements_by_map: Dictionary,
	items: Dictionary,
	recipes: Dictionary,
	quests: Dictionary,
	currencies: Dictionary,
	state_keys: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> Dictionary:
	if int(catalog.get("schema_version", 0)) != CinematicCatalog.SUPPORTED_SCHEMA:
		errors.append("%s: unsupported cinematic schema_version." % path)
	var value: Variant = catalog.get("cinematics", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: cinematics must be an array." % path)
		return {"cinematic_count": 0, "step_count": 0}
	var ids: Dictionary = {}
	var step_count := 0
	for sequence_value in value:
		if typeof(sequence_value) != TYPE_DICTIONARY:
			errors.append("%s: every cinematic must be an object." % path)
			continue
		var sequence: Dictionary = sequence_value
		var cinematic_id := str(sequence.get("id", ""))
		var prefix := "%s/%s" % [path, cinematic_id if not cinematic_id.is_empty() else "cinematic"]
		if cinematic_id.is_empty() or Repository.normalise_id(cinematic_id) != cinematic_id:
			errors.append("%s: id must be a normalised lowercase identifier." % prefix)
		elif ids.has(cinematic_id):
			errors.append("%s: duplicate cinematic id '%s'." % [path, cinematic_id])
		else:
			ids[cinematic_id] = true
		if CinematicCatalog.display_name(sequence).is_empty():
			errors.append("%s: display_name is required." % prefix)
		var map_id := CinematicCatalog.map_id(sequence)
		if map_id.is_empty() or not maps_by_id.has(map_id):
			errors.append("%s: map_id '%s' is not a declared map." % [prefix, map_id])
		var eras: Dictionary = eras_by_map.get(map_id, {})
		validate_era_list(sequence.get("available_eras", []), prefix, eras, errors)
		if typeof(sequence.get("skippable", true)) != TYPE_BOOL:
			errors.append("%s: skippable must be boolean." % prefix)
		if typeof(sequence.get("letterbox", true)) != TYPE_BOOL:
			errors.append("%s: letterbox must be boolean." % prefix)
		if typeof(sequence.get("trigger_once", true)) != TYPE_BOOL:
			errors.append("%s: trigger_once must be boolean." % prefix)
		var completion_key := CinematicCatalog.completion_state_key(sequence)
		if CinematicCatalog.trigger_once(sequence) and completion_key.is_empty():
			errors.append("%s: trigger_once cinematics require completion_state_key." % prefix)
		elif completion_key.length() > MAX_STATE_KEY_LENGTH:
			errors.append("%s: completion_state_key exceeds %d characters." % [prefix, MAX_STATE_KEY_LENGTH])
		elif not completion_key.is_empty() and state_keys.has(completion_key):
			errors.append("%s: completion_state_key '%s' is also used by '%s'." % [prefix, completion_key, state_keys[completion_key]])
		elif not completion_key.is_empty():
			state_keys[completion_key] = cinematic_id
		var steps := CinematicCatalog.steps(sequence)
		if steps.is_empty():
			errors.append("%s: steps cannot be empty." % prefix)
		if steps.size() > MAX_STEPS:
			errors.append("%s: steps exceeds the %d-step safety limit." % [prefix, MAX_STEPS])
		var step_ids: Dictionary = {}
		for step_index in range(steps.size()):
			var step_value: Variant = steps[step_index]
			if typeof(step_value) != TYPE_DICTIONARY:
				errors.append("%s/steps/%d: step must be an object." % [prefix, step_index])
				continue
			var step: Dictionary = step_value
			validate_step(step, step_index, prefix, map_id, eras, placements_by_map.get(map_id, {}), items, recipes, quests, currencies, step_ids, errors, warnings)
		step_count += steps.size()
		validate_effects(sequence.get("completion_effects", []), prefix + "/completion_effects", items, recipes, quests, currencies, errors)
		validate_effects(sequence.get("skip_effects", []), prefix + "/skip_effects", items, recipes, quests, currencies, errors)
	return {"cinematic_count": (value as Array).size(), "step_count": step_count}


static func validate_step(
	step: Dictionary,
	step_index: int,
	prefix: String,
	map_id: String,
	eras: Dictionary,
	placements: Dictionary,
	items: Dictionary,
	recipes: Dictionary,
	quests: Dictionary,
	currencies: Dictionary,
	step_ids: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var step_id := str(step.get("id", ""))
	var step_prefix := "%s/step/%s" % [prefix, step_id if not step_id.is_empty() else step_index]
	if step_id.is_empty() or Repository.normalise_id(step_id) != step_id:
		errors.append("%s: id must be a normalised lowercase identifier." % step_prefix)
	elif step_ids.has(step_id):
		errors.append("%s: duplicate step id '%s'." % [prefix, step_id])
	else:
		step_ids[step_id] = true
	var step_type := CinematicCatalog.step_type(step)
	if not CinematicCatalog.ALLOWED_STEP_TYPES.has(step_type):
		errors.append("%s: unsupported step type '%s'." % [step_prefix, step_type])
		return
	var duration := CinematicCatalog.step_duration(step)
	if duration > MAX_DURATION:
		errors.append("%s: duration cannot exceed %.0f seconds." % [step_prefix, MAX_DURATION])
	match step_type:
		"wait":
			if duration <= 0.0:
				errors.append("%s: wait duration must be positive." % step_prefix)
		"dialogue":
			validate_text(step.get("text", ""), step_prefix, errors)
			if typeof(step.get("advance_on_confirm", true)) != TYPE_BOOL:
				errors.append("%s: advance_on_confirm must be boolean." % step_prefix)
			if duration <= 0.0 and not bool(step.get("advance_on_confirm", true)):
				errors.append("%s: dialogue requires duration or advance_on_confirm." % step_prefix)
		"camera":
			var target := str(step.get("target", "world"))
			if not CinematicCatalog.ALLOWED_CAMERA_TARGETS.has(target) and not target.begins_with("placement:"):
				errors.append("%s: unsupported camera target '%s'." % [step_prefix, target])
			validate_target_reference(target, placements, step_prefix, errors)
			if target == "world":
				validate_position(step.get("position"), step_prefix, map_id, errors)
			var zoom := float(step.get("zoom", 1.0))
			if zoom < 0.5 or zoom > 2.0:
				errors.append("%s: zoom must be between 0.5 and 2.0." % step_prefix)
		"move_actor":
			var actor := str(step.get("actor", ""))
			if actor not in ["player", "companion"] and not actor.begins_with("placement:"):
				errors.append("%s: actor must be player, companion or placement:<id>." % step_prefix)
			validate_target_reference(actor, placements, step_prefix, errors)
			validate_position(step.get("position"), step_prefix, map_id, errors)
			if duration <= 0.0:
				errors.append("%s: move_actor duration must be positive." % step_prefix)
		"set_era":
			var era_id := str(step.get("era_id", ""))
			if not eras.has(era_id):
				errors.append("%s: era_id '%s' is not available on the cinematic map." % [step_prefix, era_id])
		"fade":
			if str(step.get("direction", "")) not in CinematicCatalog.ALLOWED_FADE_DIRECTIONS:
				errors.append("%s: fade direction must be 'in' or 'out'." % step_prefix)
			if duration <= 0.0:
				errors.append("%s: fade duration must be positive." % step_prefix)
		"effects":
			validate_effects(step.get("effects", []), step_prefix + "/effects", items, recipes, quests, currencies, errors)
		"checkpoint":
			var key := str(step.get("key", "")).strip_edges()
			if key.is_empty() or key.length() > MAX_STATE_KEY_LENGTH:
				errors.append("%s: checkpoint key is required and must not exceed %d characters." % [step_prefix, MAX_STATE_KEY_LENGTH])
		_:
			pass


static func validate_target_reference(target: String, placements: Dictionary, prefix: String, errors: Array[String]) -> void:
	if target.begins_with("placement:"):
		var placement_id := target.trim_prefix("placement:")
		if placement_id.is_empty() or not placements.has(placement_id):
			errors.append("%s: unknown placement target '%s'." % [prefix, placement_id])


static func validate_position(value: Variant, prefix: String, _map_id: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: position must be an object with x and y." % prefix)
		return
	var data: Dictionary = value
	if not data.has("x") or not data.has("y"):
		errors.append("%s: position requires x and y." % prefix)


static func validate_text(value: Variant, prefix: String, errors: Array[String]) -> void:
	if typeof(value) == TYPE_STRING:
		if str(value).strip_edges().is_empty():
			errors.append("%s: text cannot be empty." % prefix)
		return
	if typeof(value) != TYPE_DICTIONARY or (value as Dictionary).is_empty():
		errors.append("%s: text must be a string or non-empty era-keyed object." % prefix)
		return
	for text_value in (value as Dictionary).values():
		if str(text_value).strip_edges().is_empty():
			errors.append("%s: era-keyed text values cannot be empty." % prefix)


static func validate_era_list(value: Variant, prefix: String, eras: Dictionary, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: available_eras must be an array." % prefix)
		return
	var seen: Dictionary = {}
	for era_value in value:
		var era_id := str(era_value)
		if seen.has(era_id):
			errors.append("%s: available_eras repeats '%s'." % [prefix, era_id])
		elif not eras.has(era_id):
			errors.append("%s: available_eras references unknown era '%s'." % [prefix, era_id])
		seen[era_id] = true


static func validate_effects(value: Variant, prefix: String, items: Dictionary, recipes: Dictionary, quests: Dictionary, currencies: Dictionary, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an array." % prefix)
		return
	for index in range((value as Array).size()):
		var effect_value: Variant = (value as Array)[index]
		var effect_prefix := "%s/%d" % [prefix, index]
		if typeof(effect_value) != TYPE_DICTIONARY:
			errors.append("%s: effect must be an object." % effect_prefix)
			continue
		var effect: Dictionary = effect_value
		var effect_type := str(effect.get("type", ""))
		if effect_type not in ALLOWED_EFFECT_TYPES:
			errors.append("%s: unsupported effect type '%s'." % [effect_prefix, effect_type])
			continue
		match effect_type:
			"set_state":
				if str(effect.get("key", "")).strip_edges().is_empty():
					errors.append("%s: set_state requires key." % effect_prefix)
			"message":
				if str(effect.get("text", "")).strip_edges().is_empty():
					errors.append("%s: message requires text." % effect_prefix)
			"grant_clock_shards":
				if int(effect.get("amount", 0)) <= 0:
					errors.append("%s: amount must be positive." % effect_prefix)
			"grant_item", "remove_item":
				var item_id := str(effect.get("item_id", ""))
				if not items.has(item_id):
					errors.append("%s: unknown item '%s'." % [effect_prefix, item_id])
				if int(effect.get("quantity", 0)) <= 0:
					errors.append("%s: quantity must be positive." % effect_prefix)
			"unlock_recipe":
				var recipe_id := str(effect.get("recipe_id", ""))
				if not recipes.has(recipe_id):
					errors.append("%s: unknown recipe '%s'." % [effect_prefix, recipe_id])
			"start_quest", "advance_quest", "complete_quest":
				var quest_id := str(effect.get("quest_id", ""))
				if not quests.has(quest_id):
					errors.append("%s: unknown quest '%s'." % [effect_prefix, quest_id])
			"grant_currency", "remove_currency":
				var currency_id := str(effect.get("currency_id", ""))
				if not currencies.has(currency_id):
					errors.append("%s: unknown currency '%s'." % [effect_prefix, currency_id])
				if int(effect.get("amount", 0)) <= 0:
					errors.append("%s: amount must be positive." % effect_prefix)
			_:
				pass


static func validate_triggers(campaign: Dictionary, maps: Array, definitions: Dictionary, catalog_result: Dictionary, errors: Array[String], warnings: Array[String]) -> int:
	var trigger_count := 0
	var referenced: Dictionary = {}
	var intro_id := str(campaign.get("intro_cinematic_id", "")).strip_edges()
	if not intro_id.is_empty():
		trigger_count += 1
		referenced[intro_id] = true
		if not definitions.has(intro_id):
			errors.append("%s: intro_cinematic_id references unknown cinematic '%s'." % [campaign.get("id", "campaign"), intro_id])
	for map_value in maps:
		if typeof(map_value) != TYPE_DICTIONARY:
			continue
		var map_data: Dictionary = map_value
		for interaction_value in map_data.get("interactions", []):
			if typeof(interaction_value) != TYPE_DICTIONARY:
				continue
			var cinematic_id := str((interaction_value as Dictionary).get("cinematic_id", "")).strip_edges()
			if cinematic_id.is_empty():
				continue
			trigger_count += 1
			referenced[cinematic_id] = true
			if not definitions.has(cinematic_id):
				errors.append("%s/%s: cinematic_id references unknown cinematic '%s'." % [map_data.get("id", "map"), (interaction_value as Dictionary).get("id", "interaction"), cinematic_id])
	var object_result := ObjectCatalog.load_catalogs(str(catalog_result.get("campaign_path", "")), campaign) if false else {}
	# Boss cinematic references live in the already loaded reusable definitions from campaign object catalogs.
	var campaign_path := str(catalog_result.get("campaign_path", ""))
	if campaign_path.is_empty():
		campaign_path = ""
	# Load directly because load_catalogs intentionally returns only cinematic records.
	var object_files_value: Variant = campaign.get("object_files", [])
	if typeof(object_files_value) == TYPE_ARRAY:
		for relative_value in object_files_value:
			var relative_path := str(relative_value)
			if not ObjectCatalog.safe_relative_json_path(relative_path):
				continue
			var path := str(campaign.get("_campaign_path", ""))
			if path.is_empty():
				continue
	for cinematic_id in definitions.keys():
		if not referenced.has(cinematic_id):
			warnings.append("Cinematic '%s' has no campaign or map trigger." % cinematic_id)
	return trigger_count


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


static func make_report(errors: Array[String], warnings: Array[String], cinematic_count: int, step_count: int, trigger_count: int) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"cinematic_count": cinematic_count,
		"cinematic_step_count": step_count,
		"cinematic_trigger_count": trigger_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
