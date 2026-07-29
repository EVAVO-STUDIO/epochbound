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
6. A campaign-defined animal companion with navigation and recovery behaviour
7. Contextual interactions and era-specific dialogue
8. Shifting between mechanically different versions of the same location
9. Named map entries and validated cross-map connections
10. Bidirectional travel between Bellweather Crossing and Clockwood Edge
11. Pause, resume and safe transition flow

The runtime currently uses Godot drawing primitives so it remains executable before final artwork exists. These placeholders establish composition, scale, timing, camera, traversal and interaction contracts for the future pixel-art pipeline.

## Campaign Studio

Epochbound includes a dedicated **Campaign** main-screen editor inside Godot. It can now:

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
- validate the complete campaign before play;
- run authored campaigns through the same runtime as the reference journey.

Canvas controls:

| Action | Input |
| --- | --- |
| Paint or place | Left mouse button |
| Erase current scoped cell | Right mouse button |
| Pan canvas | Middle mouse drag |
| Zoom canvas | Mouse wheel |

Source campaigns live under `res://campaigns`. Installed player campaigns are discovered under `user://campaigns`.

Read [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md) for the complete editor workflow, [`docs/WORLD_BUILDER.md`](docs/WORLD_BUILDER.md) for map-production rules and [`docs/CAMPAIGN_FORMAT.md`](docs/CAMPAIGN_FORMAT.md) for the versioned JSON contract.

## Run

Open `project.godot` in Godot 4.6.2 and press **F6** or **F5**.

### Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | WASD or arrow keys | D-pad / left stick |
| Confirm, interact or use entrance | E or Z | South face button |
| Shift era | Q or X | West face button |
| Back, pause or skip | Escape | Start |

## Validate

From Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

The local script performs a headless editor import and script parse followed by campaign validation. GitHub Actions additionally runs the executable world-model smoke test covering terrain blocking, explicit collision, era-scoped cells, navigation, recovery anchors and cross-map target resolution.

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

## Documentation

- [`docs/GAME_VISION.md`](docs/GAME_VISION.md): originality and player promise
- [`docs/GAME_DESIGN_RESEARCH.md`](docs/GAME_DESIGN_RESEARCH.md): research synthesis and map-quality rubric
- [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md): editor workflow and authoring surfaces
- [`docs/WORLD_BUILDER.md`](docs/WORLD_BUILDER.md): terrain, navigation and connection production rules
- [`docs/CAMPAIGN_FORMAT.md`](docs/CAMPAIGN_FORMAT.md): data schema and migration rules

## Next production layers

The next vertical slices will build on the current world contract rather than replace it: authored object and tile sets, NPC and enemy placement, encounter zones, companion commands, dialogue and quest graphs, deterministic world state, save profiles, combat, inventory, crafting, bosses, cinematics, campaign packaging and automated softlock probes.
