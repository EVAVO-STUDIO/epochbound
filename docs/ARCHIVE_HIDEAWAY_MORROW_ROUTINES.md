# Archive Hideaway Morrow Routines

The Archive Hideaway now gives Morrow optional, active-session refuge routines so restored spaces feel inhabited rather than static. These are ambient companion behaviours inside the existing expedition refuge, not a pet-care, farming or maintenance system.

## Authored routines

The reference Hideaway provides eight routines in stable authored order:

1. **Threshold Watch** is always available.
2. **Pack Circle** appears after the first qualifying return.
3. **Hearth Sprawl** appears after restoring the Archive Hearth.
4. **Coldframe Scent** appears beside the restored coldframe in Verdant.
5. **Cinder-Glass Watch** replaces it beside the coldframe in Ashen.
6. **Workbench Listening** appears after the Salvage Workbench reaches level two.
7. **Blanket Curl** appears after restoring Morrow's Corner.
8. **Both Ears Down** appears when all twelve facility levels form Archive Haven.

Each routine has an authored interaction anchor, a bounded offset, a governed pose and an active in-session dwell of three to twelve seconds. Selection is deterministic and cycles only while the player remains in the refuge.

## Player commands always win

Ambient routines run only when Morrow is alive, the game is in normal play, no dialogue or transition owns the scene, and the current companion command is `follow`. Hold, seek, recall or any explicit command immediately suspends the routine. A four-second grace window prevents ambient movement from snapping back as soon as the player returns to follow.

Morrow still uses the existing recovery distance and normal companion movement. If Eli moves too far away, normal companion authority takes over.

## Persistence and progression boundary

Routines are derived from the existing return count, facility levels, refuge tier and current era. There is **no new save field**, unlock list or migration. No new save field is introduced. Routine cursors, arrival state, dwell timers and command-grace timers are transient presentation state.

The system:

- uses active in-session delta only;
- grants no item, currency, salvage, preparation charge or combat benefit;
- spends no resource;
- advances no wall-clock or offline time;
- creates no hunger, sleep, grooming, feeding, maintenance or daily chore loop;
- cannot override multiplayer, dialogue, transition or explicit companion-command authority.

## Validation

Strict validation rejects duplicate IDs, unsupported poses, unknown anchors, unsafe offsets, durations outside the authored range, invalid era lists, unsupported conditions, reward payloads, wall-clock gates and mismatched English fallback copy. The local and exact-main release gates compile the model and runtime, run pure availability and no-write regressions, and preserve the complete Godot 4.6.2 multiplayer and seventeen-system suite.
