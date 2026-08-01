# Combat Readability and Canvas-Layer Polish

This pass corrects a structural presentation problem: combat simulation lived in the scrolling world canvas, while the polished actors, interface and environmental treatment lived in a higher screen-space `CanvasLayer`.

In Godot, a higher-numbered CanvasLayer is drawn above lower layers regardless of ordinary scene-tree order. A projectile, arena frame or prototype HUD drawn only on the base world layer can therefore appear behind replacement actors, environment marks or fixed interface panels.

The solution is not to make every combat element permanently topmost. Epochbound now promotes combat-critical visuals into the governed presentation layer and places them deliberately within its existing depth and interface order.

## Runtime adapter

The playable scene uses `presentation_runtime_current.gd`, which retains every Cinematic, Boss, Arsenal, economy, equipment, save, story and world behaviour.

When the combat-readability overlay is present, the adapter suppresses duplicate root drawing for:

- moving projectiles;
- the authored boss arena outline;
- Arsenal ammunition and reload status;
- Boss health, phase and reinforcement status;
- Boss transition banners.

The adapter does **not** suppress inherited quest, companion, notice or system HUD contributions. During the inherited HUD pass, only the ranged-weapon and active-boss queries are temporarily made empty, then restored immediately. Gameplay state is never changed by presentation suppression.

A stripped-down custom scene without the overlay still receives every inherited fallback drawing path.

Simulation remains in the existing runtime. The adapter changes presentation ownership only.

The complete root, camera, Audio, CanvasLayer and overlay relationship is defined in [`RUNTIME_COMPOSITION_CONTRACT.md`](RUNTIME_COMPOSITION_CONTRACT.md).

## Projectile presentation

Projectiles are read from the existing Arsenal `projectiles` array. No second projectile state is created.

Each active projectile enters the same world-depth list as:

- Eli;
- Morrow;
- NPCs;
- enemies;
- pickups;
- interactive props.

The list sorts by world-space ground-contact Y and then by a stable tie breaker. This allows a projectile to pass behind deeper scenery or in front of shallower actors without escaping into a permanently topmost effects layer.

Projectile positions are converted from world space through the active presentation camera. Trail length is capped so a slow frame, camera jump or unusual projectile speed cannot draw an uncontrolled line across the screen.

The presentation mark uses:

- a dark one-pixel-readable outline;
- the authored projectile colour;
- a bounded source radius;
- a small highlight core;
- a short directional trail.

The underlying collision, damage, range, cover and save-blocking behaviour remains owned by Arsenal and Boss runtime code.

## Ammunition status

The high presentation layer now owns the visible ranged-weapon status panel.

It reads the real runtime values for:

- equipped ranged weapon;
- loaded rounds;
- reserve inventory;
- reload timer;
- reload duration.

The panel sits beneath the existing map and era plaque rather than competing with it. During reload, the weapon label is replaced by a bounded progress bar and explicit `RELOADING` state.

The runtime continues to enforce transactional reload behaviour. Presentation does not remove reserve ammunition or alter magazine state.

## Boss arena and status

The active boss arena is redrawn in camera-correct screen space before actors. It uses the current Presentation danger colour and remains subordinate to projectiles, actors and telegraphs.

The boss status panel reads:

- active boss display name;
- current health;
- current maximum health;
- active authored phase name;
- reinforcement-only arena state.

Boss banners are redrawn in the same fixed layer as the rest of the polished interface. Existing phase transitions, damage clamping, reinforcement activation and durable outcomes remain unchanged.

## Pause-screen correctness

The root runtime already draws the pause panel after its world. A higher CanvasLayer must not redraw the entire world and HUD over that pause panel.

When gameplay flow is paused, the combat-readability overlay now draws only its restrained screen texture. It does not redraw:

- actors;
- projectiles;
- environment motion;
- ammunition status;
- boss status;
- contextual prompts;
- area cards.

This keeps the root pause interface readable while preserving the intended low-resolution screen treatment.

Inventory, Journal, Save Profiles and merchant surfaces retain their existing blocking-menu behaviour.

## Layer order

Normal gameplay now resolves as:

```text
Base map, collision-aware world and simulation fallbacks
Animated terrain and ambient ground motion
Material-specific ground disturbances
Feet-sorted actors, entities and projectiles
Foreground landmark occlusion
Inherited non-duplicated system HUD
Fixed polished player, ammo and boss status
Dialogue, area cards and contextual prompts
Screen texture and bounded flashes
```

Pause flow resolves as:

```text
Root world and root pause panel
Restrained screen texture only
```

## Performance bounds

The combat presentation layer retains strict limits:

- no more than 128 active projectiles are promoted for drawing;
- projectile trails are capped at 18 world pixels;
- off-screen projectile heads are skipped;
- no projectile nodes, textures or scenes are created per frame;
- existing environment and ground-response limits remain active;
- custom drawing continues through one queued CanvasItem redraw per frame.

## Automated contract

The dedicated combat-readability regression verifies:

- the playable root binds the presentation-safe runtime adapter;
- the scene binds `combat_readability_overlay.gd`;
- duplicate base projectile and arena drawing is suppressed;
- active projectiles enter the shared depth list;
- projectile trails remain bounded;
- ammo HUD values come from the real magazine and inventory state;
- boss name, health and phase come from active runtime state;
- normal gameplay permits presentation-owned combat layers;
- paused gameplay prevents those layers from covering the pause panel.

The canonical runtime-scene regression additionally verifies exact script paths, inherited subsystem APIs, Audio readiness, selective combat-HUD suppression, fallback ownership and restoration after reattaching the overlay.

The cinematic regression also confirms that the runtime adapter preserves the complete cinematic API and durable completion behaviour.

The primary compile probe, focused compile probe, complete local validation gate, static runtime audit, Sprite integration audit and exact-SHA workflows all include the runtime composition and combat-readability tests.

## Manual review

A focused Windows playtest should verify:

1. Fire the Dartcaster on a scrolling map and confirm projectile position follows the camera.
2. Fire above and below NPCs, props and enemies and inspect overlap.
3. Fire behind a tree canopy or ruin foreground and confirm the occlusion is believable.
4. Reload and confirm the top-right ammo panel remains readable beside the map plaque.
5. Confirm quest, companion and system feedback still appears while the polished ammo panel replaces only the prototype ammo panel.
6. Enter the Underworks Sentinel arena and confirm its boundary stays behind actors.
7. Review boss name, phase and health during all three phases.
8. Pause while a projectile is active and confirm the pause panel remains unobstructed.
9. Open every blocking menu and confirm combat-critical feedback does not leak above it.
10. Resume and confirm projectile simulation and transient presentation remain coherent.
11. Remove the presentation overlay in a temporary local scene and confirm inherited fallback HUD, projectile and arena drawing remains functional.
12. Test at native 640 by 360 and the 1280 by 720 window override.
