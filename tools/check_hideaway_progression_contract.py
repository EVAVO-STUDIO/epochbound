#!/usr/bin/env python3
"""Fail closed when Archive Hideaway visible refuge progression drifts."""
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
    "REFUGE_TIER_IDS",
    "return_opportunities_awarded",
    "stored_returns",
    "refuge_summary",
    "refuge_tier_id",
    "facility_status",
    "next_upgrade_cost",
    "preparation_capacity",
    'return &"haven"',
])

runtime = read("src/hideaway_runtime.gd")
require("src/hideaway_runtime.gd", runtime, [
    "HIDEAWAY_STATUS_WIDTH := 464.0",
    "hideaway_facility_visual_descriptor",
    "draw_hideaway_hearth_stage",
    "draw_hideaway_coldframe_stage",
    "draw_hideaway_workbench_stage",
    "draw_hideaway_morrow_stage",
    "draw_hideaway_environment_progression",
    "hideaway_tier_name",
    "hideaway_facility_status_text",
    "hideaway_facility_controls_text",
    "ui.hideaway.status.overview",
    "ui.hideaway.status.restoration",
    "ui.hideaway.status.facility.unrestored",
    "ui.hideaway.status.facility.active",
    "ui.hideaway.status.facility.complete",
    "ui.hideaway.controls.restore",
    "return_opportunities_awarded",
    "HideawayStewardship.MAX_BANKED_RETURNS",
])
for forbidden in [
    "Time.get_unix_time_from_system",
    "Time.get_ticks_msec",
    "hunger =",
    "thirst =",
    "forced_sleep(",
    "crop_growth(",
    "offline_reward(",
]:
    if forbidden in runtime or forbidden in model:
        errors.append(f"Archive Hideaway progression contains forbidden obligation or wall-clock path: {forbidden}")

ui = json.loads((ROOT / "localisation/ui.json").read_text(encoding="utf-8"))
messages = ui.get("messages", {})
for key in [
    "ui.hideaway.return.qualified",
    "ui.hideaway.facility.upgraded.complete",
    "ui.hideaway.facility.upgraded.next",
    "ui.hideaway.facility.prepared",
    "ui.hideaway.status.overview",
    "ui.hideaway.status.restoration",
    "ui.hideaway.status.facility.unrestored",
    "ui.hideaway.status.facility.active",
    "ui.hideaway.status.facility.complete",
    "ui.hideaway.controls.restore",
    "ui.hideaway.controls.active",
    "ui.hideaway.controls.complete",
    "ui.hideaway.tier.unsettled",
    "ui.hideaway.tier.sheltered",
    "ui.hideaway.tier.established",
    "ui.hideaway.tier.haven",
]:
    entry = messages.get(key)
    if not isinstance(entry, dict) or not isinstance(entry.get("en"), str) or not entry["en"].strip():
        errors.append(f"localisation/ui.json: missing English {key}")

for path, tokens in {
    "tools/smoke_hideaway_stewardship.gd": [
        "return_opportunities_awarded",
        "refuge_summary",
        "four total facility levels must establish shelter",
        "eight total facility levels must establish the refuge",
        "Archive Haven",
        "next_upgrade_cost",
    ],
    "tools/smoke_hideaway_runtime.gd": [
        "hideaway_facility_visual_descriptor",
        "cold_stone",
        "chimney_glow",
        "exact next Archive Hearth cost",
        "level-derived capacity",
    ],
    "tools/smoke_localisation_layout.gd": [
        '"ui.hideaway.status.overview"',
        '"ui.hideaway.status.restoration"',
        '"ui.hideaway.status.facility.complete"',
        '"width": 464.0',
    ],
    "docs/ARCHIVE_HIDEAWAY_RUNTIME.md": [
        "Visible refuge progression",
        "Unsettled Refuge",
        "Archive Haven",
        "Capacity-aware planning",
    ],
    "README.md": [
        "visible four-tier refuge progression",
        "exact upgrade costs",
    ],
    "scripts/validate.ps1": [
        "Validate Archive Hideaway visible progression contract",
        "python3 tools/check_hideaway_progression_contract.py",
    ],
}.items():
    require(path, read(path), tokens)

if errors:
    print("Epochbound Archive Hideaway progression contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_hideaway_progression_contract_passed")
print("- four derived refuge tiers reflect the exact sum of existing facility levels")
print("- every facility has deterministic level-specific visual stages without new asset dependencies")
print("- status and dialogue expose exact upgrade costs preparation capacity and storage caps")
print("- return feedback reports actual salvage and return-opportunity deltas at both caps")
print("- progression remains active-play only and introduces no chores decay or save migration")
