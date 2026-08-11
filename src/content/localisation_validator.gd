@tool
extends RefCounted

const Repository = preload("res://src/content/campaign_repository.gd")
const LocalisationCatalog = preload("res://src/content/localisation_catalog.gd")




static func validate_ui_only() -> Dictionary:
	var report := LocalisationCatalog.load_ui_catalog()
	var errors: Array[String] = []
	append_messages(errors, report.get("errors", []))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": [],
		"localisation_locale_count": int(report.get("locale_count", 0)),
		"localisation_message_count": int(report.get("message_count", 0))
	}

static func validate_all(root: String = Repository.DEFAULT_ROOT) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_count := 0
	var locale_count := 0
	var message_count := 0
	var ui_report := LocalisationCatalog.load_ui_catalog()
	append_messages(errors, ui_report.get("errors", []))
	locale_count += int(ui_report.get("locale_count", 0))
	message_count += int(ui_report.get("message_count", 0))
	for value in Repository.scan_campaigns(root):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		campaign_count += 1
		var path := str((value as Dictionary).get("path", ""))
		var report := validate_localisation_only(path)
		append_messages(errors, report.get("errors", []))
		append_messages(warnings, report.get("warnings", []))
		message_count += int(report.get("campaign_localisation_message_count", 0))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"localisation_campaign_count": campaign_count,
		"localisation_locale_count": locale_count,
		"localisation_message_count": message_count
	}


static func validate_localisation_only(campaign_path: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var campaign_result := Repository.read_json(campaign_path)
	if not bool(campaign_result.get("ok", false)):
		append_messages(errors, campaign_result.get("errors", []))
		return result(errors, warnings, 0, 0)
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog_result := LocalisationCatalog.load_campaign_catalogs(campaign_path, campaign)
	append_messages(errors, catalog_result.get("errors", []))
	var messages_value: Variant = catalog_result.get("messages", {})
	var messages: Dictionary = messages_value if typeof(messages_value) == TYPE_DICTIONARY else {}
	validate_key_field(campaign, "title_key", "title", messages, campaign_path, errors)
	validate_key_field(campaign, "subtitle_key", "subtitle", messages, campaign_path, errors)
	var intro_value: Variant = campaign.get("intro", [])
	var intro: Array = intro_value if typeof(intro_value) == TYPE_ARRAY else []
	var intro_keys_value: Variant = campaign.get("intro_keys", [])
	if campaign.has("intro_keys"):
		if typeof(intro_keys_value) != TYPE_ARRAY:
			errors.append("%s: intro_keys must be an array." % campaign_path)
		else:
			var intro_keys: Array = intro_keys_value
			if intro_keys.size() != intro.size():
				errors.append("%s: intro_keys must contain exactly one key for every intro page." % campaign_path)
			for index in range(intro_keys.size()):
				var key_value: Variant = intro_keys[index]
				if typeof(key_value) != TYPE_STRING or not LocalisationCatalog.valid_message_key(str(key_value)):
					errors.append("%s: intro_keys[%d] must be a valid localisation key." % [campaign_path, index])
				elif not messages.has(str(key_value)):
					errors.append("%s: intro_keys[%d] references missing message '%s'." % [campaign_path, index, key_value])
	return result(
		errors,
		warnings,
		int(catalog_result.get("locale_count", 0)),
		int(catalog_result.get("message_count", 0))
	)


static func validate_key_field(
	campaign: Dictionary,
	key_field: String,
	text_field: String,
	messages: Dictionary,
	campaign_path: String,
	errors: Array[String]
) -> void:
	if not campaign.has(key_field):
		return
	var key_value: Variant = campaign.get(key_field)
	if typeof(key_value) != TYPE_STRING or not LocalisationCatalog.valid_message_key(str(key_value)):
		errors.append("%s: %s must be a valid localisation key." % [campaign_path, key_field])
		return
	if not messages.has(str(key_value)):
		errors.append("%s: %s references missing message '%s'." % [campaign_path, key_field, key_value])
	if typeof(campaign.get(text_field, "")) != TYPE_STRING or str(campaign.get(text_field, "")).strip_edges().is_empty():
		errors.append("%s: %s requires fallback text even when %s is declared." % [campaign_path, text_field, key_field])


static func result(errors: Array[String], warnings: Array[String], locale_count: int, message_count: int) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"localisation_locale_count": locale_count,
		"campaign_localisation_message_count": message_count
	}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
