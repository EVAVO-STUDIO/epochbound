# Epochbound Cinematic & Timeline Studio

Cinematic & Timeline Studio authors skippable, save-safe sequences inside the Godot editor. It reuses campaign maps, actors, reusable placements, Story Studio effects, boss outcomes and durable state rather than hiding progression inside scene scripts.

## Responsibilities

The cinematic layer controls transient presentation:

- camera framing and pans;
- letterboxing and fades;
- timed or confirm-advanced dialogue;
- player, companion and placed-actor blocking;
- controlled era changes;
- authored waits and checkpoints;
- completion effects shared with Story Studio.

It does not persist a half-finished camera pan, dialogue box, fade or actor interpolation. Save profiles preserve only durable effects and completion keys.

## Editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select **Cinematic** in the main-screen toolbar.
3. Choose a campaign.
4. Add or select a stable cinematic ID.
5. Select its authored map and optional era scope.
6. Choose whether it is skippable, letterboxed and trigger-once.
7. Assign a durable completion-state key for trigger-once playback.
8. Enter one JSON step per line.
9. Add completion effects and optional skip-only effects.
10. Review the timeline preview.
11. Apply and validate the complete campaign.
12. Run the campaign and test both watched and skipped outcomes.

## Sequence contract

```json
{
  "id": "storm_door_opening",
  "display_name": "The Door Beneath Bellweather",
  "map_id": "bellweather_crossing",
  "available_eras": ["verdant"],
  "skippable": true,
  "letterbox": true,
  "trigger_once": true,
  "completion_state_key": "cinematic:storm_door_opening",
  "steps": [],
  "completion_effects": [],
  "skip_effects": []
}
```

### Stable ID

The ID is used by campaign, map-interaction and boss triggers. Renaming display text does not break references.

### Map and era scope

Every sequence is authored against one map. Optional era scope prevents a sequence from playing in an incompatible version of that location.

### Skipping

A skippable sequence may be closed with Escape or Start. Skipping:

- stops transient camera, dialogue, fade and movement state;
- applies skip-only effects;
- applies normal completion effects;
- writes the same durable completion key;
- returns control to gameplay;
- requests a safe autosave after progression settles.

Skipping must never strand the player before an essential reward, quest update, opened route or boss outcome.

### Trigger-once

A trigger-once sequence requires a completion key. Watched sequences store `completed`; skipped sequences store `skipped`. Both values prevent automatic replay.

## Timeline steps

### Wait

```json
{"id":"hold","type":"wait","duration":0.5}
```

Waits provide breathing room. They must be positive and no longer than the global safety limit.

### Dialogue

```json
{
  "id":"eli_line",
  "type":"dialogue",
  "speaker":"ELI",
  "text":"The door remembers the storm.",
  "duration":3.0,
  "advance_on_confirm":true
}
```

Text may be a string or era-keyed object. Confirm advancement allows players to read at their own pace. A duration supplies an automatic fallback.

### Camera

```json
{
  "id":"frame_sentinel",
  "type":"camera",
  "target":"placement:underworks_sentinel",
  "zoom":1.15,
  "duration":0.55
}
```

Supported targets are:

- `player`
- `companion`
- `world` with an explicit position
- `placement:<stable_map_placement_id>`

Camera zoom is constrained to prevent unreadable or disorienting framing.

### Move actor

```json
{
  "id":"morrow_checks_air",
  "type":"move_actor",
  "actor":"companion",
  "position":{"x":292,"y":224},
  "duration":0.65
}
```

Supported actors are the player, companion and stable map placements. Runtime movement is recovered against authored collision before control returns.

### Set era

```json
{"id":"remember_fire","type":"set_era","era_id":"ashen","duration":0.5}
```

The requested era must exist on the sequence map. Projectiles and reloads clear before entity availability is rebuilt.

### Fade

```json
{"id":"fade_out","type":"fade","direction":"out","duration":0.55}
```

Directions are `in` and `out`. Fades are transient and never saved mid-progress.

### Effects

```json
{
  "id":"release_archive",
  "type":"effects",
  "effects":[
    {"type":"set_state","key":"underworks:archive_released","value":true}
  ]
}
```

Effects use the same typed records as Story Studio. Supported cinematic effects include state, messages, items, recipes, quests, clock shards and currency.

### Checkpoint

```json
{"id":"opening_positioned","type":"checkpoint","key":"cinematic:opening_positioned","value":true}
```

Checkpoints are durable state records for downstream story or support diagnostics. They are not save files by themselves.

## Trigger sources

### Campaign opening

```json
{"intro_cinematic_id":"storm_door_opening"}
```

The sequence begins after the existing campaign prologue pages hand control to gameplay.

### Map interaction

```json
{
  "id":"memory_projector",
  "cinematic_id":"archivist_memory",
  "story_conditions":[]
}
```

Normal capability and Story Studio requirements are checked before playback.

### Boss introduction and conclusion

Boss profiles may declare:

```json
{
  "intro_cinematic_id":"underworks_sentinel_intro",
  "defeat_cinematic_id":"underworks_sentinel_defeat"
}
```

The introduction pauses the engaged arena without discarding boss state. The conclusion begins only after durable boss completion and rewards resolve.

## Runtime safety

While a cinematic is active:

- player movement and attacks are paused;
- enemy and boss simulation is paused;
- merchant, inventory, Journal and save overlays are closed;
- conversations close safely;
- projectiles and reloads clear before playback;
- manual save and autosave flushing are blocked;
- the current map remains authoritative.

After completion:

- transient cinematic state resets;
- Story Studio progression reevaluates;
- the durable fingerprint updates;
- a safe autosave is requested;
- trigger-once sequences cannot replay.

## Validation

Cinematic validation rejects:

- unsafe or duplicate catalog paths;
- duplicate or malformed cinematic IDs;
- unknown maps and eras;
- trigger-once sequences without completion keys;
- duplicate completion keys;
- empty or excessive timelines;
- duplicate or malformed step IDs;
- unsupported step types;
- unknown camera or actor placement targets;
- unsafe zoom and duration values;
- malformed dialogue and positions;
- unknown item, recipe, quest or currency effects;
- broken campaign, interaction or boss trigger references.

## Quality gates

### Narrative purpose

Every sequence should reveal information, establish a relationship, transform a place or communicate a gameplay change. Avoid using cinematics for actions the player could perform more clearly in normal control.

### Pacing

- Keep noninteractive waits short.
- Let dialogue advance on confirm.
- Return control immediately after the final meaningful beat.
- Use camera movement to clarify spatial relationships, not merely to decorate.

### Accessibility

- All essential dialogue must be readable as text.
- Skipping must preserve progression.
- Avoid rapid flashes and extreme zoom changes.
- Do not require timed input during playback.
- Keep controller and keyboard skip behaviour equivalent.

### Save safety

- Never save a partial timeline.
- Completion effects must be idempotent.
- Trigger-once keys must be stable.
- Boss conclusions begin after durable arena completion.
- Loading reconstructs normal gameplay, not a half-finished cinematic.

## Reference sequences

### The Door Beneath Bellweather

The opening frames the remembered museum door, lets Eli respond to the changed road, moves Morrow toward the scent and returns the camera to gameplay. Watching and skipping both publish the same completion key.

### The Sentinel Seals the Gallery

The boss introduction frames the reusable Sentinel placement, resolves era-specific dialogue and returns to the engaged arena without resetting boss health or patterns.

### The Missing Accession

The defeat sequence plays after the boss arena, reinforcements and one-time rewards are complete. It publishes a durable archive-release state and then returns to a save-safe world.

## Automated verification

The official Godot 4.6.2 gate verifies:

1. cinematic runtime, catalog, validator and editor compilation;
2. strict plugin import;
3. complete trigger and timeline validation;
4. playback, camera and dialogue advancement;
5. skip equivalence and trigger-once behaviour;
6. save blocking during playback and availability afterward;
7. durable completion effects and autosave fingerprints;
8. editor source parsing, timeline preview and rollback;
9. malformed map, era, target, effect and checkpoint rejection.
