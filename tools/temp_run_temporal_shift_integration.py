#!/usr/bin/env python3
"""Run the temporary applicator with one deliberately first-match policy edit."""

from __future__ import annotations

from pathlib import Path

path = Path("tools/temp_apply_temporal_shift_integration.py")
source = path.read_text(encoding="utf-8")
function_anchor = (
    '    file_path.write_text(source.replace(old, new, 1), encoding="utf-8")\n\n\n'
    "replace_once("
)
replacement = (
    '    file_path.write_text(source.replace(old, new, 1), encoding="utf-8")\n\n\n'
    "def replace_first(path: str, old: str, new: str) -> None:\n"
    "    file_path = Path(path)\n"
    '    source = file_path.read_text(encoding="utf-8")\n'
    "    if old not in source:\n"
    '        raise SystemExit(f"{path}: missing first-match replacement anchor: {old[:100]!r}")\n'
    '    file_path.write_text(source.replace(old, new, 1), encoding="utf-8")\n\n\n'
    "replace_once("
)
if source.count(function_anchor) != 1:
    raise SystemExit("temporary applicator function anchor drifted")
source = source.replace(function_anchor, replacement, 1)
call_anchor = '\nreplace_once(\n    "tools/check_release_workflow_policy.py",'
if source.count(call_anchor) < 1:
    raise SystemExit("temporary applicator workflow-policy call anchor drifted")
source = source.replace(
    call_anchor,
    '\nreplace_first(\n    "tools/check_release_workflow_policy.py",',
    1,
)
exec(compile(source, str(path), "exec"), {"__name__": "__main__"})
