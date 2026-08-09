#!/usr/bin/env python3
"""Fail closed when Epochbound's meaningful temporal-shift audit drifts."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(name: str, relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.is_file():
        errors.append(f"{name}: required file is missing: {relative_path}")
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


helper = read("temporal_shift_audit", "src/content/temporal_shift_audit.gd")
require(
    "temporal_shift_audit",
    helper,
    [
        '"route"',
        '"threat"',
        '"information"',
        '"relationship"',
        '"resource"',
        '"temporal.palette_only"',
        '"multi_era_map_count"',
        '"meaningful_shift_map_count"',
        '"temporal_outcome_count"',
        "collect_route_evidence",
        "collect_interaction_evidence",
        "collect_companion_evidence",
        "collect_object_evidence",
        "collect_boss_phase_evidence",
        "collect_encounter_evidence",
        "dialogue_varies",
        'record.get("available_eras", [])',
        "declared_available_count",
        "declared_available_count > 0 and declared_available_count < era_ids.size()",
        'object_definition.get("boss", {})',
        'boss_value as Dictionary).get("phases", [])',
    ],
)
forbid(
    "temporal_shift_audit",
    helper,
    [
        'map_data.get("palette"',
        'map_data.get("landmarks"',
        'Time.get_ticks',
        'OS.get_unix_time',
        'randf(',
        'randi(',
    ],
)

campaign_audit = read("campaign_audit", "src/content/campaign_audit.gd")
require(
    "campaign_audit",
    campaign_audit,
    [
        'TemporalShiftAudit = preload("res://src/content/temporal_shift_audit.gd")',
        "PROBE_COUNT := 10",
        '"multi_era_map_count": 0',
        '"meaningful_shift_map_count": 0',
        '"temporal_outcome_count": 0',
        'TemporalShiftAudit.audit(maps, objects, findings)',
    ],
)

smoke = read("temporal_smoke", "tools/smoke_temporal_shift_audit.gd")
require(
    "temporal_smoke",
    smoke,
    [
        '"palette_only"',
        '"authored_shift"',
        '"temporal.palette_only"',
        '"available_eras": ["verdant", "ashen"]',
        '"temporal_route_count"',
        '"temporal_threat_count"',
        '"temporal_information_count"',
        '"temporal_relationship_count"',
        '"temporal_resource_count"',
        "Records available in every declared era must not count as route consequences",
        "Repeated temporal audits must produce deterministic evidence and findings",
    ],
)

reference_smoke = read("reference_smoke", "tools/smoke_campaign_audit.gd")
require(
    "reference_smoke",
    reference_smoke,
    [
        "all ten production probes",
        'metrics.get("multi_era_map_count", 0)',
        'metrics.get("meaningful_shift_map_count", 0)',
        'metrics.get("temporal_route_count", 0)',
        'metrics.get("temporal_threat_count", 0)',
        'metrics.get("temporal_information_count", 0)',
        'metrics.get("temporal_relationship_count", 0)',
        'metrics.get("temporal_resource_count", 0)',
    ],
)

edge_smoke = read("edge_smoke", "tools/smoke_campaign_audit_edges.gd")
require(
    "edge_smoke",
    edge_smoke,
    [
        '"temporal.palette_only"',
        '"orphan"',
        "Synthetic audit must execute all ten probes",
    ],
)

studio = read("audit_studio", "addons/epochbound_campaign_audit/campaign_audit_studio.gd")
require(
    "audit_studio",
    studio,
    [
        "Temporal maps %d/%d authored",
        "Route %d",
        "Threat %d",
        "Information %d",
        "Relationship %d",
        "Resource %d",
    ],
)

studio_smoke = read("studio_smoke", "tools/smoke_campaign_audit_studio.gd")
require(
    "studio_smoke",
    studio_smoke,
    [
        "all ten production probes",
        "Temporal maps 3/3 authored",
        "Temporal outcomes",
    ],
)

compile_probe = read("compile_probe", "tools/compile_probe.gd")
require(
    "compile_probe",
    compile_probe,
    [
        '"res://src/content/temporal_shift_audit.gd"',
        '"res://tools/smoke_temporal_shift_audit.gd"',
    ],
)

local_gate = read("local_gate", "scripts/validate.ps1")
require(
    "local_gate",
    local_gate,
    [
        "Smoke test meaningful temporal shift consequences",
        "smoke_temporal_shift_audit.gd",
        "meaningful temporal shifts",
    ],
)

documentation = read("audit_documentation", "docs/CAMPAIGN_AUDIT_STUDIO.md")
require(
    "audit_documentation",
    documentation,
    [
        "all ten audit probes",
        "## Ten permanent probes",
        "### 10. Temporal shift consequence",
        "`temporal.palette_only`",
        "route, threat, information, relationship or resource",
        "Records available in every declared era are neutral",
        "Palette and landmark styling do not count as evidence",
    ],
)

checklist = read("audit_checklist", "docs/AUDIT_PLAYTEST_CHECKLIST.md")
require(
    "audit_checklist",
    checklist,
    [
        "all ten probes",
        "## Temporal shift consequences",
        "Temporal maps",
        "`temporal.palette_only`",
        "same ten-probe audit report",
    ],
)

readme = read("readme", "README.md")
require(
    "readme",
    readme,
    [
        "ten deterministic production probes",
        "meaningful temporal-shift consequences",
        "Meaningful era consequences before palette-only shifts",
    ],
)

workflow = read("validate_workflow", ".github/workflows/validate.yml")
require(
    "validate_workflow",
    workflow,
    [
        "python3 tools/check_temporal_shift_contract.py",
        '# Receipt schema migrated from: "schemaVersion": "2.6"',
        '"schemaVersion": "2.7"',
        '"temporalShiftValidation": "passed"',
    ],
)

release_policy = read("release_policy", "tools/check_release_workflow_policy.py")
require(
    "release_policy",
    release_policy,
    [
        "python3 tools/check_temporal_shift_contract.py",
        '"schemaVersion": "2.7"',
        '"temporalShiftValidation": "passed"',
        "smoke_temporal_shift_audit.gd",
        "meaningful temporal shifts",
    ],
)

if errors:
    print("Epochbound temporal shift contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_temporal_shift_contract_passed")
print("- every multi-era map is measured against route, threat, information, relationship and resource evidence")
print("- all-era records, palette and landmark styling cannot satisfy the meaningful-shift release probe")
print("- reference, edge, editor, local and exact-main gates pin deterministic temporal evidence")
