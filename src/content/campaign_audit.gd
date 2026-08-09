@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const ReleaseValidator = preload("res://src/content/package_release_validator.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const SupplyRegionCatalog = preload("res://src/content/supply_region_catalog.gd")
const ProgressionSourceAudit = preload("res://src/content/progression_source_audit.gd")
const ProgressionAffordabilityAudit = preload("res://src/content/progression_affordability_audit.gd")
const TemporalShiftAudit = preload("res://src/content/temporal_shift_audit.gd")
const EconomyBalanceSimulation = preload("res://src/content/economy_balance_simulation.gd")

const PROBE_COUNT := 10
const SEVERITY_RANK := {"blocker": 0, "warning": 1, "info": 2}

static func audit_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var reports: Array[Dictionary] = []
	var blocker_count := 0
	var warning_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		var report := audit_campaign_path(str(entry.get("path", "")))
		reports.append(report)
		blocker_count += int(report.get("blocker_count", 0))
		warning_count += int(report.get("warning_count", 0))
	return {
		"ok": blocker_count == 0,
		"campaign_count": reports.size(),
		"blocker_count": blocker_count,
		"warning_count": warning_count,
		"reports": reports
	}


static func audit_campaign_path(campaign_path: String) -> Dictionary:
	var findings: Array[Dictionary] = []
	var validation: Dictionary = ReleaseValidator.validate_campaign_path(campaign_path)
	if not bool(validation.get("ok", false)):
		for error_value in validation.get("errors", []):
			add_finding(findings, "blocker", "content.invalid", str(error_value), campaign_path)
	var result := Repository.read_json(campaign_path)
	if not bool(result.get("ok", false)):
		for error_value in result.get("errors", []):
			add_finding(findings, "blocker", "campaign.unreadable", str(error_value), campaign_path)
		return build_report(campaign_path.get_file().get_basename(), findings, {})
	var campaign: Dictionary = result.get("data", {})
	var maps := load_maps(campaign_path, campaign, findings)

	var item_result: Dictionary = ItemCatalog.load_item_catalogs(campaign_path, campaign)
	for error_value in item_result.get("errors", []):
		add_finding(findings, "blocker", "items.unreadable", str(error_value), campaign_path)
	var recipe_result: Dictionary = ItemCatalog.load_recipe_catalogs(campaign_path, campaign)
	for error_value in recipe_result.get("errors", []):
		add_finding(findings, "blocker", "recipes.unreadable", str(error_value), campaign_path)
	var story_result: Dictionary = StoryCatalog.load_catalogs(campaign_path, campaign)
	for error_value in story_result.get("errors", []):
		add_finding(findings, "blocker", "story.unreadable", str(error_value), campaign_path)
	var economy_result: Dictionary = EconomyCatalog.load_catalogs(campaign_path, campaign)
	for error_value in economy_result.get("errors", []):
		add_finding(findings, "blocker", "economy.unreadable", str(error_value), campaign_path)
	var object_result: Dictionary = ObjectCatalog.load_catalogs(campaign_path, campaign)
	for error_value in object_result.get("errors", []):
		add_finding(findings, "blocker", "objects.unreadable", str(error_value), campaign_path)
	var supply_result: Dictionary = SupplyRegionCatalog.load_catalogs(campaign_path, campaign)
	for error_value in supply_result.get("errors", []):
		add_finding(findings, "blocker", "supply.unreadable", str(error_value), campaign_path)

	var loaded := audit_loaded(
		campaign,
		maps,
		item_result.get("definitions", {}),
		{"quests": story_result.get("quests", {}), "conversations": story_result.get("conversations", {})},
		{
			"currencies": economy_result.get("currencies", {}),
			"merchants": economy_result.get("merchants", {}),
			"supply_regions": supply_result.get("definitions", {})
		},
		recipe_result.get("definitions", {}),
		object_result.get("definitions", {})
	)
	for finding_value in loaded.get("findings", []):
		if typeof(finding_value) == TYPE_DICTIONARY:
			findings.append((finding_value as Dictionary).duplicate(true))
	return build_report(str(campaign.get("id", campaign_path)), findings, loaded.get("metrics", {}))


static func audit_loaded(
	campaign: Dictionary,
	maps: Dictionary,
	items: Dictionary,
	story: Dictionary,
	economy: Dictionary,
	recipes: Dictionary = {},
	objects: Dictionary = {}
) -> Dictionary:
	var findings: Array[Dictionary] = []
	var metrics: Dictionary = {
		"probe_count": PROBE_COUNT,
		"map_count": maps.size(),
		"reachable_map_count": 0,
		"required_capability_count": 0,
		"optional_capability_count": 0,
		"quest_count": 0,
		"restorative_source_count": 0,
		"multi_era_map_count": 0,
		"meaningful_shift_map_count": 0,
		"temporal_outcome_count": 0,
		"temporal_route_count": 0,
		"temporal_threat_count": 0,
		"temporal_information_count": 0,
		"temporal_relationship_count": 0,
		"temporal_resource_count": 0,
		"progression_item_count": 0,
		"progression_capability_count": 0,
		"progression_source_risk_count": 0,
		"merchant_only_progression_count": 0,
		"affordability_risk_count": 0,
		"economy_balance_scenario_count": 0,
		"economy_balance_risk_count": 0,
		"economy_starting_wallet_count": 0,
		"economy_starting_choice_count": 0,
		"economy_recovery_safe_choice_count": 0,
		"economy_optional_dead_end_count": 0,
		"economy_preparation_category_count": 0,
		"economy_arbitrage_route_count": 0,
		"economy_repeatable_arbitrage_count": 0,
		"economy_renewable_recovery_units": 0,
		"economy_renewable_ammo_units": 0,
		"economy_finite_progression_stock_count": 0
	}
	var graph := graph_from_maps(maps)
	var reachable := probe_map_reachability(campaign, maps, graph, findings)
	metrics["reachable_map_count"] = reachable.size()
	probe_return_routes(campaign, maps, graph, findings)
	var optional_capabilities: Dictionary = {}
	var required_capabilities := probe_capability_sources(
		campaign,
		maps,
		items,
		story,
		economy,
		optional_capabilities,
		findings
	)
	metrics["required_capability_count"] = required_capabilities.size()
	metrics["optional_capability_count"] = optional_capabilities.size()
	metrics["restorative_source_count"] = probe_economy_recovery(campaign, items, economy, findings)
	metrics["quest_count"] = probe_quest_startability(campaign, story, findings)
	probe_save_policy(campaign, findings)

	var temporal_metrics := TemporalShiftAudit.audit(maps, objects, findings)
	for metric_name in [
		"multi_era_map_count",
		"meaningful_shift_map_count",
		"temporal_outcome_count",
		"temporal_route_count",
		"temporal_threat_count",
		"temporal_information_count",
		"temporal_relationship_count",
		"temporal_resource_count"
	]:
		metrics[metric_name] = int(temporal_metrics.get(metric_name, 0))

	var source_finding_start := findings.size()
	var progression := ProgressionSourceAudit.audit(
		campaign,
		maps,
		items,
		recipes,
		story,
		economy,
		objects,
		required_capabilities,
		findings
	)
	metrics["progression_item_count"] = int(progression.get("progression_item_count", 0))
	metrics["progression_capability_count"] = int(progression.get("progression_capability_count", 0))
	metrics["progression_source_risk_count"] = findings.size() - source_finding_start

	var affordability_finding_start := findings.size()
	metrics["merchant_only_progression_count"] = ProgressionAffordabilityAudit.audit(
		economy,
		progression,
		findings
	)
	metrics["affordability_risk_count"] = findings.size() - affordability_finding_start

	var economy_metrics: Dictionary = EconomyBalanceSimulation.audit(
		campaign,
		items,
		economy,
		findings
	)
	for metric_name_value in economy_metrics.keys():
		var metric_name: String = str(metric_name_value)
		metrics[metric_name] = economy_metrics.get(metric_name_value)
	return build_report(str(campaign.get("id", "campaign")), findings, metrics)


static func load_maps(campaign_path: String, campaign: Dictionary, findings: Array[Dictionary]) -> Dictionary:
	var maps: Dictionary = {}
	var map_files_value: Variant = campaign.get("map_files", [])
	if typeof(map_files_value) != TYPE_ARRAY:
		add_finding(findings, "blocker", "maps.invalid_list", "map_files must be an array.", campaign_path)
		return maps
	for relative_value in map_files_value:
		var relative_path := str(relative_value)
		var path := campaign_path.get_base_dir().path_join(relative_path)
		var result := Repository.read_json(path)
		if not bool(result.get("ok", false)):
			for error_value in result.get("errors", []):
				add_finding(findings, "blocker", "map.unreadable", str(error_value), relative_path)
			continue
		var map_data: Dictionary = result.get("data", {})
		var map_id := str(map_data.get("id", ""))
		if not map_id.is_empty():
			maps[map_id] = map_data
	return maps


static func graph_from_maps(maps: Dictionary) -> Dictionary:
	var graph: Dictionary = {}
	for map_id_value in maps.keys():
		graph[str(map_id_value)] = []
	for map_id_value in maps.keys():
		var map_id := str(map_id_value)
		var map_data: Dictionary = maps.get(map_id, {})
		var neighbors: Array = []
		for connection_value in map_data.get("connections", []):
			if typeof(connection_value) != TYPE_DICTIONARY:
				continue
			var target := str((connection_value as Dictionary).get("target_map", ""))
			if maps.has(target) and not neighbors.has(target):
				neighbors.append(target)
		graph[map_id] = neighbors
	return graph


static func probe_map_reachability(
	campaign: Dictionary,
	maps: Dictionary,
	graph: Dictionary,
	findings: Array[Dictionary]
) -> Dictionary:
	var start_map := str(campaign.get("start_map", ""))
	if start_map.is_empty() or not maps.has(start_map):
		add_finding(findings, "blocker", "map.missing_start", "The authored start map does not resolve.", start_map)
		return {}
	var reachable := reachable_from(graph, start_map)
	for map_id_value in maps.keys():
		var map_id := str(map_id_value)
		if not reachable.has(map_id):
			add_finding(findings, "blocker", "map.unreachable", "Map '%s' has no structural route from start map '%s'." % [map_id, start_map], map_id)
	return reachable


static func probe_return_routes(
	campaign: Dictionary,
	maps: Dictionary,
	graph: Dictionary,
	findings: Array[Dictionary]
) -> void:
	var start_map := str(campaign.get("start_map", ""))
	for map_id_value in maps.keys():
		var map_id := str(map_id_value)
		if map_id == start_map:
			continue
		var map_data: Dictionary = maps.get(map_id, {})
		var connections_value: Variant = map_data.get("connections", [])
		var connections: Array = connections_value as Array if typeof(connections_value) == TYPE_ARRAY else []
		if connections.is_empty():
			add_finding(findings, "blocker", "travel.no_exit", "Map '%s' has no authored exit." % map_id, map_id)
			continue
		if not can_reach(graph, map_id, start_map):
			add_finding(findings, "warning", "travel.no_return_path", "Map '%s' cannot structurally return to the campaign start." % map_id, map_id)
		var has_ungated_exit := false
		for connection_value in connections:
			if typeof(connection_value) != TYPE_DICTIONARY:
				continue
			var connection: Dictionary = connection_value
			var required_value: Variant = connection.get("required_capabilities", [])
			var conditions_value: Variant = connection.get("conditions", [])
			var required_count := (required_value as Array).size() if typeof(required_value) == TYPE_ARRAY else 0
			var condition_count := (conditions_value as Array).size() if typeof(conditions_value) == TYPE_ARRAY else 0
			if required_count == 0 and condition_count == 0:
				has_ungated_exit = true
				break
		if not has_ungated_exit:
			add_finding(findings, "warning", "travel.all_exits_gated", "Every exit from '%s' is capability- or condition-gated." % map_id, map_id)


static func probe_capability_sources(
	campaign: Dictionary,
	maps: Dictionary,
	items: Dictionary,
	story: Dictionary,
	economy: Dictionary,
	optional: Dictionary,
	findings: Array[Dictionary]
) -> Dictionary:
	var required: Dictionary = {}
	collect_map_capability_requirements(maps, required, optional)
	collect_required_capabilities(story, required)
	collect_required_capabilities(economy, required)
	for capability_id in required.keys():
		optional.erase(capability_id)
	var all_sources: Dictionary = {}
	var starting_sources: Dictionary = {}
	for capability_value in campaign.get("base_capabilities", []):
		var capability_id := str(capability_value)
		all_sources[capability_id] = true
		starting_sources[capability_id] = true
	for item_id_value in items.keys():
		var item: Dictionary = items.get(str(item_id_value), {})
		var equipment_value: Variant = item.get("equipment", {})
		if typeof(equipment_value) != TYPE_DICTIONARY:
			continue
		for capability_value in (equipment_value as Dictionary).get("capabilities", []):
			all_sources[str(capability_value)] = true
	var starting_equipment_value: Variant = campaign.get("starting_equipment", {})
	if typeof(starting_equipment_value) == TYPE_DICTIONARY:
		for item_id_value in (starting_equipment_value as Dictionary).values():
			var item: Dictionary = items.get(str(item_id_value), {})
			var equipment_value: Variant = item.get("equipment", {})
			if typeof(equipment_value) != TYPE_DICTIONARY:
				continue
			for capability_value in (equipment_value as Dictionary).get("capabilities", []):
				starting_sources[str(capability_value)] = true
				all_sources[str(capability_value)] = true
	var ids := PackedStringArray()
	for capability_id_value in required.keys():
		ids.append(str(capability_id_value))
	ids.sort()
	for capability_id in ids:
		if not all_sources.has(capability_id):
			add_finding(findings, "blocker", "capability.no_source", "Required capability '%s' is never granted by campaign base abilities or equipment." % capability_id, capability_id)
		elif not starting_sources.has(capability_id):
			add_finding(findings, "warning", "capability.late_source", "Required capability '%s' is available only after acquiring alternate equipment." % capability_id, capability_id)
	return required


# Connections, story and economy can block the authored journey. Map
# interactions are exploratory unless an author explicitly marks one as
# progression_required, so optional lore does not inflate softlock demand.
static func collect_map_capability_requirements(
	maps: Dictionary,
	required: Dictionary,
	optional: Dictionary
) -> void:
	for map_id in sorted_dictionary_keys(maps):
		var map_data: Dictionary = maps.get(map_id, {})
		var progression_map := map_data.duplicate(true)
		progression_map.erase("interactions")
		collect_required_capabilities(progression_map, required)
		var interactions_value: Variant = map_data.get("interactions", [])
		if typeof(interactions_value) != TYPE_ARRAY:
			continue
		for interaction_value in interactions_value as Array:
			if typeof(interaction_value) != TYPE_DICTIONARY:
				continue
			var interaction: Dictionary = interaction_value
			if bool(interaction.get("progression_required", false)):
				collect_required_capabilities(interaction, required)
			else:
				collect_required_capabilities(interaction, optional)


static func collect_required_capabilities(value: Variant, output: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		if str(data.get("type", "")) == "has_capability":
			var capability_id := str(data.get("capability_id", ""))
			if not capability_id.is_empty():
				output[capability_id] = true
		var required_value: Variant = data.get("required_capabilities", [])
		if typeof(required_value) == TYPE_ARRAY:
			for capability_value in required_value:
				var capability_id := str(capability_value)
				if not capability_id.is_empty():
					output[capability_id] = true
		for child_value in data.values():
			collect_required_capabilities(child_value, output)
	elif typeof(value) == TYPE_ARRAY:
		for child_value in value:
			collect_required_capabilities(child_value, output)


static func probe_economy_recovery(
	campaign: Dictionary,
	items: Dictionary,
	economy: Dictionary,
	findings: Array[Dictionary]
) -> int:
	var restorative_items: Dictionary = {}
	var ranged_ammo: Dictionary = {}
	for item_id_value in items.keys():
		var item_id := str(item_id_value)
		var item: Dictionary = items.get(item_id, {})
		var use_effect_value: Variant = item.get("use_effect", {})
		if str(item.get("kind", "")) == "consumable" and typeof(use_effect_value) == TYPE_DICTIONARY:
			if str((use_effect_value as Dictionary).get("type", "")) == "heal":
				restorative_items[item_id] = true
		var equipment_value: Variant = item.get("equipment", {})
		if typeof(equipment_value) == TYPE_DICTIONARY:
			var ranged_value: Variant = (equipment_value as Dictionary).get("ranged", {})
			if typeof(ranged_value) == TYPE_DICTIONARY and not (ranged_value as Dictionary).is_empty():
				var ammo_id := str((ranged_value as Dictionary).get("ammo_item_id", ""))
				if not ammo_id.is_empty():
					ranged_ammo[ammo_id] = true
	var starting_inventory: Dictionary = {}
	for entry_value in campaign.get("starting_inventory", []):
		if typeof(entry_value) == TYPE_DICTIONARY:
			var entry: Dictionary = entry_value
			starting_inventory[str(entry.get("item_id", ""))] = int(entry.get("quantity", 0))
	var has_starting_restorative := false
	for item_id_value in restorative_items.keys():
		if int(starting_inventory.get(str(item_id_value), 0)) > 0:
			has_starting_restorative = true
			break
	var merchant_restoratives := 0
	var merchant_ammo: Dictionary = {}
	var merchants: Dictionary = economy.get("merchants", {})
	for merchant_value in merchants.values():
		if typeof(merchant_value) != TYPE_DICTIONARY:
			continue
		var merchant: Dictionary = merchant_value
		var merchant_conditions: Variant = merchant.get("conditions", [])
		if typeof(merchant_conditions) == TYPE_ARRAY and not (merchant_conditions as Array).is_empty():
			continue
		for stock_value in merchant.get("stock", []):
			if typeof(stock_value) != TYPE_DICTIONARY:
				continue
			var stock: Dictionary = stock_value
			var stock_conditions: Variant = stock.get("conditions", [])
			if typeof(stock_conditions) == TYPE_ARRAY and not (stock_conditions as Array).is_empty():
				continue
			var item_id := str(stock.get("item_id", ""))
			if restorative_items.has(item_id) and (bool(stock.get("unlimited", false)) or int(stock.get("quantity", 0)) > 0):
				merchant_restoratives += 1
			if ranged_ammo.has(item_id) and (bool(stock.get("unlimited", false)) or int(stock.get("quantity", 0)) > 0):
				merchant_ammo[item_id] = true
	var source_count := merchant_restoratives + (1 if has_starting_restorative else 0)
	if source_count == 0:
		add_finding(findings, "blocker", "economy.no_restorative_source", "The campaign provides no starting or immediately available healing item.", "economy")
	for ammo_id_value in ranged_ammo.keys():
		var ammo_id := str(ammo_id_value)
		if int(starting_inventory.get(ammo_id, 0)) <= 0 and not merchant_ammo.has(ammo_id):
			add_finding(findings, "warning", "economy.no_ammo_recovery", "Ranged ammunition '%s' has no starting stack or unconditional merchant source." % ammo_id, ammo_id)
	return source_count


static func probe_quest_startability(campaign: Dictionary, story: Dictionary, findings: Array[Dictionary]) -> int:
	var quests: Dictionary = story.get("quests", {})
	var starting: Dictionary = {}
	for quest_id_value in campaign.get("starting_quests", []):
		starting[str(quest_id_value)] = true
	var started_by_effect: Dictionary = {}
	collect_started_quests(story, started_by_effect)
	var ids := PackedStringArray()
	for quest_id_value in quests.keys():
		ids.append(str(quest_id_value))
	ids.sort()
	for quest_id in ids:
		var quest: Dictionary = quests.get(quest_id, {})
		if starting.has(quest_id) or bool(quest.get("auto_start", false)) or started_by_effect.has(quest_id):
			continue
		add_finding(findings, "warning", "quest.no_start_path", "Quest '%s' is neither a starting quest nor started by an authored story effect." % quest_id, quest_id)
	return ids.size()


static func collect_started_quests(value: Variant, output: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		if str(data.get("type", "")) == "start_quest":
			var quest_id := str(data.get("quest_id", ""))
			if not quest_id.is_empty():
				output[quest_id] = true
		for child_value in data.values():
			collect_started_quests(child_value, output)
	elif typeof(value) == TYPE_ARRAY:
		for child_value in value:
			collect_started_quests(child_value, output)


static func probe_save_policy(campaign: Dictionary, findings: Array[Dictionary]) -> void:
	var policy_value: Variant = campaign.get("save_policy", {})
	var policy: Dictionary = policy_value if typeof(policy_value) == TYPE_DICTIONARY else {}
	var manual_slots := int(policy.get("manual_slots", 0))
	var autosave_enabled := bool(policy.get("autosave_enabled", true))
	if manual_slots <= 0 and not autosave_enabled:
		add_finding(findings, "blocker", "save.no_path", "The campaign disables both manual slots and autosave.", "save_policy")
	if autosave_enabled and not bool(policy.get("autosave_on_travel", true)) and not bool(policy.get("autosave_on_progress", true)):
		add_finding(findings, "warning", "save.autosave_never_requested", "Autosave is enabled but neither travel nor durable progress requests it.", "save_policy")
	if bool(policy.get("allow_manual_save_in_combat", false)):
		add_finding(findings, "warning", "save.manual_in_combat", "Manual saving is permitted during active directed combat.", "save_policy")


static func sorted_dictionary_keys(value: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in value.keys():
		output.append(str(key_value))
	output.sort()
	return output


static func reachable_from(graph: Dictionary, start_id: String) -> Dictionary:
	var seen: Dictionary = {}
	if start_id.is_empty() or not graph.has(start_id):
		return seen
	var queue: Array[String] = []
	queue.append(start_id)
	seen[start_id] = true
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		var neighbors_value: Variant = graph.get(current, [])
		if typeof(neighbors_value) != TYPE_ARRAY:
			continue
		for neighbor_value in neighbors_value:
			var neighbor := str(neighbor_value)
			if seen.has(neighbor):
				continue
			seen[neighbor] = true
			queue.append(neighbor)
	return seen


static func can_reach(graph: Dictionary, source_id: String, target_id: String) -> bool:
	return reachable_from(graph, source_id).has(target_id)


static func add_finding(findings: Array[Dictionary], severity: String, code: String, message: String, context: String = "") -> void:
	findings.append({"severity": severity, "code": code, "message": message, "context": context})


static func build_report(campaign_id: String, findings: Array[Dictionary], metrics: Dictionary) -> Dictionary:
	sort_findings(findings)
	var blocker_count := 0
	var warning_count := 0
	var info_count := 0
	for finding in findings:
		match str(finding.get("severity", "info")):
			"blocker":
				blocker_count += 1
			"warning":
				warning_count += 1
			_:
				info_count += 1
	return {
		"ok": blocker_count == 0,
		"campaign_id": campaign_id,
		"probe_count": PROBE_COUNT,
		"blocker_count": blocker_count,
		"warning_count": warning_count,
		"info_count": info_count,
		"findings": findings,
		"metrics": metrics
	}


static func sort_findings(findings: Array[Dictionary]) -> void:
	for left in range(findings.size()):
		for right in range(left + 1, findings.size()):
			var left_key := finding_key(findings[left])
			var right_key := finding_key(findings[right])
			if left_key.naturalnocasecmp_to(right_key) > 0:
				var temporary: Dictionary = findings[left]
				findings[left] = findings[right]
				findings[right] = temporary


static func finding_key(finding: Dictionary) -> String:
	var severity := str(finding.get("severity", "info"))
	return "%d|%s|%s|%s" % [
		int(SEVERITY_RANK.get(severity, 9)),
		str(finding.get("code", "")),
		str(finding.get("context", "")),
		str(finding.get("message", ""))
	]
