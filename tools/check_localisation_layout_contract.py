#!/usr/bin/env python3
"""Fail closed when Epochbound's fixed-viewport localisation layout safety drifts."""

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


def forbid(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token in source:
            errors.append(f"{relative_path}: contains forbidden {token}")


def require_order(relative_path: str, source: str, earlier: str, later: str) -> None:
    first = source.find(earlier)
    second = source.find(later)
    if first < 0:
        errors.append(f"{relative_path}: missing ordered token {earlier}")
    elif second < 0:
        errors.append(f"{relative_path}: missing ordered token {later}")
    elif first >= second:
        errors.append(f"{relative_path}: expected {earlier} before {later}")


layout = read("src/content/localisation_layout.gd")
require(
    "src/content/localisation_layout.gd",
    layout,
    [
        "@tool",
        "extends RefCounted",
        'ELLIPSIS := "…"',
        "WIDTH_EPSILON := 0.5",
        "MIN_FONT_SIZE := 4",
        "MAX_FONT_SIZE := 96",
        "MAX_WRAP_LINES := 16",
        "localisation_layout_contract_ok",
        "fit_single_line",
        "fit_block",
        "wrap_text",
        "split_long_token",
        "ellipsize",
        "line_with_ellipsis",
        "lines_fit",
        "max_line_width",
        "block_height",
        "font.get_string_size",
        '"truncated": false',
        '"errors": []',
        "The minimum-size text cannot fit the declared width.",
        "The minimum-size block cannot fit the declared bounds.",
    ],
)
require_order(
    "src/content/localisation_layout.gd",
    layout,
    "for size in range(preferred, minimum - 1, -1):",
    "var clipped := ellipsize",
)
forbid(
    "src/content/localisation_layout.gd",
    layout,
    [
        "Time.get_",
        "OS.delay",
        "HTTPRequest",
        "HTTPClient",
        "TranslationServer.set_locale",
        "randf",
        "randi",
    ],
)

app = read("src/app.gd")
require(
    "src/app.gd",
    app,
    [
        'LocalisationLayout = preload("res://src/content/localisation_layout.gd")',
        "LocalisationLayout.localisation_layout_contract_ok()",
        "func draw_fitted_line(",
        "func draw_fitted_block(",
        "LocalisationLayout.fit_single_line(",
        "LocalisationLayout.fit_block(",
        "Rect2(84, 207, 472, 66)",
        "VIEW.x - 24.0",
        "draw_title",
        "draw_campaign_select",
        "draw_intro",
        "draw_hud",
    ],
)
forbid(
    "src/app.gd",
    app,
    [
        'draw_string(ThemeDB.fallback_font, Vector2(229, 152 + index * 27), menu[index]',
        'draw_string(ThemeDB.fallback_font, Vector2(132, y), entry_title',
        'draw_string(ThemeDB.fallback_font, Vector2(455, y), source_label',
    ],
)

for overlay_path, helper, contract in [
    (
        "src/combat_readability_overlay.gd",
        "draw_localised_fitted_line",
        "player_settings_overlay_contract_ok",
    ),
    (
        "src/player_controls_overlay.gd",
        "draw_fitted_line",
        "control_remapping_overlay_contract_ok",
    ),
]:
    overlay = read(overlay_path)
    require(
        overlay_path,
        overlay,
        [
            'LocalisationLayout = preload("res://src/content/localisation_layout.gd")',
            f"func {helper}(",
            "LocalisationLayout.fit_single_line(",
            "LocalisationLayout.localisation_layout_contract_ok()",
            contract,
            "HORIZONTAL_ALIGNMENT_RIGHT",
            "HORIZONTAL_ALIGNMENT_CENTER",
        ],
    )

runtime_contract = read("src/game/runtime_scene_contract.gd")
require(
    "src/game/runtime_scene_contract.gd",
    runtime_contract,
    [
        'LocalisationLayout = preload("res://src/content/localisation_layout.gd")',
        "LocalisationLayout.localisation_layout_contract_ok()",
        "Localisation layout utility contract is invalid.",
    ],
)

compile_probe = read("tools/compile_localisation_layout_probe.gd")
require(
    "tools/compile_localisation_layout_probe.gd",
    compile_probe,
    [
        'LocalisationLayout = preload("res://src/content/localisation_layout.gd")',
        '"res://src/content/localisation_layout.gd"',
        '"res://src/app.gd"',
        '"res://src/combat_readability_overlay.gd"',
        '"res://src/player_controls_overlay.gd"',
        '"res://tools/smoke_localisation_layout.gd"',
        "localisation_layout_contract_ok",
        "Localisation layout compile probe passed",
    ],
)

smoke = read("tools/smoke_localisation_layout.gd")
require(
    "tools/smoke_localisation_layout.gd",
    smoke,
    [
        'LocalisationLayout = preload("res://src/content/localisation_layout.gd")',
        'LocalisationCatalog.PSEUDO_LOCALE',
        "test_layout_primitives",
        "test_ui_surface_budgets",
        "test_reference_intro_budget",
        '"ui.hideaway.status.header"',
        '"ui.hideaway.status.facility"',
        '"width": 464.0',
        "fit_single_line",
        "fit_block",
        "WIDTH_EPSILON",
        "must fit current pseudo-localised copy without truncation",
        "Truncated copy must use the stable ellipsis marker",
        "Single-line fitting must be deterministic",
        "Block fitting must be deterministic",
        "Localisation layout smoke test passed",
    ],
)

for compile_path in [
    "tools/compile_probe.gd",
    "tools/compile_localisation_probe.gd",
    "tools/compile_player_settings_probe.gd",
    "tools/compile_sprite_animation_probe.gd",
    "tools/compile_supply_region_probe.gd",
]:
    source = read(compile_path)
    require(
        compile_path,
        source,
        [
            '"res://src/content/localisation_layout.gd"',
            '"res://tools/compile_localisation_layout_probe.gd"',
            '"res://tools/smoke_localisation_layout.gd"',
        ],
    )

local_gate = read("scripts/validate.ps1")
require(
    "scripts/validate.ps1",
    local_gate,
    [
        "Compile deterministic localisation layout utility and regressions",
        "res://tools/compile_localisation_layout_probe.gd",
        "Smoke test fixed-viewport localisation layout safety",
        "res://tools/smoke_localisation_layout.gd",
        "measured localisation layout",
    ],
)

for workflow_path in [
    ".github/workflows/validate.yml",
    ".github/workflows/audio-mood-validation.yml",
    ".github/workflows/sprite-animation-validation.yml",
]:
    workflow = read(workflow_path)
    require(
        workflow_path,
        workflow,
        [
            "python3 tools/check_localisation_layout_contract.py",
        ],
    )
    if workflow_path != ".github/workflows/validate.yml":
        require(
            workflow_path,
            workflow,
            [
                "compile_localisation_layout_probe.gd",
                "smoke_localisation_layout.gd",
            ],
        )

primary_workflow = read(".github/workflows/validate.yml")
require(
    ".github/workflows/validate.yml",
    primary_workflow,
    [
        '# Receipt schema migrated from: "schemaVersion": "2.9"',
        '"schemaVersion": "2.10"',
        '"localisationValidation": "passed"',
        '"localisationLayoutValidation": "passed"',
    ],
)

release_policy = read("tools/check_release_workflow_policy.py")
require(
    "tools/check_release_workflow_policy.py",
    release_policy,
    [
        "python3 tools/check_localisation_layout_contract.py",
        "compile_localisation_layout_probe.gd",
        "smoke_localisation_layout.gd",
        '"schemaVersion": "2.10"',
        '"localisationLayoutValidation": "passed"',
        "measured localisation layout",
    ],
)

for documentation_path in [
    "README.md",
    "docs/LOCALISATION_FOUNDATION.md",
    "docs/LOCALISATION_LAYOUT_SAFETY.md",
]:
    source = read(documentation_path)
    require(
        documentation_path,
        source,
        [
            "measured",
            "pseudo-local",
            "ellipsis",
        ],
    )

if errors:
    print("Epochbound localisation layout contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_localisation_layout_contract_passed")
print("- real Godot font measurement owns fixed-viewport text fitting")
print("- authored size ranges shrink deterministically before bounded wrapping or visible ellipsis")
print("- title campaign intro settings controls prompts HUD and overlay surfaces remain protected")
print("- current English and pseudo-localised copy is measured against production pixel budgets")
print("- primary focused and local gates record schema-2.10 localisationLayoutValidation evidence")
