@tool
extends RefCounted


static func collect_required_items(value: Variant, output: Dictionary) -> void:
	# Compatibility wrapper for callers that inspect one authored tree. The
	# production audit keeps possession and consumption evidence separate until
	# every relevant content surface has been inspected.
	var held: Dictionary = {}
	var consumed: Dictionary = {}
	collect_required_item_evidence(value, held, consumed)
	var merged := required_items_from_evidence(held, consumed)
	for item_id in sorted_dictionary_keys(merged):
		output[item_id] = maxi(int(output.get(item_id, 0)), int(merged.get(item_id, 0)))


static func collect_required_item_evidence(
	value: Variant,
	held: Dictionary,
	consumed: Dictionary
) -> void:
	# Disconnected records do not prove that every branch or interaction is
	# mandatory, so consumption uses a maximum unless an explicit execution
	# sequence is being inspected.
	collect_item_evidence(value, held, consumed, false)


static func collect_effect_item_evidence(
	value: Variant,
	held: Dictionary,
	consumed: Dictionary
) -> void:
	# Effects in one authored bundle execute together, so repeated removals are
	# cumulative within that bundle.
	collect_item_evidence(value, held, consumed, true)


static func collect_item_evidence(
	value: Variant,
	held: Dictionary,
	consumed: Dictionary,
	accumulate_consumption: bool
) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		var type_id := str(data.get("type", ""))
		var item_id := str(data.get("item_id", ""))
		var quantity := maxi(1, int(data.get("quantity", 1)))
		if not item_id.is_empty():
			if type_id == "has_item":
				held[item_id] = maxi(quantity, int(held.get(item_id, 0)))
			elif type_id == "remove_item":
				if accumulate_consumption:
					consumed[item_id] = int(consumed.get(item_id, 0)) + quantity
				else:
					consumed[item_id] = maxi(quantity, int(consumed.get(item_id, 0)))
		for child_value in data.values():
			collect_item_evidence(
				child_value,
				held,
				consumed,
				accumulate_consumption
			)
	elif typeof(value) == TYPE_ARRAY:
		for child_value in value:
			collect_item_evidence(
				child_value,
				held,
				consumed,
				accumulate_consumption
			)


static func collect_story_required_item_evidence(
	story: Dictionary,
	held: Dictionary,
	consumed: Dictionary
) -> void:
	var story_held: Dictionary = {}
	var story_consumed: Dictionary = {}

	# Quest records do not establish a single executable path between every
	# stage and optional reward, so they use conservative maximum evidence.
	var quests_value: Variant = story.get("quests", {})
	if typeof(quests_value) == TYPE_DICTIONARY:
		collect_required_item_evidence(quests_value, story_held, story_consumed)

	# Conversation choices are alternatives, while nodes connected by `next`
	# execute sequentially. Separate conversations are not assumed mandatory in
	# one playthrough, so their evidence is merged as alternatives.
	var conversations_value: Variant = story.get("conversations", {})
	if typeof(conversations_value) == TYPE_DICTIONARY:
		var conversations: Dictionary = conversations_value
		for conversation_id in sorted_dictionary_keys(conversations):
			var conversation_value: Variant = conversations.get(conversation_id, {})
			if typeof(conversation_value) != TYPE_DICTIONARY:
				continue
			var evidence := conversation_required_item_evidence(
				conversation_value as Dictionary
			)
			merge_evidence_alternative(
				story_held,
				story_consumed,
				evidence_dictionary(evidence, "held"),
				evidence_dictionary(evidence, "consumed")
			)

	merge_evidence_alternative(
		held,
		consumed,
		story_held,
		story_consumed
	)


static func conversation_required_item_evidence(conversation: Dictionary) -> Dictionary:
	var node_index := conversation_node_index(conversation)
	var memo: Dictionary = {}
	var visiting: Dictionary = {}
	return conversation_node_evidence(
		str(conversation.get("start_node", "")),
		node_index,
		memo,
		visiting
	)


static func conversation_node_index(conversation: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	var nodes_value: Variant = conversation.get("nodes", [])
	if typeof(nodes_value) != TYPE_ARRAY:
		return output
	for node_value in nodes_value:
		if typeof(node_value) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_value
		var node_id := str(node.get("id", ""))
		if not node_id.is_empty():
			output[node_id] = node
	return output


static func conversation_node_evidence(
	node_id: String,
	node_index: Dictionary,
	memo: Dictionary,
	visiting: Dictionary
) -> Dictionary:
	if node_id.is_empty() or not node_index.has(node_id):
		return empty_evidence()
	var memo_value: Variant = memo.get(node_id, {})
	if typeof(memo_value) == TYPE_DICTIONARY and not (memo_value as Dictionary).is_empty():
		return duplicate_evidence(memo_value as Dictionary)
	if visiting.has(node_id):
		# Content validation owns graph legality. The quantity probe must never
		# inflate a repeatable dialogue loop into infinite required supply.
		return empty_evidence()
	visiting[node_id] = true

	var node_value: Variant = node_index.get(node_id, {})
	var node: Dictionary = node_value as Dictionary if typeof(node_value) == TYPE_DICTIONARY else {}
	var result_held: Dictionary = {}
	var result_consumed: Dictionary = {}
	collect_required_item_evidence(node.get("conditions", []), result_held, result_consumed)
	collect_effect_item_evidence(node.get("effects", []), result_held, result_consumed)

	if str(node.get("kind", "line")) == "choice":
		var alternatives_held: Dictionary = {}
		var alternatives_consumed: Dictionary = {}
		var has_alternative := false
		var choices_value: Variant = node.get("choices", [])
		if typeof(choices_value) == TYPE_ARRAY:
			for choice_value in choices_value:
				if typeof(choice_value) != TYPE_DICTIONARY:
					continue
				var choice: Dictionary = choice_value
				var branch_held: Dictionary = {}
				var branch_consumed: Dictionary = {}
				collect_required_item_evidence(
					choice.get("conditions", []),
					branch_held,
					branch_consumed
				)
				collect_effect_item_evidence(
					choice.get("effects", []),
					branch_held,
					branch_consumed
				)
				var next_evidence := conversation_node_evidence(
					str(choice.get("next", "")),
					node_index,
					memo,
					visiting
				)
				merge_evidence_sequential(
					branch_held,
					branch_consumed,
					evidence_dictionary(next_evidence, "held"),
					evidence_dictionary(next_evidence, "consumed")
				)
				if not has_alternative:
					alternatives_held = branch_held.duplicate(true)
					alternatives_consumed = branch_consumed.duplicate(true)
					has_alternative = true
				else:
					merge_evidence_alternative(
						alternatives_held,
						alternatives_consumed,
						branch_held,
						branch_consumed
					)
		if has_alternative:
			merge_evidence_sequential(
				result_held,
				result_consumed,
				alternatives_held,
				alternatives_consumed
			)
		else:
			var fallback_evidence := conversation_node_evidence(
				str(node.get("next", node.get("fallback", ""))),
				node_index,
				memo,
				visiting
			)
			merge_evidence_sequential(
				result_held,
				result_consumed,
				evidence_dictionary(fallback_evidence, "held"),
				evidence_dictionary(fallback_evidence, "consumed")
			)
	else:
		var next_evidence := conversation_node_evidence(
			str(node.get("next", "")),
			node_index,
			memo,
			visiting
		)
		merge_evidence_sequential(
			result_held,
			result_consumed,
			evidence_dictionary(next_evidence, "held"),
			evidence_dictionary(next_evidence, "consumed")
		)

	visiting.erase(node_id)
	var result := {"held": result_held, "consumed": result_consumed}
	memo[node_id] = duplicate_evidence(result)
	return result


static func empty_evidence() -> Dictionary:
	return {"held": {}, "consumed": {}}


static func duplicate_evidence(evidence: Dictionary) -> Dictionary:
	return {
		"held": evidence_dictionary(evidence, "held").duplicate(true),
		"consumed": evidence_dictionary(evidence, "consumed").duplicate(true)
	}


static func evidence_dictionary(evidence: Dictionary, field: String) -> Dictionary:
	var value: Variant = evidence.get(field, {})
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func merge_evidence_sequential(
	target_held: Dictionary,
	target_consumed: Dictionary,
	source_held: Dictionary,
	source_consumed: Dictionary
) -> void:
	for item_id in sorted_dictionary_keys(source_held):
		target_held[item_id] = maxi(
			int(target_held.get(item_id, 0)),
			int(source_held.get(item_id, 0))
		)
	for item_id in sorted_dictionary_keys(source_consumed):
		target_consumed[item_id] = (
			int(target_consumed.get(item_id, 0))
			+ int(source_consumed.get(item_id, 0))
		)


static func merge_evidence_alternative(
	target_held: Dictionary,
	target_consumed: Dictionary,
	source_held: Dictionary,
	source_consumed: Dictionary
) -> void:
	for item_id in sorted_dictionary_keys(source_held):
		target_held[item_id] = maxi(
			int(target_held.get(item_id, 0)),
			int(source_held.get(item_id, 0))
		)
	for item_id in sorted_dictionary_keys(source_consumed):
		target_consumed[item_id] = maxi(
			int(target_consumed.get(item_id, 0)),
			int(source_consumed.get(item_id, 0))
		)


static func required_items_from_evidence(held: Dictionary, consumed: Dictionary) -> Dictionary:
	var all_ids: Dictionary = {}
	for item_id_value in held.keys():
		all_ids[str(item_id_value)] = true
	for item_id_value in consumed.keys():
		all_ids[str(item_id_value)] = true
	var output: Dictionary = {}
	for item_id in sorted_dictionary_keys(all_ids):
		# A possession guard paired with a removal effect describes the same
		# physical item, so do not add those quantities together. Proven
		# sequential removals remain cumulative because each consumes real supply.
		output[item_id] = maxi(
			int(held.get(item_id, 0)),
			int(consumed.get(item_id, 0))
		)
	return output


static func recipe_output_index(recipes: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for recipe_id_value in recipes.keys():
		var recipe_id := str(recipe_id_value)
		var recipe: Dictionary = recipes.get(recipe_id, {})
		var output_value: Variant = recipe.get("output", {})
		if typeof(output_value) != TYPE_DICTIONARY:
			continue
		var item_id := str((output_value as Dictionary).get("item_id", ""))
		if item_id.is_empty():
			continue
		var records_value: Variant = output.get(item_id, [])
		var records: Array = records_value as Array if typeof(records_value) == TYPE_ARRAY else []
		records.append({"recipe_id": recipe_id, "recipe": recipe})
		output[item_id] = records
	return output


static func detect_recipe_cycle_items(output_recipes: Dictionary) -> Dictionary:
	var cyclic_items: Dictionary = {}
	var state: Dictionary = {}
	var stack: Array[String] = []
	for item_id in sorted_dictionary_keys(output_recipes):
		detect_recipe_cycle_from(item_id, output_recipes, state, stack, cyclic_items)
	return cyclic_items


static func recipe_cycle_component(
	start_item_id: String,
	cyclic_items: Dictionary,
	output_recipes: Dictionary
) -> PackedStringArray:
	var seen: Dictionary = {}
	seen[start_item_id] = true
	var queue: Array[String] = [start_item_id]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for candidate in sorted_dictionary_keys(cyclic_items):
			if seen.has(candidate):
				continue
			if recipe_item_depends_on(current, candidate, output_recipes) or recipe_item_depends_on(candidate, current, output_recipes):
				seen[candidate] = true
				queue.append(candidate)
	return sorted_dictionary_keys(seen)


static func recipe_item_depends_on(item_id: String, ingredient_id: String, output_recipes: Dictionary) -> bool:
	for record_value in source_array(output_recipes.get(item_id, [])):
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var recipe_value: Variant = (record_value as Dictionary).get("recipe", {})
		if typeof(recipe_value) != TYPE_DICTIONARY:
			continue
		for ingredient_value in (recipe_value as Dictionary).get("ingredients", []):
			if typeof(ingredient_value) == TYPE_DICTIONARY and str((ingredient_value as Dictionary).get("item_id", "")) == ingredient_id:
				return true
	return false


static func detect_recipe_cycle_from(
	item_id: String,
	output_recipes: Dictionary,
	state: Dictionary,
	stack: Array[String],
	cyclic_items: Dictionary
) -> void:
	var current_state := int(state.get(item_id, 0))
	if current_state == 2:
		return
	if current_state == 1:
		var start := stack.find(item_id)
		if start < 0:
			cyclic_items[item_id] = true
		else:
			for index in range(start, stack.size()):
				cyclic_items[stack[index]] = true
		return
	state[item_id] = 1
	stack.append(item_id)
	var recipe_records := source_array(output_recipes.get(item_id, []))
	for record_value in recipe_records:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var recipe: Dictionary = (record_value as Dictionary).get("recipe", {})
		for ingredient_value in recipe.get("ingredients", []):
			if typeof(ingredient_value) != TYPE_DICTIONARY:
				continue
			var ingredient_id := str((ingredient_value as Dictionary).get("item_id", ""))
			if output_recipes.has(ingredient_id):
				detect_recipe_cycle_from(ingredient_id, output_recipes, state, stack, cyclic_items)
	stack.pop_back()
	state[item_id] = 2


static func expand_recipe_requirements(
	requirements: Dictionary,
	output_recipes: Dictionary,
	cyclic_items: Dictionary,
	non_recipe_supply: Dictionary = {},
	available_recipe_items: Dictionary = {},
	enforce_recipe_availability: bool = false
) -> void:
	# Resolve each original demand against one shared supply pool. Ingredients are
	# expanded only for the residual quantity that genuinely must be crafted.
	var roots: Dictionary = requirements.duplicate(true)
	var remaining_supply: Dictionary = non_recipe_supply.duplicate(true)
	for item_id in sorted_dictionary_keys(roots):
		expand_recipe_demand(
			item_id,
			maxi(1, int(roots.get(item_id, 1))),
			output_recipes,
			cyclic_items,
			requirements,
			remaining_supply,
			available_recipe_items,
			enforce_recipe_availability,
			PackedStringArray()
		)


static func expand_recipe_demand(
	item_id: String,
	quantity: int,
	output_recipes: Dictionary,
	cyclic_items: Dictionary,
	requirements: Dictionary,
	remaining_supply: Dictionary,
	available_recipe_items: Dictionary,
	enforce_recipe_availability: bool,
	recursion_path: PackedStringArray
) -> void:
	if quantity <= 0:
		return
	var residual_quantity := consume_available_supply(item_id, quantity, remaining_supply)
	if residual_quantity <= 0:
		return
	if cyclic_items.has(item_id) or recursion_path.has(item_id):
		return
	if enforce_recipe_availability and not available_recipe_items.has(item_id):
		return
	var recipe_records := source_array(output_recipes.get(item_id, []))
	# Alternative recipes are intentionally not guessed. The production audit
	# expands only a single unambiguous dependency route.
	if recipe_records.size() != 1 or typeof(recipe_records[0]) != TYPE_DICTIONARY:
		return
	var recipe_value: Variant = (recipe_records[0] as Dictionary).get("recipe", {})
	if typeof(recipe_value) != TYPE_DICTIONARY:
		return
	var recipe: Dictionary = recipe_value
	var output_value: Variant = recipe.get("output", {})
	var output_quantity := 1
	if typeof(output_value) == TYPE_DICTIONARY:
		output_quantity = maxi(1, int((output_value as Dictionary).get("quantity", 1)))
	var batches := int(ceil(float(residual_quantity) / float(output_quantity)))
	var produced_quantity := batches * output_quantity
	add_available_supply(
		item_id,
		maxi(0, produced_quantity - residual_quantity),
		remaining_supply
	)
	var next_path: PackedStringArray = recursion_path.duplicate()
	next_path.append(item_id)
	for ingredient_value in recipe.get("ingredients", []):
		if typeof(ingredient_value) != TYPE_DICTIONARY:
			continue
		var ingredient: Dictionary = ingredient_value
		var ingredient_id := str(ingredient.get("item_id", ""))
		var ingredient_quantity := maxi(1, int(ingredient.get("quantity", 1))) * batches
		if ingredient_id.is_empty():
			continue
		requirements[ingredient_id] = int(requirements.get(ingredient_id, 0)) + ingredient_quantity
		expand_recipe_demand(
			ingredient_id,
			ingredient_quantity,
			output_recipes,
			cyclic_items,
			requirements,
			remaining_supply,
			available_recipe_items,
			enforce_recipe_availability,
			next_path
		)


static func consume_available_supply(
	item_id: String,
	quantity: int,
	remaining_supply: Dictionary
) -> int:
	if not remaining_supply.has(item_id):
		return quantity
	var available := int(remaining_supply.get(item_id, 0))
	if available < 0:
		return 0
	var consumed := mini(quantity, maxi(0, available))
	remaining_supply[item_id] = available - consumed
	return quantity - consumed


static func add_available_supply(
	item_id: String,
	quantity: int,
	remaining_supply: Dictionary
) -> void:
	if item_id.is_empty() or quantity <= 0:
		return
	var available := int(remaining_supply.get(item_id, 0))
	if available < 0:
		return
	remaining_supply[item_id] = available + quantity


static func sorted_dictionary_keys(value: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in value.keys():
		output.append(str(key_value))
	output.sort()
	return output


static func source_array(value: Variant) -> Array:
	return value as Array if typeof(value) == TYPE_ARRAY else []
