@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const BaseValidator = preload("res://src/content/equipment_validator.gd")
const EconomyCatalog = preload("res://src/content/economy_catalog.gd")
const EquipmentCatalog = preload("res://src/content/equipment_catalog.gd")
const ItemCatalog = preload("res://src/content/item_catalog.gd")
const ObjectCatalog = preload("res://src/content/object_catalog.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")

const MAX_MULTIPLIER := 100.0


static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var base_report: Dictionary = BaseValidator.validate_all(root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var currency_count := 0
	var merchant_count := 0
	var merchant_binding_count := 0
	var merchant_stock_count := 0
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = value
		var report := validate_economy_only(str(entry.get("path", "")))
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		currency_count += int(report.get("currency_count", 0))
		merchant_count += int(report.get("merchant_count", 0))
		merchant_binding_count += int(report.get("merchant_binding_count", 0))
		merchant_stock_count += int(report.get("merchant_stock_count", 0))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	output["currency_count"] = currency_count
	output["merchant_count"] = merchant_count
	output["merchant_binding_count"] = merchant_binding_count
	output["merchant_stock_count"] = merchant_stock_count
	return output


static func validate_campaign_path(campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_campaign_path(campaign_path)
	var economy_report := validate_economy_only(campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(errors, economy_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	append_messages(warnings, economy_report.get("warnings", []))
	var output := base_report.duplicate(true)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["warnings"] = warnings
	for field in ["currency_count", "merchant_count", "merchant_binding_count", "merchant_stock_count"]:
		output[field] = economy_report.get(field, 0)
	return output


static func validate_profile(profile: Dictionary, campaign_path: String) -> Dictionary:
	var base_report := BaseValidator.validate_profile(profile, campaign_path)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	append_messages(errors, base_report.get("errors", []))
	append_messages(warnings, base_report.get("warnings", []))
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return {"ok": false, "errors": errors, "warnings": warnings}
	var campaign: Dictionary = campaign_result.get("data", {})
	var economy_result := EconomyCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, economy_result.get("errors", []))
	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) == TYPE_DICTIONARY:
		validate_profile_economy(
			payload_value,
			economy_result.get("currencies", {}),
			economy_result.get("merchants", {}),
			item_result.get("definitions", {}),
			errors,
			warnings
		)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func validate_economy_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return make_report(errors, warnings, 0, 0, 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var campaign_id := str(campaign.get("id", campaign_path))
	validate_file_list(campaign, campaign_id, errors, warnings)
	var economy_result := EconomyCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, economy_result.get("errors", []))
	var currencies: Dictionary = economy_result.get("currencies", {})
	var merchants: Dictionary = economy_result.get("merchants", {})
	var item_result := ItemCatalog.load_item_catalogs(campaign_path, campaign)
	append_messages(errors, item_result.get("errors", []))
	var items: Dictionary = item_result.get("definitions", {})
	var story_result := StoryCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, story_result.get("errors", []))
	var capability_result := EquipmentCatalog.load_capability_catalogs(campaign_path, campaign)
	append_messages(errors, capability_result.get("errors", []))
	var capabilities: Dictionary = capability_result.get("definitions", {})
	var object_result := ObjectCatalog.load_catalogs(campaign_path, campaign)
	append_messages(errors, object_result.get("errors", []))
	var object_definitions: Dictionary = object_result.get("definitions", {})
	var map_records := load_maps(campaign_path, campaign, errors)
	var map_ids: Dictionary = {}
	var era_ids: Dictionary = {}
	for map_data_value in map_records:
		if typeof(map_data_value) != TYPE_DICTIONARY:
			continue
		var map_data: Dictionary = map_data_value
		map_ids[str(map_data.get("id", ""))] = true
		for era_value in map_data.get("eras", []):
			if typeof(era_value) == TYPE_DICTIONARY:
				era_ids[str((era_value as Dictionary).get("id", ""))] = true

	var currency_sources: Dictionary = {}
	var merchant_sources: Dictionary = {}
	var used_currencies: Dictionary = {}
	var used_merchants: Dictionary = {}
	var stock_count := 0
	for file_value in economy_result.get("files", []):
		if typeof(file_value) != TYPE_DICTIONARY:
			continue
		var file_record: Dictionary = file_value
		var report := validate_catalog_file(
			file_record.get("data", {}),
			str(file_record.get("path", "economy catalog")),
			currencies,
			merchants,
			items,
			story_result.get("quests", {}),
			map_ids,
			era_ids,
			capabilities,
			currency_sources,
			merchant_sources,
			used_currencies,
			errors,
			warnings
		)
		stock_count += int(report.get("stock_count", 0))

	var binding_count := validate_merchant_bindings(
		campaign_id,
		object_definitions,
		merchants,
		used_merchants,
		errors,
		warnings
	)
	validate_story_currency_references(
		story_result.get("conversations", {}),
		story_result.get("quests", {}),
		object_definitions,
		map_records,
		currencies,
		used_currencies,
		errors
	)
	for merchant_id_value in merchants.keys():
		var merchant_id := str(merchant_id_value)
		if not used_merchants.has(merchant_id):
			warnings.append("%s: merchant '%s' is not bound to any reusable NPC definition." % [campaign_id, merchant_id])
	for currency_id_value in currencies.keys():
		var currency_id := str(currency_id_value)
		if not used_currencies.has(currency_id):
			warnings.append("%s: currency '%s' is not used by a merchant or story effect." % [campaign_id, currency_id])
	return make_report(errors, warnings, currencies.size(), merchants.size(), binding_count, stock_count)


static func validate_file_list(
	campaign: Dictionary,
	campaign_id: String,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if not campaign.has("economy_files"):
		warnings.append("%s: economy_files is omitted; merchant and currency systems are unavailable." % campaign_id)
		return
	var value: Variant = campaign.get("economy_files")
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: economy_files must be an array of safe relative JSON paths." % campaign_id)
		return
	var seen: Dictionary = {}
	for relative_value in value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			errors.append("%s: unsafe economy_files path '%s'." % [campaign_id, relative_path])
		elif seen.has(relative_path):
			errors.append("%s: economy_files repeats '%s'." % [campaign_id, relative_path])
		else:
			seen[relative_path] = true
	if seen.is_empty():
		warnings.append("%s: economy_files is empty." % campaign_id)


static func validate_catalog_file(
	catalog: Dictionary,
	path: String,
	all_currencies: Dictionary,
	all_merchants: Dictionary,
	items: Dictionary,
	quests: Dictionary,
	map_ids: Dictionary,
	era_ids: Dictionary,
	capabilities: Dictionary,
	currency_sources: Dictionary,
	merchant_sources: Dictionary,
	used_currencies: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> Dictionary:
	if int(catalog.get("schema_version", 0)) != EconomyCatalog.SUPPORTED_SCHEMA:
		errors.append("%s: unsupported economy catalog schema_version." % path)
	validate_currency_records(catalog.get("currencies", []), path, currency_sources, errors, warnings)
	var stock_count := validate_merchant_records(
		catalog.get("merchants", []),
		path,
		all_currencies,
		all_merchants,
		items,
		quests,
		map_ids,
		era_ids,
		capabilities,
		merchant_sources,
		used_currencies,
		errors,
		warnings
	)
	return {"stock_count": stock_count}


static func validate_currency_records(
	value: Variant,
	path: String,
	sources: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: currencies must be an array." % path)
		return
	var local_ids: Dictionary = {}
	for record_value in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("%s: every currency must be an object." % path)
			continue
		var data: Dictionary = record_value
		var currency_id := str(data.get("id", ""))
		var prefix := "%s/currency/%s" % [path, currency_id if not currency_id.is_empty() else "currency"]
		if currency_id.is_empty() or Repository.normalise_id(currency_id) != currency_id or currency_id.length() > EconomyCatalog.MAX_CURRENCY_ID_LENGTH:
			errors.append("%s: id must be a normalised lowercase identifier no longer than %d characters." % [prefix, EconomyCatalog.MAX_CURRENCY_ID_LENGTH])
		elif local_ids.has(currency_id):
			errors.append("%s: currency is repeated." % prefix)
		else:
			local_ids[currency_id] = true
			if sources.has(currency_id) and sources[currency_id] != path:
				errors.append("%s: currency '%s' is also declared by %s." % [path, currency_id, sources[currency_id]])
			sources[currency_id] = path
		var display_name := str(data.get("display_name", "")).strip_edges()
		if display_name.is_empty():
			errors.append("%s: display_name is required." % prefix)
		elif display_name.length() > EconomyCatalog.MAX_DISPLAY_NAME_LENGTH:
			errors.append("%s: display_name is too long." % prefix)
		var symbol := str(data.get("symbol", "")).strip_edges()
		if symbol.is_empty():
			errors.append("%s: symbol is required." % prefix)
		elif symbol.length() > 8:
			errors.append("%s: symbol must contain at most 8 characters." % prefix)
		var maximum := int(data.get("max_balance", 0))
		var starting := int(data.get("starting_balance", -1))
		if maximum < 1 or maximum > EconomyCatalog.MAX_BALANCE:
			errors.append("%s: max_balance must be between 1 and %d." % [prefix, EconomyCatalog.MAX_BALANCE])
		if starting < 0 or (maximum > 0 and starting > maximum):
			errors.append("%s: starting_balance must fit within max_balance." % prefix)
		if starting == 0:
			warnings.append("%s: starting_balance is zero; the campaign must provide another earning route." % prefix)


static func validate_merchant_records(
	value: Variant,
	path: String,
	currencies: Dictionary,
	all_merchants: Dictionary,
	items: Dictionary,
	quests: Dictionary,
	map_ids: Dictionary,
	era_ids: Dictionary,
	capabilities: Dictionary,
	sources: Dictionary,
	used_currencies: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> int:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: merchants must be an array." % path)
		return 0
	var local_ids: Dictionary = {}
	var stock_count := 0
	for record_value in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("%s: every merchant must be an object." % path)
			continue
		var data: Dictionary = record_value
		var merchant_id := str(data.get("id", ""))
		var prefix := "%s/merchant/%s" % [path, merchant_id if not merchant_id.is_empty() else "merchant"]
		if merchant_id.is_empty() or Repository.normalise_id(merchant_id) != merchant_id or merchant_id.length() > EconomyCatalog.MAX_MERCHANT_ID_LENGTH:
			errors.append("%s: id must be a normalised lowercase identifier no longer than %d characters." % [prefix, EconomyCatalog.MAX_MERCHANT_ID_LENGTH])
		elif local_ids.has(merchant_id):
			errors.append("%s: merchant is repeated." % prefix)
		else:
			local_ids[merchant_id] = true
			if sources.has(merchant_id) and sources[merchant_id] != path:
				errors.append("%s: merchant '%s' is also declared by %s." % [path, merchant_id, sources[merchant_id]])
			sources[merchant_id] = path
		if not all_merchants.has(merchant_id):
			errors.append("%s: merchant could not be merged into the campaign catalogue." % prefix)
		var display_name := str(data.get("display_name", "")).strip_edges()
		if display_name.is_empty():
			errors.append("%s: display_name is required." % prefix)
		var currency_id := str(data.get("currency_id", ""))
		if not currencies.has(currency_id):
			errors.append("%s: unknown currency_id '%s'." % [prefix, currency_id])
		else:
			used_currencies[currency_id] = true
		for field in ["greeting", "farewell"]:
			var text := str(data.get(field, "")).strip_edges()
			if text.is_empty():
				warnings.append("%s: %s is empty." % [prefix, field])
			elif text.length() > EconomyCatalog.MAX_MESSAGE_LENGTH:
				errors.append("%s: %s exceeds %d characters." % [prefix, field, EconomyCatalog.MAX_MESSAGE_LENGTH])
		var buy_multiplier := float(data.get("buy_multiplier", 0.0))
		var sell_multiplier := float(data.get("sell_multiplier", -1.0))
		if buy_multiplier <= 0.0 or buy_multiplier > MAX_MULTIPLIER:
			errors.append("%s: buy_multiplier must be greater than zero and no more than %.1f." % [prefix, MAX_MULTIPLIER])
		if sell_multiplier < 0.0 or sell_multiplier > MAX_MULTIPLIER:
			errors.append("%s: sell_multiplier must be between zero and %.1f." % [prefix, MAX_MULTIPLIER])
		if sell_multiplier >= buy_multiplier and buy_multiplier > 0.0:
			warnings.append("%s: sell_multiplier is not lower than buy_multiplier and may permit trivial profit loops." % prefix)
		for field in ["accepts_sales", "resell_player_goods"]:
			if typeof(data.get(field, true)) != TYPE_BOOL:
				errors.append("%s: %s must be boolean." % [prefix, field])
		validate_accepted_kinds(data.get("accepted_kinds", []), prefix, errors, warnings)
		validate_item_id_array(data.get("refused_items", []), prefix + "/refused_items", items, errors)
		validate_currency_conditions(data.get("conditions", []), prefix + "/conditions", currencies, quests, map_ids, era_ids, capabilities, used_currencies, errors)
		stock_count += validate_stock(
			data.get("stock", []),
			prefix,
			data,
			items,
			currencies,
			quests,
			map_ids,
			era_ids,
			capabilities,
			used_currencies,
			errors,
			warnings
		)
	return stock_count


static func validate_accepted_kinds(value: Variant, prefix: String, errors: Array[String], warnings: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: accepted_kinds must be an array." % prefix)
		return
	var seen: Dictionary = {}
	for kind_value in value:
		var kind := str(kind_value)
		if not ItemCatalog.ALLOWED_ITEM_KINDS.has(kind):
			errors.append("%s: unsupported accepted item kind '%s'." % [prefix, kind])
		elif seen.has(kind):
			errors.append("%s: accepted item kind '%s' is repeated." % [prefix, kind])
		else:
			seen[kind] = true
	if seen.is_empty():
		warnings.append("%s: accepted_kinds is empty; this merchant cannot purchase player items." % prefix)


static func validate_item_id_array(value: Variant, prefix: String, items: Dictionary, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s must be an array of item IDs." % prefix)
		return
	var seen: Dictionary = {}
	for item_value in value:
		var item_id := str(item_value)
		if not items.has(item_id):
			errors.append("%s: unknown item '%s'." % [prefix, item_id])
		elif seen.has(item_id):
			errors.append("%s: item '%s' is repeated." % [prefix, item_id])
		else:
			seen[item_id] = true


static func validate_stock(
	value: Variant,
	prefix: String,
	merchant_data: Dictionary,
	items: Dictionary,
	currencies: Dictionary,
	quests: Dictionary,
	map_ids: Dictionary,
	era_ids: Dictionary,
	capabilities: Dictionary,
	used_currencies: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> int:
	if typeof(value) != TYPE_ARRAY:
		errors.append("%s: stock must be an array." % prefix)
		return 0
	var seen: Dictionary = {}
	var records: Array = value
	if records.is_empty():
		warnings.append("%s: stock is empty." % prefix)
	for index in range(records.size()):
		var record_value: Variant = records[index]
		var stock_prefix := "%s/stock/%d" % [prefix, index]
		if typeof(record_value) != TYPE_DICTIONARY:
			errors.append("%s: stock entry must be an object." % stock_prefix)
			continue
		var entry: Dictionary = record_value
		var item_id := str(entry.get("item_id", ""))
		if not items.has(item_id):
			errors.append("%s: unknown item '%s'." % [stock_prefix, item_id])
		elif seen.has(item_id):
			errors.append("%s: item '%s' is repeated in merchant stock." % [stock_prefix, item_id])
		else:
			seen[item_id] = true
		var unlimited_value: Variant = entry.get("unlimited", false)
		if typeof(unlimited_value) != TYPE_BOOL:
			errors.append("%s: unlimited must be boolean." % stock_prefix)
		var quantity := int(entry.get("quantity", -1))
		if quantity < 0 or quantity > EconomyCatalog.MAX_STOCK:
			errors.append("%s: quantity must be between zero and %d." % [stock_prefix, EconomyCatalog.MAX_STOCK])
		elif quantity == 0 and not bool(unlimited_value):
			warnings.append("%s: finite stock starts empty." % stock_prefix)
		var buy_price := int(entry.get("buy_price", 0))
		var sell_price := int(entry.get("sell_price", 0))
		if buy_price < 0 or sell_price < 0:
			errors.append("%s: price overrides cannot be negative." % stock_prefix)
		var item_data := ItemCatalog.item(items, item_id)
		if not item_data.is_empty() and buy_price == 0 and int(item_data.get("value", 0)) <= 0:
			errors.append("%s: item has no positive value and needs an explicit buy_price." % stock_prefix)
		var resolved_buy := buy_price
		if resolved_buy <= 0 and not item_data.is_empty():
			resolved_buy = maxi(1, int(ceil(float(item_data.get("value", 0)) * float(merchant_data.get("buy_multiplier", 1.0)))))
		var resolved_sell := sell_price
		if resolved_sell <= 0 and not item_data.is_empty():
			resolved_sell = maxi(1, int(floor(float(item_data.get("value", 0)) * float(merchant_data.get("sell_multiplier", 0.5))))) if int(item_data.get("value", 0)) > 0 else 0
		if resolved_sell >= resolved_buy and resolved_buy > 0:
			warnings.append("%s: resolved sell price is not lower than buy price." % stock_prefix)
		validate_currency_conditions(entry.get("conditions", []), stock_prefix + "/conditions", currencies, quests, map_ids, era_ids, capabilities, used_currencies, errors)
	return records.size()


static func validate_merchant_bindings(
	campaign_id: String,
	object_definitions: Dictionary,
	merchants: Dictionary,
	used_merchants: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> int:
	var count := 0
	for object_id_value in object_definitions.keys():
		var object_id := str(object_id_value)
		var object_data: Dictionary = object_definitions.get(object_id, {})
		var merchant_id := str(object_data.get("merchant_id", "")).strip_edges()
		if merchant_id.is_empty():
			continue
		count += 1
		var prefix := "%s/object/%s" % [campaign_id, object_id]
		if not merchants.has(merchant_id):
			errors.append("%s: unknown merchant_id '%s'." % [prefix, merchant_id])
		else:
			used_merchants[merchant_id] = true
		if str(object_data.get("kind", "")) != "npc":
			warnings.append("%s: merchant_id is normally expected on an NPC definition." % prefix)
	return count


static func validate_story_currency_references(
	conversations: Dictionary,
	quests: Dictionary,
	object_definitions: Dictionary,
	map_records: Array,
	currencies: Dictionary,
	used_currencies: Dictionary,
	errors: Array[String]
) -> void:
	for conversation_id_value in conversations.keys():
		var conversation_id := str(conversation_id_value)
		var conversation_data := StoryCatalog.conversation(conversations, conversation_id)
		validate_currency_conditions(StoryCatalog.conditions(conversation_data), "conversation/%s/conditions" % conversation_id, currencies, quests, {}, {}, {}, used_currencies, errors)
		for node_value in StoryCatalog.nodes(conversation_data):
			if typeof(node_value) != TYPE_DICTIONARY:
				continue
			var node: Dictionary = node_value
			var node_id := str(node.get("id", "node"))
			validate_currency_conditions(StoryCatalog.conditions(node), "conversation/%s/node/%s/conditions" % [conversation_id, node_id], currencies, quests, {}, {}, {}, used_currencies, errors)
			validate_currency_effects(StoryCatalog.effects(node), "conversation/%s/node/%s/effects" % [conversation_id, node_id], currencies, used_currencies, errors)
			for choice_value in StoryCatalog.choices(node):
				if typeof(choice_value) != TYPE_DICTIONARY:
					continue
				var choice: Dictionary = choice_value
				var choice_id := str(choice.get("id", "choice"))
				validate_currency_conditions(StoryCatalog.conditions(choice), "conversation/%s/node/%s/choice/%s/conditions" % [conversation_id, node_id, choice_id], currencies, quests, {}, {}, {}, used_currencies, errors)
				validate_currency_effects(StoryCatalog.effects(choice), "conversation/%s/node/%s/choice/%s/effects" % [conversation_id, node_id, choice_id], currencies, used_currencies, errors)
	for quest_id_value in quests.keys():
		var quest_id := str(quest_id_value)
		var quest_data := StoryCatalog.quest(quests, quest_id)
		for stage_value in StoryCatalog.stages(quest_data):
			if typeof(stage_value) != TYPE_DICTIONARY:
				continue
			var stage: Dictionary = stage_value
			validate_currency_conditions(StoryCatalog.conditions(stage, "completion_conditions"), "quest/%s/stage/%s/conditions" % [quest_id, stage.get("id", "stage")], currencies, quests, {}, {}, {}, used_currencies, errors)
		validate_currency_effects(StoryCatalog.effects(quest_data, "rewards"), "quest/%s/rewards" % quest_id, currencies, used_currencies, errors)
	for object_id_value in object_definitions.keys():
		var object_id := str(object_id_value)
		var object_data: Dictionary = object_definitions.get(object_id, {})
		validate_currency_effects(StoryCatalog.effects(object_data, "story_effects"), "object/%s/story_effects" % object_id, currencies, used_currencies, errors)
	for map_value in map_records:
		if typeof(map_value) != TYPE_DICTIONARY:
			continue
		var map_data: Dictionary = map_value
		var map_id := str(map_data.get("id", "map"))
		for interaction_value in map_data.get("interactions", []):
			if typeof(interaction_value) != TYPE_DICTIONARY:
				continue
			var interaction: Dictionary = interaction_value
			var prefix := "map/%s/interaction/%s" % [map_id, interaction.get("id", "interaction")]
			validate_currency_conditions(StoryCatalog.conditions(interaction, "story_conditions"), prefix + "/conditions", currencies, quests, {}, {}, {}, used_currencies, errors)
			validate_currency_effects(StoryCatalog.effects(interaction, "story_effects"), prefix + "/effects", currencies, used_currencies, errors)
		for cue_value in map_data.get("companion_cues", []):
			if typeof(cue_value) == TYPE_DICTIONARY:
				var cue: Dictionary = cue_value
				validate_currency_effects(StoryCatalog.effects(cue, "story_effects"), "map/%s/cue/%s/effects" % [map_id, cue.get("id", "cue")], currencies, used_currencies, errors)


static func validate_currency_conditions(
	value: Variant,
	prefix: String,
	currencies: Dictionary,
	_quests: Dictionary,
	_map_ids: Dictionary,
	_era_ids: Dictionary,
	_capabilities: Dictionary,
	used_currencies: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for index in range((value as Array).size()):
		var condition_value: Variant = (value as Array)[index]
		if typeof(condition_value) != TYPE_DICTIONARY:
			continue
		var condition: Dictionary = condition_value
		if str(condition.get("type", "")) != "currency_at_least":
			continue
		var condition_prefix := "%s/%d" % [prefix, index]
		var currency_id := str(condition.get("currency_id", ""))
		if not currencies.has(currency_id):
			errors.append("%s: unknown currency '%s'." % [condition_prefix, currency_id])
		else:
			used_currencies[currency_id] = true
		if int(condition.get("amount", -1)) < 0:
			errors.append("%s: amount cannot be negative." % condition_prefix)


static func validate_currency_effects(
	value: Variant,
	prefix: String,
	currencies: Dictionary,
	used_currencies: Dictionary,
	errors: Array[String]
) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for index in range((value as Array).size()):
		var effect_value: Variant = (value as Array)[index]
		if typeof(effect_value) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = effect_value
		var effect_type := str(effect.get("type", ""))
		if effect_type not in ["grant_currency", "remove_currency"]:
			continue
		var effect_prefix := "%s/%d" % [prefix, index]
		var currency_id := str(effect.get("currency_id", ""))
		if not currencies.has(currency_id):
			errors.append("%s: unknown currency '%s'." % [effect_prefix, currency_id])
		else:
			used_currencies[currency_id] = true
		if int(effect.get("amount", 0)) <= 0:
			errors.append("%s: amount must be positive." % effect_prefix)


static func validate_profile_economy(
	payload: Dictionary,
	currencies: Dictionary,
	merchants: Dictionary,
	items: Dictionary,
	errors: Array[String],
	warnings: Array[String]
) -> void:
	if typeof(payload.get("economy_initialized", false)) != TYPE_BOOL:
		errors.append("Save payload economy_initialized must be boolean.")
	var initialized := bool(payload.get("economy_initialized", false))
	var balances_value: Variant = payload.get("currency_balances", {})
	var stock_value: Variant = payload.get("merchant_stock", {})
	if typeof(balances_value) != TYPE_DICTIONARY:
		errors.append("Save payload currency_balances must be an object.")
		return
	if typeof(stock_value) != TYPE_DICTIONARY:
		errors.append("Save payload merchant_stock must be an object.")
		return
	var balances: Dictionary = balances_value
	for currency_key in balances.keys():
		var currency_id := str(currency_key)
		if not currencies.has(currency_id):
			errors.append("Save currency_balances references unknown currency '%s'." % currency_id)
			continue
		var amount := int(balances.get(currency_key, -1))
		var maximum := EconomyCatalog.max_balance(EconomyCatalog.currency(currencies, currency_id))
		if amount < 0 or amount > maximum:
			errors.append("Save balance for '%s' must be between zero and %d." % [currency_id, maximum])
	if initialized:
		for currency_id_value in currencies.keys():
			if not balances.has(str(currency_id_value)):
				errors.append("Save currency_balances is missing '%s'." % currency_id_value)
	elif not balances.is_empty() or not (stock_value as Dictionary).is_empty():
		warnings.append("Save payload contains economy state while economy_initialized is false; defaults will replace it.")
	var stock: Dictionary = stock_value
	for merchant_key in stock.keys():
		var merchant_id := str(merchant_key)
		if not merchants.has(merchant_id):
			errors.append("Save merchant_stock references unknown merchant '%s'." % merchant_id)
			continue
		var merchant_state_value: Variant = stock.get(merchant_key, {})
		if typeof(merchant_state_value) != TYPE_DICTIONARY:
			errors.append("Save merchant_stock entry for '%s' must be an object." % merchant_id)
			continue
		var merchant_data := EconomyCatalog.merchant(merchants, merchant_id)
		var authored := EconomyCatalog.stock_entry_index(merchant_data)
		for item_key in (merchant_state_value as Dictionary).keys():
			var item_id := str(item_key)
			if not items.has(item_id):
				errors.append("Save merchant '%s' stock references unknown item '%s'." % [merchant_id, item_id])
				continue
			if not authored.has(item_id) and not EconomyCatalog.merchant_resells_player_goods(merchant_data):
				errors.append("Save merchant '%s' contains unauthored stock '%s' but resell_player_goods is false." % [merchant_id, item_id])
			var quantity := int((merchant_state_value as Dictionary).get(item_key, 0))
			var authored_entry: Dictionary = authored.get(item_id, {})
			if not authored_entry.is_empty() and EconomyCatalog.stock_is_unlimited(authored_entry):
				if quantity != -1:
					errors.append("Save merchant '%s' unlimited stock '%s' must use -1." % [merchant_id, item_id])
			elif quantity < 0 or quantity > EconomyCatalog.MAX_STOCK:
				errors.append("Save merchant '%s' stock '%s' must be between zero and %d." % [merchant_id, item_id, EconomyCatalog.MAX_STOCK])
	if initialized:
		for merchant_id_value in merchants.keys():
			if not stock.has(str(merchant_id_value)):
				errors.append("Save merchant_stock is missing '%s'." % merchant_id_value)


static func load_maps(campaign_path: String, campaign: Dictionary, errors: Array[String]) -> Array:
	var output: Array = []
	var value: Variant = campaign.get("map_files", [])
	if typeof(value) != TYPE_ARRAY:
		return output
	for relative_value in value:
		var relative_path := str(relative_value)
		if not ObjectCatalog.safe_relative_json_path(relative_path):
			continue
		var result := Repository.read_json(campaign_path.get_base_dir().path_join(relative_path))
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		output.append(result.get("data", {}))
	return output


static func make_report(
	errors: Array[String],
	warnings: Array[String],
	currency_count: int,
	merchant_count: int,
	merchant_binding_count: int,
	merchant_stock_count: int
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"currency_count": currency_count,
		"merchant_count": merchant_count,
		"merchant_binding_count": merchant_binding_count,
		"merchant_stock_count": merchant_stock_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
