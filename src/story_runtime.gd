extends "res://src/inventory_runtime.gd"

const StoryCatalog = preload("res://src/content/story_catalog.gd")
const StoryValidator = preload("res://src/content/story_validator.gd")
const StoryModel = preload("res://src/game/story_model.gd")
const StoryInventoryModel = preload("res://src/game/inventory_model.gd")
const StoryItemCatalog = preload("res://src/content/item_catalog.gd")
const StoryObjectCatalog = preload("res://src/content/object_catalog.gd")
const StoryEncounterModel = preload("res://src/game/encounter_model.gd")
const StoryCompanionModel = preload("res://src/game/companion_model.gd")
const StoryRepository = preload("res://src/content/campaign_repository.gd")
const StoryMapModel = preload("res://src/content/map_model.gd")

const STORY_NOTICE_DURATION := 1.7
const STORY_JOURNAL_ROWS := 7
const MAX_STORY_TRANSITIONS := 32

var conversation_definitions: Dictionary = {}
var quest_definitions: Dictionary = {}
var quest_progress: Dictionary = {}
var active_conversation_id := ""
var active_node_id := ""
var active_choice_index := 0
var story_journal_open := false
var story_journal_tab := 0
var story_journal_index := 0
var story_notice := ""
var story_notice_timer := 0.0
var story_evaluation_lock := false


func load_campaign(path: String) -> bool:
	var validation := StoryValidator.validate_campaign_path(path)
	if not validation.get("ok", false):
		load_error = format_errors(validation.get("errors", []))
		push_error("Story validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	var loaded := super.load_campaign(path)
	if not loaded:
		return false
	if not load_story_catalogs():
		return false
	reset_story_state()
	return true


func load_fallback_campaign() -> void:
	super.load_fallback_campaign()
	var fallback := StoryCatalog.default_story_catalog()
	conversation_definitions = definitions_from_story_catalog(fallback, "conversations")
	quest_definitions = definitions_from_story_catalog(fallback, "quests")
	reset_story_state()


func load_story_catalogs() -> bool:
	var result := StoryCatalog.load_catalogs(campaign_path, campaign)
	if not result.get("ok", false):
		load_error = format_errors(result.get("errors", []))
		push_error("Story catalog load failed: %s" % load_error)
		return false
	conversation_definitions = result.get("conversations", {})
	quest_definitions = result.get("quests", {})
	return true


func definitions_from_story_catalog(catalog: Dictionary, field: String) -> Dictionary:
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


func reset_story_state() -> void:
	quest_progress = StoryModel.initial_progress(campaign, quest_definitions)
	active_conversation_id = ""
	active_node_id = ""
	active_choice_index = 0
	story_journal_open = false
	story_journal_tab = 0
	story_journal_index = 0
	story_notice = ""
	story_notice_timer = 0.0
	dialogue = ""
	evaluate_story_progress()


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	story_journal_open = false
	finish_conversation(false)
	var activated := super.activate_map(map_id, entry_id, requested_era, use_transition)
	if activated:
		evaluate_story_progress()
	return activated


func shift_to_next_era() -> void:
	finish_conversation(false)
	super.shift_to_next_era()
	evaluate_story_progress()


func update_game(delta: float) -> void:
	story_notice_timer = maxf(0.0, story_notice_timer - delta)
	if story_notice_timer <= 0.0:
		story_notice = ""
	if flow == Flow.GAME and story_journal_open:
		update_story_journal()
		return
	if flow == Flow.GAME and not active_conversation_id.is_empty():
		update_active_conversation()
		return
	if (
		flow == Flow.GAME
		and dialogue.is_empty()
		and not inventory_open
		and transition_lock <= 0.45
		and Input.is_action_just_pressed("story_journal")
	):
		open_story_journal()
		return
	super.update_game(delta)
	if flow == Flow.GAME and dialogue.is_empty() and not inventory_open:
		evaluate_story_progress()


func open_story_journal() -> void:
	story_journal_open = true
	story_journal_tab = 0
	story_journal_index = clamp_story_journal_index(story_journal_index)


func close_story_journal() -> void:
	story_journal_open = false


func update_story_journal() -> void:
	if Input.is_action_just_pressed("story_journal") or Input.is_action_just_pressed("ui_cancel"):
		close_story_journal()
		return
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right"):
		story_journal_tab = 1 - story_journal_tab
		story_journal_index = 0
		return
	var entries := journal_quest_ids()
	if entries.is_empty():
		story_journal_index = 0
		return
	if Input.is_action_just_pressed("move_up"):
		story_journal_index = posmod(story_journal_index - 1, entries.size())
	elif Input.is_action_just_pressed("move_down"):
		story_journal_index = posmod(story_journal_index + 1, entries.size())


func journal_quest_ids() -> PackedStringArray:
	if story_journal_tab == 0:
		return StoryModel.active_quest_ids(quest_progress, quest_definitions)
	return StoryModel.completed_quest_ids(quest_progress, quest_definitions)


func clamp_story_journal_index(value: int) -> int:
	return clampi(value, 0, maxi(0, journal_quest_ids().size() - 1))


func interact() -> void:
	var best_index := nearest_story_entity_index()
	if best_index >= 0:
		var entity: Dictionary = runtime_entities[best_index]
		var definition_data: Dictionary = entity.get("definition", {})
		if not authored_requirements_met(definition_data):
			dialogue = authored_blocked_message(definition_data)
			return
		if StoryEncounterModel.kind(entity) == "pickup":
			collect_pickup(best_index)
			return
		var conversation_id := str(definition_data.get("conversation_id", "")).strip_edges()
		if not conversation_id.is_empty() and start_conversation(conversation_id):
			apply_story_effects(StoryCatalog.effects(definition_data, "story_effects"), false)
			return
		dialogue = StoryObjectCatalog.dialogue_for(definition_data, current_era_id)
		return

	var interaction := nearest_map_interaction()
	if interaction.is_empty():
		if companion_enabled():
			dialogue = "%s sniffs the wind, then looks toward the nearest unfinished story." % companion_name().capitalize()
		else:
			dialogue = "Nothing answers yet."
		return
	if not authored_requirements_met(interaction):
		dialogue = authored_blocked_message(interaction)
		return
	if not StoryModel.conditions_met(StoryCatalog.conditions(interaction, "story_conditions"), story_context()):
		dialogue = str(interaction.get("blocked_dialogue", "Nothing changes yet."))
		return
	var conversation_id := str(interaction.get("conversation_id", "")).strip_edges()
	if not conversation_id.is_empty() and start_conversation(conversation_id):
		apply_story_effects(StoryCatalog.effects(interaction, "story_effects"), false)
		return
	apply_story_effects(StoryCatalog.effects(interaction, "story_effects"), true)
	dialogue = dialogue_for(interaction)


func nearest_story_entity_index() -> int:
	var best_index := -1
	var best_distance := INF
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		if not bool(entity.get("active", true)):
			continue
		var kind := StoryEncounterModel.kind(entity)
		if not ["prop", "npc", "pickup"].has(kind):
			continue
		var distance := player.distance_to(entity.get("position", Vector2.ZERO))
		if distance <= StoryEncounterModel.interaction_radius(entity) and distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


func nearest_map_interaction() -> Dictionary:
	var closest: Dictionary = {}
	var closest_distance := INF
	for value in map_data.get("interactions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = value
		if not StoryMapModel.available_in_era(interaction, current_era_id):
			continue
		var position := StoryRepository.data_to_vector(interaction.get("position"))
		var distance := player.distance_to(position)
		if distance <= float(interaction.get("radius", 32.0)) and distance < closest_distance:
			closest = interaction
			closest_distance = distance
	return closest


func start_conversation(conversation_id: String) -> bool:
	var conversation_data := StoryCatalog.conversation(conversation_definitions, conversation_id)
	if conversation_data.is_empty() or not StoryModel.conversation_available(conversation_data, story_context()):
		return false
	active_conversation_id = conversation_id
	active_choice_index = 0
	return enter_story_node(str(conversation_data.get("start_node", "")))


func enter_story_node(node_id: String) -> bool:
	var conversation_data := active_conversation()
	var transitions := 0
	var next_id := node_id
	while transitions < MAX_STORY_TRANSITIONS:
		var node_data := StoryCatalog.node(conversation_data, next_id)
		if node_data.is_empty():
			finish_conversation()
			return false
		if not StoryModel.conditions_met(StoryCatalog.conditions(node_data), story_context()):
			next_id = str(node_data.get("next", node_data.get("fallback", "")))
			if next_id.is_empty():
				finish_conversation()
				return false
			transitions += 1
			continue
		active_node_id = next_id
		active_choice_index = 0
		apply_story_effects(StoryCatalog.effects(node_data), false)
		var kind := str(node_data.get("kind", "line"))
		if kind == "end":
			finish_conversation()
			return true
		if kind == "choice" and active_choices().is_empty():
			set_story_notice("No response is currently available.")
			finish_conversation()
			return false
		refresh_story_dialogue()
		return true
	finish_conversation()
	set_story_notice("Conversation transition limit reached.")
	return false


func active_conversation() -> Dictionary:
	return StoryCatalog.conversation(conversation_definitions, active_conversation_id)


func active_story_node() -> Dictionary:
	return StoryCatalog.node(active_conversation(), active_node_id)


func active_choices() -> Array:
	return StoryModel.available_choices(active_story_node(), story_context())


func refresh_story_dialogue() -> void:
	var node_data := active_story_node()
	if node_data.is_empty():
		dialogue = ""
		return
	if str(node_data.get("kind", "line")) == "choice":
		dialogue = StoryCatalog.choice_prompt(node_data, current_era_id)
	else:
		dialogue = StoryCatalog.node_text(node_data, current_era_id)


func update_active_conversation() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		finish_conversation()
		return
	var node_data := active_story_node()
	if node_data.is_empty():
		finish_conversation()
		return
	var kind := str(node_data.get("kind", "line"))
	if kind == "choice":
		var choices := active_choices()
		if choices.is_empty():
			finish_conversation()
			return
		if Input.is_action_just_pressed("move_up"):
			active_choice_index = posmod(active_choice_index - 1, choices.size())
		elif Input.is_action_just_pressed("move_down"):
			active_choice_index = posmod(active_choice_index + 1, choices.size())
		if confirm() or Input.is_action_just_pressed("attack"):
			active_choice_index = clampi(active_choice_index, 0, choices.size() - 1)
			var choice: Dictionary = choices[active_choice_index]
			apply_story_effects(StoryCatalog.effects(choice), false)
			var next_id := str(choice.get("next", ""))
			if next_id.is_empty():
				finish_conversation()
			else:
				enter_story_node(next_id)
		return
	if confirm() or Input.is_action_just_pressed("attack"):
		var next_id := str(node_data.get("next", ""))
		if next_id.is_empty():
			finish_conversation()
		else:
			enter_story_node(next_id)


func finish_conversation(clear_dialogue: bool = true) -> void:
	active_conversation_id = ""
	active_node_id = ""
	active_choice_index = 0
	if clear_dialogue:
		dialogue = ""


func story_context() -> Dictionary:
	return {
		"map_id": str(map_data.get("id", "")),
		"era_id": current_era_id,
		"inventory": inventory,
		"item_definitions": item_definitions,
		"quest_progress": quest_progress,
		"session_state": session_state,
		"clock_shards": clock_shards
	}


func apply_story_effects(effects: Array, announce: bool = true, evaluate_after: bool = true) -> PackedStringArray:
	var messages := PackedStringArray()
	for value in effects:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = value
		var effect_type := str(effect.get("type", ""))
		match effect_type:
			"start_quest":
				var event := StoryModel.start_quest(quest_progress, quest_definitions, str(effect.get("quest_id", "")))
				append_quest_event_message(event, messages)
			"advance_quest":
				var event := StoryModel.advance_quest(quest_progress, quest_definitions, str(effect.get("quest_id", "")))
				handle_quest_event(event, messages)
			"complete_quest":
				var event := StoryModel.complete_quest(quest_progress, quest_definitions, str(effect.get("quest_id", "")))
				handle_quest_event(event, messages)
			"set_quest_stage":
				var event := StoryModel.set_quest_stage(
					quest_progress,
					quest_definitions,
					str(effect.get("quest_id", "")),
					str(effect.get("stage_id", ""))
				)
				append_quest_event_message(event, messages)
			"set_state":
				session_state[str(effect.get("key", ""))] = effect.get("value")
			"grant_item":
				var item_id := str(effect.get("item_id", ""))
				var result := StoryInventoryModel.add_item(inventory, item_definitions, item_id, int(effect.get("quantity", 0)))
				var added := int(result.get("added", 0))
				if added > 0:
					messages.append("Received %s x%d." % [StoryItemCatalog.item_name(StoryItemCatalog.item(item_definitions, item_id), item_id), added])
			"remove_item":
				var item_id := str(effect.get("item_id", ""))
				var quantity := int(effect.get("quantity", 0))
				if StoryInventoryModel.remove_item(inventory, item_id, quantity):
					messages.append("Used %s x%d." % [StoryItemCatalog.item_name(StoryItemCatalog.item(item_definitions, item_id), item_id), quantity])
			"unlock_recipe":
				var recipe_ids := PackedStringArray([str(effect.get("recipe_id", ""))])
				var unlocked_names := unlock_recipe_ids(recipe_ids)
				if not unlocked_names.is_empty():
					messages.append("Recipe learned: %s." % ", ".join(unlocked_names))
			"grant_clock_shards":
				var amount := maxi(0, int(effect.get("amount", 0)))
				clock_shards += amount
				if amount > 0:
					messages.append("Clock shards +%d." % amount)
			"message":
				var text := str(effect.get("text", "")).strip_edges()
				if not text.is_empty():
					messages.append(text)
			_:
				pass
	if evaluate_after:
		evaluate_story_progress()
	if announce and not messages.is_empty():
		set_story_notice("  ".join(messages))
	return messages


func append_quest_event_message(event: Dictionary, messages: PackedStringArray) -> void:
	if event.is_empty():
		return
	var quest_id := str(event.get("quest_id", ""))
	var event_type := str(event.get("type", ""))
	if event_type == "quest_started":
		messages.append("Quest started: %s." % StoryModel.quest_title(quest_definitions, quest_id))
	elif event_type == "quest_stage_changed":
		messages.append("Objective updated: %s." % StoryModel.current_objective(quest_progress, quest_definitions, quest_id))


func handle_quest_event(event: Dictionary, messages: PackedStringArray) -> void:
	if event.is_empty():
		return
	if str(event.get("type", "")) == "quest_completed":
		var quest_id := str(event.get("quest_id", ""))
		messages.append("Quest completed: %s." % StoryModel.quest_title(quest_definitions, quest_id))
		var rewards_value: Variant = event.get("rewards", [])
		if typeof(rewards_value) == TYPE_ARRAY:
			var reward_messages := apply_story_effects(rewards_value, false, false)
			for reward_message in reward_messages:
				messages.append(reward_message)
	else:
		append_quest_event_message(event, messages)


func evaluate_story_progress() -> void:
	if story_evaluation_lock or quest_definitions.is_empty():
		return
	story_evaluation_lock = true
	var messages := PackedStringArray()
	var rounds := 0
	while rounds < 8:
		var events := StoryModel.evaluate_ready_quests(
			quest_progress,
			quest_definitions,
			story_context(),
			MAX_STORY_TRANSITIONS
		)
		if events.is_empty():
			break
		for event_value in events:
			if typeof(event_value) == TYPE_DICTIONARY:
				handle_quest_event(event_value, messages)
		rounds += 1
	story_evaluation_lock = false
	if not messages.is_empty():
		set_story_notice("  ".join(messages))


func collect_pickup(index: int) -> void:
	if index < 0 or index >= runtime_entities.size() or typeof(runtime_entities[index]) != TYPE_DICTIONARY:
		return
	var entity: Dictionary = runtime_entities[index]
	var state_key := str(entity.get("state_key", ""))
	var was_collected := session_state.has(state_key)
	var definition_data: Dictionary = entity.get("definition", {})
	super.collect_pickup(index)
	if not was_collected and session_state.has(state_key):
		apply_story_effects(StoryCatalog.effects(definition_data, "story_effects"), true)
		evaluate_story_progress()


func reveal_companion_cue(cue: Dictionary) -> void:
	var state_key := StoryCompanionModel.cue_state_key(str(map_data.get("id", "map")), cue)
	var was_discovered := session_state.has(state_key)
	super.reveal_companion_cue(cue)
	if not was_discovered and session_state.has(state_key):
		apply_story_effects(StoryCatalog.effects(cue, "story_effects"), true)
		evaluate_story_progress()


func craft_inventory_recipe(recipe_id: String) -> bool:
	var crafted := super.craft_inventory_recipe(recipe_id)
	if crafted:
		evaluate_story_progress()
	return crafted


func use_inventory_item(item_id: String, quick_use: bool = false) -> bool:
	var used := super.use_inventory_item(item_id, quick_use)
	if used:
		evaluate_story_progress()
	return used


func update_zone_clear_states() -> void:
	var before_size := session_state.size()
	super.update_zone_clear_states()
	if session_state.size() != before_size:
		evaluate_story_progress()


func set_story_notice(message: String, duration: float = STORY_NOTICE_DURATION) -> void:
	story_notice = message
	story_notice_timer = duration


func draw_game() -> void:
	super.draw_game()
	if story_journal_open:
		draw_story_journal_overlay()


func draw_hud(era_data: Dictionary) -> void:
	super.draw_hud(era_data)
	draw_active_quest_tracker()
	if not story_notice.is_empty() and dialogue.is_empty() and not inventory_open and not story_journal_open:
		draw_rect(Rect2(116, 96, 408, 28), Color(0.03, 0.04, 0.05, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(130, 114), story_notice, HORIZONTAL_ALIGNMENT_CENTER, 380, 9, Color("f2dda0"))


func draw_active_quest_tracker() -> void:
	var quest_ids := StoryModel.active_quest_ids(quest_progress, quest_definitions)
	if quest_ids.is_empty() or story_journal_open:
		return
	var quest_id := str(quest_ids[0])
	var title := StoryModel.quest_title(quest_definitions, quest_id)
	var objective := StoryModel.current_objective(quest_progress, quest_definitions, quest_id)
	draw_rect(Rect2(384, 62, 246, 42), Color(0.03, 0.04, 0.05, 0.84))
	draw_string(ThemeDB.fallback_font, Vector2(394, 79), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 226, 9, Color("e9cd7d"))
	draw_string(ThemeDB.fallback_font, Vector2(394, 96), objective, HORIZONTAL_ALIGNMENT_LEFT, 226, 8, Color("c8c5b8"))


func draw_dialogue() -> void:
	if active_conversation_id.is_empty():
		super.draw_dialogue()
		return
	var node_data := active_story_node()
	var kind := str(node_data.get("kind", "line"))
	draw_rect(Rect2(20, 222, 600, 120), Color("0c1117"))
	draw_rect(Rect2(20, 222, 600, 120), Color("d0b978"), false, 2.0)
	if kind == "choice":
		draw_string(ThemeDB.fallback_font, Vector2(38, 246), StoryCatalog.choice_prompt(node_data, current_era_id), HORIZONTAL_ALIGNMENT_LEFT, 560, 12, Color("f1ead8"))
		var choices := active_choices()
		for index in range(mini(4, choices.size())):
			var choice: Dictionary = choices[index]
			var active := index == active_choice_index
			var label := StoryCatalog.resolved_text(choice.get("text", ""), current_era_id, "...")
			draw_string(ThemeDB.fallback_font, Vector2(42, 272 + index * 17), "◆" if active else "", HORIZONTAL_ALIGNMENT_LEFT, 16, 10, Color("e7c66b"))
			draw_string(ThemeDB.fallback_font, Vector2(62, 272 + index * 17), label, HORIZONTAL_ALIGNMENT_LEFT, 535, 10, Color("fff2c9") if active else Color("aeb7b8"))
		return
	var speaker := str(node_data.get("speaker", "")).strip_edges()
	if not speaker.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(38, 244), speaker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 560, 10, Color("e7c66b"))
	draw_text_lines(StoryCatalog.node_text(node_data, current_era_id), Vector2(38, 266), 13, Color("f1ead8"))
	draw_string(ThemeDB.fallback_font, Vector2(482, 330), "CONFIRM  •  ESC CLOSE", HORIZONTAL_ALIGNMENT_LEFT, 120, 8, Color("7f8a90"))


func draw_story_journal_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.01, 0.015, 0.02, 0.92))
	draw_rect(Rect2(38, 30, 564, 300), Color("111820"))
	draw_rect(Rect2(38, 30, 564, 300), Color("75694d"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(58, 58), "JOURNAL", HORIZONTAL_ALIGNMENT_LEFT, 220, 22, Color("f0dfad"))
	draw_string(ThemeDB.fallback_font, Vector2(390, 55), "ACTIVE" if story_journal_tab == 0 else "COMPLETED", HORIZONTAL_ALIGNMENT_LEFT, 170, 12, Color("e7c66b"))
	var ids := journal_quest_ids()
	if ids.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(64, 112), "No quests in this section.", HORIZONTAL_ALIGNMENT_LEFT, 500, 13, Color("87949b"))
		draw_string(ThemeDB.fallback_font, Vector2(64, 310), "J / R3 CLOSE   LEFT / RIGHT TABS", HORIZONTAL_ALIGNMENT_LEFT, 500, 9, Color("68747e"))
		return
	story_journal_index = clampi(story_journal_index, 0, ids.size() - 1)
	var visible_count := mini(STORY_JOURNAL_ROWS, ids.size())
	var start_index := clampi(story_journal_index - 3, 0, maxi(0, ids.size() - visible_count))
	for row in range(visible_count):
		var index := start_index + row
		var quest_id := str(ids[index])
		var active := index == story_journal_index
		var y := 94 + row * 26
		if active:
			draw_rect(Rect2(54, y - 17, 222, 23), Color("26323a"))
		draw_string(ThemeDB.fallback_font, Vector2(62, y), "◆" if active else "", HORIZONTAL_ALIGNMENT_LEFT, 16, 10, Color("e7c66b"))
		draw_string(ThemeDB.fallback_font, Vector2(82, y), StoryModel.quest_title(quest_definitions, quest_id), HORIZONTAL_ALIGNMENT_LEFT, 185, 11, Color("fff2c9") if active else Color("a7b0b3"))
	var selected_id := str(ids[story_journal_index])
	var quest_data := StoryCatalog.quest(quest_definitions, selected_id)
	draw_string(ThemeDB.fallback_font, Vector2(304, 100), str(quest_data.get("title", selected_id)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 270, 14, Color("f1d483"))
	draw_text_lines(str(quest_data.get("summary", "")), Vector2(304, 126), 10, Color("bfc5c4"))
	if story_journal_tab == 0:
		draw_string(ThemeDB.fallback_font, Vector2(304, 214), "CURRENT OBJECTIVE", HORIZONTAL_ALIGNMENT_LEFT, 270, 9, Color("8fa9a5"))
		draw_text_lines(StoryModel.current_objective(quest_progress, quest_definitions, selected_id), Vector2(304, 236), 11, Color("f0ead8"))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(304, 224), "COMPLETED", HORIZONTAL_ALIGNMENT_LEFT, 270, 12, Color("91c6a1"))
	draw_string(ThemeDB.fallback_font, Vector2(64, 310), "J / R3 CLOSE   LEFT / RIGHT TABS   UP / DOWN SELECT", HORIZONTAL_ALIGNMENT_LEFT, 500, 9, Color("68747e"))
