#!/usr/bin/env python3
"""Finish protected workflow bookkeeping for the host-shutdown integration."""

from pathlib import Path


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

policy_path = Path("tools/check_release_workflow_policy.py")
policy = policy_path.read_text(encoding="utf-8")
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
policy_path.write_text(policy.rstrip() + "\n", encoding="utf-8")

normalized_paths = [
    "README.md",
    "docs/MULTIPLAYER_COOP_PVP.md",
    "docs/MULTIPLAYER_LOOPBACK_GATE.md",
    "scripts/validate.ps1",
    "scripts/validate_multiplayer_loopback.ps1",
    "src/multiplayer_transport_session.gd",
    "tools/check_multiplayer_loopback_contract.py",
    "tools/multiplayer_loopback_peer.gd",
    "tools/multiplayer_loopback_peer_driver.gd",
    "tools/smoke_multiplayer_runtime.gd",
]
for relative_path in normalized_paths:
    path = Path(relative_path)
    if path.is_file():
        path.write_text(
            path.read_text(encoding="utf-8").rstrip() + "\n",
            encoding="utf-8",
        )

print("graceful_host_shutdown_protected_edits_finalized")
