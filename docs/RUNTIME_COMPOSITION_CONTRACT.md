# Runtime Composition Contract

Epochbound's playable scene combines a long inherited gameplay runtime with a separate high-layer presentation system. This contract prevents those layers from drifting apart as new systems are added.

## Canonical playable scene

The production scene is `res://src/app.tscn` and must contain:

```text
Epochbound                         presentation_runtime_current.gd
├── AudioMood                      audio_mood_runtime.gd
├── PresentationCamera             presentation_camera.gd
└── PresentationLayer              CanvasLayer above world layer 0
    └── PresentationOverlay         combat_readability_overlay.gd
```

The canonical paths and required APIs are defined once in:

```text
res://src/game/runtime_scene_contract.gd
```

Subsystem tests should verify behaviour through inherited methods. The dedicated runtime-scene test verifies the exact production composition.

## Runtime inheritance

`presentation_runtime_current.gd` inherits `cinematic_runtime.gd`, which retains the complete chain for:

- world traversal and interactions;
- directed combat and companion commands;
- items, crafting and inventory;
- story and quest progression;
- save profiles and migrations;
- equipment and capabilities;
- merchants and economy;
- ranged weapons and projectiles;
- bosses, phases and arena state;
- cinematic timelines and durable completion.

The presentation adapter must not reimplement those systems. It changes final drawing ownership only.

## Explicit drawing ownership

When the production overlay is present, the root runtime suppresses its prototype copies of:

- the base adventure HUD;
- ammunition and reload information;
- boss health and phase information;
- boss transition banners;
- projectiles;
- boss arena framing.

The `CanvasLayer` then draws those elements with the same camera conversion, pixel treatment and depth rules as the polished actors and environment.

When a stripped-down custom scene omits the overlay, the inherited root drawing remains available as a fallback. Suppression must therefore be conditional rather than permanent.

## Why this is required

Godot draws higher-numbered `CanvasLayer` content above lower canvas layers independently of ordinary scene-tree ordering. A polished HUD layer can therefore obscure projectiles or a pause screen if ownership is ambiguous.

The production contract avoids that ambiguity:

- world simulation remains in the root runtime;
- durable state remains in existing subsystem records;
- final polished drawing lives in the high presentation layer;
- root prototype drawing is disabled only when the high layer confirms it can replace it;
- fallback scenes remain functional.

## Validation

`tools/smoke_runtime_scene_contract.gd` loads the real production scene and verifies:

- exact root, overlay, camera and Audio scripts;
- inherited runtime APIs from every major gameplay layer;
- all presentation contracts;
- Audio generator readiness and zero startup underruns;
- positive CanvasLayer ordering;
- explicit duplicate-render suppression;
- fallback ownership after removing the overlay;
- restoration after reattaching the overlay.

`tools/check_runtime_scene_contract.py` checks the same wiring statically before Godot starts. It also confirms that the primary compile probe, focused compile probe, local gate and governed workflows include the executable runtime-scene test.

## Change procedure

When replacing the production runtime adapter or overlay:

1. Add the new script without deleting the previous working adapter.
2. Update `runtime_scene_contract.gd` with the exact new path.
3. Update `app.tscn`.
4. Preserve every required inherited runtime method.
5. Preserve conditional root-drawing fallback.
6. Update the static and executable composition tests.
7. Run the complete Godot 4.6.2 gate.
8. Confirm no tracked source changed during validation.
9. Commit the coherent change directly to `main` only after the contract is green.

Do not solve presentation conflicts by adding larger opaque masks over unknown prototype output. Give each visual element one explicit owner and retain a tested fallback.
