# Epochbound

Epochbound is an original Godot 4.6.2 action RPG and campaign-authoring platform designed with the pacing, readability, tactile movement and authored surprise of a premium lost 1990s console adventure.

It learns from the design strengths of classic action RPGs and timeline-spanning adventures while using an entirely original world, cast, narrative, terminology, artwork and audio.

## Current playable flow

The repository now provides:

1. EVAVO Studio splash
2. Animated title menu
3. Built-in and custom campaign browser
4. Validated campaign loading
5. Campaign-defined skippable prologues
6. Variable-size scrolling exploration maps
7. Responsive eight-direction movement
8. A campaign-defined animal companion with follow and recovery behaviour
9. Contextual interactions and era-specific dialogue
10. Shifting between authored versions of the same location
11. Pause and resume flow

The runtime currently uses Godot drawing primitives so it remains executable before final artwork exists. These placeholders establish composition, scale, timing, camera and interaction contracts for the future pixel-art pipeline.

## Campaign Studio

Epochbound includes its own Godot main-screen editor plugin. Open the project and select the **Campaign** tab to:

- create campaigns and starter maps;
- create additional maps;
- preview era-specific palettes and landmarks;
- place player and companion spawns;
- add and edit interactions;
- author dialogue per era;
- validate cross-file content before play;
- run authored campaigns through the same runtime as the reference game.

Source campaigns live under `res://campaigns`. Installed player campaigns are discovered under `user://campaigns`.

Read [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md) for the editor workflow and [`docs/CAMPAIGN_FORMAT.md`](docs/CAMPAIGN_FORMAT.md) for the versioned JSON contract.

## Run

Open `project.godot` in Godot 4.6.2 and press **F6** or **F5**.

### Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | WASD or arrow keys | D-pad / left stick |
| Confirm / interact | E or Z | South face button |
| Shift era | Q or X | West face button |
| Back, pause or skip | Escape | Start |

## Validate

From Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

This performs a headless editor import and script parse, followed by campaign and map validation.

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

## Documentation

- [`docs/GAME_VISION.md`](docs/GAME_VISION.md): originality and player promise
- [`docs/GAME_DESIGN_RESEARCH.md`](docs/GAME_DESIGN_RESEARCH.md): research synthesis and map-quality rubric
- [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md): editor workflow and roadmap
- [`docs/CAMPAIGN_FORMAT.md`](docs/CAMPAIGN_FORMAT.md): data schema and migration rules

## Next production layers

The next vertical slices will build on the current contracts rather than replace them: tile and terrain painting, collision and navigation editing, cross-map entrances, world state, save profiles, actor definitions, companion orders, dialogue graphs, quests, combat, inventory, crafting, encounters, cinematics and automated softlock detection.
