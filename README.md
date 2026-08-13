# Epochbound

Epochbound is an original Godot 4.6.2 action RPG and campaign-authoring platform built around a boy, his dog, and places that exist in more than one age.

The project draws on broad strengths of premium mid-1990s console adventures: readable low-resolution silhouettes, responsive real-time combat, compact framed interfaces, environmental mystery, a useful animal companion, strong location identity, deliberate camera movement, concise animation and authored surprise. Its world, cast, maps, creatures, dialogue, systems, terminology, procedural art, frame timing, music patterns, sound design and future mastered assets are original to Epochbound.

It does **not** reproduce protected characters, locations, sprites, animation sheets, portraits, dialogue, music, sound effects, story scenes, maps, samples or exact interface designs from *Secret of Evermore* or any other existing game.

## Current playable foundation

The reference campaign, **The Hours Beneath**, currently provides:

1. EVAVO Studio splash, title, campaign browser and campaign-defined prologue
2. Four connected scrolling maps: Bellweather Crossing, Clockwood Edge, Museum Underworks and the Archive Hideaway
3. Verdant and Ashen versions of each location
4. Eight-direction movement, authored collision, navigation, entries, recovery anchors and return routes
5. Eli and his dog Morrow with Follow, Stay, Seek, Guard and Recall behaviour
6. Reusable NPC, prop, enemy, pickup, merchant and boss definitions
7. Telegraphed action combat with stagger, knockback, defence, projectiles, ammunition and reloads
8. Encounter zones with activation, patrol, pursuit, leash return, reinforcement and clearing
9. Items, equipment, capabilities, consumables, recipes, crafting and quick-use healing
10. Branching conversations, typed conditions and effects, multi-stage quests, objectives and Journal
11. Campaign currencies, atomic trade, durable stock, regional supply routes, bounded restocking and authored scarcity
12. A three-phase cross-era Underworks Sentinel boss encounter
13. Skippable, progression-equivalent cinematic timelines
14. Versioned save profiles, migrations, checksums, autosave, manual slots, backup recovery and Continue
15. Deterministic campaign packages with manifests, SHA-256 verification, complete staged validation and safe installation
16. Repository-wide campaign audits with ten deterministic production probes for reachability, return safety, capability definitions, recovery, quest starts, save safety, progression sources, affordability, economy balance and meaningful temporal-shift consequences, plus regional supply evidence
17. Original map and era presentation profiles with camera feel, atmosphere, restrained screen texture and framed HUD
18. Original procedural music, environmental ambience, dynamic combat layers, mix ducking and event-driven sound feedback
19. Frame-based Sprite Animation profiles with four-direction timing, attack anticipation, Morrow gait, atlas import and procedural fallbacks
20. Animated water, grass sway, brass machinery cycles, material-specific foot response, foreground occlusion and contextual world feedback
21. Camera-correct projectiles, shared combat depth, presentation-owned ammo and boss status, and pause-safe CanvasLayer ordering
22. Versioned player-local Audio, presentation and accessibility settings with persistent keyboard and controller remapping
23. Authored boss phase music stems that layer Catalogue Measure, Cinder Measure and Last Accession over the current Underworks era theme
24. Automated repeated long-form progression playthroughs with eight completed-world laps, deterministic supply time, checksummed checkpoints and destructive restoration probes
25. Reliable host-shutdown requests, per-peer acknowledgements, committed closure and independent clean ENet process exit
26. Unexpected-host restart recovery for accepted direct-IP clients with six bounded retries and same-process replacement-host validation
27. Player-local English and deterministic pseudo-localisation with strict UI and campaign catalogues, stable title/subtitle/intro keys, placeholder parity and staged package validation
28. Measured localisation layout safety with bounded font reduction, deterministic wrapping and visible ellipsis across fixed 640 by 360 UI surfaces
29. A playable Archive Hideaway refuge with active-play expeditions, four optional facilities, truthful dual-cap return accounting, visible four-tier refuge progression, exact upgrade costs, preparation capacity and strict one-use persistence
30. A non-consuming journey memento shelf derived from existing campaign milestones, with six authored Verdant/Ashen memories and no new save flags, rewards or obligation loop

The runtime still uses generated visuals and synthesis for much of its production blockout. These systems establish scale, silhouette, colour, frame timing, environmental motion, combat readability, feedback, camera, interface, collision, combat, cinematic, musical, ambience and mix contracts before final pixel art and mastered audio replace the generated assets.

## Seventeen connected Godot authoring tools

Godot’s main-screen toolbar exposes:

```text
Campaign
Encounter
Combat
Companion
Items
Story
State
Loadout
Trade
Arsenal
Boss
Cinematic
Package
Audit
Presentation
Audio
Sprite
```

Every tool writes inspectable campaign data and reuses stable IDs across the same runtime. No editor creates a hidden parallel database.

### Campaign

Authors maps, eras, terrain, collision, navigation, spawns, entries, recovery anchors, interactions and cross-map travel.

### Encounter

Authors reusable props, NPCs, enemies, pickups and their map placements.

### Combat

Directs encounter zones, activation, patrols, windups, leashes, stagger, knockback and persistent clearing.

### Companion

Authors Morrow’s command profile, scent, clue and resource cues, recovery, Guard behaviour and one-time discoveries.

### Items

Authors inventory items, consumables, materials, equipment, ammunition, recipes, rewards, crafting and starting inventory.

### Story

Authors conversation graphs, choices, typed conditions and effects, quests, stages, objectives and rewards.

### State

Inspects, validates, migrates, recovers and deletes durable player save profiles, including wallet, merchant stock and **Supply Cycles**.

### Loadout

Authors equipment slots, starting gear, derived statistics, semantic capabilities and capability-gated world and story records.

### Trade

Authors currencies, merchant availability, stock, pricing, sale rules, reusable NPC shop bindings, regional supply routes, replenishment targets and scarcity.

### Arsenal

Authors ammunition, ranged weapons, projectile behaviour, reload timing and enemy projectile profiles.

### Boss

Authors arena bounds, exit locks, phases, thresholds, attack-pattern sequences, reinforcements and one-time outcomes.

### Cinematic

Authors camera tracks, actor movement, dialogue, waits, fades, era changes, effects, checkpoints and save-safe skip outcomes.

### Package

Authors release metadata and exports or imports data-only `.epochbound.zip` campaign packages with tamper-evident manifests and complete current-content validation.

### Audit

Runs ten deterministic production probes covering structural reachability, recovery, progression-source softlocks, merchant-only affordability, bounded economy-balance simulation and meaningful temporal-shift consequences, then adds regional supply evidence and exports machine-readable blocker and warning reports.

### Presentation

Authors original 16-bit palette, atmosphere, camera deadzone, follow and look-ahead, bounded shake, screen texture and actor-motion profiles by map and era.

### Audio

Authors original procedural music scales and patterns, ambience character, dynamic combat gain, menu, dialogue and cinematic ducking, and safe crossfade timing by map and era.

### Sprite

Authors frame dimensions, render size, pivots, one-row or four-direction layouts, optional transparent PNG atlases, fallback style and idle, walk, attack and hurt timing.

## Regional supply and scarcity

The reference economy now has two deterministic routes:

- **Bellweather Museum Route**: 180-second active-play interval with at most four catch-up cycles.
- **Underworks Salvage Route**: 300-second active-play interval with at most three catch-up cycles.

Museum Tonic, Brass Filings, Ember Salve, Archive Bolts and Ashen Resin replenish toward authored caps. Museum Flashlight, Clockglass Fragments, Salvager Wrap, Clockglass Dartcaster and progression lenses remain finite.

Supply uses durable `play_time_seconds`, never wall-clock time. Every elapsed cycle is consumed exactly once, including cycles where stock is already full. Catch-up is bounded, excess cycles are discarded deliberately, saved cursors are checksummed, and older compatible saves initialise at their current gameplay-time cycle without retroactive deliveries or offline windfalls.

Trade Studio authors routes and merchant assignments. State Studio exposes exact saved cursors. Package installation rejects malformed supply policy before promotion. Campaign Audit Studio publishes route and renewable-stock evidence without treating restocking as guaranteed immediate progression supply.

## Player settings, accessibility and controls

Player-local settings are stored separately from campaigns, save profiles and portable packages. Options controls Master, Music, Ambience and SFX volume; screen texture; camera shake; world motion; screen flashes; action prompts; high-contrast interface treatment; and Language between English and deterministic Pseudo-localisation.

The Controls submenu remaps fourteen gameplay actions across physical keyboard keys, controller buttons, D-pad directions and deliberate analogue-axis directions. Escape, O and Start remain fixed recovery inputs, so Pause and Options cannot become inaccessible. Conflicting managed inputs use a device-local swap rather than creating duplicates or leaving an action unbound.

Keyboard capture accepts one physical key at a time. Modifier chords are rejected because Epochbound reads gameplay actions through Godot’s normal non-exact action matching, where additional key modifiers are not a safe way to distinguish two actions.

The complete profile is applied through Godot’s runtime `InputMap` and persisted through the existing atomic player-settings writer. Validated keyboard rows, controller rows and prompt labels are cached only when settings load or bindings change; gameplay drawing reads those bounded caches rather than sanitising the complete profile every frame.

Read [`docs/PLAYER_SETTINGS.md`](docs/PLAYER_SETTINGS.md) for the schema, migration, recovery, capture and validation contracts, [`docs/LOCALISATION_FOUNDATION.md`](docs/LOCALISATION_FOUNDATION.md) for strict catalogue, fallback, pseudo-localisation and package rules, [`docs/LOCALISATION_LAYOUT_SAFETY.md`](docs/LOCALISATION_LAYOUT_SAFETY.md) for measured fixed-viewport fitting, wrapping and ellipsis, and [`docs/ARCHIVE_HIDEAWAY_RUNTIME.md`](docs/ARCHIVE_HIDEAWAY_RUNTIME.md) for the refuge loop, visible four-tier shelter progression, capacity-aware planning, truthful return feedback and one-use persistence boundary, and [`docs/ARCHIVE_HIDEAWAY_MEMENTOS.md`](docs/ARCHIVE_HIDEAWAY_MEMENTOS.md) for the journey memento shelf, existing campaign milestones, era reflections and reward-free unlock contract.

## Original 16-bit presentation, audio and animation

### Presentation

The Presentation layer provides:

- eight reference profiles, one for every map and era combination;
- distinct Verdant and Ashen value and hue relationships;
- camera follow, deadzone, directional look-ahead and bounded shake;
- a separate CanvasLayer that keeps HUD and dialogue fixed during world-camera movement;
- deterministic pollen, dust, fireflies, embers and cinders;
- animated water, grass, brass service paths and bounded ambient ground motion;
- movement-linked water ripples, bent grass, ash, dust and metal glints for Eli and Morrow;
- feet-based actor, entity and projectile depth ordering plus foreground tree, branch and ruin occlusion;
- area arrival cards, nearest-target action prompts and capability-aware locked feedback;
- camera-correct projectile trails, presentation-owned ammunition status and boss phase panels;
- pause-safe layering that prevents the high CanvasLayer from covering the root pause interface;
- footstep puffs, impact bursts, era flashes and attack glints;
- notched health bars and an original compact framed interface;
- restrained scanline, dither and vignette treatment.

### Audio

The Audio layer provides:

- one title and prologue profile plus eight map and era profiles;
- original scale-degree melody and bass patterns;
- bounded pulse, triangle and sine synthesis;
- deterministic room tone, pollen, insects, embers, cinders, machinery and furnace ambience;
- a combat layer that fades over the continuing exploration theme;
- stable boss-and-phase stems that escalate authored encounters without replacing map-and-era identity;
- feedback for attacks, impacts, damage, pickups, travel, shifts, menus, dialogue, combat and cinematics;
- menu, dialogue, cinematic and pause ducking;
- guarded generator startup and underrun detection.

### Sprite Animation

The Sprite layer provides:

- six reference animation profiles for Eli, Morrow, humanoids, beasts, orbs and props;
- stable bindings by player, companion, placement, object, shape and kind;
- four-direction row order of Down, Left, Right and Up;
- distinct idle, walk, attack and hurt frame timing;
- attack anticipation, maximum reach and follow-through;
- Morrow’s own movement-facing, six-frame gait and tail motion;
- entity pursuit, windup and stagger animation selection;
- capability-aware flashlight illumination;
- transparent PNG atlas loading with nearest-neighbour rendering;
- original procedural animation when final art is absent;
- strict atlas, pivot, frame-grid and package validation.

These systems are production foundations, not recreations of another game’s graphics, animation or soundtrack. Final Epochbound atlases, recorded ambience, sound effects and music masters can replace generated output without changing gameplay state, authoring data, validation, packaging or save contracts.

Read:

- [`docs/PRESENTATION_FEEL_STUDIO.md`](docs/PRESENTATION_FEEL_STUDIO.md)
- [`docs/PRESENTATION_PLAYTEST_CHECKLIST.md`](docs/PRESENTATION_PLAYTEST_CHECKLIST.md)
- [`docs/AUDIO_MOOD_STUDIO.md`](docs/AUDIO_MOOD_STUDIO.md)
- [`docs/BOSS_MUSIC_STEMS.md`](docs/BOSS_MUSIC_STEMS.md)
- [`docs/AUDIO_PLAYTEST_CHECKLIST.md`](docs/AUDIO_PLAYTEST_CHECKLIST.md)
- [`docs/SPRITE_ANIMATION_STUDIO.md`](docs/SPRITE_ANIMATION_STUDIO.md)
- [`docs/SPRITE_ANIMATION_PLAYTEST_CHECKLIST.md`](docs/SPRITE_ANIMATION_PLAYTEST_CHECKLIST.md)
- [`docs/ANIMATION_DEPTH_POLISH.md`](docs/ANIMATION_DEPTH_POLISH.md)
- [`docs/ADVENTURE_FEEDBACK_POLISH.md`](docs/ADVENTURE_FEEDBACK_POLISH.md)
- [`docs/ENVIRONMENT_ANIMATION_POLISH.md`](docs/ENVIRONMENT_ANIMATION_POLISH.md)
- [`docs/COMBAT_READABILITY_POLISH.md`](docs/COMBAT_READABILITY_POLISH.md)

## Reference campaign structure

```text
campaigns/epochbound_demo/
  campaign.json
  maps/
  objects/
  items/
  recipes/
  story/
  capabilities/
  economy/
  cinematics/
  presentation/
  audio/
  animation/
```

Built-in campaigns live under `res://campaigns`. Installed player campaigns live under `user://campaigns` and use the same runtime and validation contracts.

## Run

Open `project.godot` in Godot 4.6.2 and run the main scene.

The project uses a 640 by 360 viewport, a 1280 by 720 window override, pixel snapping and nearest-neighbour texture filtering.

## Controls

The table shows the authored defaults. The fourteen gameplay actions can be changed under **Options → Controls**.

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | WASD or arrows | D-pad or left stick |
| Attack or fire | Space or C | East face button |
| Reload | G | Right trigger |
| Confirm, interact or enter | E or Z | South face button |
| Shift era | Q or X | West face button |
| Cycle Morrow command | R | North face button |
| Recall Morrow | F | Left shoulder |
| Field Satchel | I | Back or View |
| Quick restorative | V | Right shoulder |
| Journal | J | Right stick click |
| Save Profiles | K | Left stick click |
| Pause, back or skip | Escape | Start |
| Open Options directly | O | Pause, then confirm |

Escape, O and Start are fixed recovery controls and are not assignable to gameplay actions. Keyboard capture accepts one physical key without Shift, Alt, Ctrl or Meta. Menus use Left and Right for tabs or modes, Up and Down for selection, and the active Interact binding or controller confirm to act.

## Complete local validation

From Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound

.\scripts\validate.ps1 `
    -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

The gate performs:

- direct compilation of runtime, resources, validators, all seventeen editor plugins and every smoke test;
- warning-safe semantic editor-tab icon resolution with a checked shared fallback across all seventeen plugins;
- bounded headless runtime disposal that drains procedural Audio playback before every full-scene test exits;
- focused player-settings, persistent-control and regional-supply compile probes;
- strict headless project import;
- complete content validation through Sprite Animation plus regional supply;
- repository-wide ten-probe campaign production audit with progression, affordability, deterministic economy balance, meaningful temporal-shift consequences and supply evidence;
- exact-main schema-2.10 release evidence with `economyBalanceValidation`, `localisationValidation` and `localisationLayoutValidation` bound to the validated production SHA;
- a strict reference-campaign release gate requiring zero content errors, audit blockers or review warnings;
- every inherited world, combat, companion, item, story, save, loadout, economy, Arsenal, Boss, Cinematic, Package, Audit, Presentation and Audio regression;
- schema migration, atomic settings recovery, fixed recovery inputs, physical-key-only capture, conflict-safe swaps, exact `InputMap` replacement and bounded control-cache regressions;
- measured English and pseudo-localised fixed-viewport layout, deterministic font reduction, bounded wrapping and visible ellipsis regressions;
- deterministic supply intervals, bounded catch-up, target caps, full-stock cursor persistence, old-save safety and malformed-content regressions;
- Sprite runtime, editor, atlas, malformed-content, scaffolding and package-promotion regressions;
- animated-terrain, movement-response, pause-freezing, era-reset and bounded-environment regressions;
- projectile camera conversion, shared combat depth, ammo HUD, boss status, duplicate suppression and pause-layer regressions;
- boss phase stem references, deterministic phase selection, era continuity, clock resets and final-phase escalation;
- eight completed-world laps covering 32 map transitions, 16 era shifts, 13 supply cycles, eight checkpoints and four destructive restorations without completed-boss re-engagement or duplicate progression rewards;
- real ENet host shutdown with two unique peer acknowledgements, reliable commit, final offline state and independent zero-exit child processes.
- real unexpected-host process loss followed by same-client automatic recovery to a replacement ENet host on the same literal endpoint, later production input and snapshot exchange, and acknowledged final shutdown.

Any logged `SCRIPT ERROR:` or top-level `ERROR:` fails the gate even if Godot returns exit code zero. Missing editor-theme icons and `ObjectDB instances leaked at exit` also fail validation, preventing unchecked editor resources or incomplete runtime teardown from returning to the supported Godot editor.

## Governed GitHub validation

The primary `validate.yml` workflow runs automatically for every push to `main` and remains manually dispatchable for an exact-SHA rerun. The focused Audio, Sprite and Linux Agent workflows remain manual, exact-SHA and read-only.

To request exact reruns from `main`:

```powershell
$Sha = git rev-parse HEAD

gh workflow run validate.yml `
    --ref main `
    -f expected_sha=$Sha `
    -f request_source=evavo-development-studio

gh workflow run audio-mood-validation.yml `
    --ref main `
    -f expected_sha=$Sha `
    -f request_source=evavo-development-studio

gh workflow run sprite-animation-validation.yml `
    --ref main `
    -f expected_sha=$Sha `
    -f request_source=evavo-development-studio
```

The workflows verify the official Godot 4.6.2 archive against published SHA-512 sums, check out the exact commit, run their governed gates and confirm validation leaves tracked source unchanged. The primary receipt records zero reference content warnings, zero reference audit warnings, passed meaningful temporal-shift validation, `bossMusicStemValidation`, `longFormProgressionValidation`, `multiplayerHostRestartRecoveryValidation`, and a passed warning-free release-readiness gate. Runtime composition, player settings, persistent controls and regional supply contracts are checked before Godot starts. None of these validation workflows can publish, deploy, reset, clean or push repository content.

A separate pinned Linux Agent QA workflow performs visual, keyboard, gamepad and menu-surface checks through the EVAVO Godot test lab.

## Documentation

### World and encounters

- [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md)
- [`docs/WORLD_BUILDER.md`](docs/WORLD_BUILDER.md)
- [`docs/ENCOUNTER_STUDIO.md`](docs/ENCOUNTER_STUDIO.md)
- [`docs/COMBAT_DIRECTOR.md`](docs/COMBAT_DIRECTOR.md)
- [`docs/COMPANION_STUDIO.md`](docs/COMPANION_STUDIO.md)

### Items, story, saves and economy

- [`docs/ITEM_FORGE.md`](docs/ITEM_FORGE.md)
- [`docs/STORY_STUDIO.md`](docs/STORY_STUDIO.md)
- [`docs/SAVE_STATE_STUDIO.md`](docs/SAVE_STATE_STUDIO.md)
- [`docs/LOADOUT_STUDIO.md`](docs/LOADOUT_STUDIO.md)
- [`docs/MERCHANT_ECONOMY_STUDIO.md`](docs/MERCHANT_ECONOMY_STUDIO.md)
- [`docs/ECONOMY_PLAYTEST_CHECKLIST.md`](docs/ECONOMY_PLAYTEST_CHECKLIST.md)
- [`docs/ECONOMY_BALANCE_SIMULATION.md`](docs/ECONOMY_BALANCE_SIMULATION.md)

### Player accessibility and controls

- [`docs/PLAYER_SETTINGS.md`](docs/PLAYER_SETTINGS.md)
- [`docs/LOCALISATION_FOUNDATION.md`](docs/LOCALISATION_FOUNDATION.md)
- [`docs/LOCALISATION_LAYOUT_SAFETY.md`](docs/LOCALISATION_LAYOUT_SAFETY.md)
- [`docs/EDITOR_PLUGIN_RELIABILITY.md`](docs/EDITOR_PLUGIN_RELIABILITY.md)
- [`docs/HEADLESS_RUNTIME_CLEANUP.md`](docs/HEADLESS_RUNTIME_CLEANUP.md)
- [`docs/MULTIPLAYER_LOOPBACK_GATE.md`](docs/MULTIPLAYER_LOOPBACK_GATE.md)
- [`docs/MULTIPLAYER_HOST_RESTART_RECOVERY.md`](docs/MULTIPLAYER_HOST_RESTART_RECOVERY.md)

### Combat, bosses and cinematics

- [`docs/ARSENAL_STUDIO.md`](docs/ARSENAL_STUDIO.md)
- [`docs/ARSENAL_PLAYTEST_CHECKLIST.md`](docs/ARSENAL_PLAYTEST_CHECKLIST.md)
- [`docs/BOSS_PHASE_STUDIO.md`](docs/BOSS_PHASE_STUDIO.md)
- [`docs/BOSS_PLAYTEST_CHECKLIST.md`](docs/BOSS_PLAYTEST_CHECKLIST.md)
- [`docs/CINEMATIC_TIMELINE_STUDIO.md`](docs/CINEMATIC_TIMELINE_STUDIO.md)
- [`docs/CINEMATIC_PLAYTEST_CHECKLIST.md`](docs/CINEMATIC_PLAYTEST_CHECKLIST.md)
- [`docs/COMBAT_READABILITY_POLISH.md`](docs/COMBAT_READABILITY_POLISH.md)

### Release, audit and presentation

- [`docs/PACKAGE_RELEASE_STUDIO.md`](docs/PACKAGE_RELEASE_STUDIO.md)
- [`docs/PACKAGE_PLAYTEST_CHECKLIST.md`](docs/PACKAGE_PLAYTEST_CHECKLIST.md)
- [`docs/CAMPAIGN_AUDIT_STUDIO.md`](docs/CAMPAIGN_AUDIT_STUDIO.md)
- [`docs/AUDIT_PLAYTEST_CHECKLIST.md`](docs/AUDIT_PLAYTEST_CHECKLIST.md)
- [`docs/CANONICAL_JOURNEY_GATE.md`](docs/CANONICAL_JOURNEY_GATE.md)
- [`docs/LONG_FORM_PROGRESSION_PLAYTHROUGHS.md`](docs/LONG_FORM_PROGRESSION_PLAYTHROUGHS.md)
- [`docs/PRESENTATION_FEEL_STUDIO.md`](docs/PRESENTATION_FEEL_STUDIO.md)
- [`docs/PRESENTATION_PLAYTEST_CHECKLIST.md`](docs/PRESENTATION_PLAYTEST_CHECKLIST.md)
- [`docs/AUDIO_MOOD_STUDIO.md`](docs/AUDIO_MOOD_STUDIO.md)
- [`docs/BOSS_MUSIC_STEMS.md`](docs/BOSS_MUSIC_STEMS.md)
- [`docs/AUDIO_PLAYTEST_CHECKLIST.md`](docs/AUDIO_PLAYTEST_CHECKLIST.md)
- [`docs/SPRITE_ANIMATION_STUDIO.md`](docs/SPRITE_ANIMATION_STUDIO.md)
- [`docs/SPRITE_ANIMATION_PLAYTEST_CHECKLIST.md`](docs/SPRITE_ANIMATION_PLAYTEST_CHECKLIST.md)
- [`docs/ANIMATION_DEPTH_POLISH.md`](docs/ANIMATION_DEPTH_POLISH.md)
- [`docs/ADVENTURE_FEEDBACK_POLISH.md`](docs/ADVENTURE_FEEDBACK_POLISH.md)
- [`docs/ENVIRONMENT_ANIMATION_POLISH.md`](docs/ENVIRONMENT_ANIMATION_POLISH.md)

### Formats and vision

- [`docs/GAME_VISION.md`](docs/GAME_VISION.md)
- [`docs/GAME_DESIGN_RESEARCH.md`](docs/GAME_DESIGN_RESEARCH.md)
- [`docs/CAMPAIGN_FORMAT.md`](docs/CAMPAIGN_FORMAT.md)
- [`docs/OBJECT_FORMAT.md`](docs/OBJECT_FORMAT.md)

## Design principles

- Originality before imitation
- Player and companion readability before decorative detail
- Visible timing before unexplained damage
- Stable IDs before scene-tree serialization
- Data-driven authoring before hidden runtime exceptions
- Checked editor-theme lookups before unchecked visual fallbacks
- Atomic transactions before partial mutation
- Fixed recovery controls before unrestricted remapping
- Deterministic active-play clocks before wall-clock rewards
- Meaningful era consequences before palette-only shifts
- Bounded recovery supply without erasing progression scarcity
- Skippable presentation with progression-equivalent outcomes
- Campaign portability with strict validation and safe installation
- Low-resolution authenticity with modern reliability and accessibility
- Music, animation, environmental motion and sound that reinforce place and action without copying protected works

## Next production boundaries

The next coherent layers build on these contracts rather than replacing them: final original sprite atlases and animation masters, recorded ambience, sound effects and music masters, broader multi-boss music authoring previews, final economy tuning from human playtests, production translations beyond English and pseudo-localisation, host migration and production relay, matchmaking and NAT-traversal infrastructure.

### Host-directed disconnect ordering

After every registered client acknowledges the shutdown request, the host broadcasts one reliable commit and keeps the ENet server alive for a bounded flush window. Clients become quiescent but remain connected. The host then disconnects each captured peer, waits for those disconnects to be observed or for the bounded disconnect grace to expire, and only then closes the server. This prevents a client-side close from racing a later high-level send and proves that all peers return offline without harness-forced termination.
