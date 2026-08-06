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
        'host_has_reconnect_exchange',
        'graceful_leave_request_count',
        'last_graceful_leave_peer_id',
        'initial_ally_peer_id',
        'reconnected_ally_peer_id',
        'persistent_invader_peer_id',
        'same_process_reconnect_proved',
        'last_snapshot_sequence',
        'build_world_snapshot',
        'encode_world_snapshot',
        'snapshot_wire_bytes',
        'snapshot_uncompressed_bytes',
        'write_json(receipt_path, receipt)',
        'hold_after_receipt',
        'LOOPBACK INITIAL EXCHANGE',
        'LOOPBACK RECONNECT EXCHANGE',
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
        'INITIAL_EXCHANGE_HOLD_MSEC := 650',
        'RECONNECT_EXCHANGE_HOLD_MSEC := 450',
        'RECONNECT_SETTLE_MSEC := 250',
        'session.call("join_session", HOST_ADDRESS, peer_role, port)',
        'session.call(\n\t\t\t\t\t\t\t"request_graceful_leave"',
        'last_graceful_leave_ack_sequence',
        'same_process_reconnect',
        'first_peer_id',
        'first_snapshot_sequence',
        'first_input_sequence_sent',
        'reconnect_generation',
        'session.rpc_id(',
        '"_submit_input"',
        'explicit_input_sequence += 1',
        'input_sequence_sent',
        'LOOPBACK JOIN ACCEPTED',
        'LOOPBACK GRACEFUL LEAVE REQUESTED',
        'LOOPBACK GRACEFUL LEAVE ACKNOWLEDGED',
        'LOOPBACK RECONNECT STARTED',
        'LOOPBACK REJOIN ACCEPTED',
        'LOOPBACK RECONNECT INPUT SENT',
        'LOOPBACK RECONNECT SNAPSHOT RECEIVED',
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
        'SNAPSHOT_WIRE_MAGIC_TEXT := "EPB1"',
        'SNAPSHOT_WIRE_MAGIC_BYTES := 4',
        'SNAPSHOT_WIRE_DIGEST_BYTES := 32',
        'SNAPSHOT_WIRE_HEADER_BYTES := SNAPSHOT_WIRE_MAGIC_BYTES + SNAPSHOT_WIRE_DIGEST_BYTES',
        'MAX_NETWORK_SNAPSHOT_BYTES := 1200',
        'MAX_DECOMPRESSED_SNAPSHOT_BYTES := 65536',
        'GRACEFUL_LEAVE_TIMEOUT_SECONDS := 3.0',
        'MAX_GRACEFUL_LEAVE_REASON_CHARS := 80',
        'MAX_GRACEFUL_LEAVE_HISTORY := 8',
        'broadcast_world_snapshot_wire',
        'multiplayer.get_peers()',
        '_receive_snapshot_wire.rpc_id',
        'var_to_bytes(snapshot)',
        'bytes_to_var(serialized)',
        'snapshot_wire_digest',
        'HashingContext.HASH_SHA256',
        'actual_digest != expected_digest',
        'decompress_dynamic(',
        '@rpc("authority", "call_remote", "unreliable_ordered", SNAPSHOT_CHANNEL)',
        'snapshot_facing_name',
        'entity["facing"] = snapshot_facing_name',
        'func request_graceful_leave',
        '@rpc("any_peer", "call_remote", "reliable", 0)\nfunc _request_graceful_leave',
        '@rpc("authority", "call_remote", "reliable", 0)\nfunc _graceful_leave_accepted',
        'graceful_leave_timeout_remaining',
        'last_graceful_leave_ack_sequence',
        'graceful_leave_request_count',
        'graceful_leave_peer_history',
        'MultiplayerSessionModel.remove_peer(peers, sender_id)',
        '_graceful_leave_accepted.rpc_id',
        'close_session_immediately',
        'multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()',
        'closing_peer.close()',
        'MAX_NETWORK_SNAPSHOT_BYTES < 1392',
    ],
)
require_order(
    transport_path,
    transport,
    [
        'if magic != snapshot_wire_magic():',
        'if (\n\t\tactual_digest.size() != SNAPSHOT_WIRE_DIGEST_BYTES',
        'var serialized: PackedByteArray = compressed.decompress_dynamic(',
    ],
)
require_order(
    transport_path,
    transport,
    [
        'MultiplayerSessionModel.remove_peer(peers, sender_id)',
        '_graceful_leave_accepted.rpc_id',
    ],
)
require_order(
    transport_path,
    transport,
    [
        'last_graceful_leave_ack_sequence = sequence',
        'close_session_immediately(graceful_leave_reason(reason))',
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
        'Time.get_unix_time',
        'OS.get_unix_time',
    ],
)

matrix_path = "tools/smoke_multiplayer_snapshot_transport.gd"
matrix = read(matrix_path)
require(
    matrix_path,
    matrix,
    [
        'MAX_WIRE_BYTES := 1200',
        '"bellweather_crossing"',
        '"clockwood_edge"',
        '"museum_underworks"',
        '"verdant"',
        '"ashen"',
        'register the second ally',
        'register the invader',
        'expected_peer_count := 4',
        'Snapshot transport must reject payloads above 1,200 bytes before decompression',
        'Snapshot transport must reject malformed wire headers before decompression',
        'Snapshot transport must reject checksum mismatches before decompression',
        'deterministic_noise(8192)',
        'fail closed when compressed state exceeds its wire budget',
        'all six reference map/era states',
    ],
)
forbid(
    matrix_path,
    matrix,
    [
        'randf(',
        'randi(',
        'allow_object_decoding = true',
        'bytes_to_var_with_objects',
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
        'graceful_leave_request_count -lt 1',
        'last_graceful_leave_peer_id -ne',
        'same_process_reconnect_proved',
        'same_process_reconnect',
        'graceful_leave_ack_sequence -le 0',
        'reconnect_generation -ne 1',
        'persistent_invader_peer_id',
        'input_sequence_sent -le 10000',
        'protocol_version -ne 1',
        'snapshot_wire_bytes -gt 1200',
        'snapshot_uncompressed_bytes -le',
        'clockwood_ashen_hunt',
        'exited before harness-owned cleanup',
        'parent harness deliberately owns only final process-tree termination',
        'host shutdown and independent headless process exit',
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
        'smoke_multiplayer_snapshot_transport.gd',
        'bounded ENet transport',
        'deterministic real loopback peers',
        'all-map snapshot matrix',
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
        'Run all-map snapshot transport matrix',
        'smoke_multiplayer_snapshot_transport.gd',
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
        'bounded input retries',
        'SHA-256 wire envelope',
        'six reference map/era states',
        'remote input reaches host authority',
        'authoritative snapshots reach both clients',
        'host-acknowledged graceful leave',
        'same Godot process reconnects',
        'original invader remains connected',
        '1,200-byte',
        'parent harness owns final process termination',
        'does not prove graceful host shutdown',
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
print("- bounded repeated input RPCs make host-authority evidence deterministic")
print("- SHA-256 envelopes reject malformed packets before object-free Deflate decompression")
print("- all six reference map and era states fit the 1,200-byte wire budget at maximum authored party size")
print("- the ally completes a host-acknowledged leave and same-process reconnect while the invader remains online")
print("- authoritative snapshots reach both clients and restore the ally after reconnect")
print("- the parent harness validates atomic live receipts and owns bounded final process cleanup")
print("- graceful host shutdown, public Internet reachability, relay, NAT traversal and platform invitations remain separate boundaries")