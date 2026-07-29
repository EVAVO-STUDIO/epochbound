# Epochbound Save & State Studio

Save & State Studio is the durable-progress layer for Epochbound campaigns.

It sits beside the existing Godot production tools:

- **Campaign Studio** authors maps, eras, collision, navigation and travel.
- **Encounter Studio** defines reusable objects and stable map placements.
- **Combat Director** produces enemy defeat and encounter-clear state.
- **Companion Studio** produces discoveries, commands and recovery state.
- **Item Forge** defines inventory, stack limits, recipes and item rewards.
- **Story Studio** defines conversations, quest stages, typed conditions and rewards.
- **Save & State Studio** validates, inspects, migrates and manages the durable outcome of all those systems.

The save layer does not create a parallel gameplay database. It serialises the same stable IDs and persistent state keys already consumed by the runtime, validators and other editors.

## Design goals

The save system follows these production rules:

1. A save profile is versioned data with an explicit schema number.
2. Durable gameplay state is separated from transient presentation and combat timing.
3. Save writes use temporary files, promotion and rotating backups rather than writing directly over the only valid copy.
4. Every complete profile carries a deterministic SHA-256 checksum.
5. A checksum detects accidental corruption or unreviewed mutation; it is not a security or anti-cheat signature.
6. Older supported schemas migrate through explicit transformations.
7. Newer unknown schemas are rejected rather than guessed.
8. Profiles validate against the installed campaign before they can alter runtime state.
9. Manual saving is blocked during unsafe combat by default.
10. Loading re-resolves map collision, authored recovery and active runtime entities.
11. Autosave uses the same profile contract as manual slots.
12. Save files remain player data under `user://`; they are never written into campaign source directories.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **State** main-screen tab.
3. Choose a source campaign.
4. Review the campaign’s save policy.
5. Select an occupied autosave or manual slot.
6. Review its schema, checksum, timestamp, reason, location and play time.
7. Inspect inventory, quest progress and durable world-state keys.
8. Validate the profile against the current campaign definitions.
9. Rewrite a supported legacy profile to the current schema when required.
10. Delete an obsolete slot and its backup when appropriate.
11. Open the campaign’s save folder for manual support or debugging.
12. Run the campaign and verify save, load, Continue and backup recovery from the player’s perspective.

## Player workflow

The title screen exposes **Continue** when at least one valid installed-campaign profile exists.

During normal gameplay:

| Action | Keyboard | Controller |
| --- | --- | --- |
| Open or close Save Profiles | `K` | Left stick click |
| Change Save or Load mode | Left / Right | D-pad Left / Right |
| Select a slot | Up / Down | D-pad Up / Down |
| Confirm save or load | E, Z, Space or C | South or East face button |
| Close | Escape or K | Left stick click |

The reference campaign provides:

- one managed autosave slot;
- three manual save slots.

Autosave cannot be overwritten manually from the slot interface. It is managed by the runtime’s authored policy.

## Campaign save policy

Each campaign declares a `save_policy` object:

```json
{
  "save_policy": {
    "manual_slots": 3,
    "autosave_enabled": true,
    "autosave_on_travel": true,
    "autosave_on_progress": true,
    "allow_manual_save_in_combat": false
  }
}
```

### Manual slots

`manual_slots` controls how many numbered manual profiles the campaign exposes.

Current accepted range:

- minimum: `1`;
- maximum: `9`.

The stable IDs are:

```text
slot_1
slot_2
...
slot_9
```

Changing the number of visible slots does not rename existing profile IDs. Reducing the count hides higher slots from the normal runtime interface but does not silently delete their files.

### Autosave enabled

`autosave_enabled` determines whether the campaign exposes the managed `autosave` slot.

When false, travel and progress trigger fields should also be false. Validation warns when trigger fields are enabled while autosave itself is disabled.

### Autosave on travel

`autosave_on_travel` requests a checkpoint after:

- a validated cross-map transition;
- an era shift.

The write is deferred until the runtime is outside dialogue, transitions, menus and active combat.

### Autosave on progress

`autosave_on_progress` observes a canonical fingerprint of durable progression:

- current map ID;
- current era ID;
- inventory;
- unlocked recipes;
- durable session state;
- quest progress;
- clock-shard total.

A changed fingerprint requests an autosave. Actor movement alone does not trigger continuous disk writes.

### Manual saving in combat

`allow_manual_save_in_combat` defaults to `false`.

The runtime treats enemies in chase, attack windup or stagger states as active combat. Manual saving remains unavailable until the encounter is stable. This prevents profiles from capturing ambiguous half-attacks while still allowing campaigns to opt into a more permissive model deliberately.

## Save location

Profiles are stored under Godot’s user-data directory:

```text
user://save_profiles/<campaign_id>/<slot_id>.json
```

For example:

```text
user://save_profiles/epochbound_demo/autosave.json
user://save_profiles/epochbound_demo/slot_1.json
user://save_profiles/epochbound_demo/slot_2.json
user://save_profiles/epochbound_demo/slot_3.json
```

Because Epochbound uses a custom user directory name, the operating-system path is isolated under the application’s EVAVO/Epochbound data directory.

Source campaigns under `res://campaigns` and installed campaigns under `user://campaigns` remain separate from player profile storage.

## Profile root contract

A current save profile has this shape:

```json
{
  "schema_version": 1,
  "profile_id": "epochbound_demo:slot_1",
  "campaign_id": "epochbound_demo",
  "slot_id": "slot_1",
  "metadata": {},
  "payload": {},
  "checksum": "..."
}
```

### Schema version

`schema_version` identifies the save-profile format, not the campaign-content format.

The current save schema is `1`.

A profile with a version newer than the runtime supports is rejected with a compatibility error. The runtime does not reinterpret unfamiliar fields or silently discard unknown progress.

### Profile ID

`profile_id` is derived from the campaign and slot:

```text
<campaign_id>:<slot_id>
```

It must agree with `campaign_id` and `slot_id` during validation.

### Campaign ID

`campaign_id` links the profile to one installed campaign. Continue resolves that ID against the current built-in and installed campaign catalogue.

A profile is not loaded into a campaign with a different ID, even if both campaigns happen to contain similarly named maps or items.

### Slot ID

Accepted slot IDs are:

- `autosave`;
- `slot_1` through `slot_9`.

Slot identifiers are stable path-safe values, not player-facing labels.

## Metadata contract

Metadata summarises a profile without becoming authoritative gameplay state.

Typical fields:

```json
{
  "saved_at_unix": 1785312000,
  "play_time_seconds": 3723.5,
  "reason": "Travelled to Clockwood Edge",
  "map_id": "clockwood_edge",
  "map_name": "Clockwood Edge",
  "era_id": "ashen",
  "era_name": "Ashen Age",
  "active_quest_count": 1,
  "completed_quest_count": 2
}
```

Player-facing labels may become stale if campaign copy changes. Runtime restoration uses IDs from the payload, not display names from metadata.

## Durable payload contract

The payload records state required to resume the campaign coherently:

```json
{
  "map_id": "clockwood_edge",
  "era_id": "ashen",
  "player_position": {"x": 80, "y": 232},
  "companion_position": {"x": 112, "y": 248},
  "facing": {"x": 1, "y": 0},
  "player_health": 23,
  "companion_health": 17,
  "clock_shards": 7,
  "inventory": {},
  "unlocked_recipes": [],
  "session_state": {},
  "quest_progress": {},
  "companion_command": "stay",
  "companion_hold_position": {"x": 112, "y": 248}
}
```

### Map and era

`map_id` must resolve through the campaign’s declared map files.

`era_id` must exist on that map. A profile cannot restore an era merely because the same era ID exists elsewhere in the campaign.

### Actor positions

Player, companion and hold positions are stored as numeric `x` and `y` values.

On load, positions are:

1. read from the validated payload;
2. checked against map bounds;
3. checked against authored terrain and collision;
4. recovered through map recovery anchors when required;
5. checked against active solid runtime entities.

The system preserves exact safe positions while refusing to recreate a softlock from invalid or changed geometry.

### Facing

Facing is stored as a two-dimensional direction. A zero direction is normalised to down during restoration.

### Health

Player and companion health must be positive and cannot exceed the current campaign actor maximums.

The first save schema does not preserve a defeated player state. Loading always resumes from a viable checkpoint.

### Clock shards

Clock shards are stored as a non-negative integer.

### Inventory

Inventory remains the same Item Forge dictionary:

```json
{
  "museum_tonic": 1,
  "brass_filings": 4,
  "clockglass_fragment": 2
}
```

Each ID must still exist in the campaign. Quantities must remain positive and within the current item stack limit.

### Unlocked recipes

Learned recipes are stored as a sorted array of stable recipe IDs:

```json
[
  "clockglass_lens_recipe",
  "ember_salve_recipe"
]
```

Unknown or repeated IDs are rejected.

### Session state

`session_state` contains durable cross-system keys produced by the existing authoring tools:

- collected pickup states;
- defeated enemy states;
- cleared encounter-zone states;
- companion discoveries;
- story flags and quest outcomes.

Example:

```json
{
  "bellweather:clock_shard": "collected",
  "bellweather:zone:east_ash_hunt": "cleared",
  "clockwood:companion:cold_ash_cache": "discovered",
  "story:missing_hour:completed": true
}
```

Keys must be non-empty strings. Values must be representable safely in JSON.

### Quest progress

Quest state uses the same Story Studio records already consumed at runtime:

```json
{
  "the_missing_hour": {
    "status": "active",
    "stage_id": "forge_the_lens"
  }
}
```

Accepted statuses:

- `not_started`;
- `active`;
- `completed`.

Active and completed records must reference an existing stage in the current quest definition.

### Companion command

Only commands that can resume safely are persisted:

- `follow`;
- `stay`;
- `guard`.

Seek is transient because its target depends on currently unresolved, era-specific map cues. A save captured while Seek is active stores Follow instead.

## Transient state that is intentionally reset

The following states are not persisted:

- an open conversation node;
- current response selection;
- dialogue-box presentation;
- open inventory, Journal or save overlays;
- attack cooldowns;
- attack windups;
- knockback velocity;
- stagger timers;
- hit flashes;
- camera shake;
- temporary HUD notices;
- active seek target;
- transition fade progress;
- enemy runtime positions and short-term pursuit modes.

These values describe presentation or incomplete simulation frames rather than durable campaign outcomes.

Enemies are re-instantiated from authored placements and persistent defeat keys. Quests are restored from their stable status and stage IDs. This produces a reliable resume point rather than attempting to serialise every node in the live scene tree.

## Deterministic canonicalisation

Before hashing or writing, save data is canonicalised recursively:

- dictionary keys are sorted;
- arrays preserve authored order;
- packed primitive arrays become normal JSON arrays;
- `Vector2` and `Vector2i` values become numeric `{x, y}` objects;
- unsupported engine objects are rejected.

Canonicalisation ensures that logically identical state produces the same unsigned JSON representation even when dictionary insertion order differs.

## Checksum and integrity

The checksum is calculated as SHA-256 over the canonical profile without the `checksum` field.

Validation rejects a profile when:

- the checksum is missing;
- the checksum does not match the current durable state.

This protects against truncated writes, accidental hand edits and unnoticed file corruption.

It is not a cryptographic authenticity guarantee because the checksum is unkeyed and the algorithm is part of the open-source runtime. A user who intentionally edits a profile can calculate another valid checksum. Competitive anti-cheat is outside this system’s purpose.

## Atomic write sequence

A save write follows this sequence:

1. Build the complete profile in memory.
2. Validate its structure and checksum.
3. Write the complete JSON to `<slot>.json.tmp`.
4. Flush and close the temporary file.
5. Remove an older backup if one exists.
6. Rename the current `<slot>.json` to `<slot>.json.bak`.
7. Rename the temporary file to `<slot>.json`.
8. Restore the backup if promotion fails.

The runtime never intentionally streams a new profile directly over the only valid slot file.

## Backup recovery

When the promoted slot cannot be parsed, migrated or validated, loading checks the rotated `.bak` file.

A successful fallback is reported as `recovered_from_backup` so the runtime and State Studio can communicate what happened.

The backup represents the previous complete checkpoint, not a copy of the newly promoted profile.

## Migration

The current migration layer supports legacy schema `0`.

Schema `0` stored several durable fields directly on the root profile. Migration moves them into the schema-1 metadata and payload records, normalises recipe unlocks, adds safe companion state and calculates a new checksum.

Migration rules:

- operate on a duplicate of the source record;
- never guess a future schema;
- preserve stable campaign, map, era, item, quest and state identifiers;
- validate the migrated result against the installed campaign;
- rewrite only after validation succeeds;
- rotate the previous file into a backup during rewrite.

## Continue flow

The title-screen Continue command searches all valid profiles from installed campaign IDs and selects the most recently saved checkpoint by timestamp.

Continue refuses to load when:

- no valid profile exists;
- the profile’s campaign is not installed;
- the profile is from a newer schema;
- checksum validation fails;
- campaign-bound validation fails.

A failed Continue attempt leaves the current title state intact and reports an error rather than partially applying profile data.

## Runtime restoration sequence

Loading a profile follows this order:

1. Read the promoted slot or a valid backup.
2. Migrate a supported legacy schema in memory.
3. Validate profile structure and checksum.
4. Resolve the installed campaign by stable campaign ID.
5. Validate the profile against current campaign maps, eras, actors, items, recipes and quests.
6. Load the campaign catalogs.
7. Restore inventory, recipes, world state, quest progress, health and shards.
8. Activate the saved map and era without a travel autosave.
9. Restore actor positions and safe facing.
10. Recover actors from changed collision or solid placements when needed.
11. Restore a safe companion command and hold point.
12. Rebuild runtime entities from authored placements plus durable state.
13. Reevaluate ready quest objectives.
14. Clear transient conversations, menus and notices.
15. Resume the game flow.

The runtime uses a save-operation guard so loading cannot recursively trigger travel autosaves or reset the state being restored.

## Autosave behaviour

Autosave requests are deferred rather than written immediately inside another state mutation.

A pending autosave flushes only when:

- the game flow is active;
- no inventory, Journal or save overlay is open;
- no conversation or ordinary dialogue is open;
- no transition is active;
- the player is alive;
- no directed enemy is in active combat.

A failed autosave retains its pending reason so a later safe frame can retry.

## Save & State Studio inspector

The State editor exposes five views.

### Overview

Shows:

- slot label;
- campaign ID;
- schema version;
- checksum status;
- timestamp;
- save reason;
- map and era;
- play time;
- actor health;
- clock-shard total;
- inventory stack count;
- active and completed quest counts;
- durable state-key count;
- full profile ID and checksum.

### Inventory

Shows every stored item stack with:

- current display name where available;
- quantity;
- stable item ID.

### Quests

Shows every persisted quest record with:

- current display title where available;
- status;
- stage ID;
- stable quest ID.

### World State

Shows deterministic key/value rows sorted by state key.

### Raw JSON

Shows the complete canonical profile for support, review and migration debugging. The editor view is read-only.

## Validation rules

Campaign save-policy validation rejects:

- non-object policies;
- manual slot counts outside 1 to 9;
- non-boolean policy flags.

Profile validation rejects:

- unsupported schema versions;
- missing campaign or slot IDs;
- inconsistent profile IDs;
- invalid metadata;
- invalid or missing payload fields;
- missing or mismatched checksums;
- unknown maps or eras;
- actor positions outside the map canvas;
- health outside current campaign limits;
- negative clock shards;
- unknown inventory items;
- invalid inventory quantities or stack overflow;
- unknown or repeated recipe unlocks;
- empty durable state keys;
- non-JSON-safe durable values;
- unknown quests;
- unsupported quest statuses;
- unknown quest stages;
- unsafe companion commands.

Warnings cover unusual but recoverable conditions such as a zero facing direction or autosave triggers enabled while autosave itself is disabled.

## Production quality gates

### Durability

- A completed write leaves either the new slot or the previous backup recoverable.
- Loading never mutates runtime state before validation succeeds.
- A failed migration preserves the original file.
- A failed autosave does not discard the pending checkpoint request.
- Profile deletion removes the promoted slot, backup and abandoned temporary file.

### Determinism

- Equivalent durable state produces identical canonical unsigned JSON.
- Unlocked recipe ordering is stable.
- Inventory and world-state inspector ordering is stable.
- Runtime restoration rebuilds transient entities from authored definitions and persistent outcomes.

### Compatibility

- Stable IDs remain unchanged across display-copy edits.
- Campaign changes that invalidate profiles fail with explicit references.
- Unknown future schemas fail closed.
- Supported legacy schemas migrate through reviewed transformations.

### Player experience

- Continue communicates when no profile is available.
- Save and load use a keyboard/controller-operable overlay.
- Autosave does not interrupt dialogue or active combat.
- Slot summaries identify map, era and play time before loading.
- Manual save is available without requiring pointer input.
- Corrupt promoted files recover from backups where possible.

### Accessibility

- Checksum, validity and slot state use text rather than colour alone.
- Save and load modes have explicit labels.
- Every profile detail is available through text lists.
- The inspector does not depend on hovering graph nodes or tiny icons.

## Automated verification

The official Godot 4.6.2 gate checks:

1. direct compilation of the save runtime, profile model, store, validator, State Studio and all inherited systems;
2. strict project import with parser and plugin errors treated as failures;
3. campaign save-policy validation;
4. deterministic profile capture and checksum generation;
5. atomic profile writing;
6. exact restoration of map, era, positions, health, inventory, recipes, world state, quests, companion mode, shards and play time;
7. schema-0 migration;
8. future-schema rejection;
9. checksum-mismatch rejection;
10. rotated-backup recovery after promoted-file corruption;
11. State Studio campaign, slot, overview, inventory, quest, world-state and raw-JSON inspection.

Run the same gate locally:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

## Support workflow

When a player reports a broken save:

1. Keep both the `.json` and `.json.bak` files.
2. Do not open and resave them in an editor before preserving copies.
3. Select the campaign and slot in State Studio.
4. Check schema and checksum status.
5. Run campaign-bound validation.
6. Note whether backup recovery was used.
7. Inspect unknown item, recipe, quest, map, era or state references.
8. Apply a reviewed migration only when the source schema is supported.
9. Revalidate before replacing the player’s active slot.

## Future extensions

The current contracts are designed to support:

- profile thumbnails captured from the blockout or final renderer;
- platform cloud-save synchronisation;
- campaign package/version fingerprints;
- explicit content migrations for renamed IDs;
- per-profile accessibility and difficulty settings;
- save-point-only campaign modes;
- ironman profiles;
- profile import and export;
- compressed payloads;
- user-facing backup selection;
- equipment and merchant state;
- procedural seed state;
- co-op or multiplayer authority models;
- automated campaign-update compatibility matrices;
- long-run save/load soak testing.

Those features should extend the same versioned profile and stable campaign identifiers rather than introducing a second persistence system.
