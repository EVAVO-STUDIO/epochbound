#!/usr/bin/env python3
"""Apply the combat target-lock and stagger-interrupt production slice."""

from __future__ import annotations

from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    source = file_path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise SystemExit(
            f"{path}: expected one replacement anchor, found {count}: {old[:120]!r}"
        )
    file_path.write_text(source.replace(old, new, 1), encoding="utf-8")


# Runtime: preserve one target identity through windup and cancel it on stagger.
replace_once(
    "src/combat_director_runtime.gd",
    '\t\tentity["attack_windup"] = float(old.get("attack_windup", 0.0))\n\t\tentity["target_memory"] = float(old.get("target_memory", 0.0))',
    '\t\tentity["attack_windup"] = float(old.get("attack_windup", 0.0))\n\t\tentity["attack_target_id"] = str(old.get("attack_target_id", ""))\n\t\tentity["target_memory"] = float(old.get("target_memory", 0.0))',
)
replace_once(
    "src/combat_director_runtime.gd",
    '''\tvar attack_windup := maxf(0.0, float(entity.get("attack_windup", 0.0)) - delta)
\tif float(entity.get("attack_windup", 0.0)) > 0.0:
\t\tentity["attack_windup"] = attack_windup
\t\tentity["mode"] = "windup"
\t\tEncounterModel.update_facing(entity, position.direction_to(target_position))
\t\tif attack_windup <= 0.0:
\t\t\tif position.distance_to(target_position) <= attack_range + 6.0 and target_inside_leash:
\t\t\t\tvar attacker_context := definition_data.duplicate(true)
\t\t\t\tattacker_context["_position"] = position
\t\t\t\tdamage_actor(target_name, int(definition_data.get("attack_damage", 1)), attacker_context)
\t\t\tentity["attack_cooldown"] = float(definition_data.get("attack_cooldown", 1.0))
\t\t\tentity["mode"] = "chase"
\t\truntime_entities[index] = entity
\t\treturn

\tvar outside_leash := spawn_position.distance_to(position) > leash''',
    '''\tvar attack_windup := maxf(0.0, float(entity.get("attack_windup", 0.0)) - delta)
\tif float(entity.get("attack_windup", 0.0)) > 0.0:
\t\tvar locked_target_id := str(entity.get("attack_target_id", ""))
\t\tif not attack_target_is_available(locked_target_id):
\t\t\tentity["attack_windup"] = 0.0
\t\t\tentity["attack_target_id"] = ""
\t\t\tentity["mode"] = "chase"
\t\t\truntime_entities[index] = entity
\t\t\treturn
\t\tvar locked_target_position := attack_target_position(locked_target_id)
\t\tvar locked_target_inside_leash := EncounterZoneModel.target_is_inside_leash(
\t\t\tzone,
\t\t\tspawn_position,
\t\t\tlocked_target_position,
\t\t\tleash
\t\t)
\t\tentity["attack_windup"] = attack_windup
\t\tentity["mode"] = "windup"
\t\tEncounterModel.update_facing(entity, position.direction_to(locked_target_position))
\t\tif attack_windup <= 0.0:
\t\t\tif position.distance_to(locked_target_position) <= attack_range + 6.0 and locked_target_inside_leash:
\t\t\t\tvar attacker_context := definition_data.duplicate(true)
\t\t\t\tattacker_context["_position"] = position
\t\t\t\tdamage_actor(locked_target_id, int(definition_data.get("attack_damage", 1)), attacker_context)
\t\t\tentity["attack_cooldown"] = float(definition_data.get("attack_cooldown", 1.0))
\t\t\tentity["attack_target_id"] = ""
\t\t\tentity["mode"] = "chase"
\t\truntime_entities[index] = entity
\t\treturn

\tentity["attack_target_id"] = ""
\tvar outside_leash := spawn_position.distance_to(position) > leash''',
)
replace_once(
    "src/combat_director_runtime.gd",
    '\t\t\tentity["attack_windup"] = maxf(0.05, float(definition_data.get("attack_windup", DEFAULT_ATTACK_WINDUP)))\n\t\t\tentity["mode"] = "windup"\n\t\t\tEncounterModel.update_facing(entity, position.direction_to(target_position))',
    '\t\t\tentity["attack_windup"] = maxf(0.05, float(definition_data.get("attack_windup", DEFAULT_ATTACK_WINDUP)))\n\t\t\tentity["attack_target_id"] = target_name\n\t\t\tentity["mode"] = "windup"\n\t\t\tEncounterModel.update_facing(entity, position.direction_to(target_position))',
)
replace_once(
    "src/combat_director_runtime.gd",
    '''\tentity = update_patrol(index, entity, spawn_position, definition_data, delta)
\truntime_entities[index] = entity


func update_patrol(''',
    '''\tentity = update_patrol(index, entity, spawn_position, definition_data, delta)
\truntime_entities[index] = entity


func attack_target_is_available(actor_id: String) -> bool:
\tmatch actor_id:
\t\t"player":
\t\t\treturn player_health > 0
\t\t"companion":
\t\t\treturn companion_enabled() and companion_health > 0
\t\t_:
\t\t\treturn false


func attack_target_position(actor_id: String) -> Vector2:
\treturn companion if actor_id == "companion" else player


func update_patrol(''',
)
replace_once(
    "src/combat_director_runtime.gd",
    '\tvar distance := maxf(0.0, float(definition_data.get("knockback_distance", DEFAULT_KNOCKBACK_DISTANCE)))\n\tentity["stagger_timer"] = stagger',
    '\tvar distance := maxf(0.0, float(definition_data.get("knockback_distance", DEFAULT_KNOCKBACK_DISTANCE)))\n\tentity["attack_windup"] = 0.0\n\tentity["attack_target_id"] = ""\n\tentity["stagger_timer"] = stagger',
)

# Executable regression: actor-switching cannot steal a telegraph and stagger is a true interrupt.
replace_once(
    "tools/smoke_combat_director.gd",
    '''\tcheck(float(hound.get("attack_windup", 0.0)) > 0.0, "Enemy windup timer must be active.")
\tcheck(int(runtime.get("player_health")) == player_health_before, "Windup must not damage the player early.")
\truntime.call("update_runtime_entities", 0.35)
\tcheck(int(runtime.get("player_health")) == player_health_before - expected_player_damage, "Completed windup must apply authored attack damage after active defence.")''',
    '''\tcheck(float(hound.get("attack_windup", 0.0)) > 0.0, "Enemy windup timer must be active.")
\tcheck(str(hound.get("attack_target_id", "")) == "player", "Windup must lock the selected target identity.")
\tcheck(int(runtime.get("player_health")) == player_health_before, "Windup must not damage the player early.")
\tvar companion_health_before := int(runtime.get("companion_health"))
\truntime.set("companion", Vector2(398, 216))
\truntime.call("update_runtime_entities", 0.35)
\tcheck(int(runtime.get("player_health")) == player_health_before - expected_player_damage, "Completed windup must apply authored attack damage after active defence.")
\tcheck(int(runtime.get("companion_health")) == companion_health_before, "A closer companion must not inherit the player's active telegraph.")
\tentities = runtime_entities(runtime)
\thound = entities[hound_index]
\tcheck(str(hound.get("attack_target_id", "")) == "", "Resolved windup must clear its target lock.")''',
)
replace_once(
    "tools/smoke_combat_director.gd",
    '''\tentities = runtime_entities(runtime)
\thound = entities[hound_index]
\thound["position"] = Vector2(416, 216)
\thound["attack_windup"] = 0.0
\thound["stagger_timer"] = 0.0
\tentities[hound_index] = hound
\truntime.set("runtime_entities", entities)
\truntime.set("player", Vector2(380, 216))
\truntime.call("damage_entity", hound_index, 4, "ELI")
\tentities = runtime_entities(runtime)
\thound = entities[hound_index]
\tcheck(str(hound.get("mode", "")) == "staggered", "Damaged enemy must enter staggered mode.")
\tcheck(float(hound.get("stagger_timer", 0.0)) > 0.0, "Damaged enemy must receive stagger time.")
\tvar knockback_value: Variant = hound.get("knockback_velocity", Vector2.ZERO)
\tcheck(knockback_value is Vector2 and (knockback_value as Vector2).length_squared() > 0.0, "Damaged enemy must receive knockback velocity.")
\tcheck(int(runtime.get("combo_count")) >= 1, "Successful hit must advance the combat chain.")''',
    '''\tentities = runtime_entities(runtime)
\thound = entities[hound_index]
\thound["position"] = Vector2(400, 216)
\thound["attack_windup"] = 0.0
\thound["attack_target_id"] = ""
\thound["stagger_timer"] = 0.0
\thound["knockback_velocity"] = Vector2.ZERO
\thound["attack_cooldown"] = 0.0
\thound["mode"] = "chase"
\tentities[hound_index] = hound
\truntime.set("runtime_entities", entities)
\truntime.set("player", Vector2(380, 216))
\truntime.set("companion", Vector2(270, 230))
\truntime.set("player_hurt_lock", 0.0)
\truntime.call("update_runtime_entities", 0.01)
\tentities = runtime_entities(runtime)
\thound = entities[hound_index]
\tcheck(str(hound.get("mode", "")) == "windup", "Interrupt fixture must begin from an active enemy windup.")
\tcheck(str(hound.get("attack_target_id", "")) == "player", "Interrupt fixture must retain the selected player target.")
\tvar player_health_before_interrupt := int(runtime.get("player_health"))
\truntime.call("damage_entity", hound_index, 1, "ELI")
\tentities = runtime_entities(runtime)
\thound = entities[hound_index]
\tcheck(str(hound.get("mode", "")) == "staggered", "Damaged enemy must enter staggered mode.")
\tcheck(float(hound.get("stagger_timer", 0.0)) > 0.0, "Damaged enemy must receive stagger time.")
\tcheck(float(hound.get("attack_windup", -1.0)) == 0.0, "Stagger must cancel the pending attack windup.")
\tcheck(str(hound.get("attack_target_id", "missing")) == "", "Stagger must clear the pending attack target.")
\tvar knockback_value: Variant = hound.get("knockback_velocity", Vector2.ZERO)
\tcheck(knockback_value is Vector2 and (knockback_value as Vector2).length_squared() > 0.0, "Damaged enemy must receive knockback velocity.")
\tcheck(int(runtime.get("combo_count")) >= 1, "Successful hit must advance the combat chain.")
\tvar stagger_remaining := float(hound.get("stagger_timer", 0.0))
\thound["knockback_velocity"] = Vector2.ZERO
\tentities[hound_index] = hound
\truntime.set("runtime_entities", entities)
\truntime.call("update_runtime_entities", stagger_remaining + 0.01)
\tcheck(int(runtime.get("player_health")) == player_health_before_interrupt, "Interrupted windup must not deal deferred damage after stagger.")
\tentities = runtime_entities(runtime)
\thound = entities[hound_index]
\tcheck(str(hound.get("mode", "")) == "windup", "A post-stagger attack must begin a fresh telegraph.")
\tcheck(float(hound.get("attack_windup", 0.0)) > 0.0, "Fresh post-stagger telegraph must restore the full authored windup.")
\tcheck(str(hound.get("attack_target_id", "")) == "player", "Fresh post-stagger telegraph must acquire its own target lock.")''',
)
replace_once(
    "tools/smoke_combat_director.gd",
    '\thound["attack_windup"] = 0.0\n\thound["mode"] = "chase"',
    '\thound["attack_windup"] = 0.0\n\thound["attack_target_id"] = ""\n\thound["mode"] = "chase"',
)
replace_once(
    "tools/smoke_combat_director.gd",
    'print("Combat Director smoke test passed: zones, windup, derived damage, stagger, leash return and persistent clearing are coherent.")',
    'print("Combat Director smoke test passed: zones, target locking, interruptible windup, derived damage, stagger, leash return and persistent clearing are coherent.")',
)

# Documentation: make the player-facing fairness rules explicit.
replace_once(
    "docs/COMBAT_DIRECTOR.md",
    '''`attack_windup` is the telegraph between entering range and applying damage. During windup the enemy faces its target and displays a visible timing ring.

A readable attack should give the player enough information to:''',
    '''`attack_windup` is the telegraph between entering range and applying damage. During windup the enemy faces its target and displays a visible timing ring.

Target identity is locked when windup begins. A different actor becoming closer cannot inherit the pending attack. The enemy may continue tracking the locked actor's current position, but damage can resolve only against that actor. If the locked actor becomes unavailable, the telegraph cancels instead of transferring silently.

A readable attack should give the player enough information to:''',
)
replace_once(
    "docs/COMBAT_DIRECTOR.md",
    '''`stagger_duration` determines how long a damaged enemy stops its current behaviour. Stagger creates tactical confirmation and prevents every successful attack from feeling ignored.

Very long stagger values can remove threat entirely.''',
    '''`stagger_duration` determines how long a damaged enemy stops its current behaviour. Stagger creates tactical confirmation and prevents every successful attack from feeling ignored.

A successful stagger cancels an in-progress windup and clears its locked target. When the enemy recovers, it must begin a fresh full windup before later damage can resolve. A paused pre-hit telegraph never resumes after the interrupt.

Very long stagger values can remove threat entirely.''',
)
replace_once(
    "docs/COMBAT_DIRECTOR.md",
    '''### Windup

The enemy has reached attack range and is telegraphing. Damage is applied only when the windup completes and the target remains close enough.

### Staggered

The enemy has been hit. It pauses its attack logic and resolves authored knockback.''',
    '''### Windup

The enemy has reached attack range and is telegraphing. The selected actor identity remains locked until resolution or cancellation. Damage is applied only when the windup completes and that locked target remains available, close enough and inside the leash.

### Staggered

The enemy has been hit. It cancels any pending windup and target lock, then resolves authored knockback. Any later attack must start a new telegraph.''',
)
replace_once(
    "docs/COMBAT_DIRECTOR.md",
    '''### Fairness

- Damage follows a telegraphed action rather than arbitrary contact.
- Leash boundaries do not cause enemies to reset in the middle of normal combat.''',
    '''### Fairness

- Damage follows a telegraphed action rather than arbitrary contact.
- A telegraph cannot silently transfer from Eli to Morrow, or from Morrow to Eli, because another actor becomes closer.
- A successful stagger cancels the pending hit instead of pausing it until recovery.
- Leash boundaries do not cause enemies to reset in the middle of normal combat.''',
)
replace_once(
    "docs/COMBAT_DIRECTOR.md",
    '6. Combat Director smoke tests for activation, windup, damage, stagger, knockback, leash return and zone clearing.',
    '6. Combat Director smoke tests for activation, target locking and stagger interruption, windup, damage, knockback, leash return and zone clearing.',
)

# Local and exact-main gates.
replace_once(
    "scripts/validate.ps1",
    '@("Smoke test Combat Director zones and behaviour", "res://tools/smoke_combat_director.gd")',
    '@("Smoke test Combat Director target locking and stagger interrupts", "res://tools/smoke_combat_director.gd")',
)
replace_once(
    "scripts/validate.ps1",
    'meaningful temporal shifts, multi-source affordability, regional supply, scarcity, sprite-animation, environment and combat-readability validation',
    'meaningful temporal shifts, locked combat telegraphs, stagger interrupts, multi-source affordability, regional supply, scarcity, sprite-animation, environment and combat-readability validation',
)
replace_once(
    ".github/workflows/validate.yml",
    '''      - name: Validate temporal shift consequence contract
        run: python3 tools/check_temporal_shift_contract.py

      - name: Validate canonical runtime composition contract''',
    '''      - name: Validate temporal shift consequence contract
        run: python3 tools/check_temporal_shift_contract.py

      - name: Validate combat telegraph fairness contract
        run: python3 tools/check_combat_fairness_contract.py

      - name: Validate canonical runtime composition contract''',
)
replace_once(
    ".github/workflows/validate.yml",
    '# Receipt schema migrated from: "schemaVersion": "2.1"\n          payload = {\n              "schemaVersion": "2.2",',
    '# Receipt schema migrated from: "schemaVersion": "2.2"\n          payload = {\n              "schemaVersion": "2.3",',
)
replace_once(
    ".github/workflows/validate.yml",
    '              "temporalShiftValidation": "passed",\n              "presentationValidation": "passed",',
    '              "temporalShiftValidation": "passed",\n              "combatFairnessValidation": "passed",\n              "presentationValidation": "passed",',
)

# Release policy pins the new checker, runtime regression and receipt evidence.
replace_once(
    "tools/check_release_workflow_policy.py",
    '        "python3 tools/check_temporal_shift_contract.py",\n        "python3 tools/check_runtime_scene_contract.py",',
    '        "python3 tools/check_temporal_shift_contract.py",\n        "python3 tools/check_combat_fairness_contract.py",\n        "python3 tools/check_runtime_scene_contract.py",',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    '        \'"schemaVersion": "2.2"\',',
    '        \'"schemaVersion": "2.3"\',',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    '        \'"temporalShiftValidation": "passed"\',\n        \'"supplyRegionValidation": "passed"\',',
    '        \'"temporalShiftValidation": "passed"\',\n        \'"combatFairnessValidation": "passed"\',\n        \'"supplyRegionValidation": "passed"\',',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    '        "smoke_temporal_shift_audit.gd",\n        "meaningful temporal shifts",\n        "smoke_multiplayer_session_model.gd",',
    '        "smoke_temporal_shift_audit.gd",\n        "meaningful temporal shifts",\n        "Smoke test Combat Director target locking and stagger interrupts",\n        "smoke_combat_director.gd",\n        "locked combat telegraphs",\n        "stagger interrupts",\n        "smoke_multiplayer_session_model.gd",',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    '''multiplayer_session = read("multiplayer_session", ROOT / "src/multiplayer_session.gd")''',
    '''combat_fairness_contract = read(
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

multiplayer_session = read("multiplayer_session", ROOT / "src/multiplayer_session.gd")''',
)
replace_once(
    "tools/check_release_workflow_policy.py",
    'print("- runtime composition, player settings, persistent controls, warning-safe editor icons, leak-free headless cleanup, meaningful temporal shifts, warning-free reference readiness, progression affordability and regional supply entrypoints are guarded before Godot execution")',
    'print("- runtime composition, player settings, persistent controls, warning-safe editor icons, leak-free headless cleanup, meaningful temporal shifts, locked combat telegraphs, stagger interrupts, warning-free reference readiness, progression affordability and regional supply entrypoints are guarded before Godot execution")',
)

# Every source checker that pins the current receipt schema must advance together.
for checker_path in sorted(Path("tools").glob("check_*_contract.py")):
    source = checker_path.read_text(encoding="utf-8")
    updated = source.replace(
        '# Receipt schema migrated from: "schemaVersion": "2.1"',
        '# Receipt schema migrated from: "schemaVersion": "2.2"',
    )
    updated = updated.replace('"schemaVersion": "2.2"', '"schemaVersion": "2.3"')
    if updated != source:
        checker_path.write_text(updated, encoding="utf-8")

print("combat_fairness_integration_applied")
