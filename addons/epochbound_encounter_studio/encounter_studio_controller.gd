@tool
extends "res://addons/epochbound_encounter_studio/encounter_studio.gd"

const ControllerRepository = preload("res://src/content/campaign_repository.gd")


func _on_era_selected(index: int) -> void:
	super._on_era_selected(index)
	if not selected_definition_id.is_empty():
		populate_definition_inspector()


func populate_definition_inspector() -> void:
	super.populate_definition_inspector()
	var definition_data := ObjectCatalog.definition(definitions, selected_definition_id)
	if definition_data.is_empty():
		return
	var dialogue: Variant = definition_data.get("dialogue", "")
	if typeof(dialogue) == TYPE_DICTIONARY:
		var by_era: Dictionary = dialogue
		definition_dialogue.text = String(
			by_era.get(selected_era_id(), by_era.get("default", ""))
		)


func apply_definition() -> void:
	if selected_definition_id.is_empty():
		return
	var objects: Array = active_catalog.get("objects", [])
	var found := false
	for index in range(objects.size()):
		if typeof(objects[index]) != TYPE_DICTIONARY:
			continue
		var definition_data: Dictionary = objects[index]
		if String(definition_data.get("id", "")) != selected_definition_id:
			continue
		var original_dialogue: Variant = definition_data.get("dialogue", "")
		definition_data["display_name"] = definition_name_edit.text.strip_edges()
		definition_data["kind"] = definition_kind_selector.get_item_text(definition_kind_selector.selected)
		definition_data["appearance"] = {
			"shape": definition_shape_selector.get_item_text(definition_shape_selector.selected),
			"color": definition_color_edit.text.strip_edges(),
			"accent": definition_accent_edit.text.strip_edges()
		}
		definition_data["solid"] = definition_solid.button_pressed
		definition_data["collision_radius"] = definition_collision_radius.value
		definition_data["interaction_radius"] = definition_interaction_radius.value
		for field in [
			"max_health", "move_speed", "awareness_radius", "attack_radius",
			"attack_damage", "attack_cooldown", "reward", "pickup_value",
			"pickup_label", "dialogue"
		]:
			definition_data.erase(field)
		var kind := String(definition_data.get("kind", "prop"))
		if kind in ["prop", "npc"]:
			if typeof(original_dialogue) == TYPE_DICTIONARY:
				var by_era: Dictionary = Dictionary(original_dialogue).duplicate(true)
				var era_key := selected_era_id()
				if era_key.is_empty():
					era_key = "default"
				by_era[era_key] = definition_dialogue.text
				definition_data["dialogue"] = by_era
			else:
				definition_data["dialogue"] = definition_dialogue.text
		elif kind == "enemy":
			definition_data["max_health"] = int(definition_max_health.value)
			definition_data["move_speed"] = definition_move_speed.value
			definition_data["awareness_radius"] = definition_awareness_radius.value
			definition_data["attack_radius"] = definition_attack_radius.value
			definition_data["attack_damage"] = int(definition_attack_damage.value)
			definition_data["attack_cooldown"] = definition_attack_cooldown.value
			definition_data["reward"] = int(definition_value.value)
		elif kind == "pickup":
			definition_data["pickup_value"] = maxi(1, int(definition_value.value))
			definition_data["pickup_label"] = definition_pickup_label.text.strip_edges()
		objects[index] = definition_data
		found = true
		break
	if not found:
		set_status("The selected definition is not in the editable primary catalog.", true)
		return
	active_catalog["objects"] = objects
	rebuild_definitions_from_files()
	if save_catalog():
		refresh_definition_list(selected_definition_id)
		set_status("Updated object type '%s'." % selected_definition_id, false)
