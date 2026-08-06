@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/companion_validator.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

const MAX_DESCRIPTION_LENGTH := 1200
const MAX_STACK_LIMIT := 999


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_count := 0
	var map_count := 0
	var definition_count := 0
	var placement_count := 0
	var zone_count := 0
	var cue_count := 0
	var item_count := 0
	var recipe_count := 0
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
		cue_count += int(report.get("cue_count", 0))
		item_count += int(report.get("item_count", 0))
		recipe_count += int(report.get("recipe_count", 0))
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
		"zone_count": zone_count,
		"cue_count": cue_count,
		"item_count": item_count,
		"recipe_count": recipe_count
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
		return make_report(errors, warnings, base_report, 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id := str(campaign.get("id", campaign_path))
	validate_file_list(campaign, "item_files", campaign_id, errors, warnings)
	validate_file_list(campaign, "recipe_files", campaign_id, errors, warnings)

	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	var recipe_result := ItemCatalog.load_recipe_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	append_messages(errors, recipe_result.get("errors", []))
	var items: Dictionary = item_result.get("definitions", {})
	var recipes: Dictionary = recipe_result.get("definitions", {})
	var item_sources: Dictionary = {}
	var recipe_sources: Dictionary = {}
	var used_items: Dictionary = {}
	var used_recipes: Dictionary = {}

	for file_value in item_result.get("files", []):
		if typeof(file_value) != TYPE_DICTIONARY:
			continue
		var file_record: Dictionary = file_value
		validate_item_catalog_file(
			file_record.get("data", {}),
			str(file_record.get("path", "item catalog")),
			item_sources,
			errors,
			warnings
		)
	for file_value in recipe_result.get("files", []):
		if typeof(file_value) != TYPE_DICTIONARY:
			continue
		var file_record: Dictionary = file_value
		validate_recipe_catalog_file(
			file_record.get("data", {}),
			str(file_record.get("path", "recipe catalog")),
			items,
			recipe_sources,
			used_items,
			errors,
			warnings
		)

	validate_starting_inventory(campaign, campaign_id, items, used_items, errors, warnings)
	validate_starting_recipes(campaign, campaign_id, recipes, used_recipes, errors)
	collect_authored_item_and_recipe_uses(
		campaign,
		items,
		recipes,
		used_items,
		used_recipes
	)

	var object_result := ObjectCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, object_result.get("errors", []))
	var object_definitions: Dictionary = object_result.get("definitions", {})
	for object_id in object_definitions.keys():
		var object_data: Dictionary = object_definitions.get(object_id, {})
		var grants_value: Variant = object_data.get("item_grants", [])
		var has_grants := typeof(grants_value) == TYPE_ARRAY and not Array(grants_value).is_empty()
		if has_grants and str(object_data.get("kind", "")) != "pickup":
			warnings.append("%s/object/%s: item_grants are normally expected on pickup definitions." % [campaign_id, object_id])
		validate_grants(
			grants_value,
			"%s/object/%s/item_grants" % [campaign_id, object_id],
			items,
			used_items,
			errors
		)
		collect_authored_item_and_recipe_uses(
			object_data,
			items,
			recipes,
			used_items,
			used_recipes
		)

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
			validate_map_item_rewards(map_data, items, recipes, used_items, used_recipes, errors)
			collect_authored_item_and_recipe_uses(
				map_data,
				items,
				recipes,
				used_items,
				used_recipes
			)

	for field in ["story_files", "economy_files", "cinematic_files"]:
		collect_declared_file_uses(
			campaign_path,
			campaign,
			field,
			items,
			recipes,
			used_items,
			used_recipes
		)

	for item_id in items.keys():
		if not used_items.has(item_id):
			warnings.append("%s: item '%s' is not used by starting inventory, recipes or authored rewards." % [campaign_id, item_id])
	for recipe_id in recipes.keys():
		if not used_recipes.has(recipe_id) and not bool(ItemCatalog.recipe(recipes, str(recipe_id)).get("unlocked_by_default", false)):
			warnings.append("%s: recipe '%s' is never unlocked." % [campaign_id, recipe_id])

	return make_report(errors, warnings, base_report, items.size(), recipes.size())


static func validate_file_list(
	campaign: Dictionary,
	field: String,
	campaign_id: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var value: Variant = campaign.get(field, [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: %s must be an array of safe relative JSON paths." % [campaign_id, field])
		return
	var files: Array = value
	if files.is_empty():
		warnings.append("%s: %s is empty." % [campaign_id, field])
	var seen: Dictionary = {}
	for relative_value in files:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe %s path '%s'." % [campaign_id, field, relative_path])
		elif seen.has(relative_path):
			errors.append("%s: %s repeats '%s'." % [campaign_id, field, relative_path])
		else:
			seen[relative_path] = true


static func validate_item_catalog_file(
	catalog: Dictionary,
	path: String,
	sources: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if int(catalog.get("schema_version", 0)) != ItemCatalog.SUPPORTED_SCHEMA:
		errors.append("%s: unsupported item catalog schema_version." % path)
	var value: Variant = catalog.get("items", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: items must be an array." % path)
		return
	var items: Array = value
	if items.is_empty():
		warnings.append("%s: item catalog is empty." % path)
	var local_ids: Dictionary = {}
	for item_value in items:
		if typeof(item_value) != TYPE_DICTIONARY:
			errors.append("%s: every item must be an object." % path)
			continue
		var item_data: Dictionary = item_value
		var item_id := str(item_data.get("id", ""))
		var prefix := "%s/%s" % [path, item_id if not item_id.is_empty() else "item"]
		if item_id.is_empty() or Repository.normalise_id(item_id) != item_id:
			errors.append("%s: id must be a normalised lowercase identifier." % prefix)
		elif local_ids.has(item_id):
			errors.append("%s: duplicate item id '%s'." % [path, item_id])
		else:
			local_ids[item_id] = true
			if sources.has(item_id) and sources[item_id] != path:
				errors.append("%s: item '%s' is also declared by %s." % [path, item_id, sources[item_id]])
			sources[item_id] = path
		if str(item_data.get("display_name", "")).strip_edges().is_empty():
			errors.append("%s: display_name is required." % prefix)
		var kind := str(item_data.get("kind", ""))
		if not ItemCatalog.ALLOWED_ITEM_KINDS.has(kind):
			errors.append("%s: unsupported item kind '%s'." % [prefix, kind])
		var description := str(item_data.get("description", "")).strip_edges()
		if description.is_empty():
			warnings.append("%s: description is empty." % prefix)
		elif description.length() > MAX_DESCRIPTION_LENGTH:
			errors.append("%s: description exceeds %d characters." % [prefix, MAX_DESCRIPTION_LENGTH])
		var stack_limit := int(item_data.get("stack_limit", 0))
		if stack_limit < 1 or stack_limit > MAX_STACK_LIMIT:
			errors.append("%s: stack_limit must be between 1 and %d." % [prefix, MAX_STACK_LIMIT])
		if int(item_data.get("value", 0)) < 0:
			errors.append("%s: value cannot be negative." % prefix)
		validate_use_effect(item_data, prefix, kind, errors, warnings)


static func validate_use_effect(
	item_data: Dictionary,
	prefix: String,
	kind: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var value: Variant = item_data.get("use_effect", {})
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: use_effect must be an object." % prefix)
		return
	var effect: Dictionary = value
	var effect_type := str(effect.get("type", "none"))
	if not ItemCatalog.ALLOWED_EFFECT_TYPES.has(effect_type):
		errors.append("%s: unsupported use effect '%s'." % [prefix, effect_type])
		return
	if effect_type == "heal" and int(effect.get("amount", 0)) <= 0:
		errors.append("%s: heal effect amount must be positive." % prefix)
	if kind != "consumable" and effect_type != "none":
		warnings.append("%s: non-consumable item defines an active use effect." % prefix)
	if kind == "consumable" and effect_type == "none":
		warnings.append("%s: consumable item has no active use effect." % prefix)


static func validate_recipe_catalog_file(
	catalog: Dictionary,
	path: String,
	items: Dictionary,
	sources: Dictionary,
	used_items: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if int(catalog.get("schema_version", 0)) != ItemCatalog.SUPPORTED_SCHEMA:
		errors.append("%s: unsupported recipe catalog schema_version." % path)
	var value: Variant = catalog.get("recipes", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: recipes must be an array." % path)
		return
	var recipes: Array = value
	if recipes.is_empty():
		warnings.append("%s: recipe catalog is empty." % path)
	var local_ids: Dictionary = {}
	for recipe_value in recipes:
		if typeof(recipe_value) != TYPE_DICTIONARY:
			errors.append("%s: every recipe must be an object." % path)
			continue
		var recipe_data: Dictionary = recipe_value
		var recipe_id := str(recipe_data.get("id", ""))
		var prefix := "%s/%s" % [path, recipe_id if not recipe_id.is_empty() else "recipe"]
		if recipe_id.is_empty() or Repository.normalise_id(recipe_id) != recipe_id:
			errors.append("%s: id must be a normalised lowercase identifier." % prefix)
		elif local_ids.has(recipe_id):
			errors.append("%s: duplicate recipe id '%s'." % [path, recipe_id])
		else:
			local_ids[recipe_id] = true
			if sources.has(recipe_id) and sources[recipe_id] != path:
				errors.append("%s: recipe '%s' is also declared by %s." % [path, recipe_id, sources[recipe_id]])
			sources[recipe_id] = path
		if str(recipe_data.get("display_name", "")).strip_edges().is_empty():
			errors.append("%s: display_name is required." % prefix)
		if str(recipe_data.get("description", "")).strip_edges().is_empty():
			warnings.append("%s: description is empty." % prefix)
		if typeof(recipe_data.get("unlocked_by_default", false)) != TYPE_BOOL:
			errors.append("%s: unlocked_by_default must be boolean." % prefix)
		var ingredient_ids: Dictionary = {}
		var ingredient_values := InventoryModel.ingredients(recipe_data)
		if ingredient_values.is_empty():
			errors.append("%s: recipe must have at least one ingredient." % prefix)
		for ingredient_value in ingredient_values:
			var ingredient: Dictionary = ingredient_value
			var item_id := str(ingredient.get("item_id", ""))
			if not items.has(item_id):
				errors.append("%s: unknown ingredient item '%s'." % [prefix, item_id])
			else:
				used_items[item_id] = true
			if int(ingredient.get("quantity", 0)) <= 0:
				errors.append("%s: ingredient '%s' quantity must be positive." % [prefix, item_id])
			if ingredient_ids.has(item_id):
				errors.append("%s: ingredient '%s' is repeated." % [prefix, item_id])
			ingredient_ids[item_id] = true
		var output := InventoryModel.recipe_output(recipe_data)
		var output_id := str(output.get("item_id", ""))
		if not items.has(output_id):
			errors.append("%s: unknown output item '%s'." % [prefix, output_id])
		else:
			used_items[output_id] = true
			var quantity := int(output.get("quantity", 0))
			if quantity <= 0:
				errors.append("%s: output quantity must be positive." % prefix)
			elif quantity > ItemCatalog.stack_limit(ItemCatalog.item(items, output_id)):
				errors.append("%s: output quantity exceeds the item stack limit." % prefix)
		if ingredient_ids.has(output_id):
			warnings.append("%s: output item is also consumed as an ingredient." % prefix)


static func validate_starting_inventory(
	campaign: Dictionary,
	campaign_id: String,
	items: Dictionary,
	used_items: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var value: Variant = campaign.get("starting_inventory", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: starting_inventory must be an array." % campaign_id)
		return
	var seen: Dictionary = {}
	for entry_value in value:
		if typeof(entry_value) != TYPE_DICTIONARY:
			errors.append("%s: starting_inventory entries must be objects." % campaign_id)
			continue
		var entry: Dictionary = entry_value
		var item_id := str(entry.get("item_id", ""))
		var prefix := "%s/starting_inventory/%s" % [campaign_id, item_id]
		if not items.has(item_id):
			errors.append("%s: unknown item." % prefix)
			continue
		used_items[item_id] = true
		if seen.has(item_id):
			errors.append("%s: item is repeated." % prefix)
		seen[item_id] = true
		var quantity := int(entry.get("quantity", 0))
		if quantity <= 0:
			errors.append("%s: quantity must be positive." % prefix)
		elif quantity > ItemCatalog.stack_limit(ItemCatalog.item(items, item_id)):
			errors.append("%s: quantity exceeds the item stack limit." % prefix)
	if Array(value).is_empty():
		warnings.append("%s: starting_inventory is empty." % campaign_id)


static func validate_starting_recipes(
	campaign: Dictionary,
	campaign_id: String,
	recipes: Dictionary,
	used_recipes: Dictionary,
	errors: Array[String]
) -> void:
	var value: Variant = campaign.get("starting_recipes", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: starting_recipes must be an array." % campaign_id)
		return
	var seen: Dictionary = {}
	for recipe_value in value:
		var recipe_id := str(recipe_value)
		if not recipes.has(recipe_id):
			errors.append("%s: starting_recipes references unknown recipe '%s'." % [campaign_id, recipe_id])
		elif seen.has(recipe_id):
			errors.append("%s: starting_recipes repeats '%s'." % [campaign_id, recipe_id])
		else:
			seen[recipe_id] = true
			used_recipes[recipe_id] = true


static func validate_map_item_rewards(
	map_data: Dictionary,
	items: Dictionary,
	recipes: Dictionary,
	used_items: Dictionary,
	used_recipes: Dictionary,
	errors: Array[String]
) -> void:
	var map_id := str(map_data.get("id", "map"))
	var cues_value: Variant = map_data.get("companion_cues", [])
	if typeof(cues_value) != TYPE_ARRAY:
		return
	for cue_value in cues_value:
		if typeof(cue_value) != TYPE_DICTIONARY:
			continue
		var cue: Dictionary = cue_value
		var prefix := "%s/companion_cue/%s" % [map_id, cue.get("id", "cue")]
		validate_grants(cue.get("reward_items", []), prefix + "/reward_items", items, used_items, errors)
		validate_recipe_unlocks(cue.get("unlock_recipes", []), prefix + "/unlock_recipes", recipes, used_recipes, errors)


static func validate_grants(
	value: Variant,
	prefix: String,
	items: Dictionary,
	used_items: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: grants must be an array." % prefix)
		return
	var grants: Array = value
	var seen: Dictionary = {}
	for grant_value in grants:
		if typeof(grant_value) != TYPE_DICTIONARY:
			errors.append("%s: grant entries must be objects." % prefix)
			continue
		var grant: Dictionary = grant_value
		var item_id := str(grant.get("item_id", ""))
		if not items.has(item_id):
			errors.append("%s: unknown item '%s'." % [prefix, item_id])
		else:
			used_items[item_id] = true
		if int(grant.get("quantity", 0)) <= 0:
			errors.append("%s: item '%s' quantity must be positive." % [prefix, item_id])
		if seen.has(item_id):
			errors.append("%s: item '%s' is repeated." % [prefix, item_id])
		seen[item_id] = true


static func validate_recipe_unlocks(
	value: Variant,
	prefix: String,
	recipes: Dictionary,
	used_recipes: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: recipe unlocks must be an array." % prefix)
		return
	var unlock_ids: Array = value
	var seen: Dictionary = {}
	for recipe_value in unlock_ids:
		if typeof(recipe_value) != TYPE_STRING:
			errors.append("%s: every recipe unlock must be a string ID." % prefix)
			continue
		var recipe_id := str(recipe_value).strip_edges()
		if recipe_id.is_empty():
			errors.append("%s: recipe unlock ID cannot be empty." % prefix)
		elif seen.has(recipe_id):
			errors.append("%s: recipe '%s' is repeated." % [prefix, recipe_id])
		elif not recipes.has(recipe_id):
			errors.append("%s: unknown recipe '%s'." % [prefix, recipe_id])
		else:
			seen[recipe_id] = true
			used_recipes[recipe_id] = true


static func collect_declared_file_uses(
	campaign_path: String,
	campaign: Dictionary,
	field: String,
	items: Dictionary,
	recipes: Dictionary,
	used_items: Dictionary,
	used_recipes: Dictionary
) -> void:
	var files_value: Variant = campaign.get(field, [])
	if typeof(files_value) != TYPE_ARRAY:
		return
	for relative_value in files_value as Array:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			continue
		var result := Repository.read_json(
			campaign_path.get_base_dir().path_join(relative_path)
		)
		if not bool(result.get("ok", false)):
			continue
		collect_authored_item_and_recipe_uses(
			result.get("data", {}),
			items,
			recipes,
			used_items,
			used_recipes
		)


# Usage warnings are cross-domain. A stock entry, story condition, cinematic
# reward or starting loadout reference is just as intentional as a recipe
# ingredient. Other domain validators remain responsible for rejecting bad IDs.
static func collect_authored_item_and_recipe_uses(
	value: Variant,
	items: Dictionary,
	recipes: Dictionary,
	used_items: Dictionary,
	used_recipes: Dictionary
) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		for key_value in data.keys():
			var key := str(key_value)
			var child: Variant = data.get(key_value)
			match key:
				"item_id", "ammo_item_id":
					mark_known_reference(str(child), items, used_items)
				"recipe_id":
					mark_known_reference(str(child), recipes, used_recipes)
				"refused_items":
					mark_known_array_references(child, items, used_items)
				"unlock_recipes", "starting_recipes":
					mark_known_array_references(child, recipes, used_recipes)
				"starting_equipment":
					if typeof(child) == TYPE_DICTIONARY:
						for item_value in (child as Dictionary).values():
							mark_known_reference(str(item_value), items, used_items)
				_:
					pass
			collect_authored_item_and_recipe_uses(
				child,
				items,
				recipes,
				used_items,
				used_recipes
			)
	elif typeof(value) == TYPE_ARRAY:
		for child_value in value as Array:
			collect_authored_item_and_recipe_uses(
				child_value,
				items,
				recipes,
				used_items,
				used_recipes
			)


static func mark_known_array_references(
	value: Variant,
	definitions: Dictionary,
	used: Dictionary
) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for item_value in value as Array:
		mark_known_reference(str(item_value), definitions, used)


static func mark_known_reference(
	identifier: String,
	definitions: Dictionary,
	used: Dictionary
) -> void:
	var clean := identifier.strip_edges()
	if not clean.is_empty() and definitions.has(clean):
		used[clean] = true


static func make_report(
	errors: Array[String],
	warnings: Array[String],
	base_report: Dictionary,
	item_count: int,
	recipe_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"map_count": base_report.get("map_count", 0),
		"definition_count": base_report.get("definition_count", 0),
		"placement_count": base_report.get("placement_count", 0),
		"zone_count": base_report.get("zone_count", 0),
		"cue_count": base_report.get("cue_count", 0),
		"item_count": item_count,
		"recipe_count": recipe_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
