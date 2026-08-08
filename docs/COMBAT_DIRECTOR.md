# Epochbound Combat Director

Combat Director is the encounter-pacing and enemy-behaviour layer inside the Godot editor. It sits beside Campaign Studio and Encounter Studio rather than replacing them:

- **Campaign Studio** authors maps, terrain, collision, navigation, eras, interactions and connections.
- **Encounter Studio** authors reusable props, NPCs, enemies, pickups and their map placements.
- **Combat Director** groups enemies into encounters, defines activation and leash spaces, tunes behaviour timing and validates combat fairness.

All three tools write to the same versioned campaign records consumed by the runtime and automated tests.

## Why encounter direction is separate

An enemy definition answers questions such as:

- How much health does this enemy have?
- How quickly does it move?
- How far can it see?
- How much damage does its attack cause?

An encounter zone answers different questions:

- Which enemies belong to this authored beat?
- When should they become active?
- How far may they pursue the player?
- Which era contains the encounter?
- When is the encounter considered cleared?
- What persistent state key records that outcome?

Keeping these concerns separate allows the same enemy type to behave differently in a cramped ruin, an open forest, a boss approach or a tutorial encounter without duplicating the reusable enemy definition.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Combat** tab.
3. Choose a campaign, map and era.
4. Select **Place Zone**, then click the map.
5. Give the zone a stable identifier and player-facing display name.
6. Set its combat radius, activation radius and leash padding.
7. Select the enemy placements belonging to the zone.
8. Decide whether the zone exists in every era or only the selected era.
9. Set an optional explicit clear-state key.
10. Apply the zone and validate the campaign.
11. Choose an enemy definition and tune patrol, telegraph, stagger, knockback and return behaviour.
12. Run the campaign and test entry, combat, disengagement, era shifting and return travel.

## Canvas controls

| Action | Input |
| --- | --- |
| Place or select a zone | Left mouse button |
| Pan | Middle mouse drag |
| Zoom | Mouse wheel |
| Change current operation | **Place Zone** or **Select** toolbar buttons |

The canvas includes the same map, object-placement and era context used by the other editors. Zone radius and activation radius remain visible together so authors can inspect combat space and trigger space as one composition.

## Encounter-zone contract

A map may contain an `encounter_zones` array:

```json
{
  "encounter_zones": [
    {
      "id": "clockwood_hound_pair",
      "display_name": "Clockwood Hound Pair",
      "position": {"x": 400, "y": 240},
      "radius": 132,
      "activation_radius": 188,
      "leash_padding": 42,
      "enemy_placements": [
        "clockwood_hound_west",
        "clockwood_hound_east"
      ],
      "available_eras": ["ashen"],
      "clear_state_key": "clockwood:zone:hound_pair"
    }
  ]
}
```

### Identifier

`id` is a stable lowercase reference. It should describe the authored encounter rather than a transient implementation detail.

Good examples:

- `east_ash_hunt`
- `clockwood_hound_pair`
- `floodgate_guardians`
- `museum_roof_ambush`

### Position and radius

`position` and `radius` describe the authored combat region. They are used for:

- encounter visualisation;
- target and leash review;
- validating that assigned enemies begin in a sensible region;
- future encounter cameras, music and objective logic.

The radius is not a hard invisible wall for the player. It establishes the encounter's intended spatial identity.

### Activation radius

`activation_radius` determines how close the player or active companion must come before the zone may wake its enemies. It must be at least as large as the combat radius.

A larger activation radius can:

- give enemies time to face or patrol before contact;
- make an encounter visible before it becomes dangerous;
- prevent the player from walking directly into a dormant group;
- support a deliberate approach beat.

It should not be so large that enemies activate from an unrelated room or route.

### Leash padding

`leash_padding` extends the legal pursuit region beyond the zone radius. Enemies return home when they or their target leave the authored leash.

The leash prevents several common action-RPG problems:

- enemies following the player across an entire map;
- combat contaminating dialogue, puzzles or entrances;
- enemies becoming stranded behind collision;
- repeated map transitions carrying an unintended pursuit state;
- one encounter pulling every nearby group at once.

### Enemy placements

`enemy_placements` references stable map placement IDs, not reusable enemy definition IDs. This means two instances of the same enemy type may belong to different zones.

A placement may belong to only one encounter zone on the same map. Shared ownership is rejected because it makes activation, clearing and retreat ambiguous.

### Era availability

`available_eras` follows the common Epochbound scoping rule:

- an empty array means every era;
- one or more era IDs limit the zone to those eras.

A zone may therefore disappear, gain members or be replaced by a different encounter when the player shifts eras.

### Clear-state key

`clear_state_key` records that every assigned enemy has been defeated. When left blank, the runtime derives a stable key from the map and zone IDs.

The reference runtime uses session state now. A later save-profile layer will persist these keys without changing the authored campaign record.

## Enemy behaviour tuning

Combat Director extends enemy definitions with optional behaviour fields.

### Patrol radius

`patrol_radius` describes a deterministic idle patrol around the placement's spawn point. A value of zero keeps the enemy at its spawn until activated.

Patrol movement should:

- establish the creature's temperament;
- remain inside readable combat space;
- avoid blocking a required route before activation;
- respect navigation and collision;
- return to a stable spawn after disengagement.

### Leash radius

`leash_radius` overrides the zone-derived leash for that enemy. A value of zero uses the zone radius plus leash padding.

Use an override sparingly. Zone-based leashes make groups easier to reason about and validate.

### Attack windup

`attack_windup` is the telegraph between entering range and applying damage. During windup the enemy faces its target and displays a visible timing ring.

Target identity is locked when windup begins. A different actor becoming closer cannot inherit the pending attack. The enemy may continue tracking the locked actor's current position, but damage can resolve only against that actor. If the locked actor becomes unavailable, the telegraph cancels instead of transferring silently.

Ordinary enemies share one active windup slot per actor. An in-range enemy that cannot claim the slot enters **Pressure**: it faces the target, maintains combat interest and waits without applying contact damage. When the committed attack resolves, misses or is interrupted, the next eligible enemy may begin a fresh telegraph. Boss definitions do not consume the ordinary-enemy slot, so a boss may remain active while one reinforcement pressures the same actor.

A readable attack should give the player enough information to:

- recognise that damage is imminent;
- choose movement, spacing or counterattack;
- understand why a hit occurred;
- learn the timing through play.

Instant contact damage is not the default combat language.

### Stagger duration

`stagger_duration` determines how long a damaged enemy stops its current behaviour. Stagger creates tactical confirmation and prevents every successful attack from feeling ignored.

A successful stagger cancels an in-progress windup and clears its locked target. When the enemy recovers, it must begin a fresh full windup before later damage can resolve. A paused pre-hit telegraph never resumes after the interrupt.

Very long stagger values can remove threat entirely. Very short values make hits feel weightless. The value belongs to the enemy definition so different enemy families can have distinct resistance.

### Knockback distance

`knockback_distance` controls how far a successful player or companion attack pushes the enemy during stagger.

Knockback must remain subordinate to collision, map bounds and encounter readability. It should not routinely throw enemies behind progression locks or out of their authored zone.

### Return speed multiplier

`return_speed_multiplier` modifies movement speed while an enemy is returning to its spawn. Returning should be decisive enough to restore encounter state without looking like a teleport.

### Target memory

`target_memory` allows an activated enemy to retain interest briefly after the target leaves awareness range. This prevents noisy one-frame switches between chase and idle near the awareness boundary.

### Contact knockback

`contact_knockback` controls the response applied to the player or companion when the enemy's completed attack lands.

## Runtime behaviour states

The current directed enemy state machine uses these modes:

### Idle

The enemy is at rest and has no active patrol target.

### Patrol

The enemy moves between deterministic points around its spawn. Patrol is cosmetic and spatially restrained until activation.

### Chase

The zone is active, the target is valid and inside the leash, and the enemy is navigating toward attack range.

### Pressure

The enemy is in attack range, but another ordinary enemy already owns the active windup against that actor. It holds position, faces the target and waits without dealing damage. Pressure is transient coordination state, not a durable campaign outcome.

### Windup

The enemy has reached attack range, owns the available pressure slot and is telegraphing. The selected actor identity remains locked until resolution or cancellation. Damage is applied only when the windup completes and that locked target remains available, close enough and inside the leash.

### Staggered

The enemy has been hit. It cancels any pending windup and target lock, then resolves authored knockback. Any later attack must start a new telegraph.

### Return

The target or enemy has left the leash, or combat interest has ended. The enemy navigates back to its authored spawn and returns to idle or patrol.

These modes are runtime state, not campaign definitions. Save files should not preserve a half-completed attack windup. They should preserve durable outcomes such as defeated placements and cleared zones.

## Hit feedback

The Combat Director runtime adds several temporary feedback channels:

- enemy hit flash;
- stagger pause;
- directional knockback;
- player and companion hurt outlines;
- attack-windup rings;
- chase and stagger indicators in the blockout renderer;
- short camera shake on damage or defeat;
- combat-chain count for consecutive successful hits;
- encounter-clear banners.

These are blockout contracts. Final sprites, animation, sound, particles and screen effects should reinforce the same timing rather than replacing undocumented rules.

## Companion combat

Morrow's combat assistance remains intentionally low-micromanagement:

- Morrow selects a nearby enemy automatically;
- attacks use a separate cooldown and lower damage;
- enemy targeting may prefer Morrow when he is closer;
- hurt recovery returns him to a safe trail position;
- companion presence can activate encounter zones;
- authored navigation and recovery still govern movement.

Future companion commands may change priorities, but the default behaviour must remain useful without turning combat into party-management overhead.

## Validation rules

Combat Director validation rejects:

- malformed `encounter_zones` records;
- invalid or duplicate zone IDs;
- positions outside the map canvas;
- non-positive radii;
- activation radii smaller than zone radii;
- negative leash padding;
- unknown era IDs;
- missing enemy placement references;
- placements that do not reference enemy definitions;
- one enemy assigned to multiple zones;
- duplicate or excessively long clear-state keys;
- negative enemy timing or movement values;
- non-positive return-speed multipliers.

It warns about:

- zones without enemies;
- enemies not assigned to any zone;
- enemy placements outside their zone leash;
- attack windups that may feel excessively slow;
- explicit leash radii smaller than awareness radii.

Validation proves referential and numerical coherence. It does not prove that an encounter is enjoyable.

## Combat quality gates

A production encounter should pass all of these gates.

### Readability

- The player can identify the threat before unavoidable damage.
- The attack windup has a distinct silhouette or timing cue.
- Enemy health and hit response are understandable.
- The combat area does not hide required exits or interactions.

### Fairness

- Damage follows a telegraphed action rather than arbitrary contact.
- A telegraph cannot silently transfer from Eli to Morrow, or from Morrow to Eli, because another actor becomes closer.
- A successful stagger cancels the pending hit instead of pausing it until recovery.
- Ordinary groups expose one active melee telegraph per actor instead of stacking simultaneous contact windups.
- Waiting enemies communicate pressure without applying hidden damage; bosses remain exempt from the ordinary-enemy slot.
- Leash boundaries do not cause enemies to reset in the middle of normal combat.
- Entry points do not place the player inside attack range.
- Era shifting does not spawn an enemy directly on an actor.
- Recovery cannot place Morrow inside an active attack.

### Spatial design

- The zone supports player and companion movement together.
- Collision does not create one-cell traps or unintentional safe exploits.
- Assigned enemies begin inside or reasonably near the zone.
- Retreat paths do not cross unrelated encounters.
- The zone does not overlap a map transition without a deliberate reason.

### Pacing

- The encounter introduces, develops or resolves an idea.
- Repeated enemies gain new spatial or group context.
- Patrol and activation create anticipation rather than empty waiting.
- Clearing the encounter produces a readable change or reward.
- Optional combat remains optional unless the campaign explicitly communicates otherwise.

### Persistence

- Defeated enemies do not respawn unexpectedly during the same session.
- Zone-clear state resolves only after all declared members are defeated.
- Era shifts preserve durable defeat state correctly.
- Map travel does not duplicate rewards.

## Reference encounters

### East Ash Hunt

Bellweather Crossing contains one Ashen-only hound zone around the eastern path. It proves:

- era-scoped activation;
- one enemy controlled by an authored zone;
- patrol, chase, windup, stagger and return;
- a stable clear-state key;
- encounter feedback without affecting Verdant exploration.

### Clockwood Hound Pair

Clockwood Edge contains an Ashen-only two-enemy zone. It proves:

- multiple placements coordinated by one zone;
- group activation;
- shared leash space;
- one-slot ordinary-enemy pressure and deterministic attack handoff;
- persistent clearing only after both enemies are defeated;
- combat on a larger scrolling map.

## Automated verification

The strict Godot 4.6.2 gate now covers:

1. direct loading and compilation of the runtime, all editor plugins and critical resources;
2. project import with logged parser errors treated as failures;
3. complete campaign, map, catalog, placement and encounter-zone validation;
4. world traversal and cross-map smoke tests;
5. reusable object and base-combat smoke tests;
6. Combat Director smoke tests for activation, target locking and stagger interruption, ordinary-enemy pressure handoff, windup, damage, knockback, leash return and zone clearing.

Run the same gate from Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

## Future extensions

The current contracts are intended to support later additions without replacing authored content:

- ranged attacks and projectiles;
- directional defence, dodge and invulnerability windows;
- authored enemy roles and richer coordinated group tactics beyond the baseline pressure slot;
- encounter phases and reinforcement waves;
- capability and quest-gated activation;
- boss arenas and phase transitions;
- encounter-specific music and ambience;
- authored camera framing;
- drops and loot tables;
- difficulty profiles and accessibility assists;
- automated reachability, damage and softlock probes;
- save-profile persistence for defeated placements and cleared zones.

Every extension should preserve the same rule: editor, validator, runtime and executable tests consume one shared authored contract.
