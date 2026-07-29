# Epochbound Encounter Studio

Encounter Studio is the reusable-object and map-instance authoring surface for Epochbound campaigns. It appears as the **Encounter** main-screen tab in Godot 4.6.2.

The editor separates two ideas that should not be confused:

- an **object type** defines reusable rules and blockout presentation;
- an **object placement** puts one stable instance of that type on a map.

This lets one enemy, NPC, pickup or prop definition be reused across many maps and eras while every placed instance retains its own position, facing, availability and persistent state key.

## Current workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Encounter** tab.
3. Choose a source campaign, map and era.
4. Create or select a reusable object type in the left catalogue.
5. Configure the type in the **Object Type** inspector.
6. Choose **Place Object** and select an object type from the toolbar.
7. Click the map to place an instance.
8. Switch to **Select** and click a placement to edit it.
9. Use the **Placement** inspector to change its stable ID, object type, position, facing, state key or era scope.
10. Select **Validate All** before running the campaign.
11. Run the game and test the encounter in every available era and from every relevant entrance.

The Encounter canvas inherits the same map framing, zoom, pan, terrain, collision, navigation and marker rendering as Campaign Studio. This keeps encounter placement grounded in the actual traversal contract rather than a disconnected preview.

## Object types

Object types live in campaign object-catalog JSON files, normally `objects/core.json`.

Supported kinds are:

- `prop`
- `npc`
- `enemy`
- `pickup`

Every object type contains:

- a stable identifier;
- a display name;
- a kind;
- a blockout shape and two colours;
- solidity;
- collision radius;
- interaction radius.

Kind-specific fields extend this shared base.

### Props

Props are static authored objects. A prop may be solid and may provide dialogue or environmental description.

Use props for:

- crates and containers;
- statues and machinery;
- furniture and large scenery pieces;
- examinable environmental storytelling;
- temporary blockout representations of future art assets.

A solid prop participates in runtime actor and enemy collision. Do not use a solid prop to conceal a mismatch between the visual map and its traversal design.

### NPCs

NPCs are currently stationary conversational actors. They may be solid, have an interaction radius and provide default or era-keyed dialogue.

The present slice deliberately establishes stable NPC identity and placement before adding schedules, dialogue graphs, quests, factions or movement behaviours.

### Enemies

Enemy definitions currently expose:

- maximum health;
- movement speed;
- awareness radius;
- attack radius;
- attack damage;
- attack cooldown;
- reward value.

Enemies pursue the nearest viable player-side actor after entering their awareness radius. They use the map's authored navigation network when available and fall back to direct steering during blockout.

The player attacks with Space or C. Morrow automatically assists when close enough to an active enemy. Enemy defeat marks the placement's persistent state key for the current session, preventing it from respawning after era or map travel.

### Pickups

Pickup definitions expose:

- pickup value;
- pickup message;
- blockout appearance;
- collection radius.

Pickups are collected when the player moves within range. Collection records the placement state key and prevents the pickup from returning during the current session.

The reference campaign uses Clock Shards as both pickups and simple combat rewards. Inventory and item-catalog systems will later separate collectible identity from generic numerical rewards.

## Blockout appearance

The current renderer supports these shapes:

- `crate`
- `person`
- `beast`
- `orb`
- `pillar`
- `marker`

Shapes are production placeholders. They provide consistent scale, collision review, silhouette and encounter readability before final sprite, animation and effects references exist.

The final art pipeline should replace appearance references while preserving the stable object and placement contracts.

## Stable identifiers

Object-type IDs cannot be renamed in the current editor after creation. This is intentional: map placements, save state and later quest records depend on those identifiers.

Display names may change freely.

Placement IDs are unique within a map and may be edited while authoring. Once a placement becomes part of persistent state, quest logic or released saves, it should also be treated as stable.

## Persistent state keys

Each placement may provide an explicit `state_key`.

When empty, the runtime derives:

```text
map_id:placement_id
```

The current session uses the key to remember:

- defeated enemies;
- collected pickups.

State keys are validated for uniqueness across the entire campaign. Explicit keys are useful when multiple era-specific placements should deliberately represent the same persistent object.

Example:

```json
{
  "id": "clockwood_shard",
  "object_id": "clock_shard",
  "position": {"x": 624, "y": 232},
  "facing": "down",
  "available_eras": [],
  "state_key": "clockwood:clock_shard"
}
```

Later save profiles will serialise these stable keys rather than copying full map or object records.

## Era scope

Placements may be global or restricted to the selected era.

Use era scope for:

- an NPC who exists only before a disaster;
- an enemy that appears only in a ruined era;
- a pickup exposed after environmental change;
- a prop whose physical presence changes across time.

An era change re-resolves the active placement set. Runtime health and movement state are preserved for placements that remain active, while newly available placements spawn from their authored positions. Defeated or collected state still takes precedence.

## Placement production rules

### Props and NPCs

- Keep interaction radii large enough for every valid approach direction.
- Avoid placing solid objects directly on required companion navigation cells unless the route deliberately bends around them.
- Ensure dialogue remains meaningful in every declared era.
- Prefer a few strong environmental objects over repetitive decorative noise.

### Enemies

- Place enemies in walkable space.
- Provide navigation cells between their spawn region and intended combat arena.
- Do not spawn enemies directly on entrances or recovery anchors.
- Keep awareness ranges consistent with the visible combat space.
- Leave enough room for player movement, Morrow and multiple enemies.
- Test attack reach against collision and solid props.

### Pickups

- Place pickups where the player can read and reach them.
- Use placement and environmental composition to explain why the item is there.
- Do not hide critical progression pickups behind untelegraphed collision.
- Confirm collection persists after map travel and era shifts.

## Combat contract

The current combat layer establishes a testable foundation:

- player attack input and cooldown;
- broad facing-based target acquisition;
- authored enemy health and damage;
- enemy awareness, pursuit and attack cooldown;
- player and companion health;
- Morrow automatic assistance;
- hit feedback and enemy health bars;
- player defeat rewind;
- companion recovery instead of permanent removal;
- enemy defeat rewards;
- stable session persistence.

It is not the final combat design. Future layers should add:

- explicit attack wind-up, active and recovery frames;
- directional hurt and knockback;
- invulnerability communication;
- weapon and item data;
- stamina or charge systems where justified;
- enemy state machines and authored behaviours;
- encounter boundaries and reset rules;
- boss phases and rehearsal tools;
- accessibility and assist settings;
- deterministic combat telemetry and replayable tests.

## Validation

Encounter validation rejects:

- unsafe or missing object-catalog paths;
- duplicate object-type IDs;
- unsupported kinds or shapes;
- invalid colours;
- negative radii;
- invalid enemy statistics;
- invalid pickup data;
- duplicate placement IDs;
- missing object references;
- placements outside the map canvas;
- invalid facing values;
- unknown era references;
- duplicate persistent state keys across the campaign.

Warnings identify incomplete but playable conditions such as unused definitions, enemies on maps without navigation, or placements that begin in blocked space.

## Safe deletion

Encounter Studio blocks deletion of an object type while any declared map still contains a placement that references it.

This avoids a common editor failure mode where a catalogue cleanup silently corrupts multiple maps. Remove or replace the placements first, validate, and then delete the unused definition.

## Undo and redo

Map placement creation, editing and deletion use a map-local history. Undo and redo restore the complete map record and run the same validation before saving.

Object-catalog changes save deliberately through the catalogue validator. Stable object IDs are not automatically rewritten because such renames require a future reference-aware migration across maps, quests, saves and world state.

## Reference encounters

### Bellweather Crossing

- A shared solid brass supply crate
- A Verdant-only Lost Archivist
- An Ashen-only Ash Hound
- A Verdant-only Clock Shard

### Clockwood Edge

- A shared supply crate
- A Verdant-only archivist
- Two Ashen-only Ash Hounds
- A shared Clock Shard

Together these prove reusable definitions, era filtering, solid-object collision, multiple enemy instances, pickup persistence and stable cross-map state.

## Next Encounter Studio layers

1. Object-library files beyond the primary editable catalogue
2. Reference-aware object and placement renaming
3. Placement duplication, box selection and transform tools
4. Patrol paths, encounter zones and spawn groups
5. Enemy behaviour profiles and state-machine authoring
6. NPC schedules, factions and dialogue-graph links
7. Loot tables, item catalogues and chest contents
8. Conditional placement and world-state rules
9. Combat rehearsal and damage-timeline tools
10. Automated encounter reachability, fairness and softlock probes

Every extension should continue to use one shared contract across editor, validator, runtime and tests.
