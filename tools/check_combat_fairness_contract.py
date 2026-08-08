#!/usr/bin/env python3
"""Fail closed when Epochbound's combat telegraph fairness contract drifts."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(name: str, relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.is_file():
        errors.append(f"{name}: required file is missing: {relative_path}")
        return ""
    return path.read_text(encoding="utf-8")


def require(name: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token not in source:
            errors.append(f"{name}: missing {token}")


def forbid(name: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token in source:
            errors.append(f"{name}: contains forbidden {token}")


def require_order(name: str, source: str, tokens: list[str]) -> None:
    cursor = -1
    for token in tokens:
        position = source.find(token, cursor + 1)
        if position < 0:
            errors.append(f"{name}: missing ordered token {token}")
            return
        cursor = position


def function_body(name: str, source: str, function_name: str) -> str:
    marker = f"\nfunc {function_name}("
    start = source.find(marker)
    if start < 0:
        errors.append(f"{name}: missing function {function_name}")
        return ""
    next_function = source.find("\n\nfunc ", start + len(marker))
    return source[start:] if next_function < 0 else source[start:next_function]


runtime = read("combat_runtime", "src/combat_director_runtime.gd")
sync_body = function_body("combat_runtime", runtime, "sync_runtime_entities")
enemy_body = function_body("combat_runtime", runtime, "update_directed_enemy")
damage_body = function_body("combat_runtime", runtime, "damage_entity")
require(
    "combat_runtime",
    runtime,
    [
        'entity["attack_target_id"] = str(old.get("attack_target_id", ""))',
        "func attack_target_is_available(actor_id: String) -> bool:",
        "func attack_target_position(actor_id: String) -> Vector2:",
        'var locked_target_id := str(entity.get("attack_target_id", ""))',
        "attack_target_is_available(locked_target_id)",
        "attack_target_position(locked_target_id)",
        "damage_actor(locked_target_id",
        'entity["attack_target_id"] = target_name',
        "MAX_NON_BOSS_WINDUPS_PER_TARGET := 1",
        "func attack_pressure_slot_available(",
        "func uses_shared_attack_pressure_slot(",
        'entity["mode"] = "pressure"',
    ],
)
require(
    "combat_runtime_sync",
    sync_body,
    ['entity["attack_target_id"] = str(old.get("attack_target_id", ""))'],
)
require_order(
    "combat_runtime_windup",
    enemy_body,
    [
        'var locked_target_id := str(entity.get("attack_target_id", ""))',
        "attack_target_is_available(locked_target_id)",
        "attack_target_position(locked_target_id)",
        "damage_actor(locked_target_id",
        'entity["attack_target_id"] = ""',
    ],
)
require_order(
    "combat_runtime_pressure",
    enemy_body,
    [
        "attack_pressure_slot_available(index, target_name, definition_data)",
        'entity["attack_windup"] = maxf(',
        'entity["mode"] = "pressure"',
    ],
)
require_order(
    "combat_runtime_interrupt",
    damage_body,
    [
        'entity["attack_windup"] = 0.0',
        'entity["attack_target_id"] = ""',
        'entity["stagger_timer"] = stagger',
        'entity["mode"] = "staggered"',
    ],
)
forbid(
    "combat_runtime",
    runtime,
    [
        "damage_actor(target_name",
        "Time.get_unix_time",
        "OS.get_unix_time",
        "randf(",
        "randi(",
    ],
)

smoke = read("combat_smoke", "tools/smoke_combat_director.gd")
require(
    "combat_smoke",
    smoke,
    [
        "Windup must lock the selected target identity.",
        "A closer companion must not inherit the player's active telegraph.",
        "Stagger must cancel the pending attack windup.",
        "Stagger must clear the pending attack target.",
        "Interrupted windup must not deal deferred damage after stagger.",
        "A post-stagger attack must begin a fresh telegraph.",
        "Only one ordinary enemy may own a windup against the same actor.",
        "The waiting enemy must enter pressure mode.",
        "Attack pressure must hand the next telegraph to the waiting enemy.",
        "Pressure coordination must not add untelegraphed damage.",
        "target locking, interruptible windup, one-slot ordinary-enemy pressure",
    ],
)

documentation = read("combat_documentation", "docs/COMBAT_DIRECTOR.md")
require(
    "combat_documentation",
    documentation,
    [
        "Target identity is locked when windup begins",
        "A successful stagger cancels an in-progress windup",
        "fresh full windup",
        "A telegraph cannot silently transfer",
        "target locking and stagger interruption",
        "one active windup slot per actor",
        "Pressure",
        "Boss definitions do not consume",
    ],
)

fairness_doc = read("combat_fairness_documentation", "docs/COMBAT_FAIRNESS_CONTRACT.md")
require(
    "combat_fairness_documentation",
    fairness_doc,
    [
        "windup locks target identity",
        "stagger cancels pending damage",
        "A paused pre-hit telegraph must never resume and land later",
        "attack_target_id",
        "ordinary enemies share one active melee windup slot",
        "Bosses do not consume the ordinary-enemy slot",
        "Deterministic verification",
    ],
)

local_gate = read("local_gate", "scripts/validate.ps1")
require(
    "local_gate",
    local_gate,
    [
        "Smoke test Combat Director target locking stagger interrupts and pressure budget",
        "smoke_combat_director.gd",
        "locked combat telegraphs",
        "stagger interrupts",
        "ordinary-enemy pressure budget",
    ],
)

workflow = read("validate_workflow", ".github/workflows/validate.yml")
require(
    "validate_workflow",
    workflow,
    [
        "Validate combat telegraph fairness contract",
        "python3 tools/check_combat_fairness_contract.py",
        '# Receipt schema migrated from: "schemaVersion": "2.5"',
        '"schemaVersion": "2.6"',
        '"combatFairnessValidation": "passed"',
    ],
)

release_policy = read("release_policy", "tools/check_release_workflow_policy.py")
require(
    "release_policy",
    release_policy,
    [
        "python3 tools/check_combat_fairness_contract.py",
        '"schemaVersion": "2.6"',
        '"combatFairnessValidation": "passed"',
        "check_combat_fairness_contract.py",
        "locked combat telegraphs",
        "stagger interrupts",
        "ordinary-enemy pressure budget",
    ],
)

if errors:
    print("Epochbound combat fairness contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_combat_fairness_contract_passed")
print("- windups retain one actor identity from telegraph start through resolution")
print("- a closer actor cannot inherit an existing pending attack")
print("- stagger clears both the pending timer and target before recovery")
print("- interrupted enemies must begin a fresh telegraph before later damage")
print("- ordinary enemies share one active melee windup per target while bosses remain exempt")
print("- waiting enemies use deterministic pressure state and inherit the next available telegraph")
print("- runtime, smoke, documentation, local and exact-main gates remain pinned")
