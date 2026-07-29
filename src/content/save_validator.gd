@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/story_validator.gd")
const SaveProfile = preload("res://src/content/save_profile.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const StoryModel = preload("res://src/game/story_model.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

const ALLOWED_QUEST_STATUSES := [
	StoryModel.STATUS_NOT_STARTED,
	StoryModel.STATUS_ACTIVE,
	StoryModel.STATUS_COMPLETED
]


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var policy_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		var campaign_value: Variant = entry.get("data", {})
		if typeof(campaign_value) != TYPE_DICTIONARY:
			continue
		var campaign: Dictionary = campaign_value
		validate_policy(campaign, str(campaign.get("id", entry.get("id", "campaign"))), errors, warnings)
		policy_count += 1
	var report := base_report.duplicate(true)
	report["ok"] = errors.is_empty()
	report["errors"] = errors
	report["warnings"] = warnings
	report["save_policy_count"] = policy_count
	return report


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_campaign_path(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var campaign_result: Dictionary = Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
	else:
		var campaign: Dictionary = campaign_result.get("data", {})
		validate_policy(campaign, str(campaign.get("id", campaign_path)), errors, warnings)
	var report := base_report.duplicate(true)
	report["ok"] = errors.is_empty()
	report["errors"] = errors
	report["warnings"] = warnings
	report["save_policy_count"] = 1 if bool(campaign_result.get("ok", false)) else 0
	return report


static func validate_policy(
	campaign: Dictionary,
	campaign_id: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if not campaign.has("save_policy"):
		warnings.append("%s: save_policy is omitted; the backwards-compatible default policy will be used." % campaign_id)
		return
	var value: Variant = campaign.get("save_policy")
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: save_policy must be an object." % campaign_id)
		return
	var policy: Dictionary = value
	var defaults := SaveProfile.default_policy()
	if policy.has("manual_slots") and typeof(policy.get("manual_slots")) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: save_policy manual_slots must be numeric." % campaign_id)
	var manual_slots := int(policy.get("manual_slots", defaults.get("manual_slots", 3)))
	if manual_slots < SaveProfile.MIN_MANUAL_SLOTS or manual_slots > SaveProfile.MAX_MANUAL_SLOTS:
		errors.append("%s: save_policy manual_slots must be between %d and %d." % [campaign_id, SaveProfile.MIN_MANUAL_SLOTS, SaveProfile.MAX_MANUAL_SLOTS])
	for field in ["autosave_enabled", "autosave_on_travel", "autosave_on_progress", "allow_manual_save_in_combat"]:
		if policy.has(field) and typeof(policy.get(field)) != TYPE_BOOL:
			errors.append("%s: save_policy %s must be boolean." % [campaign_id, field])
	var effective := SaveProfile.policy(campaign)
	if not bool(effective.get("autosave_enabled", true)) and (
		bool(effective.get("autosave_on_travel", false)) or bool(effective.get("autosave_on_progress", false))
	):
		warnings.append("%s: autosave triggers are enabled while autosave_enabled is false." % campaign_id)


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var structural: Dictionary = SaveProfile.validate_structure(profile)
	append_messages(errors, structural.get("errors", []))
	var campaign_result: Dictionary = Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings}
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id := str(campaign.get("id", ""))
	if str(profile.get("campaign_id", "")) != campaign_id:
		errors.append("Save profile campaign_id does not match campaign '%s'." % campaign_id)
	validate_policy(campaign, campaign_id, errors, warnings)

	var item_result: Dictionary = ItemCatalog.load_item_catalogs(campaign_path, campaign)
	var recipe_result: Dictionary = ItemCatalog.load_recipe_catalogs(campaign_path, campaign)
	var story_result: Dictionary = StoryCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	append_messages(errors, recipe_result.get("errors", []))
	append_messages(errors, story_result.get("errors", []))
	var item_definitions: Dictionary = item_result.get("definitions", {})
	var recipe_definitions: Dictionary = recipe_result.get("definitions", {})
	var quest_definitions: Dictionary = story_result.get("quests", {})

	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) != TYPE_DICTIONARY:
		return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}
	var payload: Dictionary = payload_value
	var map_id := str(payload.get("map_id", ""))
	var map_path := Repository.find_exact_map_path(campaign_path, campaign, map_id)
	if map_path.is_empty():
		errors.append("Save profile references unknown map '%s'." % map_id)
	else:
		var map_result: Dictionary = Repository.read_json(map_path)
		if not bool(map_result.get("ok", false)):
			append_messages(errors, map_result.get("errors", []))
		else:
			validate_map_state(payload, map_result.get("data", {}), errors, warnings)
	validate_actor_state(payload, campaign, errors)
	validate_inventory(payload, item_definitions, errors)
	validate_recipes(payload, recipe_definitions, errors)
	validate_session_state(payload, errors, warnings)
	validate_quest_progress(payload, quest_definitions, errors)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func validate_map_state(
	payload: Dictionary,
	map_data: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var era_id := str(payload.get("era_id", ""))
	var era_found := false
	for value in map_data.get("eras", []):
		if typeof(value) == TYPE_DICTIONARY and str((value as Dictionary).get("id", "")) == era_id:
			era_found = true
			break
	if not era_found:
		errors.append("Save profile references unknown era '%s' for map '%s'." % [era_id, map_data.get("id", "map")])
	var canvas: Dictionary = map_data.get("canvas", {})
	var width := float(canvas.get("width", 0.0))
	var height := float(canvas.get("height", 0.0))
	for field in ["player_position", "companion_position", "companion_hold_position"]:
		var value: Variant = payload.get(field, {})
		if not SaveProfile.valid_position(value):
			continue
		var data: Dictionary = value
		var x := float(data.get("x", 0.0))
		var y := float(data.get("y", 0.0))
		if x < 0.0 or y < 0.0 or x > width or y > height:
			errors.append("Save payload %s lies outside the map canvas." % field)
	var facing_value: Variant = payload.get("facing", {})
	if SaveProfile.valid_position(facing_value):
		var facing_data: Dictionary = facing_value
		var facing := Vector2(float(facing_data.get("x", 0.0)), float(facing_data.get("y", 0.0)))
		if facing.length_squared() <= 0.0001:
			warnings.append("Save profile facing direction is zero and will fall back to down.")


static func validate_actor_state(payload: Dictionary, campaign: Dictionary, errors: Array[String]) -> void:
	var actors: Dictionary = campaign.get("actors", {})
	for actor_id in ["player", "companion"]:
		var actor_value: Variant = actors.get(actor_id, {})
		var actor: Dictionary = actor_value if typeof(actor_value) == TYPE_DICTIONARY else {}
		var maximum := int(actor.get("max_health", 1))
		var field := "%s_health" % actor_id
		var health := int(payload.get(field, 0))
		if health <= 0 or health > maximum:
			errors.append("Save payload %s must be between 1 and %d." % [field, maximum])
	if int(payload.get("clock_shards", -1)) < 0:
		errors.append("Save payload clock_shards cannot be negative.")


static func validate_inventory(payload: Dictionary, item_definitions: Dictionary, errors: Array[String]) -> void:
	var value: Variant = payload.get("inventory", {})
	if typeof(value) != TYPE_DICTIONARY:
		return
	var inventory: Dictionary = value
	for item_key in inventory.keys():
		var item_id := str(item_key)
		if not item_definitions.has(item_id):
			errors.append("Save inventory references unknown item '%s'." % item_id)
			continue
		var quantity := int(inventory.get(item_key, 0))
		if quantity <= 0:
			errors.append("Save inventory quantity for '%s' must be positive." % item_id)
		elif quantity > ItemCatalog.stack_limit(ItemCatalog.item(item_definitions, item_id)):
			errors.append("Save inventory quantity for '%s' exceeds its stack limit." % item_id)


static func validate_recipes(payload: Dictionary, recipe_definitions: Dictionary, errors: Array[String]) -> void:
	var value: Variant = payload.get("unlocked_recipes", [])
	if typeof(value) != TYPE_ARRAY:
		return
	var seen: Dictionary = {}
	for recipe_value in value:
		if typeof(recipe_value) != TYPE_STRING:
			errors.append("Save unlocked_recipes entries must be strings.")
			continue
		var recipe_id := str(recipe_value)
		if not recipe_definitions.has(recipe_id):
			errors.append("Save profile references unknown recipe '%s'." % recipe_id)
		elif seen.has(recipe_id):
			errors.append("Save profile repeats unlocked recipe '%s'." % recipe_id)
		seen[recipe_id] = true


static func validate_session_state(payload: Dictionary, errors: Array[String], warnings: Array[String]) -> void:
	var value: Variant = payload.get("session_state", {})
	if typeof(value) != TYPE_DICTIONARY:
		return
	var state: Dictionary = value
	for key_value in state.keys():
		var key := str(key_value).strip_edges()
		if key.is_empty():
			errors.append("Save session_state contains an empty key.")
		elif key.length() > 200:
			warnings.append("Save session_state key '%s' is unusually long." % key)
		if not SaveProfile.is_json_safe(state.get(key_value)):
			errors.append("Save session_state value for '%s' is not JSON-safe." % key)


static func validate_quest_progress(payload: Dictionary, quest_definitions: Dictionary, errors: Array[String]) -> void:
	var value: Variant = payload.get("quest_progress", {})
	if typeof(value) != TYPE_DICTIONARY:
		return
	var progress: Dictionary = value
	for quest_key in progress.keys():
		var quest_id := str(quest_key)
		if not quest_definitions.has(quest_id):
			errors.append("Save quest_progress references unknown quest '%s'." % quest_id)
			continue
		var record_value: Variant = progress.get(quest_key)
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("Save quest_progress record for '%s' must be an object." % quest_id)
			continue
		var record: Dictionary = record_value
		var status := str(record.get("status", StoryModel.STATUS_NOT_STARTED))
		if not ALLOWED_QUEST_STATUSES.has(status):
			errors.append("Save quest '%s' uses unsupported status '%s'." % [quest_id, status])
		var stage_id := str(record.get("stage_id", ""))
		if status in [StoryModel.STATUS_ACTIVE, StoryModel.STATUS_COMPLETED]:
			var quest_data := StoryCatalog.quest(quest_definitions, quest_id)
			if stage_id.is_empty() or StoryCatalog.stage(quest_data, stage_id).is_empty():
				errors.append("Save quest '%s' references unknown stage '%s'." % [quest_id, stage_id])


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
