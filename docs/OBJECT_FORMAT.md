# Object Catalog and Placement Contract

Epochbound separates reusable object definitions from map placements.

- A **definition** describes what a prop, NPC, enemy or pickup is.
- A **placement** describes one stable instance on one map.

This separation lets authors tune one reusable object type without copying combat, dialogue, collision or appearance rules into every map.

## Campaign declaration

Campaign manifests declare one or more safe relative object-catalog paths:

```json
{
  "object_files": [
    "objects/core.json"
  ]
}
```

Paths must:

- be relative to the campaign directory;
- use the `.json` extension;
- avoid parent traversal;
- avoid absolute paths and URL protocols.

Definitions are merged in declared file order. Object IDs must remain unique across every catalog in the campaign.

## Catalog root

```json
{
  "schema_version": 1,
  "objects": []
}
```

The current catalog schema version is `1`. Unsupported versions fail validation rather than being interpreted silently.

## Shared definition fields

Every object definition contains:

```json
{
  "id": "lost_archivist",
  "display_name": "Lost Archivist",
  "kind": "npc",
  "appearance": {
    "shape": "person",
    "color": "526b82",
    "accent": "e4c39e"
  },
  "solid": true,
  "collision_radius": 9,
  "interaction_radius": 46
}
```

### `id`

The stable identifier used by map placements, state records and future quest or save references. It uses lowercase letters, numbers, underscores and hyphens.

The current editor deliberately does not rename existing IDs. A future rename tool must update every reference atomically.

### `display_name`

Player-facing or editor-facing presentation text. It may change without breaking references.

### `kind`

Supported values:

- `prop`
- `npc`
- `enemy`
- `pickup`

### `appearance`

Current blockout appearance fields:

- `shape`
- `color`
- `accent`

Supported blockout shapes:

- `crate`
- `person`
- `beast`
- `orb`
- `pillar`
- `marker`

Colours are validated HTML hexadecimal strings. Final sprite, animation, sound and effects references can extend this record later without changing object identity.

### `solid`

Determines whether the runtime treats the placed object as actor collision.

### `collision_radius`

The circular solid footprint used by player, companion and enemy movement. It cannot be negative.

### `interaction_radius`

The distance within which a prop, NPC or pickup can be interacted with or collected. It cannot be negative.

## Props

A prop may provide a single dialogue or description string:

```json
{
  "id": "brass_supply_crate",
  "kind": "prop",
  "dialogue": "A museum crate stamped with an impossible delivery date."
}
```

It may instead provide era-keyed text:

```json
{
  "dialogue": {
    "verdant": "The brass corners are warm despite the rain.",
    "ashen": "Only the brass corners remain suspended in ash.",
    "default": "A shipping crate marked with an impossible date."
  }
}
```

Encounter Studio edits the currently selected era without discarding other era entries.

## NPCs

NPCs currently use the shared fields and dialogue contract. They are stationary conversational actors in this slice.

Future additions should extend the same stable definition with references to:

- dialogue graphs;
- schedules;
- factions;
- quests;
- movement or behaviour profiles;
- portraits and animation sets.

## Enemies

Enemy definitions add:

```json
{
  "max_health": 12,
  "move_speed": 58,
  "awareness_radius": 132,
  "attack_radius": 20,
  "attack_damage": 4,
  "attack_cooldown": 1.05,
  "reward": 2
}
```

All combat timing and distance fields must be positive. `reward` may be zero or greater.

The current runtime uses these fields for:

- activation when a player-side actor enters awareness range;
- navigation-aware pursuit;
- attack range and cooldown;
- damage;
- health and defeat;
- Clock Shard reward count.

Later behaviour profiles should reference reusable state-machine or ability data rather than overloading this core definition.

## Pickups

Pickup definitions add:

```json
{
  "pickup_value": 1,
  "pickup_label": "Clock shard recovered."
}
```

`pickup_value` must be at least one and `pickup_label` must contain text.

The current runtime records pickup state and increments the campaign's temporary shard counter. A future inventory system should reference stable item IDs rather than embedding full item data in placements.

## Map placements

Maps contain a sparse `object_placements` array:

```json
{
  "object_placements": [
    {
      "id": "crossing_archivist",
      "object_id": "lost_archivist",
      "position": {"x": 232, "y": 192},
      "facing": "right",
      "available_eras": ["verdant"],
      "state_key": "bellweather:archivist"
    }
  ]
}
```

### Placement `id`

Unique within the map. It identifies this instance for editing and provides the default persistent state key.

### `object_id`

Must resolve to exactly one definition declared by the campaign.

### `position`

A world-space position inside the map canvas.

### `facing`

Supported values:

- `up`
- `down`
- `left`
- `right`

### `available_eras`

An empty array means every era. A non-empty array restricts the instance to declared era IDs.

```json
{"available_eras": ["ashen"]}
```

Changing era re-resolves active placements. Runtime state is preserved for instances that remain available, while newly available instances begin at their authored positions.

### `state_key`

An optional campaign-wide persistent key. When empty, the runtime derives:

```text
map_id:placement_id
```

State keys must be unique across the campaign unless future schema explicitly introduces shared-state groups.

The current session stores:

- `defeated` for enemies;
- `collected` for pickups.

An explicit shared key can intentionally represent one conceptual object across multiple era-specific placements, but the current validator rejects duplicate keys. That capability should only be introduced alongside an explicit grouping contract and deterministic resolution rules.

## Runtime resolution

For the active map and era, the runtime:

1. reads every placement;
2. filters by `available_eras`;
3. resolves `object_id` against the merged campaign catalogs;
4. derives or reads the persistent state key;
5. skips defeated enemies and collected pickups;
6. creates a runtime entity with authored position, facing and definition data.

Runtime-only fields such as current health, movement position, cooldowns and hit flash are not written back into campaign JSON.

## Era transitions

When the player changes era:

- globally available placements remain active;
- placements unavailable in the next era are removed from the runtime set;
- placements newly available in the next era are instantiated;
- surviving matching placement IDs retain runtime health, position, facing and cooldown state;
- persistent defeated or collected state takes precedence.

This prevents an enemy from fully healing merely because the player shifted eras while that same placement remains active.

## Map travel

When travelling to another map:

- the previous map's runtime entities are discarded;
- the target map resolves its own placements;
- campaign session state prevents defeated enemies and collected pickups from returning;
- player and companion arrival still use the target entry point contract.

Future save profiles will serialise persistent keys and campaign content-version metadata, not the complete runtime entity objects.

## Validation guarantees

The full validator rejects:

- unsafe catalog paths;
- unsupported catalog schema versions;
- duplicate object definition IDs;
- unsupported kinds or shapes;
- invalid colours;
- negative radii;
- incomplete or invalid enemy statistics;
- incomplete pickup records;
- non-array placement collections;
- duplicate placement IDs;
- unknown object references;
- positions outside the map canvas;
- unsupported facing values;
- unknown era references;
- state keys longer than 160 characters;
- duplicate persistent state keys across the campaign.

Warnings identify:

- empty catalogs;
- unused definitions;
- enemies placed on maps without navigation cells;
- placements that begin in blocked terrain or collision.

## Schema evolution

Object catalogs and maps each retain their own `schema_version`.

Migration rules:

1. Migrate one version at a time.
2. Validate a migrated copy before replacing original content.
3. Preserve stable object IDs, placement IDs and state keys.
4. Never silently reinterpret combat or persistence fields.
5. Keep campaign definitions separate from player save state.
6. Add new optional fields only when older records have an unambiguous default.

## Future object contracts

The next compatible extensions should include:

- sprite, animation, sound and effects references;
- reusable item and loot-table IDs;
- enemy behaviour-profile IDs;
- NPC dialogue-graph and schedule IDs;
- conditional availability beyond era scope;
- encounter-group membership;
- object variants and inheritance with deterministic validation;
- explicit shared-state groups;
- versioned save migration for persistent state keys.
