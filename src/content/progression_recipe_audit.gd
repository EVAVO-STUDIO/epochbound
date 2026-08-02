@tool
extends RefCounted


static func collect_required_items(value: Variant, output: Dictionary) -> void:
	# Compatibility wrapper for callers that inspect one authored tree. The
	# production audit uses the evidence API below so consumption can accumulate
	# across maps, story and economy before the final quantity is resolved.
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
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value
		var type_id := str(data.get("type", ""))
		var item_id := str(data.get("item_id", ""))
		var quantity := maxi(1, int(data.get("quantity", 1)))
		if not item_id.is_empty():
			if type_id == "has_item":
				held[item_id] = maxi(quantity, int(held.get(item_id, 0)))
			elif type_id == "remove_item":
				consumed[item_id] = int(consumed.get(item_id, 0)) + quantity
		for child_value in data.values():
			collect_required_item_evidence(child_value, held, consumed)
	elif typeof(value) == TYPE_ARRAY:
		for child_value in value:
			collect_required_item_evidence(child_value, held, consumed)


static func required_items_from_evidence(held: Dictionary, consumed: Dictionary) -> Dictionary:
	var all_ids: Dictionary = {}
	for item_id_value in held.keys():
		all_ids[str(item_id_value)] = true
	for item_id_value in consumed.keys():
		all_ids[str(item_id_value)] = true
	var output: Dictionary = {}
	for item_id in sorted_dictionary_keys(all_ids):
		# A possession guard paired with a removal effect describes the same
		# physical item, so do not add those quantities together. Repeated removal
		# effects are cumulative because every authored consumption needs supply.
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
	cyclic_items: Dictionary
) -> void:
	# Expand each original demand independently. This preserves cumulative
	# ingredient costs when several progression paths consume the same material
	# and still handles an item that is both directly required and used by a
	# parent recipe.
	var roots := requirements.duplicate(true)
	for item_id in sorted_dictionary_keys(roots):
		expand_recipe_demand(
			item_id,
			maxi(1, int(roots.get(item_id, 1))),
			output_recipes,
			cyclic_items,
			requirements,
			PackedStringArray()
		)


static func expand_recipe_demand(
	item_id: String,
	quantity: int,
	output_recipes: Dictionary,
	cyclic_items: Dictionary,
	requirements: Dictionary,
	recursion_path: PackedStringArray
) -> void:
	if quantity <= 0 or cyclic_items.has(item_id) or recursion_path.has(item_id):
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
	var batches := int(ceil(float(quantity) / float(output_quantity)))
	var next_path := recursion_path.duplicate()
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
			next_path
		)


static func sorted_dictionary_keys(value: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in value.keys():
		output.append(str(key_value))
	output.sort()
	return output


static func source_array(value: Variant) -> Array:
	return value as Array if typeof(value) == TYPE_ARRAY else []
