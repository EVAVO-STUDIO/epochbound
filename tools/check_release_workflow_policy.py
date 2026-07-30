#!/usr/bin/env python3
"""Fail closed when Epochbound GitHub Actions release policy drifts."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = {
    "validate": ROOT / ".github/workflows/validate.yml",
    "linux_agent": ROOT / ".github/workflows/godot-linux-agent-qa.yml",
}
errors: list[str] = []


def read(name: str, path: Path) -> str:
    if not path.is_file():
        errors.append(f"{name}: workflow is missing: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")


def require(name: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token not in source:
            errors.append(f"{name}: missing {token}")


def forbid(name: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token in source:
            errors.append(f"{name}: contains forbidden {token}")


def events(source: str) -> set[str]:
    lines = source.splitlines()
    start = next((i for i, line in enumerate(lines) if line == "on:"), None)
    if start is None:
        return set()
    found: set[str] = set()
    for line in lines[start + 1 :]:
        if line and not line.startswith(" "):
            break
        match = re.match(r"^  ([A-Za-z_][A-Za-z0-9_-]*):", line)
        if match:
            found.add(match.group(1))
    return found


sources = {name: read(name, path) for name, path in WORKFLOWS.items()}
for name, source in sources.items():
    workflow_events = events(source)
    if workflow_events != {"workflow_dispatch"}:
        errors.append(
            f"{name}: only workflow_dispatch is allowed, found {sorted(workflow_events)}"
        )
    require(
        name,
        source,
        [
            "expected_sha:",
            "request_source:",
            "default: evavo-development-studio",
            "permissions:\n  contents: read",
            "cancel-in-progress: false",
        ],
    )
    forbid(
        name,
        source,
        [
            "contents: write",
            "git push",
            "git reset --hard",
            "git clean -",
            "vercel deploy",
            "wrangler deploy",
            "gh release create",
        ],
    )

require(
    "validate",
    sources["validate"],
    [
        "actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955",
        "persist-credentials: false",
        "ref: ${{ inputs.expected_sha }}",
        "SHA512-SUMS.txt",
        "sha512sum --check",
        "python3 tools/check_release_workflow_policy.py",
        "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
        "git merge-base --is-ancestor",
        "git diff --exit-code",
    ],
)
require(
    "linux_agent",
    sources["linux_agent"],
    [
        "reusable-godot-linux-sandbox.yml@9d81ab2135cdcf24bd5f682843b53d897bbc1579",
        "lab_sha: 9d81ab2135cdcf24bd5f682843b53d897bbc1579",
        "inputs.request_source == 'evavo-development-studio'",
        "inputs.expected_sha || 'invalid-request-source'",
    ],
)

if errors:
    print("Epochbound release workflow policy failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_release_workflow_policy_passed")
print("- workflows are manual exact-SHA only")
print("- remote actions and reusable workflows are immutable")
print("- validation cannot publish, deploy, reset, clean or push")
