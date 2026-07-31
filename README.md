# Epochbound

Epochbound is an original Godot 4.6.2 action RPG and campaign-authoring platform built around a boy, his dog, and places that exist in more than one age.

The project draws on broad strengths of premium mid-1990s console adventures: readable low-resolution silhouettes, tactile real-time combat, deliberate camera movement, compact framed interfaces, environmental mystery, strong companion behaviour, and authored surprise. Its world, cast, maps, creatures, dialogue, systems, terminology, procedural visuals, documentation, and future art/audio are original to Epochbound.

It does **not** reproduce protected characters, locations, sprites, portraits, dialogue, music, sound effects, story scenes, maps, or exact interface designs from Secret of Evermore or any other existing game.

## Current playable foundation

The reference campaign, **The Hours Beneath**, currently provides:

1. EVAVO Studio splash, title, campaign browser, and campaign-defined prologue
2. Three connected scrolling maps: Bellweather Crossing, Clockwood Edge, and Museum Underworks
3. Verdant and Ashen versions of each location
4. Eight-direction movement, authored collision, navigation, entries, recovery anchors, and return routes
5. Eli and his dog Morrow with Follow, Stay, Seek, Guard, and Recall behaviour
6. Reusable NPC, prop, enemy, pickup, merchant, and boss definitions
7. Telegraphed action combat with stagger, knockback, defence, projectiles, ammunition, and reloads
8. Encounter zones with activation, patrol, pursuit, leash return, reinforcement, and clearing
9. Items, equipment, capabilities, consumables, recipes, crafting, and quick-use healing
10. Branching conversations, typed conditions/effects, multi-stage quests, objectives, and Journal
11. Campaign currencies, finite merchant stock, atomic buying/selling, and durable economy state
12. A three-phase cross-era Underworks Sentinel boss encounter
13. Skippable, progression-equivalent cinematic timelines
14. Versioned save profiles, migrations, checksums, autosave, manual slots, backup recovery, and Continue
15. Deterministic campaign packages with manifests, SHA-256 verification, staging, and safe installation
16. Repository-wide campaign audits for reachability, capability sources, economy recovery, quest starts, and save safety
17. Original map/era presentation profiles with camera feel, atmosphere, restrained screen texture, framed HUD, procedural silhouettes, and tactile impact feedback

The runtime still uses procedural drawing for much of its blockout art. These visuals establish scale, silhouette, colour, feedback, camera, interface, collision, combat, and cinematic contracts before the final pixel-art and audio pipeline is introduced.

## Fifteen connected Godot authoring tools

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
```

Every tool writes inspectable campaign data and reuses stable IDs across the same runtime. No editor creates a hidden parallel database.

### Campaign

Authors maps, eras, terrain, collision, navigation, spawns, entries, recovery anchors, interactions, and cross-map travel.

### Encounter

Authors reusable props, NPCs, enemies, pickups, and their map placements.

### Combat

Directs encounter zones, activation, patrols, windups, leashes, stagger, knockback, and persistent clearing.

### Companion

Authors Morrow’s command profile, scent/clue/resource cues, recovery, Guard behaviour, and one-time discoveries.

### Items

Authors inventory items, consumables, materials, equipment, ammunition, recipes, rewards, crafting, and starting inventory.

### Story

Authors conversation graphs, choices, typed conditions/effects, quests, stages, objectives, and rewards.

### State

Inspects, validates, migrates, recovers, and deletes durable player save profiles.

### Loadout

Authors equipment slots, starting gear, derived statistics, semantic capabilities, and capability-gated world/story records.

### Trade

Authors currencies, merchant availability, stock, pricing, sales rules, and reusable NPC shop bindings.

### Arsenal

Authors ammunition, ranged weapons, projectile behaviour, reload timing, and enemy projectile profiles.

### Boss

Authors arena bounds, exit locks, phases, thresholds, attack-pattern sequences, reinforcements, and one-time outcomes.

### Cinematic

Authors camera tracks, actor movement, dialogue, waits, fades, era changes, effects, checkpoints, and save-safe skip outcomes.

### Package

Authors release metadata and exports/imports data-only `.epochbound.zip` campaign packages with tamper-evident manifests.

### Audit

Runs deterministic production probes and exports machine-readable blocker/warning reports for humans and maintenance agents.

### Presentation

Authors original 16-bit palette, atmosphere, camera deadzone/follow/look-ahead, bounded shake, screen texture, and actor-motion profiles by map and era.

## Original 16-bit presentation pass

The current Presentation layer adds:

- six reference profiles, one for every map/era combination;
- distinct Verdant and Ashen value/hue relationships;
- profile-driven camera follow, deadzone, directional look-ahead, and bounded shake;
- a separate CanvasLayer that keeps HUD and dialogue stationary during world-camera movement;
- hard-edged procedural silhouettes for Eli, Morrow, NPCs, enemies, props, and pickups;
- facing-aware weapon shapes and a capability-aware flashlight cone;
- deterministic pollen, dust, fireflies, embers, and cinders;
- footstep puffs, impact bursts, era flashes, and attack glints;
- notched health bars and a compact original framed interface;
- restrained scanline, dither, and vignette treatment.

This is a production blockout, not a recreation of another game’s graphics. Final Epochbound sprites and animation can replace the procedural shapes without changing the profile, camera, validation, or campaign contracts.

Read:

- [`docs/PRESENTATION_FEEL_STUDIO.md`](docs/PRESENTATION_FEEL_STUDIO.md)
- [`docs/PRESENTATION_PLAYTEST_CHECKLIST.md`](docs/PRESENTATION_PLAYTEST_CHECKLIST.md)

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
```

Built-in source campaigns live under `res://campaigns`. Installed player campaigns live under `user://campaigns` and use the same validation/runtime contracts.

## Run

Open `project.godot` in Godot 4.6.2 and run the main scene.

The project uses a 640×360 viewport with a 1280×720 window override and nearest-neighbour texture filtering.

## Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | WASD or arrows | D-pad or left stick |
| Attack or fire | Space or C | East face button |
| Reload | G | Right trigger |
| Confirm, interact, or enter | E or Z | South face button |
| Shift era | Q or X | West face button |
| Cycle Morrow command | R | North face button |
| Recall Morrow | F | Left stick click |
| Field Satchel | I | Back / View |
| Quick restorative | V | Right shoulder |
| Journal | J | Right stick click |
| Save Profiles | K | Left stick click |
| Pause, back, or skip | Escape | Start |

Menus use Left/Right for tabs or modes, Up/Down for selection, and E, Z, Space, C, or controller confirm to act.

## Complete local validation

From Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound

.\scripts\validate.ps1 `
    -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

The gate performs:

- direct compilation of the runtime, resources, validators, all fifteen editor plugins, and every smoke test;
- strict headless project import;
- complete content validation through Presentation Validator;
- repository-wide campaign production audit;
- all inherited world, combat, companion, item, story, save, loadout, economy, Arsenal, Boss, Cinematic, Package, and Audit regressions;
- presentation profile/runtime/editor/malformed-content regressions.

Any logged `SCRIPT ERROR:` or top-level `ERROR:` fails the gate even if Godot returns exit code zero.

## Governed GitHub validation

The exact-candidate workflow is manual by design. Dispatch `.github/workflows/validate.yml` from `main` with the current 40-character SHA:

```powershell
gh workflow run validate.yml `
    --ref main `
    -f expected_sha=$(git rev-parse HEAD) `
    -f request_source=evavo-development-studio
```

The workflow checks out that exact commit, verifies the official Godot 4.6.2 archive against the published SHA-512 sums, runs the complete gate, confirms validation did not modify tracked source, and uploads a bounded receipt.

A separate pinned Linux Agent QA workflow performs visual, keyboard, gamepad, and menu-surface checks through the EVAVO Godot test lab.

## Documentation

### World and encounters

- [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md)
- [`docs/WORLD_BUILDER.md`](docs/WORLD_BUILDER.md)
- [`docs/ENCOUNTER_STUDIO.md`](docs/ENCOUNTER_STUDIO.md)
- [`docs/COMBAT_DIRECTOR.md`](docs/COMBAT_DIRECTOR.md)
- [`docs/COMPANION_STUDIO.md`](docs/COMPANION_STUDIO.md)

### Items, story, saves, and economy

- [`docs/ITEM_FORGE.md`](docs/ITEM_FORGE.md)
- [`docs/STORY_STUDIO.md`](docs/STORY_STUDIO.md)
- [`docs/SAVE_STATE_STUDIO.md`](docs/SAVE_STATE_STUDIO.md)
- [`docs/LOADOUT_STUDIO.md`](docs/LOADOUT_STUDIO.md)
- [`docs/MERCHANT_ECONOMY_STUDIO.md`](docs/MERCHANT_ECONOMY_STUDIO.md)
- [`docs/ECONOMY_PLAYTEST_CHECKLIST.md`](docs/ECONOMY_PLAYTEST_CHECKLIST.md)

### Combat, bosses, and cinematics

- [`docs/ARSENAL_STUDIO.md`](docs/ARSENAL_STUDIO.md)
- [`docs/ARSENAL_PLAYTEST_CHECKLIST.md`](docs/ARSENAL_PLAYTEST_CHECKLIST.md)
- [`docs/BOSS_PHASE_STUDIO.md`](docs/BOSS_PHASE_STUDIO.md)
- [`docs/BOSS_PLAYTEST_CHECKLIST.md`](docs/BOSS_PLAYTEST_CHECKLIST.md)
- [`docs/CINEMATIC_TIMELINE_STUDIO.md`](docs/CINEMATIC_TIMELINE_STUDIO.md)
- [`docs/CINEMATIC_PLAYTEST_CHECKLIST.md`](docs/CINEMATIC_PLAYTEST_CHECKLIST.md)

### Release, audit, and presentation

- [`docs/PACKAGE_RELEASE_STUDIO.md`](docs/PACKAGE_RELEASE_STUDIO.md)
- [`docs/PACKAGE_PLAYTEST_CHECKLIST.md`](docs/PACKAGE_PLAYTEST_CHECKLIST.md)
- [`docs/CAMPAIGN_AUDIT_STUDIO.md`](docs/CAMPAIGN_AUDIT_STUDIO.md)
- [`docs/AUDIT_PLAYTEST_CHECKLIST.md`](docs/AUDIT_PLAYTEST_CHECKLIST.md)
- [`docs/PRESENTATION_FEEL_STUDIO.md`](docs/PRESENTATION_FEEL_STUDIO.md)
- [`docs/PRESENTATION_PLAYTEST_CHECKLIST.md`](docs/PRESENTATION_PLAYTEST_CHECKLIST.md)

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

## Next production boundaries

The next coherent layers build on these contracts rather than replacing them: final sprite/animation import pipelines, authored audio and music direction, localisation, regional merchant restocking and scarcity, accessibility settings for presentation intensity, and automated progression/affordability/softlock probes.
