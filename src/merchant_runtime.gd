extends "res://src/equipment_runtime.gd"

const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const EconomyValidator = preload("res://src/content/economy_validator.gd")
const EconomyModel = preload("res://src/game/economy_model.gd")
const MerchantItemCatalog = preload("res://src/content/item_catalog.gd")
const MerchantInventoryModel = preload("res://src/game/inventory_model.gd")
const MerchantEncounterModel = preload("res://src/game/encounter_model.gd")
const MerchantStoryCatalog = preload("res://src/content/story_catalog.gd")
const MerchantSaveProfile = preload("res://src/content/save_profile.gd")
const MerchantSaveStore = preload("res://src/content/save_profile_store.gd")

const MERCHANT_NOTICE_DURATION := 1.5
const MERCHANT_ROWS := 8

var currency_definitions: Dictionary = {}
var merchant_definitions: Dictionary = {}
var currency_balances: Dictionary = {}
var merchant_stock: Dictionary = {}
var economy_initialized := false
var merchant_open := false
var active_merchant_id := ""
var merchant_mode := 0
var merchant_index := 0
var merchant_notice := ""
var merchant_notice_timer := 0.0


func load_campaign(path: String) -> bool:
	var validation := EconomyValidator.validate_campaign_path(path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		push_error("Merchant and economy validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	currency_definitions = {}
	merchant_definitions = {}
	currency_balances = {}
	merchant_stock = {}
	economy_initialized = false
	var loaded := super.load_campaign(path)
	if not loaded:
		return false
	if not load_economy_catalogs():
		return false
	reset_economy_state()
	return true


func load_fallback_campaign() -> void:
	currency_definitions = {}
	merchant_definitions = {}
	currency_balances = {}
	merchant_stock = {}
	economy_initialized = false
	super.load_fallback_campaign()
	var fallback := EconomyCatalog.default_catalog()
	currency_definitions = definitions_from_economy_catalog(fallback, "currencies")
	merchant_definitions = definitions_from_economy_catalog(fallback, "merchants")
	reset_economy_state()


func load_economy_catalogs() -> bool:
	if campaign_path.is_empty():
		var fallback := EconomyCatalog.default_catalog()
		currency_definitions = definitions_from_economy_catalog(fallback, "currencies")
		merchant_definitions = definitions_from_economy_catalog(fallback, "merchants")
		return true
	var result := EconomyCatalog.load_catalogs(campaign_path, campaign)
	if not bool(result.get("ok", false)):
		load_error = format_errors(result.get("errors", []))
		push_error("Economy catalog load failed: %s" % load_error)
		return false
	currency_definitions = result.get("currencies", {})
	merchant_definitions = result.get("merchants", {})
	return true


func definitions_from_economy_catalog(catalog: Dictionary, field: String) -> Dictionary:
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


func reset_economy_state() -> void:
	currency_balances = EconomyModel.initial_balances(currency_definitions)
	merchant_stock = EconomyModel.initial_stock(merchant_definitions)
	economy_initialized = true
	close_merchant(false)
	last_durable_fingerprint = durable_progress_fingerprint()


func story_context() -> Dictionary:
	var context := super.story_context()
	context["currency_balances"] = currency_balances
	context["currency_definitions"] = currency_definitions
	return context


func apply_story_effects(effects: Array, announce: bool = true, evaluate_after: bool = true) -> PackedStringArray:
	var messages := super.apply_story_effects(effects, false, false)
	for value in effects:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = value
		var effect_type := str(effect.get("type", ""))
		var currency_id := str(effect.get("currency_id", ""))
		var amount := int(effect.get("amount", 0))
		if effect_type == "grant_currency":
			var result := EconomyModel.add_currency(currency_balances, currency_definitions, currency_id, amount)
			var added := int(result.get("added", 0))
			if added > 0:
				messages.append("%s +%d." % [EconomyCatalog.currency_name(currency_definitions, currency_id), added])
		elif effect_type == "remove_currency":
			if EconomyModel.remove_currency(currency_balances, currency_id, amount):
				messages.append("Paid %s %d." % [EconomyCatalog.currency_symbol(currency_definitions, currency_id), amount])
	if evaluate_after:
		evaluate_story_progress()
	if announce and not messages.is_empty():
		set_story_notice("  ".join(messages))
	return messages


func update_game(delta: float) -> void:
	merchant_notice_timer = maxf(0.0, merchant_notice_timer - delta)
	if merchant_notice_timer <= 0.0:
		merchant_notice = ""
	if flow == Flow.GAME and merchant_open:
		update_merchant_overlay()
		return
	super.update_game(delta)


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	close_merchant(false)
	return super.activate_map(map_id, entry_id, requested_era, use_transition)


func shift_to_next_era() -> void:
	close_merchant(false)
	super.shift_to_next_era()


func can_open_save_overlay() -> bool:
	return not merchant_open and super.can_open_save_overlay()


func can_flush_autosave() -> bool:
	return not merchant_open and super.can_flush_autosave()


func interact() -> void:
	var best_index := nearest_story_entity_index()
	if best_index >= 0 and best_index < runtime_entities.size():
		var entity: Dictionary = runtime_entities[best_index]
		var definition_data: Dictionary = entity.get("definition", {})
		var merchant_id := str(definition_data.get("merchant_id", "")).strip_edges()
		if not merchant_id.is_empty():
			if not authored_requirements_met(definition_data):
				dialogue = authored_blocked_message(definition_data)
				return
			var merchant_data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
			if merchant_data.is_empty():
				dialogue = "This trader has no valid economy record."
				return
			if not EconomyModel.merchant_available(merchant_data, story_context()):
				dialogue = str(definition_data.get("merchant_blocked_dialogue", "The trader is not ready to exchange goods yet."))
				return
			open_merchant(merchant_id)
			return
	super.interact()


func open_merchant(merchant_id: String) -> bool:
	var merchant_data := EconomyCatalog.merchant(merchant_definitions, merchant_id)
	if merchant_data.is_empty() or not EconomyModel.merchant_available(merchant_data, story_context()):
		return false
	finish_conversation(false)
	inventory_open = false
	story_journal_open = false
	save_overlay_open = false
	dialogue = ""
	merchant_open = true
	active_merchant_id = merchant_id
	merchant_mode = 0
	merchant_index = 0
	merchant_notice = str(merchant_data.get("greeting", "Browse the available goods."))
	merchant_notice_timer = MERCHANT_NOTICE_DURATION
	return true


func close_merchant(show_farewell: bool = true) -> void:
	if show_farewell and merchant_open:
		var merchant_data := active_merchant()
		var farewell := str(merchant_data.get("farewell", "Safe travels.")).strip_edges()
		if not farewell.is_empty():
			set_combat_text(farewell, 1.2)
	merchant_open = false
	active_merchant_id = ""
	merchant_mode = 0
	merchant_index = 0
	merchant_notice = ""
	merchant_notice_timer = 0.0


func update_merchant_overlay() -> void:
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("inventory_toggle"):
		close_merchant(true)
		return
	if Input.is_action_just_pressed("move_left"):
		merchant_mode = 0
		merchant_index = 0
		return
	if Input.is_action_just_pressed("move_right"):
		merchant_mode = 1
		merchant_index = 0
		return
	var ids := merchant_entry_ids()
	if ids.is_empty():
		merchant_index = 0
	else:
		if Input.is_action_just_pressed("move_up"):
			merchant_index = posmod(merchant_index - 1, ids.size())
		elif Input.is_action_just_pressed("move_down"):
			merchant_index = posmod(merchant_index + 1, ids.size())
		merchant_index = clampi(merchant_index, 0, ids.size() - 1)
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("attack"):
		activate_merchant_selection()


func active_merchant() -> Dictionary:
	return EconomyCatalog.merchant(merchant_definitions, active_merchant_id)


func merchant_entry_ids() -> PackedStringArray:
	if active_merchant_id.is_empty():
		return PackedStringArray()
	if merchant_mode == 0:
		return EconomyModel.available_stock_ids(
			active_merchant_id,
			merchant_stock,
			merchant_definitions,
			item_definitions,
			story_context()
		)
	return EconomyModel.sellable_inventory_ids(
		active_merchant_id,
		inventory,
		merchant_definitions,
		item_definitions,
		protected_equipment_ids()
	)


func protected_equipment_ids() -> PackedStringArray:
	var output := PackedStringArray()
	for item_value in equipped_items.values():
		var item_id := str(item_value)
		if not item_id.is_empty() and not output.has(item_id):
			output.append(item_id)
	return output


func activate_merchant_selection() -> bool:
	var ids := merchant_entry_ids()
	if ids.is_empty():
		set_merchant_notice("Nothing is available in this section.")
		return false
	merchant_index = clampi(merchant_index, 0, ids.size() - 1)
	var item_id := str(ids[merchant_index])
	var before_max := actor_health("player", 32)
	var result: Dictionary
	if merchant_mode == 0:
		result = EconomyModel.buy_item(
			currency_balances,
			merchant_stock,
			inventory,
			currency_definitions,
			merchant_definitions,
			item_definitions,
			active_merchant_id,
			item_id,
			1,
			story_context()
		)
	else:
		result = EconomyModel.sell_item(
			currency_balances,
			merchant_stock,
			inventory,
			currency_definitions,
			merchant_definitions,
			item_definitions,
			active_merchant_id,
			item_id,
			1,
			protected_equipment_ids(),
			story_context()
		)
	if not bool(result.get("ok", false)):
		set_merchant_notice(transaction_failure_message(str(result.get("reason", "transaction_failed"))))
		return false
	sanitize_loadout_after_inventory_change(before_max)
	var item_data := MerchantItemCatalog.item(item_definitions, item_id)
	var item_name := MerchantItemCatalog.item_name(item_data, item_id)
	var symbol := EconomyCatalog.currency_symbol(currency_definitions, str(result.get("currency_id", "")))
	if merchant_mode == 0:
		set_merchant_notice("Bought %s for %s %d." % [item_name, symbol, int(result.get("total", 0))])
	else:
		set_merchant_notice("Sold %s for %s %d." % [item_name, symbol, int(result.get("total", 0))])
	merchant_index = clampi(merchant_index, 0, maxi(0, merchant_entry_ids().size() - 1))
	evaluate_story_progress()
	last_durable_fingerprint = durable_progress_fingerprint()
	return true


func transaction_failure_message(reason: String) -> String:
	match reason:
		"insufficient_funds":
			return "You do not have enough currency."
		"out_of_stock", "stock_unavailable":
			return "That item is out of stock."
		"stack_full":
			return "Your item stack cannot hold another."
		"merchant_refuses", "not_for_sale":
			return "The merchant refuses that item."
		"equipped_item":
			return "Unequip that item before selling it."
		"wallet_full":
			return "Your wallet cannot hold the full payment."
		"not_owned":
			return "You do not own that item."
		"merchant_unavailable":
			return "The merchant is unavailable."
		_:
			return "The transaction could not be completed."


func set_merchant_notice(message: String, duration: float = MERCHANT_NOTICE_DURATION) -> void:
	merchant_notice = message
	merchant_notice_timer = duration


func primary_currency_id() -> String:
	if merchant_open:
		var active_id := EconomyCatalog.merchant_currency_id(active_merchant())
		if currency_definitions.has(active_id):
			return active_id
	var ids: Array[String] = []
	for currency_id_value in currency_definitions.keys():
		ids.append(str(currency_id_value))
	ids.sort()
	return ids[0] if not ids.is_empty() else ""


func draw_game() -> void:
	super.draw_game()
	if merchant_open:
		draw_merchant_overlay()


func draw_hud(era_data: Dictionary) -> void:
	super.draw_hud(era_data)
	var currency_id := primary_currency_id()
	if currency_id.is_empty():
		return
	var symbol := EconomyCatalog.currency_symbol(currency_definitions, currency_id)
	draw_rect(Rect2(288, 36, 116, 21), Color(0.03, 0.04, 0.05, 0.84))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(296, 51),
		"%s %d" % [symbol, EconomyModel.balance(currency_balances, currency_id)],
		HORIZONTAL_ALIGNMENT_LEFT,
		104,
		9,
		Color("d8c98f")
	)


func draw_merchant_overlay() -> void:
	var merchant_data := active_merchant()
	var currency_id := EconomyCatalog.merchant_currency_id(merchant_data)
	var symbol := EconomyCatalog.currency_symbol(currency_definitions, currency_id)
	var ids := merchant_entry_ids()
	merchant_index = clampi(merchant_index, 0, maxi(0, ids.size() - 1))
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.01, 0.015, 0.02, 0.94))
	draw_rect(Rect2(34, 22, 572, 316), Color("10161d"))
	draw_rect(Rect2(34, 22, 572, 316), Color("8b7550"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(52, 50), str(merchant_data.get("display_name", active_merchant_id)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 330, 19, Color("f2dfaa"))
	draw_string(ThemeDB.fallback_font, Vector2(440, 48), "%s %d" % [symbol, EconomyModel.balance(currency_balances, currency_id)], HORIZONTAL_ALIGNMENT_LEFT, 140, 13, Color("e7c66b"))
	var buy_color := Color("f2d77f") if merchant_mode == 0 else Color("78858f")
	var sell_color := Color("f2d77f") if merchant_mode == 1 else Color("78858f")
	draw_string(ThemeDB.fallback_font, Vector2(60, 76), "BUY", HORIZONTAL_ALIGNMENT_LEFT, 60, 11, buy_color)
	draw_string(ThemeDB.fallback_font, Vector2(126, 76), "SELL", HORIZONTAL_ALIGNMENT_LEFT, 60, 11, sell_color)
	if ids.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(60, 126), "NO ITEMS AVAILABLE", HORIZONTAL_ALIGNMENT_LEFT, 240, 12, Color("7f8a90"))
	else:
		var visible_count := mini(MERCHANT_ROWS, ids.size())
		var start := clampi(merchant_index - 3, 0, maxi(0, ids.size() - visible_count))
		for row in range(visible_count):
			var index := start + row
			var item_id := str(ids[index])
			var item_data := MerchantItemCatalog.item(item_definitions, item_id)
			var selected := index == merchant_index
			var y := 103 + row * 24
			if selected:
				draw_rect(Rect2(52, y - 17, 264, 22), Color(0.22, 0.19, 0.11, 0.9))
			draw_string(ThemeDB.fallback_font, Vector2(58, y), "◆" if selected else "", HORIZONTAL_ALIGNMENT_LEFT, 16, 10, Color("e7c66b"))
			draw_string(ThemeDB.fallback_font, Vector2(78, y), MerchantItemCatalog.item_name(item_data, item_id), HORIZONTAL_ALIGNMENT_LEFT, 150, 10, Color("fff2c9") if selected else Color("b9b7aa"))
			var entry := EconomyCatalog.stock_entry(merchant_data, item_id)
			var price := EconomyModel.buy_price(item_data, merchant_data, entry) if merchant_mode == 0 else EconomyModel.sell_price(item_data, merchant_data, entry)
			draw_string(ThemeDB.fallback_font, Vector2(234, y), "%s %d" % [symbol, price], HORIZONTAL_ALIGNMENT_RIGHT, 70, 9, Color("d8c98f"))
			if merchant_mode == 0:
				var quantity := EconomyModel.stock_quantity(merchant_stock, active_merchant_id, item_id)
				draw_string(ThemeDB.fallback_font, Vector2(280, y), "∞" if quantity < 0 else "x%d" % quantity, HORIZONTAL_ALIGNMENT_RIGHT, 28, 8, Color("7f939b"))
	var detail_rect := Rect2(330, 82, 248, 194)
	draw_rect(detail_rect, Color("0b1117"))
	if not ids.is_empty():
		var item_id := str(ids[merchant_index])
		var item_data := MerchantItemCatalog.item(item_definitions, item_id)
		draw_string(ThemeDB.fallback_font, Vector2(346, 108), MerchantItemCatalog.item_name(item_data, item_id), HORIZONTAL_ALIGNMENT_LEFT, 216, 13, Color("f1d483"))
		draw_text_lines(str(item_data.get("description", "")), Vector2(346, 132), 9, Color("bfc5c4"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 215), "OWNED  x%d" % MerchantInventoryModel.count(inventory, item_id), HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color("8fa9a5"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 235), "KIND  %s" % MerchantItemCatalog.item_kind(item_data).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color("8fa9a5"))
		if protected_equipment_ids().has(item_id):
			draw_string(ThemeDB.fallback_font, Vector2(346, 257), "CURRENTLY EQUIPPED", HORIZONTAL_ALIGNMENT_LEFT, 210, 8, Color("d78f84"))
	if not merchant_notice.is_empty():
		draw_rect(Rect2(76, 288, 488, 24), Color(0.03, 0.04, 0.05, 0.9))
		draw_centered(merchant_notice, 305, 9, Color("f0d58a"))
	draw_string(ThemeDB.fallback_font, Vector2(58, 328), "LEFT / RIGHT MODE   UP / DOWN SELECT   CONFIRM TRADE   ESC CLOSE", HORIZONTAL_ALIGNMENT_LEFT, 520, 8, Color("68747e"))


func capture_save_profile(slot_id: String, reason: String = "Manual save") -> Dictionary:
	var profile := super.capture_save_profile(slot_id, reason)
	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) == TYPE_DICTIONARY:
		var payload: Dictionary = payload_value
		payload["currency_balances"] = currency_balances.duplicate(true)
		payload["merchant_stock"] = merchant_stock.duplicate(true)
		payload["economy_initialized"] = true
		profile["payload"] = payload
		MerchantSaveProfile.refresh_checksum(profile)
	return profile


func save_current_profile(slot_id: String, reason: String) -> bool:
	if save_operation_depth > 0:
		return false
	var profile := capture_save_profile(slot_id, reason)
	var validation := EconomyValidator.validate_profile(profile, campaign_path)
	if not bool(validation.get("ok", false)):
		set_save_notice("Save validation failed: %s" % format_errors(validation.get("errors", [])), 2.4)
		return false
	var result := MerchantSaveStore.write_profile(profile)
	if not bool(result.get("ok", false)):
		set_save_notice("Save failed: %s" % format_errors(result.get("errors", [])), 2.4)
		return false
	current_save_slot = slot_id
	pending_autosave_reason = ""
	last_durable_fingerprint = durable_progress_fingerprint()
	refresh_save_slot_cache()
	refresh_continue_profile()
	set_save_notice("%s SAVED" % MerchantSaveProfile.slot_label(slot_id))
	return true


func apply_save_profile(profile: Dictionary, target_campaign_path: String) -> bool:
	var validation := EconomyValidator.validate_profile(profile, target_campaign_path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		set_save_notice("Profile rejected: %s" % load_error, 2.6)
		return false
	currency_definitions = {}
	merchant_definitions = {}
	currency_balances = {}
	merchant_stock = {}
	economy_initialized = false
	var loaded := super.apply_save_profile(profile, target_campaign_path)
	if not loaded:
		return false
	if not load_economy_catalogs():
		return false
	var payload: Dictionary = profile.get("payload", {})
	var initialized := bool(payload.get("economy_initialized", false))
	currency_balances = EconomyModel.sanitize_balances(payload.get("currency_balances", {}), currency_definitions, not initialized)
	merchant_stock = EconomyModel.sanitize_stock(payload.get("merchant_stock", {}), merchant_definitions, not initialized)
	economy_initialized = true
	close_merchant(false)
	evaluate_story_progress()
	last_durable_fingerprint = durable_progress_fingerprint()
	return true


func durable_progress_fingerprint() -> String:
	return MerchantSaveProfile.canonical_json({
		"base": super.durable_progress_fingerprint(),
		"currency_balances": currency_balances,
		"merchant_stock": merchant_stock
	})
