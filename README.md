# Epochbound

Epochbound is an original Godot 4.6.2 action RPG and campaign-authoring platform designed with the pacing, readability, tactile movement and authored surprise of a premium lost 1990s console adventure.

It learns from the design strengths of classic action RPGs and timeline-spanning adventures while using an entirely original world, cast, narrative, terminology, artwork and audio.

## Current playable flow

The repository now provides:

1. EVAVO Studio splash and animated title flow
2. Built-in and installed custom campaign browser
3. Validated campaign loading and campaign-defined prologues
4. Variable-size scrolling exploration maps
5. Responsive eight-direction movement with authored collision
6. A campaign-defined animal companion with commands, navigation, recovery, discovery and combat assistance
7. Contextual interactions and era-specific dialogue
8. Shifting between mechanically different versions of the same location
9. Named map entries and validated cross-map connections
10. Reusable props, NPCs, enemies and pickups authored outside engine code
11. Solid placed objects and persistent session state
12. Player action attacks, telegraphed enemy attacks, damage, stagger and knockback
13. Authored encounter zones with activation, patrol, pursuit, leash return and clearing
14. Follow, Stay, Seek, Guard and dedicated Recall companion behaviour
15. Era-scoped scent, clue, trail, warning and resource discoveries
16. Bidirectional travel between Bellweather Crossing and Clockwood Edge
17. Pause, resume and safe transition flow

The runtime currently uses Godot drawing primitives so it remains executable before final artwork exists. These placeholders establish composition, scale, timing, camera, traversal, encounter, companion and interaction contracts for the future pixel-art pipeline.

## Campaign Studio

The **Campaign** main-screen editor can:

- create campaigns and world-builder-ready starter maps;
- create and browse additional maps;
- preview every authored era;
- paint terrain with era-specific or shared brushes;
- paint and erase collision cells;
- paint companion navigation cells;
- zoom and pan around maps of different sizes;
- toggle collision, navigation and marker overlays;
- place player and companion spawns;
- add and edit interactions and era-specific dialogue;
- add named entry points and companion arrival positions;
- add recovery anchors that prevent companion softlocks;
- add validated interact or touch connections between maps;
- undo and redo map edits;
- validate the complete campaign before play.

### Campaign canvas controls

| Action | Input |
| --- | --- |
| Paint or place | Left mouse button |
| Erase current scoped cell | Right mouse button |
| Pan canvas | Middle mouse drag |
| Zoom canvas | Mouse wheel |

## Encounter Studio

The **Encounter** main-screen editor works on the same campaign and map records. It can:

- create reusable object types;
- define props, NPCs, enemies and pickups;
- configure blockout appearance, solidity and interaction radii;
- author NPC and prop dialogue without flattening era-specific variants;
- configure enemy health, movement, awareness, attack range, damage, cooldown and rewards;
- configure pickup values and messages;
- place instances visually on any map;
- restrict placements to selected eras;
- set facing and stable persistent-state keys;
- select, inspect, move, replace and delete placements;
- block unsafe object deletion while placements still reference it;
- undo and redo map-placement edits;
- validate every catalog and placement before saving.

Campaign object types are stored in catalog files such as `objects/core.json`. Maps reference them through `object_placements`, so one authored type can be reused across the entire campaign without copying its rules.

## Combat Director

The **Combat** main-screen editor turns placed enemies into authored encounters rather than independent chase agents. It can:

- place and select encounter zones visually;
- set combat, activation and leash radii;
- assign stable enemy placements to a zone;
- scope zones to particular eras;
- author persistent encounter-clear keys;
- tune enemy patrol radius and explicit leash overrides;
- tune attack windup, target memory and return speed;
- tune stagger, knockback and contact response;
- undo and redo zone changes;
- validate zones, enemy assignments and behaviour values before play.

The runtime supports deterministic idle patrol, zone activation, pursuit, visible attack windup, stagger, directional knockback and return-to-spawn behaviour. Enemies stop pursuing outside their authored leash, while cleared encounters publish stable state keys for later save-profile persistence.

Reference proofs include the Ashen-only **East Ash Hunt** in Bellweather Crossing and the two-enemy **Clockwood Hound Pair** in Clockwood Edge.

## Companion Studio

The **Companion** main-screen editor turns the animal companion into an authored exploration and reliability system. It can:

- configure the companion name and maximum health;
- choose the available command cycle;
- tune follow, guard and recovery distances;
- tune seek radius, seek speed and Guard assistance range;
- place scent, clue, trail, resource and warning cues visually;
- author discovery messages and one-time rewards;
- hide cues until the companion finds them;
- scope discoveries to selected eras;
- assign stable persistent state keys;
- select, inspect, move and delete cues;
- undo and redo cue edits;
- validate the complete companion profile and discovery layer.

The player can cycle **Follow**, **Stay**, **Seek** and **Guard**, while **Recall** remains a dedicated safety action. Seek selects only the nearest unresolved cue available in the current era and returns to Follow after discovery. Stay suppresses automatic combat movement, Guard keeps the companion closer and extends assistance range, and Recall resolves an authored safe position near the player.

The reference campaign includes four companion discoveries across Bellweather Crossing and Clockwood Edge, with different clues in the Verdant and Ashen eras.

## Content locations

Source campaigns live under `res://campaigns`. Installed player campaigns are discovered under `user://campaigns`.

Read:

- [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md) for the map editor workflow;
- [`docs/WORLD_BUILDER.md`](docs/WORLD_BUILDER.md) for map-production and quality rules;
- [`docs/ENCOUNTER_STUDIO.md`](docs/ENCOUNTER_STUDIO.md) for reusable objects and placement authoring;
- [`docs/COMBAT_DIRECTOR.md`](docs/COMBAT_DIRECTOR.md) for encounter zones, behaviour direction and combat-quality gates;
- [`docs/COMPANION_STUDIO.md`](docs/COMPANION_STUDIO.md) for commands, scent cues, recovery and companion-quality gates;
- [`docs/OBJECT_FORMAT.md`](docs/OBJECT_FORMAT.md) for the reusable object and placement contract;
- [`docs/CAMPAIGN_FORMAT.md`](docs/CAMPAIGN_FORMAT.md) for the campaign and world-map contract.

## Run

Open `project.godot` in Godot 4.6.2 and press **F6** or **F5**.

### Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | WASD or arrow keys | D-pad or left stick |
| Attack | Space or C | East face button |
| Confirm, interact or use entrance | E or Z | South face button |
| Shift era | Q or X | West face button |
| Cycle companion command | R | North face button |
| Recall companion | F | Left shoulder button |
| Back, pause or skip | Escape | Start |

## Validate

From Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

The validation gate performs:

1. direct loading and compilation of the runtime, critical resources and all four editor plugins;
2. headless project import with logged parser and plugin errors treated as failures;
3. complete campaign, map, object-catalog, placement, encounter-zone, companion-profile and cue validation;
4. executable terrain, collision, navigation, recovery and cross-map smoke tests;
5. executable object-catalog, placement, persistence and base-combat smoke tests;
6. executable zone activation, windup, damage, stagger, leash return and clear-state smoke tests;
7. executable companion command, Stay, Seek, discovery, reward-idempotence, Guard and Recall smoke tests.

## Design pillars

- A loyal animal companion who is useful in exploration, combat and story
- Multiple versions of places whose changes matter mechanically
- Fast, readable real-time action combat without input clutter
- Dense environmental storytelling, puzzles, secrets and optional discoveries
- Cinematic sequences that respect player control and can be skipped
- Distinct regional systems instead of repeated content with new colours
- Strong authored pacing supported by data-driven production tools
- Authentic low-resolution presentation with modern accessibility and reliability
- Campaign creation that remains portable, inspectable and safe to validate
- Level design that treats collision, companion routes, entrances and recovery as one authored system
- Encounters built from reusable definitions, stable map instances and explicit spatial direction
- Damage that follows readable timing and feedback instead of unexplained contact
- Companion behaviour that communicates relationship and information rather than merely following the player

## Documentation

- [`docs/GAME_VISION.md`](docs/GAME_VISION.md): originality and player promise
- [`docs/GAME_DESIGN_RESEARCH.md`](docs/GAME_DESIGN_RESEARCH.md): research synthesis and map-quality rubric
- [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md): editor workflow and authoring surfaces
- [`docs/WORLD_BUILDER.md`](docs/WORLD_BUILDER.md): terrain, navigation and connection production rules
- [`docs/ENCOUNTER_STUDIO.md`](docs/ENCOUNTER_STUDIO.md): object and placement production rules
- [`docs/COMBAT_DIRECTOR.md`](docs/COMBAT_DIRECTOR.md): directed combat and encounter production rules
- [`docs/COMPANION_STUDIO.md`](docs/COMPANION_STUDIO.md): companion command and discovery production rules
- [`docs/OBJECT_FORMAT.md`](docs/OBJECT_FORMAT.md): object catalog, placement and persistent-state schema
- [`docs/CAMPAIGN_FORMAT.md`](docs/CAMPAIGN_FORMAT.md): campaign and map schema and migration rules

## Next production layers

The next vertical slices will build on the current contracts rather than replace them: items and inventory, crafting and recipe discovery, dialogue and quest graphs, deterministic world state, save profiles, ranged attacks, bosses, cinematics, campaign packaging and automated reachability, companion-recovery, damage and softlock probes.
