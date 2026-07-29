@tool
extends "res://addons/epochbound_campaign_studio/campaign_studio.gd"

const SafeRepository = preload("res://src/content/campaign_repository.gd")
const SafeMapModel = preload("res://src/content/map_model.gd")
const FullValidator = preload("res://src/content/epochbound_validator.gd")

# Validate connection references before mutating the selected record. This keeps
# an invalid inspector edit from changing the in-memory map even when saving is
# correctly blocked by the campaign validator.
func apply_selected_marker() -> void:
	var records := records_for_kind(selected_kind)
	if selected_index < 0 or selected_index >= records.size():
		return
	var requested_id := SafeRepository.normalise_id(marker_id_edit.text)
	if requested_id.is_empty():
		set_status("Selection ID cannot be empty.", true)
		return
	for index in range(records.size()):
		if index == selected_index or typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var other: Dictionary = records[index]
		if String(other.get("id", "")) == requested_id:
			set_status("ID '%s' is already used in this collection." % requested_id, true)
			return

	var connection_target_map := ""
	var connection_target_entry := ""
	var connection_target_era := "same"
	if selected_kind == "connection":
		connection_target_map = selected_target_map_id()
		connection_target_entry = SafeRepository.normalise_id(target_entry_edit.text)
		connection_target_era = target_era_edit.text.strip_edges().to_lower()
		if connection_target_era.is_empty():
			connection_target_era = "same"
		if connection_target_map.is_empty():
			set_status("A connection requires a target map.", true)
			return
		if connection_target_entry.is_empty():
			set_status("A connection requires a target entry ID.", true)
			return
		var target_map := resolve_target_map(connection_target_map)
		if target_map.is_empty():
			set_status("Target map '%s' could not be loaded." % connection_target_map, true)
			return
		if not map_contains_entry(target_map, connection_target_entry):
			set_status(
				"Target entry '%s' does not exist in map '%s'." % [connection_target_entry, connection_target_map],
				true
			)
			return
		if connection_target_era != "same" and not map_contains_era(target_map, connection_target_era):
			set_status(
				"Target era '%s' does not exist in map '%s'." % [connection_target_era, connection_target_map],
				true
			)
			return

	begin_change()
	var record: Dictionary = records[selected_index]
	record["id"] = requested_id
	var position := Vector2(position_x.value, position_y.value)
	if selected_kind == "entry":
		record["player"] = SafeRepository.vector_to_data(position)
		record["companion"] = SafeRepository.vector_to_data(Vector2(secondary_x.value, secondary_y.value))
	else:
		record["position"] = SafeRepository.vector_to_data(position)
	record["available_eras"] = SafeMapModel.scope_for_era(
		selected_era_id(),
		marker_era_only.button_pressed
	)
	if selected_kind in ["interaction", "connection"]:
		record["radius"] = marker_radius.value
	if selected_kind == "interaction":
		var existing: Variant = record.get("dialogue", {})
		var by_era: Dictionary = {}
		if typeof(existing) == TYPE_DICTIONARY:
			by_era = Dictionary(existing).duplicate(true)
		else:
			by_era["default"] = String(existing)
		var key := selected_era_id()
		if key.is_empty():
			key = "default"
		by_era[key] = marker_dialogue.text
		record["dialogue"] = by_era
	elif selected_kind == "connection":
		record["target_map"] = connection_target_map
		record["target_entry"] = connection_target_entry
		record["target_era"] = connection_target_era
		record["trigger"] = trigger_selector.get_item_text(trigger_selector.selected)
	records[selected_index] = record
	active_map[collection_for_kind(selected_kind)] = records
	map_canvas.set_selected_marker(selected_kind, requested_id)
	if commit_change("Update %s" % selected_kind):
		if save_active_map():
			set_status("Updated '%s'." % requested_id, false)


func validate_all_campaigns() -> void:
	var report := FullValidator.validate_all()
	set_status(format_full_report(report), not report.get("ok", false))


func format_full_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(
		"%d campaign(s), %d map(s), %d object definition(s), %d placement(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 0),
			report.get("map_count", 0),
			report.get("definition_count", 0),
			report.get("placement_count", 0),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
	for warning in report.get("warnings", []):
		lines.append("WARNING: %s" % warning)
	for error in report.get("errors", []):
		lines.append("ERROR: %s" % error)
	return "\n".join(lines)


func resolve_target_map(map_id: String) -> Dictionary:
	if String(active_map.get("id", "")) == map_id:
		return active_map
	var path := SafeRepository.find_exact_map_path(active_campaign_path, active_campaign, map_id)
	if path.is_empty():
		return {}
	var result := SafeRepository.read_json(path)
	return result.get("data", {}) if result.get("ok", false) else {}


func map_contains_entry(target_map: Dictionary, entry_id: String) -> bool:
	for value in target_map.get("entry_points", []):
		if typeof(value) == TYPE_DICTIONARY:
			var entry: Dictionary = value
			if String(entry.get("id", "")) == entry_id:
				return true
	return false


func map_contains_era(target_map: Dictionary, era_id: String) -> bool:
	for value in target_map.get("eras", []):
		if typeof(value) == TYPE_DICTIONARY:
			var era: Dictionary = value
			if String(era.get("id", "")) == era_id:
				return true
	return false
