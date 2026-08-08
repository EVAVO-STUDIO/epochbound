# Epochbound Boss & Phase Studio

Boss & Phase Studio is the campaign-authoring layer for major encounters that need more structure than an ordinary enemy or encounter zone. It builds on the existing systems rather than replacing them:

- **Encounter Studio** defines the reusable enemy.
- **Combat Director** supplies awareness, navigation, windup, pursuit, return and the authored encounter zone.
- **Arsenal Studio** supplies moving projectiles and ranged profiles.
- **Story Studio** supplies typed rewards, durable state and quest reactions.
- **Boss & Phase Studio** supplies arena control, health phases, ordered attack patterns, reinforcements, phase transitions and durable boss outcomes.

The editor, validator, runtime and executable tests consume the same source-controlled object and map records.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Boss** main-screen tab.
3. Choose a campaign.
4. Select an existing reusable enemy definition.
5. Place that enemy through Encounter Studio if it is not already on a map.
6. Assign its placement to a Combat Director encounter zone.
7. Enable the boss contract.
8. Select the authored arena zone.
9. Define the durable outcome state key.
10. Set arena introduction and completion messages.
11. Choose whether era shifting remains available during the fight.
12. Set the playable arena bounds.
13. Select map connections that remain locked while the arena is unresolved.
14. Author one complete defeat-effect JSON object per line.
15. Author one complete phase JSON object per line.
16. Review the phase and fairness preview.
17. Apply the contract.
18. Run complete validation and the manual playtest checklist.

Boss Studio snapshots the existing object catalogue before writing. If the complete campaign becomes invalid, it restores the previous file and in-memory definitions.

## Boss definition contract

A reusable enemy becomes a boss by adding a `boss` object:

```json
{
  "boss": {
    "enabled": true,
    "arena_zone_id": "underworks_gallery_watch",
    "outcome_state_key": "underworks:boss:sentinel",
    "intro_message": "The Sentinel seals the gallery.",
    "defeat_message": "The gallery breathes again.",
    "lock_connection_ids": ["west_to_bellweather"],
    "allow_era_shift": true,
    "arena_bounds": {
      "left": 280,
      "right": 590,
      "top": 112,
      "bottom": 312
    },
    "defeat_effects": [
      {"type": "grant_clock_shards", "amount": 5},
      {"type": "grant_currency", "currency_id": "archive_chits", "amount": 15}
    ],
    "phases": []
  }
}
```

The underlying object still uses `kind: enemy`. Health, collision, movement, attack range, base damage, base cooldown and base projectile settings remain ordinary reusable enemy fields.

## Arena zone

`arena_zone_id` references one Combat Director encounter zone on the boss's source map.

That zone must:

- exist on the same map;
- include the boss placement ID;
- include every reinforcement that must be defeated before the encounter clears;
- use a stable clear-state key;
- remain large enough for the intended movement and projectile patterns;
- activate before the player begins inside unavoidable damage.

The encounter zone controls activation and durable clearing. The boss contract adds stricter arena boundaries and exit locks.

## Arena bounds

`arena_bounds` defines the playable rectangle while the boss arena is active.

The bounds:

- must remain inside the map's playable bounds;
- must provide at least 180 by 120 pixels of movement space;
- clamp both Eli and Morrow safely inside the fight;
- should include cover, recovery space and all active phase members;
- must not trap the player after completion;
- must not overlap an entry point that begins inside the boss's immediate attack envelope.

Arena bounds are not a replacement for map collision. They provide a temporary encounter perimeter around normal authored geometry.

## Connection locks

`lock_connection_ids` contains stable map connection IDs that cannot be used while the arena remains unresolved.

A locked exit:

- rejects travel before map state changes;
- displays clear player-facing feedback;
- remains locked after the boss falls if required reinforcements remain;
- unlocks only when the complete encounter zone is cleared;
- never requires a second hidden unlock record.

Only connections on the boss's source map may be referenced.

## Durable outcome

`outcome_state_key` records the completed major encounter, independently of individual placement defeat keys and the encounter-zone clear key.

The runtime writes the outcome only after:

1. The boss has been defeated.
2. Every declared zone member has been defeated.
3. The Combat Director zone has published its clear state.
4. The outcome has not already been granted.

This separation supports story conditions such as:

```json
{
  "type": "state_equals",
  "key": "underworks:boss:sentinel",
  "value": "defeated"
}
```

The outcome and its effects are idempotent. Re-entering the map, shifting eras or loading a save cannot duplicate completion rewards.

### Completed-arena retirement

When the durable outcome is already `defeated`, the runtime retires the boss placement before activation checks run. The placement remains inactive with zero health, transient boss context is removed, arena locks stay released and introduction or conclusion cinematics cannot replay.

This retirement is checked both by the focused Boss runtime regression and by the repeated long-form progression gate after every Museum Underworks revisit.

Save-profile restoration clears all transient engagement, context, phase and pattern dictionaries after the durable payload and exact map have loaded. Boss state is then derived again from the restored outcome and player position, preventing stale combat state from surviving a load.

## Phase contract

Each phase is a complete object:

```json
{
  "id": "last_accession",
  "display_name": "Last Accession",
  "health_ratio_at_or_below": 0.55,
  "available_eras": [],
  "on_enter_message": "Two curator echoes step out of the missing hour.",
  "transition_duration": 0.7,
  "move_speed_multiplier": 1.15,
  "attack_cooldown_multiplier": 0.82,
  "attack_damage_multiplier": 1.15,
  "attack_windup": 0.48,
  "reinforcement_placements": [
    "curator_echo_west",
    "curator_echo_east"
  ],
  "ranged_attack_override": {
    "projectile_speed": 250,
    "projectile_range": 280,
    "projectile_color": "f08a56"
  },
  "attack_pattern": [
    {"type": "fan_shot", "count": 5, "spread_degrees": 52},
    {"type": "pause", "duration": 0.55},
    {"type": "radial_burst", "count": 8, "spread_degrees": 360},
    {"type": "pause", "duration": 0.65}
  ]
}
```

### Stable ID

`id` is a normalised lowercase identifier. Save files do not store transient phase progress, but stable IDs remain essential for editor references, diagnostics, reinforcement metadata and automated tests.

### Health threshold

`health_ratio_at_or_below` is a value greater than zero and no greater than one.

A phase becomes eligible when boss health is at or below that fraction of maximum health. The most specific eligible threshold wins.

At least one opening phase must cover full health. Era-specific opening phases may share a threshold of `1.0` when their `available_eras` records do not overlap.

### Phase-boundary protection

A single attack may reach the next phase boundary but cannot skip a required phase entirely.

When a hit would cross an unread phase threshold, damage is clamped to that boundary. The transition then:

- clears active projectiles;
- cancels reload without consuming reserve ammunition;
- displays the authored phase message;
- honours the transition duration;
- activates declared reinforcements;
- resets the boss pattern index.

Once the final phase is active, ordinary lethal damage may defeat the boss.

### Era availability

`available_eras` follows the common Epochbound rule:

- an empty array means every era;
- one or more era IDs restrict the phase to those eras.

The reference Sentinel uses one Verdant opening phase, one Ashen opening phase and a shared final phase. Its current health persists across era shifts, while the eligible phase and projectile presentation change.

### Stat multipliers

The phase may override:

- movement speed multiplier;
- attack cooldown multiplier;
- attack damage multiplier;
- attack windup;
- ranged projectile fields.

Multipliers must remain positive. The validator rejects phase profiles whose projectile speed or size exceeds the current boss readability limits.

## Attack-pattern graph

Boss patterns are deterministic ordered arrays. A completed Combat Director windup consumes the next pattern step.

Supported step types are:

### Aimed shot

```json
{"type": "aimed_shot", "count": 1}
```

Fires toward the selected target using the phase's active projectile profile.

### Fan shot

```json
{
  "type": "fan_shot",
  "count": 5,
  "spread_degrees": 52,
  "damage_multiplier": 0.82
}
```

Fires two to five projectiles across an authored arc. The spread must remain wide enough for distinct lanes but not so wide that unrelated spaces are hit without warning.

### Radial burst

```json
{
  "type": "radial_burst",
  "count": 8,
  "spread_degrees": 360,
  "damage_multiplier": 0.72
}
```

Fires four to ten projectiles around the boss. Automated validation estimates the gap between projectiles at a fairness probe radius and rejects patterns that leave less than 16 pixels of escape space.

### Strike

```json
{"type": "strike", "damage_multiplier": 1.2}
```

Resolves the existing telegraphed contact attack rather than spawning a projectile.

### Pause

```json
{"type": "pause", "duration": 0.55}
```

Consumes one attack opportunity as an explicit recovery interval. Every phase pattern must include at least one pause of 0.35 seconds or longer.

Patterns may not contain more than three consecutive attack steps without a safe pause.

## Reinforcements

A phase may activate existing map placements through `reinforcement_placements`.

Each reinforcement placement must:

- reference a non-boss enemy definition;
- belong to the boss arena encounter zone;
- have a unique placement and state key;
- include matching `boss_reinforcement` metadata;
- name the boss placement ID;
- name the exact phase ID that activates it.

Example:

```json
{
  "id": "curator_echo_west",
  "object_id": "ash_hound",
  "position": {"x": 400, "y": 224},
  "available_eras": [],
  "state_key": "underworks:curator_echo_west",
  "boss_reinforcement": {
    "boss_placement_id": "underworks_sentinel",
    "phase_id": "last_accession"
  }
}
```

Reinforcements instantiate with the map but remain inactive until their phase begins. They then use their ordinary reusable enemy and Combat Director behaviour.

## Defeat effects

Boss completion currently supports these typed effects:

- `grant_clock_shards`
- `grant_item`
- `grant_currency`
- `set_state`

Item and currency references are validated against the installed campaign. Effects run once after the complete arena clears.

Quest progression can react to the resulting stable state through Story Studio instead of embedding quest-specific logic inside the boss runtime.

## Runtime presentation

The blockout runtime provides:

- arena boundary rendering;
- boss introduction and phase banners;
- boss name and current phase label;
- a dedicated boss health bar;
- an explicit “reinforcements remain” state after the boss body falls;
- existing Combat Director windups;
- Arsenal moving projectiles and cover collision;
- transition pauses that clear unresolved projectiles;
- durable completion feedback and rewards.

Final sprites, animation, music, sound and particles should reinforce these same timing contracts rather than redefining them informally.

## Fairness validation

Boss validation rejects:

- non-enemy boss definitions;
- missing arena zones or outcome keys;
- arena bounds outside the map;
- arenas smaller than the minimum movement space;
- missing or duplicate phase IDs;
- phase thresholds outside `(0, 1]`;
- no opening full-health phase;
- fewer than two phases;
- unreadably short windups;
- non-positive phase multipliers;
- unsupported pattern types;
- fan or radial counts outside safe limits;
- fan spreads outside the supported range;
- patterns without safe pauses;
- excessive consecutive attack steps;
- excessive projectile speed or radius;
- radial patterns with insufficient escape gaps;
- unknown exits, reinforcements, items or currencies;
- reinforcement metadata that disagrees with the phase;
- entry points inside the immediate attack envelope.

Validation proves structural coherence and minimum response windows. It does not prove that a fight is enjoyable, accessible or appropriately balanced.

## Production quality gates

### Readability

- Every damaging action has a visible tell.
- Phase changes are announced and temporarily suppress unresolved attacks.
- The boss name, health and current phase remain visible.
- Projectile colours remain distinguishable from terrain and player effects.
- Reinforcement arrival is understandable rather than appearing as unexplained damage.

### Fairness

- The player never enters directly inside an active attack envelope.
- The arena provides a meaningful route around the boss.
- Projectile patterns leave traversable lanes.
- Every phase includes recovery time.
- Phase transitions cannot be skipped by burst damage.
- Era shifting cannot create an unavoidable projectile overlap.
- Morrow can remain inside the arena without being trapped by its bounds.

### Pacing

- The opening phase teaches one clear idea.
- Later phases combine or transform previously learned ideas.
- Reinforcements change priorities rather than merely extending health.
- The final phase is more demanding without becoming continuous damage.
- Completion produces a readable world or story consequence.

### Reliability

- Exit locks fail before travel state changes.
- Save and autosave remain blocked while the arena is unresolved.
- Defeat rewinds remove transient boss state safely.
- Map and era transitions clear projectiles and reloads.
- Reload cancellation preserves reserve ammunition.
- Completion rewards cannot duplicate.
- Old saves reconstruct boss state from durable placement, zone and outcome keys.

## Reference boss: Underworks Sentinel

The Museum Underworks Sentinel proves:

- activation through an authored encounter zone;
- a locked return route during combat;
- safe arena bounds;
- a Verdant Catalogue Measure phase;
- an Ashen Cinder Measure phase;
- a shared Last Accession final phase;
- health-boundary protection;
- aimed, fan and radial projectile patterns;
- explicit recovery pauses;
- two dormant curator echoes activated in the final phase;
- a fight that remains unresolved until every arena member is defeated;
- durable boss, zone and placement outcomes;
- one-time clock-shard and Archive Chit rewards.

## Automated verification

The permanent Godot 4.6.2 gate covers:

1. direct compilation of Boss Runtime, Boss Catalog, Boss Validator, Boss Studio and boss tests;
2. strict project import with all eleven editor plugins;
3. complete campaign validation including boss phases and arenas;
4. runtime engagement and arena locking;
5. era-specific phase selection;
6. phase-boundary damage clamping;
7. reinforcement activation;
8. deterministic fan-pattern projectile creation;
9. durable zone and boss completion;
10. one-time reward application;
11. Boss Studio source parsing and editor state;
12. rejection of malformed arenas, patterns, rewards and reinforcements.

Run the complete local gate from Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

## Future extensions

The current contracts are designed to support:

- cinematic camera and animation tracks;
- boss-specific music layers;
- destructible arena props;
- invulnerability and vulnerability windows;
- multi-target and companion-command phases;
- authored reinforcement waves rather than one activation set;
- environmental phase effects;
- optional challenge modifiers;
- difficulty and accessibility profiles;
- automated damage-density and route-reachability simulation;
- campaign packaging of boss previews and test reports.

Each extension should preserve the current rule: one authored contract is shared by the editor, validator, runtime and executable tests.
