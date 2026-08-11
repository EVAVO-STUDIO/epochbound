#!/usr/bin/env python3
"""Fail closed when Epochbound's unexpected-host restart recovery drifts."""

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


def require_count(relative_path: str, source: str, token: str, count: int) -> None:
    actual = source.count(token)
    if actual != count:
        errors.append(
            f"{relative_path}: expected {count} occurrence(s) of {token}, found {actual}"
        )


def require_order(relative_path: str, source: str, tokens: list[str]) -> None:
    cursor = -1
    for token in tokens:
        position = source.find(token, cursor + 1)
        if position < 0:
            errors.append(f"{relative_path}: missing ordered token {token}")
            return
        cursor = position


transport_path = "src/multiplayer_transport_session.gd"
transport = read(transport_path)
require(
    transport_path,
    transport,
    [
        "HOST_RESTART_RECOVERY_MAX_ATTEMPTS := 6",
        "HOST_RESTART_RECOVERY_INITIAL_DELAY_SECONDS := 0.35",
        "HOST_RESTART_RECOVERY_MAX_DELAY_SECONDS := 2.0",
        "HOST_RESTART_RECOVERY_BACKOFF_MULTIPLIER := 2.0",
        'HOST_RESTART_TRANSITION_NONE := ""',
        'HOST_RESTART_TRANSITION_BEGIN := "begin"',
        'HOST_RESTART_TRANSITION_FAIL := "fail"',
        "host_restart_recovery_armed",
        "host_restart_recovery_pending",
        "host_restart_retry_initiated",
        "host_restart_attempt_count",
        "host_restart_transition_deferred",
        "host_restart_transition_kind",
        "host_restart_transition_reason",
        "last_host_restart_generation",
        "last_host_restart_attempt_count",
        "last_host_restart_recovered",
        "last_host_restart_exhausted",
        "last_host_restart_address",
        "last_host_restart_port",
        "last_host_restart_role",
        "func host_restart_address_is_direct",
        "candidate.is_valid_ip_address()",
        "func arm_host_restart_recovery",
        "func queue_host_restart_transition",
        "func apply_host_restart_transition",
        "func clear_host_restart_transition",
        "func begin_host_restart_recovery",
        "func detach_transport_for_host_restart",
        "func host_restart_retry_delay_after_attempt",
        "func update_host_restart_recovery",
        "func start_host_restart_attempt",
        "func fail_host_restart_attempt",
        "func complete_host_restart_recovery",
        "func exhaust_host_restart_recovery",
        "func cancel_host_restart_recovery",
        "func reset_host_restart_recovery",
        'join_session(\n\t\thost_restart_address,',
        '"HOST LOST — RECOVERY 0/%d"',
        '"HOST RECOVERED AFTER %d ATTEMPT%s"',
        'set_notice("HOST RECOVERY EXHAUSTED — OPEN ONLINE PLAY TO RETRY")',
        'call_deferred("apply_host_restart_transition")',
        "if host_restart_transition_deferred:\n\t\treturn",
        "MultiplayerAPI emits disconnect signals while it is still iterating",
        '"HOST RESTART ATTEMPT DISCONNECTED"',
        '"HOST RESTART CONNECTION FAILED"',
        "host_restart_recovery_pending or super.blocks_manual_save()",
        "host_restart_recovery_pending or super.blocks_autosave()",
        "reset_host_restart_recovery(true)",
        "reset_host_restart_recovery(false)",
        "not last_host_shutdown_commit_received",
        "not graceful_leave_pending",
        "not remote_host_shutdown_pending",
        "HOST_RESTART_RECOVERY_MAX_ATTEMPTS == 6",
        "HOST RECOVERY RETRY %d/%d IN %.2fS",
        "if connection_pending:\n\t\t\treturn",
        "or network_peer != null",
    ],
)
if "HOST RECOVERY RETRY %d/%d IN %.2FS" in transport:
    errors.append(
        f"{transport_path}: contains unsupported uppercase float format token"
    )

forbid(
    transport_path,
    transport,
    [
        "Time.get_ticks",
        "Time.get_unix",
        "OS.delay",
        "randf(",
        "randi(",
        "SaveProfileStore",
        "write_profile(",
        "read_profile(",
        "host migration",
    ],
)

for callback_name in [
    "_on_server_disconnected",
    "_on_peer_disconnected",
    "_on_connection_failed",
]:
    callback_start = transport.find(f"func {callback_name}")
    if callback_start < 0:
        continue
    callback_end = transport.find("\nfunc ", callback_start + 1)
    callback_source = transport[
        callback_start : callback_end if callback_end >= 0 else len(transport)
    ]
    if "queue_host_restart_transition" not in callback_source:
        errors.append(
            f"{transport_path}: {callback_name} must defer host-restart transport mutation"
        )
    for forbidden_call in [
        "begin_host_restart_recovery(",
        "fail_host_restart_attempt(",
        "detach_transport_for_host_restart(",
        "close_session_immediately(",
    ]:
        if forbidden_call in callback_source:
            errors.append(
                f"{transport_path}: {callback_name} contains unsafe direct {forbidden_call}"
            )

smoke_path = "tools/smoke_multiplayer_host_restart_recovery.gd"
smoke = read(smoke_path)
require(
    smoke_path,
    smoke,
    [
        'RUNTIME_SCENE := "res://src/app.tscn"',
        'host_restart_address_is_direct", "127.0.0.1"',
        'host_restart_address_is_direct", "[::1]"',
        'host_restart_address_is_direct", "example.invalid"',
        "expected_delays := [0.35, 0.7, 1.4, 2.0, 2.0, 2.0]",
        '"configure_test_host_restart_client"',
        '"_on_server_disconnected"',
        '"_on_peer_disconnected", 1',
        '"_on_connection_failed"',
        '"host_restart_transition_deferred"',
        '"host_restart_transition_kind"',
        '"apply_host_restart_transition"',
        "Disconnect signal dispatch must not detach ENet synchronously",
        "Duplicate disconnect callbacks must collapse into the same deferred transition",
        "Duplicate stale-peer disconnect signals",
        "Pending retry must ignore stale server and peer disconnect callbacks",
        "Pending retry connection_failed must queue the authoritative failed attempt",
        "The first failed retry must advance to the deterministic second backoff",
        '"cancel_host_restart_recovery"',
        '"complete_host_restart_recovery"',
        '"exhaust_host_restart_recovery"',
        "Manual saves must remain blocked",
        "Autosaves must remain blocked",
        "Terminal evidence must retain the complete six-attempt budget",
        "deferred signal-safe transport handoff",
        "pending-attempt signal authority",
        "Host restart recovery smoke test passed",
    ],
)
forbid(
    smoke_path,
    smoke,
    [
        "Time.get_ticks",
        "Time.get_unix",
        "randf(",
        "randi(",
        "FileAccess.open(",
    ],
)

peer_path = "tools/multiplayer_host_restart_peer.gd"
peer = read(peer_path)
require(
    peer_path,
    peer,
    [
        'extends "res://tools/multiplayer_loopback_peer.gd"',
        "RESTART_INPUT_SEQUENCE_START := 20000",
        "RESTART_HOST_SHUTDOWN_EXCHANGE_HOLD_MSEC := 800",
        "host_generation not in [1, 2]",
        '--standby=',
        '--activation=',
        "standby_path",
        "activation_path",
        "wait_for_replacement_activation",
        "HOST RESTART REPLACEMENT STANDBY",
        "HOST RESTART REPLACEMENT ACTIVATED",
        "FileAccess.file_exists(activation_path)",
        '"transport_bound": false',
        "run_original_host_until_forced_loss",
        "run_replacement_host",
        "initial_join_call_count += 1",
        'session.call(\n\t\t"join_session",',
        "HOST RESTART CLIENT CONNECT STARTED",
        "HOST RESTART INITIAL EXCHANGE",
        "HOST RESTART CLIENT INITIAL EXCHANGE",
        "HOST RESTART CLIENT RECOVERY PENDING",
        "HOST RESTART RECOVERED EXCHANGE",
        "HOST RESTART CLIENT RECOVERED",
        '"host_restart_generation"',
        '"host_restart_attempt_count"',
        '"host_restart_recovered"',
        '"host_restart_exhausted"',
        '"host_restart_address"',
        '"host_restart_port"',
        '"host_restart_role"',
        '"manual_save_blocked_after_recovery"',
        '"autosave_blocked_after_recovery"',
        '"request_graceful_host_shutdown"',
        '"HOST RESTART RECOVERY COMPLETE"',
        '"_submit_input"',
        "explicit_input_sequence += 1",
        "while true:",
        "The parent harness must now terminate this process",
    ],
)
require_count(peer_path, peer, '"join_session"', 1)
forbid(
    peer_path,
    peer,
    [
        "const HOST_SHUTDOWN_EXCHANGE_HOLD_MSEC",
        "configure_test_host_session",
        "register_test_peer",
        "test_mode = true",
        "request_graceful_leave",
        "allow_object_decoding = true",
        "SaveProfileStore",
        "write_profile(",
        "read_profile(",
        "randf(",
        "randi(",
    ],
)

harness_path = "scripts/validate_multiplayer_host_restart.ps1"
harness = read(harness_path)
require(
    harness_path,
    harness,
    [
        "[int]$TimeoutSeconds = 75",
        "multiplayer_host_restart_peer.gd",
        '-Generation 1',
        '-Generation 2',
        'Force-Terminate-OriginalHost',
        '$Peer.Process.Kill($true)',
        'without invoking request_graceful_host_shutdown',
        'host-1-exchange.json',
        'ally-initial.json',
        'ally-recovery.json',
        'host-2-standby.json',
        'host-2-activate.txt',
        'host-2-exchange.json',
        '$host2StandbyPath',
        '$host2ActivationPath',
        '-StandbyPath $host2StandbyPath',
        '-ActivationPath $host2ActivationPath',
        'Set-Content -Path $host2ActivationPath',
        'Replacement host standby marker',
        'Prewarmed replacement host must remain alive and unbound',
        'Replacement host bound its UDP endpoint before explicit fault activation',
        'HOST RESTART REPLACEMENT PREWARMED WITHOUT UDP BIND',
        'HOST RESTART REPLACEMENT ACTIVATION RELEASED AFTER RECOVERY BEGAN',
        'explicit_join_calls -ne 1',
        'address -ne "127.0.0.1"',
        'attempt_count -gt 6',
        'Start-Sleep -Milliseconds 550',
        'host_restart_generation -ne 1',
        'host_restart_attempt_count -lt 1',
        'host_restart_attempt_count -gt 6',
        'host_restart_recovered',
        'host_restart_exhausted',
        'host_restart_reason -ne "HOST RESTART RECOVERED"',
        'host_restart_address -ne "127.0.0.1"',
        'host_restart_role -ne "ally"',
        '-not [bool]$allyReceipt.manual_save_blocked_after_recovery',
        '-not [bool]$allyReceipt.autosave_blocked_after_recovery',
        'host_shutdown_expected_count -ne 1',
        'host_shutdown_ack_count -ne 1',
        'host_shutdown_disconnect_count -ne 1',
        'HOST RESTART RECOVERY COMPLETE',
        'Unexpected-host restart recovery passed',
        'Remove-Item -Recurse -Force',
    ],
)
require_order(
    harness_path,
    harness,
    [
        '-Description "Replacement host standby marker"',
        'Force-Terminate-OriginalHost -Peer $host1',
        '-Description "Ally bounded host-restart recovery state"',
        'Set-Content -Path $host2ActivationPath',
        '-Description "Replacement host ready marker"',
    ],
)

forbid(
    harness_path,
    harness,
    [
        "configure_test_host_session",
        "register_test_peer",
        "--test-mode",
        "IgnoreExitCode",
        "request_graceful_leave",
    ],
)

compile_path = "tools/compile_multiplayer_probe.gd"
compile_probe = read(compile_path)
require(
    compile_path,
    compile_probe,
    [
        "multiplayer_host_restart_peer.gd",
        "smoke_multiplayer_host_restart_recovery.gd",
        "deterministic real loopback and host-restart peers",
    ],
)

local_gate_path = "scripts/validate.ps1"
local_gate = read(local_gate_path)
require(
    local_gate_path,
    local_gate,
    [
        "Smoke test bounded unexpected-host restart recovery",
        "smoke_multiplayer_host_restart_recovery.gd",
    ],
)

runtime_contract_path = "src/game/runtime_scene_contract.gd"
runtime_contract = read(runtime_contract_path)
require(
    runtime_contract_path,
    runtime_contract,
    [
        '"begin_host_restart_recovery"',
        '"host_restart_retry_delay_after_attempt"',
        '"blocks_manual_save"',
        '"blocks_autosave"',
    ],
)

workflow_path = ".github/workflows/validate.yml"
workflow = read(workflow_path)
require(
    workflow_path,
    workflow,
    [
        "Validate unexpected host restart recovery contract",
        "python3 tools/check_multiplayer_host_restart_contract.py",
        "Run real unexpected-host restart recovery",
        "scripts/validate_multiplayer_host_restart.ps1",
        '# Receipt schema migrated from: "schemaVersion": "2.9"',
        '"schemaVersion": "2.9"',
        '"multiplayerHostRestartRecoveryValidation": "passed"',
    ],
)
require_order(
    workflow_path,
    workflow,
    [
        "Run real ENet host ally and invader loopback",
        "Run real unexpected-host restart recovery",
        "Confirm validation did not modify tracked source",
    ],
)

release_policy_path = "tools/check_release_workflow_policy.py"
release_policy = read(release_policy_path)
require(
    release_policy_path,
    release_policy,
    [
        "python3 tools/check_multiplayer_host_restart_contract.py",
        '"multiplayerHostRestartRecoveryValidation": "passed"',
        "smoke_multiplayer_host_restart_recovery.gd",
        "unexpected-host restart recovery",
        "epochbound_multiplayer_host_restart_contract_passed",
    ],
)

docs_path = "docs/MULTIPLAYER_HOST_RESTART_RECOVERY.md"
docs = read(docs_path)
require(
    docs_path,
    docs,
    [
        "unexpected host-process loss",
        "same client process",
        "literal IPv4 or IPv6",
        "six attempts",
        "0.35 seconds",
        "2.0 seconds",
        "stale disconnect",
        "one explicit join",
        "forced process termination",
        "replacement host",
        "prewarms the replacement Godot process",
        "does not bind the shared UDP endpoint",
        "activation marker",
        "notification-only",
        "native signal dispatch",
        "production input",
        "authoritative snapshot",
        "acknowledged graceful shutdown",
        "does not provide host migration",
        "validate_multiplayer_host_restart.ps1",
        "multiplayerHostRestartRecoveryValidation",
    ],
)

loopback_docs_path = "docs/MULTIPLAYER_LOOPBACK_GATE.md"
loopback_docs = read(loopback_docs_path)
require(
    loopback_docs_path,
    loopback_docs,
    [
        "MULTIPLAYER_HOST_RESTART_RECOVERY.md",
        "Unexpected-host restart recovery",
        "does not prove host migration",
    ],
)
forbid(
    loopback_docs_path,
    loopback_docs,
    [
        "reconnect after a host restart",
        "automatic outage recovery",
    ],
)

readme_path = "README.md"
readme = read(readme_path)
require(
    readme_path,
    readme,
    [
        "Unexpected-host restart recovery",
        "MULTIPLAYER_HOST_RESTART_RECOVERY.md",
        "multiplayerHostRestartRecoveryValidation",
    ],
)

loopback_contract_path = "tools/check_multiplayer_loopback_contract.py"
loopback_contract = read(loopback_contract_path)
require(
    loopback_contract_path,
    loopback_contract,
    [
        "unexpected-host restart recovery is covered by its dedicated real-process gate",
    ],
)
forbid(
    loopback_contract_path,
    loopback_contract,
    [
        "host restart recovery, migration, public Internet reachability",
    ],
)

if errors:
    print("Epochbound multiplayer host-restart contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_multiplayer_host_restart_contract_passed")
print("- accepted literal IPv4 and IPv6 endpoints are replayed without persisting connection state")
print("- six deterministic attempts use bounded exponential backoff from 0.35 to 2.0 seconds")
print("- duplicate stale-peer signals cannot consume attempts or reset the current timer")
print("- one ally process survives forced host loss and joins a replacement host without a second driver join")
print("- later production input and a fresh authoritative snapshot cross the replacement ENet session")
print("- intentional leave and acknowledged host shutdown remain non-recovering lifecycle boundaries")
print("- host migration, relay, NAT traversal, matchmaking and public Internet reachability remain separate boundaries")
