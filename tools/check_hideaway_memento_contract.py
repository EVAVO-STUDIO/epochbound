#!/usr/bin/env python3
"""Fail closed when Archive Hideaway journey mementos drift."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(path: str) -> str:
    target = ROOT / path
    if not target.is_file():
        errors.append(f"missing required file: {path}")
        return ""
    return target.read_text(encoding="utf-8")


def read_json(path: str) -> dict:
    source = read(path)
    if not source:
        return {}
    try:
        value = json.loads(source)
    except json.JSONDecodeError as exc:
        errors.append(f"{path}: invalid JSON: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{path}: root must be an object")
        return {}
    return value


def require(path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token not in source:
            errors.append(f"{path}: missing {token}")


def forbid(path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token in source:
            errors.append(f"{path}: contains forbidden {token}")


model_path = "src/game/hideaway_memento_model.gd"
model = read(model_path)
require(model_path, model, [
    "class_name HideawayMementoModel",
    'SHELF_KIND := "hideaway_memento_shelf"',
    "MAX_MEMENTOS := 12",
    "state_equals",
    "return_count_at_least",
    "refuge_tier_at_least",
    "unlocked_entries",
    "entry_unlocked",
    "values_equal",
    "reflection_key",
    "reflection_fallback",
    "memento_contract_ok",
])
forbid(model_path, model, [
    "Time.get_",
    "OS.delay",
    "HTTPRequest",
    "HTTPClient",
    "grant_currency",
    "grant_item",
    "grant_clock_shards",
    "add_salvage",
    "session_state[",
])

validator_path = "src/content/hideaway_stewardship_validator.gd"
validator = read(validator_path)
require(validator_path, validator, [
    'CAMPAIGN_FIELD := "hideaway_stewardship_file"',
    'UI_CATALOG_PATH := "res://localisation/ui.json"',
    '"memento_shelf"',
    '"mementos"',
    "validate_hideaway_only",
    "_validate_memento_shelf",
    "_validate_mementos",
    "_validate_conditions",
    "_validate_ui_catalog",
    "_validate_campaign_binding",
    "memento_count_exceeds_shelf",
    "memento_forbidden_field",
    "memento_rewards",
    "memento_unlocks_derived",
    "hideaway_memento_count",
])

definition_path = "campaigns/epochbound_demo/hideaway_stewardship.json"
definition = read_json(definition_path)
mementos = definition.get("mementos", [])
if not isinstance(mementos, list) or len(mementos) != 6:
    errors.append(f"{definition_path}: expected exactly six reference mementos")
else:
    expected_ids = [
        "first_safe_return",
        "well_name_rubbing",
        "absent_chime_case",
        "quieted_ash_mark",
        "released_accession_plate",
        "archive_haven_key",
    ]
    if [entry.get("id") for entry in mementos if isinstance(entry, dict)] != expected_ids:
        errors.append(f"{definition_path}: memento order or IDs drifted")
    for entry in mementos:
        if not isinstance(entry, dict):
            continue
        for forbidden_field in ["effects", "rewards", "reward", "grant", "salvage"]:
            if forbidden_field in entry:
                errors.append(f"{definition_path}: {entry.get('id')} contains forbidden {forbidden_field}")
        if not isinstance(entry.get("conditions"), list) or not entry["conditions"]:
            errors.append(f"{definition_path}: {entry.get('id')} requires derived conditions")
shelf = definition.get("memento_shelf", {})
if shelf != {
    "interaction_id": "memento_shelf_station",
    "kind": "hideaway_memento_shelf",
    "maximum_slots": 6,
}:
    errors.append(f"{definition_path}: reference shelf contract drifted")
boundaries = definition.get("design_boundaries", {})
if boundaries.get("memento_unlocks_derived") is not True or boundaries.get("memento_rewards") is not False:
    errors.append(f"{definition_path}: memento design boundaries must remain derived and reward-free")

campaign = read_json("campaigns/epochbound_demo/campaign.json")
if campaign.get("hideaway_stewardship_file") != "hideaway_stewardship.json":
    errors.append("reference campaign must bind hideaway_stewardship.json")
hideaway_map = read_json("campaigns/epochbound_demo/maps/archive_hideaway.json")
shelf_records = [
    entry
    for entry in hideaway_map.get("interactions", [])
    if isinstance(entry, dict) and entry.get("id") == "memento_shelf_station"
]
if len(shelf_records) != 1 or shelf_records[0].get("kind") != "hideaway_memento_shelf":
    errors.append("Archive Hideaway map must expose exactly one authored memento shelf")

runtime_path = "src/hideaway_runtime.gd"
runtime = read(runtime_path)
require(runtime_path, runtime, [
    'HideawayMementoModel = preload("res://src/game/hideaway_memento_model.gd")',
    'HideawayStewardshipValidator = preload("res://src/content/hideaway_stewardship_validator.gd")',
    'HIDEAWAY_MEMENTO_KIND := "hideaway_memento_shelf"',
    "hideaway_definition_snapshot",
    "unlocked_hideaway_mementos",
    "hideaway_memento_summary",
    "nearest_hideaway_memento_shelf",
    "inspect_hideaway_memento",
    "hideaway_memento_name",
    "hideaway_memento_reflection",
    "hideaway_memento_visual_descriptor",
    "draw_hideaway_memento_shelf",
    "draw_hideaway_memento_symbol",
    "ui.hideaway.status.mementos",
    "ui.hideaway.controls.mementos",
    "NOTHING IS CONSUMED",
])
forbidden_runtime = [
    "Time.get_unix_time_from_system",
    "Time.get_ticks_msec",
    "offline_memento",
    "memento_reward",
]
forbid(runtime_path, runtime, forbidden_runtime)

complete = read("src/content/complete_content_validator.gd")
require("src/content/complete_content_validator.gd", complete, [
    'HideawayValidator = preload("res://src/content/hideaway_stewardship_validator.gd")',
    "HideawayValidator.validate_hideaway_only",
    'output["hideaway_memento_count"]',
])
package = read("src/content/campaign_package.gd")
require("src/content/campaign_package.gd", package, [
    'HideawayValidator = preload("res://src/content/hideaway_stewardship_validator.gd")',
    "HideawayValidator.validate_hideaway_only(staged_campaign_path)",
    'validation["hideaway_memento_count"]',
])
release = read("src/content/package_release_validator.gd")
require("src/content/package_release_validator.gd", release, [
    'HideawayValidator = preload("res://src/content/hideaway_stewardship_validator.gd")',
    "HideawayValidator.validate_hideaway_only(campaign_path)",
])

ui = read_json("localisation/ui.json")
messages = ui.get("messages", {}) if isinstance(ui, dict) else {}
for entry in mementos if isinstance(mementos, list) else []:
    if not isinstance(entry, dict):
        continue
    pairs = [(entry.get("display_name_key"), entry.get("display_name"))]
    reflection_keys = entry.get("reflection_keys", {})
    reflection = entry.get("reflection", {})
    for era in ["verdant", "ashen"]:
        pairs.append((reflection_keys.get(era), reflection.get(era)))
    for key, fallback in pairs:
        value = messages.get(key) if isinstance(messages, dict) else None
        if not isinstance(value, dict) or value.get("en") != fallback:
            errors.append(f"localisation/ui.json: English fallback mismatch for {key}")
for key in [
    "ui.hideaway.memento.none",
    "ui.hideaway.status.mementos",
    "ui.hideaway.controls.mementos",
]:
    value = messages.get(key) if isinstance(messages, dict) else None
    if not isinstance(value, dict) or not isinstance(value.get("en"), str) or not value["en"].strip():
        errors.append(f"localisation/ui.json: missing English {key}")

for path, tokens in {
    "tools/compile_hideaway_memento_probe.gd": [
        "src/game/hideaway_memento_model.gd",
        "smoke_hideaway_mementos.gd",
        "Godot 4.6.2",
    ],
    "tools/smoke_hideaway_mementos.gd": [
        "new journeys must begin with an empty memento shelf",
        "existing campaign milestones",
        "mementos must reject reward payloads",
        "wall-clock unlock conditions must fail closed",
    ],
    "tools/smoke_hideaway_runtime.gd": [
        "first safe-return memento",
        "Remembering a memento must not spend or mutate campaign state",
        "unlock all six mementos without new saved flags",
        "deterministic pseudo-localisation",
    ],
    "tools/smoke_localisation_layout.gd": [
        '"ui.hideaway.status.mementos"',
        '"ui.hideaway.controls.mementos"',
        '"width": 464.0',
    ],
    "scripts/validate.ps1": [
        "Validate Archive Hideaway memento contract",
        "python3 tools/check_hideaway_memento_contract.py",
        "Compile Archive Hideaway memento model and shelf",
        "res://tools/compile_hideaway_memento_probe.gd",
        "Smoke test Archive Hideaway journey mementos",
        "res://tools/smoke_hideaway_mementos.gd",
    ],
    ".github/workflows/validate.yml": [
        "Validate Archive Hideaway memento contract",
        "python3 tools/check_hideaway_memento_contract.py",
        '"hideawayMementoValidation": "passed"',
    ],
    "docs/ARCHIVE_HIDEAWAY_MEMENTOS.md": [
        "First Safe Return",
        "Archive Haven Key",
        "No new save field",
        "No reward payload",
    ],
    "docs/ARCHIVE_HIDEAWAY_RUNTIME.md": [
        "Journey memento shelf",
        "Nothing is consumed",
    ],
    "README.md": [
        "journey memento shelf",
        "existing campaign milestones",
    ],
}.items():
    require(path, read(path), tokens)

if errors:
    print("Epochbound Archive Hideaway memento contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_hideaway_memento_contract_passed")
print("- six authored memories unlock from existing campaign and refuge milestones")
print("- shelf inspection is reflective and cannot grant or consume resources")
print("- definitions, map binding, English fallback and package promotion fail closed")
print("- fixed-viewport status, deterministic symbols and both era reflections remain covered")
print("- mementos add no save schema, wall-clock growth or obligation loop")
