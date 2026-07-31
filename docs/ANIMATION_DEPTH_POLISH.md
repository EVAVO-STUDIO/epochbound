# Grounded Animation and Depth Polish

This pass corrects three presentation fundamentals that matter more than adding extra decorative frames: feet must look connected to movement, world actors must overlap according to ground contact, and tall scenery needs a foreground portion that can pass over actors.

## Distance-driven walk cadence

Idle, attack and hurt animations remain time-driven. Walk animation is different: its frame is derived from actual distance travelled.

That prevents several common blockout problems:

- legs cycling while an actor is stationary;
- animation speed changing when frame rate changes;
- foot sliding when movement speed is modified by equipment;
- Morrow's gait drifting out of phase with his actual travel;
- patrol and return animations looking detached from enemy motion.

A profile's rendered body height and walk-frame count determine a bounded number of world pixels per frame. Teleports and map transitions reset the accumulated travel distance rather than playing a burst of skipped walk frames.

## Shared feet-based depth order

Eli, Morrow and every active runtime entity enter one deterministic depth list. The list sorts by world-space ground-contact `y`, then by a stable tie-break order.

This means:

- a character walking behind an NPC appears behind the NPC;
- a character walking below a prop appears in front of it;
- Morrow can pass naturally around Eli;
- enemies, pickups and interactive props no longer belong to a separate draw pass;
- identical positions resolve consistently rather than flickering between frames.

## Foreground landmark occlusion

Trees, dead trees and ruins retain their authored world base, but their canopy, high branches or upper masonry are redrawn after the actor/entity depth pass.

This creates the classic low-resolution depth cue where a character can walk behind scenery without requiring a second map, duplicate landmark record or hand-authored mask for the procedural blockout.

The foreground treatment is deliberately limited to the upper portion of the landmark. Collision and navigation still come from map data, and the lower ground contact remains visible enough for movement readability.

Final environment atlases can replace these procedural foregrounds while keeping the same split-layer principle.

## Paused animation

Animation time freezes while the game is paused or while inventory, Journal, Save Profiles or merchant interfaces are open. This keeps non-looping combat poses and idle cycles from silently completing behind a blocking menu.

Dialogue and cinematics may continue to animate because they are visible authored presentation rather than hidden menu time.

## Production rules

- Align each atlas profile's pivot to its ground contact.
- Keep walk frames cyclic and evenly spaced.
- Avoid duplicate contact poses at both the first and last frame of a looping walk.
- Test slow and fast movement bonuses; cadence must remain grounded at both extremes.
- Test actors crossing above and below every major prop type.
- Test actors passing behind trees, dead trees and ruin arches.
- Keep foreground masks above the actor's head and away from critical interaction prompts.
- Test ties at the same world `y`; order must remain stable.
- Test map travel and recovery teleports; they must not advance a large burst of walk frames.
- Test pause, inventory, Journal, save and merchant overlays during idle, walk and attack states.

## Automated contract

The Sprite runtime regression verifies:

- stationary walk animation does not advance with wall-clock time;
- travelled distance advances the walk cycle;
- Morrow retains his own movement-facing direction;
- player, companion and active entities share one ordered depth list;
- the reference map exposes a foreground landmark occluder;
- paused gameplay freezes animation time;
- the playable scene binds the grounded polish adapter.

The static Sprite integration audit also requires the distance accumulator, cadence resolver, pause guard and depth-order functions to remain wired into `main`.
