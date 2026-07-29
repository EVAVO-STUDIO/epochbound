extends RefCounted

const ItemCatalog = preload("res://src/content/item_catalog.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")


static func initial_equipment(
	campaign: Dictionary,
	inventory: Dictionary,
	item_definitions: Dictionary
) -> Dictionary:
	var output: Dictionary = {}
	var requested: Dictionary = EquipmentCatalog.starting_equipment(campaign)
	for slot_id in EquipmentCatalog.slot_ids(campaign):
		var item_id: String = str(requested.get(slot_id, ""))
		if can_equip(item_id, slot_id, inventory, item_definitions, campaign):
			output[slot_id] = item_id
	return output


static func sanitize_equipment(
	equipped: Dictionary,
	campaign: Dictionary,
	inventory: Dictionary,
	item_definitions: Dictionary
) -> Dictionary:
	var output: Dictionary = {}
	for slot_id in EquipmentCatalog.slot_ids(campaign):
		var item_id: String = str(equipped.get(slot_id, ""))
		if can_equip(item_id, slot_id, inventory, item_definitions, campaign):
			output[slot_id] = item_id
	return output


static func can_equip(
	item_id: String,
	slot_id: String,
	inventory: Dictionary,
	item_definitions: Dictionary,
	campaign: Dictionary
) -> bool:
	if item_id.is_empty() or not EquipmentCatalog.slot_index(campaign).has(slot_id):
		return false
	if InventoryModel.count(inventory, item_id) <= 0:
		return false
	var item_data: Dictionary = ItemCatalog.item(item_definitions, item_id)
	return (
		ItemCatalog.item_kind(item_data) == "equipment"
		and EquipmentCatalog.equipment_slot(item_data) == slot_id
	)


static func equip_item(
	equipped: Dictionary,
	slot_id: String,
	item_id: String,
	inventory: Dictionary,
	item_definitions: Dictionary,
	campaign: Dictionary
) -> Dictionary:
	if item_id.is_empty():
		equipped.erase(slot_id)
		return {"ok": true, "slot_id": slot_id, "item_id": ""}
	if not can_equip(item_id, slot_id, inventory, item_definitions, campaign):
		return {"ok": false, "slot_id": slot_id, "item_id": item_id}
	equipped[slot_id] = item_id
	return {"ok": true, "slot_id": slot_id, "item_id": item_id}


static func equipment_candidates(
	slot_id: String,
	inventory: Dictionary,
	item_definitions: Dictionary
) -> PackedStringArray:
	var ids: Array[String] = []
	for item_id in EquipmentCatalog.equipment_item_ids(item_definitions):
		var item_data: Dictionary = ItemCatalog.item(item_definitions, item_id)
		if (
			EquipmentCatalog.equipment_slot(item_data) == slot_id
			and InventoryModel.count(inventory, item_id) > 0
		):
			ids.append(item_id)
	return PackedStringArray(ids)


static func cycle_slot(
	equipped: Dictionary,
	slot_id: String,
	inventory: Dictionary,
	item_definitions: Dictionary,
	campaign: Dictionary
) -> Dictionary:
	var candidates: Array[String] = [""]
	for item_id in equipment_candidates(slot_id, inventory, item_definitions):
		candidates.append(item_id)
	var current: String = str(equipped.get(slot_id, ""))
	var index: int = candidates.find(current)
	var next_item: String = candidates[(index + 1) % candidates.size()] if index >= 0 else candidates[0]
	return equip_item(equipped, slot_id, next_item, inventory, item_definitions, campaign)


static func modifier_total(
	equipped: Dictionary,
	item_definitions: Dictionary,
	field: String
) -> float:
	var total := 0.0
	for item_id_value in equipped.values():
		var item_id: String = str(item_id_value)
		var item_data: Dictionary = ItemCatalog.item(item_definitions, item_id)
		total += EquipmentCatalog.modifier(item_data, field)
	return total


static func active_capabilities(
	campaign: Dictionary,
	equipped: Dictionary,
	item_definitions: Dictionary
) -> PackedStringArray:
	var output := EquipmentCatalog.base_capabilities(campaign)
	for item_id_value in equipped.values():
		var item_id: String = str(item_id_value)
		var item_data: Dictionary = ItemCatalog.item(item_definitions, item_id)
		for capability_id in EquipmentCatalog.granted_capabilities(item_data):
			if not output.has(capability_id):
				output.append(capability_id)
	output.sort()
	return output


static func requirements_met(record: Dictionary, capabilities: PackedStringArray) -> bool:
	for capability_id in EquipmentCatalog.required_capabilities(record):
		if not capabilities.has(capability_id):
			return false
	return true


static func missing_capabilities(record: Dictionary, capabilities: PackedStringArray) -> PackedStringArray:
	var output := PackedStringArray()
	for capability_id in EquipmentCatalog.required_capabilities(record):
		if not capabilities.has(capability_id):
			output.append(capability_id)
	return output


static func equipment_summary(
	equipped: Dictionary,
	campaign: Dictionary,
	item_definitions: Dictionary
) -> PackedStringArray:
	var output := PackedStringArray()
	for slot_id in EquipmentCatalog.slot_ids(campaign):
		var item_id: String = str(equipped.get(slot_id, ""))
		var item_name := "Empty"
		if not item_id.is_empty():
			item_name = ItemCatalog.item_name(ItemCatalog.item(item_definitions, item_id), item_id)
		output.append("%s: %s" % [EquipmentCatalog.slot_name(campaign, slot_id), item_name])
	return output
