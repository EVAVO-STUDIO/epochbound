@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/item_validator.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

const MAX_STATE_KEY_LENGTH := 160
const ALLOWED_QUEST_STATUSES := ["not_started", "active", "completed"]


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
	var conversation_count := 0
	var quest_count := 0
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
		conversation_count += int(report.get("conversation_count", 0))
		quest_count += int(report.get("quest_count", 0))
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
		"recipe_count": recipe_count,
		"conversation_count": conversation_count,
		"quest_count": quest_count
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
	validate_story_file_list(campaign, campaign_id, errors, warnings)

	var story_result := StoryCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, story_result.get("errors", []))
	var conversations: Dictionary = story_result.get("conversations", {})
	var quests: Dictionary = story_result.get("quests", {})
	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	var recipe_result := ItemCatalog.load_recipe_catalogs(campaign_path, campaign)
	var object_result := ObjectCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	append_messages(errors, recipe_result.get("errors", []))
	append_messages(errors, object_result.get("errors", []))
	var items: Dictionary = item_result.get("definitions", {})
	var recipes: Dictionary = recipe_result.get("definitions", {})
	var object_definitions: Dictionary = object_result.get("definitions", {})

	var map_records: Dictionary = {}
	var map_ids: Dictionary = {}
	var era_ids: Dictionary = {}
	load_campaign_maps(campaign_path, campaign, map_records, map_ids, era_ids)
	var used_conversations: Dictionary = {}
	var used_quests: Dictionary = {}

	for conversation_id in conversations.keys():
		validate_conversation(
			StoryCatalog.conversation(conversations, str(conversation_id)),
			str(conversation_id),
			conversations,
			quests,
			items,
			recipes,
			map_ids,
			era_ids,
			used_quests,
			errors,
			warnings
		)

	for quest_id in quests.keys():
		validate_quest(
			StoryCatalog.quest(quests, str(quest_id)),
			str(quest_id),
			quests,
			items,
			recipes,
			map_ids,
			era_ids,
			used_quests,
			errors,
			warnings
		)

	validate_starting_quests(campaign, campaign_id, quests, used_quests, errors)
	validate_story_references(
		campaign_id,
		object_definitions,
		map_records,
		conversations,
		quests,
		items,
		recipes,
		map_ids,
		era_ids,
		used_conversations,
		used_quests,
		errors,
		warnings
	)

	for conversation_id in conversations.keys():
		if not used_conversations.has(conversation_id):
			warnings.append("%s: conversation '%s' is not referenced by any object or map interaction." % [campaign_id, conversation_id])
	for quest_id in quests.keys():
		var quest_data := StoryCatalog.quest(quests, str(quest_id))
		if not used_quests.has(quest_id) and not bool(quest_data.get("auto_start", false)):
			warnings.append("%s: quest '%s' is never started or referenced." % [campaign_id, quest_id])

	return make_report(errors, warnings, base_report, conversations.size(), quests.size())


static func validate_story_file_list(
	campaign: Dictionary,
	campaign_id: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var value: Variant = campaign.get("story_files", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: story_files must be an array of safe relative JSON paths." % campaign_id)
		return
	var files: Array = value
	if files.is_empty():
		warnings.append("%s: story_files is empty." % campaign_id)
	var seen: Dictionary = {}
	for relative_value in files:
		var relative_path := str(relative_value)
		if not StoryCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe story catalog path '%s'." % [campaign_id, relative_path])
		elif seen.has(relative_path):
			errors.append("%s: story_files repeats '%s'." % [campaign_id, relative_path])
		else:
			seen[relative_path] = true


static func load_campaign_maps(
	campaign_path: String,
	campaign: Dictionary,
	map_records: Dictionary,
	map_ids: Dictionary,
	era_ids: Dictionary
) -> void:
	var value: Variant = campaign.get("map_files", [])
	if typeof(value) != TYPE_ARRAY:
		return
	for relative_value in value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			continue
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result := Repository.read_json(path)
		if not result.get("ok", false):
			continue
		var map_data: Dictionary = result.get("data", {})
		var map_id := str(map_data.get("id", ""))
		if map_id.is_empty():
			continue
		map_records[map_id] = map_data
		map_ids[map_id] = true
		for era_value in map_data.get("eras", []):
			if typeof(era_value) == TYPE_DICTIONARY:
				var era: Dictionary = era_value
				var era_id := str(era.get("id", ""))
				if not era_id.is_empty():
					era_ids[era_id] = true


static func validate_conversation(
	conversation_data: Dictionary,
	conversation_id: String,
	conversations: Dictionary,
	quests: Dictionary,
	items: Dictionary,
	recipes: Dictionary,
	map_ids: Dictionary,
	era_ids: Dictionary,
	used_quests: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var prefix := "conversation/%s" % conversation_id
	if conversation_id.is_empty() or Repository.normalise_id(conversation_id) != conversation_id:
		errors.append("%s: id must be a normalised lowercase identifier." % prefix)
	if str(conversation_data.get("display_name", "")).strip_edges().is_empty():
		errors.append("%s: display_name is required." % prefix)
	validate_conditions(
		StoryCatalog.conditions(conversation_data),
		prefix + "/conditions",
		quests,
		items,
		map_ids,
		era_ids,
		used_quests,
		errors
	)
	var nodes_value: Variant = conversation_data.get("nodes", [])
	if typeof(nodes_value) != TYPE_ARRAY:
		errors.append("%s: nodes must be an array." % prefix)
		return
	var nodes: Array = nodes_value
	if nodes.is_empty():
		errors.append("%s: at least one node is required." % prefix)
		return
	var node_ids: Dictionary = {}
	for node_value in nodes:
		if typeof(node_value) != TYPE_DICTIONARY:
			errors.append("%s: every node must be an object." % prefix)
			continue
		var node_data: Dictionary = node_value
		var node_id := str(node_data.get("id", ""))
		var node_prefix := "%s/node/%s" % [prefix, node_id if not node_id.is_empty() else "node"]
		if node_id.is_empty() or Repository.normalise_id(node_id) != node_id:
			errors.append("%s: id must be a normalised lowercase identifier." % node_prefix)
		elif node_ids.has(node_id):
			errors.append("%s: duplicate node id '%s'." % [prefix, node_id])
		else:
			node_ids[node_id] = node_data
	var start_node := str(conversation_data.get("start_node", ""))
	if start_node.is_empty() or not node_ids.has(start_node):
		errors.append("%s: start_node '%s' does not exist." % [prefix, start_node])

	var outgoing: Dictionary = {}
	for node_id in node_ids.keys():
		var node_data: Dictionary = node_ids[node_id]
		var node_prefix := "%s/node/%s" % [prefix, node_id]
		var kind := str(node_data.get("kind", ""))
		if not StoryCatalog.ALLOWED_NODE_KINDS.has(kind):
			errors.append("%s: unsupported kind '%s'." % [node_prefix, kind])
			continue
		validate_conditions(
			StoryCatalog.conditions(node_data),
			node_prefix + "/conditions",
			quests,
			items,
			map_ids,
			era_ids,
			used_quests,
			errors
		)
		validate_effects(
			StoryCatalog.effects(node_data),
			node_prefix + "/effects",
			quests,
			items,
			recipes,
			used_quests,
			errors
		)
		validate_editor_position(node_data.get("editor_position"), node_prefix, errors)
		match kind:
			"line":
				validate_text_value(node_data.get("text", ""), node_prefix + "/text", errors)
				if str(node_data.get("speaker", "")).strip_edges().is_empty():
					warnings.append("%s: speaker is empty." % node_prefix)
				var next_id := str(node_data.get("next", ""))
				if not next_id.is_empty():
					outgoing[node_id] = [next_id]
			"choice":
				validate_text_value(node_data.get("prompt", ""), node_prefix + "/prompt", errors)
				var choices_value: Variant = node_data.get("choices", [])
				if typeof(choices_value) != TYPE_ARRAY:
					errors.append("%s: choices must be an array." % node_prefix)
					continue
				var choices: Array = choices_value
				if choices.is_empty():
					errors.append("%s: choice nodes require at least one choice." % node_prefix)
				var choice_ids: Dictionary = {}
				var targets: Array = []
				for choice_value in choices:
					if typeof(choice_value) != TYPE_DICTIONARY:
						errors.append("%s: every choice must be an object." % node_prefix)
						continue
					var choice: Dictionary = choice_value
					var choice_id := str(choice.get("id", ""))
					var choice_prefix := "%s/choice/%s" % [node_prefix, choice_id if not choice_id.is_empty() else "choice"]
					if choice_id.is_empty() or Repository.normalise_id(choice_id) != choice_id:
						errors.append("%s: id must be a normalised lowercase identifier." % choice_prefix)
					elif choice_ids.has(choice_id):
						errors.append("%s: duplicate choice id '%s'." % [node_prefix, choice_id])
					else:
						choice_ids[choice_id] = true
					validate_text_value(choice.get("text", ""), choice_prefix + "/text", errors)
					validate_conditions(
						StoryCatalog.conditions(choice),
						choice_prefix + "/conditions",
						quests,
						items,
						map_ids,
						era_ids,
						used_quests,
						errors
					)
					validate_effects(
						StoryCatalog.effects(choice),
						choice_prefix + "/effects",
						quests,
						items,
						recipes,
						used_quests,
						errors
					)
					var next_id := str(choice.get("next", ""))
					if next_id.is_empty():
						errors.append("%s: next is required." % choice_prefix)
					else:
						targets.append(next_id)
				outgoing[node_id] = targets
			"end":
				outgoing[node_id] = []
			_:
				pass

	for source_id in outgoing.keys():
		for target_value in outgoing[source_id]:
			var target_id := str(target_value)
			if not node_ids.has(target_id):
				errors.append("%s/node/%s: next node '%s' does not exist." % [prefix, source_id, target_id])
	var reachable := reachable_nodes(start_node, outgoing)
	for node_id in node_ids.keys():
		if not reachable.has(node_id):
			warnings.append("%s/node/%s: node is unreachable from start_node." % [prefix, node_id])
	if conversations.is_empty():
		warnings.append("%s: no conversations are available." % prefix)


static func validate_quest(
	quest_data: Dictionary,
	quest_id: String,
	quests: Dictionary,
	items: Dictionary,
	recipes: Dictionary,
	map_ids: Dictionary,
	era_ids: Dictionary,
	used_quests: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	var prefix := "quest/%s" % quest_id
	if quest_id.is_empty() or Repository.normalise_id(quest_id) != quest_id:
		errors.append("%s: id must be a normalised lowercase identifier." % prefix)
	if str(quest_data.get("title", "")).strip_edges().is_empty():
		errors.append("%s: title is required." % prefix)
	if str(quest_data.get("summary", "")).strip_edges().is_empty():
		warnings.append("%s: summary is empty." % prefix)
	if typeof(quest_data.get("auto_start", false)) != TYPE_BOOL:
		errors.append("%s: auto_start must be boolean." % prefix)
	var stages_value: Variant = quest_data.get("stages", [])
	if typeof(stages_value) != TYPE_ARRAY:
		errors.append("%s: stages must be an array." % prefix)
		return
	var stages: Array = stages_value
	if stages.is_empty():
		errors.append("%s: at least one stage is required." % prefix)
		return
	var stage_ids: Dictionary = {}
	var stage_records: Array[Dictionary] = []
	for stage_value in stages:
		if typeof(stage_value) != TYPE_DICTIONARY:
			errors.append("%s: every stage must be an object." % prefix)
			continue
		var stage_data: Dictionary = stage_value
		stage_records.append(stage_data)
		var stage_id := str(stage_data.get("id", ""))
		var stage_prefix := "%s/stage/%s" % [prefix, stage_id if not stage_id.is_empty() else "stage"]
		if stage_id.is_empty() or Repository.normalise_id(stage_id) != stage_id:
			errors.append("%s: id must be a normalised lowercase identifier." % stage_prefix)
		elif stage_ids.has(stage_id):
			errors.append("%s: duplicate stage id '%s'." % [prefix, stage_id])
		else:
			stage_ids[stage_id] = stage_data
	var initial_stage := str(quest_data.get("initial_stage", ""))
	if initial_stage.is_empty() or not stage_ids.has(initial_stage):
		errors.append("%s: initial_stage '%s' does not exist." % [prefix, initial_stage])
	var outgoing: Dictionary = {}
	for stage_data in stage_records:
		var stage_id := str(stage_data.get("id", ""))
		var stage_prefix := "%s/stage/%s" % [prefix, stage_id if not stage_id.is_empty() else "stage"]
		if str(stage_data.get("description", "")).strip_edges().is_empty():
			errors.append("%s: description is required." % stage_prefix)
		var conditions := StoryCatalog.conditions(stage_data, "completion_conditions")
		if conditions.is_empty():
			warnings.append("%s: completion_conditions is empty and will advance immediately." % stage_prefix)
		validate_conditions(
			conditions,
			stage_prefix + "/completion_conditions",
			quests,
			items,
			map_ids,
			era_ids,
			used_quests,
			errors
		)
		var next_stage := str(stage_data.get("next_stage", ""))
		if not next_stage.is_empty() and not stage_ids.has(next_stage):
			errors.append("%s: next_stage '%s' does not exist." % [stage_prefix, next_stage])
		outgoing[stage_id] = [] if next_stage.is_empty() else [next_stage]
	validate_effects(
		StoryCatalog.effects(quest_data, "rewards"),
		prefix + "/rewards",
		quests,
		items,
		recipes,
		used_quests,
		errors
	)
	var reachable := reachable_nodes(initial_stage, outgoing)
	for stage_id in stage_ids.keys():
		if not reachable.has(stage_id):
			warnings.append("%s/stage/%s: stage is unreachable from initial_stage." % [prefix, stage_id])


static func validate_starting_quests(
	campaign: Dictionary,
	campaign_id: String,
	quests: Dictionary,
	used_quests: Dictionary,
	errors: Array[String]
) -> void:
	var value: Variant = campaign.get("starting_quests", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: starting_quests must be an array." % campaign_id)
		return
	var seen: Dictionary = {}
	for quest_value in value:
		var quest_id := str(quest_value)
		if not quests.has(quest_id):
			errors.append("%s: starting_quests references unknown quest '%s'." % [campaign_id, quest_id])
		elif seen.has(quest_id):
			errors.append("%s: starting_quests repeats '%s'." % [campaign_id, quest_id])
		else:
			seen[quest_id] = true
			used_quests[quest_id] = true


static func validate_story_references(
	campaign_id: String,
	object_definitions: Dictionary,
	map_records: Dictionary,
	conversations: Dictionary,
	quests: Dictionary,
	items: Dictionary,
	recipes: Dictionary,
	map_ids: Dictionary,
	era_ids: Dictionary,
	used_conversations: Dictionary,
	used_quests: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	for object_id in object_definitions.keys():
		var object_data: Dictionary = object_definitions.get(object_id, {})
		var conversation_id := str(object_data.get("conversation_id", "")).strip_edges()
		if conversation_id.is_empty():
			continue
		if not conversations.has(conversation_id):
			errors.append("%s/object/%s: unknown conversation_id '%s'." % [campaign_id, object_id, conversation_id])
		else:
			used_conversations[conversation_id] = true
		validate_effects(
			StoryCatalog.effects(object_data, "story_effects"),
			"%s/object/%s/story_effects" % [campaign_id, object_id],
			quests,
			items,
			recipes,
			used_quests,
			errors
		)
	for map_id in map_records.keys():
		var map_data: Dictionary = map_records[map_id]
		for interaction_value in map_data.get("interactions", []):
			if typeof(interaction_value) != TYPE_DICTIONARY:
				continue
			var interaction: Dictionary = interaction_value
			var interaction_id := str(interaction.get("id", "interaction"))
			var prefix := "%s/map/%s/interaction/%s" % [campaign_id, map_id, interaction_id]
			var conversation_id := str(interaction.get("conversation_id", "")).strip_edges()
			if not conversation_id.is_empty():
				if not conversations.has(conversation_id):
					errors.append("%s: unknown conversation_id '%s'." % [prefix, conversation_id])
				else:
					used_conversations[conversation_id] = true
			validate_conditions(
				StoryCatalog.conditions(interaction, "story_conditions"),
				prefix + "/story_conditions",
				quests,
				items,
				map_ids,
				era_ids,
				used_quests,
				errors
			)
			validate_effects(
				StoryCatalog.effects(interaction, "story_effects"),
				prefix + "/story_effects",
				quests,
				items,
				recipes,
				used_quests,
				errors
			)
		for cue_value in map_data.get("companion_cues", []):
			if typeof(cue_value) != TYPE_DICTIONARY:
				continue
			var cue: Dictionary = cue_value
			validate_effects(
				StoryCatalog.effects(cue, "story_effects"),
				"%s/map/%s/companion_cue/%s/story_effects" % [campaign_id, map_id, cue.get("id", "cue")],
				quests,
				items,
				recipes,
				used_quests,
				errors
			)
	if conversations.is_empty():
		warnings.append("%s: no conversations are declared." % campaign_id)


static func validate_conditions(
	conditions: Array,
	prefix: String,
	quests: Dictionary,
	items: Dictionary,
	map_ids: Dictionary,
	era_ids: Dictionary,
	used_quests: Dictionary,
	errors: Array[String]
) -> void:
	for index in range(conditions.size()):
		var value: Variant = conditions[index]
		var condition_prefix := "%s/%d" % [prefix, index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s: condition must be an object." % condition_prefix)
			continue
		var condition: Dictionary = value
		var condition_type := str(condition.get("type", ""))
		if not StoryCatalog.ALLOWED_CONDITION_TYPES.has(condition_type):
			errors.append("%s: unsupported condition type '%s'." % [condition_prefix, condition_type])
			continue
		match condition_type:
			"always":
				pass
			"has_item":
				var item_id := str(condition.get("item_id", ""))
				if not items.has(item_id):
					errors.append("%s: unknown item '%s'." % [condition_prefix, item_id])
				if int(condition.get("quantity", 0)) <= 0:
					errors.append("%s: quantity must be positive." % condition_prefix)
			"has_capability":
				var capability_id := str(condition.get("capability_id", "")).strip_edges()
				if capability_id.is_empty() or Repository.normalise_id(capability_id) != capability_id:
					errors.append("%s: capability_id must be a normalised lowercase identifier." % condition_prefix)
			"state_equals":
				var key := str(condition.get("key", "")).strip_edges()
				if key.is_empty():
					errors.append("%s: key is required." % condition_prefix)
				elif key.length() > MAX_STATE_KEY_LENGTH:
					errors.append("%s: key exceeds %d characters." % [condition_prefix, MAX_STATE_KEY_LENGTH])
				if not condition.has("value"):
					errors.append("%s: value is required." % condition_prefix)
			"quest_status":
				var quest_id := str(condition.get("quest_id", ""))
				if not quests.has(quest_id):
					errors.append("%s: unknown quest '%s'." % [condition_prefix, quest_id])
				else:
					used_quests[quest_id] = true
				if not ALLOWED_QUEST_STATUSES.has(str(condition.get("status", ""))):
					errors.append("%s: unsupported quest status '%s'." % [condition_prefix, condition.get("status", "")])
			"quest_stage":
				var quest_id := str(condition.get("quest_id", ""))
				var stage_id := str(condition.get("stage_id", ""))
				if not quests.has(quest_id):
					errors.append("%s: unknown quest '%s'." % [condition_prefix, quest_id])
				elif StoryCatalog.stage(StoryCatalog.quest(quests, quest_id), stage_id).is_empty():
					errors.append("%s: unknown stage '%s' on quest '%s'." % [condition_prefix, stage_id, quest_id])
				else:
					used_quests[quest_id] = true
			"map_is":
				var map_id := str(condition.get("map_id", ""))
				if not map_ids.has(map_id):
					errors.append("%s: unknown map '%s'." % [condition_prefix, map_id])
			"era_is":
				var era_id := str(condition.get("era_id", ""))
				if not era_ids.has(era_id):
					errors.append("%s: unknown era '%s'." % [condition_prefix, era_id])
			"clock_shards_at_least":
				if int(condition.get("amount", -1)) < 0:
					errors.append("%s: amount cannot be negative." % condition_prefix)
			_:
				pass


static func validate_effects(
	effects: Array,
	prefix: String,
	quests: Dictionary,
	items: Dictionary,
	recipes: Dictionary,
	used_quests: Dictionary,
	errors: Array[String]
) -> void:
	for index in range(effects.size()):
		var value: Variant = effects[index]
		var effect_prefix := "%s/%d" % [prefix, index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s: effect must be an object." % effect_prefix)
			continue
		var effect: Dictionary = value
		var effect_type := str(effect.get("type", ""))
		if not StoryCatalog.ALLOWED_EFFECT_TYPES.has(effect_type):
			errors.append("%s: unsupported effect type '%s'." % [effect_prefix, effect_type])
			continue
		match effect_type:
			"start_quest", "advance_quest", "complete_quest":
				var quest_id := str(effect.get("quest_id", ""))
				if not quests.has(quest_id):
					errors.append("%s: unknown quest '%s'." % [effect_prefix, quest_id])
				else:
					used_quests[quest_id] = true
			"set_quest_stage":
				var quest_id := str(effect.get("quest_id", ""))
				var stage_id := str(effect.get("stage_id", ""))
				if not quests.has(quest_id):
					errors.append("%s: unknown quest '%s'." % [effect_prefix, quest_id])
				elif StoryCatalog.stage(StoryCatalog.quest(quests, quest_id), stage_id).is_empty():
					errors.append("%s: unknown stage '%s' on quest '%s'." % [effect_prefix, stage_id, quest_id])
				else:
					used_quests[quest_id] = true
			"set_state":
				var key := str(effect.get("key", "")).strip_edges()
				if key.is_empty():
					errors.append("%s: key is required." % effect_prefix)
				elif key.length() > MAX_STATE_KEY_LENGTH:
					errors.append("%s: key exceeds %d characters." % [effect_prefix, MAX_STATE_KEY_LENGTH])
				if not effect.has("value"):
					errors.append("%s: value is required." % effect_prefix)
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
			"grant_clock_shards":
				if int(effect.get("amount", 0)) <= 0:
					errors.append("%s: amount must be positive." % effect_prefix)
			"message":
				if str(effect.get("text", "")).strip_edges().is_empty():
					errors.append("%s: text is required." % effect_prefix)
			_:
				pass


static func validate_text_value(value: Variant, prefix: String, errors: Array[String]) -> void:
	if typeof(value) == TYPE_STRING:
		if str(value).strip_edges().is_empty():
			errors.append("%s: text is required." % prefix)
		return
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: value must be text or an era-keyed object." % prefix)
		return
	var by_era: Dictionary = value
	if by_era.is_empty():
		errors.append("%s: era-keyed text cannot be empty." % prefix)
	for key in by_era.keys():
		if str(by_era.get(key, "")).strip_edges().is_empty():
			errors.append("%s: text for '%s' is empty." % [prefix, key])


static func validate_editor_position(value: Variant, prefix: String, errors: Array[String]) -> void:
	if value == null:
		return
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: editor_position must be an object." % prefix)
		return
	var data: Dictionary = value
	if not data.has("x") or not data.has("y"):
		errors.append("%s: editor_position requires x and y." % prefix)


static func reachable_nodes(start_id: String, outgoing: Dictionary) -> Dictionary:
	var reachable: Dictionary = {}
	if start_id.is_empty():
		return reachable
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if reachable.has(current):
			continue
		reachable[current] = true
		var targets_value: Variant = outgoing.get(current, [])
		if typeof(targets_value) != TYPE_ARRAY:
			continue
		for target_value in targets_value:
			var target_id := str(target_value)
			if not target_id.is_empty() and not reachable.has(target_id):
				queue.append(target_id)
	return reachable


static func make_report(
	errors: Array[String],
	warnings: Array[String],
	base_report: Dictionary,
	conversation_count: int,
	quest_count: int
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
		"item_count": base_report.get("item_count", 0),
		"recipe_count": base_report.get("recipe_count", 0),
		"conversation_count": conversation_count,
		"quest_count": quest_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
