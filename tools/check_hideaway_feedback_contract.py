#!/usr/bin/env python3
"""Fail closed when Archive Hideaway feedback or one-use persistence drifts."""
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


def require(path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token not in source:
            errors.append(f"{path}: missing {token}")


model = read("src/game/hideaway_stewardship.gd")
require("src/game/hideaway_stewardship.gd", model, [
    "requested_award",
    "salvage_before",
    "stored_award",
    "stored_returns",
    "return_opportunities_awarded",
])

runtime = read("src/hideaway_runtime.gd")
require("src/hideaway_runtime.gd", runtime, [
    "hideaway_return_message",
    "ui.hideaway.return.qualified",
    "return_opportunities_awarded",
    "HideawayStewardship.MAX_BANKED_RETURNS",
    "ui.hideaway.return.too_short",
    "HideawayStewardship.MINIMUM_EXPEDITION_SECONDS",
    "ui.hideaway.facility.upgraded.next",
    "ui.hideaway.facility.upgraded.complete",
    "ui.hideaway.facility.prepared",
    "ui.hideaway.host_only.change",
    "ui.hideaway.preparation.applied",
    "ui.hideaway.warmth.absorb",
    "ui.hideaway.status.overview",
    "ui.hideaway.status.restoration",
    "ui.hideaway.status.facility.active",
    "draw_fitted_line",
    "464.0",
])

save = read("src/content/save_validator.gd")
require("src/content/save_validator.gd", save, [
    "HIDEAWAY_TRANSIENT_COUNTER_KEYS",
    '"hideaway:buff:warmth_guard"',
    '"hideaway:buff:repair_strike"',
    '"hideaway:buff:companion_focus"',
    "validate_hideaway_transient_counter",
    "must be 0 or 1",
])

ui_path = ROOT / "localisation/ui.json"
try:
    ui = json.loads(ui_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    errors.append(f"localisation/ui.json: {exc}")
    ui = {}
messages = ui.get("messages", {}) if isinstance(ui, dict) else {}
for key in [
    "ui.hideaway.return.qualified",
    "ui.hideaway.return.too_short",
    "ui.hideaway.facility.upgraded.next",
    "ui.hideaway.facility.upgraded.complete",
    "ui.hideaway.facility.prepared",
    "ui.hideaway.failure.unrestored",
    "ui.hideaway.status.overview",
    "ui.hideaway.status.restoration",
    "ui.hideaway.status.facility.active",
    "ui.hideaway.warmth.absorb",
]:
    entry = messages.get(key) if isinstance(messages, dict) else None
    if not isinstance(entry, dict) or not isinstance(entry.get("en"), str) or not entry["en"].strip():
        errors.append(f"localisation/ui.json: missing English {key}")

for path, tokens in {
    "tools/smoke_hideaway_stewardship.gd": [
        "capped_return",
        "return feedback must report only salvage actually stored",
    ],
    "tools/smoke_hideaway_runtime.gd": [
        "remaining active-play requirement",
        "Fractional Hideaway one-use counters",
        "qps-ploc",
    ],
    "tools/smoke_localisation_layout.gd": [
        '"ui.hideaway.status.overview"',
        '"ui.hideaway.status.restoration"',
        '"ui.hideaway.status.facility.active"',
        '"ui.hideaway.status.facility.complete"',
        '"width": 464.0',
    ],
    "docs/ARCHIVE_HIDEAWAY_RUNTIME.md": [
        "Truthful return feedback",
        "Transient preparation validation",
    ],
}.items():
    require(path, read(path), tokens)

local_gate = read("scripts/validate.ps1")
require("scripts/validate.ps1", local_gate, [
    "Validate Archive Hideaway feedback and persistence contract",
    "python3 tools/check_hideaway_feedback_contract.py",
])

if errors:
    print("Epochbound Archive Hideaway feedback contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_hideaway_feedback_contract_passed")
print("- capped return feedback reports only salvage and opportunities actually stored")
print("- short expeditions publish a visible active-play requirement")
print("- facility, return, status and one-use preparation feedback is localised")
print("- fixed Hideaway status panels use measured bounded fitting")
print("- transient warmth, repair and Morrow-focus counters fail closed outside 0 or 1")
