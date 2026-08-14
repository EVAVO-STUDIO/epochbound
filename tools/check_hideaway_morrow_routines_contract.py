#!/usr/bin/env python3
"""Fail closed when Archive Hideaway Morrow ambient routines drift."""
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


model_path = "src/game/hideaway_morrow_routine_model.gd"
model = read(model_path)
require(model_path, model, [
    "class_name HideawayMorrowRoutineModel",
    "MAX_ROUTINES := 12",
    "MIN_DURATION_SECONDS := 3.0",
    "MAX_DURATION_SECONDS := 12.0",
    "MAX_OFFSET_COMPONENT := 96.0",
    '"always"', '"state_equals"', '"return_count_at_least"',
    '"refuge_tier_at_least"', '"facility_level_at_least"',
    '"watch"', '"sniff"', '"warm"', '"listen"', '"curl"', '"sleep"',
    "available_entries", "entry_available", "available_in_era", "condition_met",
    "anchor_interaction_id", "offset", "duration_seconds", "pose_id",
    "routine_contract_ok",
])
forbid(model_path, model, [
    "Time.get_", "OS.delay", "HTTPRequest", "HTTPClient", "randf", "randi",
    "grant_currency", "grant_item", "add_salvage", "session_state[",
])

validator_path = "src/content/hideaway_stewardship_validator.gd"
validator = read(validator_path)
require(validator_path, validator, [
    'MORROW_ROUTINES := preload("res://src/game/hideaway_morrow_routine_model.gd")',
    '"morrow_routines"', "_validate_morrow_routines", "_validate_morrow_routine_conditions",
    "morrow_routine_forbidden_field", "morrow_routine_anchor_missing",
    "morrow_routines_read_only", "morrow_routine_rewards",
    "morrow_routines_advance_time", "morrow_routines_override_commands",
    "hideaway_morrow_routine_count", "validate_campaign_binding_for_test",
])

definition_path = "campaigns/epochbound_demo/hideaway_stewardship.json"
definition = read_json(definition_path)
routines = definition.get("morrow_routines", [])
expected_ids = [
    "threshold_watch", "first_return_pack", "hearth_sprawl", "coldframe_scent",
    "cinder_glass_watch", "workbench_listen", "corner_curl", "haven_sleep",
]
if not isinstance(routines, list) or len(routines) != 8:
    errors.append(f"{definition_path}: expected exactly eight reference Morrow routines")
elif [entry.get("id") for entry in routines if isinstance(entry, dict)] != expected_ids:
    errors.append(f"{definition_path}: Morrow routine order or IDs drifted")
else:
    always_count = 0
    for entry in routines:
        if not isinstance(entry, dict):
            continue
        if entry.get("pose") not in {"watch", "sniff", "warm", "listen", "curl", "sleep"}:
            errors.append(f"{definition_path}: {entry.get('id')} has an unsupported pose")
        if not isinstance(entry.get("anchor_interaction_id"), str) or not entry["anchor_interaction_id"]:
            errors.append(f"{definition_path}: {entry.get('id')} lacks an authored interaction anchor")
        duration = entry.get("duration_seconds")
        if not isinstance(duration, (int, float)) or not 3 <= float(duration) <= 12:
            errors.append(f"{definition_path}: {entry.get('id')} duration is outside 3-12 seconds")
        conditions = entry.get("conditions")
        if not isinstance(conditions, list) or not conditions:
            errors.append(f"{definition_path}: {entry.get('id')} requires derived conditions")
        else:
            always_count += sum(1 for c in conditions if isinstance(c, dict) and c.get("type") == "always")
        for forbidden_field in ["effects", "rewards", "reward", "grant", "salvage", "time_advance", "save_key"]:
            if forbidden_field in entry:
                errors.append(f"{definition_path}: {entry.get('id')} contains forbidden {forbidden_field}")
    if always_count != 1:
        errors.append(f"{definition_path}: exactly one baseline always Morrow routine is required")

boundaries = definition.get("design_boundaries", {})
for key, expected in {
    "morrow_routines_read_only": True,
    "morrow_routine_rewards": False,
    "morrow_routines_advance_time": False,
    "morrow_routines_override_commands": False,
}.items():
    if boundaries.get(key) is not expected:
        errors.append(f"{definition_path}: {key} must remain {expected}")

hideaway_map = read_json("campaigns/epochbound_demo/maps/archive_hideaway.json")
interaction_ids = {
    entry.get("id") for entry in hideaway_map.get("interactions", [])
    if isinstance(entry, dict)
}
for entry in routines if isinstance(routines, list) else []:
    if isinstance(entry, dict) and entry.get("anchor_interaction_id") not in interaction_ids:
        errors.append(f"Archive Hideaway map lacks routine anchor {entry.get('anchor_interaction_id')}")

for path, token in [
    ("src/content/complete_content_validator.gd", 'output["hideaway_morrow_routine_count"]'),
    ("src/content/campaign_package.gd", 'validation["hideaway_morrow_routine_count"]'),
    ("src/content/package_release_validator.gd", 'output["hideaway_morrow_routine_count"]'),
]:
    require(path, read(path), [token])

runtime_path = "src/hideaway_runtime.gd"
runtime = read(runtime_path)
require(runtime_path, runtime, [
    'HideawayMorrowRoutineModel = preload("res://src/game/hideaway_morrow_routine_model.gd")',
    "HIDEAWAY_MORROW_ROUTINE_ARRIVAL_RADIUS := 8.0",
    "HIDEAWAY_MORROW_ROUTINE_OVERRIDE_SECONDS := 4.0",
    "available_hideaway_morrow_routines", "hideaway_morrow_routine_summary",
    "hideaway_morrow_routines_should_run", "current_hideaway_morrow_routine",
    "hideaway_morrow_routine_target", "advance_hideaway_morrow_routine",
    "suspend_hideaway_morrow_routines", "hideaway_morrow_routine_visual_descriptor",
    "ui.hideaway.morrow_routine.arrived", "ui.hideaway.status.morrow_routine",
    'companion_command == "follow"', "super.set_companion_command(command)",
    "super.recall_companion()",
])
forbid(runtime_path, runtime, [
    "Time.get_unix_time_from_system", "Time.get_ticks_msec", "morrow_routine_reward",
    "hideaway:morrow_routine", "randf", "randi",
])

ui = read_json("localisation/ui.json")
messages = ui.get("messages", {}) if isinstance(ui, dict) else {}
for entry in routines if isinstance(routines, list) else []:
    if not isinstance(entry, dict):
        continue
    key, fallback = entry.get("display_name_key"), entry.get("display_name")
    value = messages.get(key) if isinstance(messages, dict) else None
    if not isinstance(value, dict) or value.get("en") != fallback:
        errors.append(f"localisation/ui.json: English fallback mismatch for {key}")
for key in ["ui.hideaway.morrow_routine.arrived", "ui.hideaway.status.morrow_routine"]:
    value = messages.get(key) if isinstance(messages, dict) else None
    if not isinstance(value, dict) or not isinstance(value.get("en"), str) or not value["en"].strip():
        errors.append(f"localisation/ui.json: missing English {key}")

for path, tokens in {
    "tools/compile_hideaway_morrow_routine_probe.gd": ["src/game/hideaway_morrow_routine_model.gd", "smoke_hideaway_morrow_routines.gd", "Godot 4.6.2"],
    "tools/smoke_hideaway_morrow_routines.gd": ["eight Morrow routines", "new journeys must begin with one calm threshold routine", "Morrow routines must reject reward payloads", "wall-clock routine conditions must fail closed", "never overrides player commands"],
    "tools/smoke_hideaway_runtime.gd": ["Morrow routine", "available_hideaway_morrow_routines", "hideaway_morrow_routine_summary", "player command must pause ambient routines"],
    "tools/smoke_localisation_layout.gd": ['"ui.hideaway.status.morrow_routine"', '"width": 464.0'],
    "scripts/validate.ps1": ["Validate Archive Hideaway Morrow routine contract", "python3 tools/check_hideaway_morrow_routines_contract.py", "Compile Archive Hideaway Morrow routines", "res://tools/compile_hideaway_morrow_routine_probe.gd", "Smoke test optional Archive Hideaway Morrow routines", "res://tools/smoke_hideaway_morrow_routines.gd"],
    ".github/workflows/validate.yml": ["Validate Archive Hideaway Morrow routine contract", "python3 tools/check_hideaway_morrow_routines_contract.py", '"hideawayMorrowRoutineValidation": "passed"'],
    "docs/ARCHIVE_HIDEAWAY_MORROW_ROUTINES.md": ["Threshold Watch", "Both Ears Down", "Player commands always win", "No new save field", "active in-session delta"],
    "docs/ARCHIVE_HIDEAWAY_RUNTIME.md": ["Living Morrow routines", "player commands always win"],
    "README.md": ["living Morrow refuge routines", "no new save field, reward or chore loop"],
}.items():
    require(path, read(path), tokens)

if errors:
    print("Epochbound Archive Hideaway Morrow routine contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_hideaway_morrow_routines_contract_passed")
print("- eight optional companion routines derive from existing return facility era and refuge state")
print("- player commands and recall always override ambient refuge movement")
print("- routines use active in-session delta only and write no save fields or unlock lists")
print("- authored anchors localisation package validation and exact-main evidence remain pinned")
