# Epochbound Campaign Studio

Campaign Studio is the in-editor authoring surface for making original Epochbound campaigns, maps and game variations without rewriting the runtime.

It appears as the **Campaign** main-screen tab in Godot 4.6.2 and is enabled by default in this repository.

## Current authoring workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Campaign** tab at the top of the editor.
3. Choose an existing campaign or enter an identifier and select **New Campaign**.
4. Add maps with stable lowercase identifiers.
5. Select an era to preview that version of the current map.
6. Choose a terrain brush and paint the main traversal language of the level.
7. Paint collision where terrain alone does not describe a solid obstacle.
8. Paint the companion navigation network through the intended routes.
9. Place player and companion default spawns.
10. Add named entry points for every incoming route.
11. Add recovery anchors near traversal regions and transition destinations.
12. Add interactions and author dialogue for each relevant era.
13. Add map connections and select their target map, target entry, target era and trigger.
14. Select **Validate All** before running the game.
15. Run the project and choose **Campaigns** from the title screen to test the authored journey.

The editor saves deterministic, reviewable JSON. The runtime reads the same records directly, so preview data and game data never become competing sources of truth.

## Canvas controls

| Action | Input |
| --- | --- |
| Paint selected terrain, collision or navigation | Left mouse button or drag |
| Erase the current era scope | Right mouse button or drag |
| Place the selected marker tool | Left mouse button |
| Select a nearby marker | Select tool, then left mouse button |
| Pan | Middle mouse drag |
| Zoom | Mouse wheel |
| Return to automatic framing | **Reset View** |

Each paint drag becomes one undoable history entry. **Undo** and **Redo** restore the complete map record, then save the validated result.

## Current tools

### Select

Selects interactions, connections, entry points and recovery anchors. The inspector edits stable IDs, positions, radii, era availability, dialogue and connection targets.

### Paint Terrain

Paints sparse terrain cells using the current terrain palette. Terrain definitions own their display name, era-aware colours and whether the terrain blocks actors.

### Paint Collision

Adds explicit solid cells independently of terrain. Use this for walls, large props, structures and authored blockers that are not themselves terrain tiles.

### Paint Navigation

Creates the companion's preferred four-direction traversal network. If no navigation cells exist, the companion falls back to direct steering. A connected network is preferable for production maps because it makes routes inspectable and testable.

### Place Player and Place Companion

Updates the map's default starting positions. Named entry points are used when arriving from another map.

### Add Interaction

Creates a selectable interaction with a radius, optional era restriction and era-keyed dialogue.

### Add Connection

Creates an interact or touch transition. Every connection declares:

- a stable identifier;
- a world position and activation radius;
- a target map;
- a target entry point;
- `same` or an explicit target era;
- a trigger type;
- optional era availability.

Broken map, entry or era references fail campaign validation.

### Add Entry Point

Creates a named arrival record with separate player and companion positions. This prevents the companion appearing inside the player, a wall or the return trigger.

### Add Recovery Anchor

Creates an era-aware safe location used when the companion becomes separated or when a transition or era change leaves an actor in blocked space.

## Era scope

The **Selected era only** option applies to terrain, collision, navigation and newly placed markers.

- Disabled: the record applies in every era.
- Enabled: the record contains the selected era in `available_eras`.

A global cell and an era-specific cell may share a coordinate. The era-specific record overrides the global record for that era. Right-click erases only the currently selected scope, which prevents an era edit from accidentally deleting the global base.

## Overlays

The editor can independently display:

- collision cells;
- navigation cells;
- interactions, connections, entry points and recovery anchors.

Terrain and era landmarks remain visible beneath these production overlays. This makes it possible to review visual composition, walkability, companion routes and travel links together.

## Editor design principles

### Runtime and editor share contracts

A feature is not considered an editor feature until the runtime consumes the same authored record. Campaign Studio does not maintain a hidden editor-only database.

### Stable identifiers are permanent references

Campaign, map, era, layer, terrain, landmark, interaction, connection, entry and recovery identifiers use lowercase letters, numbers, underscores and hyphens. Display names may change freely. Identifier renaming should eventually use a reference-aware operation rather than manual search and replace.

### Era changes must affect play

Each era is a version of the same authored place. A useful era change should alter at least one of these:

- route or traversal;
- threat or encounter;
- information or dialogue;
- relationship or faction state;
- resource, crafting or quest state.

A palette-only duplicate is acceptable during blockout but is not sufficient for final content.

### Companion-safe levels

A production map should provide:

- a default companion spawn;
- companion positions on every entry point;
- a connected navigation network through intended routes;
- recovery anchors near major traversal regions;
- enough clearance around transition destinations to avoid immediate retriggering.

The runtime still has safe fallbacks, but those fallbacks are protection against defects rather than a replacement for authored level design.

### Safe experimentation

The format is inspectable and validation-first. Invalid colours, broken links, duplicate identifiers, out-of-grid cells, unknown terrain IDs, missing entries and invalid era references are reported before play.

## Content locations

`res://campaigns` contains campaigns shipped with the project. Campaign Studio writes there because it is an editor tool operating on source content.

`user://campaigns` is reserved for installed or player-created campaigns in exported builds. A user campaign with the same identifier as a built-in campaign takes precedence in the runtime catalogue, enabling controlled replacement and testing without changing packaged source content.

## Validation

From Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

GitHub Actions performs three gates:

1. headless project import and script/plugin parsing;
2. complete campaign and cross-map validation;
3. executable world-model smoke testing for collision, blocked terrain, era scoping, navigation, recovery and connection resolution.

A non-zero exit code blocks the production slice from merging.

## Next editor surfaces

The next production layers should extend the existing records rather than fork new map formats:

1. authored tile sets and object palettes
2. object placement, selection and transforms
3. NPC, enemy, loot and encounter placement
4. dialogue and quest graph editing
5. world-state conditions and consequences across eras
6. combat arenas, boss phases and encounter rehearsal
7. item, crafting, economy and progression databases
8. cinematic tracks, camera cues and skip-safety validation
9. campaign packaging, dependency checks and installed-content management
10. automated reachability and softlock probes

These should remain modular panels over one versioned campaign model.
