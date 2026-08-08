#!/usr/bin/env python3
"""Fail closed when Epochbound boss phase music stem integration drifts."""

from __future__ import annotations

import json
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


def require_order(name: str, source: str, tokens: list[str]) -> None:
    cursor = -1
    for token in tokens:
        position = source.find(token, cursor + 1)
        if position < 0:
            errors.append(f"{name}: missing ordered token {token}")
            return
        cursor = position


catalog = read("audio_catalog", "src/content/audio_mood_catalog.gd")
require(
    "audio_catalog",
    catalog,
    [
        '"boss_stems": []',
        "var boss_stems: Dictionary = {}",
        "var boss_stem_sources: Dictionary = {}",
        'data.get("boss_stems", [])',
        "merge_boss_stem(",
        "static func boss_stem_key(boss_id: String, phase_id: String) -> String:",
        "static func boss_stem(definitions: Dictionary, boss_id: String, phase_id: String) -> Dictionary:",
        '"boss_stems": boss_stems',
        '"boss_stem_sources": boss_stem_sources',
    ],
)
forbid(
    "audio_catalog",
    catalog,
    [
        "ResourceLoader",
        "HTTPClient",
        "FileAccess.open_encrypted",
    ],
)

validator = read("audio_validator", "src/content/audio_mood_validator.gd")
require(
    "audio_validator",
    validator,
    [
        'preload("res://src/content/object_catalog.gd")',
        'preload("res://src/content/boss_catalog.gd")',
        "static func validate_boss_stem_record(",
        "BossCatalog.is_boss",
        "BossCatalog.phase_by_id",
        "validate_boss_stem_sequence(",
        "enabled boss phase",
        '"boss_stem_count": boss_stem_count',
    ],
)

strict_validator = read("strict_audio_validator", "src/content/audio_mood_strict_validator.gd")
require(
    "strict_audio_validator",
    strict_validator,
    [
        "static func validate_boss_stem_record(",
        "BaseValidator.validate_boss_stem_record",
        "validate_boss_stem_integral_values",
        'stem_data.get("root_offset", null)',
        '"melody_steps"',
        '"bass_steps"',
    ],
)

controller = read("audio_controller", "src/audio_mood_controller.gd")
require(
    "audio_controller",
    controller,
    [
        "var boss_stems: Dictionary = {}",
        "var active_boss_stem: Dictionary = {}",
        'var active_boss_stem_key := ""',
        "var boss_stem_sample_clock := 0",
        "func resolve_active_boss_stem(force: bool) -> void:",
        "func current_boss_audio_context() -> Dictionary:",
        'runtime_dictionary("engaged_bosses")',
        'runtime_dictionary("boss_contexts")',
        'runtime_dictionary("boss_phase_ids")',
        "AudioMoodCatalog.boss_stem(",
        "boss_stem_mix_current",
        "boss_stem_sample_clock += 1",
        "func boss_stem_snapshot() -> Dictionary:",
    ],
)
require_order(
    "audio_controller_process",
    controller,
    [
        "resolve_active_profile(false)",
        "resolve_active_boss_stem(false)",
        "update_mix(delta)",
        "fill_music()",
    ],
)
forbid(
    "audio_controller",
    controller,
    [
        'if boss_id == "underworks_sentinel"',
        'if phase_id == "last_accession"',
        "randf(",
        "randi(",
        "Time.get_unix_time",
        "OS.get_unix_time",
    ],
)

runtime = read("audio_runtime", "src/audio_mood_runtime.gd")
require(
    "audio_runtime",
    runtime,
    [
        'boss_stems = result.get("boss_stems", {})',
        "boss_stems.clear()",
        "resolve_active_boss_stem(true)",
    ],
)

studio = read(
    "audio_studio",
    "addons/epochbound_audio_mood_studio/audio_mood_studio.gd",
)
require(
    "audio_studio",
    studio,
    [
        "var boss_stem_label: Label",
        'current_catalog.get("boss_stems", [])',
        "func boss_stem_count() -> int:",
        "Boss phase stems:",
    ],
)

smoke = read("boss_stem_smoke", "tools/smoke_boss_music_stems.gd")
require(
    "boss_stem_smoke",
    smoke,
    [
        "Reference campaign must expose three boss phase music stems.",
        "Verdant engagement must resolve Catalogue Measure music.",
        "Ashen era shift must resolve Cinder Measure music.",
        "Changing phase stems must reset only the phase-stem sample clock.",
        "Health-threshold transition must resolve Last Accession music.",
        "Boss disengagement must clear the transient phase stem.",
        "Duplicate boss and phase stem keys must fail deterministically.",
    ],
)

studio_smoke = read("audio_studio_smoke", "tools/smoke_audio_mood_studio.gd")
require(
    "audio_studio_smoke",
    studio_smoke,
    [
        "studio.boss_stem_count() == 3",
        "three reference boss stems",
    ],
)

edge_smoke = read("audio_edge_smoke", "tools/smoke_audio_mood_validation_edges.gd")
require(
    "audio_edge_smoke",
    edge_smoke,
    [
        "validate_boss_stem_record",
        "Malformed boss stem",
        "Duplicate boss stem",
    ],
)

compile_probe = read("compile_probe", "tools/compile_probe.gd")
require(
    "compile_probe",
    compile_probe,
    ['"res://tools/smoke_boss_music_stems.gd"'],
)

local_gate = read("local_gate", "scripts/validate.ps1")
require(
    "local_gate",
    local_gate,
    [
        "Smoke test authored boss phase music stems",
        "smoke_boss_music_stems.gd",
        "boss phase music stems",
    ],
)

workflow = read("validate_workflow", ".github/workflows/validate.yml")
require(
    "validate_workflow",
    workflow,
    [
        "Validate boss phase music stem contract",
        "python3 tools/check_boss_music_stem_contract.py",
        '# Receipt schema migrated from: "schemaVersion": "2.3"',
        '"schemaVersion": "2.4"',
        '"bossMusicStemValidation": "passed"',
    ],
)

focused_workflow = read(
    "audio_workflow",
    ".github/workflows/audio-mood-validation.yml",
)
require(
    "audio_workflow",
    focused_workflow,
    [
        "Validate boss phase music stem contract",
        "python3 tools/check_boss_music_stem_contract.py",
        "smoke_boss_music_stems.gd",
    ],
)

release_policy = read("release_policy", "tools/check_release_workflow_policy.py")
require(
    "release_policy",
    release_policy,
    [
        "python3 tools/check_boss_music_stem_contract.py",
        '"schemaVersion": "2.4"',
        '"bossMusicStemValidation": "passed"',
        "check_boss_music_stem_contract.py",
        "smoke_boss_music_stems.gd",
        "boss phase music stems",
    ],
)

readme = read("readme", "README.md")
require(
    "readme",
    readme,
    [
        "Authored boss phase music stems",
        "BOSS_MUSIC_STEMS.md",
        "bossMusicStemValidation",
    ],
)

documentation = read("boss_stem_documentation", "docs/BOSS_MUSIC_STEMS.md")
require(
    "boss_stem_documentation",
    documentation,
    [
        "boss_id|phase_id",
        "Catalogue Measure",
        "Cinder Measure",
        "Last Accession",
        "presentation-only",
        "Manual listening review",
    ],
)

audio_documentation = read("audio_documentation", "docs/AUDIO_MOOD_STUDIO.md")
require(
    "audio_documentation",
    audio_documentation,
    [
        "Boss phase stems",
        "boss_stems",
        "BOSS_MUSIC_STEMS.md",
    ],
)

catalog_path = ROOT / "campaigns/epochbound_demo/audio/core.json"
if not catalog_path.is_file():
    errors.append("reference_audio: missing campaigns/epochbound_demo/audio/core.json")
else:
    try:
        reference_audio = json.loads(catalog_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"reference_audio: invalid JSON: {exc}")
    else:
        stems = reference_audio.get("boss_stems", [])
        expected = {
            "underworks_sentinel|catalogue_measure",
            "underworks_sentinel|cinder_measure",
            "underworks_sentinel|last_accession",
        }
        actual = {
            f"{str(stem.get('boss_id', ''))}|{str(stem.get('phase_id', ''))}"
            for stem in stems
            if isinstance(stem, dict)
        }
        if len(stems) != 3:
            errors.append(f"reference_audio: expected 3 boss stems, found {len(stems)}")
        if actual != expected:
            errors.append(
                "reference_audio: expected exact Sentinel phase coverage, found "
                + repr(sorted(actual))
            )

if errors:
    print("Epochbound boss music stem contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_boss_music_stem_contract_passed")
print("- boss stems resolve through stable boss and phase IDs rather than hard-coded encounters")
print("- exploration profiles continue while deterministic phase layers crossfade above them")
print("- strict validation rejects duplicate, unknown, fractional and out-of-range stem data")
print("- Catalogue Measure, Cinder Measure and Last Accession remain permanently covered")
print("- editor summary, local gate, focused Audio gate and exact-main receipt stay pinned")
