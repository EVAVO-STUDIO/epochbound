#!/usr/bin/env python3
"""Fail closed when Epochbound's canonical long-form journey gate drifts."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.is_file():
        errors.append(f"missing required file: {relative_path}")
        return ""
    return path.read_text(encoding="utf-8")


def require(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token not in source:
            errors.append(f"{relative_path}: missing {token}")


def require_order(relative_path: str, source: str, tokens: list[str]) -> None:
    cursor = -1
    for token in tokens:
        position = source.find(token, cursor + 1)
        if position < 0:
            errors.append(f"{relative_path}: missing ordered token {token}")
            return
        cursor = position


journey_path = "tools/smoke_canonical_journey.gd"
journey = read(journey_path)
require(
    journey_path,
    journey,
    [
        'RUNTIME_SCENE := "res://src/app.tscn"',
        'CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"',
        'open_merchant',
        'activate_merchant_selection',
        'reveal_companion_cue',
        'craft_inventory_recipe',
        'authored_requirements_met',
        'update_boss_engagements',
        'finish_cinematic',
        'shift_to_next_era',
        'damage_entity',
        'finalize_boss_outcomes',
        'capture_save_profile',
        'apply_save_profile',
        'underworks:boss:sentinel',
        'A restored completed boss must not remain engaged',
    ],
)
require_order(
    journey_path,
    journey,
    [
        'open_merchant',
        'capture_save_profile',
        'apply_save_profile',
        'craft_inventory_recipe',
        'update_boss_engagements',
        'finalize_boss_outcomes',
        'capture_save_profile',
        'apply_save_profile',
    ],
)
for forbidden in [
    "Time.get_unix_time",
    "OS.get_unix_time",
    "randf(",
    "randi(",
    "SaveProfileStore.write_profile",
    "SaveProfileStore.read_profile",
]:
    if forbidden in journey:
        errors.append(f"{journey_path}: contains forbidden {forbidden}")

local_gate_path = "scripts/validate.ps1"
local_gate = read(local_gate_path)
require(
    local_gate_path,
    local_gate,
    [
        'Smoke test canonical long-form reference journey',
        'res://tools/smoke_canonical_journey.gd',
        'long-form journey',
    ],
)
require_order(
    local_gate_path,
    local_gate,
    [
        'Validate campaign content',
        'Run deterministic campaign production audit',
        'Smoke test canonical long-form reference journey',
        'Smoke test world model and traversal',
    ],
)

documentation_path = "docs/CANONICAL_JOURNEY_GATE.md"
documentation = read(documentation_path)
require(
    documentation_path,
    documentation,
    [
        'res://tools/smoke_canonical_journey.gd',
        'two checksummed profiles',
        'Determinism and safety',
        'does not use wall-clock time',
        'not a substitute for hands-on Windows playtesting',
    ],
)

workflow_path = ".github/workflows/validate.yml"
workflow = read(workflow_path)
require(
    workflow_path,
    workflow,
    [
        'python3 tools/check_canonical_journey_contract.py',
        '"canonicalJourneyValidation": "passed"',
        'scripts/validate.ps1',
    ],
)

release_policy_path = "tools/check_release_workflow_policy.py"
release_policy = read(release_policy_path)
require(
    release_policy_path,
    release_policy,
    [
        'python3 tools/check_canonical_journey_contract.py',
        '"canonicalJourneyValidation": "passed"',
    ],
)

if errors:
    print("Epochbound canonical journey contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_canonical_journey_contract_passed")
print("- the playable reference route crosses economy, discovery, crafting, travel, boss and save boundaries")
print("- two in-memory checksummed restorations remain part of the release gate")
print("- content validation and deterministic audit run before the journey")
print("- wall-clock, random-input and external save-file shortcuts remain forbidden")
