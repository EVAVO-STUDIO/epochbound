#!/usr/bin/env python3
"""Fail closed when Epochbound's player-local multiplayer connection setup drifts."""

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


profile_path = "src/game/multiplayer_connection_profile.gd"
profile = read(profile_path)
require(
    profile_path,
    profile,
    [
        'CURRENT_SCHEMA := 1',
        'DEFAULT_ADDRESS := "127.0.0.1"',
        'DEFAULT_PORT := 27491',
        'MIN_PORT := 1024',
        'MAX_PORT := 65535',
        'MAX_ADDRESS_LENGTH := 253',
        'sanitize_address',
        'address_is_valid',
        'candidate.contains("://")',
        'candidate.contains("/")',
        'candidate.count(":") < 2',
        'port_is_valid',
        'player_name_is_valid',
        'MultiplayerSessionModel.sanitize_name',
        'migrate',
        'summary',
    ],
)
forbid(
    profile_path,
    profile,
    [
        "Time.get_unix_time",
        "OS.get_unix_time",
        "randf(",
        "randi(",
        "SaveProfileStore",
        "CampaignPackage",
    ],
)

store_path = "src/game/multiplayer_connection_profile_store.gd"
store = read(store_path)
require(
    store_path,
    store,
    [
        'ROOT := "user://settings"',
        'PROFILE_FILENAME := "multiplayer_connection.json"',
        'TEMP_SUFFIX := ".tmp"',
        'BACKUP_SUFFIX := ".bak"',
        'load_profile',
        'read_profile_path',
        'write_profile',
        'MultiplayerConnectionProfile.validate(profile)',
        'MultiplayerConnectionProfile.sanitize(',
        'FileAccess.open(temporary_path, FileAccess.WRITE)',
        'rotated_valid_existing',
        'recovered_from_backup',
        'used_defaults',
        'delete_profile',
    ],
)
require_order(
    store_path,
    store,
    [
        'var validation := MultiplayerConnectionProfile.validate(profile)',
        'var sanitized := MultiplayerConnectionProfile.sanitize(',
        'var file := FileAccess.open(temporary_path, FileAccess.WRITE)',
    ],
)
forbid(
    store_path,
    store,
    [
        "SaveProfileStore",
        "CampaignPackage",
        "multiplayer.multiplayer_peer",
        "rpc(",
        "Time.get_unix_time",
        "OS.get_unix_time",
    ],
)

panel_path = "src/multiplayer_connection_panel.gd"
panel = read(panel_path)
require(
    panel_path,
    panel,
    [
        'extends Control',
        'PANEL_RECT := Rect2(94, 38, 452, 284)',
        'LOBBY_HINT_RECT := Rect2(332, 310, 198, 22)',
        'process_priority = -200',
        'load_saved_profile',
        'has_connection_command_line_override',
        'argument == "--host"',
        'argument == "--invade"',
        'argument.begins_with("--join=")',
        'argument.begins_with("--port=")',
        'argument.begins_with("--name=")',
        'RECOVERED SAVED CONNECTION',
        'UPDATED SAVED CONNECTION',
        'INVALID SAVED CONNECTION — LOCALHOST',
        'connection_setup_can_open',
        'open_editor',
        'session.set_process(false)',
        'call_deferred("restore_session_polling")',
        'save_current_profile',
        'MultiplayerConnectionProfileStore.write_profile',
        'mouse_filter = Control.MOUSE_FILTER_STOP',
        'LineEdit.KEYBOARD_TYPE_URL',
        'configure_focus_navigation',
        'multiplayer_connection_panel_contract_ok',
    ],
)
require_order(
    panel_path,
    panel,
    [
        'var validation := MultiplayerConnectionProfile.validate(raw_profile)',
        'var result := MultiplayerConnectionProfileStore.write_profile(',
        'apply_profile_to_session(result.get("profile", raw_profile))',
        'close_editor(true)',
    ],
)
forbid(
    panel_path,
    panel,
    [
        "SaveProfileStore",
        "CampaignPackage",
        "@rpc",
        "multiplayer.multiplayer_peer",
        "snapshot_sequence",
    ],
)

scene_path = "src/app.tscn"
scene = read(scene_path)
require(
    scene_path,
    scene,
    [
        'res://src/multiplayer_connection_panel.gd',
        '[node name="MultiplayerConnectionPanel" type="Control" parent="PresentationLayer"]',
    ],
)

runtime_contract_path = "src/game/runtime_scene_contract.gd"
runtime_contract = read(runtime_contract_path)
require(
    runtime_contract_path,
    runtime_contract,
    [
        'CURRENT_MULTIPLAYER_CONNECTION_PANEL_SCRIPT := "res://src/multiplayer_connection_panel.gd"',
        'PresentationLayer/MultiplayerConnectionPanel',
        'multiplayer_connection_panel_contract_ok',
        'player-local connection setup contract',
    ],
)

compile_path = "tools/compile_multiplayer_probe.gd"
compile_probe = read(compile_path)
require(
    compile_path,
    compile_probe,
    [
        'multiplayer_connection_profile.gd',
        'multiplayer_connection_profile_store.gd',
        'multiplayer_connection_panel.gd',
        'smoke_multiplayer_connection_profile.gd',
        'app.tscn',
    ],
)

smoke_path = "tools/smoke_multiplayer_connection_profile.gd"
smoke = read(smoke_path)
require(
    smoke_path,
    smoke,
    [
        'TEST_ROOT := "user://tests/multiplayer_connection_profile_smoke"',
        'An invalid primary without a backup must fall back visibly to safe defaults',
        'Connection profiles must accept fully qualified hostnames',
        'Connection profiles must accept IPv4 addresses',
        'Connection profiles must normalize bracketed IPv6 addresses for ENet',
        'Connection profiles must reject URL schemes and paths',
        'Connection profiles must keep the UDP port in its separately bounded field',
        'Invalid raw connection data must fail before rotating the current profile',
        'Malformed primary connection data must recover from the last valid backup',
        'Backup recovery must remain visible until the online lobby is opened',
        'Connection setup must suspend lobby polling while text controls own input',
        'Address entry must request an address-appropriate virtual keyboard',
        'Keyboard and controller focus navigation must remain explicitly wired',
        'A rejected form must retain text ownership and suspended lobby polling',
        'Returning to the lobby must restore session polling',
        'Campaign saves must exclude player-local connection field',
        'Connection-profile smoke data must clean up without touching campaign source',
    ],
)

local_gate_path = "scripts/validate.ps1"
local_gate = read(local_gate_path)
require(
    local_gate_path,
    local_gate,
    [
        'compile_multiplayer_probe.gd',
        'Smoke test player-local multiplayer connection setup and recovery',
        'smoke_multiplayer_connection_profile.gd',
        'host-authoritative co-op',
        'authored PvP invasions',
    ],
)

session_path = "src/multiplayer_session.gd"
session = read(session_path)
forbid(
    session_path,
    session,
    [
        'snapshot["connect_address"]',
        'snapshot["connect_port"]',
        'snapshot["local_name"]',
        'snapshot["multiplayer_connection_profile"]',
    ],
)

save_profile_path = "src/content/save_profile.gd"
save_profile = read(save_profile_path)
forbid(
    save_profile_path,
    save_profile,
    [
        '"multiplayer_connection_profile"',
        '"connect_address"',
        '"connect_port"',
    ],
)

package_path = "src/content/campaign_package.gd"
package = read(package_path)
forbid(
    package_path,
    package,
    [
        'multiplayer_connection.json',
        'multiplayer_connection_profile',
    ],
)

docs_path = "docs/MULTIPLAYER_COOP_PVP.md"
docs = read(docs_path)
require(
    docs_path,
    docs,
    [
        'in-game hostname, IPv4, IPv6, UDP-port and display-name setup',
        'user://settings/multiplayer_connection.json',
        'Command-line networking arguments remain available',
        'Connection details are player-local',
        'smoke_multiplayer_connection_profile.gd',
        'platform invitations, friend discovery or join codes',
    ],
)

workflow_path = ".github/workflows/validate.yml"
workflow = read(workflow_path)
require(
    workflow_path,
    workflow,
    [
        'Validate multiplayer connection setup contract',
        'python3 tools/check_multiplayer_connection_contract.py',
        '"multiplayerConnectionValidation": "passed"',
        '"schemaVersion": "2.2"',
    ],
)

release_policy_path = "tools/check_release_workflow_policy.py"
release_policy = read(release_policy_path)
require(
    release_policy_path,
    release_policy,
    [
        'python3 tools/check_multiplayer_connection_contract.py',
        '"multiplayerConnectionValidation": "passed"',
        'multiplayer_connection_profile.gd',
        'multiplayer_connection_profile_store.gd',
        'multiplayer_connection_panel.gd',
        'smoke_multiplayer_connection_profile.gd',
    ],
)

if errors:
    print("Epochbound multiplayer connection contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_multiplayer_connection_contract_passed")
print("- hostname and direct IP setup remains bounded and player-local")
print("- raw connection data fails before temporary writes or backup rotation")
print("- one known-good backup and visible localhost fallback remain available")
print("- command-line networking arguments retain explicit precedence")
print("- campaign saves packages and snapshots remain free of connection details")
print("- the canonical scene compile probe regression gate documentation and receipt are pinned")
