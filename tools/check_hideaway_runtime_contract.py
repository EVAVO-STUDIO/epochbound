#!/usr/bin/env python3
"""Fail closed when the playable Archive Hideaway runtime bridge drifts."""
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


runtime_path = "src/hideaway_runtime.gd"
runtime = read(runtime_path)
require(runtime_path, runtime, [
    'extends "res://src/presentation_runtime_base.gd"',
    'HIDEAWAY_MAP_ID := "archive_hideaway"',
    'HIDEAWAY_STATE_KEY := "hideaway:stewardship"',
    'HIDEAWAY_MEMENTO_KIND := "hideaway_memento_shelf"',
    'HideawayMementoModel = preload("res://src/game/hideaway_memento_model.gd")',
    'HideawayStewardship.begin_expedition',
    'HideawayStewardship.record_return',
    'upgrade_hideaway_facility',
    'prepare_hideaway_facility',
    'apply_hideaway_departure_preparation',
    'hideaway_has_durable_authority',
    'str(online.get("mode")) != "client"',
    'HIDEAWAY_WARMTH_REDUCTION := 2',
    'HIDEAWAY_BONUS_DAMAGE := 2',
    'draw_hideaway_facilities',
    'draw_hideaway_status',
    'hideaway_return_message',
    'ui.hideaway.return.too_short',
    'ui.hideaway.status.overview',
    'ui.hideaway.status.restoration',
    'hideaway_facility_visual_descriptor',
    'hideaway_memento_visual_descriptor',
    'draw_hideaway_memento_shelf',
    'inspect_hideaway_memento',
    'ui.hideaway.status.mementos',
    'hideaway_tier_name',
    'draw_fitted_line',
    'hideaway_runtime_contract_ok',
])
for forbidden in [
    "Time.get_unix_time_from_system",
    "Time.get_ticks_msec",
    "OS.delay_msec",
    "hunger",
    "thirst",
    "forced_sleep",
    "crop_growth",
]:
    if forbidden in runtime:
        errors.append(f"{runtime_path}: contains forbidden obligation or wall-clock path {forbidden}")

presentation_root = read("src/presentation_runtime_current.gd")
require(
    "src/presentation_runtime_current.gd",
    presentation_root,
    ['extends "res://src/hideaway_runtime.gd"'],
)

scene = read("src/app.tscn")
require("src/app.tscn", scene, ['res://src/presentation_runtime_current.gd'])

save_validator = read("src/content/save_validator.gd")
require("src/content/save_validator.gd", save_validator, [
    'HideawayStewardship = preload("res://src/game/hideaway_stewardship.gd")',
    'state.has("hideaway:stewardship")',
    'HideawayStewardship.validate_state',
    'HIDEAWAY_TRANSIENT_COUNTER_KEYS',
    'validate_hideaway_transient_counter',
])

campaign_path = ROOT / "campaigns/epochbound_demo/campaign.json"
campaign = json.loads(campaign_path.read_text(encoding="utf-8"))
if "maps/archive_hideaway.json" not in campaign.get("map_files", []):
    errors.append("reference campaign does not declare Archive Hideaway")

map_path = ROOT / "campaigns/epochbound_demo/maps/archive_hideaway.json"
if not map_path.is_file():
    errors.append("reference Archive Hideaway map is missing")
else:
    hideaway = json.loads(map_path.read_text(encoding="utf-8"))
    if hideaway.get("id") != "archive_hideaway":
        errors.append("Archive Hideaway map id drifted")
    eras = {entry.get("id") for entry in hideaway.get("eras", []) if isinstance(entry, dict)}
    if eras != {"verdant", "ashen"}:
        errors.append(f"Archive Hideaway must retain Verdant and Ashen identities, found {sorted(eras)}")
    facilities = {
        entry.get("facility_id")
        for entry in hideaway.get("interactions", [])
        if isinstance(entry, dict) and entry.get("kind") == "hideaway_facility"
    }
    expected = {"archive_hearth", "sheltered_coldframe", "salvage_workbench", "morrows_corner"}
    if facilities != expected:
        errors.append("Archive Hideaway map must expose all four stewardship facilities")
    if not any(entry.get("target_map") == "bellweather_crossing" for entry in hideaway.get("connections", []) if isinstance(entry, dict)):
        errors.append("Archive Hideaway must retain a Bellweather return route")

bellweather = json.loads((ROOT / "campaigns/epochbound_demo/maps/bellweather_crossing.json").read_text(encoding="utf-8"))
if not any(entry.get("target_map") == "archive_hideaway" for entry in bellweather.get("connections", []) if isinstance(entry, dict)):
    errors.append("Bellweather must retain the authored Hideaway route")
if not any(entry.get("id") == "from_hideaway" for entry in bellweather.get("entry_points", []) if isinstance(entry, dict)):
    errors.append("Bellweather must retain the Hideaway return spawn")

presentation = json.loads((ROOT / "campaigns/epochbound_demo/presentation/core.json").read_text(encoding="utf-8"))
presentation_ids = {entry.get("id") for entry in presentation.get("profiles", []) if isinstance(entry, dict)}
if not {"hideaway_verdant", "hideaway_ashen"}.issubset(presentation_ids):
    errors.append("Hideaway presentation profiles are incomplete")
if sum(1 for entry in presentation.get("bindings", []) if isinstance(entry, dict) and entry.get("map_id") == "archive_hideaway") != 2:
    errors.append("Hideaway presentation must bind both eras")

audio = json.loads((ROOT / "campaigns/epochbound_demo/audio/core.json").read_text(encoding="utf-8"))
audio_ids = {entry.get("id") for entry in audio.get("profiles", []) if isinstance(entry, dict)}
if not {"hideaway_verdant", "hideaway_ashen"}.issubset(audio_ids):
    errors.append("Hideaway audio profiles are incomplete")
if sum(1 for entry in audio.get("bindings", []) if isinstance(entry, dict) and entry.get("map_id") == "archive_hideaway") != 2:
    errors.append("Hideaway audio must bind both eras")

multiplayer = json.loads((ROOT / "campaigns/epochbound_demo/multiplayer/core.json").read_text(encoding="utf-8"))
area = next((entry for entry in multiplayer.get("areas", []) if isinstance(entry, dict) and entry.get("id") == "archive_hideaway_sanctuary"), None)
if not area or area.get("kind") != "sanctuary" or area.get("allow_invaders") is not False:
    errors.append("Archive Hideaway must remain an invasion-free sanctuary")

for path, tokens in {
    "tools/smoke_world_model.gd": ["four maps", "archive_hideaway"],
    "tools/smoke_presentation_runtime.gd": ["eight presentation profiles", "hideaway_verdant"],
    "tools/smoke_audio_mood_runtime.gd": ["nine audio profiles", "all eight map/era contexts"],
    "tools/smoke_multiplayer_runtime.gd": ["five authored online areas"],
    "tools/smoke_multiplayer_snapshot_transport.gd": ["archive_hideaway", "all eight reference map/era states"],
    "tools/smoke_hideaway_runtime.gd": ["Archive Hideaway runtime smoke passed", "Fractional Hideaway durable state", "Fractional Hideaway one-use counters", "remaining active-play requirement", "first safe-return memento", "unlock all six mementos without new saved flags", "qps-ploc", "archive_hideaway_sanctuary"],
    "tools/compile_hideaway_runtime_probe.gd": ["src/hideaway_runtime.gd", "smoke_hideaway_runtime.gd"],
    "scripts/validate.ps1": ["Compile Archive Hideaway live runtime bridge", "Smoke test playable Archive Hideaway refuge loop"],
}.items():
    require(path, read(path), tokens)

if errors:
    print("Epochbound Archive Hideaway runtime contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_hideaway_runtime_contract_passed")
print("- Archive Hideaway is an authored fourth map with Verdant and Ashen refuge identity")
print("- live travel owns active-play expedition start, truthful dual-cap rewards and visible short-return guidance")
print("- four facility interactions visibly evolve across level-specific stages and expose exact costs through existing controls")
print("- a non-consuming journey memento shelf reflects existing story combat companion and refuge milestones")
print("- one-use warmth repair recovery and Morrow focus preparations bridge into combat readiness")
print("- semantic Hideaway state is save-validated and remains host-authoritative online")
print("- audio presentation multiplayer and eight-state snapshot coverage include the refuge")
