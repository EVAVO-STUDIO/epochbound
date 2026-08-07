#!/usr/bin/env python3
"""Fail closed when Epochbound GitHub Actions release policy drifts."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = {
    "validate": ROOT / ".github/workflows/validate.yml",
    "linux_agent": ROOT / ".github/workflows/godot-linux-agent-qa.yml",
    "audio_mood": ROOT / ".github/workflows/audio-mood-validation.yml",
    "sprite_animation": ROOT / ".github/workflows/sprite-animation-validation.yml",
}
errors: list[str] = []


def read(name: str, path: Path) -> str:
    if not path.is_file():
        errors.append(f"{name}: required file is missing: {path.relative_to(ROOT)}")
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


def require_order(name: str, source: str, earlier: str, later: str) -> None:
    earlier_index = source.find(earlier)
    later_index = source.find(later)
    if earlier_index < 0:
        errors.append(f"{name}: missing ordered token {earlier}")
    elif later_index < 0:
        errors.append(f"{name}: missing ordered token {later}")
    elif earlier_index >= later_index:
        errors.append(f"{name}: expected {earlier} before {later}")


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
    allowed_events = {"push", "workflow_dispatch"} if name == "validate" else {"workflow_dispatch"}
    if workflow_events != allowed_events:
        errors.append(f"{name}: expected events {sorted(allowed_events)}, found {sorted(workflow_events)}")
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
        "push:\n    branches:\n      - main",
        "actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955",
        "persist-credentials: false",
        "ref: ${{ github.sha }}",
        "EVENT_NAME: ${{ github.event_name }}",
        'if [[ "${EVENT_NAME}" == "workflow_dispatch" ]]; then',
        'elif [[ "${EVENT_NAME}" == "push" ]]; then',
        '[[ "${EXPECTED_SHA}" == "${GITHUB_SHA}" ]]',
        "SHA512-SUMS.txt",
        "sha512sum --check",
        "python3 tools/check_release_workflow_policy.py",
        "python3 tools/check_temporal_shift_contract.py",
        "python3 tools/check_combat_fairness_contract.py",
        "python3 tools/check_runtime_scene_contract.py",
        "python3 tools/check_player_settings_contract.py",
        "python3 tools/check_supply_region_contract.py",
        "python3 tools/check_canonical_journey_contract.py",
        "python3 tools/check_multiplayer_contract.py",
        "python3 tools/check_multiplayer_connection_contract.py",
        "scripts/validate.ps1",
        "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
        '"schemaVersion": "2.3"',
        '"referenceContentWarnings": 0',
        '"referenceAuditWarnings": 0',
        '"referenceReleaseReadinessValidation": "passed"',
        '"headlessCleanupValidation": "passed"',
        '"temporalShiftValidation": "passed"',
        '"combatFairnessValidation": "passed"',
        '"supplyRegionValidation": "passed"',
        '"canonicalJourneyValidation": "passed"',
        '"multiplayerValidation": "passed"',
        '"multiplayerConnectionValidation": "passed"',
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

require(
    "audio_mood",
    sources["audio_mood"],
    [
        "actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955",
        "persist-credentials: false",
        "ref: ${{ inputs.expected_sha }}",
        "SHA512-SUMS.txt",
        "sha512sum --check",
        "python3 tools/check_release_workflow_policy.py",
        "python3 tools/check_runtime_scene_contract.py",
        "python3 tools/check_player_settings_contract.py",
        "python3 tools/check_supply_region_contract.py",
        "compile_player_settings_probe.gd",
        "compile_supply_region_probe.gd",
        "smoke_runtime_scene_contract.gd",
        "smoke_player_settings.gd",
        "smoke_input_bindings.gd",
        "smoke_supply_regions.gd",
        "smoke_supply_validation_edges.gd",
        "smoke_audio_mood_runtime.gd",
        "smoke_audio_mood_studio.gd",
        "smoke_audio_mood_validation_edges.gd",
        "smoke_audio_campaign_scaffold.gd",
        "smoke_package_current_validation.gd",
        "git merge-base --is-ancestor",
        "git diff --exit-code",
    ],
)

require(
    "sprite_animation",
    sources["sprite_animation"],
    [
        "actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955",
        "persist-credentials: false",
        "ref: ${{ inputs.expected_sha }}",
        "SHA512-SUMS.txt",
        "sha512sum --check",
        "python3 tools/check_release_workflow_policy.py",
        "python3 tools/check_runtime_scene_contract.py",
        "python3 tools/check_player_settings_contract.py",
        "python3 tools/check_supply_region_contract.py",
        "python3 tools/check_sprite_animation_contract.py",
        "compile_sprite_animation_probe.gd",
        "compile_player_settings_probe.gd",
        "compile_supply_region_probe.gd",
        "smoke_runtime_scene_contract.gd",
        "smoke_player_settings.gd",
        "smoke_input_bindings.gd",
        "smoke_supply_regions.gd",
        "smoke_supply_validation_edges.gd",
        "smoke_sprite_animation_runtime.gd",
        "smoke_environment_animation.gd",
        "smoke_combat_readability_overlay.gd",
        "smoke_sprite_animation_studio.gd",
        "smoke_sprite_animation_validation_edges.gd",
        "smoke_sprite_campaign_scaffold.gd",
        "smoke_sprite_package_validation.gd",
        "git merge-base --is-ancestor",
        "git diff --exit-code",
    ],
)

local_gate = read("local_gate", ROOT / "scripts/validate.ps1")
require(
    "local_gate",
    local_gate,
    [
        "compile_player_settings_probe.gd",
        "compile_supply_region_probe.gd",
        "compile_multiplayer_probe.gd",
        "smoke_player_settings.gd",
        "smoke_player_settings_recovery_edges.gd",
        "smoke_input_bindings.gd",
        "Smoke test warning-safe editor plugin icon resolution",
        "smoke_editor_plugin_icons.gd",
        "Trying to access a non-existing editor theme icon",
        "ObjectDB instances leaked at exit",
        "leak-free headless shutdown",
        "Smoke test persistent keyboard and controller remapping",
        "smoke_supply_regions.gd",
        "smoke_supply_validation_edges.gd",
        "smoke_progression_affordability.gd",
        "Smoke test multi-source progression affordability planning",
        "Smoke test warning-free reference campaign release readiness",
        "smoke_campaign_audit.gd",
        "smoke_temporal_shift_audit.gd",
        "meaningful temporal shifts",
        "Smoke test Combat Director target locking and stagger interrupts",
        "smoke_combat_director.gd",
        "locked combat telegraphs",
        "stagger interrupts",
        "smoke_multiplayer_session_model.gd",
        "smoke_multiplayer_connection_profile.gd",
        "Smoke test player-local multiplayer connection setup and recovery",
        "smoke_multiplayer_runtime.gd",
        "smoke_multiplayer_validation_edges.gd",
        "host-authoritative co-op",
        "authored PvP invasions",
        "smoke_canonical_journey.gd",
    ],
)



headless_cleanup = read("headless_cleanup", ROOT / "tools/headless_runtime_cleanup.gd")
require(
    "headless_cleanup",
    headless_cleanup,
    [
        'AUDIO_SETTLE_FRAMES := 30',
        'AUDIO_SETTLE_SECONDS := 0.25',
        'player.stream = null',
        'await tree.create_timer(AUDIO_SETTLE_SECONDS).timeout',
    ],
)
forbid(
    "headless_cleanup",
    headless_cleanup,
    [
        'clear_buffer()',
        'OS.delay',
    ],
)

reference_gate = read("reference_gate", ROOT / "tools/smoke_campaign_audit.gd")
require(
    "reference_gate",
    reference_gate,
    [
        "CompleteValidator.validate_campaign_path",
        "Reference content validation must remain warning-free",
        "Reference campaign audit must remain warning-free",
        'metrics.get("optional_capability_count", 0)',
        'metrics.get("progression_source_risk_count", -1)) == 0',
        'metrics.get("multi_era_map_count", 0)',
        'metrics.get("meaningful_shift_map_count", 0)',
        "all nine production probes",
        "zero blockers, errors or warnings",
    ],
)

item_validator = read("item_validator", ROOT / "src/content/item_validator.gd")
require(
    "item_validator",
    item_validator,
    [
        "collect_authored_item_and_recipe_uses",
        "collect_declared_file_uses",
        '["story_files", "economy_files", "cinematic_files"]',
        '"item_id", "ammo_item_id"',
        '"unlock_recipes", "starting_recipes"',
        '"starting_equipment"',
    ],
)

cinematic_validator = read("cinematic_validator", ROOT / "src/content/cinematic_validator.gd")
require(
    "cinematic_validator",
    cinematic_validator,
    [
        'BossCatalog = preload("res://src/content/boss_catalog.gd")',
        "validate_boss_cinematic_triggers",
        'campaign.get("boss_cinematics", {})',
        "BossCatalog.is_boss",
        '"intro_cinematic_id", "defeat_cinematic_id"',
    ],
)
forbid(
    "cinematic_validator",
    cinematic_validator,
    [
        "ObjectCatalog.load_catalogs(str(catalog_result.get",
        "if false else {}",
    ],
)

campaign_audit = read("campaign_audit", ROOT / "src/content/campaign_audit.gd")
require(
    "campaign_audit",
    campaign_audit,
    [
        '"optional_capability_count": 0',
        "collect_map_capability_requirements",
        'interaction.get("progression_required", false)',
        'progression_map.erase("interactions")',
        'TemporalShiftAudit = preload("res://src/content/temporal_shift_audit.gd")',
        "PROBE_COUNT := 9",
        'TemporalShiftAudit.audit(maps, objects, findings)',
    ],
)

campaign_validator = read("campaign_validator", ROOT / "src/content/campaign_validator.gd")
require(
    "campaign_validator",
    campaign_validator,
    [
        'interaction.has("progression_required")',
        "progression_required must be boolean",
    ],
)

progression_source_index = read(
    "progression_source_index",
    ROOT / "src/content/progression_source_index.gd",
)
require(
    "progression_source_index",
    progression_source_index,
    [
        "collect_recipe_unlock_sources",
        '"unlock_recipes"',
        '"gated": gated',
    ],
)

settings_compile = read("settings_compile", ROOT / "tools/compile_player_settings_probe.gd")
require(
    "settings_compile",
    settings_compile,
    [
        "player_input_bindings.gd",
        "player_settings.gd",
        "player_settings_store.gd",
        "player_controls_overlay.gd",
        "smoke_player_settings.gd",
        "smoke_player_settings_recovery_edges.gd",
        "smoke_input_bindings.gd",
    ],
)

supply_compile = read("supply_compile", ROOT / "tools/compile_supply_region_probe.gd")
require(
    "supply_compile",
    supply_compile,
    [
        "supply_region_catalog.gd",
        "supply_region_validator.gd",
        "complete_content_validator.gd",
        "supply_region_model.gd",
        "smoke_supply_regions.gd",
        "smoke_supply_validation_edges.gd",
    ],
)

multiplayer_compile = read("multiplayer_compile", ROOT / "tools/compile_multiplayer_probe.gd")
require(
    "multiplayer_compile",
    multiplayer_compile,
    [
        "multiplayer_catalog.gd",
        "multiplayer_area_validator.gd",
        "multiplayer_session_model.gd",
        "multiplayer_connection_profile.gd",
        "multiplayer_connection_profile_store.gd",
        "multiplayer_session.gd",
        "multiplayer_save_guard.gd",
        "multiplayer_post_tick.gd",
        "multiplayer_overlay.gd",
        "multiplayer_connection_panel.gd",
        "smoke_multiplayer_session_model.gd",
        "smoke_multiplayer_connection_profile.gd",
        "smoke_multiplayer_runtime.gd",
        "smoke_multiplayer_validation_edges.gd",
        "app.tscn",
    ],
)

bindings = read("input_bindings", ROOT / "src/game/player_input_bindings.gd")
require(
    "input_bindings",
    bindings,
    [
        "RESERVED_ESCAPE_PHYSICAL",
        "RESERVED_OPTIONS_PHYSICAL",
        "RESERVED_START_BUTTON",
        "descriptor_has_modifiers",
        "event_uses_modifiers",
        "modifier_chord_message",
        "non-exact InputMap matching",
        "apply_profile",
        "input_map_matches",
        "swapped_with",
    ],
)
require_order(
    "input_bindings",
    bindings,
    "static func apply_profile(value: Variant) -> Dictionary:\n\tvar validation := validate_profile(value)",
    "\tvar profile := sanitize_profile(value)",
)
forbid(
    "input_bindings",
    bindings,
    ['"options_menu",', '"pause_game",', "Time.get_unix_time", "OS.get_unix_time"],
)

settings_model = read("player_settings", ROOT / "src/game/player_settings.gd")
require(
    "player_settings",
    settings_model,
    [
        "CURRENT_SCHEMA := 2",
        '"input_bindings"',
        '"controls"',
        "number_step",
        "lookup never rebuilds fourteen actions",
        "PlayerInputBindings.validate_profile",
    ],
)
forbid(
    "player_settings",
    settings_model,
    ["sanitize(settings).get", "var sanitized := sanitize(settings)"],
)

settings_store = read("player_settings_store", ROOT / "src/game/player_settings_store.gd")
require(
    "player_settings_store",
    settings_store,
    [
        "validate_raw_input_bindings",
        'PlayerInputBindings.validate_profile(settings.get("input_bindings"))',
        "fail closed before sanitization",
        "write_settings",
        "FileAccess.open(temporary_path, FileAccess.WRITE)",
    ],
)
require_order(
    "player_settings_store",
    settings_store,
    "var binding_validation := validate_raw_input_bindings(settings, final_path)",
    "var sanitized := PlayerSettings.sanitize(settings)",
)
require_order(
    "player_settings_store",
    settings_store,
    "var binding_validation := validate_raw_input_bindings(settings, final_path)",
    "var file := FileAccess.open(temporary_path, FileAccess.WRITE)",
)

runtime = read("runtime_controls", ROOT / "src/presentation_runtime_current.gd")
require(
    "runtime_controls",
    runtime,
    [
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
        "open_control_bindings",
        "handle_control_capture_event",
        "input_action_hint",
        "input_binding_cache_contract_ok",
        "control_bindings_contract_ok",
    ],
)

controls_overlay = read("controls_overlay", ROOT / "src/player_controls_overlay.gd")
require(
    "controls_overlay",
    controls_overlay,
    [
        "draw_dynamic_context_prompt",
        "draw_dynamic_reload_hint",
        "draw_control_settings_panel",
        "control_remapping_overlay_contract_ok",
    ],
)

control_smoke = read("control_smoke", ROOT / "tools/smoke_input_bindings.gd")
require(
    "control_smoke",
    control_smoke,
    [
        "all fourteen gameplay actions",
        "Keyboard capture must detect modifier chords before InputMap matching",
        "Invalid modifier profiles must fail before InputMap mutation",
        "Small analogue noise must not become a binding",
        "Binding a used key must swap",
        "Atomic settings writes must reject malformed controls before rotating the valid primary file",
        "Rejected control writes must leave the valid primary settings file in place",
        "Rejected control writes must not rotate the valid primary settings file into a backup",
        "Rejected control writes must not leave a temporary settings file",
        "A rejected control write must continue loading directly from the unchanged primary file",
        "Repeated draw-time hint and row reads must not rebuild the binding profile cache",
        "Modifier chords must be consumed rather than leaking into a non-exact gameplay action",
        "Reserved recovery inputs must be consumed",
        "Reset Controls must invalidate and rebuild every cached hint and row",
    ],
)

player_settings_contract = read("player_settings_contract", ROOT / "tools/check_player_settings_contract.py")
require(
    "player_settings_contract",
    player_settings_contract,
    [
        "descriptor_has_modifiers",
        "modifier_chord_message",
        "validate_raw_input_bindings",
        "require_order",
        "Rejected control writes must leave the valid primary settings file in place",
        "A malformed control profile exits before any file mutation",
    ],
)

settings_documentation = read("player_settings_documentation", ROOT / "docs/PLAYER_SETTINGS.md")
require(
    "player_settings_documentation",
    settings_documentation,
    [
        "Physical keys, not modifier chords",
        "Validate the raw nested binding profile before sanitization",
        "A malformed control profile exits before any file mutation",
        "clean primary load, rather than backup recovery, after a rejected write",
    ],
)

supply_validator = read("supply_validator", ROOT / "src/content/supply_region_validator.gd")
require(
    "supply_validator",
    supply_validator,
    [
        "supply_region_id must be a string",
        "restock_quantity must be an integer",
        "restock_target must be an integer",
        "restock_interval_seconds must be numeric",
        "max_catchup_cycles must be an integer",
        "supply_regions_initialized must be boolean",
        "Save supply cycle for '%s' must be an integer",
    ],
)

supply_edges = read("supply_edges", ROOT / "tools/smoke_supply_validation_edges.gd")
require(
    "supply_edges",
    supply_edges,
    [
        "Supply route IDs must reject numeric coercion",
        "Supply intervals must reject numeric strings",
        "Restock quantities must reject numeric strings",
        "Supply initialisation state must reject string coercion",
    ],
)

trade_studio = read("trade_studio_supply", ROOT / "addons/epochbound_trade_studio/trade_studio_supply.gd")
require(
    "trade_studio_supply",
    trade_studio,
    [
        "The selected supply route is not in the editable primary catalogue",
        "merchant_supply_region_selector.disabled = true",
    ],
)

trade_smoke = read("trade_studio_smoke", ROOT / "tools/smoke_trade_studio.gd")
require(
    "trade_studio_smoke",
    trade_smoke,
    [
        "Deleting a route from a secondary catalogue must not rewrite the editable primary catalogue",
        "Secondary-route deletion must explain why it was blocked",
    ],
)

multiplayer_contract = read("multiplayer_contract", ROOT / "tools/check_multiplayer_contract.py")
require(
    "multiplayer_contract",
    multiplayer_contract,
    [
        "ENetMultiplayerPeer.new()",
        "multiplayer.get_remote_sender_id()",
        "host-only progression",
        "session-only PvP",
        "sanctuary safety",
        "bounded snapshots",
        "matchmaking, relay, identity and anti-cheat remain explicit future production boundaries",
    ],
)

multiplayer_connection_contract = read(
    "multiplayer_connection_contract",
    ROOT / "tools/check_multiplayer_connection_contract.py",
)
require(
    "multiplayer_connection_contract",
    multiplayer_connection_contract,
    [
        'PROFILE_FILENAME := "multiplayer_connection.json"',
        "Connection profiles must keep the UDP port in its separately bounded field",
        "Raw connection data fails before temporary writes or backup rotation".lower(),
        "multiplayer_connection_panel_contract_ok",
        "smoke_multiplayer_connection_profile.gd",
        "epochbound_multiplayer_connection_contract_passed",
    ],
)

combat_fairness_contract = read(
    "combat_fairness_contract",
    ROOT / "tools/check_combat_fairness_contract.py",
)
require(
    "combat_fairness_contract",
    combat_fairness_contract,
    [
        "epochbound_combat_fairness_contract_passed",
        "attack_target_id",
        "Stagger must cancel the pending attack windup",
        "Interrupted windup must not deal deferred damage after stagger",
        '"combatFairnessValidation": "passed"',
    ],
)

combat_fairness_runtime = read(
    "combat_fairness_runtime",
    ROOT / "src/combat_director_runtime.gd",
)
require(
    "combat_fairness_runtime",
    combat_fairness_runtime,
    [
        'entity["attack_target_id"] = target_name',
        "damage_actor(locked_target_id",
        'entity["attack_windup"] = 0.0',
        'entity["attack_target_id"] = ""',
    ],
)
forbid(
    "combat_fairness_runtime",
    combat_fairness_runtime,
    ["damage_actor(target_name"],
)

multiplayer_session = read("multiplayer_session", ROOT / "src/multiplayer_session.gd")
require(
    "multiplayer_session",
    multiplayer_session,
    [
        'ENET_CLASS_NAME := "ENetMultiplayerPeer"',
        "ClassDB.instantiate(ENET_CLASS_NAME)",
        'peer.has_method("create_server")',
        '"create_server",',
        'peer.has_method("create_client")',
        'peer.call("create_client", connect_address, connect_port, 3)',
        '@rpc("any_peer", "call_remote", "unreliable_ordered", INPUT_CHANNEL)',
        '@rpc("authority", "call_remote", "unreliable_ordered", SNAPSHOT_CHANNEL)',
        "PROTOCOL VERSION MISMATCH",
        "CAMPAIGN VERSION MISMATCH",
        "blocks_manual_save",
        "blocks_autosave",
    ],
)
forbid(
    "multiplayer_session",
    multiplayer_session,
    [
        "allow_object_decoding = true",
        "SaveProfileStore",
        "write_profile(",
        "read_profile(",
    ],
)

if errors:
    print("Epochbound release workflow policy failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_release_workflow_policy_passed")
print("- primary validation runs automatically for exact main-push SHAs and remains manually dispatchable")
print("- focused Audio, Sprite and Linux Agent workflows remain governed manual exact-SHA gates")
print("- remote actions and reusable workflows are immutable")
print("- raw controls fail before sanitization, temporary writes or backup rotation")
print("- host-authoritative co-op, authored PvP areas and save isolation are guarded before Godot execution")
print("- player-local multiplayer connection setup, atomic recovery and save isolation are guarded before Godot execution")
print("- runtime composition, player settings, persistent controls, warning-safe editor icons, leak-free headless cleanup, meaningful temporal shifts, locked combat telegraphs, stagger interrupts, warning-free reference readiness, progression affordability and regional supply entrypoints are guarded before Godot execution")
print("- validation cannot publish, deploy, reset, clean or push")
