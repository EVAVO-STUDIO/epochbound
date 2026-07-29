# Epochbound Campaign Studio

Campaign Studio is the in-editor authoring surface for making original Epochbound campaigns, maps and game variations without rewriting the runtime.

It appears as the **Campaign** main-screen tab in Godot 4.6.2. The plugin is enabled by default for this repository.

## Current authoring workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Campaign** tab at the top of the editor.
3. Choose the reference campaign or enter an identifier and select **New Campaign**.
4. Add maps with stable lowercase identifiers.
5. Select an era to preview that version of the current map.
6. Use the canvas tools to place the player spawn, companion spawn and interactions.
7. Select an interaction to edit its identifier, kind, radius, era availability and dialogue.
8. Select **Validate All** before running the game.
9. Run the project and choose **Campaigns** from the title screen to test the authored journey.

The editor snaps authored positions to the map grid and saves deterministic, reviewable JSON. The runtime reads the same files directly, so preview data and game data do not become parallel sources of truth.

## What the first editor slice supports

- Create campaigns with starter maps
- Create additional maps
- Browse campaign and map files
- Preview multiple era states
- Preview palettes and landmark composition
- Place player and companion spawns
- Add, select, edit and delete interactions
- Author era-specific interaction dialogue
- Restrict interactions to a selected era
- Validate campaign, map, era, layer, palette, spawn, landmark, interaction and connection records
- Launch authored campaigns from the in-game campaign browser
- Discover built-in campaigns from `res://campaigns`
- Discover installed player campaigns from `user://campaigns`

## Editor design principles

### Runtime and editor share contracts

A feature is not considered an editor feature until the runtime can consume the same authored record. Campaign Studio does not maintain a hidden editor-only database.

### Stable identifiers are permanent references

Campaign, map, era, layer, landmark and interaction identifiers use lowercase letters, numbers, underscores and hyphens. Display names may change freely; identifiers should only change through a future reference-aware rename operation.

### Era changes must affect play

Each era is a version of the same authored place. A useful era change should alter at least one of these:

- route or traversal;
- threat or encounter;
- information or dialogue;
- relationship or faction state;
- resource, crafting or quest state.

A palette-only duplicate is acceptable while blocking out a map, but should fail the final content-quality review.

### Safe experimentation

The authoring format is deliberately inspectable and validation-first. Invalid colours, broken map links, duplicate identifiers, missing spawns and out-of-bounds positions are reported before play.

### Companion-safe levels

Maps must provide a companion spawn even when a campaign temporarily disables the companion. Runtime recovery prevents the companion from being permanently lost during early blockout, while later navigation and collision tools will add authored recovery anchors and traversal capabilities.

## Content locations

`res://campaigns` contains campaigns shipped with the project. Campaign Studio writes here because it is an editor tool operating on source content.

`user://campaigns` is reserved for installed or player-created campaigns in exported builds. A user campaign with the same identifier as a built-in campaign takes precedence in the runtime catalogue, enabling controlled replacement and testing without altering packaged files.

## Validation

From Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

The script first asks Godot to import and parse the project in headless editor mode, then runs the campaign validator. A non-zero exit code means the slice should not be committed or exported.

## Planned editor surfaces

The next production layers should extend the existing map record rather than create separate tools:

1. Tile and terrain painting with layer visibility and locking
2. Collision, navigation and companion recovery overlays
3. Entrances, exits and cross-map connection editing
4. NPC, enemy, loot and encounter placement
5. Dialogue graph, quest graph and world-state condition editing
6. Combat arenas, boss phases and encounter rehearsal
7. Alchemy or crafting recipes, economy and item databases
8. Cinematic tracks, camera cues and skippable sequence validation
9. Campaign packaging, dependency checks and installed-content management
10. Automated playthrough probes for unreachable goals and softlocks

These should remain modular panels over one versioned campaign model.
