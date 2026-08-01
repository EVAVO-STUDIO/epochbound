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

The current adapter also owns player-local Options state. Those preferences are versioned separately under `user://settings`; they are not inserted into campaign data, portable packages or journey save profiles.

The presentation adapter must not reimplement inherited gameplay systems. It changes final drawing ownership and applies bounded player preference multipliers only.

## Player settings responsibilities

The canonical runtime must expose:

- Options opening and closing;
- validated settings rows;
- numeric and boolean preference queries;
- save and autosave blocking while Options is open;
- local atomic persistence and backup recovery.

The canonical presentation overlay must apply:

- screen-texture intensity;
- camera-shake intensity;
- world-motion intensity;
- screen-flash intensity;
- Action Prompt visibility;
- High Contrast UI treatment;
- the fixed-layer Options panel.

The canonical Audio node must apply Master, Music, Ambience and SFX gains to the existing generator players. It must preserve bus routing, buffer priming and underrun checks.

Accessibility settings may alter presentation intensity but must not change collision, damage, quest logic, save data, merchant state or campaign validation.

## Explicit drawing ownership

When the production overlay is present, the root runtime suppresses only its duplicated combat-presentation surfaces:

- ammunition and reload information;
- boss health and phase information;
- boss transition banners;
- projectiles;
- boss arena framing.

The inherited root HUD remains responsible for lower-layer information that has not been replaced, including quest, companion, notice and system feedback. During root HUD drawing, only Arsenal and Boss status queries are temporarily made empty; their underlying gameplay state is not changed.

The `CanvasLayer` draws the polished combat surfaces with the same camera conversion, pixel treatment and depth rules as the actors and environment. It also draws Options after the current title, gameplay or pause surface so the settings panel remains fixed and readable.

When a stripped-down custom scene omits the overlay, every inherited root drawing path remains available as a fallback. Suppression must therefore be conditional rather than permanent.

## Why this is required

Godot draws higher-numbered `CanvasLayer` content above lower canvas layers independently of ordinary scene-tree ordering. A polished HUD layer can therefore obscure projectiles or a pause screen if ownership is ambiguous.

The production contract avoids that ambiguity:

- world simulation remains in the root runtime;
- durable campaign state remains in existing subsystem records;
- player preferences remain in their own local settings store;
- final polished combat and Options drawing lives in the high presentation layer;
- quest, companion and system feedback remain available from inherited HUD code;
- root duplicate combat drawing is disabled only when the high layer confirms it can replace it;
- fallback scenes remain functional.

## Validation

`tools/smoke_runtime_scene_contract.gd` loads the real production scene and verifies:

- exact root, overlay, camera and Audio scripts;
- inherited runtime APIs from every major gameplay layer;
- player settings methods on runtime, overlay and Audio;
- all presentation contracts;
- Audio generator readiness and zero startup underruns;
- positive CanvasLayer ordering;
- explicit duplicate-render suppression;
- fallback ownership after removing the overlay;
- restoration after reattaching the overlay.

`tools/smoke_player_settings.gd` separately verifies schema migration, isolated atomic storage, backup recovery, Options controls, presentation intensity, prompt visibility, contrast and Audio gain application.

`tools/check_runtime_scene_contract.py` and `tools/check_player_settings_contract.py` check the same wiring statically before Godot starts. They also confirm that the local gate and all governed workflows include the executable contracts.

## Change procedure

When replacing the production runtime adapter, overlay or Audio adapter:

1. Add the new script without deleting the previous working adapter.
2. Update `runtime_scene_contract.gd` with the exact new path.
3. Update `app.tscn` only when a canonical script path changes.
4. Preserve every required inherited runtime method.
5. Preserve player-local settings separation and migrations.
6. Preserve inherited non-duplicated HUD information.
7. Preserve conditional root-drawing fallback.
8. Update the static and executable composition tests.
9. Run the complete Godot 4.6.2 gate.
10. Confirm no tracked source changed during validation.
11. Commit the coherent change directly to `main` only after the contract is green.

Do not solve presentation conflicts by adding larger opaque masks over unknown prototype output. Give each visual element one explicit owner, retain a tested fallback and keep player preferences outside authored campaign state.
