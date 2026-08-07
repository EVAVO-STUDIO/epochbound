@tool
extends RefCounted

const OUTCOME_CATEGORIES := [
	"route",
	"threat",
	"information",
	"relationship",
	"resource"
]
const ROUTE_COLLECTIONS := [
	"terrain_cells",
	"collision_cells",
	"navigation_cells",
	"entry_points",
	"connections",
	"recovery_anchors"
]


static func audit(
	maps: Dictionary,
	objects: Dictionary,
	findings: Array[Dictionary]
) -> Dictionary:
	var metrics := {
		"multi_era_map_count": 0,
		"meaningful_shift_map_count": 0,
		"temporal_outcome_count": 0,
		"temporal_route_count": 0,
		"temporal_threat_count": 0,
		"temporal_information_count": 0,
		"temporal_relationship_count": 0,
		"temporal_resource_count": 0
	}
	for map_id in sorted_dictionary_keys(maps):
		var map_data: Dictionary = maps.get(map_id, {})
		var era_ids := declared_era_ids(map_data)
		if era_ids.size() < 2:
			continue
		metrics["multi_era_map_count"] = int(metrics["multi_era_map_count"]) + 1
		var evidence := outcomes_for_map(map_id, map_data, era_ids, objects)
		var outcome_count := 0
		for category in OUTCOME_CATEGORIES:
			var bucket_value: Variant = evidence.get(category, {})
			var bucket: Dictionary = bucket_value if typeof(bucket_value) == TYPE_DICTIONARY else {}
			var category_count := bucket.size()
			outcome_count += category_count
			metrics["temporal_%s_count" % category] = (
				int(metrics.get("temporal_%s_count" % category, 0)) + category_count
			)
		metrics["temporal_outcome_count"] = int(metrics["temporal_outcome_count"]) + outcome_count
		if outcome_count > 0:
			metrics["meaningful_shift_map_count"] = int(metrics["meaningful_shift_map_count"]) + 1
			continue
		findings.append({
			"severity": "warning",
			"code": "temporal.palette_only",
			"message": (
				"Map '%s' defines multiple eras but no authored route, threat, information, relationship or resource consequence."
				% map_id
			),
			"context": map_id
		})
	return metrics


static func outcomes_for_map(
	map_id: String,
	map_data: Dictionary,
	era_ids: PackedStringArray,
	objects: Dictionary
) -> Dictionary:
	var evidence := empty_evidence()
	collect_route_evidence(map_id, map_data, era_ids, evidence)
	collect_interaction_evidence(map_id, map_data, era_ids, evidence)
	collect_companion_evidence(map_id, map_data, era_ids, evidence)
	collect_object_evidence(map_id, map_data, era_ids, objects, evidence)
	collect_encounter_evidence(map_id, map_data, era_ids, evidence)
	return evidence


static func collect_route_evidence(
	map_id: String,
	map_data: Dictionary,
	era_ids: PackedStringArray,
	evidence: Dictionary
) -> void:
	for collection_name in ROUTE_COLLECTIONS:
		var records_value: Variant = map_data.get(collection_name, [])
		if typeof(records_value) != TYPE_ARRAY:
			continue
		var index := 0
		for record_value in records_value as Array:
			if typeof(record_value) != TYPE_DICTIONARY:
				index += 1
				continue
			var record: Dictionary = record_value
			var record_id := str(record.get("id", "%d" % index))
			if is_era_scoped(record, era_ids):
				mark_evidence(evidence, "route", "%s:%s:%s" % [map_id, collection_name, record_id])
			if collection_name == "connections":
				var target_era := str(record.get("target_era", ""))
				if not target_era.is_empty() and target_era != "same":
					mark_evidence(evidence, "route", "%s:connection_target:%s" % [map_id, record_id])
			index += 1


static func collect_interaction_evidence(
	map_id: String,
	map_data: Dictionary,
	era_ids: PackedStringArray,
	evidence: Dictionary
) -> void:
	var interactions_value: Variant = map_data.get("interactions", [])
	if typeof(interactions_value) != TYPE_ARRAY:
		return
	var index := 0
	for interaction_value in interactions_value as Array:
		if typeof(interaction_value) != TYPE_DICTIONARY:
			index += 1
			continue
		var interaction: Dictionary = interaction_value
		var interaction_id := str(interaction.get("id", "%d" % index))
		if is_era_scoped(interaction, era_ids):
			mark_evidence(evidence, "information", "%s:interaction_scope:%s" % [map_id, interaction_id])
		if dialogue_varies(interaction.get("dialogue", null), era_ids):
			mark_evidence(evidence, "information", "%s:interaction_dialogue:%s" % [map_id, interaction_id])
		index += 1


static func collect_companion_evidence(
	map_id: String,
	map_data: Dictionary,
	era_ids: PackedStringArray,
	evidence: Dictionary
) -> void:
	var cues_value: Variant = map_data.get("companion_cues", [])
	if typeof(cues_value) != TYPE_ARRAY:
		return
	var index := 0
	for cue_value in cues_value as Array:
		if typeof(cue_value) != TYPE_DICTIONARY:
			index += 1
			continue
		var cue: Dictionary = cue_value
		var cue_id := str(cue.get("id", "%d" % index))
		if not is_era_scoped(cue, era_ids):
			index += 1
			continue
		mark_evidence(evidence, "information", "%s:companion_information:%s" % [map_id, cue_id])
		mark_evidence(evidence, "relationship", "%s:companion_relationship:%s" % [map_id, cue_id])
		if has_resource_payload(cue):
			mark_evidence(evidence, "resource", "%s:companion_resource:%s" % [map_id, cue_id])
		index += 1


static func collect_object_evidence(
	map_id: String,
	map_data: Dictionary,
	era_ids: PackedStringArray,
	objects: Dictionary,
	evidence: Dictionary
) -> void:
	var placements_value: Variant = map_data.get("object_placements", [])
	if typeof(placements_value) != TYPE_ARRAY:
		return
	var index := 0
	for placement_value in placements_value as Array:
		if typeof(placement_value) != TYPE_DICTIONARY:
			index += 1
			continue
		var placement: Dictionary = placement_value
		var placement_id := str(placement.get("id", "%d" % index))
		var object_id := str(placement.get("object_id", ""))
		var object_value: Variant = objects.get(object_id, {})
		var object_definition: Dictionary = (
			object_value if typeof(object_value) == TYPE_DICTIONARY else {}
		)
		var kind := str(object_definition.get("kind", ""))
		if is_era_scoped(placement, era_ids):
			match kind:
				"enemy":
					mark_evidence(evidence, "threat", "%s:enemy:%s" % [map_id, placement_id])
				"npc":
					mark_evidence(evidence, "relationship", "%s:npc:%s" % [map_id, placement_id])
					if not str(object_definition.get("merchant_id", "")).is_empty():
						mark_evidence(evidence, "resource", "%s:merchant:%s" % [map_id, placement_id])
				"pickup":
					mark_evidence(evidence, "resource", "%s:pickup:%s" % [map_id, placement_id])
				_:
					if has_resource_payload(object_definition):
						mark_evidence(evidence, "resource", "%s:object_resource:%s" % [map_id, placement_id])
		if dialogue_varies(object_definition.get("dialogue", null), era_ids):
			mark_evidence(evidence, "information", "%s:object_dialogue:%s" % [map_id, placement_id])
		collect_boss_phase_evidence(map_id, placement_id, object_definition, era_ids, evidence)
		index += 1


static func collect_boss_phase_evidence(
	map_id: String,
	placement_id: String,
	object_definition: Dictionary,
	era_ids: PackedStringArray,
	evidence: Dictionary
) -> void:
	var boss_value: Variant = object_definition.get("boss", {})
	if typeof(boss_value) != TYPE_DICTIONARY:
		return
	var phases_value: Variant = (boss_value as Dictionary).get("phases", [])
	if typeof(phases_value) != TYPE_ARRAY:
		return
	var index := 0
	for phase_value in phases_value as Array:
		if typeof(phase_value) != TYPE_DICTIONARY:
			index += 1
			continue
		var phase: Dictionary = phase_value
		if is_era_scoped(phase, era_ids):
			var phase_id := str(phase.get("id", "%d" % index))
			mark_evidence(evidence, "threat", "%s:boss_phase:%s:%s" % [map_id, placement_id, phase_id])
		index += 1


static func collect_encounter_evidence(
	map_id: String,
	map_data: Dictionary,
	era_ids: PackedStringArray,
	evidence: Dictionary
) -> void:
	var zones_value: Variant = map_data.get("encounter_zones", [])
	if typeof(zones_value) != TYPE_ARRAY:
		return
	var index := 0
	for zone_value in zones_value as Array:
		if typeof(zone_value) != TYPE_DICTIONARY:
			index += 1
			continue
		var zone: Dictionary = zone_value
		if is_era_scoped(zone, era_ids):
			var zone_id := str(zone.get("id", "%d" % index))
			mark_evidence(evidence, "threat", "%s:encounter:%s" % [map_id, zone_id])
		index += 1


static func declared_era_ids(map_data: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	var eras_value: Variant = map_data.get("eras", [])
	if typeof(eras_value) != TYPE_ARRAY:
		return output
	for era_value in eras_value as Array:
		if typeof(era_value) != TYPE_DICTIONARY:
			continue
		var era_id := str((era_value as Dictionary).get("id", ""))
		if not era_id.is_empty() and not output.has(era_id):
			output.append(era_id)
	output.sort()
	return output


static func is_era_scoped(record: Dictionary, era_ids: PackedStringArray) -> bool:
	var available_value: Variant = record.get("available_eras", [])
	if typeof(available_value) != TYPE_ARRAY:
		return false
	for era_value in available_value as Array:
		if era_ids.has(str(era_value)):
			return true
	return false


static func dialogue_varies(value: Variant, era_ids: PackedStringArray) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var dialogue: Dictionary = value
	var distinct: Dictionary = {}
	for era_id in era_ids:
		var text := str(dialogue.get(era_id, dialogue.get("default", ""))).strip_edges()
		if not text.is_empty():
			distinct[text] = true
	return distinct.size() >= 2


static func has_resource_payload(record: Dictionary) -> bool:
	for key in ["item_grants", "reward_items", "unlock_recipes"]:
		var value: Variant = record.get(key, [])
		if typeof(value) == TYPE_ARRAY and not (value as Array).is_empty():
			return true
	return int(record.get("pickup_value", 0)) > 0


static func empty_evidence() -> Dictionary:
	return {
		"route": {},
		"threat": {},
		"information": {},
		"relationship": {},
		"resource": {}
	}


static func mark_evidence(evidence: Dictionary, category: String, key: String) -> void:
	var bucket_value: Variant = evidence.get(category, {})
	var bucket: Dictionary = bucket_value if typeof(bucket_value) == TYPE_DICTIONARY else {}
	bucket[key] = true
	evidence[category] = bucket


static func sorted_dictionary_keys(value: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in value.keys():
		output.append(str(key_value))
	output.sort()
	return output
