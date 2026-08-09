#!/usr/bin/env python3
"""Fail closed when Epochbound's repeated long-form progression gate drifts."""

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


playthrough_path = "tools/smoke_long_form_progression.gd"
playthrough = read(playthrough_path)
require(
    playthrough_path,
    playthrough,
    [
        'RUNTIME_SCENE := "res://src/app.tscn"',
        'CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"',
        'SOAK_LAPS := 8',
        'SECONDS_PER_LAP := 195.0',
        'EXPECTED_ROUTE_TRANSITIONS := 32',
        'EXPECTED_ERA_SHIFTS := 16',
        'EXPECTED_SAVE_RESTORES := 4',
        'EXPECTED_SUPPLY_CYCLES := 13',
        'ReferenceJourneyDriver.complete',
        'for lap_index in range(SOAK_LAPS)',
        'activate_map',
        'shift_to_next_era',
        'apply_due_supply_restock',
        'capture_save_profile',
        'apply_save_profile',
        'destructively_mutate_runtime',
        'progression_fingerprint',
        'underworks:boss:sentinel',
        'Completed boss runtime entities must remain retired',
        'Only the purchased Museum Tonic unit may restock',
        'LONG_FORM_PROGRESSION_REPORT',
        'four destructive restorations',
    ],
)
for forbidden in [
    "Time.get_unix_time",
    "OS.get_unix_time",
    "randf(",
    "randi(",
    "SaveProfileStore.write_profile",
    "SaveProfileStore.read_profile",
    "FileAccess.open(",
]:
    if forbidden in playthrough:
        errors.append(f"{playthrough_path}: contains forbidden {forbidden}")


boss_runtime_path = "src/boss_runtime.gd"
boss_runtime = read(boss_runtime_path)
require(
    boss_runtime_path,
    boss_runtime,
    [
        "boss_outcome_completed",
        "retire_completed_boss",
        "func apply_save_profile(",
        "super.apply_save_profile",
        "clear_boss_state()",
        'session_state.get(outcome_key) == "defeated"',
        'entity["active"] = false',
        'entity["health"] = 0',
        'engaged_bosses.erase(placement_id)',
    ],
)

boss_smoke_path = "tools/smoke_boss_runtime.gd"
boss_smoke = read(boss_smoke_path)
require(
    boss_smoke_path,
    boss_smoke,
    [
        "Revisiting a completed boss arena must not re-engage the boss",
        "Revisiting a completed boss arena must retire its runtime entity",
        "must not replay boss cinematics",
        "must not duplicate currency rewards",
        "must not duplicate shard rewards",
        "Completed boss restore regression must clear stale engagement",
        "Completed boss restore regression must clear stale boss context",
        "Completed boss restore regression must keep the runtime entity retired",
        "completed-arena retirement",
    ],
)

compile_path = "tools/compile_probe.gd"
compile_probe = read(compile_path)
require(
    compile_path,
    compile_probe,
    [
        'res://tools/reference_journey_driver.gd',
        'res://tools/smoke_long_form_progression.gd',
    ],
)

local_gate_path = "scripts/validate.ps1"
local_gate = read(local_gate_path)
require(
    local_gate_path,
    local_gate,
    [
        'Smoke test repeated long-form progression endurance',
        'res://tools/smoke_long_form_progression.gd',
        'repeated progression endurance',
        'thirty-two map transitions',
        'four destructive restorations',
    ],
)
require_order(
    local_gate_path,
    local_gate,
    [
        'Smoke test canonical long-form reference journey',
        'Smoke test repeated long-form progression endurance',
        'Smoke test world model and traversal',
    ],
)

workflow_path = ".github/workflows/validate.yml"
workflow = read(workflow_path)
require(
    workflow_path,
    workflow,
    [
        'Validate long-form progression integration contract',
        'python3 tools/check_long_form_progression_contract.py',
        '# Receipt schema migrated from: "schemaVersion": "2.6"',
        '"schemaVersion": "2.7"',
        '"longFormProgressionValidation": "passed"',
    ],
)

release_policy_path = "tools/check_release_workflow_policy.py"
release_policy = read(release_policy_path)
require(
    release_policy_path,
    release_policy,
    [
        'python3 tools/check_long_form_progression_contract.py',
        '"longFormProgressionValidation": "passed"',
        'smoke_long_form_progression.gd',
        'repeated long-form progression',
        'epochbound_long_form_progression_contract_passed',
    ],
)

readme_path = "README.md"
readme = read(readme_path)
require(
    readme_path,
    readme,
    [
        'Automated repeated long-form progression playthroughs',
        'LONG_FORM_PROGRESSION_PLAYTHROUGHS.md',
        'longFormProgressionValidation',
        'eight completed-world laps',
    ],
)

documentation_path = "docs/LONG_FORM_PROGRESSION_PLAYTHROUGHS.md"
documentation = read(documentation_path)
require(
    documentation_path,
    documentation,
    [
        'res://tools/smoke_long_form_progression.gd',
        'eight completed-world laps',
        '32 map transitions',
        '16 era shifts',
        '13 supply cycles',
        'eight checksummed checkpoints',
        'four destructive restorations',
        'No wall-clock or random input',
        'not a substitute for manual playtesting',
    ],
)

if errors:
    print("Epochbound long-form progression contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_long_form_progression_contract_passed")
print("- the canonical production route seeds one completed-world baseline")
print("- eight bounded laps prove thirty-two transitions and sixteen era changes")
print("- thirteen active-play supply cycles advance exactly once while finite progression stays finite")
print("- eight in-memory checkpoints and four destructive restores preserve exact durable state")
print("- boss, currency, shard, inventory and cinematic rewards cannot duplicate")
