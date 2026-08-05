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
        'last_sequence',
        'build_world_snapshot',
        'write_json(receipt_path, receipt)',
        'protocol_version',
        'peer_count',
        'input_peer_count',
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

harness_path = "scripts/validate_multiplayer_loopback.ps1"
harness = read(harness_path)
require(
    harness_path,
    harness,
    [
        'Start-Process',
        'multiplayer_loopback_peer.gd',
        '-Role "host"',
        '-Role "ally"',
        '-Role "invader"',
        'host-ready.json',
        'Read-Receipt',
        'Assert-PeerLogClean',
        'ConvertFrom-Json',
        'input_peer_count -ne 2',
        'protocol_version -ne 1',
        'clockwood_ashen_hunt',
        'Kill($true)',
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

compile_path = "tools/compile_multiplayer_probe.gd"
compile_probe = read(compile_path)
require(
    compile_path,
    compile_probe,
    [
        'multiplayer_loopback_peer.gd',
        'real loopback peer',
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
print("- remote client input reaches host authority and authoritative snapshots return")
print("- the harness is bounded, cleans every child process and leaves tracked source unchanged")
print("- public Internet reachability, relay, NAT traversal and platform invitations remain separate boundaries")
