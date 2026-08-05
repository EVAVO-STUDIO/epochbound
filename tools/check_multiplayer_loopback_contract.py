#!/usr/bin/env python3
"""Fail closed when Epochbound's real ENet loopback validation drifts."""

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


peer_path = "tools/multiplayer_loopback_peer.gd"
peer = read(peer_path)
require(
    peer_path,
    peer,
    [
        'RUNTIME_SCENE := "res://src/app.tscn"',
        'HOST_ADDRESS := "127.0.0.1"',
        'HOST_MAP := "clockwood_edge"',
        'HOST_ERA := "ashen"',
        'EXPECTED_AREA := "clockwood_ashen_hunt"',
        'session.call("host_session", port)',
        'session.call("join_session", HOST_ADDRESS, peer_role, port)',
        'MultiplayerSessionModel.ROLE_ALLY',
        'MultiplayerSessionModel.ROLE_INVADER',
        'remote_input_peer_count(peers) == 2',
        'last_snapshot_sequence',
        'build_world_snapshot',
        'encode_world_snapshot',
        'snapshot_wire_bytes',
        'snapshot_uncompressed_bytes',
        'write_json(receipt_path, receipt)',
        'hold_after_receipt',
        'LOOPBACK RECEIPT READY',
    ],
)
forbid(
    peer_path,
    peer,
    [
        'configure_test_host_session',
        'register_test_peer',
        'test_mode = true',
        'allow_object_decoding = true',
        'SaveProfileStore',
        'write_profile(',
        'read_profile(',
        'randf(',
        'randi(',
    ],
)

driver_path = "tools/multiplayer_loopback_peer_driver.gd"
driver = read(driver_path)
require(
    driver_path,
    driver,
    [
        'extends "res://tools/multiplayer_loopback_peer.gd"',
        'LOOPBACK_INPUT_RETRY_MSEC := 200',
        'LOOPBACK_INPUT_SEQUENCE_START := 10000',
        'session.call("join_session", HOST_ADDRESS, peer_role, port)',
        'session.rpc_id(',
        '"_submit_input"',
        'explicit_input_sequence += 1',
        'input_sequence_sent',
        'LOOPBACK JOIN ACCEPTED',
        'LOOPBACK INPUT SENT',
        'LOOPBACK SNAPSHOT RECEIVED',
        'temporary_path := path + ".tmp"',
        'DirAccess.rename_absolute(temporary_path, path)',
    ],
)
forbid(
    driver_path,
    driver,
    [
        'configure_test_host_session',
        'register_test_peer',
        'test_mode = true',
        'allow_object_decoding = true',
        'SaveProfileStore',
        'write_profile(',
        'read_profile(',
        'randf(',
        'randi(',
    ],
)

transport_path = "src/multiplayer_transport_session.gd"
transport = read(transport_path)
require(
    transport_path,
    transport,
    [
        'extends "res://src/multiplayer_session.gd"',
        'NETWORK_SNAPSHOT_COMPRESSION_MODE := FileAccess.COMPRESSION_DEFLATE',
        'MAX_NETWORK_SNAPSHOT_BYTES := 1200',
        'MAX_DECOMPRESSED_SNAPSHOT_BYTES := 65536',
        'broadcast_world_snapshot_wire',
        'multiplayer.get_peers()',
        '_receive_snapshot_wire.rpc_id',
        'var_to_bytes(snapshot)',
        'bytes_to_var(serialized)',
        'decompress_dynamic(',
        '@rpc("authority", "call_remote", "unreliable_ordered", SNAPSHOT_CHANNEL)',
        'snapshot_facing_name',
        'entity["facing"] = snapshot_facing_name',
        'multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()',
        'closing_peer.close()',
        'MAX_NETWORK_SNAPSHOT_BYTES < 1392',
    ],
)
require_order(
    transport_path,
    transport,
    [
        'network_peer = null',
        'multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()',
        'closing_peer.close()',
    ],
)
forbid(
    transport_path,
    transport,
    [
        'allow_object_decoding = true',
        'bytes_to_var_with_objects',
        'str_to_var',
        'SaveProfileStore',
    ],
)

harness_path = "scripts/validate_multiplayer_loopback.ps1"
harness = read(harness_path)
require(
    harness_path,
    harness,
    [
        '[int]$TimeoutSeconds = 60',
        'Start-Process',
        'multiplayer_loopback_peer_driver.gd',
        '"--timeout=45"',
        '-Role "host"',
        '-Role "ally"',
        '-Role "invader"',
        'Start-Sleep -Milliseconds 800',
        'host-ready.json',
        'Read-Receipt',
        'Assert-PeerLogClean',
        'Test-AllReceiptsPresent',
        'Write-AllPeerLogs',
        'ConvertFrom-Json',
        'input_peer_count -ne 2',
        'input_sequence_sent -le 10000',
        'protocol_version -ne 1',
        'snapshot_wire_bytes -gt 1200',
        'snapshot_uncompressed_bytes -le',
        'clockwood_ashen_hunt',
        'exited before harness-owned cleanup',
        'parent harness deliberately owns termination',
        'Remove-Item -Recurse -Force',
        'Real ENet loopback passed',
    ],
)
forbid(
    harness_path,
    harness,
    [
        'configure_test_host_session',
        'register_test_peer',
        '--test-mode',
        'localhost mock',
        'IgnoreExitCode',
    ],
)

scene_path = "src/app.tscn"
scene = read(scene_path)
require(
    scene_path,
    scene,
    [
        'res://src/multiplayer_transport_session.gd',
        '[node name="MultiplayerSession" type="Node" parent="."]',
        'script = ExtResource("6_multiplayer")',
    ],
)

runtime_contract_path = "src/game/runtime_scene_contract.gd"
runtime_contract = read(runtime_contract_path)
require(
    runtime_contract_path,
    runtime_contract,
    [
        'CURRENT_MULTIPLAYER_SESSION_SCRIPT := "res://src/multiplayer_transport_session.gd"',
        '"encode_world_snapshot"',
        '"decode_world_snapshot"',
        '"broadcast_world_snapshot_wire"',
        'host-authoritative bounded online policy',
    ],
)

compile_path = "tools/compile_multiplayer_probe.gd"
compile_probe = read(compile_path)
require(
    compile_path,
    compile_probe,
    [
        'multiplayer_session.gd',
        'multiplayer_transport_session.gd',
        'multiplayer_loopback_peer.gd',
        'multiplayer_loopback_peer_driver.gd',
        'bounded ENet transport',
        'deterministic real loopback peers',
    ],
)

workflow_path = ".github/workflows/validate.yml"
workflow = read(workflow_path)
require(
    workflow_path,
    workflow,
    [
        'Validate real ENet loopback integration contract',
        'python3 tools/check_multiplayer_loopback_contract.py',
        'Run real ENet host ally and invader loopback',
        'scripts/validate_multiplayer_loopback.ps1',
        '"schemaVersion": "1.9"',
        '"multiplayerLoopbackValidation": "passed"',
    ],
)

docs_path = "docs/MULTIPLAYER_LOOPBACK_GATE.md"
docs = read(docs_path)
require(
    docs_path,
    docs,
    [
        'three independent Godot processes',
        'real ENet UDP sockets',
        'remote input reaches host authority',
        'authoritative snapshots reach both clients',
        '1,200-byte',
        'bounded input retries',
        'parent harness owns process termination',
        'does not validate graceful disconnect',
        'does not prove public Internet reachability',
        'validate_multiplayer_loopback.ps1',
        'multiplayerLoopbackValidation',
    ],
)

if errors:
    print("Epochbound multiplayer loopback contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_multiplayer_loopback_contract_passed")
print("- three independent Godot processes use real ENet UDP sockets")
print("- an ally and invader negotiate through the production join RPC surface")
print("- bounded repeated input RPCs make host-authority evidence deterministic")
print("- authoritative snapshots return through an object-free 1,200-byte Deflate wire budget")
print("- the parent harness validates atomic live receipts and owns bounded process cleanup")
print("- graceful disconnect, public Internet reachability, relay, NAT traversal and platform invitations remain separate boundaries")
