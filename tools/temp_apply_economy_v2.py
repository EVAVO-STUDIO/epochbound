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

CONTRACT_SOURCE = r'''#!/usr/bin/env python3
"""Fail closed when Epochbound's deterministic economy-balance gate drifts."""

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


def require_order(relative_path: str, source: str, tokens: list[str]) -> None:
    cursor = -1
    for token in tokens:
        position = source.find(token, cursor + 1)
        if position < 0:
            errors.append(f"{relative_path}: missing ordered token {token}")
            return
        cursor = position


def forbid(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token in source:
            errors.append(f"{relative_path}: contains forbidden {token}")


simulation_path = "src/content/economy_balance_simulation.gd"
simulation = read(simulation_path)
require(
    simulation_path,
    simulation,
    [
        "SIMULATION_HORIZON_SECONDS := 1800.0",
        "economy.starting_wallet_no_choice",
        "economy.starting_wallet_single_choice",
        "economy.optional_spend_strands_recovery",
        "economy.repeatable_arbitrage",
        "economy.recovery_endurance_risk",
        "economy.ammo_endurance_risk",
        "restock_quantity",
    ],
)
forbid(
    simulation_path,
    simulation,
    [
        "Time.get_unix_time",
        "OS.get_unix_time",
        "RandomNumberGenerator",
        "randf(",
        "randi(",
        "FileAccess.open(",
    ],
)

campaign_audit_path = "src/content/campaign_audit.gd"
campaign_audit = read(campaign_audit_path)
require(
    campaign_audit_path,
    campaign_audit,
    [
        'res://src/content/economy_balance_simulation.gd',
        "PROBE_COUNT := 10",
    ],
)

studio_path = "addons/epochbound_campaign_audit/campaign_audit_studio.gd"
studio = read(studio_path)
require(
    studio_path,
    studio,
    [
        "economy",
        "recovery",
        "arbitrage",
    ],
)

smoke_path = "tools/smoke_economy_balance_simulation.gd"
smoke = read(smoke_path)
require(
    smoke_path,
    smoke,
    [
        'CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"',
        "Economy choices 4/4 recovery-safe",
        "economy.repeatable_arbitrage",
        "repeatable arbitrage",
    ],
)
forbid(
    smoke_path,
    smoke,
    [
        "Time.get_unix_time",
        "OS.get_unix_time",
        "randf(",
        "randi(",
    ],
)

compile_path = "tools/compile_probe.gd"
compile_probe = read(compile_path)
require(
    compile_path,
    compile_probe,
    [
        'res://src/content/economy_balance_simulation.gd',
        'res://tools/smoke_economy_balance_simulation.gd',
    ],
)

local_gate_path = "scripts/validate.ps1"
local_gate = read(local_gate_path)
require(
    local_gate_path,
    local_gate,
    [
        "Smoke test deterministic economy balance simulation",
        "res://tools/smoke_economy_balance_simulation.gd",
        "Economy choices 4/4 recovery-safe",
    ],
)
require_order(
    local_gate_path,
    local_gate,
    [
        "Smoke test warning-free reference campaign release readiness",
        "Smoke test deterministic economy balance simulation",
    ],
)

workflow_path = ".github/workflows/validate.yml"
workflow = read(workflow_path)
require(
    workflow_path,
    workflow,
    [
        "Validate deterministic economy balance integration contract",
        "python3 tools/check_economy_balance_contract.py",
        '# Receipt schema migrated from: "schemaVersion": "2.6"',
        '"schemaVersion": "2.7"',
        '"economyBalanceValidation": "passed"',
    ],
)

release_policy_path = "tools/check_release_workflow_policy.py"
release_policy = read(release_policy_path)
require(
    release_policy_path,
    release_policy,
    [
        "python3 tools/check_economy_balance_contract.py",
        "epochbound_economy_balance_contract_passed",
        "SIMULATION_HORIZON_SECONDS := 1800.0",
        "economy.repeatable_arbitrage",
        "Economy choices 4/4 recovery-safe",
        '"economyBalanceValidation": "passed"',
    ],
)

readme_path = "README.md"
readme = read(readme_path)
require(
    readme_path,
    readme,
    [
        "ECONOMY_BALANCE_SIMULATION.md",
        "ECONOMY_PLAYTEST_CHECKLIST.md",
        "economyBalanceValidation",
    ],
)

documentation_path = "docs/ECONOMY_BALANCE_SIMULATION.md"
documentation = read(documentation_path)
require(
    documentation_path,
    documentation,
    [
        "fixed 1,800 seconds of active play",
        "economy.repeatable_arbitrage",
        "four executable opening preparation purchases",
        "four recovery-safe choices",
        "twenty renewable healing units",
        "eighty renewable ammunition units",
        "three finite non-renewable equipment offers",
        "zero economy-balance findings",
        "not a fun score",
    ],
)

playtest_path = "docs/ECONOMY_PLAYTEST_CHECKLIST.md"
playtest = read(playtest_path)
require(
    playtest_path,
    playtest,
    [
        "economy",
        "recovery",
        "ammunition",
        "arbitrage",
        "supply",
    ],
)

if errors:
    print("Epochbound economy-balance contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_economy_balance_contract_passed")
print("- deterministic thirty-minute active-play horizon remains fixed")
print("- opening purchases remain enumerable and recovery-safe")
print("- repeatable arbitrage remains release-stopping while finite trade rewards stay measurable")
print("- recovery, ammunition and finite equipment endurance remain visible in Campaign Audit")
print("- schema-2.7 exact-main evidence records economyBalanceValidation")
'''

DOCUMENTATION_PROVENANCE = '''## Automated release gate

The production implementation is protected by `tools/check_economy_balance_contract.py`, the deterministic Godot smoke test, the complete local validation gate and the exact-main schema-2.7 receipt. The contract fails closed if the 30-minute horizon, authored finding identifiers, Campaign Audit integration, compile coverage, human playtest checklist or release evidence drifts.
'''

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

contract_path = Path("tools/check_economy_balance_contract.py")
contract_path.write_text(CONTRACT_SOURCE, encoding="utf-8")

documentation_path = Path("docs/ECONOMY_BALANCE_SIMULATION.md")
documentation = documentation_path.read_text(encoding="utf-8").rstrip()
if "## Automated release gate" not in documentation:
    documentation = f"{documentation}\n\n{DOCUMENTATION_PROVENANCE.strip()}\n"
    documentation_path.write_text(documentation, encoding="utf-8")

print("economy_balance_v2_patch_applied")
print(f"- patch bytes: {len(patch)}")
print(f"- patch sha256: {PATCH_SHA256}")
print("- generated fail-closed economy release contract")
print("- bound documentation to the automated schema-2.7 release gate")
