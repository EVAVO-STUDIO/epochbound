@tool
extends RefCounted

const UI_CATALOG_PATH := "res://localisation/ui.json"
const SUPPORTED_SCHEMA := 1
const DEFAULT_LOCALE := "en"
const PSEUDO_LOCALE := "qps-ploc"
const PLAYER_LOCALES := [DEFAULT_LOCALE, PSEUDO_LOCALE]
const MESSAGE_KEY_PATTERN := "^[a-z0-9][a-z0-9_.-]*$"
const LOCALE_ID_PATTERN := "^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$"
const PSEUDO_CHARACTER_MAP := {
	"A": "Å", "B": "Ɓ", "C": "Ç", "D": "Ð", "E": "Ë", "F": "Ƒ", "G": "Ğ",
	"H": "Ħ", "I": "Ï", "J": "Ĵ", "K": "Ķ", "L": "Ŀ", "M": "M", "N": "Ñ",
	"O": "Ö", "P": "Þ", "Q": "Q", "R": "Ŗ", "S": "Š", "T": "Ţ", "U": "Ü",
	"V": "V", "W": "Ŵ", "X": "X", "Y": "Ÿ", "Z": "Ž",
	"a": "å", "b": "ƀ", "c": "ç", "d": "ð", "e": "ë", "f": "ƒ", "g": "ğ",
	"h": "ħ", "i": "ï", "j": "ĵ", "k": "ķ", "l": "ŀ", "m": "m", "n": "ñ",
	"o": "ö", "p": "þ", "q": "q", "r": "ŗ", "s": "š", "t": "ţ", "u": "ü",
	"v": "v", "w": "ŵ", "x": "x", "y": "ÿ", "z": "ž"
}


static func empty_catalog() -> Dictionary:
	return {
		"default_locale": DEFAULT_LOCALE,
		"locales": {
			DEFAULT_LOCALE: "English",
			PSEUDO_LOCALE: "Pseudo-localised"
		},
		"messages": {},
		"source_paths": [],
		"locale_count": 2,
		"message_count": 0,
		"ok": true,
		"errors": []
	}


static func supported_player_locales() -> Array[String]:
	return [DEFAULT_LOCALE, PSEUDO_LOCALE]


static func sanitize_player_locale(value: Variant) -> String:
	var locale := str(value).strip_edges()
	return locale if supported_player_locales().has(locale) else DEFAULT_LOCALE


static func locale_label(locale: String) -> String:
	match sanitize_player_locale(locale):
		PSEUDO_LOCALE:
			return "PSEUDO"
	return "ENGLISH"


static func default_campaign_catalog(campaign: Dictionary) -> Dictionary:
	var campaign_id := normalise_identifier(str(campaign.get("id", "campaign")))
	if campaign_id.is_empty():
		campaign_id = "campaign"
	var messages: Dictionary = {}
	messages["campaign.%s.title" % campaign_id] = {
		DEFAULT_LOCALE: str(campaign.get("title", campaign_id.capitalize()))
	}
	messages["campaign.%s.subtitle" % campaign_id] = {
		DEFAULT_LOCALE: str(campaign.get("subtitle", "A New Journey"))
	}
	var intro_value: Variant = campaign.get("intro", [])
	var intro: Array = intro_value if typeof(intro_value) == TYPE_ARRAY else []
	for index in range(intro.size()):
		messages["campaign.%s.intro.%02d" % [campaign_id, index + 1]] = {
			DEFAULT_LOCALE: str(intro[index])
		}
	return {
		"schema_version": SUPPORTED_SCHEMA,
		"default_locale": DEFAULT_LOCALE,
		"messages": messages
	}


static func campaign_intro_keys(campaign_id: String, count: int) -> Array[String]:
	var output: Array[String] = []
	var normalized := normalise_identifier(campaign_id)
	for index in range(maxi(0, count)):
		output.append("campaign.%s.intro.%02d" % [normalized, index + 1])
	return output


static func load_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var output := empty_catalog()
	var errors: Array[String] = []
	var ui_result := load_catalog_path(UI_CATALOG_PATH)
	if not bool(ui_result.get("ok", false)):
		append_messages(errors, ui_result.get("errors", []))
	else:
		merge_catalog(output, ui_result.get("catalog", {}), UI_CATALOG_PATH, errors)
	if campaign_path.is_empty():
		output["ok"] = errors.is_empty()
		output["errors"] = errors
		output["locale_count"] = (output.get("locales", {}) as Dictionary).size()
		output["message_count"] = (output.get("messages", {}) as Dictionary).size()
		return output
	var files_result := campaign_catalog_paths(campaign_path, campaign)
	append_messages(errors, files_result.get("errors", []))
	for path_value in files_result.get("paths", []):
		var path := str(path_value)
		var result := load_catalog_path(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		merge_catalog(output, result.get("catalog", {}), path, errors)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["locale_count"] = (output.get("locales", {}) as Dictionary).size()
	output["message_count"] = (output.get("messages", {}) as Dictionary).size()
	return output


static func load_ui_catalog() -> Dictionary:
	var result := load_catalog_path(UI_CATALOG_PATH)
	if not bool(result.get("ok", false)):
		return result
	var output := empty_catalog()
	var errors: Array[String] = []
	merge_catalog(output, result.get("catalog", {}), UI_CATALOG_PATH, errors)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["locale_count"] = (output.get("locales", {}) as Dictionary).size()
	output["message_count"] = (output.get("messages", {}) as Dictionary).size()
	return output


static func load_campaign_catalogs(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var output := empty_catalog()
	output["messages"] = {}
	output["source_paths"] = []
	var errors: Array[String] = []
	var files_result := campaign_catalog_paths(campaign_path, campaign)
	append_messages(errors, files_result.get("errors", []))
	for path_value in files_result.get("paths", []):
		var path := str(path_value)
		var result := load_catalog_path(path)
		if not bool(result.get("ok", false)):
			append_messages(errors, result.get("errors", []))
			continue
		merge_catalog(output, result.get("catalog", {}), path, errors)
	output["ok"] = errors.is_empty()
	output["errors"] = errors
	output["locale_count"] = (output.get("locales", {}) as Dictionary).size()
	output["message_count"] = (output.get("messages", {}) as Dictionary).size()
	return output


static func campaign_catalog_paths(campaign_path: String, campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var paths: Array[String] = []
	if campaign_path.is_empty():
		return {"ok": true, "paths": paths, "errors": errors}
	var value: Variant = campaign.get("localisation_files", [])
	if campaign.has("localisation_files") and typeof(value) != TYPE_ARRAY:
		return {
			"ok": false,
			"paths": paths,
			"errors": ["%s: localisation_files must be an array of safe relative JSON paths." % campaign.get("id", campaign_path)]
		}
	if typeof(value) != TYPE_ARRAY:
		return {"ok": true, "paths": paths, "errors": errors}
	var seen: Dictionary = {}
	for relative_value in value:
		if typeof(relative_value) != TYPE_STRING:
			errors.append("%s: every localisation_files entry must be a string." % campaign.get("id", campaign_path))
			continue
		var relative_path := str(relative_value)
		if not safe_relative_json_path(relative_path):
			errors.append("%s: unsafe localisation path '%s'." % [campaign.get("id", campaign_path), relative_path])
			continue
		if seen.has(relative_path):
			errors.append("%s: localisation_files repeats '%s'." % [campaign.get("id", campaign_path), relative_path])
			continue
		seen[relative_path] = true
		paths.append(campaign_path.get_base_dir().path_join(relative_path))
	return {"ok": errors.is_empty(), "paths": paths, "errors": errors}


static func load_catalog_path(path: String) -> Dictionary:
	var result := read_json(path)
	if not bool(result.get("ok", false)):
		return {"ok": false, "catalog": {}, "errors": result.get("errors", [])}
	var value: Variant = result.get("data", {})
	var validation := validate_catalog(value, path)
	return {
		"ok": bool(validation.get("ok", false)),
		"catalog": value if typeof(value) == TYPE_DICTIONARY else {},
		"errors": validation.get("errors", [])
	}


static func validate_catalog(value: Variant, path: String = "catalog") -> Dictionary:
	var errors: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["%s: localisation root must be an object." % path]}
	var catalog: Dictionary = value
	var schema_value: Variant = catalog.get("schema_version", 0)
	var schema_type := typeof(schema_value)
	if (
		schema_type != TYPE_INT and schema_type != TYPE_FLOAT
	) or float(schema_value) != float(SUPPORTED_SCHEMA):
		errors.append("%s: unsupported localisation schema_version." % path)
	var default_locale := str(catalog.get("default_locale", DEFAULT_LOCALE))
	if not valid_locale_id(default_locale):
		errors.append("%s: default_locale '%s' is invalid." % [path, default_locale])
	var locales_value: Variant = catalog.get("locales", {})
	if catalog.has("locales") and typeof(locales_value) != TYPE_DICTIONARY:
		errors.append("%s: locales must be an object of locale labels." % path)
	elif typeof(locales_value) == TYPE_DICTIONARY:
		if catalog.has("locales") and not (locales_value as Dictionary).has(default_locale):
			errors.append("%s: locales must declare default locale '%s'." % [path, default_locale])
		for locale_value in sorted_keys(locales_value as Dictionary):
			var locale := str(locale_value)
			var label_value: Variant = (locales_value as Dictionary).get(locale)
			if not valid_locale_id(locale):
				errors.append("%s: locale id '%s' is invalid." % [path, locale])
			if typeof(label_value) != TYPE_STRING or str(label_value).strip_edges().is_empty():
				errors.append("%s: locale '%s' requires a non-empty display label." % [path, locale])
	var messages_value: Variant = catalog.get("messages", {})
	if typeof(messages_value) != TYPE_DICTIONARY:
		errors.append("%s: messages must be an object." % path)
		return {"ok": false, "errors": errors}
	for key_value in sorted_keys(messages_value as Dictionary):
		var key := str(key_value)
		if not valid_message_key(key):
			errors.append("%s: message key '%s' is invalid." % [path, key])
		var translations_value: Variant = (messages_value as Dictionary).get(key)
		if typeof(translations_value) != TYPE_DICTIONARY:
			errors.append("%s: message '%s' must map locale IDs to text." % [path, key])
			continue
		var translations: Dictionary = translations_value
		if not translations.has(default_locale):
			errors.append("%s: message '%s' is missing default locale '%s'." % [path, key, default_locale])
		var baseline_tokens := PackedStringArray()
		if translations.has(default_locale) and typeof(translations.get(default_locale)) == TYPE_STRING:
			baseline_tokens = placeholder_tokens(str(translations.get(default_locale)))
		for locale_value in sorted_keys(translations):
			var locale := str(locale_value)
			var text_value: Variant = translations.get(locale)
			if not valid_locale_id(locale):
				errors.append("%s: message '%s' uses invalid locale '%s'." % [path, key, locale])
			if typeof(text_value) != TYPE_STRING or str(text_value).strip_edges().is_empty():
				errors.append("%s: message '%s' locale '%s' must contain text." % [path, key, locale])
				continue
			if locale != default_locale and placeholder_tokens(str(text_value)) != baseline_tokens:
				errors.append("%s: message '%s' locale '%s' changes its placeholders." % [path, key, locale])
	return {"ok": errors.is_empty(), "errors": errors}


static func merge_catalog(output: Dictionary, catalog_value: Variant, path: String, errors: Array[String]) -> void:
	if typeof(catalog_value) != TYPE_DICTIONARY:
		return
	var catalog: Dictionary = catalog_value
	var output_locales: Dictionary = output.get("locales", {})
	var locales_value: Variant = catalog.get("locales", {})
	if typeof(locales_value) == TYPE_DICTIONARY:
		for locale_value in sorted_keys(locales_value as Dictionary):
			var locale := str(locale_value)
			var label := str((locales_value as Dictionary).get(locale))
			if output_locales.has(locale) and str(output_locales.get(locale)) != label:
				errors.append("%s: locale '%s' conflicts with an earlier display label." % [path, locale])
			else:
				output_locales[locale] = label
	output["locales"] = output_locales
	var output_messages: Dictionary = output.get("messages", {})
	var messages_value: Variant = catalog.get("messages", {})
	if typeof(messages_value) == TYPE_DICTIONARY:
		for key_value in sorted_keys(messages_value as Dictionary):
			var key := str(key_value)
			if output_messages.has(key):
				errors.append("%s: localisation key '%s' duplicates an earlier catalogue." % [path, key])
				continue
			output_messages[key] = (messages_value as Dictionary).get(key)
	output["messages"] = output_messages
	var paths: Array = output.get("source_paths", [])
	paths.append(path)
	output["source_paths"] = paths


static func has_message(catalog: Dictionary, key: String) -> bool:
	var value: Variant = catalog.get("messages", {})
	return typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has(key)


static func resolve(
	catalog: Dictionary,
	locale_value: String,
	key: String,
	fallback: String = "",
	replacements: Dictionary = {}
) -> String:
	var locale := sanitize_player_locale(locale_value)
	var source := fallback
	var messages_value: Variant = catalog.get("messages", {})
	if typeof(messages_value) == TYPE_DICTIONARY and not key.is_empty():
		var entry_value: Variant = (messages_value as Dictionary).get(key, {})
		if typeof(entry_value) == TYPE_DICTIONARY:
			var entry: Dictionary = entry_value
			if locale != PSEUDO_LOCALE and typeof(entry.get(locale)) == TYPE_STRING:
				source = str(entry.get(locale))
			elif typeof(entry.get(DEFAULT_LOCALE)) == TYPE_STRING:
				source = str(entry.get(DEFAULT_LOCALE))
	if source.is_empty():
		source = key
	if locale == PSEUDO_LOCALE:
		source = pseudo_localise(source)
	return apply_replacements(source, replacements)


static func pseudo_localise(text: String) -> String:
	if text.is_empty():
		return text
	var output := "⟦"
	var letters := 0
	var index := 0
	while index < text.length():
		var character := text.substr(index, 1)
		if character == "{":
			var closing := text.find("}", index + 1)
			if closing >= 0:
				output += text.substr(index, closing - index + 1)
				index = closing + 1
				continue
		if character == "%" and index + 1 < text.length():
			var next := text.substr(index + 1, 1)
			if next in ["%", "s", "d", "f", "i"]:
				output += character + next
				index += 2
				continue
		var transformed := pseudo_character(character)
		output += transformed
		if is_ascii_letter(character):
			letters += 1
			if letters % 5 == 0:
				output += "~"
		index += 1
	return output + "⟧"


static func pseudo_character(character: String) -> String:
	return str(PSEUDO_CHARACTER_MAP.get(character, character))


static func apply_replacements(text: String, replacements: Dictionary) -> String:
	var output := text
	for key_value in sorted_keys(replacements):
		var key := str(key_value)
		output = output.replace("{%s}" % key, str(replacements.get(key)))
	return output


static func placeholder_tokens(text: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	var index := 0
	while index < text.length():
		var character := text.substr(index, 1)
		if character == "{":
			var closing := text.find("}", index + 1)
			if closing >= 0:
				tokens.append(text.substr(index, closing - index + 1))
				index = closing + 1
				continue
		if character == "%" and index + 1 < text.length():
			var next := text.substr(index + 1, 1)
			if next in ["%", "s", "d", "f", "i"]:
				tokens.append(character + next)
				index += 2
				continue
		index += 1
	tokens.sort()
	return tokens


static func valid_message_key(key: String) -> bool:
	return regex_matches(MESSAGE_KEY_PATTERN, key)


static func valid_locale_id(locale: String) -> bool:
	return locale == PSEUDO_LOCALE or regex_matches(LOCALE_ID_PATTERN, locale)


static func safe_relative_json_path(path: String) -> bool:
	var normalized := path.strip_edges()
	return (
		not normalized.is_empty()
		and normalized == path
		and not normalized.begins_with("/")
		and not normalized.contains("\\")
		and not normalized.contains("..")
		and normalized.to_lower().ends_with(".json")
	)


static func normalise_identifier(value: String) -> String:
	var output := value.strip_edges().to_lower().replace(" ", "_")
	var filtered := ""
	for index in range(output.length()):
		var character := output.substr(index, 1)
		if "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			filtered += character
	return filtered.trim_prefix("_").trim_suffix("_")


static func is_ascii_letter(character: String) -> bool:
	return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(character)


static func regex_matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func sorted_keys(source: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for key_value in source.keys():
		output.append(str(key_value))
	output.sort()
	return output


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "errors": ["Localisation file does not exist: %s" % path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}, "errors": ["Could not open localisation file: %s" % path]}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		return {
			"ok": false,
			"data": {},
			"errors": ["%s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()]]
		}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "errors": ["Localisation root must be an object: %s" % path]}
	return {"ok": true, "data": parser.data, "errors": []}


static func append_messages(target: Array[String], value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		return
	for message in value:
		target.append(str(message))
