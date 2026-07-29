extends "res://src/save_runtime.gd"

const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const EquipmentValidator = preload("res://src/content/equipment_validator.gd")
const EquipmentModel = preload("res://src/game/equipment_model.gd")
const LoadoutItemCatalog = preload("res://src/content/item_catalog.gd")
const LoadoutEncounterModel = preload("res://src/game/encounter_model.gd")
const LoadoutSaveProfile = preload("res://src/content/save_profile.gd")
const LoadoutSaveStore = preload("res://src/content/save_profile_store.gd")

const LOADOUT_TAB := 2
const LOADOUT_TAB_COUNT := 3
const LOADOUT_NOTICE_DURATION := 1.5
const MIN_PLAYER_SPEED := 40.0
const MAX_PLAYER_SPEED := 260.0

var capability_definitions: Dictionary = {}
var equipped_items: Dictionary = {}


func load_campaign(path: String) -> bool:
	var validation: Dictionary = EquipmentValidator.validate_campaign_path(path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		push_error("Equipment and capability validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	capability_definitions = {}
	equipped_items = {}
	var loaded: bool = super.load_campaign(path)
	if not loaded:
		return false
	if not load_capability_definitions():
		return false
	reset_equipment_state()
	return true


func load_fallback_campaign() -> void:
	capability_definitions = {}
	equipped_items = {}
	super.load_fallback_campaign()
	capability_definitions = definitions_from_capability_catalog(EquipmentCatalog.default_capability_catalog())
	reset_equipment_state()


func load_capability_definitions() -> bool:
	if campaign_path.is_empty():
		capability_definitions = definitions_from_capability_catalog(EquipmentCatalog.default_capability_catalog())
		return true
	var result: Dictionary = EquipmentCatalog.load_capability_catalogs(campaign_path, campaign)
	if not bool(result.get("ok", false)):
		load_error = format_errors(result.get("errors", []))
		push_error("Capability catalog load failed: %s" % load_error)
		return false
	capability_definitions = result.get("definitions", {})
	return true


func definitions_from_capability_catalog(catalog: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	var value: Variant = catalog.get("capabilities", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for capability_value in value:
		if typeof(capability_value) != TYPE_DICTIONARY:
			continue
		var capability_data: Dictionary = capability_value
		var capability_id: String = str(capability_data.get("id", ""))
		if not capability_id.is_empty():
			output[capability_id] = capability_data
	return output


func reset_equipment_state() -> void:
	equipped_items = EquipmentModel.initial_equipment(campaign, inventory, item_definitions)
	player_health = actor_health("player", 32)
	inventory_tab = clampi(inventory_tab, 0, LOADOUT_TAB_COUNT - 1)
	inventory_index = 0
	last_durable_fingerprint = durable_progress_fingerprint()


func active_capabilities() -> PackedStringArray:
	return EquipmentModel.active_capabilities(campaign, equipped_items, item_definitions)


func story_context() -> Dictionary:
	var context: Dictionary = super.story_context()
	context["capabilities"] = active_capabilities()
	context["equipment"] = equipped_items.duplicate(true)
	return context


func authored_requirements_met(record: Dictionary) -> bool:
	return EquipmentModel.requirements_met(record, active_capabilities())


func authored_blocked_message(record: Dictionary) -> String:
	var authored: String = str(record.get("blocked_dialogue", "")).strip_edges()
	if not authored.is_empty():
		return authored
	var missing: PackedStringArray = EquipmentModel.missing_capabilities(record, active_capabilities())
	if missing.is_empty():
		return super.authored_blocked_message(record)
	var names := PackedStringArray()
	for capability_id in missing:
		names.append(EquipmentCatalog.capability_name(capability_definitions, capability_id))
	return "Required: %s." % ", ".join(names)


func player_move_speed_value() -> float:
	return clampf(
		super.player_move_speed_value()
		+ EquipmentModel.modifier_total(equipped_items, item_definitions, "move_speed_bonus"),
		MIN_PLAYER_SPEED,
		MAX_PLAYER_SPEED
	)


func actor_health(actor_id: String, fallback: int) -> int:
	var maximum: int = super.actor_health(actor_id, fallback)
	if actor_id == "player":
		maximum += int(EquipmentModel.modifier_total(equipped_items, item_definitions, "max_health_bonus"))
	return maxi(1, maximum)


func player_attack_damage_value() -> int:
	return maxi(
		1,
		PLAYER_ATTACK_DAMAGE
		+ int(EquipmentModel.modifier_total(equipped_items, item_definitions, "attack_bonus"))
	)


func player_defense_value() -> int:
	return maxi(0, int(EquipmentModel.modifier_total(equipped_items, item_definitions, "defense_bonus")))


func perform_player_attack() -> void:
	player_attack_lock = PLAYER_ATTACK_COOLDOWN
	player_attack_timer = 0.17
	var target_index: int = LoadoutEncounterModel.nearest_facing_enemy_index(
		runtime_entities,
		player,
		facing,
		PLAYER_ATTACK_RANGE
	)
	if target_index >= 0:
		damage_entity(target_index, player_attack_damage_value(), player_name())


func damage_actor(actor_id: String, amount: int, attacker: Dictionary) -> void:
	var resolved_amount: int = amount
	if actor_id == "player":
		resolved_amount = maxi(1, amount - player_defense_value())
	super.damage_actor(actor_id, resolved_amount, attacker)


func open_inventory() -> void:
	super.open_inventory()
	inventory_tab = clampi(inventory_tab, 0, LOADOUT_TAB_COUNT - 1)


func update_inventory_overlay() -> void:
	if Input.is_action_just_pressed("inventory_toggle") or Input.is_action_just_pressed("ui_cancel"):
		close_inventory()
		return
	if Input.is_action_just_pressed("move_left"):
		inventory_tab = posmod(inventory_tab - 1, LOADOUT_TAB_COUNT)
		inventory_index = 0
		return
	if Input.is_action_just_pressed("move_right"):
		inventory_tab = posmod(inventory_tab + 1, LOADOUT_TAB_COUNT)
		inventory_index = 0
		return
	var entry_count: int = current_inventory_entry_count()
	if entry_count > 0:
		if Input.is_action_just_pressed("move_up"):
			inventory_index = posmod(inventory_index - 1, entry_count)
		elif Input.is_action_just_pressed("move_down"):
			inventory_index = posmod(inventory_index + 1, entry_count)
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("attack"):
		activate_inventory_selection()


func current_inventory_entry_count() -> int:
	if inventory_tab == LOADOUT_TAB:
		return EquipmentCatalog.slot_ids(campaign).size()
	return super.current_inventory_entry_count()


func activate_inventory_selection() -> void:
	if inventory_tab != LOADOUT_TAB:
		super.activate_inventory_selection()
		return
	var slots: PackedStringArray = EquipmentCatalog.slot_ids(campaign)
	if slots.is_empty():
		set_inventory_notice("This campaign has no equipment slots.")
		return
	inventory_index = clampi(inventory_index, 0, slots.size() - 1)
	cycle_equipment_slot(str(slots[inventory_index]))


func use_inventory_item(item_id: String, quick_use: bool = false) -> bool:
	var item_data: Dictionary = LoadoutItemCatalog.item(item_definitions, item_id)
	if LoadoutItemCatalog.item_kind(item_data) == "equipment":
		if quick_use:
			return false
		return equip_specific_item(item_id)
	var before_max: int = actor_health("player", 32)
	var used: bool = super.use_inventory_item(item_id, quick_use)
	if used:
		sanitize_loadout_after_inventory_change(before_max)
	return used


func craft_inventory_recipe(recipe_id: String) -> bool:
	var before_max: int = actor_health("player", 32)
	var crafted: bool = super.craft_inventory_recipe(recipe_id)
	if crafted:
		sanitize_loadout_after_inventory_change(before_max)
	return crafted


func apply_story_effects(effects: Array, announce: bool = true, evaluate_after: bool = true) -> PackedStringArray:
	var before_max: int = actor_health("player", 32)
	var messages: PackedStringArray = super.apply_story_effects(effects, announce, evaluate_after)
	sanitize_loadout_after_inventory_change(before_max)
	return messages


func equip_specific_item(item_id: String) -> bool:
	var item_data: Dictionary = LoadoutItemCatalog.item(item_definitions, item_id)
	var slot_id: String = EquipmentCatalog.equipment_slot(item_data)
	if slot_id.is_empty():
		set_inventory_notice("That item has no equipment slot.")
		return false
	var before_max: int = actor_health("player", 32)
	var result: Dictionary = EquipmentModel.equip_item(
		equipped_items,
		slot_id,
		item_id,
		inventory,
		item_definitions,
		campaign
	)
	if not bool(result.get("ok", false)):
		set_inventory_notice("That item cannot be equipped here.")
		return false
	apply_max_health_change(before_max)
	set_inventory_notice("Equipped %s." % LoadoutItemCatalog.item_name(item_data, item_id))
	evaluate_story_progress()
	last_durable_fingerprint = durable_progress_fingerprint()
	return true


func cycle_equipment_slot(slot_id: String) -> bool:
	var before_max: int = actor_health("player", 32)
	var result: Dictionary = EquipmentModel.cycle_slot(
		equipped_items,
		slot_id,
		inventory,
		item_definitions,
		campaign
	)
	if not bool(result.get("ok", false)):
		set_inventory_notice("No compatible item is available for %s." % EquipmentCatalog.slot_name(campaign, slot_id))
		return false
	apply_max_health_change(before_max)
	var item_id: String = str(result.get("item_id", ""))
	if item_id.is_empty():
		set_inventory_notice("%s cleared." % EquipmentCatalog.slot_name(campaign, slot_id))
	else:
		var item_data: Dictionary = LoadoutItemCatalog.item(item_definitions, item_id)
		set_inventory_notice("Equipped %s." % LoadoutItemCatalog.item_name(item_data, item_id))
	evaluate_story_progress()
	last_durable_fingerprint = durable_progress_fingerprint()
	return true


func sanitize_loadout_after_inventory_change(before_max: int = -1) -> void:
	var previous_max: int = actor_health("player", 32) if before_max < 0 else before_max
	equipped_items = EquipmentModel.sanitize_equipment(equipped_items, campaign, inventory, item_definitions)
	apply_max_health_change(previous_max)


func apply_max_health_change(previous_max: int) -> void:
	var next_max: int = actor_health("player", 32)
	if next_max > previous_max:
		player_health += next_max - previous_max
	else:
		player_health = mini(player_health, next_max)
	player_health = maxi(1, player_health)


func draw_connections() -> void:
	super.draw_connections()
	for value in map_data.get("connections", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = value
		if not MapModel.available_in_era(connection, current_era_id):
			continue
		if EquipmentCatalog.required_capabilities(connection).is_empty() or authored_requirements_met(connection):
			continue
		var position: Vector2 = CampaignRepository.data_to_vector(connection.get("position"))
		draw_circle(position, 10.0, Color(0.38, 0.12, 0.1, 0.82), false, 2.0)
		draw_line(position + Vector2(-5, -5), position + Vector2(5, 5), Color("f08c74"), 2.0)
		draw_line(position + Vector2(5, -5), position + Vector2(-5, 5), Color("f08c74"), 2.0)


func draw_inventory_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.015, 0.02, 0.027, 0.92))
	draw_rect(Rect2(34, 24, 572, 312), Color("10161d"))
	draw_rect(Rect2(34, 24, 572, 312), Color("d2bd78"), false, 2.0)
	draw_centered("FIELD SATCHEL", 50, 18, Color("f2dfaa"))
	var labels := ["ITEMS", "RECIPES", "EQUIPMENT"]
	var xs := [58, 140, 235]
	for index in range(labels.size()):
		var color := Color("f2d77f") if inventory_tab == index else Color("78858f")
		draw_string(ThemeDB.fallback_font, Vector2(xs[index], 72), labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
	draw_string(ThemeDB.fallback_font, Vector2(430, 72), "I / BACK CLOSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("89959d"))
	match inventory_tab:
		0:
			draw_item_inventory_tab()
		1:
			draw_recipe_inventory_tab()
		_:
			draw_equipment_inventory_tab()
	if not inventory_notice.is_empty():
		draw_rect(Rect2(86, 298, 468, 24), Color(0.03, 0.04, 0.05, 0.9))
		draw_centered(inventory_notice, 315, 9, Color("f0d58a"))


func draw_equipment_inventory_tab() -> void:
	var slots: PackedStringArray = EquipmentCatalog.slot_ids(campaign)
	inventory_index = clampi(inventory_index, 0, maxi(0, slots.size() - 1))
	if slots.is_empty():
		draw_centered("NO EQUIPMENT SLOTS", 178, 12, Color("89959d"))
		return
	for row in range(slots.size()):
		var slot_id: String = str(slots[row])
		var selected := row == inventory_index
		if selected:
			draw_rect(Rect2(58, 92 + row * 38, 252, 32), Color(0.22, 0.19, 0.11, 0.9))
		var item_id: String = str(equipped_items.get(slot_id, ""))
		var item_name := "Empty"
		if not item_id.is_empty():
			item_name = LoadoutItemCatalog.item_name(LoadoutItemCatalog.item(item_definitions, item_id), item_id)
		draw_string(ThemeDB.fallback_font, Vector2(66, 108 + row * 38), "◆" if selected else "", HORIZONTAL_ALIGNMENT_LEFT, 16, 10, Color("e7c66b"))
		draw_string(ThemeDB.fallback_font, Vector2(84, 106 + row * 38), EquipmentCatalog.slot_name(campaign, slot_id).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 90, 9, Color("8fa9a5"))
		draw_string(ThemeDB.fallback_font, Vector2(84, 119 + row * 38), item_name, HORIZONTAL_ALIGNMENT_LEFT, 210, 10, Color("fff2c9") if selected else Color("b9b7aa"))
	var selected_slot: String = str(slots[inventory_index])
	var selected_item: String = str(equipped_items.get(selected_slot, ""))
	draw_rect(Rect2(330, 88, 244, 190), Color("0b1117"))
	draw_string(ThemeDB.fallback_font, Vector2(346, 111), EquipmentCatalog.slot_name(campaign, selected_slot).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 210, 12, Color("e7c66b"))
	if selected_item.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(346, 145), "EMPTY", HORIZONTAL_ALIGNMENT_LEFT, 210, 13, Color("78858f"))
	else:
		var item_data: Dictionary = LoadoutItemCatalog.item(item_definitions, selected_item)
		var equipment_data: Dictionary = EquipmentCatalog.equipment_data(item_data)
		draw_string(ThemeDB.fallback_font, Vector2(346, 139), LoadoutItemCatalog.item_name(item_data, selected_item), HORIZONTAL_ALIGNMENT_LEFT, 210, 13, Color("f1d483"))
		draw_text_lines(str(item_data.get("description", "")), Vector2(346, 160), 9, Color("bfc5c4"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 217), "ATK +%d   DEF +%d   HP +%d" % [int(equipment_data.get("attack_bonus", 0)), int(equipment_data.get("defense_bonus", 0)), int(equipment_data.get("max_health_bonus", 0))], HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color("c8c5b8"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 235), "SPEED +%d" % int(equipment_data.get("move_speed_bonus", 0)), HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color("c8c5b8"))
		var capability_names := PackedStringArray()
		for capability_id in EquipmentCatalog.granted_capabilities(item_data):
			capability_names.append(EquipmentCatalog.capability_name(capability_definitions, capability_id))
		if not capability_names.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(346, 255), ", ".join(capability_names), HORIZONTAL_ALIGNMENT_LEFT, 210, 8, Color("8fc6aa"))
	draw_string(ThemeDB.fallback_font, Vector2(60, 282), "CONFIRM CYCLES OWNED GEAR AND EMPTY", HORIZONTAL_ALIGNMENT_LEFT, 500, 8, Color("7f8a90"))


func draw_hud(era_data: Dictionary) -> void:
	super.draw_hud(era_data)
	var attack: int = player_attack_damage_value()
	var defense: int = player_defense_value()
	draw_rect(Rect2(288, 9, 116, 24), Color(0.03, 0.04, 0.05, 0.84))
	draw_string(ThemeDB.fallback_font, Vector2(296, 25), "ATK %d  DEF %d" % [attack, defense], HORIZONTAL_ALIGNMENT_LEFT, 104, 9, Color("d8c98f"))


func capture_save_profile(slot_id: String, reason: String = "Manual save") -> Dictionary:
	var profile: Dictionary = super.capture_save_profile(slot_id, reason)
	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) == TYPE_DICTIONARY:
		var payload: Dictionary = payload_value
		payload["equipment"] = equipped_items.duplicate(true)
		profile["payload"] = payload
		LoadoutSaveProfile.refresh_checksum(profile)
	return profile


func save_current_profile(slot_id: String, reason: String) -> bool:
	if save_operation_depth > 0:
		return false
	var profile: Dictionary = capture_save_profile(slot_id, reason)
	var validation: Dictionary = EquipmentValidator.validate_profile(profile, campaign_path)
	if not bool(validation.get("ok", false)):
		set_save_notice("Save validation failed: %s" % format_errors(validation.get("errors", [])), 2.4)
		return false
	var result: Dictionary = LoadoutSaveStore.write_profile(profile)
	if not bool(result.get("ok", false)):
		set_save_notice("Save failed: %s" % format_errors(result.get("errors", [])), 2.4)
		return false
	current_save_slot = slot_id
	pending_autosave_reason = ""
	last_durable_fingerprint = durable_progress_fingerprint()
	refresh_save_slot_cache()
	refresh_continue_profile()
	set_save_notice("%s SAVED" % LoadoutSaveProfile.slot_label(slot_id))
	return true


func apply_save_profile(profile: Dictionary, target_campaign_path: String) -> bool:
	var validation: Dictionary = EquipmentValidator.validate_profile(profile, target_campaign_path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		set_save_notice("Profile rejected: %s" % load_error, 2.6)
		return false
	capability_definitions = {}
	equipped_items = {}
	var loaded: bool = super.apply_save_profile(profile, target_campaign_path)
	if not loaded:
		return false
	if not load_capability_definitions():
		return false
	var payload: Dictionary = profile.get("payload", {})
	var equipment_value: Variant = payload.get("equipment", {})
	var requested: Dictionary = equipment_value if typeof(equipment_value) == TYPE_DICTIONARY else {}
	equipped_items = EquipmentModel.sanitize_equipment(requested, campaign, inventory, item_definitions)
	player_health = mini(player_health, actor_health("player", 32))
	evaluate_story_progress()
	last_durable_fingerprint = durable_progress_fingerprint()
	return true


func durable_progress_fingerprint() -> String:
	return LoadoutSaveProfile.canonical_json({
		"base": super.durable_progress_fingerprint(),
		"equipment": equipped_items
	})
