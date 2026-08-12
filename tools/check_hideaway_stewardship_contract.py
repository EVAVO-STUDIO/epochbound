#!/usr/bin/env python3
"""Fail-closed Archive Hideaway stewardship foundation contract."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "src/game/hideaway_stewardship.gd"
VALIDATOR = ROOT / "src/content/hideaway_stewardship_validator.gd"
DEFINITION = ROOT / "campaigns/epochbound_demo/hideaway_stewardship.json"
COMPILE = ROOT / "tools/compile_hideaway_stewardship_probe.gd"
SMOKE = ROOT / "tools/smoke_hideaway_stewardship.gd"
DOC = ROOT / "docs/ARCHIVE_HIDEAWAY_STEWARDSHIP.md"

for path in [MODEL, VALIDATOR, DEFINITION, COMPILE, SMOKE, DOC]:
    if not path.is_file():
        raise SystemExit(f"missing Archive Hideaway contract file: {path.relative_to(ROOT)}")

model = MODEL.read_text(encoding="utf-8")
validator = VALIDATOR.read_text(encoding="utf-8")
smoke = SMOKE.read_text(encoding="utf-8")
definition = json.loads(DEFINITION.read_text(encoding="utf-8"))

required_model = [
    "class_name HideawayStewardship",
    "MINIMUM_EXPEDITION_SECONDS: float = 90.0",
    "MAX_BANKED_RETURNS: int = 3",
    "MAX_FACILITY_LEVEL: int = 3",
    "archive_hearth",
    "sheltered_coldframe",
    "salvage_workbench",
    "morrows_corner",
    "static func begin_expedition",
    "static func record_return",
    "static func upgrade_facility",
    "static func prepare_facility",
    "static func consume_prepared_effect",
    "numeric != floor(numeric)",
]
for token in required_model:
    if token not in model:
        raise SystemExit(f"Archive Hideaway model contract missing: {token}")

for forbidden in [
    "Time.get_unix_time_from_system",
    "Time.get_datetime",
    "OS.get_unix_time",
    "crop_growth",
    "hunger_tick",
    "thirst_tick",
]:
    if forbidden in model:
        raise SystemExit(
            "Archive Hideaway source introduced forbidden obligation or wall-clock path: "
            f"{forbidden}"
        )

if definition.get("schema_version") != 1 or definition.get("hideaway_id") != "archive_hideaway":
    raise SystemExit("Archive Hideaway definition identity or schema changed")
if definition.get("minimum_expedition_seconds") != 90 or definition.get("max_banked_returns") != 3:
    raise SystemExit("Archive Hideaway expedition bounds changed")
if definition.get("max_salvage") != 99:
    raise SystemExit("Archive Hideaway salvage cap changed")
facilities = definition.get("facilities")
if not isinstance(facilities, list) or len(facilities) != 4:
    raise SystemExit("Archive Hideaway must retain exactly four facilities")
expected = {
    "archive_hearth",
    "sheltered_coldframe",
    "salvage_workbench",
    "morrows_corner",
}
if {entry.get("id") for entry in facilities if isinstance(entry, dict)} != expected:
    raise SystemExit("Archive Hideaway facility IDs changed")

for token in [
    "sub-threshold expedition must not qualify",
    "duplicate return must not award twice",
    "banked returns must remain capped",
    "JSON round trip must preserve valid durable state",
    "fractional durable counters must fail closed",
    "time alone must not create offline progress",
]:
    if token not in smoke:
        raise SystemExit(f"Archive Hideaway smoke coverage missing: {token}")

for token in ["extends RefCounted", "validate_definition", "_validate_costs", "max_salvage"]:
    if token not in validator:
        raise SystemExit(f"strict Hideaway definition validator is incomplete: {token}")

print("epochbound_hideaway_stewardship_contract_passed")
print("- active-play expeditions require ninety seconds and cannot double-award")
print("- exact-integral JSON numbers restore while fractional durable counters fail closed")
print("- return opportunities salvage facility levels and preparation charges stay bounded")
print("- four authored refuge facilities preserve a quiet survival-preparation identity")
print("- wall-clock progress hunger thirst forced sleep and daily chores remain excluded")
