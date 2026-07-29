extends RefCounted

const StoryCatalog = preload("res://src/content/story_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")

const STATUS_NOT_STARTED := "not_started"
const STATUS_ACTIVE := "active"
const STATUS_COMPLETED := "completed"


static func quest_status(progress: Dictionary, quest_id: String) -> String:
	var value: Variant = progress.get(quest_id, {})
	if typeof(value) != TYPE_DICTIONARY:
		return STATUS_NOT_STARTED
	return str((value as Dictionary).get("status", STATUS_NOT_STARTED))


static func quest_stage_id(progress: Dictionary, quest_id: String) -> String:
	var value: Variant = progress.get(quest_id, {})
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	return str((value as Dictionary).get("stage_id", ""))


static func initial_progress(campaign: Dictionary, quest_definitions: Dictionary) -> Dictionary:
	var progress: Dictionary = {}
	for quest_id in quest_definitions.keys():
		var quest_data := StoryCatalog.quest(quest_definitions, str(quest_id))
		if bool(quest_data.get("auto_start", false)):
			start_quest(progress, quest_definitions, str(quest_id))
	var starting_value: Variant = campaign.get("starting_quests", [])
	if typeof(starting_value) == TYPE_ARRAY:
		for quest_value in starting_value:
			start_quest(progress, quest_definitions, str(quest_value))
	return progress


static func start_quest(progress: Dictionary, quest_definitions: Dictionary, quest_id: String) -> Dictionary:
	if quest_status(progress, quest_id) != STATUS_NOT_STARTED:
		return {}
	var quest_data := StoryCatalog.quest(quest_definitions, quest_id)
	if quest_data.is_empty():
		return {}
	var stage_id := str(quest_data.get("initial_stage", ""))
	if stage_id.is_empty() or StoryCatalog.stage(quest_data, stage_id).is_empty():
		return {}
	progress[quest_id] = {"status": STATUS_ACTIVE, "stage_id": stage_id}
	return {"type": "quest_started", "quest_id": quest_id, "stage_id": stage_id}


static func set_quest_stage(
	progress: Dictionary,
	quest_definitions: Dictionary,
	quest_id: String,
	stage_id: String
) -> Dictionary:
	var quest_data := StoryCatalog.quest(quest_definitions, quest_id)
	if quest_data.is_empty() or StoryCatalog.stage(quest_data, stage_id).is_empty():
		return {}
	progress[quest_id] = {"status": STATUS_ACTIVE, "stage_id": stage_id}
	return {"type": "quest_stage_changed", "quest_id": quest_id, "stage_id": stage_id}


static func advance_quest(progress: Dictionary, quest_definitions: Dictionary, quest_id: String) -> Dictionary:
	if quest_status(progress, quest_id) != STATUS_ACTIVE:
		return {}
	var quest_data := StoryCatalog.quest(quest_definitions, quest_id)
	var current_id := quest_stage_id(progress, quest_id)
	var current := StoryCatalog.stage(quest_data, current_id)
	if current.is_empty():
		return {}
	var next_id := str(current.get("next_stage", ""))
	if next_id.is_empty():
		return complete_quest(progress, quest_definitions, quest_id)
	return set_quest_stage(progress, quest_definitions, quest_id, next_id)


static func complete_quest(progress: Dictionary, quest_definitions: Dictionary, quest_id: String) -> Dictionary:
	var quest_data := StoryCatalog.quest(quest_definitions, quest_id)
	if quest_data.is_empty() or quest_status(progress, quest_id) == STATUS_COMPLETED:
		return {}
	var stage_id := quest_stage_id(progress, quest_id)
	progress[quest_id] = {"status": STATUS_COMPLETED, "stage_id": stage_id}
	return {
		"type": "quest_completed",
		"quest_id": quest_id,
		"stage_id": stage_id,
		"rewards": StoryCatalog.effects(quest_data, "rewards")
	}


static func conditions_met(conditions: Array, context: Dictionary) -> bool:
	for value in conditions:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		if not condition_met(value, context):
			return false
	return true


static func condition_met(condition: Dictionary, context: Dictionary) -> bool:
	var condition_type := str(condition.get("type", "always"))
	match condition_type:
		"always":
			return true
		"has_item":
			var inventory: Dictionary = context.get("inventory", {})
			return InventoryModel.count(inventory, str(condition.get("item_id", ""))) >= maxi(1, int(condition.get("quantity", 1)))
		"has_capability":
			var capabilities_value: Variant = context.get("capabilities", [])
			if typeof(capabilities_value) not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
				return false
			return capabilities_value.has(str(condition.get("capability_id", "")))
		"state_equals":
			var state: Dictionary = context.get("session_state", {})
			var key := str(condition.get("key", ""))
			return state.has(key) and state.get(key) == condition.get("value")
		"quest_status":
			var progress: Dictionary = context.get("quest_progress", {})
			return quest_status(progress, str(condition.get("quest_id", ""))) == str(condition.get("status", STATUS_NOT_STARTED))
		"quest_stage":
			var progress: Dictionary = context.get("quest_progress", {})
			var quest_id := str(condition.get("quest_id", ""))
			return (
				quest_status(progress, quest_id) == STATUS_ACTIVE
				and quest_stage_id(progress, quest_id) == str(condition.get("stage_id", ""))
			)
		"map_is":
			return str(context.get("map_id", "")) == str(condition.get("map_id", ""))
		"era_is":
			return str(context.get("era_id", "")) == str(condition.get("era_id", ""))
		"clock_shards_at_least":
			return int(context.get("clock_shards", 0)) >= maxi(0, int(condition.get("amount", 0)))
		"currency_at_least":
			var balances: Dictionary = context.get("currency_balances", {})
			return int(balances.get(str(condition.get("currency_id", "")), 0)) >= maxi(0, int(condition.get("amount", 0)))
		_:
			return false


static func available_choices(node_data: Dictionary, context: Dictionary) -> Array:
	var output: Array = []
	for value in StoryCatalog.choices(node_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = value
		if conditions_met(StoryCatalog.conditions(choice), context):
			output.append(choice)
	return output


static func conversation_available(conversation_data: Dictionary, context: Dictionary) -> bool:
	return conditions_met(StoryCatalog.conditions(conversation_data), context)


static func evaluate_ready_quests(
	progress: Dictionary,
	quest_definitions: Dictionary,
	context: Dictionary,
	maximum_transitions: int = 32
) -> Array:
	var events: Array = []
	var transitions := 0
	var changed := true
	while changed and transitions < maximum_transitions:
		changed = false
		var quest_ids := active_quest_ids(progress, quest_definitions)
		for quest_id in quest_ids:
			var quest_data := StoryCatalog.quest(quest_definitions, quest_id)
			var stage_id := quest_stage_id(progress, quest_id)
			var stage_data := StoryCatalog.stage(quest_data, stage_id)
			if stage_data.is_empty():
				continue
			if not conditions_met(StoryCatalog.conditions(stage_data, "completion_conditions"), context):
				continue
			var event := advance_quest(progress, quest_definitions, quest_id)
			if event.is_empty():
				continue
			events.append(event)
			transitions += 1
			changed = true
			if transitions >= maximum_transitions:
				break
	return events


static func active_quest_ids(progress: Dictionary, quest_definitions: Dictionary) -> PackedStringArray:
	return sorted_quest_ids(progress, quest_definitions, STATUS_ACTIVE)


static func completed_quest_ids(progress: Dictionary, quest_definitions: Dictionary) -> PackedStringArray:
	return sorted_quest_ids(progress, quest_definitions, STATUS_COMPLETED)


static func sorted_quest_ids(
	progress: Dictionary,
	quest_definitions: Dictionary,
	status: String
) -> PackedStringArray:
	var ids: Array[String] = []
	for quest_id in progress.keys():
		var identifier := str(quest_id)
		if quest_status(progress, identifier) == status and quest_definitions.has(identifier):
			ids.append(identifier)
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_title := str(StoryCatalog.quest(quest_definitions, left).get("title", left))
		var right_title := str(StoryCatalog.quest(quest_definitions, right).get("title", right))
		return left_title.naturalnocasecmp_to(right_title) < 0
	)
	return PackedStringArray(ids)


static func current_stage(progress: Dictionary, quest_definitions: Dictionary, quest_id: String) -> Dictionary:
	return StoryCatalog.stage(
		StoryCatalog.quest(quest_definitions, quest_id),
		quest_stage_id(progress, quest_id)
	)


static func quest_title(quest_definitions: Dictionary, quest_id: String) -> String:
	return str(StoryCatalog.quest(quest_definitions, quest_id).get("title", quest_id.replace("_", " ").capitalize()))


static func current_objective(progress: Dictionary, quest_definitions: Dictionary, quest_id: String) -> String:
	var stage_data := current_stage(progress, quest_definitions, quest_id)
	return str(stage_data.get("description", "No objective is currently defined."))
