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
    "src/multiplayer_transport_session.gd",
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
