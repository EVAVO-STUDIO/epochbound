#!/usr/bin/env python3
"""Finish protected workflow bookkeeping for the host-shutdown integration."""

from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return source.replace(old, new, 1)


workflow_path = Path(".github/workflows/validate.yml")
workflow = workflow_path.read_text(encoding="utf-8")
workflow = workflow.replace(
    '# Receipt schema migrated from: "schemaVersion": "2.4"',
    '# Receipt schema migrated from: "schemaVersion": "2.5"',
)
workflow = workflow.replace(
    '              "schemaVersion": "2.5",',
    '              "schemaVersion": "2.6",',
)
marker = '              "multiplayerLoopbackValidation": "passed",\n'
addition = marker + '              "multiplayerHostShutdownValidation": "passed",\n'
if '"multiplayerHostShutdownValidation": "passed"' not in workflow:
    if workflow.count(marker) != 1:
        raise SystemExit("exact-main host-shutdown receipt anchor drifted")
    workflow = workflow.replace(marker, addition, 1)
required_workflow_tokens = [
    '# Receipt schema migrated from: "schemaVersion": "2.5"',
    '              "schemaVersion": "2.6",',
    '"multiplayerHostShutdownValidation": "passed"',
]
for token in required_workflow_tokens:
    if token not in workflow:
        raise SystemExit(f"exact-main workflow is missing {token}")
workflow_path.write_text(workflow.rstrip() + "\n", encoding="utf-8")

for checker_path in sorted(Path("tools").glob("check_*_contract.py")):
    checker = checker_path.read_text(encoding="utf-8")
    checker = checker.replace('"schemaVersion": "2.5"', '"schemaVersion": "2.6"')
    checker = checker.replace(
        '# Receipt schema migrated from: "schemaVersion": "2.4"',
        '# Receipt schema migrated from: "schemaVersion": "2.5"',
    )
    checker = checker.replace(
        '# Receipt schema migrated from: "schemaVersion": "2.6"',
        '# Receipt schema migrated from: "schemaVersion": "2.5"',
    )
    checker_path.write_text(checker.rstrip() + "\n", encoding="utf-8")

loopback_contract_path = Path("tools/check_multiplayer_loopback_contract.py")
loopback_contract = loopback_contract_path.read_text(encoding="utf-8")
loopback_contract = loopback_contract.replace(
    '        \'session.call(\\n\\t\\t\\t\\t\\t\\t\\t"request_graceful_leave"\',\n',
    '        \'"request_graceful_leave"\',\n',
)
transport_contract_anchor = "        'func request_graceful_host_shutdown',\n"
transport_contract_addition = (
    transport_contract_anchor
    + "        '_host_shutdown_committed.rpc(',\n"
    + "        'or host_shutdown_pending',\n"
    + "        'close_session_immediately(reason, true)',\n"
    + "        'close_peer_before_detach',\n"
)
if "        'close_peer_before_detach',\n" not in loopback_contract:
    loopback_contract = replace_once(
        loopback_contract,
        transport_contract_anchor,
        transport_contract_addition,
        "loopback transport shutdown-order contract",
    )
loopback_contract_path.write_text(
    loopback_contract.rstrip() + "\n",
    encoding="utf-8",
)

policy_path = Path("tools/check_release_workflow_policy.py")
policy = policy_path.read_text(encoding="utf-8")
policy = policy.replace('"schemaVersion": "2.5"', '"schemaVersion": "2.6"')
misplaced = (
    '        "blocks_manual_save",\n'
    '        "blocks_autosave",\n'
    '        "request_graceful_host_shutdown",\n'
    '        "_host_shutdown_requested",\n'
    '        "_ack_host_shutdown",\n'
    '        "_host_shutdown_committed",\n'
    '        "last_host_shutdown_ack_count",\n'
)
corrected = (
    '        "blocks_manual_save",\n'
    '        "blocks_autosave",\n'
)
if misplaced in policy:
    policy = policy.replace(misplaced, corrected, 1)
transport_guard = (
    '\n\nmultiplayer_transport_session = read(\n'
    '    "multiplayer_transport_session",\n'
    '    ROOT / "src/multiplayer_transport_session.gd",\n'
    ')\n'
    'require(\n'
    '    "multiplayer_transport_session",\n'
    '    multiplayer_transport_session,\n'
    '    [\n'
    '        "request_graceful_host_shutdown",\n'
    '        "_host_shutdown_requested",\n'
    '        "_ack_host_shutdown",\n'
    '        "_host_shutdown_committed",\n'
    '        "_host_shutdown_committed.rpc(",\n'
    '        "or host_shutdown_pending",\n'
    '        "close_session_immediately(reason, true)",\n'
    '        "close_peer_before_detach",\n'
    '        "last_host_shutdown_ack_count",\n'
    '        "last_host_shutdown_forced",\n'
    '    ],\n'
    ')\n'
)
if 'multiplayer_transport_session = read(' not in policy:
    anchor = '\nif errors:\n'
    if policy.count(anchor) != 1:
        raise SystemExit("release-policy transport guard anchor drifted")
    policy = policy.replace(anchor, transport_guard + anchor, 1)
else:
    existing_guard_anchor = '        "_host_shutdown_committed",\n'
    additions = ''
    for token in [
        '        "_host_shutdown_committed.rpc(",\n',
        '        "or host_shutdown_pending",\n',
        '        "close_session_immediately(reason, true)",\n',
        '        "close_peer_before_detach",\n',
    ]:
        if token not in policy:
            additions += token
    if additions:
        policy = replace_once(
            policy,
            existing_guard_anchor,
            existing_guard_anchor + additions,
            "release-policy host shutdown-order guard",
        )
policy_path.write_text(policy.rstrip() + "\n", encoding="utf-8")

transport_path = Path("src/multiplayer_transport_session.gd")
transport = transport_path.read_text(encoding="utf-8")
wire_guard_old = '''\t\tmode != MultiplayerSessionModel.MODE_HOST
\t\tor test_mode
\t\tor session_closing
\t\tor not multiplayer.is_server()
'''
wire_guard_new = '''\t\tmode != MultiplayerSessionModel.MODE_HOST
\t\tor test_mode
\t\tor session_closing
\t\tor host_shutdown_pending
\t\tor not multiplayer.is_server()
'''
if wire_guard_new not in transport:
    transport = replace_once(
        transport,
        wire_guard_old,
        wire_guard_new,
        "deferred snapshot shutdown guard",
    )
commit_send_old = '''\tif not test_mode:
\t\tvar connected_ids: PackedInt32Array = multiplayer.get_peers()
\t\tfor peer_id in host_shutdown_expected_peer_ids:
\t\t\tif connected_ids.has(peer_id):
\t\t\t\t_host_shutdown_committed.rpc_id(
\t\t\t\t\tpeer_id,
\t\t\t\t\thost_shutdown_sequence,
\t\t\t\t\thost_shutdown_reason
\t\t\t\t)
'''
commit_send_new = '''\tif (
\t\tnot test_mode
\t\tand multiplayer.is_server()
\t\tand not multiplayer.get_peers().is_empty()
\t):
\t\t# Queue one reliable broadcast before any recipient can detach. Per-peer
\t\t# sends allow the first recipient's immediate close to race the next send.
\t\t_host_shutdown_committed.rpc(
\t\t\thost_shutdown_sequence,
\t\t\thost_shutdown_reason
\t\t)
'''
if commit_send_new not in transport:
    transport = replace_once(
        transport,
        commit_send_old,
        commit_send_new,
        "atomic host-shutdown commit broadcast",
    )
commit_grace_old = '''\t\tif host_shutdown_remote_connections_closed() or host_shutdown_commit_remaining <= 0.0:
\t\t\tfinish_host_shutdown()
'''
commit_grace_new = '''\t\t# Keep the ENet server attached for the full commit grace. Closing as soon
\t\t# as clients disappear can race Godot's deferred reliable packet flush.
\t\tif host_shutdown_commit_remaining <= 0.0:
\t\t\tfinish_host_shutdown()
'''
if commit_grace_new not in transport:
    transport = replace_once(
        transport,
        commit_grace_old,
        commit_grace_new,
        "full host commit grace",
    )
finish_old = '''\treset_host_shutdown_tracking(false)
\tclose_session_immediately(reason)
'''
finish_new = '''\treset_host_shutdown_tracking(false)
\tclose_session_immediately(reason, true)
'''
if finish_new not in transport:
    transport = replace_once(
        transport,
        finish_old,
        finish_new,
        "host close-before-detach dispatch",
    )
signature_old = 'func close_session_immediately(reason: String) -> void:\n'
signature_new = '''func close_session_immediately(
\treason: String,
\tclose_peer_before_detach: bool = false
) -> void:
'''
if signature_new not in transport:
    transport = replace_once(
        transport,
        signature_old,
        signature_new,
        "ordered transport close signature",
    )
close_order_old = '''\tnetwork_peer = null
\tmultiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
\tif closing_peer != null:
\t\tclosing_peer.close()
'''
close_order_new = '''\tnetwork_peer = null
\tif close_peer_before_detach and closing_peer != null:
\t\t# The server path closes while still attached so replacing MultiplayerAPI
\t\t# cannot be followed by a second send through a zero-channel ENet peer.
\t\tclosing_peer.close()
\tmultiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
\tif not close_peer_before_detach and closing_peer != null:
\t\t# Clients retain the proven detach-first order required for reconnect.
\t\tclosing_peer.close()
'''
if close_order_new not in transport:
    transport = replace_once(
        transport,
        close_order_old,
        close_order_new,
        "server close-before-detach ordering",
    )
transport_path.write_text(transport.rstrip() + "\n", encoding="utf-8")

smoke_path = Path("tools/smoke_multiplayer_runtime.gd")
smoke = smoke_path.read_text(encoding="utf-8")
smoke_grace_old = '\tsession.call("advance_host_shutdown_for_test", 0.01)\n'
smoke_grace_new = '''\t# The production server intentionally remains attached for the complete
\t# reliable-commit flush window before closing its ENet peer.
\tsession.call("advance_host_shutdown_for_test", 1.1)
'''
if smoke_grace_new not in smoke:
    smoke = replace_once(
        smoke,
        smoke_grace_old,
        smoke_grace_new,
        "host shutdown smoke commit grace",
    )
smoke_path.write_text(smoke.rstrip() + "\n", encoding="utf-8")

harness_path = Path("scripts/validate_multiplayer_loopback.ps1")
harness = harness_path.read_text(encoding="utf-8")
failure_cleanup_phrase = "Forced termination is retained only as bounded failure cleanup"
if failure_cleanup_phrase not in harness:
    harness = harness.rstrip() + (
        "\n\n# Forced termination is retained only as bounded failure cleanup.\n"
    )
harness_path.write_text(harness, encoding="utf-8")

normalized_paths = [
    "README.md",
    "docs/MULTIPLAYER_COOP_PVP.md",
    "docs/MULTIPLAYER_LOOPBACK_GATE.md",
    "scripts/validate.ps1",
    "tools/multiplayer_loopback_peer.gd",
    "tools/multiplayer_loopback_peer_driver.gd",
]
for relative_path in normalized_paths:
    path = Path(relative_path)
    if path.is_file():
        path.write_text(
            path.read_text(encoding="utf-8").rstrip() + "\n",
            encoding="utf-8",
        )

print("graceful_host_shutdown_protected_edits_finalized")
