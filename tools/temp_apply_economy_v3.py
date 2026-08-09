#!/usr/bin/env python3
"""Recover and apply the complete deterministic economy-balance release delta."""

from __future__ import annotations

import base64
import hashlib
import runpy
import subprocess
import zlib
from pathlib import Path

SUPPLEMENT_PATCH_SHA256 = "d94658c1cf2e33fa606aba43442e7e173b9942c3e8301aa8d10e5a51cd258324"
SUPPLEMENT_COMPRESSED_SHA256 = "43c36122e3c744f7fc9dddbe00d1c0d2327486eb0b5140fd997626cbf1862767"
SUPPLEMENT_PARTS = [
    Path("tools/temp_economy_v3_supplement_01.txt"),
    Path("tools/temp_economy_v3_supplement_02.txt"),
    Path("tools/temp_economy_v3_supplement_03.txt"),
    Path("tools/temp_economy_v3_supplement_04.txt"),
]

runpy.run_path("tools/temp_apply_economy_v2.py", run_name="__main__")

encoded = "".join(
    "".join(path.read_text(encoding="utf-8").split())
    for path in SUPPLEMENT_PARTS
)
compressed = base64.b64decode(encoded, validate=True)
if hashlib.sha256(compressed).hexdigest() != SUPPLEMENT_COMPRESSED_SHA256:
    raise SystemExit("compressed economy supplement checksum mismatch")

patch = zlib.decompress(compressed)
if hashlib.sha256(patch).hexdigest() != SUPPLEMENT_PATCH_SHA256:
    raise SystemExit("economy supplement checksum mismatch")

subprocess.run(
    ["git", "apply", "--whitespace=error", "-"],
    input=patch,
    check=True,
)

print("economy_balance_v3_recovery_applied")
print(f"- supplement bytes: {len(patch)}")
print(f"- supplement sha256: {SUPPLEMENT_PATCH_SHA256}")
print("- restored deterministic simulator and adversarial Godot smoke coverage")
