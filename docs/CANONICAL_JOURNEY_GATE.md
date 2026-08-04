# Canonical Journey Release Gate

Epochbound includes one executable long-form journey that crosses the production runtime as a connected player route rather than testing each subsystem only in isolation.

The gate runs from:

```text
res://tools/smoke_canonical_journey.gd
```

It is executed by the complete `scripts/validate.ps1` Godot 4.6.2 gate after campaign validation and deterministic campaign audit.

## Route covered

The journey instantiates the actual playable `src/app.tscn` scene and then:

1. Starts at Bellweather Crossing.
2. Opens Bellweather Provisions through the player-facing merchant path.
3. Purchases Museum Tonic and verifies inventory, wallet and finite stock effects.
4. Resolves Morrow's Bellweather discovery cue.
5. Collects the Bellweather Clock Shard.
6. Captures a checksummed save profile.
7. Mutates map, inventory, wallet and durable state.
8. Restores the first profile through the normal load path.
9. Travels to Clockwood Edge in the Ashen era.
10. Resolves the Ashen material cache.
11. Crafts Ember Salve.
12. Changes to the Verdant era.
13. Unlocks the Clockglass Lens recipe.
14. Collects the second Clock Shard.
15. Crafts the Clockglass Lens.
16. Verifies the equipped flashlight satisfies the Underworks capability gate.
17. Enters Museum Underworks.
18. Engages the Underworks Sentinel.
19. Completes its introduction through the normal cinematic path.
20. Shifts era during the arena fight.
21. Verifies oversized damage cannot skip Last Accession.
22. Defeats the Sentinel and both Curator Echo reinforcements.
23. Finalizes the arena, durable outcome and one-time rewards.
24. Completes the boss conclusion.
25. Captures a second checksummed profile.
26. Mutates the completed state.
27. Restores the second profile and verifies exact, idempotent completion.

## Why this gate exists

Focused smoke tests remain the best place to diagnose individual systems. They do not prove that system ordering remains coherent across a longer route.

The canonical journey catches integration regressions such as:

- merchant state not surviving later saves;
- pickup or discovery rewards being lost during map changes;
- recipe unlocks or crafted key items disappearing after restoration;
- equipment capabilities not rebuilding from a profile;
- cinematic completion leaving combat or saving blocked;
- boss phase transitions being skipped by large damage;
- reinforcement outcomes not participating in arena completion;
- one-time boss rewards duplicating or disappearing;
- a completed boss returning as engaged after load;
- save checksums representing stale rather than current durable state.

## Determinism and safety

The test does not use wall-clock time, random combat input, operating-system state or an external save directory. Save profiles are captured and restored in memory through the same runtime APIs used by normal saves.

The test intentionally uses authored IDs from the reference campaign. Changing those IDs or removing a required route must update the journey in the same change, making production-route drift explicit.

## Release policy

A release candidate is not considered fully validated unless:

- the reference campaign passes complete content validation;
- the deterministic campaign audit passes;
- the canonical journey passes without `SCRIPT ERROR:` or top-level `ERROR:` output;
- every focused regression still passes afterward;
- validation leaves tracked repository content unchanged.

The journey is a regression gate, not a substitute for hands-on Windows playtesting, controller feel review, accessibility review, visual inspection or combat balancing.
