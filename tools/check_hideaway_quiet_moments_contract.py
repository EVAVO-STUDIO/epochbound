#!/usr/bin/env python3
"""Fail closed when Archive Hideaway optional hearthside moments drift."""
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


model_path = "src/game/hideaway_quiet_moment_model.gd"
model = read(model_path)
require(model_path, model, [
    "class_name HideawayQuietMomentModel",
    'NOOK_KIND := "hideaway_quiet_moments"',
    "MAX_MOMENTS := 12",
    '"always"',
    '"state_equals"',
    '"return_count_at_least"',
    '"refuge_tier_at_least"',
    '"facility_level_at_least"',
    "available_entries",
    "entry_available",
    "condition_met",
    "nook_slots",
    "nook_interaction_id",
    "quiet_moment_contract_ok",
])
forbid(model_path, model, [
    "Time.get_", "OS.delay", "HTTPRequest", "HTTPClient",
    "grant_currency", "grant_item", "add_salvage", "session_state[",
])

validator_path = "src/content/hideaway_stewardship_validator.gd"
validator = read(validator_path)
require(validator_path, validator, [
    'QUIET_MOMENTS := preload("res://src/game/hideaway_quiet_moment_model.gd")',
    '"quiet_nook"', '"quiet_moments"',
    "_validate_quiet_nook", "_validate_quiet_moments", "_validate_quiet_conditions",
    "quiet_moment_count_exceeds_nook", "quiet_moment_forbidden_field",
    "quiet_moments_read_only", "quiet_moment_rewards", "quiet_moments_advance_time",
    "hideaway_quiet_moment_count",
])

definition_path = "campaigns/epochbound_demo/hideaway_stewardship.json"
definition = read_json(definition_path)
moments = definition.get("quiet_moments", [])
expected_ids = [
    "threshold_breaths", "first_return_watch", "hearth_watch", "coldframe_rain",
    "quiet_tools", "both_ears_down", "borrowed_hour", "archive_haven_stillness",
]
if not isinstance(moments, list) or len(moments) != 8:
    errors.append(f"{definition_path}: expected exactly eight reference quiet moments")
elif [entry.get("id") for entry in moments if isinstance(entry, dict)] != expected_ids:
    errors.append(f"{definition_path}: quiet moment order or IDs drifted")
else:
    always_count = 0
    for entry in moments:
        if not isinstance(entry, dict):
            continue
        if entry.get("speaker") not in {"eli", "morrow", "together", "hideaway"}:
            errors.append(f"{definition_path}: {entry.get('id')} has an unsupported speaker")
        conditions = entry.get("conditions")
        if not isinstance(conditions, list) or not conditions:
            errors.append(f"{definition_path}: {entry.get('id')} requires derived conditions")
        else:
            always_count += sum(1 for condition in conditions if isinstance(condition, dict) and condition.get("type") == "always")
        for forbidden_field in ["effects", "rewards", "reward", "grant", "salvage", "time_advance"]:
            if forbidden_field in entry:
                errors.append(f"{definition_path}: {entry.get('id')} contains forbidden {forbidden_field}")
    if always_count != 1:
        errors.append(f"{definition_path}: exactly one baseline always moment is required")

if definition.get("quiet_nook") != {
    "interaction_id": "quiet_moments_station",
    "kind": "hideaway_quiet_moments",
    "maximum_moments": 8,
}:
    errors.append(f"{definition_path}: reference quiet nook contract drifted")
boundaries = definition.get("design_boundaries", {})
if boundaries.get("quiet_moments_read_only") is not True:
    errors.append(f"{definition_path}: quiet moments must remain read-only")
if boundaries.get("quiet_moment_rewards") is not False:
    errors.append(f"{definition_path}: quiet moments must remain reward-free")
if boundaries.get("quiet_moments_advance_time") is not False:
    errors.append(f"{definition_path}: quiet moments must not advance time")

hideaway_map = read_json("campaigns/epochbound_demo/maps/archive_hideaway.json")
nook_records = [entry for entry in hideaway_map.get("interactions", []) if isinstance(entry, dict) and entry.get("id") == "quiet_moments_station"]
if len(nook_records) != 1 or nook_records[0].get("kind") != "hideaway_quiet_moments":
    errors.append("Archive Hideaway map must expose exactly one authored quiet-moment nook")

runtime_path = "src/hideaway_runtime.gd"
runtime = read(runtime_path)
require(runtime_path, runtime, [
    'HideawayQuietMomentModel = preload("res://src/game/hideaway_quiet_moment_model.gd")',
    'HIDEAWAY_QUIET_MOMENT_KIND := "hideaway_quiet_moments"',
    "available_hideaway_quiet_moments", "hideaway_quiet_moment_summary",
    "nearest_hideaway_quiet_nook", "inspect_hideaway_quiet_moment",
    "hideaway_quiet_moment_name", "hideaway_quiet_moment_reflection",
    "hideaway_quiet_moment_speaker", "hideaway_quiet_moment_visual_descriptor",
    "draw_hideaway_quiet_nook", "ui.hideaway.status.quiet",
    "ui.hideaway.controls.quiet", "NO TIME PASSES",
])
forbid(runtime_path, runtime, ["Time.get_unix_time_from_system", "Time.get_ticks_msec", "quiet_moment_reward"])

for path, token in [
    ("src/content/complete_content_validator.gd", 'output["hideaway_quiet_moment_count"]'),
    ("src/content/campaign_package.gd", 'validation["hideaway_quiet_moment_count"]'),
    ("src/content/package_release_validator.gd", 'output["hideaway_quiet_moment_count"]'),
]:
    require(path, read(path), [token])

ui = read_json("localisation/ui.json")
messages = ui.get("messages", {}) if isinstance(ui, dict) else {}
for entry in moments if isinstance(moments, list) else []:
    if not isinstance(entry, dict):
        continue
    pairs = [(entry.get("display_name_key"), entry.get("display_name"))]
    keys = entry.get("reflection_keys", {})
    copy = entry.get("reflection", {})
    for era in ["verdant", "ashen"]:
        pairs.append((keys.get(era), copy.get(era)))
    for key, fallback in pairs:
        value = messages.get(key) if isinstance(messages, dict) else None
        if not isinstance(value, dict) or value.get("en") != fallback:
            errors.append(f"localisation/ui.json: English fallback mismatch for {key}")
for key in [
    "ui.hideaway.quiet.none", "ui.hideaway.quiet.speaker.eli",
    "ui.hideaway.quiet.speaker.morrow", "ui.hideaway.quiet.speaker.together",
    "ui.hideaway.quiet.speaker.hideaway", "ui.hideaway.status.quiet",
    "ui.hideaway.controls.quiet",
]:
    value = messages.get(key) if isinstance(messages, dict) else None
    if not isinstance(value, dict) or not isinstance(value.get("en"), str) or not value["en"].strip():
        errors.append(f"localisation/ui.json: missing English {key}")

for path, tokens in {
    "tools/compile_hideaway_quiet_moment_probe.gd": ["src/game/hideaway_quiet_moment_model.gd", "smoke_hideaway_quiet_moments.gd", "Godot 4.6.2"],
    "tools/smoke_hideaway_quiet_moments.gd": ["one authored optional quiet moment", "facility restoration must add optional hearthside moments", "quiet moments must reject reward payloads", "wall-clock quiet moment conditions must fail closed", "advances no time"],
    "tools/smoke_hideaway_runtime.gd": ["one optional read-only hearthside moment", "Authored quiet nook must be reachable", "Listening to a quiet moment must not spend or mutate campaign state", "all eight quiet moments without new saved flags", "Hideaway quiet-moment status"],
    "tools/smoke_localisation_layout.gd": ['"ui.hideaway.status.quiet"', '"ui.hideaway.controls.quiet"', '"width": 464.0'],
    "scripts/validate.ps1": ["Validate Archive Hideaway quiet moment contract", "python3 tools/check_hideaway_quiet_moments_contract.py", "Compile Archive Hideaway quiet moments", "res://tools/compile_hideaway_quiet_moment_probe.gd", "Smoke test optional Archive Hideaway hearthside moments", "res://tools/smoke_hideaway_quiet_moments.gd"],
    ".github/workflows/validate.yml": ["Validate Archive Hideaway quiet moment contract", "python3 tools/check_hideaway_quiet_moments_contract.py", '"hideawayQuietMomentValidation": "passed"'],
    "docs/ARCHIVE_HIDEAWAY_QUIET_MOMENTS.md": ["Threshold Breaths", "Archive Haven Stillness", "No new save field", "No reward payload", "No time advancement"],
    "docs/ARCHIVE_HIDEAWAY_RUNTIME.md": ["Hearthside quiet moments", "No time passes"],
    "README.md": ["optional hearthside moments", "existing return, facility, story and refuge state"],
}.items():
    require(path, read(path), tokens)

if errors:
    print("Epochbound Archive Hideaway quiet moment contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_hideaway_quiet_moments_contract_passed")
print("- eight optional hearthside moments derive from existing return facility story and refuge state")
print("- listening is localised, deterministic and cannot consume resources or advance time")
print("- definitions, speakers, map binding, English fallback and package promotion fail closed")
print("- no new save field, offline reward, maintenance loop or daily obligation is introduced")
