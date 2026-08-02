@tool
extends RefCounted

const RecipeAudit = preload("res://src/content/progression_recipe_audit.gd")
const SourceIndex = preload("res://src/content/progression_source_index.gd")


static func audit(
	campaign: Dictionary,
	maps: Dictionary,
	items: Dictionary,
	recipes: Dictionary,
	story: Dictionary,
	economy: Dictionary,
	objects: Dictionary,
	required_capabilities: Dictionary,
	findings: Array[Dictionary]
) -> Dictionary:
	var requirements: Dictionary = {}
	RecipeAudit.collect_required_items(maps, requirements)
	RecipeAudit.collect_required_items(story, requirements)
	RecipeAudit.collect_required_items(economy, requirements)
	var output_recipes := RecipeAudit.recipe_output_index(recipes)
	var cyclic_items := RecipeAudit.detect_recipe_cycle_items(output_recipes)
	RecipeAudit.expand_recipe_requirements(requirements, output_recipes, cyclic_items)

	var merchant_bindings := SourceIndex.merchant_binding_index(objects, maps)
	var sources := SourceIndex.build_item_source_index(
		campaign,
		maps,
		items,
		recipes,
		story,
		economy,
		objects,
		merchant_bindings
	)
	report_unseeded_recipe_cycles(cyclic_items, output_recipes, sources, findings)
	var required_item_ids := sorted_dictionary_keys(requirements)
	for item_id in required_item_ids:
		var required_quantity := maxi(1, int(requirements.get(item_id, 1)))
		var item_sources := SourceIndex.source_array(sources.get(item_id, []))
		var usable_sources := SourceIndex.usable_item_sources(item_sources)
		if usable_sources.is_empty():
			var explained := false
			if SourceIndex.has_locked_recipe_source(item_sources):
				add_finding(findings, "blocker", "progression.recipe_never_unlocked", "Progression item '%s' is produced only by a recipe with no authored unlock route." % item_id, item_id)
				explained = true
			if SourceIndex.has_unbound_merchant_source(item_sources):
				add_finding(findings, "blocker", "progression.merchant_source_unbound", "Progression item '%s' is sold only by a merchant with no reusable NPC binding." % item_id, item_id)
				explained = true
			if not explained:
				add_finding(findings, "blocker", "progression.item_no_source", "Progression item '%s' has no authored acquisition source." % item_id, item_id)
			continue
		if SourceIndex.every_source_requires_item(usable_sources, item_id):
			add_finding(findings, "blocker", "progression.item_self_lock", "Every source for progression item '%s' requires that same item." % item_id, item_id)
		elif SourceIndex.every_source_is_gated(usable_sources):
			add_finding(findings, "warning", "progression.item_only_gated_sources", "Every source for progression item '%s' is gated; verify the first route cannot depend on later progress." % item_id, item_id)
		var supply := SourceIndex.finite_source_supply(usable_sources)
		if not bool(supply.get("unlimited", false)) and int(supply.get("quantity", 0)) < required_quantity:
			add_finding(findings, "blocker", "progression.insufficient_finite_supply", "Progression item '%s' requires %d but all authored finite sources provide only %d." % [item_id, required_quantity, int(supply.get("quantity", 0))], item_id)

	var capability_items: Dictionary = {}
	var starting_capabilities := SourceIndex.starting_capability_set(campaign, items)
	var required_capability_ids := sorted_dictionary_keys(required_capabilities)
	for capability_id in required_capability_ids:
		if starting_capabilities.has(capability_id):
			continue
		var granting_items := SourceIndex.items_granting_capability(items, capability_id)
		capability_items[capability_id] = granting_items
		var capability_sources: Array = []
		for item_id_value in granting_items:
			var item_id := str(item_id_value)
			for source_value in SourceIndex.usable_item_sources(SourceIndex.source_array(sources.get(item_id, []))):
				if typeof(source_value) == TYPE_DICTIONARY:
					var source: Dictionary = (source_value as Dictionary).duplicate(true)
					source["item_id"] = item_id
					capability_sources.append(source)
		if capability_sources.is_empty():
			add_finding(findings, "blocker", "progression.capability_item_no_source", "Required capability '%s' is defined on equipment that has no authored acquisition source." % capability_id, capability_id)
			continue
		if SourceIndex.every_source_requires_capability(capability_sources, capability_id):
			add_finding(findings, "blocker", "progression.capability_self_lock", "Every acquisition route for capability '%s' requires that same capability." % capability_id, capability_id)
		elif SourceIndex.every_source_is_gated(capability_sources):
			add_finding(findings, "warning", "progression.capability_only_gated_sources", "Every acquisition route for capability '%s' is gated; verify the capability is obtainable before its first mandatory use." % capability_id, capability_id)

	return {
		"requirements": requirements,
		"sources": sources,
		"capability_items": capability_items,
		"starting_capabilities": starting_capabilities,
		"merchant_bindings": merchant_bindings,
		"progression_item_count": requirements.size(),
		"progression_capability_count": required_capabilities.size()
	}


static func report_unseeded_recipe_cycles(
	cyclic_items: Dictionary,
	output_recipes: Dictionary,
	sources: Dictionary,
	findings: Array[Dictionary]
) -> void:
	var reported: Dictionary = {}
	for item_id in sorted_dictionary_keys(cyclic_items):
		if reported.has(item_id):
			continue
		var component := RecipeAudit.recipe_cycle_component(item_id, cyclic_items, output_recipes)
		var has_seed := false
		for component_item_id in component:
			reported[component_item_id] = true
			for source_value in SourceIndex.usable_item_sources(SourceIndex.source_array(sources.get(component_item_id, []))):
				if typeof(source_value) == TYPE_DICTIONARY and str((source_value as Dictionary).get("kind", "")) != "recipe":
					has_seed = true
					break
			if has_seed:
				break
		if not has_seed:
			var context := component[0] if not component.is_empty() else item_id
			add_finding(findings, "blocker", "progression.recipe_cycle", "Recipe dependencies [%s] form an unseeded cycle and cannot establish an initial source." % ", ".join(component), context)


static func add_finding(findings: Array[Dictionary], severity: String, code: String, message: String, context: String = "") -> void:
	findings.append({"severity": severity, "code": code, "message": message, "context": context})


static func sorted_dictionary_keys(value: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in value.keys():
		output.append(str(key_value))
	output.sort()
	return output
