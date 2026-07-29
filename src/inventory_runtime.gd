extends "res://src/companion_runtime.gd"

const ItemCatalog = preload("res://src/content/item_catalog.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")
const ItemValidator = preload("res://src/content/item_validator.gd")

const INVENTORY_NOTICE_DURATION := 1.4
const INVENTORY_ROWS := 8

var item_definitions: Dictionary = {}
var recipe_definitions: Dictionary = {}
var inventory: Dictionary = {}
var unlocked_recipes: Dictionary = {}
var inventory_open := false
var inventory_tab := 0
var inventory_index := 0
var inventory_notice := ""
var inventory_notice_timer := 0.0


func load_campaign(path: String) -> bool:
	var validation := ItemValidator.validate_campaign_path(path)
	if not validation.get("ok", false):
		load_error = format_errors(validation.get("errors", []))
		push_error("Item and recipe validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	var loaded := super.load_campaign(path)
	if not loaded:
		return false
	if not load_inventory_catalogs():
		return false
	reset_inventory_state()
	return true


func load_fallback_campaign() -> void:
	super.load_fallback_campaign()
	item_definitions = definitions_from_catalog(ItemCatalog.default_item_catalog(), "items")
	recipe_definitions = definitions_from_catalog(ItemCatalog.default_recipe_catalog(), "recipes")
	reset_inventory_state()


func load_inventory_catalogs() -> bool:
	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	var recipe_result := ItemCatalog.load_recipe_catalogs(campaign_path, campaign)
	if not item_result.get("ok", false) or not recipe_result.get("ok", false):
		var errors: Array[String] = []
		ItemCatalog.append_messages(errors, item_result.get("errors", []))
		ItemCatalog.append_messages(errors, recipe_result.get("errors", []))
		load_error = format_errors(errors)
		push_error("Inventory catalog load failed: %s" % load_error)
		return false
	item_definitions = item_result.get("definitions", {})
	recipe_definitions = recipe_result.get("definitions", {})
	return true


func definitions_from_catalog(catalog: Dictionary, field: String) -> Dictionary:
	var output: Dictionary = {}
	var value: Variant = catalog.get(field, [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for record_value in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_value
		var identifier := str(record.get("id", ""))
		if not identifier.is_empty():
			output[identifier] = record
	return output


func reset_inventory_state() -> void:
	inventory = InventoryModel.initial_inventory(campaign, item_definitions)
	unlocked_recipes = InventoryModel.initial_recipe_unlocks(campaign, recipe_definitions)
	inventory_open = false
	inventory_tab = 0
	inventory_index = 0
	inventory_notice = ""
	inventory_notice_timer = 0.0


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	inventory_open = false
	return super.activate_map(map_id, entry_id, requested_era, use_transition)


func update_game(delta: float) -> void:
	inventory_notice_timer = maxf(0.0, inventory_notice_timer - delta)
	if inventory_notice_timer <= 0.0:
		inventory_notice = ""
	if flow == Flow.GAME and inventory_open:
		update_inventory_overlay()
		return
	if flow == Flow.GAME and dialogue.is_empty() and transition_lock <= 0.45:
		if Input.is_action_just_pressed("inventory_toggle"):
			open_inventory()
			return
		if Input.is_action_just_pressed("quick_item"):
			use_quick_item()
	super.update_game(delta)


func open_inventory() -> void:
	inventory_open = true
	inventory_tab = 0
	inventory_index = clamp_inventory_index(inventory_index)
	inventory_notice = ""
	inventory_notice_timer = 0.0


func close_inventory() -> void:
	inventory_open = false
	inventory_notice = ""
	inventory_notice_timer = 0.0


func update_inventory_overlay() -> void:
	if Input.is_action_just_pressed("inventory_toggle") or Input.is_action_just_pressed("ui_cancel"):
		close_inventory()
		return
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right"):
		inventory_tab = 1 - inventory_tab
		inventory_index = 0
		return
	var entry_count := current_inventory_entry_count()
	if entry_count > 0:
		if Input.is_action_just_pressed("move_up"):
			inventory_index = posmod(inventory_index - 1, entry_count)
		elif Input.is_action_just_pressed("move_down"):
			inventory_index = posmod(inventory_index + 1, entry_count)
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("attack"):
		activate_inventory_selection()


func current_inventory_entry_count() -> int:
	return inventory_item_ids().size() if inventory_tab == 0 else inventory_recipe_ids().size()


func clamp_inventory_index(value: int) -> int:
	var entry_count := current_inventory_entry_count()
	return clampi(value, 0, maxi(0, entry_count - 1))


func inventory_item_ids() -> PackedStringArray:
	return InventoryModel.sorted_inventory_ids(inventory, item_definitions)


func inventory_recipe_ids() -> PackedStringArray:
	return InventoryModel.sorted_recipe_ids(unlocked_recipes, recipe_definitions)


func activate_inventory_selection() -> void:
	if inventory_tab == 0:
		var item_ids := inventory_item_ids()
		if item_ids.is_empty():
			set_inventory_notice("No items are available.")
			return
		inventory_index = clampi(inventory_index, 0, item_ids.size() - 1)
		use_inventory_item(item_ids[inventory_index])
		inventory_index = clamp_inventory_index(inventory_index)
		return
	var recipe_ids := inventory_recipe_ids()
	if recipe_ids.is_empty():
		set_inventory_notice("No recipes are unlocked.")
		return
	inventory_index = clampi(inventory_index, 0, recipe_ids.size() - 1)
	craft_inventory_recipe(recipe_ids[inventory_index])


func use_quick_item() -> void:
	var item_id := InventoryModel.first_healing_item(inventory, item_definitions)
	if item_id.is_empty():
		set_combat_text("No restorative item is available.", 1.0)
		return
	use_inventory_item(item_id, true)


func use_inventory_item(item_id: String, quick_use: bool = false) -> bool:
	var definition_data := ItemCatalog.item(item_definitions, item_id)
	if definition_data.is_empty() or InventoryModel.count(inventory, item_id) <= 0:
		set_inventory_feedback("That item is not available.", quick_use)
		return false
	if ItemCatalog.item_kind(definition_data) != "consumable":
		set_inventory_feedback("%s cannot be used directly." % ItemCatalog.item_name(definition_data, item_id), quick_use)
		return false
	var effect := ItemCatalog.use_effect(definition_data)
	var effect_type := str(effect.get("type", "none"))
	if effect_type == "heal":
		var maximum := actor_health("player", 32)
		if player_health >= maximum:
			set_inventory_feedback("Health is already full.", quick_use)
			return false
		var amount := maxi(1, int(effect.get("amount", 1)))
		var before := player_health
		player_health = mini(maximum, player_health + amount)
		InventoryModel.remove_item(inventory, item_id, 1)
		set_inventory_feedback(
			"%s restores %d health." % [ItemCatalog.item_name(definition_data, item_id), player_health - before],
			quick_use
		)
		return true
	set_inventory_feedback("%s has no usable effect yet." % ItemCatalog.item_name(definition_data, item_id), quick_use)
	return false


func craft_inventory_recipe(recipe_id: String) -> bool:
	if not bool(unlocked_recipes.get(recipe_id, false)):
		set_inventory_notice("That recipe is still unknown.")
		return false
	var recipe_data := ItemCatalog.recipe(recipe_definitions, recipe_id)
	if recipe_data.is_empty():
		set_inventory_notice("The selected recipe is unavailable.")
		return false
	if not InventoryModel.can_craft(recipe_data, inventory, item_definitions):
		var missing := InventoryModel.missing_ingredients(recipe_data, inventory)
		if missing.is_empty():
			set_inventory_notice("The result cannot fit in its item stack.")
		else:
			set_inventory_notice("Missing: %s" % missing_ingredient_names(missing))
		return false
	var result := InventoryModel.craft(recipe_data, inventory, item_definitions)
	if not result.get("ok", false):
		set_inventory_notice("Crafting did not complete.")
		return false
	var item_id := str(result.get("item_id", ""))
	var definition_data := ItemCatalog.item(item_definitions, item_id)
	set_inventory_notice(
		"Crafted %s x%d." % [ItemCatalog.item_name(definition_data, item_id), int(result.get("quantity", 0))]
	)
	return true


func missing_ingredient_names(missing: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for record in missing:
		var split := record.split(":", false, 1)
		var item_id := str(split[0]) if not split.is_empty() else record
		var quantity := int(split[1]) if split.size() > 1 else 1
		var definition_data := ItemCatalog.item(item_definitions, item_id)
		parts.append("%s x%d" % [ItemCatalog.item_name(definition_data, item_id), quantity])
	return ", ".join(parts)


func collect_pickup(index: int) -> void:
	if index < 0 or index >= runtime_entities.size() or typeof(runtime_entities[index]) != TYPE_DICTIONARY:
		return
	var entity: Dictionary = runtime_entities[index]
	var state_key := str(entity.get("state_key", ""))
	var was_collected := session_state.has(state_key)
	var definition_data: Dictionary = entity.get("definition", {})
	var grants := ItemCatalog.item_grants(definition_data)
	super.collect_pickup(index)
	if was_collected or not session_state.has(state_key) or grants.is_empty():
		return
	var grant_result := InventoryModel.add_grants(inventory, item_definitions, grants)
	var added: Dictionary = grant_result.get("added", {})
	if not added.is_empty():
		set_combat_text("Recovered %s." % InventoryModel.grant_summary(added, item_definitions), 1.45)


func reveal_companion_cue(cue: Dictionary) -> void:
	var state_key := CompanionModel.cue_state_key(str(map_data.get("id", "map")), cue)
	var was_discovered := session_state.has(state_key)
	var grants := ItemCatalog.item_grants(cue, "reward_items")
	var recipe_ids := ItemCatalog.recipe_unlocks(cue)
	super.reveal_companion_cue(cue)
	if was_discovered or not session_state.has(state_key):
		return
	var additions := PackedStringArray()
	var grant_result := InventoryModel.add_grants(inventory, item_definitions, grants)
	var added: Dictionary = grant_result.get("added", {})
	if not added.is_empty():
		additions.append("Recovered %s." % InventoryModel.grant_summary(added, item_definitions))
	var unlocked_names := unlock_recipe_ids(recipe_ids)
	if not unlocked_names.is_empty():
		additions.append("Recipe learned: %s." % ", ".join(unlocked_names))
	if not additions.is_empty():
		dialogue += "\n" + "\n".join(additions)


func unlock_recipe_ids(recipe_ids: PackedStringArray) -> PackedStringArray:
	var names := PackedStringArray()
	for recipe_id in recipe_ids:
		if not recipe_definitions.has(recipe_id) or bool(unlocked_recipes.get(recipe_id, false)):
			continue
		unlocked_recipes[recipe_id] = true
		var recipe_data := ItemCatalog.recipe(recipe_definitions, recipe_id)
		names.append(str(recipe_data.get("display_name", recipe_id)))
	return names


func set_inventory_feedback(message: String, quick_use: bool) -> void:
	if quick_use:
		set_combat_text(message, INVENTORY_NOTICE_DURATION)
	else:
		set_inventory_notice(message)


func set_inventory_notice(message: String) -> void:
	inventory_notice = message
	inventory_notice_timer = INVENTORY_NOTICE_DURATION


func draw_game() -> void:
	super.draw_game()
	draw_quick_item_hud()
	if inventory_open:
		draw_inventory_overlay()


func draw_quick_item_hud() -> void:
	var item_id := InventoryModel.first_healing_item(inventory, item_definitions)
	var label := "NO RESTORATIVE"
	if not item_id.is_empty():
		var definition_data := ItemCatalog.item(item_definitions, item_id)
		label = "%s x%d" % [ItemCatalog.item_name(definition_data, item_id), InventoryModel.count(inventory, item_id)]
	draw_rect(Rect2(10, 64, 104, 26), Color(0.03, 0.04, 0.05, 0.84))
	draw_string(ThemeDB.fallback_font, Vector2(16, 80), label, HORIZONTAL_ALIGNMENT_LEFT, 94, 8, Color("d6cfb4"))
	draw_string(ThemeDB.fallback_font, Vector2(16, 88), "V / RB", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("8f9aa2"))


func draw_inventory_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.015, 0.02, 0.027, 0.92))
	draw_rect(Rect2(34, 24, 572, 312), Color("10161d"))
	draw_rect(Rect2(34, 24, 572, 312), Color("d2bd78"), false, 2.0)
	draw_centered("FIELD SATCHEL", 50, 18, Color("f2dfaa"))
	var item_color := Color("f2d77f") if inventory_tab == 0 else Color("78858f")
	var recipe_color := Color("f2d77f") if inventory_tab == 1 else Color("78858f")
	draw_string(ThemeDB.fallback_font, Vector2(68, 72), "ITEMS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, item_color)
	draw_string(ThemeDB.fallback_font, Vector2(168, 72), "RECIPES", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, recipe_color)
	draw_string(ThemeDB.fallback_font, Vector2(410, 72), "I / BACK CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("89959d"))
	if inventory_tab == 0:
		draw_item_inventory_tab()
	else:
		draw_recipe_inventory_tab()
	if not inventory_notice.is_empty():
		draw_rect(Rect2(86, 298, 468, 24), Color(0.03, 0.04, 0.05, 0.9))
		draw_centered(inventory_notice, 315, 9, Color("f0d58a"))


func draw_item_inventory_tab() -> void:
	var item_ids := inventory_item_ids()
	inventory_index = clamp_inventory_index(inventory_index)
	if item_ids.is_empty():
		draw_centered("THE SATCHEL IS EMPTY", 178, 12, Color("89959d"))
		return
	var start := maxi(0, inventory_index - INVENTORY_ROWS + 1)
	for row in range(mini(INVENTORY_ROWS, item_ids.size() - start)):
		var index := start + row
		var item_id := item_ids[index]
		var definition_data := ItemCatalog.item(item_definitions, item_id)
		var selected := index == inventory_index
		if selected:
			draw_rect(Rect2(58, 88 + row * 23, 252, 21), Color(0.22, 0.19, 0.11, 0.9))
		draw_string(
			ThemeDB.fallback_font,
			Vector2(68, 103 + row * 23),
			ItemCatalog.item_name(definition_data, item_id),
			HORIZONTAL_ALIGNMENT_LEFT,
			190,
			10,
			Color("f5e2ae") if selected else Color("c3c7c5")
		)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(266, 103 + row * 23),
			"x%d" % InventoryModel.count(inventory, item_id),
			HORIZONTAL_ALIGNMENT_RIGHT,
			34,
			10,
			Color("e0c46d")
		)
	var selected_id := item_ids[inventory_index]
	var selected_data := ItemCatalog.item(item_definitions, selected_id)
	draw_rect(Rect2(330, 88, 246, 190), Color(0.05, 0.07, 0.09, 0.9))
	draw_string(ThemeDB.fallback_font, Vector2(344, 108), ItemCatalog.item_name(selected_data, selected_id), HORIZONTAL_ALIGNMENT_LEFT, 218, 13, Color("f0d58a"))
	draw_string(ThemeDB.fallback_font, Vector2(344, 128), ItemCatalog.item_kind(selected_data).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("94a1a8"))
	draw_text_lines(str(selected_data.get("description", "")), Vector2(344, 151), 9, Color("d4d7d5"))
	var effect := ItemCatalog.use_effect(selected_data)
	if str(effect.get("type", "none")) == "heal":
		draw_string(ThemeDB.fallback_font, Vector2(344, 238), "RESTORES %d HEALTH" % int(effect.get("amount", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("a9d5b0"))
	draw_string(ThemeDB.fallback_font, Vector2(344, 262), "E / A USE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("89959d"))


func draw_recipe_inventory_tab() -> void:
	var recipe_ids := inventory_recipe_ids()
	inventory_index = clamp_inventory_index(inventory_index)
	if recipe_ids.is_empty():
		draw_centered("NO RECIPES HAVE BEEN LEARNED", 178, 12, Color("89959d"))
		return
	var start := maxi(0, inventory_index - INVENTORY_ROWS + 1)
	for row in range(mini(INVENTORY_ROWS, recipe_ids.size() - start)):
		var index := start + row
		var recipe_id := recipe_ids[index]
		var recipe_data := ItemCatalog.recipe(recipe_definitions, recipe_id)
		var selected := index == inventory_index
		var craftable := InventoryModel.can_craft(recipe_data, inventory, item_definitions)
		if selected:
			draw_rect(Rect2(58, 88 + row * 23, 252, 21), Color(0.22, 0.19, 0.11, 0.9))
		draw_string(
			ThemeDB.fallback_font,
			Vector2(68, 103 + row * 23),
			str(recipe_data.get("display_name", recipe_id)),
			HORIZONTAL_ALIGNMENT_LEFT,
			218,
			10,
			Color("f5e2ae") if selected else Color("c3c7c5")
		)
		draw_circle(Vector2(296, 98 + row * 23), 3.0, Color("83bc8e") if craftable else Color("83564f"))
	var selected_id := recipe_ids[inventory_index]
	var selected_data := ItemCatalog.recipe(recipe_definitions, selected_id)
	draw_rect(Rect2(330, 88, 246, 190), Color(0.05, 0.07, 0.09, 0.9))
	draw_string(ThemeDB.fallback_font, Vector2(344, 108), str(selected_data.get("display_name", selected_id)), HORIZONTAL_ALIGNMENT_LEFT, 218, 13, Color("f0d58a"))
	draw_text_lines(str(selected_data.get("description", "")), Vector2(344, 132), 9, Color("d4d7d5"))
	var line_y := 192.0
	for ingredient_value in InventoryModel.ingredients(selected_data):
		var ingredient: Dictionary = ingredient_value
		var item_id := str(ingredient.get("item_id", ""))
		var required := int(ingredient.get("quantity", 1))
		var available := InventoryModel.count(inventory, item_id)
		var item_data := ItemCatalog.item(item_definitions, item_id)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(344, line_y),
			"%s  %d / %d" % [ItemCatalog.item_name(item_data, item_id), available, required],
			HORIZONTAL_ALIGNMENT_LEFT,
			218,
			9,
			Color("a9d5b0") if available >= required else Color("d68b7c")
		)
		line_y += 18.0
	var output := InventoryModel.recipe_output(selected_data)
	var output_id := str(output.get("item_id", ""))
	var output_data := ItemCatalog.item(item_definitions, output_id)
	draw_string(ThemeDB.fallback_font, Vector2(344, 252), "MAKES %s x%d" % [ItemCatalog.item_name(output_data, output_id), int(output.get("quantity", 1))], HORIZONTAL_ALIGNMENT_LEFT, 218, 9, Color("e0c46d"))
	draw_string(ThemeDB.fallback_font, Vector2(344, 270), "E / A CRAFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("89959d"))
