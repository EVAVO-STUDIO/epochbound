extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")
const CampaignPackage = preload("res://src/content/campaign_package.gd")
const Repository = preload("res://src/content/campaign_repository.gd")
const LocalisationCatalog = preload("res://src/content/localisation_catalog.gd")
const LocalisationValidator = preload("res://src/content/localisation_validator.gd")
const PlayerSettings = preload("res://src/game/player_settings.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const REFERENCE_CAMPAIGN := "res://campaigns/epochbound_demo/campaign.json"
const TEST_ROOT := "user://epochbound_localisation_smoke"
const TEST_CAMPAIGN_PATH := TEST_ROOT + "/campaign.json"
const TEST_CATALOG_PATH := TEST_ROOT + "/localisation/core.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	test_catalogue_model()
	test_reference_campaign()
	test_player_language_settings()
	test_isolated_campaign_validation()
	await test_runtime_switching()
	CampaignPackage.remove_tree(TEST_ROOT)
	finish()


func test_catalogue_model() -> void:
	var ui := LocalisationCatalog.load_ui_catalog()
	check(bool(ui.get("ok", false)), "Shared UI localisation catalogue must load and validate.")
	check(int(ui.get("locale_count", 0)) == 2, "Foundation must expose English and the deterministic pseudo locale.")
	check(int(ui.get("message_count", 0)) >= 80, "Shared UI catalogue must cover the complete current menu and settings foundation.")
	check(
		LocalisationCatalog.resolve(ui, "en", "ui.title.options", "MISSING") == "OPTIONS",
		"English message resolution must preserve the authored copy exactly."
	)
	var pseudo := LocalisationCatalog.resolve(
		ui,
		LocalisationCatalog.PSEUDO_LOCALE,
		"ui.controls.binding_failed",
		"BINDING FAILED: {error}",
		{"error": "TEST"}
	)
	check(pseudo.begins_with("⟦") and pseudo.ends_with("⟧"), "Pseudo-localised text must be visibly bounded.")
	check("TEST" in pseudo, "Pseudo-localisation must preserve and replace named placeholders.")
	check("{error}" not in pseudo, "Named placeholders must be resolved after pseudo-localisation.")
	var printf_pseudo := LocalisationCatalog.pseudo_localise("VALUE %s / %d")
	check("%s" in printf_pseudo and "%d" in printf_pseudo, "Printf placeholders must survive pseudo-localisation unchanged.")

	var json_numeric_schema := {
		"schema_version": 1.0,
		"default_locale": "en",
		"messages": {}
	}
	check(
		bool(LocalisationCatalog.validate_catalog(json_numeric_schema, "memory://json-number").get("ok", false)),
		"JSON numeric schema one must validate after a disk parse."
	)
	json_numeric_schema["schema_version"] = 1.5
	check(
		not bool(LocalisationCatalog.validate_catalog(json_numeric_schema, "memory://fractional-schema").get("ok", true)),
		"Fractional localisation schema values must fail closed."
	)

	var malformed := {
		"schema_version": 1,
		"default_locale": "en",
		"locales": {"en": "English", "fr": "French"},
		"messages": {
			"ui.test": {
				"en": "HELLO {name}",
				"fr": "BONJOUR"
			}
		}
	}
	var malformed_report := LocalisationCatalog.validate_catalog(malformed, "memory://malformed")
	check(not bool(malformed_report.get("ok", true)), "A translated message that drops placeholders must fail closed.")
	check(
		contains_message(malformed_report.get("errors", []), "changes its placeholders"),
		"Placeholder-parity rejection must identify the exact catalogue defect."
	)
	var unsafe := LocalisationCatalog.campaign_catalog_paths(
		REFERENCE_CAMPAIGN,
		{"id": "unsafe", "localisation_files": ["../escape.json"]}
	)
	check(not bool(unsafe.get("ok", true)), "Campaign localisation paths must reject traversal before file access.")
	var duplicate := LocalisationCatalog.campaign_catalog_paths(
		REFERENCE_CAMPAIGN,
		{"id": "duplicate", "localisation_files": ["localisation/core.json", "localisation/core.json"]}
	)
	check(not bool(duplicate.get("ok", true)), "Campaign localisation paths must reject duplicates deterministically.")


func test_reference_campaign() -> void:
	var campaign_result := Repository.read_json(REFERENCE_CAMPAIGN)
	check(bool(campaign_result.get("ok", false)), "Reference campaign must parse for localisation validation.")
	if not bool(campaign_result.get("ok", false)):
		return
	var campaign: Dictionary = campaign_result.get("data", {})
	var catalog := LocalisationCatalog.load_catalogs(REFERENCE_CAMPAIGN, campaign)
	check(bool(catalog.get("ok", false)), "Reference UI and campaign localisation catalogues must merge without conflicts.")
	check(int(catalog.get("message_count", 0)) >= 85, "Merged reference catalogue must contain UI and campaign messages.")
	check(
		LocalisationCatalog.resolve(catalog, "en", str(campaign.get("title_key", "")), str(campaign.get("title", ""))) == "EPOCHBOUND",
		"Reference campaign title key must resolve to its exact authored fallback."
	)
	var intro_keys_value: Variant = campaign.get("intro_keys", [])
	var intro_keys: Array = intro_keys_value if typeof(intro_keys_value) == TYPE_ARRAY else []
	check(intro_keys.size() == 3, "Reference campaign must provide one stable key per intro page.")
	var report := LocalisationValidator.validate_localisation_only(REFERENCE_CAMPAIGN)
	check(bool(report.get("ok", false)), "Reference campaign localisation references must validate.")
	check(int(report.get("campaign_localisation_message_count", 0)) == 5, "Reference campaign must expose title, subtitle and three intro messages.")
	var all_report := LocalisationValidator.validate_all()
	check(bool(all_report.get("ok", false)), "Repository-wide localisation validation must pass.")
	check(int(all_report.get("localisation_locale_count", 0)) == 2, "Repository validation must count the two supported foundation locales once.")


func test_player_language_settings() -> void:
	var defaults := PlayerSettings.default_settings()
	check(int(defaults.get("schema_version", 0)) == 3, "Player settings must advance to schema three for language persistence.")
	check(PlayerSettings.string(defaults, "language", "") == "en", "English must remain the safe default player locale.")
	check(PlayerSettings.entries().size() == 14, "Options must expose ten existing preferences, Language, Controls, Reset and Back.")
	var adjusted := PlayerSettings.adjusted(defaults, "language", 1)
	check(PlayerSettings.string(adjusted, "language", "") == "qps-ploc", "Language choice must cycle deterministically to pseudo-localisation.")
	adjusted = PlayerSettings.adjusted(adjusted, "language", -1)
	check(PlayerSettings.string(adjusted, "language", "") == "en", "Language choice must cycle deterministically back to English.")
	var sanitized := PlayerSettings.sanitize({"schema_version": 3, "language": "unknown"})
	check(PlayerSettings.string(sanitized, "language", "") == "en", "Unknown persisted locales must sanitize to English.")
	var invalid := PlayerSettings.validate({"schema_version": 3, "language": "unknown"})
	check(not bool(invalid.get("ok", true)), "Unknown raw locale values must fail validation before persistence.")
	var migrated := PlayerSettings.migrate({"schema_version": 2, "master_volume": 0.5})
	check(bool(migrated.get("ok", false)) and bool(migrated.get("migrated", false)), "Schema-two settings must migrate to schema three.")
	var migrated_settings: Dictionary = migrated.get("settings", {})
	check(PlayerSettings.string(migrated_settings, "language", "") == "en", "Schema-two migration must add the safe English locale.")


func test_isolated_campaign_validation() -> void:
	CampaignPackage.remove_tree(TEST_ROOT)
	var campaign := Repository.default_campaign("localisation_smoke", "Localisation Smoke")
	check(bool(Repository.save_json(TEST_CAMPAIGN_PATH, campaign).get("ok", false)), "Isolated campaign manifest must be writable.")
	check(
		bool(Repository.save_json(TEST_CATALOG_PATH, LocalisationCatalog.default_campaign_catalog(campaign)).get("ok", false)),
		"Isolated campaign localisation catalogue must be writable."
	)
	var report := LocalisationValidator.validate_localisation_only(TEST_CAMPAIGN_PATH)
	check(bool(report.get("ok", false)), "Default campaign localisation scaffolding must validate.")
	check(int(report.get("campaign_localisation_message_count", 0)) == 5, "Default campaign scaffold must include title, subtitle and three intro messages.")
	var broken := campaign.duplicate(true)
	broken["title_key"] = "campaign.localisation_smoke.missing"
	check(bool(Repository.save_json(TEST_CAMPAIGN_PATH, broken).get("ok", false)), "Broken manifest fixture must be writable.")
	var broken_report := LocalisationValidator.validate_localisation_only(TEST_CAMPAIGN_PATH)
	check(not bool(broken_report.get("ok", true)), "Missing campaign message references must fail closed.")
	check(contains_message(broken_report.get("errors", []), "references missing message"), "Missing-key diagnostics must remain explicit.")
	CampaignPackage.remove_tree(TEST_ROOT)


func test_runtime_switching() -> void:
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Localisation-aware runtime scene must load.")
	if not packed is PackedScene:
		return
	var runtime: Node = (packed as PackedScene).instantiate()
	check(runtime != null, "Localisation-aware runtime scene must instantiate.")
	if runtime == null:
		return
	root.add_child(runtime)
	await process_frame

	check(bool(runtime.call("localisation_contract_ok")), "Runtime must load the strict merged localisation catalogue.")
	check(str(runtime.get("current_locale")) == "en", "Fresh runtime must resolve to English.")
	check((runtime.call("title_menu") as Array).has("OPTIONS"), "English title menu must retain the existing Options copy.")
	var english_intro: Array = runtime.call("intro_pages")
	check(not english_intro.is_empty() and not str(english_intro[0]).begins_with("⟦"), "English intro copy must remain unchanged.")
	var revision_before := int(runtime.get("input_binding_cache_revision"))
	runtime.call("set_localisation_locale", "qps-ploc")
	check(str(runtime.get("current_locale")) == "qps-ploc", "Runtime locale switch must apply immediately.")
	var pseudo_menu: Array = runtime.call("title_menu")
	check(not pseudo_menu.is_empty() and str(pseudo_menu[0]).begins_with("⟦"), "Title menu must refresh through deterministic pseudo-localisation.")
	check(str(runtime.call("campaign_title_text")).begins_with("⟦"), "Campaign title fallback must pseudo-localise without changing authored source data.")
	var pseudo_intro: Array = runtime.call("intro_pages")
	check(not pseudo_intro.is_empty() and str(pseudo_intro[0]).begins_with("⟦"), "Campaign intro pages must resolve through stable keys and pseudo fallback.")
	var rows: Array = runtime.call("player_settings_rows")
	check(row_label(rows, "language").begins_with("⟦"), "Options Language row must update immediately after locale change.")
	check(row_value(rows, "language").begins_with("⟦"), "Current language value must be localized through the active locale.")
	check(int(runtime.get("input_binding_cache_revision")) > revision_before, "Locale change must rebuild cached control labels exactly at the mutation boundary.")
	var binding_rows: Array = runtime.call("control_binding_entries")
	check(row_label(binding_rows, "attack").begins_with("⟦"), "Control action labels must refresh after a locale change.")
	runtime.call("set_localisation_locale", "en")
	check((runtime.call("title_menu") as Array).has("OPTIONS"), "Switching back to English must restore exact authored UI copy.")
	check(bool(runtime.call("player_settings_contract_ok")), "Runtime settings contract must include the current valid locale.")
	await HeadlessRuntimeCleanup.release(self, runtime)


func row_label(rows: Array, row_id: String) -> String:
	for value in rows:
		if typeof(value) == TYPE_DICTIONARY and str((value as Dictionary).get("id", "")) == row_id:
			return str((value as Dictionary).get("label", ""))
	return ""


func row_value(rows: Array, row_id: String) -> String:
	for value in rows:
		if typeof(value) == TYPE_DICTIONARY and str((value as Dictionary).get("id", "")) == row_id:
			return str((value as Dictionary).get("value", ""))
	return ""


func contains_message(value: Variant, needle: String) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for message in value:
		if needle in str(message):
			return true
	return false


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Localisation smoke test passed: strict catalogues, exact English fallback, placeholder-safe pseudo-localisation, schema-three language settings, campaign scaffolding, package-safe references and live runtime switching are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
