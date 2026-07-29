# Epochbound

Epochbound is an original Godot 4.6.2 action RPG designed with the pacing, readability, tactile movement and authored surprise of a premium lost 1990s console adventure.

It is influenced by the design strengths of classic action RPGs and timeline-spanning adventures, but uses an entirely original world, cast, narrative, terminology, artwork and audio.

## Current playable slice

The repository now boots directly into a complete prototype flow:

1. EVAVO Studio splash
2. Animated title screen and menu
3. Skippable three-beat prologue
4. Playable exploration field
5. Responsive eight-direction movement
6. Morrow, a dog companion with distance-based follow behaviour
7. Contextual interactions and dialogue
8. Instant shifting between the Verdant and Ashen versions of the field
9. Pause and resume flow

The prototype uses Godot drawing primitives so it runs without external art assets. These placeholders establish composition, scale, timing and interaction contracts for the future pixel-art pipeline.

## Run

Open the repository folder in Godot 4.6.2 and press **F6** or **F5**.

### Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | WASD or arrow keys | D-pad / left stick |
| Confirm / interact | E or Z | South face button |
| Shift era | Q or X | West face button |
| Pause / skip | Escape | Start |

## Design pillars

- A loyal animal companion who is useful in exploration, combat and story
- Multiple versions of places whose changes matter mechanically
- Fast, readable real-time action combat without input clutter
- Dense environmental storytelling, puzzles, secrets and optional discoveries
- Cinematic sequences that respect player control and can be skipped
- Distinct regional systems instead of repeated content with new colours
- Strong authored pacing supported by data-driven production tools
- Authentic low-resolution presentation with modern accessibility and reliability

## Repository direction

The next slices will separate the prototype into production systems: flow orchestration, save profiles, world state, actors, companion orders, dialogue graphs, interactions, era transitions, combat, inventory, quests, authored scenes and editor-facing validation.

See [`docs/GAME_VISION.md`](docs/GAME_VISION.md) for the originality and design contract.
