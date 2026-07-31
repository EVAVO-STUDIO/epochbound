# Grounded Animation and Depth Polish

This pass corrects two presentation fundamentals that matter more than adding extra decorative frames: feet must look connected to movement, and world actors must overlap according to their ground contact.

## Distance-driven walk cadence

Idle, attack and hurt animations remain time-driven. Walk animation is different: its frame is now derived from actual distance travelled.

That prevents several common blockout problems:

- legs cycling while an actor is stationary;
- animation speed changing when frame rate changes;
- foot sliding when movement speed is modified by equipment;
- Morrow's gait drifting out of phase with his actual travel;
- patrol and return animations looking detached from enemy motion.

A profile's rendered body height and walk-frame count determine a bounded number of world pixels per frame. Teleports and map transitions reset the accumulated travel distance rather than playing a burst of skipped walk frames.

## Shared feet-based depth order

Eli, Morrow and every active runtime entity now enter one deterministic depth list. The list sorts by world-space ground-contact `y`, then by a stable tie-break order.

This means:

- a character walking behind an NPC appears behind the NPC;
- a character walking below a prop appears in front of it;
- Morrow can pass naturally around Eli;
- enemies, pickups and interactive props no longer belong to a separate draw pass;
- identical positions resolve consistently rather than flickering between frames.

Landmarks and map layers remain part of the world renderer. The shared actor/entity pass only controls objects that occupy the playable floor plane.

## Paused animation

Animation time freezes while the game is paused or while inventory, Journal, Save Profiles or merchant interfaces are open. This keeps non-looping combat poses and idle cycles from silently completing behind a blocking menu.

Dialogue and cinematics may continue to animate because they are visible authored presentation rather than hidden menu time.

## Production rules

- Align each atlas profile's pivot to its ground contact.
- Keep walk frames cyclic and evenly spaced.
- Avoid duplicate contact poses at both the first and last frame of a looping walk.
- Test slow and fast movement bonuses; cadence must remain grounded at both extremes.
- Test actors crossing above and below every major prop type.
- Test ties at the same world `y`; order must remain stable.
- Test map travel and recovery teleports; they must not advance a large burst of walk frames.
- Test pause, inventory, Journal, save and merchant overlays during idle, walk and attack states.

## Automated contract

The Sprite runtime regression now verifies:

- stationary walk animation does not advance with wall-clock time;
- travelled distance advances the walk cycle;
- Morrow retains his own movement-facing direction;
- player, companion and active entities share one ordered depth list;
- paused gameplay freezes animation time;
- the playable scene binds the grounded polish adapter.

The static Sprite integration audit also requires the distance accumulator, cadence resolver, pause guard and depth-order functions to remain wired into `main`.
