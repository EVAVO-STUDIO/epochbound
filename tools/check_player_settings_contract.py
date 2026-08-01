#!/usr/bin/env python3
"""Fail closed when Epochbound's player-local settings integration drifts."""

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


model = read("src/game/player_settings.gd")
require(
    "src/game/player_settings.gd",
    model,
    [
        "CURRENT_SCHEMA := 1",
        '"master_volume"',
        '"music_volume"',
        '"ambience_volume"',
        '"sfx_volume"',
        '"screen_texture_intensity"',
        '"camera_shake_intensity"',
        '"environment_motion_intensity"',
        '"flash_intensity"',
        '"show_action_prompts"',
        '"high_contrast_ui"',
        "default_settings",
        "sanitize",
        "validate",
        "migrate",
        "adjusted",
        "value_text",
    ],
)

store = read("src/game/player_settings_store.gd")
require(
    "src/game/player_settings_store.gd",
    store,
    [
        'ROOT := "user://settings"',
        'SETTINGS_FILENAME := "player_settings.json"',
        "root_path: String = ROOT",
        "TEMP_SUFFIX",
        "BACKUP_SUFFIX",
        "load_settings",
        "write_settings",
        "rewrite_loaded_settings",
        "recovered_from_backup",
        "rotate the previous player settings into a backup",
        "promote the temporary player settings file",
    ],
)

runtime = read("src/presentation_runtime_current.gd")
require(
    "src/presentation_runtime_current.gd",
    runtime,
    [
        'extends "res://src/cinematic_runtime.gd"',
        'PlayerSettingsStore = preload("res://src/game/player_settings_store.gd")',
        '"OPTIONS"',
        "load_player_settings",
        "open_player_settings",
        "close_player_settings",
        "update_player_settings_menu",
        "player_setting_number",
        "player_setting_bool",
        "player_settings_rows",
        "player_settings_snapshot",
        "player_settings_contract_ok",
        "not player_settings_open and super.can_open_save_overlay()",
        "not player_settings_open and super.can_flush_autosave()",
    ],
)
forbid(
    "src/presentation_runtime_current.gd",
    runtime,
    [
        'payload["player_settings"]',
        'campaign["player_settings"]',
    ],
)

overlay = read("src/combat_readability_overlay.gd")
require(
    "src/combat_readability_overlay.gd",
    overlay,
    [
        "player_settings_is_open",
        "player_setting_number",
        "player_setting_bool",
        "environment_motion_intensity",
        "camera_shake_intensity",
        "screen_texture_intensity",
        "flash_intensity",
        "show_action_prompts",
        "high_contrast_ui",
        "draw_player_settings_panel",
        "player_settings_overlay_contract_ok",
    ],
)

audio = read("src/audio_mood_runtime.gd")
require(
    "src/audio_mood_runtime.gd",
    audio,
    [
        "apply_player_volume_settings",
        "player_volume_snapshot",
        "player_settings_audio_contract_ok",
        'player_setting_number("master_volume"',
        'player_setting_number("music_volume"',
        'player_setting_number("ambience_volume"',
        'player_setting_number("sfx_volume"',
        'runtime_boolean("player_settings_open")',
        "PLAYER_VOLUME_FLOOR_DB",
    ],
)

project = read("project.godot")
require(
    "project.godot",
    project,
    [
        "options_menu={",
        'physical_keycode":79',
    ],
)

probe = read("tools/compile_player_settings_probe.gd")
require(
    "tools/compile_player_settings_probe.gd",
    probe,
    [
        "player_settings.gd",
        "player_settings_store.gd",
        "presentation_runtime_current.gd",
        "combat_readability_overlay.gd",
        "audio_mood_runtime.gd",
        "smoke_player_settings.gd",
        "app.tscn",
    ],
)

smoke = read("tools/smoke_player_settings.gd")
require(
    "tools/smoke_player_settings.gd",
    smoke,
    [
        'TEST_ROOT := "user://epochbound_test_player_settings"',
        "Schema-zero player settings must migrate",
        "A valid backup must be identified as the recovery source",
        "Music gain must combine master and music settings",
        "Manual saving must remain blocked while Options is open",
        "Options must freeze animation and environment time",
        "Reset Defaults must restore master volume",
    ],
)

runtime_contract = read("src/game/runtime_scene_contract.gd")
require(
    "src/game/runtime_scene_contract.gd",
    runtime_contract,
    [
        '"player_settings_contract_ok"',
        '"player_settings_overlay_contract_ok"',
        '"player_settings_audio_contract_ok"',
    ],
)

local_gate = read("scripts/validate.ps1")
require(
    "scripts/validate.ps1",
    local_gate,
    [
        "compile_player_settings_probe.gd",
        "smoke_player_settings.gd",
        "player settings",
    ],
)

primary_workflow_path = ".github/workflows/validate.yml"
primary_workflow = read(primary_workflow_path)
require(
    primary_workflow_path,
    primary_workflow,
    [
        "python3 tools/check_player_settings_contract.py",
        "scripts/validate.ps1",
        "Run complete seventeen-system validation gate",
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
            "python3 tools/check_player_settings_contract.py",
            "compile_player_settings_probe.gd",
            "smoke_player_settings.gd",
        ],
    )

release_policy = read("tools/check_release_workflow_policy.py")
require(
    "tools/check_release_workflow_policy.py",
    release_policy,
    [
        "python3 tools/check_player_settings_contract.py",
        "compile_player_settings_probe.gd",
        "smoke_player_settings.gd",
    ],
)

documentation = read("docs/PLAYER_SETTINGS.md")
require(
    "docs/PLAYER_SETTINGS.md",
    documentation,
    [
        "user://settings/player_settings.json",
        "Atomic persistence",
        "Campaign saves remain separate",
        "Action Prompts",
        "High Contrast UI",
    ],
)

if errors:
    print("Epochbound player settings contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_player_settings_contract_passed")
print("- player-local settings are versioned, sanitised and stored atomically")
print("- Options controls Audio, presentation intensity, prompts and contrast")
print("- campaign saves and portable campaign packages remain separate")
print("- primary unified, Audio, Sprite and local gates cover the complete integration")
