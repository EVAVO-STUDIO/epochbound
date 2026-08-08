# Automated Long-Form Progression Playthroughs

Epochbound includes a deterministic completed-world endurance matrix that extends the canonical journey beyond one successful route.

The executable gate runs from:

```text
res://tools/smoke_long_form_progression.gd
```

It first invokes the shared production route in `res://tools/reference_journey_driver.gd`. That route purchases finite stock, completes Morrow discoveries, crafts the Clockglass Lens, resolves the Underworks Sentinel and restores two normal checksummed profiles. The endurance matrix then continues from that real completed-world state.

## Bounded endurance matrix

One release run performs eight completed-world laps.

Across those laps the gate proves:

- 32 map transitions across Bellweather Crossing, Clockwood Edge and Museum Underworks;
- 16 era shifts through the production era-change path;
- 1,560 deterministic active-play seconds;
- 13 supply cycles consumed exactly once across the Bellweather and Underworks routes;
- eight checksummed checkpoints with distinct durable payloads;
- four destructive restorations through the normal `apply_save_profile` path.

Every second lap clears inventory, session state, wallet, merchant stock, supply cursors, shards, map state, era state and boss engagement before loading the checkpoint. A successful restore must recover the exact Underworks map, era, progression inventory, completed boss outcome, currency, shards, merchant state and supply cursors. It must also rebuild transient boss state from that durable payload rather than preserving the deliberately stale engagement flag.

## Progression invariants

The matrix fails if repeated completed-world travel can:

- replay the Sentinel introduction or conclusion;
- re-engage the defeated Sentinel;
- reactivate the completed Sentinel runtime entity;
- duplicate Archive Chits or Clock Shards;
- duplicate the crafted Clockglass Lens;
- move restocked merchant goods directly into player inventory;
- recreate finite progression stock;
- skip or repeat a regional supply cursor;
- produce a stale or repeated checkpoint checksum;
- leave saving blocked after travel or restoration.

The single Museum Tonic unit purchased by the canonical route is expected to return to Bellweather Provisions after the first due supply cycle. All later cycles still advance their durable cursors, including full-stock cycles, without adding more units.

## Determinism and runtime ownership

No wall-clock or random input is used. The gate advances only the runtime's active-play counter, calls the production supply application method, uses authored map entry points, invokes the production era-shift path, and captures and restores profiles in memory through normal runtime APIs.

The gate is intentionally bounded. It is long enough to cross both authored supply intervals repeatedly, alternate every map through both eras, and prove multiple save restorations without turning normal release validation into an unbounded simulation.

## Release integration

The complete Godot 4.6.2 gate runs the matrix immediately after the focused canonical journey and before isolated world, combat, economy, save, presentation, Audio and Sprite regressions.

The exact-main workflow also runs a fail-closed source contract and records:

```json
"longFormProgressionValidation": "passed"
```

The automated endurance matrix is not a substitute for manual playtesting, controller-feel review, visual review, accessibility review, combat balancing or broad economy simulation. It protects deterministic progression continuity so those human reviews begin from a stable build.
