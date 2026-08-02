# Epochbound

Epochbound is an original Godot 4.6.2 action RPG and campaign-authoring platform built around a boy, his dog, and places that exist in more than one age.

The project draws on broad strengths of premium mid-1990s console adventures: readable low-resolution silhouettes, responsive real-time combat, compact framed interfaces, environmental mystery, a useful animal companion, strong location identity, deliberate camera movement, concise animation and authored surprise. Its world, cast, maps, creatures, dialogue, systems, terminology, procedural art, frame timing, music patterns, sound design and future mastered assets are original to Epochbound.

It does **not** reproduce protected characters, locations, sprites, animation sheets, portraits, dialogue, music, sound effects, story scenes, maps, samples or exact interface designs from *Secret of Evermore* or any other existing game.

## Current playable foundation

The reference campaign, **The Hours Beneath**, currently provides:

1. EVAVO Studio splash, title, campaign browser and campaign-defined prologue
2. Three connected scrolling maps: Bellweather Crossing, Clockwood Edge and Museum Underworks
3. Verdant and Ashen versions of each location
4. Eight-direction movement, authored collision, navigation, entries, recovery anchors and return routes
5. Eli and his dog Morrow with Follow, Stay, Seek, Guard and Recall behaviour
6. Reusable NPC, prop, enemy, pickup, merchant and boss definitions
7. Telegraphed action combat with stagger, knockback, defence, projectiles, ammunition and reloads
8. Encounter zones with activation, patrol, pursuit, leash return, reinforcement and clearing
9. Items, equipment, capabilities, consumables, recipes, crafting and quick-use healing
10. Branching conversations, typed conditions and effects, multi-stage quests, objectives and Journal
11. Campaign currencies, finite merchant stock, atomic buying and selling, and durable economy state
12. A three-phase cross-era Underworks Sentinel boss encounter
13. Skippable, progression-equivalent cinematic timelines
14. Versioned save profiles, migrations, checksums, autosave, manual slots, backup recovery and Continue
15. Deterministic campaign packages with manifests, SHA-256 verification, staging and safe installation
16. Repository-wide campaign audits for reachability, capability definitions, progression sources, recipe unlocks and cycles, finite supply, merchant bindings, affordability, quest starts and save safety
17. Original map and era presentation profiles with camera feel, atmosphere, restrained screen texture and framed HUD
18. Original procedural music, environmental ambience, dynamic combat layers, mix ducking and event-driven sound feedback
19. Frame-based Sprite Animation profiles with four-direction timing, attack anticipation, Morrow gait, atlas import and procedural fallbacks
20. Animated water, grass sway, brass machinery cycles, material-specific foot response, foreground occlusion and contextual world feedback
21. Camera-correct projectiles, shared combat depth, presentation-owned ammo and boss status, and pause-safe CanvasLayer ordering

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

Inspects, validates, migrates, recovers and deletes durable player save profiles.

### Loadout

Authors equipment slots, starting gear, derived statistics, semantic capabilities and capability-gated world and story records.

### Trade

Authors currencies, merchant availability, stock, pricing, sale rules and reusable NPC shop bindings.

### Arsenal

Authors ammunition, ranged weapons, projectile behaviour, reload timing and enemy projectile profiles.

### Boss

Authors arena bounds, exit locks, phases, thresholds, attack-pattern sequences, reinforcements and one-time outcomes.

### Cinematic

Authors camera tracks, actor movement, dialogue, waits, fades, era changes, effects, checkpoints and save-safe skip outcomes.

### Package

Authors release metadata and exports or imports data-only `.epochbound.zip` campaign packages with tamper-evident manifests.

### Audit

Runs eight deterministic production probes covering structural reachability, recovery, progression-source softlocks and merchant-only affordability, then exports machine-readable blocker and warning reports for people and maintenance agents.

### Presentation

Authors original 16-bit palette, atmosphere, camera deadzone, follow and look-ahead, bounded shake, screen texture and actor-motion profiles by map and era.

### Audio

Authors original procedural music scales and patterns, ambience character, dynamic combat gain, menu, dialogue and cinematic ducking, and safe crossfade timing by map and era.

### Sprite

Authors frame dimensions, render size, pivots, one-row or four-direction layouts, optional transparent PNG atlases, fallback style and idle, walk, attack and hurt timing.

## Original 16-bit presentation, audio and animation

### Presentation

The Presentation layer provides:

- six reference profiles, one for every map and era combination;
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

- one title and prologue profile plus six map and era profiles;
- original scale-degree melody and bass patterns;
- bounded pulse, triangle and sine synthesis;
- deterministic room tone, pollen, insects, embers, cinders, machinery and furnace ambience;
- a combat layer that fades over the continuing exploration theme;
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

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | WASD or arrows | D-pad or left stick |
| Attack or fire | Space or C | East face button |
| Reload | G | Right trigger |
| Confirm, interact or enter | E or Z | South face button |
| Shift era | Q or X | West face button |
| Cycle Morrow command | R | North face button |
| Recall Morrow | F | Left stick click |
| Field Satchel | I | Back or View |
| Quick restorative | V | Right shoulder |
| Journal | J | Right stick click |
| Save Profiles | K | Left stick click |
| Pause, back or skip | Escape | Start |

Menus use Left and Right for tabs or modes, Up and Down for selection, and E, Z, Space, C or controller confirm to act.

## Complete local validation

From Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound

.\scripts\validate.ps1 `
    -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

The gate performs:

- direct compilation of runtime, resources, validators, all seventeen editor plugins and every smoke test;
- strict headless project import;
- complete content validation through the strict Sprite Animation validator;
- repository-wide eight-probe campaign production audit, including progression-source and affordability analysis;
- every inherited world, combat, companion, item, story, save, loadout, economy, Arsenal, Boss, Cinematic, Package, Audit, Presentation and Audio regression;
- Sprite runtime, editor, atlas, malformed-content, scaffolding and package-promotion regressions;
- animated-terrain, movement-response, pause-freezing, era-reset and bounded-environment regressions;
- projectile camera conversion, shared combat depth, ammo HUD, boss status, duplicate suppression and pause-layer regressions.

Any logged `SCRIPT ERROR:` or top-level `ERROR:` fails the gate even if Godot returns exit code zero.

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

The workflows verify the official Godot 4.6.2 archive against published SHA-512 sums, check out the exact commit, run their governed gates and confirm validation leaves tracked source unchanged. None of these validation workflows can publish, deploy, reset, clean or push repository content.

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
- [`docs/PRESENTATION_FEEL_STUDIO.md`](docs/PRESENTATION_FEEL_STUDIO.md)
- [`docs/PRESENTATION_PLAYTEST_CHECKLIST.md`](docs/PRESENTATION_PLAYTEST_CHECKLIST.md)
- [`docs/AUDIO_MOOD_STUDIO.md`](docs/AUDIO_MOOD_STUDIO.md)
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
- Atomic transactions before partial mutation
- Skippable presentation with progression-equivalent outcomes
- Campaign portability with strict validation and safe installation
- Low-resolution authenticity with modern reliability and accessibility
- Music, animation, environmental motion and sound that reinforce place and action without copying protected works

## Next production boundaries

The next coherent layers build on these contracts rather than replacing them: final original sprite atlases and animation masters, recorded ambience, sound effects and music masters, localisation, regional merchant restocking and scarcity, boss phase-specific music stems, controller remapping, automated long-form progression playthroughs and deeper economy-balance simulation.
