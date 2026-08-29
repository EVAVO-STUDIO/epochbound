# Epochbound Tile Map Studio binding

Epochbound is formally bound to `EVAVO-STUDIO/evavo-tile-map-studio`, but this directory does not yet contain a production Tile Map Studio manifest.

Canonical authority remains Epochbound campaign data, including its authored maps, Verdant/Ashen era variants, collision/navigation, entries, recovery anchors, encounter zones, progression and travel rules.

## Tracked integration contracts

`art-bindings.json` is the production-art boundary. It currently contains no bindings on purpose. Campaign Studio palette swatches and debug rendering are reference evidence, not final tile art. Each generated visual family such as `epochbound:verdant:terrain:grass` must eventually bind to a real 16x16 authored Art Studio, Sprite Studio, hand-authored or licensed source region.

`era-parity.json` is the gameplay-parity boundary. Verdant/Ashen palette and landmark changes are presentation differences, but terrain/collision/navigation changes must be explicitly approved at an exact map cell. The current campaign intentionally declares only two such cells: the Ashen cliff in Bellweather Crossing `(24,11)` and the Ashen cliff in Clockwood Edge `(18,13)`. Unlisted topology drift must fail closed.

Tile Map Studio now derives era-specific production candidates with runtime tile IDs qualified by era while retaining a stable `semantic_base_id` for gameplay parity checks. Entries, recovery anchors and portal topology are also compared across eras.

The future production manifest is intended to live at:

```text
.evavo/tile-map/world.tilemap-build.json
```

That manifest must be derived from current Epochbound campaign contracts after the required visual families have real art bindings. Do not replace Epochbound content with the generated reference fixture from Tile Map Studio; that fixture exists only to prove schema, QA and Godot runtime tooling.

Useful external evidence workflow from Tile Map Studio:

```powershell
tile-map-derive-consumers `
  C:\GitRepos\epochbound `
  C:\GitRepos\godot-462-transport-empire `
  C:\TileMapEvidence\consumer-derivation-001
```

The evidence directory must remain outside the game repository.

Before promotion, a real integration must pass Tile Map Studio preflight/proof, real Godot round-trip validation, a reviewed tracked `.evavo/godot-lab-tile-map.json`, exact-SHA Godot Game Test Lab evidence, and creative review.
