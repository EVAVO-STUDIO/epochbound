#!/usr/bin/env python3
"""Fail closed when Epochbound's player-local settings and controls integration drifts."""

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
    earlier_index = source.find(earlier)
    later_index = source.find(later)
    if earlier_index < 0:
        errors.append(f"{relative_path}: missing ordered token {earlier}")
    elif later_index < 0:
        errors.append(f"{relative_path}: missing ordered token {later}")
    elif earlier_index >= later_index:
        errors.append(f"{relative_path}: expected {earlier} before {later}")


bindings = read("src/game/player_input_bindings.gd")
require(
    "src/game/player_input_bindings.gd",
    bindings,
    [
        "PROFILE_SCHEMA := 1",
        'DEVICE_KEYBOARD := "keyboard"',
        'DEVICE_GAMEPAD := "gamepad"',
        "RESERVED_ESCAPE_PHYSICAL",
        "RESERVED_OPTIONS_PHYSICAL",
        "RESERVED_START_BUTTON",
        "CAPTURE_AXIS_THRESHOLD",
        "action_definitions",
        '"move_up"',
        '"interact"',
        '"attack"',
        '"reload_weapon"',
        "default_profile",
        "sanitize_profile",
        "validate_profile",
        "validate_descriptor",
        "descriptor_has_modifiers",
        "event_uses_modifiers",
        "modifier_chord_message",
        "non-exact InputMap matching",
        "descriptor_from_event",
        "event_from_descriptor",
        "apply_profile",
        "input_map_matches",
        "rebind",
        "swapped_with",
        "action_hint_from_events",
        "device_binding_text_from_events",
        "descriptor_is_reserved",
        "reserved_descriptor_message",
    ],
)
require_order(
    "src/game/player_input_bindings.gd",
    bindings,
    "static func apply_profile(value: Variant) -> Dictionary:\n\tvar validation := validate_profile(value)",
    "\tvar profile := sanitize_profile(value)",
)
forbid(
    "src/game/player_input_bindings.gd",
    bindings,
    ['"options_menu",', '"pause_game",', "Time.get_unix_time", "OS.get_unix_time"],
)

model = read("src/game/player_settings.gd")
require(
    "src/game/player_settings.gd",
    model,
    [
        "CURRENT_SCHEMA := 3",
        'PlayerInputBindings = preload("res://src/game/player_input_bindings.gd")',
        'LocalisationCatalog = preload("res://src/content/localisation_catalog.gd")',
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
        '"language"',
        '"kind": "choice"',
        'LocalisationCatalog.supported_player_locales()',
        'static func string(',
        '"input_bindings"',
        '"controls"',
        '"reset_defaults"',
        '"back"',
        "default_settings",
        "sanitize",
        "validate",
        "migrate",
        "number_step",
        "settings.get(setting_id, 1.0)",
        "settings.get(setting_id, default_value)",
        "input_bindings",
        "PlayerInputBindings.sanitize_profile",
        "adjusted",
        "value_text",
        "lookup never rebuilds fourteen actions",
    ],
)
forbid(
    "src/game/player_settings.gd",
    model,
    ["sanitize(settings).get", "var sanitized := sanitize(settings)", "var value: Variant = sanitize(settings)"],
)

store = read("src/game/player_settings_store.gd")
require(
    "src/game/player_settings_store.gd",
    store,
    [
        'ROOT := "user://settings"',
        'SETTINGS_FILENAME := "player_settings.json"',
        "TEMP_SUFFIX",
        "BACKUP_SUFFIX",
        "load_settings",
        "validate_raw_input_bindings",
        'PlayerInputBindings.validate_profile(settings.get("input_bindings"))',
        "fail closed before sanitization",
        "write_settings",
        "rewrite_loaded_settings",
        "recovered_from_backup",
        "rotate the previous player settings into a backup",
        "promote the temporary player settings file",
    ],
)
require_order(
    "src/game/player_settings_store.gd",
    store,
    "var binding_validation := validate_raw_input_bindings(settings, final_path)",
    "var sanitized := PlayerSettings.sanitize(settings)",
)
require_order(
    "src/game/player_settings_store.gd",
    store,
    "var binding_validation := validate_raw_input_bindings(settings, final_path)",
    "var file := FileAccess.open(temporary_path, FileAccess.WRITE)",
)

base_runtime = read("src/presentation_runtime_base.gd")
require(
    "src/presentation_runtime_base.gd",
    base_runtime,
    [
        'PlayerSettingsStore = preload("res://src/game/player_settings_store.gd")',
        "load_player_settings",
        "apply_player_settings_load_result",
        "player_settings_open_notice",
        'set_localisation_locale(PlayerSettings.string(player_settings, "language", "en"))',
        "player_setting_string",
        "player_setting_label",
        "player_setting_value_text",
        "open_player_settings",
        "close_player_settings",
        "player_settings_dirty = recovered or migrated",
        '"RECOVERED SETTINGS FROM BACKUP"',
        '"SETTINGS UPDATED TO CURRENT VERSION"',
        "not player_settings_open and super.can_open_save_overlay()",
        "not player_settings_open and super.can_flush_autosave()",
    ],
)

runtime = read("src/presentation_runtime_current.gd")
require(
    "src/presentation_runtime_current.gd",
    runtime,
    [
        'extends "res://src/presentation_runtime_base.gd"',
        'PlayerInputBindings = preload("res://src/game/player_input_bindings.gd")',
        "localised_control_action_label",
        "control_bindings_open",
        "control_binding_device",
        "control_capture_active",
        "control_capture_event_consumed",
        "input_binding_profile_cache",
        "input_action_hint_cache",
        "input_device_hint_cache",
        "control_binding_row_cache",
        "input_binding_cache_revision",
        "apply_input_bindings",
        "rebuild_input_binding_cache",
        "action_hint_from_events",
        "device_binding_text_from_events",
        "cached_control_binding_rows",
        "open_control_bindings",
        "close_control_bindings",
        "update_control_bindings_menu",
        "control_binding_rows",
        "begin_control_capture",
        "handle_control_capture_event",
        "reset_control_bindings",
        "input_action_hint",
        "input_action_device_hint",
        "input_binding_cache_contract_ok",
        "control_bindings_contract_ok",
        "PlayerInputBindings.input_map_matches",
        "player_settings_contract_ok",
        "localisation_changed",
        "localised_control_action_label",
    ],
)
forbid(
    "src/presentation_runtime_current.gd",
    runtime,
    [
        'payload["player_settings"]',
        'payload["input_bindings"]',
        'campaign["player_settings"]',
        'campaign["input_bindings"]',
    ],
)

controls_overlay = read("src/player_controls_overlay.gd")
require(
    "src/player_controls_overlay.gd",
    controls_overlay,
    [
        "PresentationOverlay",
        "runtime_action_hint",
        "draw_control_settings_panel",
        "draw_dynamic_context_prompt",
        "draw_dynamic_reload_hint",
        "control_remapping_overlay_contract_ok",
        'runtime_action_hint("interact"',
        'runtime_action_hint("reload_weapon"',
    ],
)

combat_overlay = read("src/combat_readability_overlay.gd")
require(
    "src/combat_readability_overlay.gd",
    combat_overlay,
    [
        "player_settings_is_open",
        "player_setting_number",
        "player_setting_bool",
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
        "pause_game={",
        'physical_keycode":4194305',
        'button_index":6',
    ],
)

scene = read("src/app.tscn")
require(
    "src/app.tscn",
    scene,
    [
        'res://src/combat_readability_overlay.gd',
        'res://src/player_controls_overlay.gd',
        '[node name="PlayerControlsOverlay" type="Node2D" parent="PresentationLayer"]',
    ],
)

probe = read("tools/compile_player_settings_probe.gd")
require(
    "tools/compile_player_settings_probe.gd",
    probe,
    [
        "player_input_bindings.gd",
        "player_settings.gd",
        "player_settings_store.gd",
        "presentation_runtime_current.gd",
        "combat_readability_overlay.gd",
        "player_controls_overlay.gd",
        "audio_mood_runtime.gd",
        "smoke_player_settings.gd",
        "smoke_player_settings_recovery_edges.gd",
        "smoke_input_bindings.gd",
        "app.tscn",
    ],
)

settings_smoke = read("tools/smoke_player_settings.gd")
require(
    "tools/smoke_player_settings.gd",
    settings_smoke,
    [
        'TEST_ROOT := "user://epochbound_test_player_settings"',
        "Schema-one player settings must migrate to persistent controls",
        "Migration must add the safe English locale",
        "Language must cycle through the Options surface",
        "Language adjustment must apply pseudo-localisation immediately",
        "Reset All Defaults must restore the safe English locale",
        "Default player settings must include a complete keyboard and controller binding profile",
        "Runtime must keep InputMap synchronized",
        "Music gain must combine master and music settings",
        "Reset All Defaults must also restore and apply default controls",
        "Options must freeze animation and environment time",
        "Options rows must refresh immediately in pseudo-localisation",
    ],
)
forbid(
    "tools/smoke_player_settings.gd",
    settings_smoke,
    [
        'audio.call("apply_player_volume_settings", runtime)',
        'volume.get("music_linear"',
        'volume.get("ambience_linear"',
        'volume.get("sfx_linear"',
    ],
)

control_smoke = read("tools/smoke_input_bindings.gd")
require(
    "tools/smoke_input_bindings.gd",
    control_smoke,
    [
        'TEST_ROOT := "user://epochbound_test_input_bindings"',
        "all fourteen gameplay actions",
        "Options must expose ten existing preferences, Language, Controls, Reset All Defaults and Back",
        "Keyboard capture must detect modifier chords before InputMap matching",
        "Invalid modifier profiles must fail before InputMap mutation",
        "Small analogue noise must not become a binding",
        "Binding a used key must swap",
        "Custom controls must write through the existing atomic player-settings store",
        "Atomic settings writes must reject malformed controls before rotating the valid primary file",
        "Rejected control writes must leave the valid primary settings file in place",
        "Rejected control writes must not rotate the valid primary settings file into a backup",
        "Rejected control writes must not leave a temporary settings file",
        "A rejected control write must continue loading directly from the unchanged primary file",
        "Runtime must build complete validated binding, row and prompt caches",
        "Repeated draw-time hint and row reads must not rebuild the binding profile cache",
        "Runtime hints must update immediately after rebinding",
        "A successful capture must rebuild the binding caches exactly when the profile changes",
        "Modifier chords must be consumed rather than leaking into a non-exact gameplay action",
        "Rejected modifier chords must not mutate or rebuild the active binding caches",
        "Reserved recovery inputs must be consumed",
        "Rejected reserved input must not rebuild or mutate the active binding caches",
        "Reset Controls must restore",
        "Reset Controls must invalidate and rebuild every cached hint and row",
    ],
)

recovery_smoke = read("tools/smoke_player_settings_recovery_edges.gd")
require(
    "tools/smoke_player_settings_recovery_edges.gd",
    recovery_smoke,
    [
        'TEST_ROOT := "user://epochbound_test_player_settings_recovery"',
        "Runtime Options must preserve supported migration status",
        "Recovered runtime settings must remain pending for atomic primary repair",
        'runtime.call("close_player_settings", TEST_ROOT)',
    ],
)

runtime_contract = read("src/game/runtime_scene_contract.gd")
require(
    "src/game/runtime_scene_contract.gd",
    runtime_contract,
    [
        '"input_binding_cache_contract_ok"',
        '"control_bindings_contract_ok"',
        '"control_remapping_overlay_contract_ok"',
        '"player_settings_contract_ok"',
        '"player_settings_overlay_contract_ok"',
        '"player_settings_audio_contract_ok"',
        '"localisation_contract_ok"',
        "Runtime root did not build complete stable input-binding caches",
    ],
)

local_gate = read("scripts/validate.ps1")
require(
    "scripts/validate.ps1",
    local_gate,
    [
        "compile_player_settings_probe.gd",
        "compile_localisation_probe.gd",
        "smoke_localisation.gd",
        "smoke_player_settings.gd",
        "smoke_player_settings_recovery_edges.gd",
        "smoke_input_bindings.gd",
        "persistent keyboard and controller remapping",
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
            "python3 tools/check_player_settings_contract.py",
            "python3 tools/check_localisation_contract.py",
            "compile_player_settings_probe.gd" if workflow_path != ".github/workflows/validate.yml" else "scripts/validate.ps1",
        ],
    )
if "smoke_input_bindings.gd" not in read(".github/workflows/audio-mood-validation.yml"):
    errors.append(".github/workflows/audio-mood-validation.yml: missing smoke_input_bindings.gd")
if "smoke_input_bindings.gd" not in read(".github/workflows/sprite-animation-validation.yml"):
    errors.append(".github/workflows/sprite-animation-validation.yml: missing smoke_input_bindings.gd")

release_policy = read("tools/check_release_workflow_policy.py")
require(
    "tools/check_release_workflow_policy.py",
    release_policy,
    [
        "python3 tools/check_player_settings_contract.py",
        "compile_player_settings_probe.gd",
        "compile_localisation_probe.gd",
        "smoke_localisation.gd",
        "smoke_player_settings.gd",
        "smoke_input_bindings.gd",
        "modifier_chord_message",
        "validate_raw_input_bindings",
        "Rejected control writes must leave the valid primary settings file in place",
    ],
)

documentation = read("docs/PLAYER_SETTINGS.md")
require(
    "docs/PLAYER_SETTINGS.md",
    documentation,
    [
        "user://settings/player_settings.json",
        "schema 3",
        "Language",
        "Pseudo-localisation",
        "Keyboard and controller remapping",
        "Physical keys, not modifier chords",
        "Escape, O and Start",
        "Conflict-safe swapping",
        "Dynamic prompts and bounded caches",
        "cache revision",
        "draw-time hint reads",
        "Validate the raw nested binding profile before sanitization",
        "A malformed control profile exits before any file mutation",
        "clean primary load, rather than backup recovery, after a rejected write",
        "Campaign saves remain separate",
        "Startup itself remains read-only",
        "InputMap",
    ],
)

readme = read("README.md")
require(
    "README.md",
    readme,
    [
        "persistent keyboard and controller remapping",
        "Player settings, accessibility and controls",
        "Language",
        "Pseudo-localisation",
        "Options → Controls",
        "Field Satchel | I | Back or View",
        "Fixed recovery controls before unrestricted remapping",
    ],
)
forbid("README.md", readme, ["controller remapping, automated long-form"])

if errors:
    print("Epochbound player settings and controls contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_player_settings_contract_passed")
print("- player-local schema-three settings and control bindings are versioned sanitised and stored atomically")
print("- raw control profiles fail before sanitization, temporary-file creation or backup rotation")
print("- scalar Audio and presentation reads never traverse the nested control profile")
print("- Escape, O and Start remain fixed recovery inputs while fourteen gameplay actions are remappable")
print("- modifier chords are rejected because gameplay uses non-exact action matching")
print("- duplicate captures swap bindings instead of creating inaccessible or ambiguous actions")
print("- validated control rows and prompt labels are cached only at profile mutation boundaries")
print("- runtime InputMap, dynamic prompts, Audio and presentation all consume the same profile")
print("- language controls campaign saves and portable campaign packages remain separate")
print("- primary unified, Audio, Sprite and local gates cover the complete integration")
