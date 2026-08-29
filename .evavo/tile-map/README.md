# Epochbound Tile Map Studio binding

Epochbound is formally bound to `EVAVO-STUDIO/evavo-tile-map-studio`, but this directory does not yet contain a production Tile Map Studio manifest.

Canonical authority remains Epochbound campaign data, including its authored maps, Verdant/Ashen era variants, collision/navigation, entries, recovery anchors, encounter zones, progression and travel rules.

The future production manifest is intended to live at:

```text
.evavo/tile-map/world.tilemap-build.json
```

That manifest must be derived from current Epochbound campaign contracts. Do not replace Epochbound content with the generated reference fixture from Tile Map Studio; that fixture exists only to prove schema, QA and Godot runtime tooling.

Before promotion, a real integration must pass Tile Map Studio preflight/proof, real Godot round-trip validation, a reviewed tracked `.evavo/godot-lab-tile-map.json`, exact-SHA Godot Game Test Lab evidence, and creative review.
