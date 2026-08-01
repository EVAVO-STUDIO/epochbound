#!/usr/bin/env python3
"""Fail closed when Epochbound's Sprite Animation integration drifts."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read_text(relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.is_file():
        errors.append(f"missing required file: {relative_path}")
        return ""
    return path.read_text(encoding="utf-8")


def read_json(relative_path: str) -> dict:
    source = read_text(relative_path)
    if not source:
        return {}
    try:
        value = json.loads(source)
    except json.JSONDecodeError as exc:
        errors.append(f"{relative_path}: invalid JSON: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{relative_path}: root must be an object")
        return {}
    return value


def require(relative_path: str, source: str, tokens: list[str]) -> None:
    for token in tokens:
        if token not in source:
            errors.append(f"{relative_path}: missing {token}")


def safe_relative_png(value: str) -> bool:
    normalized = value.strip().replace("\\", "/")
    if normalized == "":
        return True
    if normalized.startswith("/") or ":" in normalized:
        return False
    parts = normalized.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        return False
    return normalized.lower().endswith(".png")


campaign = read_json("campaigns/epochbound_demo/campaign.json")
if campaign.get("animation_files") != ["animation/core.json"]:
    errors.append("reference campaign must bind animation/core.json exactly once")

catalog = read_json("campaigns/epochbound_demo/animation/core.json")
if catalog.get("schema_version") != 1:
    errors.append("reference animation catalogue must use schema_version 1")
profiles = catalog.get("profiles", [])
bindings = catalog.get("bindings", [])
if not isinstance(profiles, list) or len(profiles) != 6:
    errors.append("reference animation catalogue must contain exactly six profiles")
    profiles = []
if not isinstance(bindings, list) or len(bindings) != 6:
    errors.append("reference animation catalogue must contain exactly six bindings")
    bindings = []

profile_ids: set[str] = set()
required_states = {"idle", "walk", "attack", "hurt"}
for index, profile in enumerate(profiles):
    label = f"animation profile #{index + 1}"
    if not isinstance(profile, dict):
        errors.append(f"{label}: must be an object")
        continue
    profile_id = profile.get("id")
    if not isinstance(profile_id, str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", profile_id):
        errors.append(f"{label}: invalid stable id")
        continue
    if profile_id in profile_ids:
        errors.append(f"duplicate animation profile id: {profile_id}")
    profile_ids.add(profile_id)
    if profile.get("directions") not in {1, 4}:
        errors.append(f"{profile_id}: directions must be 1 or 4")
    atlas = profile.get("atlas", "")
    if not isinstance(atlas, str) or not safe_relative_png(atlas):
        errors.append(f"{profile_id}: atlas must be empty or a safe relative PNG path")
    for key in ("frame_size", "render_size", "pivot"):
        record = profile.get(key)
        if not isinstance(record, dict):
            errors.append(f"{profile_id}: {key} must be an object")
            continue
        if not all(isinstance(record.get(axis), int) for axis in ("x", "y")):
            errors.append(f"{profile_id}: {key} coordinates must be integers")
    animations = profile.get("animations")
    if not isinstance(animations, dict) or set(animations) != required_states:
        errors.append(f"{profile_id}: must define exactly idle, walk, attack and hurt")
        continue
    for state, record in animations.items():
        if not isinstance(record, dict):
            errors.append(f"{profile_id}/{state}: must be an object")
            continue
        if not isinstance(record.get("row"), int) or record["row"] < 0:
            errors.append(f"{profile_id}/{state}: row must be a non-negative integer")
        if not isinstance(record.get("frames"), int) or record["frames"] < 1:
            errors.append(f"{profile_id}/{state}: frames must be a positive integer")
        fps = record.get("fps")
        if not isinstance(fps, (int, float)) or isinstance(fps, bool) or not 1.0 <= float(fps) <= 30.0:
            errors.append(f"{profile_id}/{state}: fps must be between 1 and 30")
        if not isinstance(record.get("loop"), bool):
            errors.append(f"{profile_id}/{state}: loop must be boolean")

for index, binding in enumerate(bindings):
    label = f"animation binding #{index + 1}"
    if not isinstance(binding, dict):
        errors.append(f"{label}: must be an object")
        continue
    target = binding.get("target")
    profile_id = binding.get("profile_id")
    if not isinstance(target, str) or not target:
        errors.append(f"{label}: target is required")
    if profile_id not in profile_ids:
        errors.append(f"{label}: references unknown profile {profile_id!r}")

scene = read_text("src/app.tscn")
require(
    "src/app.tscn",
    scene,
    [
        'res://src/environment_animation_overlay.gd',
        '[node name="PresentationOverlay" type="Node2D" parent="PresentationLayer"]',
    ],
)
polish_overlay = read_text("src/sprite_animation_polish_overlay.gd")
require(
    "src/sprite_animation_polish_overlay.gd",
    polish_overlay,
    [
        "travel_distance_by_key",
        "walk_frame_distance",
        "animation_should_freeze",
        "depth_records",
        "depth_order_keys",
        "draw_landmark_foregrounds",
        "animation_polish_contract_ok",
    ],
)
feedback_overlay = read_text("src/adventure_feedback_overlay.gd")
require(
    "src/adventure_feedback_overlay.gd",
    feedback_overlay,
    [
        'extends "res://src/sprite_animation_polish_overlay.gd"',
        "announce_current_area",
        "draw_area_banner",
        "resolve_context_prompt",
        "nearest_entity_prompt",
        "nearest_connection_prompt",
        "nearest_map_interaction_prompt",
        "authored_requirements_met",
        "context_prompt_snapshot",
        "adventure_feedback_contract_ok",
    ],
)
environment_overlay = read_text("src/environment_animation_overlay.gd")
require(
    "src/environment_animation_overlay.gd",
    environment_overlay,
    [
        'extends "res://src/adventure_feedback_overlay.gd"',
        "update_environment_animation",
        "terrain_effect_kind_at",
        "spawn_environment_disturbance",
        "draw_animated_terrain",
        "draw_ambient_ground_motion",
        "draw_interaction_world_pulse",
        "draw_ground_disturbances",
        "animated_terrain_counts",
        "environment_animation_contract_ok",
    ],
)
focused_compile = read_text("tools/compile_sprite_animation_probe.gd")
require(
    "tools/compile_sprite_animation_probe.gd",
    focused_compile,
    [
        "environment_animation_overlay.gd",
        "smoke_environment_animation.gd",
    ],
)
project = read_text("project.godot")
require(
    "project.godot",
    project,
    ['res://addons/epochbound_sprite_animation_studio/plugin.cfg'],
)
final_validator = read_text("tools/validate_content.gd")
require(
    "tools/validate_content.gd",
    final_validator,
    ['res://src/content/sprite_animation_strict_validator.gd'],
)
install_service = read_text("src/content/campaign_install_service.gd")
require(
    "src/content/campaign_install_service.gd",
    install_service,
    ['res://src/content/sprite_animation_strict_validator.gd'],
)
campaign_plugin = read_text("addons/epochbound_campaign_studio/plugin.gd")
require(
    "addons/epochbound_campaign_studio/plugin.gd",
    campaign_plugin,
    ['campaign_studio_animation_current.gd'],
)
package_plugin = read_text("addons/epochbound_package_studio/plugin.gd")
require(
    "addons/epochbound_package_studio/plugin.gd",
    package_plugin,
    ['package_studio_current.gd'],
)
sprite_plugin = read_text("addons/epochbound_sprite_animation_studio/plugin.gd")
require(
    "addons/epochbound_sprite_animation_studio/plugin.gd",
    sprite_plugin,
    ['sprite_animation_studio_current.gd', 'return "Sprite"'],
)
local_gate = read_text("scripts/validate.ps1")
require(
    "scripts/validate.ps1",
    local_gate,
    [
        "compile_sprite_animation_probe.gd",
        "smoke_sprite_animation_runtime.gd",
        "smoke_environment_animation.gd",
        "smoke_sprite_animation_studio.gd",
        "smoke_sprite_animation_validation_edges.gd",
        "smoke_sprite_campaign_scaffold.gd",
        "smoke_sprite_package_validation.gd",
        "all seventeen authoring systems",
    ],
)
workflow = read_text(".github/workflows/sprite-animation-validation.yml")
require(
    ".github/workflows/sprite-animation-validation.yml",
    workflow,
    [
        "workflow_dispatch:",
        "permissions:\n  contents: read",
        "persist-credentials: false",
        "sha512sum --check",
        "python3 tools/check_sprite_animation_contract.py",
        "compile_sprite_animation_probe.gd",
        "smoke_sprite_animation_runtime.gd",
        "smoke_environment_animation.gd",
        "smoke_sprite_package_validation.gd",
        "git diff --exit-code",
    ],
)

if errors:
    print("Epochbound Sprite Animation contract failed:\n")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("epochbound_sprite_animation_contract_passed")
print(f"- profiles: {len(profiles)}")
print(f"- bindings: {len(bindings)}")
print("- grounded cadence, feet-based depth order, area cards, contextual prompts, animated terrain, environmental responses, editors, validators and package promotion are wired")
