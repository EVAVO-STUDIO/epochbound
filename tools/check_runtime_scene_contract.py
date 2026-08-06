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


def forbid(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token in source:
            errors.append(f"{relative_path}: contains forbidden {token}")


scene = read("src/app.tscn")
require(
    "src/app.tscn",
    scene,
    [
        'res://src/presentation_runtime_current.gd',
        'res://src/combat_readability_overlay.gd',
        'res://src/player_controls_overlay.gd',
        'res://src/presentation_camera.gd',
        'res://src/audio_mood_runtime.gd',
        '[node name="PresentationLayer" type="CanvasLayer" parent="."]',
        '[node name="PresentationOverlay" type="Node2D" parent="PresentationLayer"]',
        '[node name="PlayerControlsOverlay" type="Node2D" parent="PresentationLayer"]',
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
        'CURRENT_CONTROLS_OVERLAY_SCRIPT := "res://src/player_controls_overlay.gd"',
        'CURRENT_AUDIO_SCRIPT := "res://src/audio_mood_runtime.gd"',
        'CURRENT_CAMERA_SCRIPT := "res://src/presentation_camera.gd"',
        '"start_conversation"',
        '"capture_save_profile"',
        '"open_merchant"',
        '"apply_due_supply_restock"',
        '"supply_runtime_contract_ok"',
        '"start_reload"',
        '"update_boss_engagements"',
        '"start_cinematic"',
        '"open_player_settings"',
        '"apply_input_bindings"',
        '"input_action_hint"',
        '"open_control_bindings"',
        '"input_binding_cache_contract_ok"',
        '"control_bindings_contract_ok"',
        '"player_settings_contract_ok"',
        '"player_settings_overlay_contract_ok"',
        '"player_settings_audio_contract_ok"',
        '"control_remapping_overlay_contract_ok"',
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
        'PlayerInputBindings = preload("res://src/game/player_input_bindings.gd")',
        'CompleteValidator = preload("res://src/content/complete_content_validator.gd")',
        'SupplyCatalog = preload("res://src/content/supply_region_catalog.gd")',
        'SupplyModel = preload("res://src/game/supply_region_model.gd")',
        'control_bindings_open',
        'control_capture_event_consumed',
        'input_binding_profile_cache',
        'input_action_hint_cache',
        'input_device_hint_cache',
        'control_binding_row_cache',
        'input_binding_cache_revision',
        'apply_input_bindings',
        'rebuild_input_binding_cache',
        'open_control_bindings',
        'handle_control_capture_event',
        'reset_control_bindings',
        'input_action_hint',
        'input_binding_cache_contract_ok',
        'control_bindings_contract_ok',
        'supply_region_definitions',
        'supply_region_cycles',
        'supply_regions_initialized',
        'apply_due_supply_restock',
        'supply_runtime_contract_ok',
        'CompleteValidator.validate_profile',
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

controls_overlay = read("src/player_controls_overlay.gd")
require(
    "src/player_controls_overlay.gd",
    controls_overlay,
    [
        'extends Node2D',
        'PresentationOverlay',
        'CONTROL_PANEL',
        'runtime_action_hint',
        'draw_dynamic_context_prompt',
        'draw_dynamic_reload_hint',
        'draw_control_settings_panel',
        'control_remapping_overlay_contract_ok',
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

control_smoke = read("tools/smoke_input_bindings.gd")
require(
    "tools/smoke_input_bindings.gd",
    control_smoke,
    [
        'input_binding_cache_contract_ok',
        'Repeated draw-time hint and row reads must not rebuild the binding profile cache',
        'A successful capture must rebuild the binding caches exactly when the profile changes',
    ],
)

primary_compile = read("tools/compile_probe.gd")
require(
    "tools/compile_probe.gd",
    primary_compile,
    [
        'res://src/game/runtime_scene_contract.gd',
        'res://src/presentation_runtime_current.gd',
        'res://src/combat_readability_overlay.gd',
        'res://addons/epochbound_editor_common/editor_plugin_icon.gd',
        'res://addons/epochbound_sprite_animation_studio/plugin.gd',
        'res://tools/smoke_editor_plugin_icons.gd',
        'res://tools/smoke_runtime_scene_contract.gd',
        'all seventeen editors',
    ],
)

supply_compile = read("tools/compile_supply_region_probe.gd")
require(
    "tools/compile_supply_region_probe.gd",
    supply_compile,
    [
        'res://src/presentation_runtime_base.gd',
        'res://src/presentation_runtime_current.gd',
        'res://src/content/supply_region_catalog.gd',
        'res://src/content/supply_region_validator.gd',
        'res://src/content/complete_content_validator.gd',
        'res://src/game/supply_region_model.gd',
        'res://tools/smoke_runtime_scene_contract.gd',
        'res://tools/smoke_supply_regions.gd',
        'res://src/app.tscn',
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
        'res://src/game/player_input_bindings.gd',
        'res://src/game/player_settings.gd',
        'res://src/game/player_settings_store.gd',
        'res://src/presentation_runtime_base.gd',
        'res://src/presentation_runtime_current.gd',
        'res://src/combat_readability_overlay.gd',
        'res://src/player_controls_overlay.gd',
        'res://src/audio_mood_runtime.gd',
        'res://tools/smoke_input_bindings.gd',
        'res://src/app.tscn',
    ],
)

local_gate = read("scripts/validate.ps1")
require(
    "scripts/validate.ps1",
    local_gate,
    [
        'Smoke test warning-safe editor plugin icon resolution',
        'res://tools/smoke_editor_plugin_icons.gd',
        'Trying to access a non-existing editor theme icon',
        'Smoke test canonical runtime scene composition',
        'res://tools/smoke_runtime_scene_contract.gd',
        'compile_player_settings_probe.gd',
        'compile_supply_region_probe.gd',
        'smoke_player_settings.gd',
        'smoke_input_bindings.gd',
        'smoke_supply_regions.gd',
        'persistent controls',
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
        'python3 tools/check_supply_region_contract.py',
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
            'python3 tools/check_supply_region_contract.py',
            'smoke_runtime_scene_contract.gd',
            'smoke_player_settings.gd',
            'smoke_input_bindings.gd',
            'smoke_supply_regions.gd',
        ],
    )

release_policy = read("tools/check_release_workflow_policy.py")
require(
    "tools/check_release_workflow_policy.py",
    release_policy,
    [
        'python3 tools/check_runtime_scene_contract.py',
        'python3 tools/check_player_settings_contract.py',
        'python3 tools/check_supply_region_contract.py',
        'smoke_runtime_scene_contract.gd',
        'smoke_player_settings.gd',
        'smoke_input_bindings.gd',
        'smoke_supply_regions.gd',
    ],
)

icon_resolver = read("addons/epochbound_editor_common/editor_plugin_icon.gd")
require(
    "addons/epochbound_editor_common/editor_plugin_icon.gd",
    icon_resolver,
    [
        '@tool',
        'extends RefCounted',
        'EDITOR_ICON_THEME_TYPE := "EditorIcons"',
        'FALLBACK_ICON := "Node"',
        'resolve(editor_interface: EditorInterface, candidates: Array)',
        'resolve_from_theme(theme: Theme, candidates: Array)',
        'theme.has_icon(candidate, EDITOR_ICON_THEME_TYPE)',
        'theme.has_icon(FALLBACK_ICON, EDITOR_ICON_THEME_TYPE)',
    ],
)

icon_smoke = read("tools/smoke_editor_plugin_icons.gd")
require(
    "tools/smoke_editor_plugin_icons.gd",
    icon_smoke,
    [
        'EditorPluginIcon.resolve_from_theme',
        'theme.set_icon("SemanticIcon"',
        'The resolver must select the first available semantic candidate',
        'An empty candidate list must still resolve the stable editor fallback',
        'A missing editor theme must fail quietly',
    ],
)

project = read("project.godot")
plugin_paths = sorted((ROOT / "addons").glob("epochbound_*/plugin.gd"))
if len(plugin_paths) != 17:
    errors.append(f"addons: expected 17 editor plugins, found {len(plugin_paths)}")
for plugin_path in plugin_paths:
    relative_path = plugin_path.relative_to(ROOT).as_posix()
    plugin_source = plugin_path.read_text(encoding="utf-8")
    require(
        relative_path,
        plugin_source,
        [
            'extends EditorPlugin',
            'const EditorPluginIcon = preload("res://addons/epochbound_editor_common/editor_plugin_icon.gd")',
            'const ICON_CANDIDATES := [',
            'return EditorPluginIcon.resolve(get_editor_interface(), ICON_CANDIDATES)',
            'studio = null',
        ],
    )
    forbid(
        relative_path,
        plugin_source,
        [
            '.get_icon(',
            '.get_theme_icon(',
        ],
    )
    plugin_config = relative_path.removesuffix("plugin.gd") + "plugin.cfg"
    if f'"res://{plugin_config}"' not in project:
        errors.append(f"project.godot: editor plugin is not enabled: {plugin_config}")

if errors:
    print("Epochbound runtime scene contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_runtime_scene_contract_passed")
print("- canonical root, combat overlay, control overlay, camera and Audio scripts are pinned")
print("- persistent InputMap bindings, bounded prompt caches and durable regional supply cycles layer above the canonical presentation runtime")
print("- duplicated Arsenal, Boss, projectile and arena drawing is selectively suppressed")
print("- inherited quest, companion, notice and system HUD paths remain available")
print("- player-local settings, controls and Audio remain outside campaign saves and packages")
print("- all seventeen editor plugins resolve semantic icons through a warning-safe shared fallback contract")
print("- primary unified and focused validation gates cover the executable composition")
