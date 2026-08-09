#!/usr/bin/env python3
"""Apply the exact deterministic economy-balance production patch."""

from __future__ import annotations

import base64
import hashlib
import subprocess
import zlib
from pathlib import Path

PATCH_SHA256 = "ebb6a3c2fff1ec77549aa27fa69b96e5e4794fa3adb0c45cac50f12fdea70bd1"
COMPRESSED_SHA256 = "57ad5ea1963a65bf56517fc3c1cdb87539cc390b33bec99a547a7e1473c2133c"
PARTS = [
    Path("tools/temp_economy_v2_part01.txt"),
    Path("tools/temp_economy_v2_part02.txt"),
]

encoded = "".join("".join(path.read_text(encoding="utf-8").split()) for path in PARTS)
compressed = base64.b64decode(encoded, validate=True)
if hashlib.sha256(compressed).hexdigest() != COMPRESSED_SHA256:
    raise SystemExit("compressed economy patch checksum mismatch")

patch = zlib.decompress(compressed)
if hashlib.sha256(patch).hexdigest() != PATCH_SHA256:
    raise SystemExit("economy patch checksum mismatch")

subprocess.run(
    ["git", "apply", "--whitespace=error", "-"],
    input=patch,
    check=True,
)
print("economy_balance_v2_patch_applied")
print(f"- patch bytes: {len(patch)}")
print(f"- patch sha256: {PATCH_SHA256}")
