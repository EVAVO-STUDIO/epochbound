#!/usr/bin/env python3
"""Fail closed when Epochbound's host-authoritative multiplayer contract drifts."""

from __future__ import annotations

import json
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


def forbid(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token in source:
            errors.append(f"{relative_path}: contains forbidden {token}")


def require_order(relative_path: str, source: str, tokens: list[str]) -> None:
    cursor = -1
    for token in tokens:
        position = source.find(token, cursor + 1)
        if position < 0:
            errors.append(f"{relative_path}: missing ordered token {token}")
            return
        cursor = position


catalog_path = "src/content/multiplayer_catalog.gd"
catalog = read(catalog_path)
require(
    catalog_path,
    catalog,
    [
        'TRANSPORT_ENET := "enet"',
        'PROGRESSION_HOST_ONLY := "host_only"',
        'REWARD_SESSION_ONLY := "session_only"',
        'AREA_SANCTUARY := "sanctuary"',
        'AREA_CO_OP := "co_op"',
        'AREA_PVP := "pvp"',
        "max_allies",
        "max_invaders",
        "snapshot_rate_hz",
        "input_rate_hz",
        "active_area",
        "priority > best_priority",
        "size < best_size",
        "invaders_allowed",
        "friendly_fire_allowed",
    ],
)

validator_path = "src/content/multiplayer_area_validator.gd"
validator = read(validator_path)
require(
    validator_path,
    validator,
    [
        "validate_multiplayer_only",
        "validate_profile_multiplayer",
        "default_port must be an integer",
        "max_allies",
        "max_invaders",
        "only PvP areas may allow invaders",
        "must remain inside map",
        "unknown era",
        "max_invaders is positive but no PvP area is authored",
        '"multiplayer_peers"',
        '"peer_roles"',
        '"invasion_state"',
    ],
)

model_path = "src/game/multiplayer_session_model.gd"
model = read(model_path)
require(
    model_path,
    model,
    [
        'MODE_OFFLINE := "offline"',
        'MODE_HOST := "host"',
        'MODE_CLIENT := "client"',
        'ROLE_HOST := "host"',
        'ROLE_ALLY := "ally"',
        'ROLE_INVADER := "invader"',
        "register_peer",
        "ally_capacity",
        "invader_capacity",
        "stale_sequence",
        "shared_pvp_area",
        "can_damage_actor",
        "can_damage_enemy",
        "ALLY_RESPAWN_SECONDS",
        "INVADER_BANISH_SECONDS",
        "PVP_GRACE_SECONDS",
        "snapshot_peer",
        "peer_from_snapshot",
    ],
)
forbid(
    model_path,
    model,
    [
        "Time.get_unix_time",
        "OS.get_unix_time",
        "randf(",
        "randi(",
        '"inventory"',
        '"quest_progress"',
        '"session_state"',
    ],
)

session_path = "src/multiplayer_session.gd"
session = read(session_path)
require(
    session_path,
    session,
    [
        "ENetMultiplayerPeer.new()",
        "create_server(resolved_port",
        "create_client(connect_address",
        "OfflineMultiplayerPeer.new()",
        '@rpc("any_peer", "call_remote", "reliable", 0)',
        '@rpc("any_peer", "call_remote", "unreliable_ordered", INPUT_CHANNEL)',
        '@rpc("authority", "call_remote", "unreliable_ordered", SNAPSHOT_CHANNEL)',
        "multiplayer.get_remote_sender_id()",
        "PROTOCOL VERSION MISMATCH",
        "CAMPAIGN VERSION MISMATCH",
        "HOST IS NOT IN A COMPATIBLE ONLINE AREA",
        "MultiplayerSessionModel.accept_input",
        "MultiplayerSessionModel.can_damage_actor",
        "damage_entity",
        "damage_actor",
        "build_world_snapshot",
        "apply_world_snapshot",
        "last_snapshot_sequence",
        "blocks_manual_save",
        "blocks_autosave",
        "shared_progression",
        "pvp_rewards",
        "multiplayer_runtime_contract_ok",
    ],
)
require_order(
    session_path,
    session,
    [
        "multiplayer.get_remote_sender_id()",
        "MultiplayerSessionModel.register_peer",
        "_join_accepted.rpc_id",
    ],
)
forbid(
    session_path,
    session,
    [
        "allow_object_decoding = true",
        "SaveProfileStore",
        "write_profile(",
        "read_profile(",
        'snapshot["inventory"]',
        'snapshot["session_state"]',
        'snapshot["quest_progress"]',
        "Time.get_unix_time",
        "OS.get_unix_time",
        "randf(",
        "randi(",
    ],
)

save_guard_path = "src/multiplayer_save_guard.gd"
save_guard = read(save_guard_path)
require(
    save_guard_path,
    save_guard,
    [
        "blocks_manual_save",
        "blocks_autosave",
        "save_operation_depth",
        "restore_after_runtime",
        "online session before opening a manual save profile",
    ],
)

post_path = "src/multiplayer_post_tick.gd"
post = read(post_path)
require(
    post_path,
    post,
    [
        "process_priority = 100",
        "post_runtime_process",
        "MultiplayerSaveGuard",
        "restore_after_runtime",
    ],
)

overlay_path = "src/multiplayer_overlay.gd"
overlay = read(overlay_path)
require(
    overlay_path,
    overlay,
    [
        "HOST-AUTHORITATIVE",
        "HOST CO-OP",
        "JOIN CO-OP",
        "INVADE",
        "PVP REWARDS SESSION-ONLY",
        "draw_area_boundary",
        "draw_remote_peers",
        "multiplayer_overlay_contract_ok",
    ],
)

scene_path = "src/app.tscn"
scene = read(scene_path)
require(
    scene_path,
    scene,
    [
        'res://src/multiplayer_session.gd',
        'res://src/multiplayer_save_guard.gd',
        'res://src/multiplayer_post_tick.gd',
        'res://src/multiplayer_overlay.gd',
        '[node name="MultiplayerSession" type="Node" parent="."]',
        '[node name="MultiplayerSaveGuard" type="Node" parent="."]',
        '[node name="MultiplayerPostTick" type="Node" parent="."]',
        '[node name="MultiplayerOverlay" type="Node2D" parent="PresentationLayer"]',
    ],
)

runtime_contract_path = "src/game/runtime_scene_contract.gd"
runtime_contract = read(runtime_contract_path)
require(
    runtime_contract_path,
    runtime_contract,
    [
        "CURRENT_MULTIPLAYER_SESSION_SCRIPT",
        "CURRENT_MULTIPLAYER_POST_SCRIPT",
        "CURRENT_MULTIPLAYER_SAVE_GUARD_SCRIPT",
        "CURRENT_MULTIPLAYER_OVERLAY_SCRIPT",
        "multiplayer_runtime_contract_ok",
        "multiplayer_post_tick_contract_ok",
        "multiplayer_save_guard_contract_ok",
        "multiplayer_overlay_contract_ok",
    ],
)

complete_validator_path = "src/content/complete_content_validator.gd"
complete_validator = read(complete_validator_path)
require(
    complete_validator_path,
    complete_validator,
    [
        'multiplayer_area_validator.gd',
        "validate_multiplayer_only",
        "validate_profile_multiplayer",
        'output["multiplayer_area_count"]',
        'output["pvp_area_count"]',
    ],
)

project_path = "project.godot"
project = read(project_path)
require(
    project_path,
    project,
    [
        "network_menu={",
        'physical_keycode":78',
        'button_index":5',
    ],
)

campaign_path = "campaigns/epochbound_demo/campaign.json"
campaign_source = read(campaign_path)
try:
    campaign = json.loads(campaign_source)
except json.JSONDecodeError as exc:
    campaign = {}
    errors.append(f"{campaign_path}: invalid JSON: {exc}")
if campaign:
    multiplayer = campaign.get("multiplayer", {})
    expected_policy = {
        "enabled": True,
        "transport": "enet",
        "default_port": 27491,
        "max_allies": 2,
        "max_invaders": 1,
        "shared_progression": "host_only",
        "pvp_rewards": "session_only",
        "friendly_fire": False,
    }
    for key, expected in expected_policy.items():
        if multiplayer.get(key) != expected:
            errors.append(f"{campaign_path}: multiplayer/{key} expected {expected!r}, found {multiplayer.get(key)!r}")
    if campaign.get("multiplayer_files") != ["multiplayer/core.json"]:
        errors.append(f"{campaign_path}: multiplayer_files must point to multiplayer/core.json")

area_path = "campaigns/epochbound_demo/multiplayer/core.json"
area_source = read(area_path)
try:
    area_catalog = json.loads(area_source)
except json.JSONDecodeError as exc:
    area_catalog = {}
    errors.append(f"{area_path}: invalid JSON: {exc}")
if area_catalog:
    areas = area_catalog.get("areas", [])
    if len(areas) != 4:
        errors.append(f"{area_path}: expected 4 authored areas, found {len(areas)}")
    pvp = [area for area in areas if area.get("kind") == "pvp"]
    if len(pvp) != 1 or pvp[0].get("id") != "clockwood_ashen_hunt":
        errors.append(f"{area_path}: expected one clockwood_ashen_hunt PvP area")
    if not any(area.get("kind") == "sanctuary" for area in areas):
        errors.append(f"{area_path}: expected at least one sanctuary")
    if any(area.get("kind") != "pvp" and area.get("allow_invaders") for area in areas):
        errors.append(f"{area_path}: non-PvP area allows invaders")

compile_path = "tools/compile_multiplayer_probe.gd"
compile_probe = read(compile_path)
require(
    compile_path,
    compile_probe,
    [
        "multiplayer_catalog.gd",
        "multiplayer_area_validator.gd",
        "multiplayer_session_model.gd",
        "multiplayer_session.gd",
        "multiplayer_save_guard.gd",
        "multiplayer_post_tick.gd",
        "multiplayer_overlay.gd",
        "smoke_multiplayer_session_model.gd",
        "smoke_multiplayer_runtime.gd",
        "smoke_multiplayer_validation_edges.gd",
        "app.tscn",
    ],
)

for smoke_path, tokens in {
    "tools/smoke_multiplayer_session_model.gd": [
        "party cap",
        "stale_sequence",
        "Sanctuary areas must suppress invasion damage",
        "temporary downed state",
        "temporary banished state",
    ],
    "tools/smoke_multiplayer_runtime.gd": [
        "configure_test_host_session",
        "Co-op ally attacks must damage host-owned enemies exactly once",
        "Invader attacks inside the authored PvP area",
        "Durable profiles must exclude online peer and invasion state",
        "Client must apply a fresh authoritative world snapshot",
    ],
    "tools/smoke_multiplayer_validation_edges.gd": [
        "numeric-string coercion",
        "host_only",
        "only PvP areas may allow invaders",
        "must remain inside map",
        "injected ephemeral multiplayer field",
    ],
}.items():
    smoke = read(smoke_path)
    require(smoke_path, smoke, tokens)

local_gate_path = "scripts/validate.ps1"
local_gate = read(local_gate_path)
require(
    local_gate_path,
    local_gate,
    [
        "compile_multiplayer_probe.gd",
        "smoke_multiplayer_session_model.gd",
        "smoke_multiplayer_runtime.gd",
        "smoke_multiplayer_validation_edges.gd",
        "host-authoritative co-op",
        "authored PvP invasions",
    ],
)

docs_path = "docs/MULTIPLAYER_COOP_PVP.md"
docs = read(docs_path)
require(
    docs_path,
    docs,
    [
        "direct-IP ENet sessions over UDP",
        "host-authoritative",
        "Host saves only",
        "session-only PvP scores",
        "sanctuary",
        "co_op",
        "pvp",
        "--invade",
        "There is no central matchmaking",
        "Remaining production boundaries",
    ],
)

workflow_path = ".github/workflows/validate.yml"
workflow = read(workflow_path)
require(
    workflow_path,
    workflow,
    [
        "python3 tools/check_multiplayer_contract.py",
        '"multiplayerValidation": "passed"',
        "scripts/validate.ps1",
    ],
)

release_policy_path = "tools/check_release_workflow_policy.py"
release_policy = read(release_policy_path)
require(
    release_policy_path,
    release_policy,
    [
        "python3 tools/check_multiplayer_contract.py",
        '"multiplayerValidation": "passed"',
        "compile_multiplayer_probe.gd",
        "smoke_multiplayer_session_model.gd",
        "smoke_multiplayer_runtime.gd",
        "smoke_multiplayer_validation_edges.gd",
    ],
)

if errors:
    print("Epochbound multiplayer contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_multiplayer_contract_passed")
print("- direct ENet sessions remain protocol and campaign-version matched")
print("- the host owns world simulation, enemy damage, PvP damage, progression and saves")
print("- allies are temporary co-op actors and invaders are hostile only in authored PvP areas")
print("- sanctuary safety, party caps, fresh input, bounded snapshots and save isolation are guarded")
print("- matchmaking, relay, identity and anti-cheat remain explicit future production boundaries")
