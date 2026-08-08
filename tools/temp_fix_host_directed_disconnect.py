#!/usr/bin/env python3
"""Apply the host-directed disconnect protocol in bounded verified parts."""

from pathlib import Path
import runpy

PARTS = [
    "tools/temp_fix_host_directed_disconnect_part1.py",
    "tools/temp_fix_host_directed_disconnect_part2.py",
    "tools/temp_fix_host_directed_disconnect_part3.py",
]

for relative_path in PARTS:
    path = Path(relative_path)
    if not path.is_file():
        raise SystemExit(f"Missing host-directed disconnect patch part: {relative_path}")
    runpy.run_path(str(path), run_name="__main__")

for relative_path in [
    "README.md",
    "docs/MULTIPLAYER_COOP_PVP.md",
    "docs/MULTIPLAYER_LOOPBACK_GATE.md",
    "scripts/validate_multiplayer_loopback.ps1",
    "src/multiplayer_transport_session.gd",
    "tools/check_multiplayer_loopback_contract.py",
    "tools/check_release_workflow_policy.py",
    "tools/multiplayer_loopback_peer.gd",
    "tools/multiplayer_loopback_peer_driver.gd",
    "tools/smoke_multiplayer_runtime.gd",
]:
    path = Path(relative_path)
    if path.is_file():
        path.write_text(
            path.read_text(encoding="utf-8").rstrip() + "\n",
            encoding="utf-8",
        )

print("host_directed_disconnect_protocol_applied")
