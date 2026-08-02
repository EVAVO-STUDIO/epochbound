#!/usr/bin/env python3
"""Fail closed when Epochbound's canonical playable scene composition drifts."""

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


scene = read("src/app.tscn")
require(
    "src/app.tscn",
    scene,
    [
        'res://src/presentation_runtime_current.gd',
        'res://src/combat_readability_overlay.gd',
        'res://src/presentation_camera.gd',
        'res://src/audio_mood_runtime.gd',
        '[node name="PresentationLayer" type="CanvasLayer" parent="."]',
        'layer = 10',
    ],
)

contract = read("src/game/runtime_scene_contract.gd")
require(
    "src/game/runtime_scene_contract.gd",
    contract,
    [
        'CURRENT_RUNTIME_SCRIPT := "res://src/presentation_runtime_current.gd"',
        'CURRENT_OVERLAY_SCRIPT := "res://src/combat_readability_overlay.gd"',
        'CURRENT_AUDIO_SCRIPT := "res://src/audio_mood_runtime.gd"',
        'CURRENT_CAMERA_SCRIPT := "res://src/presentation_camera.gd"',
        '"start_conversation"',
        '"capture_save_profile"',
        '"open_merchant"',
        '"apply_due_supply_restock"',
        '"supply_region_status_text"',
        '"supply_runtime_contract_ok"',
        '"start_reload"',
        '"update_boss_engagements"',
        '"start_cinematic"',
        '"open_player_settings"',
        '"player_settings_contract_ok"',
        '"player_settings_overlay_contract_ok"',
        '"player_settings_audio_contract_ok"',
        '"root_presentation_suppression_contract_ok"',
        'validate_runtime_scene',
        'runtime_scene_is_valid',
    ],
)

runtime = read("src/presentation_runtime_current.gd")
require(
    "src/presentation_runtime_current.gd",
    runtime,
    [
        'extends "res://src/presentation_runtime_base.gd"',
        'SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")',
        'SupplyValidator = preload("res://src/content/supply_region_validator.gd")',
        'SupplyModel = preload("res://src/game/supply_region_model.gd")',
        'supply_region_definitions',
        'supply_region_cycles',
        'supply_regions_initialized',
        'apply_due_supply_restock',
        'supply_region_status_text',
        'supply_runtime_contract_ok',
        'Regional supply caught up',
    ],
)

presentation_base = read("src/presentation_runtime_base.gd")
require(
    "src/presentation_runtime_base.gd",
    presentation_base,
    [
        'extends "res://src/cinematic_runtime.gd"',
        'PlayerSettingsStore = preload("res://src/game/player_settings_store.gd")',
        'suppress_root_combat_hud',
        'presentation_overlay_handles_combat_readability',
        'root_presentation_suppression_contract_ok',
        'open_player_settings',
        'close_player_settings',
        'player_settings_contract_ok',
        'func draw_game() -> void:',
        'var preserved_banner := boss_banner',
        'boss_banner = ""',
        'boss_banner = preserved_banner',
        'func draw_hud(era_data: Dictionary) -> void:',
        'func equipped_ranged_weapon_data() -> Dictionary:',
        'func current_boss_index() -> int:',
        'func active_arena_context() -> Dictionary:',
        'func draw_projectiles() -> void:',
        'func draw_active_boss_arena() -> void:',
    ],
)

smoke = read("tools/smoke_runtime_scene_contract.gd")
require(
    "tools/smoke_runtime_scene_contract.gd",
    smoke,
    [
        'RuntimeSceneContract.validate_runtime_scene',
        'RuntimeSceneContract.runtime_scene_is_valid',
        'generator_players_ready',
        'generator_skip_count',
        'Selective combat HUD suppression must not alter gameplay capabilities',
        'Removing the overlay must restore root fallback ownership',
        'Reattaching the overlay must restore duplicate-render suppression',
    ],
)

primary_compile = read("tools/compile_probe.gd")
require(
    "tools/compile_probe.gd",
    primary_compile,
    [
        'res://src/game/runtime_scene_contract.gd',
        'res://src/presentation_runtime_base.gd',
        'res://src/presentation_runtime_current.gd',
        'res://src/content/supply_region_catalog.gd',
        'res://src/content/supply_region_validator.gd',
        'res://src/game/supply_region_model.gd',
        'res://src/combat_readability_overlay.gd',
        'res://addons/epochbound_sprite_animation_studio/plugin.gd',
        'res://tools/smoke_runtime_scene_contract.gd',
        'all seventeen editors',
    ],
)

focused_compile = read("tools/compile_sprite_animation_probe.gd")
require(
    "tools/compile_sprite_animation_probe.gd",
    focused_compile,
    [
        'res://src/game/runtime_scene_contract.gd',
        'res://tools/smoke_runtime_scene_contract.gd',
    ],
)

settings_compile = read("tools/compile_player_settings_probe.gd")
require(
    "tools/compile_player_settings_probe.gd",
    settings_compile,
    [
        'res://src/game/player_settings.gd',
        'res://src/game/player_settings_store.gd',
        'res://src/presentation_runtime_current.gd',
        'res://src/combat_readability_overlay.gd',
        'res://src/audio_mood_runtime.gd',
        'res://src/app.tscn',
    ],
)

local_gate = read("scripts/validate.ps1")
require(
    "scripts/validate.ps1",
    local_gate,
    [
        'Smoke test canonical runtime scene composition',
        'res://tools/smoke_runtime_scene_contract.gd',
        'compile_player_settings_probe.gd',
        'smoke_player_settings.gd',
        'canonical runtime',
    ],
)

primary_workflow = read(".github/workflows/validate.yml")
require(
    ".github/workflows/validate.yml",
    primary_workflow,
    [
        'python3 tools/check_runtime_scene_contract.py',
        'python3 tools/check_player_settings_contract.py',
        'scripts/validate.ps1',
        'Run complete seventeen-system validation gate',
    ],
)

for workflow_path in [
    ".github/workflows/audio-mood-validation.yml",
    ".github/workflows/sprite-animation-validation.yml",
]:
    workflow = read(workflow_path)
    require(
        workflow_path,
        workflow,
        [
            'python3 tools/check_runtime_scene_contract.py',
            'python3 tools/check_player_settings_contract.py',
            'smoke_runtime_scene_contract.gd',
            'smoke_player_settings.gd',
        ],
    )

release_policy = read("tools/check_release_workflow_policy.py")
require(
    "tools/check_release_workflow_policy.py",
    release_policy,
    [
        'python3 tools/check_runtime_scene_contract.py',
        'python3 tools/check_player_settings_contract.py',
        'smoke_runtime_scene_contract.gd',
        'smoke_player_settings.gd',
    ],
)

if errors:
    print("Epochbound runtime scene contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_runtime_scene_contract_passed")
print("- canonical root, overlay, camera and Audio scripts are pinned")
print("- durable regional supply cycles are layered above the canonical presentation runtime")
print("- duplicated Arsenal, Boss, projectile and arena drawing is selectively suppressed")
print("- inherited quest, companion, notice and system HUD paths remain available")
print("- player-local settings are required across runtime, presentation and Audio")
print("- primary unified and focused validation gates cover the executable composition")
