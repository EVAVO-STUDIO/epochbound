# Epochbound Companion Studio

Companion Studio is the authoring and validation layer for the animal companion's movement, commands, recovery, exploration value and world discoveries.

The companion is not treated as a decorative follower or a second health bar. It is a persistent relationship expressed through movement, attention, trust, danger response and information the player cannot obtain alone.

## Responsibilities

The four current Godot authoring surfaces have separate responsibilities:

- **Campaign Studio** builds maps, eras, collision, navigation, entrances, interactions and recovery anchors.
- **Encounter Studio** defines and places reusable props, NPCs, enemies and pickups.
- **Combat Director** groups enemies into encounters and directs patrol, telegraph, pursuit, stagger and return behaviour.
- **Companion Studio** defines companion commands and authors scent, clue, resource, trail and warning cues.

All four tools edit the same portable campaign records used by the runtime and validation suite.

## Player commands

The reference profile supports four cycling commands and one safety action.

### Follow

The companion follows behind the player's current facing direction at the authored follow distance.

Follow is the default and recovery state. Map travel resets to Follow so a hold point from one map can never leak into another map.

### Stay

Stay records the companion's current position and asks it to hold that point.

The companion returns toward the hold position if displaced by collision or combat. Stay does not permit automatic attacks, preventing a supposedly stationary companion from running into a fight.

Stay is map-local. If the player moves far enough to violate the recovery contract, the runtime recalls the companion rather than allowing a permanent separation or softlock.

### Seek

Seek chooses the nearest unresolved companion cue that:

- exists in the current map;
- is available in the current era;
- has not already been discovered;
- lies within the companion's authored seek radius.

The companion navigates toward that cue using the same map navigation contract as ordinary following. On reaching the cue's reveal radius, the runtime:

1. stores the cue's persistent state key;
2. applies any authored reward once;
3. presents the authored discovery text;
4. clears the current target;
5. returns the companion to Follow.

If no valid cue is nearby, the companion reports that no unbroken trail can be found and returns to Follow. Seek never wanders indefinitely without an authored destination.

### Guard

Guard keeps the companion closer to the player and extends its combat-assistance range.

Guard remains low-micromanagement. It changes positioning and combat priority without introducing a second manually controlled character.

### Recall

Recall is always available when the companion system is enabled, regardless of the current command list.

It:

- cancels Stay or Seek;
- restores Follow;
- resolves a nearby authored recovery point;
- checks entity collision;
- places the companion safely near the player.

Recall is a reliability feature as well as a player command. It provides an explicit answer when navigation, combat displacement or experimentation separates the pair.

## Default controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Cycle companion command | R | North face button |
| Recall companion | F | Left shoulder button |

The HUD always displays the active command and both input prompts while the companion is enabled.

## Companion profile contract

The campaign's `actors.companion` record now carries behavioural defaults:

```json
{
  "actors": {
    "companion": {
      "name": "MORROW",
      "max_health": 24,
      "commands": ["follow", "stay", "seek", "guard"],
      "follow_distance": 34,
      "guard_distance": 24,
      "recovery_distance": 300,
      "seek_radius": 300,
      "seek_speed": 148,
      "guard_attack_range": 54
    }
  }
}
```

### Commands

`commands` defines the cycle order. Supported IDs are:

- `follow`
- `stay`
- `seek`
- `guard`

Follow is restored as a runtime fallback even if an invalid custom profile omits it. Companion Studio automatically includes Follow when saving a profile.

### Follow and guard distance

`follow_distance` determines the ordinary trailing position.

`guard_distance` determines the closer defensive position. Guard distance will normally be smaller than follow distance so the change is visible and mechanically useful.

### Recovery distance

`recovery_distance` is the maximum ordinary separation before the runtime performs controlled recovery.

This value should be large enough to tolerate camera movement, collision detours and short navigation failures, but small enough to prevent the companion from remaining lost off-screen.

### Seek radius and speed

`seek_radius` limits candidate discovery cues. It prevents a single command from sending the companion across an entire map or through unrelated encounters.

`seek_speed` controls movement while following a selected cue. It may be slightly faster than ordinary following, but should remain readable rather than resembling teleportation.

### Guard attack range

`guard_attack_range` extends the distance at which the companion may assist during Guard. It does not change damage or cooldown values and does not permit attacks during Stay or Seek.

## Companion cue contract

Maps may contain a `companion_cues` array:

```json
{
  "companion_cues": [
    {
      "id": "well_name_scent",
      "kind": "clue",
      "position": {"x": 148, "y": 216},
      "reveal_radius": 22,
      "message": "Morrow finds a name beneath the moss.",
      "reward": 1,
      "visible_before_discovery": false,
      "available_eras": ["verdant"],
      "state_key": "bellweather:companion:well_name_scent"
    }
  ]
}
```

### ID

`id` is a stable lowercase identifier unique within the map.

Use semantic names describing the discovery rather than its implementation:

- `well_name_scent`
- `future_bark_trail`
- `cold_ash_cache`
- `hollow_wall_warning`

### Kind

Supported cue kinds are:

- `clue`: narrative evidence or environmental understanding;
- `resource`: an item-like or currency-bearing discovery;
- `trail`: a scent or trace that points through the world;
- `warning`: information about danger, instability or an encounter.

Kind affects editor presentation now and provides a stable basis for later audio, animation, inventory and quest behaviour.

### Position and reveal radius

`position` is the target the companion navigates toward.

`reveal_radius` is the distance at which discovery resolves. It must account for collision and visual composition. Authors should not place a cue inside blocked geometry merely because the reveal radius is large enough to reach through the wall.

### Message

`message` is the player-facing result. It should describe what the companion notices or does, not merely report that a collectible was found.

Good discovery text usually contains at least one of:

- a sensory detail unavailable to the player;
- a relationship detail expressed through the companion's behaviour;
- evidence connecting two eras;
- a warning that changes how the player reads nearby space;
- a concrete clue supporting a quest or mystery.

### Reward

`reward` currently adds clock shards. It is optional and defaults to zero.

The stable field will later route through the inventory and reward systems. Discovery must remain worthwhile even when the reward is zero.

### Visibility before discovery

`visible_before_discovery` controls whether the blockout renderer shows the cue before Seek targets it.

Most scent and clue cues should remain hidden. Visible cues are useful for tutorial authoring, accessibility, explicit companion puzzles or resources that the player can see but cannot interpret alone.

### Era availability

`available_eras` follows the shared Epochbound rule:

- an empty array means every era;
- one or more IDs restrict the cue to those eras.

A cue can therefore describe evidence present only before a disaster, a scent left after a timeline change or different clues occupying the same physical location in different eras.

### State key

`state_key` records discovery. If omitted, the runtime derives a stable key from the map and cue IDs.

Once stored, the cue is removed from future Seek selection and cannot grant its reward again during the session.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Companion** tab.
3. Choose the campaign, map and era.
4. Review or edit the companion profile.
5. Select **Place Cue** and click the map.
6. Give the cue a stable ID and kind.
7. Set its exact position and reveal radius.
8. Write the discovery message.
9. Add an optional reward.
10. Decide whether the cue is visible before discovery.
11. Scope it to the selected era or every era.
12. Add an explicit state key when cross-map or quest logic will reference the discovery.
13. Apply and validate the cue.
14. Run the campaign and test Follow, Stay, Seek, Guard, Recall, era shifting and map travel.

The canvas also displays terrain, collision context, placed objects and authored cues, so discoveries can be reviewed as part of the level rather than as disconnected coordinates.

## Validation rules

Companion validation rejects:

- missing companion actor records;
- empty names or non-positive health;
- unsupported or duplicate commands;
- non-positive movement, distance or range values;
- malformed `companion_cues` arrays;
- invalid or duplicate cue IDs;
- unsupported cue kinds;
- positions outside the map canvas;
- non-positive reveal radii;
- empty messages;
- negative rewards;
- non-boolean visibility flags;
- unknown or repeated era IDs;
- duplicate or excessively long state keys.

It warns about:

- command lists that omit Follow;
- guard distance greater than follow distance;
- unusually large seek range relative to recovery range;
- Seek-enabled campaigns with no authored cues;
- visible warning cues that may disclose danger without using the companion.

Validation proves structural and referential correctness. It cannot determine whether a clue is satisfying, discoverable or narratively useful.

## Companion quality gates

### Relationship value

- The companion communicates through movement and behaviour, not only text.
- Commands have visible consequences.
- Discoveries feel specific to this companion.
- Recovery does not make the companion appear disposable or arbitrary.

### Exploration value

- Seek reveals authored information rather than random filler.
- Cues are placed within traversable space.
- The nearest cue is an intentional result from likely player positions.
- Era-specific cues reward revisiting familiar locations.
- Rewards do not replace meaningful discovery text.

### Reliability

- Follow survives ordinary obstacles and map scrolling.
- Stay cannot create a permanent separation.
- Seek cannot select an already discovered or unavailable cue.
- Recall always produces a valid nearby position.
- Map travel clears map-local targets and hold points.
- Era shifting cannot retain an invalid cue target.

### Combat behaviour

- Stay and Seek suppress automatic attacks.
- Guard increases useful assistance without taking control from the player.
- Companion recovery does not occur inside an active attack when a safe anchor exists.
- Enemy targeting and companion assistance remain understandable.

### Accessibility

- Current command is always visible in the HUD.
- Recall is a dedicated action rather than hidden in the command cycle.
- Cue visibility can be authored for tutorial or accessibility needs.
- Discovery messages do not disappear immediately during combat.

## Reference discoveries

The reference campaign contains four cues:

### Bellweather Crossing, Verdant

`well_name_scent` lets Morrow uncover a family name dated decades before Eli's birth. It proves hidden clue discovery, era scope, persistent state and a one-time reward.

### Bellweather Crossing, Ashen

`hot_brass_warning` gives an authored warning near the East Ash Hunt encounter. It proves that companion information can change how the player reads combat space without granting currency.

### Clockwood Edge, Verdant

`future_bark_trail` connects the carved future dates to Eli through scent and touch evidence. It proves long-range map seeking and cross-era mystery support.

### Clockwood Edge, Ashen

`cold_ash_cache` reveals a clock shard protected by unburned catalogue cloth. It proves resource discovery, era scope and one-time reward persistence.

## Automated verification

The Godot 4.6.2 validation gate now checks:

1. direct compilation of the runtime, all four editor plugins, validators and smoke scripts;
2. strict project import with logged parser and plugin errors treated as failures;
3. campaign, map, catalog, placement, encounter-zone, profile and cue validation;
4. terrain, collision, navigation, recovery and linked-map contracts;
5. base encounter, persistence and action-combat contracts;
6. Combat Director activation, windup, stagger, leash and clear-state contracts;
7. companion command order, Stay, Seek selection, discovery, reward idempotence, Guard and Recall.

Run the same gate locally:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

## Future extensions

The current contracts are intended to support:

- directional companion commands and point placement;
- scent trails made from ordered cue chains;
- digging, fetching, carrying and switch activation;
- companion-specific capabilities that change across eras;
- trust, injury and narrative state;
- quest conditions driven by cue discovery;
- inventory rewards and crafting ingredients;
- companion dialogue barks and animation sets;
- accessibility modes that reveal cue direction or range;
- save-profile persistence;
- automated companion reachability and recovery probes.

Future systems should preserve the same rule: editor, validator, runtime and executable tests must consume one shared authored contract.
