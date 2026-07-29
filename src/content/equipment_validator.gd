@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/save_validator.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const EquipmentModel = preload("res://src/game/equipment_model.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")

const MAX_BONUS := 999
const MAX_MOVE_SPEED_BONUS := 300.0


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var capability_count := 0
	var equipment_item_count := 0
	var equipment_slot_count := 0
	var capability_gate_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		var report: Dictionary = validate_equipment_only(str(entry.get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		capability_count += int(report.get("capability_count", 0))
		equipment_item_count += int(report.get("equipment_item_count", 0))
		equipment_slot_count += int(report.get("equipment_slot_count", 0))
		capability_gate_count += int(report.get("capability_gate_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["capability_count"] = capability_count
	output["equipment_item_count"] = equipment_item_count
	output["equipment_slot_count"] = equipment_slot_count
	output["capability_gate_count"] = capability_gate_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_campaign_path(campaign_path)
	var equipment_report: Dictionary = validate_equipment_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, equipment_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, equipment_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	for field in ["capability_count", "equipment_item_count", "equipment_slot_count", "capability_gate_count"]:
		output[field] = equipment_report.get(field, 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_profile(profile, campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var campaign_result: Dictionary = Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings}
	var campaign: Dictionary = campaign_result.get("data", {})
	var item_result: Dictionary = ItemCatalog.load_item_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	var item_definitions: Dictionary = item_result.get("definitions", {})
	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) == TYPE_DICTIONARY:
		validate_profile_equipment(
			(payload_value as Dictionary).get("equipment", {}),
			(payload_value as Dictionary).get("inventory", {}),
			campaign,
			item_definitions,
			errors
		)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func validate_equipment_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result: Dictionary = Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return make_report(errors, warnings, 0, 0, 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id: String = str(campaign.get("id", campaign_path))

	validate_capability_file_list(campaign, campaign_id, errors, warnings)
	var capability_result: Dictionary = EquipmentCatalog.load_capability_catalogs(campaign_path, campaign)
	append_messages(errors, capability_result.get("errors", []))
	var capabilities: Dictionary = capability_result.get("definitions", {})
	var capability_sources: Dictionary = {}
	for file_value in capability_result.get("files", []):
		if typeof(file_value) != TYPE_DICTIONARY:
			continue
		var file_record: Dictionary = file_value
		validate_capability_catalog_file(
			file_record.get("data", {}),
			str(file_record.get("path", "capability catalog")),
			capability_sources,
			errors,
			warnings
		)

	var item_result: Dictionary = ItemCatalog.load_item_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	var items: Dictionary = item_result.get("definitions", {})
	var slots: Dictionary = validate_slots(campaign, campaign_id, errors, warnings)
	var used_capabilities: Dictionary = {}
	var equipment_count: int = validate_equipment_items(
		items,
		slots,
		capabilities,
		used_capabilities,
		campaign_id,
		errors,
		warnings
	)
	validate_base_capabilities(campaign, campaign_id, capabilities, used_capabilities, errors)
	validate_starting_equipment(campaign, campaign_id, items, slots, errors, warnings)

	var gate_count := 0
	var map_records: Array = []
	var map_files_value: Variant = campaign.get("map_files", [])
	if typeof(map_files_value) == TYPE_ARRAY:
		for relative_value in map_files_value:
			var relative_path: String = str(relative_value)
			if not ObjectCatalog.safe_relative_json_path(relative_path):
				continue
			var map_result: Dictionary = Repository.read_json(campaign_path.get_base_dir().path_join(relative_path))
			if not bool(map_result.get("ok", false)):
				continue
			var map_data: Dictionary = map_result.get("data", {})
			map_records.append(map_data)
			gate_count += validate_map_gates(map_data, capabilities, used_capabilities, errors)

	var object_result: Dictionary = ObjectCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, object_result.get("errors", []))
	var object_definitions: Dictionary = object_result.get("definitions", {})
	for object_id_value in object_definitions.keys():
		var object_id: String = str(object_id_value)
		var object_data: Dictionary = object_definitions.get(object_id, {})
		if object_data.has("required_capabilities"):
			gate_count += 1
			validate_capability_references(
				object_data.get("required_capabilities"),
				"%s/object/%s/required_capabilities" % [campaign_id, object_id],
				capabilities,
				used_capabilities,
				errors
			)

	var story_result: Dictionary = StoryCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, story_result.get("errors", []))
	validate_story_capabilities(
		story_result.get("conversations", {}),
		story_result.get("quests", {}),
		capabilities,
		used_capabilities,
		errors
	)

	for capability_id_value in capabilities.keys():
		var capability_id: String = str(capability_id_value)
		if not used_capabilities.has(capability_id):
			warnings.append("%s: capability '%s' is not granted, required or referenced by story content." % [campaign_id, capability_id])

	return make_report(errors, warnings, capabilities.size(), equipment_count, slots.size(), gate_count)


static func validate_capability_file_list(
	campaign: Dictionary,
	campaign_id: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if not campaign.has("capability_files"):
		warnings.append("%s: capability_files is omitted; no custom capability definitions will be loaded." % campaign_id)
		return
	var value: Variant = campaign.get("capability_files")
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: capability_files must be an array of safe relative JSON paths." % campaign_id)
		return
	var seen: Dictionary = {}
	for relative_value in value:
		var relative_path: String = str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe capability_files path '%s'." % [campaign_id, relative_path])
		elif seen.has(relative_path):
			errors.append("%s: capability_files repeats '%s'." % [campaign_id, relative_path])
		else:
			seen[relative_path] = true


static func validate_capability_catalog_file(
	catalog: Dictionary,
	path: String,
	sources: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if int(catalog.get("schema_version", 0)) != EquipmentCatalog.SUPPORTED_SCHEMA:
		errors.append("%s: unsupported capability catalog schema_version." % path)
	var value: Variant = catalog.get("capabilities", [])
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: capabilities must be an array." % path)
		return
	var records: Array = value
	if records.is_empty():
		warnings.append("%s: capability catalog is empty." % path)
	var local_ids: Dictionary = {}
	for record_value in records:
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("%s: every capability must be an object." % path)
			continue
		var data: Dictionary = record_value
		var capability_id: String = str(data.get("id", ""))
		var prefix: String = "%s/%s" % [path, capability_id if not capability_id.is_empty() else "capability"]
		if not valid_capability_id(capability_id):
			errors.append("%s: id must be a normalised lowercase identifier no longer than %d characters." % [prefix, EquipmentCatalog.MAX_CAPABILITY_ID_LENGTH])
		elif local_ids.has(capability_id):
			errors.append("%s: duplicate capability id '%s'." % [path, capability_id])
		else:
			local_ids[capability_id] = true
			if sources.has(capability_id) and sources[capability_id] != path:
				errors.append("%s: capability '%s' is also declared by %s." % [path, capability_id, sources[capability_id]])
			sources[capability_id] = path
		if str(data.get("display_name", "")).strip_edges().is_empty():
			errors.append("%s: display_name is required." % prefix)
		var description: String = str(data.get("description", "")).strip_edges()
		if description.is_empty():
			warnings.append("%s: description is empty." % prefix)
		elif description.length() > EquipmentCatalog.MAX_DESCRIPTION_LENGTH:
			errors.append("%s: description exceeds %d characters." % [prefix, EquipmentCatalog.MAX_DESCRIPTION_LENGTH])


static func validate_slots(
	campaign: Dictionary,
	campaign_id: String,
	errors: Array[String],
	warnings: Array[String]
) -> Dictionary:
	var output: Dictionary = {}
	if not campaign.has("equipment_slots"):
		warnings.append("%s: equipment_slots is omitted; the default Weapon, Body and Tool slots will be used." % campaign_id)
		for slot_value in EquipmentCatalog.default_slots():
			var slot_data: Dictionary = slot_value
			output[str(slot_data.get("id", ""))] = slot_data
		return output
	var value: Variant = campaign.get("equipment_slots")
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: equipment_slots must be an array." % campaign_id)
		return output
	for slot_value in value:
		if typeof(slot_value) != TYPE_DICTIONARY:
			errors.append("%s: equipment slot entries must be objects." % campaign_id)
			continue
		var slot_data: Dictionary = slot_value
		var slot_id: String = str(slot_data.get("id", ""))
		var prefix: String = "%s/equipment_slot/%s" % [campaign_id, slot_id if not slot_id.is_empty() else "slot"]
		if slot_id.is_empty() or Repository.normalise_id(slot_id) != slot_id:
			errors.append("%s: id must be a normalised lowercase identifier." % prefix)
		elif output.has(slot_id):
			errors.append("%s: equipment slot is repeated." % prefix)
		else:
			output[slot_id] = slot_data
		if str(slot_data.get("display_name", "")).strip_edges().is_empty():
			errors.append("%s: display_name is required." % prefix)
	if output.is_empty():
		errors.append("%s: at least one equipment slot is required." % campaign_id)
	return output


static func validate_equipment_items(
	items: Dictionary,
	slots: Dictionary,
	capabilities: Dictionary,
	used_capabilities: Dictionary,
	campaign_id: String,
	errors: Array[String],
	warnings: Array[String]
) -> int:
	var count := 0
	for item_id_value in items.keys():
		var item_id: String = str(item_id_value)
		var item_data: Dictionary = ItemCatalog.item(items, item_id)
		var kind: String = ItemCatalog.item_kind(item_data)
		var prefix: String = "%s/item/%s" % [campaign_id, item_id]
		if kind != "equipment":
			if item_data.has("equipment"):
				warnings.append("%s: non-equipment item contains an equipment record." % prefix)
			continue
		count += 1
		if ItemCatalog.stack_limit(item_data) != 1:
			errors.append("%s: equipment stack_limit must be 1." % prefix)
		var equipment_value: Variant = item_data.get("equipment", {})
		if typeof(equipment_value) != TYPE_DICTIONARY:
			errors.append("%s: equipment must be an object." % prefix)
			continue
		var equipment_data: Dictionary = equipment_value
		var slot_id: String = str(equipment_data.get("slot", ""))
		if not slots.has(slot_id):
			errors.append("%s: equipment slot '%s' is not declared by the campaign." % [prefix, slot_id])
		for field in ["attack_bonus", "defense_bonus", "max_health_bonus"]:
			if typeof(equipment_data.get(field, 0)) not in [TYPE_INT, TYPE_FLOAT]:
				errors.append("%s: %s must be numeric." % [prefix, field])
			elif int(equipment_data.get(field, 0)) < 0 or int(equipment_data.get(field, 0)) > MAX_BONUS:
				errors.append("%s: %s must be between 0 and %d." % [prefix, field, MAX_BONUS])
		if typeof(equipment_data.get("move_speed_bonus", 0.0)) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("%s: move_speed_bonus must be numeric." % prefix)
		elif float(equipment_data.get("move_speed_bonus", 0.0)) < 0.0 or float(equipment_data.get("move_speed_bonus", 0.0)) > MAX_MOVE_SPEED_BONUS:
			errors.append("%s: move_speed_bonus must be between 0 and %.0f." % [prefix, MAX_MOVE_SPEED_BONUS])
		validate_capability_references(
			equipment_data.get("capabilities", []),
			prefix + "/equipment/capabilities",
			capabilities,
			used_capabilities,
			errors
		)
	return count


static func validate_base_capabilities(
	campaign: Dictionary,
	campaign_id: String,
	capabilities: Dictionary,
	used_capabilities: Dictionary,
	errors: Array[String]
) -> void:
	if not campaign.has("base_capabilities"):
		return
	validate_capability_references(
		campaign.get("base_capabilities"),
		campaign_id + "/base_capabilities",
		capabilities,
		used_capabilities,
		errors
	)


static func validate_starting_equipment(
	campaign: Dictionary,
	campaign_id: String,
	items: Dictionary,
	slots: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if not campaign.has("starting_equipment"):
		warnings.append("%s: starting_equipment is omitted; all equipment slots begin empty." % campaign_id)
		return
	var value: Variant = campaign.get("starting_equipment")
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s: starting_equipment must be an object keyed by slot ID." % campaign_id)
		return
	var starting: Dictionary = value
	var starting_inventory: Dictionary = {}
	for entry_value in ItemCatalog.starting_inventory(campaign):
		var entry: Dictionary = entry_value
		starting_inventory[str(entry.get("item_id", ""))] = int(entry.get("quantity", 0))
	var seen_items: Dictionary = {}
	for slot_id_value in starting.keys():
		var slot_id: String = str(slot_id_value)
		var item_id: String = str(starting.get(slot_id, ""))
		var prefix: String = "%s/starting_equipment/%s" % [campaign_id, slot_id]
		if not slots.has(slot_id):
			errors.append("%s: unknown equipment slot." % prefix)
			continue
		if not items.has(item_id):
			errors.append("%s: unknown item '%s'." % [prefix, item_id])
			continue
		var item_data: Dictionary = ItemCatalog.item(items, item_id)
		if ItemCatalog.item_kind(item_data) != "equipment":
			errors.append("%s: item '%s' is not equipment." % [prefix, item_id])
		elif EquipmentCatalog.equipment_slot(item_data) != slot_id:
			errors.append("%s: item '%s' belongs in slot '%s'." % [prefix, item_id, EquipmentCatalog.equipment_slot(item_data)])
		if int(starting_inventory.get(item_id, 0)) <= 0:
			errors.append("%s: item '%s' must also appear in starting_inventory." % [prefix, item_id])
		if seen_items.has(item_id):
			errors.append("%s: item '%s' is equipped in more than one slot." % [prefix, item_id])
		seen_items[item_id] = true


static func validate_map_gates(
	map_data: Dictionary,
	capabilities: Dictionary,
	used_capabilities: Dictionary,
	errors: Array[String]
) -> int:
	var count := 0
	var map_id: String = str(map_data.get("id", "map"))
	for field in ["connections", "interactions"]:
		var value: Variant = map_data.get(field, [])
		if typeof(value) != TYPE_ARRAY:
			continue
		for record_value in value:
			if typeof(record_value) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_value
			if not record.has("required_capabilities"):
				continue
			count += 1
			var record_id: String = str(record.get("id", field.trim_suffix("s")))
			validate_capability_references(
				record.get("required_capabilities"),
				"%s/%s/%s/required_capabilities" % [map_id, field.trim_suffix("s"), record_id],
				capabilities,
				used_capabilities,
				errors
			)
			if str(record.get("blocked_dialogue", "")).strip_edges().is_empty():
				errors.append("%s/%s/%s: capability gate requires blocked_dialogue." % [map_id, field.trim_suffix("s"), record_id])
	return count


static func validate_story_capabilities(
	conversations: Dictionary,
	quests: Dictionary,
	capabilities: Dictionary,
	used_capabilities: Dictionary,
	errors: Array[String]
) -> void:
	for conversation_id_value in conversations.keys():
		var conversation_id: String = str(conversation_id_value)
		var conversation_data: Dictionary = StoryCatalog.conversation(conversations, conversation_id)
		validate_condition_capabilities(StoryCatalog.conditions(conversation_data), "conversation/%s/conditions" % conversation_id, capabilities, used_capabilities, errors)
		for node_value in StoryCatalog.nodes(conversation_data):
			if typeof(node_value) != TYPE_DICTIONARY:
				continue
			var node_data: Dictionary = node_value
			var node_id: String = str(node_data.get("id", "node"))
			validate_condition_capabilities(StoryCatalog.conditions(node_data), "conversation/%s/node/%s/conditions" % [conversation_id, node_id], capabilities, used_capabilities, errors)
			for choice_value in StoryCatalog.choices(node_data):
				if typeof(choice_value) != TYPE_DICTIONARY:
					continue
				var choice_data: Dictionary = choice_value
				validate_condition_capabilities(StoryCatalog.conditions(choice_data), "conversation/%s/node/%s/choice/%s/conditions" % [conversation_id, node_id, choice_data.get("id", "choice")], capabilities, used_capabilities, errors)
	for quest_id_value in quests.keys():
		var quest_id: String = str(quest_id_value)
		var quest_data: Dictionary = StoryCatalog.quest(quests, quest_id)
		for stage_value in StoryCatalog.stages(quest_data):
			if typeof(stage_value) != TYPE_DICTIONARY:
				continue
			var stage_data: Dictionary = stage_value
			validate_condition_capabilities(StoryCatalog.conditions(stage_data, "completion_conditions"), "quest/%s/stage/%s/completion_conditions" % [quest_id, stage_data.get("id", "stage")], capabilities, used_capabilities, errors)


static func validate_condition_capabilities(
	conditions: Array,
	prefix: String,
	capabilities: Dictionary,
	used_capabilities: Dictionary,
	errors: Array[String]
) -> void:
	for index in range(conditions.size()):
		var value: Variant = conditions[index]
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var condition: Dictionary = value
		if str(condition.get("type", "")) != "has_capability":
			continue
		validate_capability_references(
			[condition.get("capability_id", "")],
			"%s/%d" % [prefix, index],
			capabilities,
			used_capabilities,
			errors
		)


static func validate_capability_references(
	value: Variant,
	prefix: String,
	capabilities: Dictionary,
	used_capabilities: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: capability references must be an array." % prefix)
		return
	var seen: Dictionary = {}
	for capability_value in value:
		if typeof(capability_value) != TYPE_STRING:
			errors.append("%s: every capability reference must be a string ID." % prefix)
			continue
		var capability_id: String = str(capability_value).strip_edges()
		if not valid_capability_id(capability_id):
			errors.append("%s: invalid capability id '%s'." % [prefix, capability_id])
		elif seen.has(capability_id):
			errors.append("%s: capability '%s' is repeated." % [prefix, capability_id])
		elif not capabilities.has(capability_id):
			errors.append("%s: unknown capability '%s'." % [prefix, capability_id])
		else:
			seen[capability_id] = true
			used_capabilities[capability_id] = true


static func validate_profile_equipment(
	equipment_value: Variant,
	inventory_value: Variant,
	campaign: Dictionary,
	item_definitions: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(equipment_value) != TYPE_DICTIONARY:
		errors.append("Save payload equipment must be an object keyed by equipment slot.")
		return
	if typeof(inventory_value) != TYPE_DICTIONARY:
		return
	var equipment: Dictionary = equipment_value
	var inventory: Dictionary = inventory_value
	var slots: Dictionary = EquipmentCatalog.slot_index(campaign)
	if slots.is_empty():
		for slot_value in EquipmentCatalog.default_slots():
			var slot_data: Dictionary = slot_value
			slots[str(slot_data.get("id", ""))] = slot_data
	var seen_items: Dictionary = {}
	for slot_id_value in equipment.keys():
		var slot_id: String = str(slot_id_value)
		var item_id: String = str(equipment.get(slot_id, ""))
		if not slots.has(slot_id):
			errors.append("Save payload equipment references unknown slot '%s'." % slot_id)
			continue
		if InventoryModel.count(inventory, item_id) <= 0:
			errors.append("Save payload equips item '%s' without owning it." % item_id)
			continue
		var item_data: Dictionary = ItemCatalog.item(item_definitions, item_id)
		if ItemCatalog.item_kind(item_data) != "equipment":
			errors.append("Save payload item '%s' is not equipment." % item_id)
		elif EquipmentCatalog.equipment_slot(item_data) != slot_id:
			errors.append("Save payload item '%s' does not belong in slot '%s'." % [item_id, slot_id])
		if seen_items.has(item_id):
			errors.append("Save payload equips item '%s' more than once." % item_id)
		seen_items[item_id] = true


static func valid_capability_id(capability_id: String) -> bool:
	return (
		not capability_id.is_empty()
		and capability_id.length() <= EquipmentCatalog.MAX_CAPABILITY_ID_LENGTH
		and Repository.normalise_id(capability_id) == capability_id
	)


static func make_report(
	errors: Array[String],
	warnings: Array[String],
	capability_count: int,
	equipment_item_count: int,
	equipment_slot_count: int,
	capability_gate_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"capability_count": capability_count,
		"equipment_item_count": equipment_item_count,
		"equipment_slot_count": equipment_slot_count,
		"capability_gate_count": capability_gate_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
