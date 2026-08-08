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

print("host_directed_disconnect_protocol_applied")
