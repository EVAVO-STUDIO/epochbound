#!/usr/bin/env python3
"""Fail closed when Epochbound's localisation foundation drifts."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.is_file():
        errors.append(f"missing required file: {relative_path}")
        return ""
    return path.read_text(encoding="utf-8")


def read_json(relative_path: str) -> dict:
    source = read(relative_path)
    if not source:
        return {}
    try:
        value = json.loads(source)
    except json.JSONDecodeError as exc:
        errors.append(f"{relative_path}: invalid JSON: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{relative_path}: root must be an object")
        return {}
    return value


def require(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token not in source:
            errors.append(f"{relative_path}: missing {token}")


def forbid(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token in source:
            errors.append(f"{relative_path}: contains forbidden {token}")


def require_order(relative_path: str, source: str, earlier: str, later: str) -> None:
    first = source.find(earlier)
    second = source.find(later)
    if first < 0:
        errors.append(f"{relative_path}: missing ordered token {earlier}")
    elif second < 0:
        errors.append(f"{relative_path}: missing ordered token {later}")
    elif first >= second:
        errors.append(f"{relative_path}: expected {earlier} before {later}")


catalog = read("src/content/localisation_catalog.gd")
require(
    "src/content/localisation_catalog.gd",
    catalog,
    [
        '@tool',
        'UI_CATALOG_PATH := "res://localisation/ui.json"',
        'SUPPORTED_SCHEMA := 1',
        'DEFAULT_LOCALE := "en"',
        'PSEUDO_LOCALE := "qps-ploc"',
        'PLAYER_LOCALES := [DEFAULT_LOCALE, PSEUDO_LOCALE]',
        'MESSAGE_KEY_PATTERN',
        'LOCALE_ID_PATTERN',
        'PSEUDO_CHARACTER_MAP',
        'default_campaign_catalog',
        'campaign_intro_keys',
        'load_catalogs',
        'load_ui_catalog',
        'load_campaign_catalogs',
        'campaign_catalog_paths',
        'safe_relative_json_path',
        'validate_catalog',
        'schema_type != TYPE_INT and schema_type != TYPE_FLOAT',
        'float(schema_value) != float(SUPPORTED_SCHEMA)',
        'merge_catalog',
        'duplicates an earlier catalogue',
        'changes its placeholders',
        'resolve',
        'pseudo_localise',
        'apply_replacements',
        'placeholder_tokens',
        'sanitize_player_locale',
        'TranslationServer' if False else 'supported_player_locales',
    ],
)
require_order(
    "src/content/localisation_catalog.gd",
    catalog,
    'compressed' if False else 'static func resolve(',
    'static func pseudo_localise(',
)
forbid(
    "src/content/localisation_catalog.gd",
    catalog,
    [
        'HTTPRequest',
        'HTTPClient',
        'fetch(',
        'curl',
        'Time.get_',
        'OS.get_unix_time',
        'machine_translate',
        'google translate',
        'deepl',
    ],
)

validator = read("src/content/localisation_validator.gd")
require(
    "src/content/localisation_validator.gd",
    validator,
    [
        'validate_ui_only',
        'validate_all',
        'validate_localisation_only',
        'title_key',
        'subtitle_key',
        'intro_keys',
        'requires fallback text',
        'references missing message',
        'campaign_localisation_message_count',
    ],
)

ui = read_json("localisation/ui.json")
if ui.get("schema_version") != 1:
    errors.append("localisation/ui.json: schema_version must be 1")
if ui.get("default_locale") != "en":
    errors.append("localisation/ui.json: default_locale must remain en")
if ui.get("locales") != {"en": "English", "qps-ploc": "Pseudo-localised"}:
    errors.append("localisation/ui.json: foundation locales must be exactly English and deterministic pseudo")
ui_messages = ui.get("messages", {})
if not isinstance(ui_messages, dict) or len(ui_messages) < 80:
    errors.append("localisation/ui.json: expected at least 80 core UI messages")
else:
    for key, translations in sorted(ui_messages.items()):
        if not isinstance(translations, dict):
            errors.append(f"localisation/ui.json: {key} must map locales to text")
            continue
        if not isinstance(translations.get("en"), str) or not translations["en"].strip():
            errors.append(f"localisation/ui.json: {key} requires non-empty English copy")
        if "qps-ploc" in translations:
            errors.append(f"localisation/ui.json: {key} must use generated pseudo-localisation, not authored pseudo copy")
for required_key in [
    "ui.title.options",
    "ui.options.title",
    "ui.settings.language",
    "ui.settings.language.en",
    "ui.settings.language.qps-ploc",
    "ui.controls.title",
    "ui.controls.action.attack",
    "ui.controls.binding_failed",
    "ui.hideaway.return.qualified",
    "ui.hideaway.return.too_short",
    "ui.hideaway.status.overview",
    "ui.hideaway.status.restoration",
    "ui.hideaway.status.facility.active",
    "ui.hideaway.tier.haven",
    "ui.hideaway.facility.archive_hearth",
    "ui.hideaway.failure.unrestored",
    "ui.hideaway.warmth.absorb",
    "ui.hideaway.memento.first_safe_return.name",
    "ui.hideaway.memento.archive_haven_key.ashen",
    "ui.hideaway.status.mementos",
    "ui.hideaway.controls.mementos",
]:
    if required_key not in ui_messages:
        errors.append(f"localisation/ui.json: missing {required_key}")

reference_catalog = read_json("campaigns/epochbound_demo/localisation/core.json")
reference_messages = reference_catalog.get("messages", {})
if reference_catalog.get("schema_version") != 1 or reference_catalog.get("default_locale") != "en":
    errors.append("reference localisation catalogue must use schema 1 with English fallback")
if not isinstance(reference_messages, dict) or len(reference_messages) != 5:
    errors.append("reference localisation catalogue must contain exactly title, subtitle and three intro messages")
reference_campaign = read_json("campaigns/epochbound_demo/campaign.json")
for field in ["title_key", "subtitle_key", "intro_keys", "localisation_files"]:
    if field not in reference_campaign:
        errors.append(f"reference campaign: missing {field}")
if reference_campaign.get("localisation_files") != ["localisation/core.json"]:
    errors.append("reference campaign must bind exactly localisation/core.json")
intro = reference_campaign.get("intro", [])
intro_keys = reference_campaign.get("intro_keys", [])
if not isinstance(intro, list) or not isinstance(intro_keys, list) or len(intro) != len(intro_keys):
    errors.append("reference campaign must provide one localisation key per intro page")
for key_field, text_field in [("title_key", "title"), ("subtitle_key", "subtitle")]:
    key = reference_campaign.get(key_field)
    text = reference_campaign.get(text_field)
    if not isinstance(key, str) or reference_messages.get(key, {}).get("en") != text:
        errors.append(f"reference campaign {key_field} must resolve to exact {text_field} fallback")
for index, key in enumerate(intro_keys if isinstance(intro_keys, list) else []):
    if index >= len(intro) or reference_messages.get(key, {}).get("en") != intro[index]:
        errors.append(f"reference campaign intro key {index} must resolve to exact fallback copy")

repository = read("src/content/campaign_repository.gd")
require(
    "src/content/campaign_repository.gd",
    repository,
    [
        'LocalisationCatalog = preload("res://src/content/localisation_catalog.gd")',
        'localisation/core.json',
        'LocalisationCatalog.default_campaign_catalog(campaign_data)',
        '"localisation_catalog_path": localisation_catalog_path',
        '"title_key": "campaign.%s.title" % campaign_id',
        '"subtitle_key": "campaign.%s.subtitle" % campaign_id',
        '"intro_keys": LocalisationCatalog.campaign_intro_keys(campaign_id, 3)',
    ],
)
complete_validator = read("src/content/complete_content_validator.gd")
require(
    "src/content/complete_content_validator.gd",
    complete_validator,
    [
        'LocalisationValidator = preload("res://src/content/localisation_validator.gd")',
        'LocalisationValidator.validate_ui_only()',
        'LocalisationValidator.validate_localisation_only(path)',
        'localisation_locale_count',
        'localisation_message_count',
        'HideawayValidator.validate_hideaway_only',
        'hideaway_memento_count',
    ],
)
package = read("src/content/campaign_package.gd")
require(
    "src/content/campaign_package.gd",
    package,
    [
        'LocalisationValidator = preload("res://src/content/localisation_validator.gd")',
        'LocalisationValidator.validate_localisation_only(staged_campaign_path)',
        'append_messages(validation_errors, localisation_validation.get("errors", []))',
        'localisation_message_count',
    ],
)
require_order(
    "src/content/campaign_package.gd",
    package,
    'LocalisationValidator.validate_localisation_only(staged_campaign_path)',
    'DirAccess.rename_absolute(staging, target)',
)

settings = read("src/game/player_settings.gd")
require(
    "src/game/player_settings.gd",
    settings,
    [
        'CURRENT_SCHEMA := 3',
        'LocalisationCatalog = preload("res://src/content/localisation_catalog.gd")',
        '"language": LocalisationCatalog.DEFAULT_LOCALE',
        '"id": "language"',
        '"kind": "choice"',
        'LocalisationCatalog.supported_player_locales()',
        'static func string(',
        'LocalisationCatalog.sanitize_player_locale',
        'ui.settings.language',
    ],
)

app = read("src/app.gd")
require(
    "src/app.gd",
    app,
    [
        'LocalisationCatalog = preload("res://src/content/localisation_catalog.gd")',
        'LocalisationLayout = preload("res://src/content/localisation_layout.gd")',
        'localisation_catalog: Dictionary = LocalisationCatalog.empty_catalog()',
        'current_locale := LocalisationCatalog.DEFAULT_LOCALE',
        'load_localisation_catalogs',
        'set_localisation_locale',
        'TranslationServer.set_locale(current_locale)',
        'localisation_changed',
        'localise',
        'localise_text',
        'localise_record',
        'campaign_title_text',
        'campaign_subtitle_text',
        'localisation_contract_ok',
        'LocalisationLayout.localisation_layout_contract_ok()',
        'draw_fitted_line',
        'draw_fitted_block',
        'intro_keys',
    ],
)
base_runtime = read("src/presentation_runtime_base.gd")
require(
    "src/presentation_runtime_base.gd",
    base_runtime,
    [
        'set_localisation_locale(PlayerSettings.string(player_settings, "language", "en"))',
        'setting_id == "language"',
        'player_setting_string',
        'player_setting_label',
        'player_setting_value_text',
        'ui.settings.language.%s',
        'player_setting_string("language", "en") == current_locale',
        'localisation_contract_ok()',
    ],
)
current_runtime = read("src/presentation_runtime_current.gd")
require(
    "src/presentation_runtime_current.gd",
    current_runtime,
    [
        'func localisation_changed()',
        'rebuild_input_binding_cache(input_binding_profile_cache)',
        'localised_control_action_label',
        'ui.controls.action.%s',
        'ui.game.bound_controls',
    ],
)
for overlay_path in ["src/combat_readability_overlay.gd", "src/player_controls_overlay.gd"]:
    overlay = read(overlay_path)
    require(
        overlay_path,
        overlay,
        [
            "runtime_localise",
            "ui.options.title",
            'LocalisationLayout = preload("res://src/content/localisation_layout.gd")',
            "LocalisationLayout.fit_single_line",
        ],
    )

compile_probe = read("tools/compile_localisation_probe.gd")
require(
    "tools/compile_localisation_probe.gd",
    compile_probe,
    [
        "localisation_catalog.gd",
        "localisation_layout.gd",
        "localisation_validator.gd",
        "player_settings.gd",
        "smoke_localisation.gd",
        "compile_localisation_layout_probe.gd",
        "smoke_localisation_layout.gd",
        "localisation/ui.json",
        "campaigns/epochbound_demo/localisation/core.json",
        "app.tscn",
    ],
)
smoke = read("tools/smoke_localisation.gd")
require(
    "tools/smoke_localisation.gd",
    smoke,
    [
        "Placeholder-parity rejection",
        "JSON numeric schema one must validate after a disk parse",
        "Fractional localisation schema values must fail closed",
        "Campaign localisation paths must reject traversal",
        "Schema-two settings must migrate to schema three",
        "Default campaign localisation scaffolding must validate",
        "Title menu must refresh through deterministic pseudo-localisation",
        "Locale change must rebuild cached control labels exactly at the mutation boundary",
        "Switching back to English must restore exact authored UI copy",
    ],
)
scaffold = read("tools/smoke_sprite_campaign_scaffold.gd")
require(
    "tools/smoke_sprite_campaign_scaffold.gd",
    scaffold,
    [
        'LOCALISATION_PATH',
        'localisation/core.json',
        'localisation_message_count',
        'Audio, Sprite Animation and Localisation catalogues',
    ],
)
content_validation = read("tools/validate_content.gd")
require(
    "tools/validate_content.gd",
    content_validation,
    ["localisation locale(s)", "localisation message(s)", 'localisation_locale_count', 'localisation_message_count'],
)
runtime_contract = read("src/game/runtime_scene_contract.gd")
require(
    "src/game/runtime_scene_contract.gd",
    runtime_contract,
    [
        '"set_localisation_locale"',
        '"localise"',
        '"localisation_contract_ok"',
        'Runtime root did not load a valid merged localisation catalogue',
        'Localisation layout utility contract is invalid.',
    ],
)

local_gate = read("scripts/validate.ps1")
require(
    "scripts/validate.ps1",
    local_gate,
    [
        "compile_localisation_probe.gd",
        "compile_localisation_layout_probe.gd",
        "smoke_localisation.gd",
        "smoke_localisation_layout.gd",
        "localisation",
    ],
)
for workflow_path in [
    ".github/workflows/validate.yml",
    ".github/workflows/audio-mood-validation.yml",
    ".github/workflows/sprite-animation-validation.yml",
]:
    workflow = read(workflow_path)
    require(
        workflow_path,
        workflow,
        [
            "python3 tools/check_localisation_contract.py",
            "python3 tools/check_localisation_layout_contract.py",
            "compile_localisation_probe.gd" if workflow_path != ".github/workflows/validate.yml" else "scripts/validate.ps1",
            "compile_localisation_layout_probe.gd" if workflow_path != ".github/workflows/validate.yml" else "localisationLayoutValidation",
        ],
    )
primary_workflow = read(".github/workflows/validate.yml")
require(
    ".github/workflows/validate.yml",
    primary_workflow,
    [
        '"schemaVersion": "2.10"',
        '"localisationValidation": "passed"',
        '"localisationLayoutValidation": "passed"',
    ],
)
release_policy = read("tools/check_release_workflow_policy.py")
require(
    "tools/check_release_workflow_policy.py",
    release_policy,
    [
        "python3 tools/check_localisation_contract.py",
        "compile_localisation_probe.gd",
        "compile_localisation_layout_probe.gd",
        "smoke_localisation.gd",
        "smoke_localisation_layout.gd",
        '"schemaVersion": "2.10"',
        '"localisationValidation": "passed"',
        '"localisationLayoutValidation": "passed"',
    ],
)

documentation = read("docs/LOCALISATION_FOUNDATION.md")
require(
    "docs/LOCALISATION_FOUNDATION.md",
    documentation,
    [
        "English remains the authored fallback",
        "qps-ploc",
        "placeholder parity",
        "localisation_files",
        "player-local",
        "campaign saves",
        "packages",
        "not a machine-translation service",
        "Pseudo-localisation",
        "Measured fixed-viewport layout",
        "LOCALISATION_LAYOUT_SAFETY.md",
    ],
)
player_docs = read("docs/PLAYER_SETTINGS.md")
require(
    "docs/PLAYER_SETTINGS.md",
    player_docs,
    [
        "schema 3",
        "Language",
        "English",
        "Pseudo-localisation",
        "localisation setting remains separate from campaign saves",
    ],
)
readme = read("README.md")
require(
    "README.md",
    readme,
    [
        "English and deterministic pseudo-localisation",
        "LOCALISATION_FOUNDATION.md",
        "LOCALISATION_LAYOUT_SAFETY.md",
        "production translations beyond English and pseudo-localisation",
        "schema-2.10",
        "localisationValidation",
        "localisationLayoutValidation",
    ],
)

if errors:
    print("Epochbound localisation contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_localisation_contract_passed")
print("- English remains the exact authored fallback while pseudo-localisation is generated deterministically")
print("- catalogue schema paths duplicate keys locale labels and placeholder parity fail closed")
print("- player-local schema-three language choice stays outside campaign saves and packages")
print("- campaign title subtitle and intro keys retain required fallback copy")
print("- new campaigns scaffold a bound localisation catalogue")
print("- staged package installation validates localisation before promotion")
print("- runtime menus options controls and campaign intro surfaces refresh immediately on locale changes")
print("- measured layout protects current English and pseudo-localised copy with deterministic wrapping and ellipsis")
print("- primary focused and local validation gates cover the complete foundation")
