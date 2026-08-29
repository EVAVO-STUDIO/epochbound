# Epochbound Tile Map Studio binding

Epochbound is formally bound to `EVAVO-STUDIO/evavo-tile-map-studio`, but this directory does not yet contain a production Tile Map Studio manifest.

Canonical authority remains Epochbound campaign data, including its authored maps, Verdant/Ashen era variants, collision/navigation, entries, recovery anchors, encounter zones, progression and travel rules.

## Tracked integration contracts

`art-bindings.json` is the production-art boundary. It currently contains no bindings on purpose. Campaign Studio palette swatches and debug rendering are reference evidence, not final tile art. Each generated visual family such as `epochbound:verdant:terrain:grass` must eventually bind to real approved source art and a receipted Sprite Studio atlas region.

`era-parity.json` is the gameplay-parity boundary. Verdant/Ashen palette and landmark changes are presentation differences, but terrain/collision/navigation changes must be explicitly approved at an exact map cell. The current campaign intentionally declares only two such cells: the Ashen cliff in Bellweather Crossing `(24,11)` and the Ashen cliff in Clockwood Edge `(18,13)`. Unlisted topology drift must fail closed.

Tile Map Studio derives era-specific production candidates with runtime tile IDs qualified by era while retaining a stable `semantic_base_id` for gameplay parity checks. Entries, recovery anchors and portal topology are also compared across eras.

## Current blocker: approved terrain and landmark source art

Tile Map Studio now emits explicit Art Studio/Sprite Studio handoffs for both tile and feature families. For Epochbound these include:

- 16x16 era-specific terrain/material families,
- continuous-material variant/seam rules where appropriate,
- structural terrain rules for paths/cliffs/walls,
- era-specific landmark families such as trees/dead trees, ruins and wells,
- immutable semantic rules that artwork cannot change.

Art Studio owns source generation/authoring, style lock and creative approval. Sprite Studio owns lossless mastering, deterministic packing and build receipts. Tile Map Studio only trusts those atlas regions after `tile-map-import-sprite-bindings` verifies the Sprite Studio manifest, atlas page hashes and build receipt.

No debug palette tile, placeholder block or unapproved provider image may satisfy `art-bindings.json`.

The future production manifest is intended to live at:

```text
.evavo/tile-map/world.tilemap-build.json
```

Useful external evidence workflow from Tile Map Studio:

```powershell
tile-map-derive-consumers `
  C:\GitRepos\epochbound `
  C:\GitRepos\godot-462-transport-empire `
  C:\TileMapEvidence\consumer-derivation-001

.\scripts\Validate-TileMapConsumerArtPipeline.ps1 `
  -DerivationRoot C:\TileMapEvidence\consumer-derivation-001 `
  -ArtHandoffRoot C:\TileMapEvidence\consumer-art-handoffs-001
```

The evidence directory must remain outside the game repository.

Before promotion, a real integration must pass Tile Map Studio preflight/proof, real Godot round-trip validation, a reviewed tracked `.evavo/godot-lab-tile-map.json`, exact-SHA Godot Game Test Lab evidence, and creative review.
