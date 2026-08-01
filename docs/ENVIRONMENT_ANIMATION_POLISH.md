# Environment Animation Polish

This pass gives Epochbound's procedural blockout a moving world rather than treating the map as a static backdrop behind animated characters.

The implementation is original to Epochbound. It uses general low-resolution action-RPG principles such as readable water motion, restrained foliage sway, material-specific foot response and bounded machinery cycles without copying another game's maps, tiles, effects, timing or animation frames.

## Runtime responsibilities

The environment presentation layer now controls:

- animated water highlights on authored water cells;
- grass sway on authored grass cells;
- moving brass glints on Underworks service paths;
- deterministic ambient ground movement in walkable space;
- material-specific responses to Eli and Morrow's actual travel;
- short-lived ripples, bent grass, ash, dust and metal sparks;
- a subtle world-space pulse around the currently selected interaction;
- map and era resets for transient environmental effects;
- pause and blocking-menu animation freezing;
- strict caps on animated cells and effect history.

It inherits the existing Sprite Animation, grounded cadence, actor depth, foreground occlusion, area-card and contextual-prompt layers.

## Terrain-driven animation

No second environment database is introduced. The overlay reads the same map and terrain records used by Campaign Studio, collision, navigation and the playable runtime.

### Water

Cells authored with the `water` terrain ID receive:

- two short moving highlight lanes;
- a darker lower ripple line;
- deterministic phase offsets by map cell;
- the terrain's active era colour;
- nearest-neighbour one-pixel drawing.

The effect is limited to visible authored cells. It does not change collision or allow actors to enter blocked water.

### Grass

Cells authored with the `grass` terrain ID receive a small set of independently phased blades. Sway remains restrained so the ground does not shimmer as one large surface.

Default walkable Verdant ground also receives a bounded deterministic sample of subtle movement. This gives open ground some life even when a map relies on its base terrain rather than explicitly painting every grass cell.

### Brass service paths

Cells authored as `brass_path` receive a moving two-pixel glint and a restrained rail shadow. Museum Underworks therefore feels mechanically active without needing a separate hard-coded scene or particle node for every floor segment.

### Ash and dust

Walkable Ashen ground receives small lateral ash skitters. Verdant paths and stone use darker dust marks instead. These effects remain close to the ground plane and never compete with combat projectiles, dialogue or objective UI.

## Movement-linked ground response

Eli and Morrow now create a response based on the material beneath their current world position.

| Material | Response |
| --- | --- |
| Water | Expanding flattened ripple |
| Grass | Two blades bend and recover |
| Ash | Three light fragments drift away |
| Brass path | Brief cross-shaped glint |
| Path or stone | Restrained dust motes |

A response is emitted from actual distance travelled rather than from elapsed time. Standing still does not create repeated puffs.

Movement jumps above the teleport threshold reset the accumulator. Map travel, recovery anchors and era shifts therefore do not create a trail of skipped footsteps across the screen.

The environment keeps at most 32 transient responses. Oldest records are removed first, and every response has a short authored lifetime.

## Interaction-linked world feedback

The active contextual prompt now has a matching world-space pulse around its target.

- Available actions use the current Presentation accent colour.
- Locked actions use the current danger colour.
- The pulse follows the same nearest-target decision as the text prompt.
- It disappears during dialogue, transitions, cinematics, pause and blocking menus.
- It communicates selection only; it does not execute or duplicate interaction logic.

This connects the screen-space prompt to the actual object without adding a large icon over every interactable in the map.

## Layer order

Animated terrain and ambient ground motion are drawn before actors.

Material-specific foot responses are drawn immediately before the shared feet-sorted actor and entity pass. Eli, Morrow, NPCs and enemies therefore appear above their own ripples, grass bends and dust.

Foreground tree canopies, dead branches and ruin masonry still draw after actors. The complete order is:

```text
Map base and authored terrain
Animated terrain and ambient ground motion
Ground disturbances
Feet-sorted actors and runtime entities
Foreground landmark occlusion
HUD, dialogue, area cards and prompts
Screen texture and flashes
```

## Pause, menus and cinematics

Environment time freezes while:

- the game is paused;
- Field Satchel is open;
- Journal is open;
- Save Profiles is open;
- a merchant interface is open.

Existing water, grass and disturbance frames remain visible but do not continue advancing behind the menu.

Cinematics may continue environmental animation because the world remains visible and authored camera movement benefits from a living scene. New movement disturbances are not spawned during cinematic control.

## Performance bounds

The procedural environment layer is deliberately bounded:

- no more than 96 visible authored terrain cells are animated per draw;
- no more than 24 ambient ground samples are considered;
- no more than 32 transient ground responses are retained;
- off-screen cells and responses are skipped;
- all phases are derived from one environment clock and deterministic seeds;
- no per-frame textures, scenes or particle nodes are created.

Final tile atlases, shaders or mastered effects may replace these procedural marks later, but they should retain equivalent performance and readability limits.

## Production rules

- Keep water highlights shorter than the source cell width.
- Use one-pixel lines and hard colour clusters at the native 640 by 360 view.
- Keep grass sway asynchronous and low amplitude.
- Do not animate every ground pixel.
- Keep ash below waist height during normal exploration.
- Make machinery cycles readable without implying a gameplay hazard unless one exists.
- Keep interaction pulses subordinate to projectiles, boss telegraphs and dialogue.
- Test movement-speed bonuses so ground responses remain spaced by distance.
- Test Eli and Morrow together so their effects do not overwhelm a narrow corridor.
- Test map travel, era shifting and recovery teleports for clean effect resets.
- Test pause and every blocking overlay for frozen environment time.

## Automated contract

The dedicated environment regression verifies:

- the playable scene binds `environment_animation_overlay.gd`;
- the inherited adventure feedback and Sprite contracts remain valid;
- authored water, grass and brass-path cells resolve the correct animated categories;
- Verdant stone produces dust while Ashen stone produces ash;
- actual player travel produces a material-specific response;
- stationary time does not create movement responses;
- expired responses are removed;
- history remains capped at 32 records;
- blocking menus freeze environment time;
- era changes clear transient ground responses.

The focused compile probe, static integration audit, local validation gate and exact-SHA Sprite workflow all include the new environment layer and test.
