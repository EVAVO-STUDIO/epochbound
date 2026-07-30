# Cinematic & Timeline Manual Playtest Checklist

Use this checklist after automated validation and before treating a sequence as production-ready.

## Setup

- Open the current `main` project in Godot 4.6.2.
- Run the complete local validation gate.
- Test at 640×360 internal resolution and the normal 1280×720 window override.
- Test keyboard and controller input separately.
- Test with an empty autosave slot and an existing autosave slot.

## Campaign opening

- Start a new reference journey.
- Complete or skip the existing prologue pages.
- Confirm **The Door Beneath Bellweather** begins once gameplay starts.
- Confirm gameplay input is paused.
- Confirm the opening fade is smooth and does not expose an uninitialised frame.
- Confirm the camera frames the authored well position.
- Confirm Eli’s line is readable.
- Confirm Morrow moves to the authored position without entering collision.
- Confirm camera control returns to Eli at the end.
- Confirm the sequence does not replay after map travel.

## Skip equivalence

- Restart with a clean profile.
- Skip the opening using Escape.
- Repeat with controller Start.
- Confirm the same durable completion key is written.
- Confirm Morrow and Eli return to safe positions.
- Confirm no progression, reward or route is lost.
- Confirm autosave occurs after playback settles, not during the timeline.
- Reload and confirm the sequence does not replay.

## Dialogue pacing

- Let every line advance automatically.
- Repeat using confirm to advance early.
- Confirm no line is skipped accidentally by the input that opened the sequence.
- Confirm speaker labels remain readable.
- Confirm long text does not overflow the dialogue frame.
- Confirm era-keyed lines use the current era.

## Camera

- Review every camera target.
- Confirm placement targets resolve to the correct stable placement.
- Confirm world targets remain inside the map canvas.
- Confirm camera pans do not reveal void outside map bounds.
- Confirm zoom never makes sprites or text unreadable.
- Confirm camera returns to normal gameplay framing after completion or skip.

## Actor blocking

- Confirm player blocking respects map bounds.
- Confirm companion blocking recovers from collision.
- Confirm placed actors finish at their authored positions.
- Confirm skipping does not leave actors halfway between start and target.
- Confirm actor movement cannot place the player inside a boss or solid prop.

## Era changes

- Test any sequence containing `set_era` from each available starting era.
- Confirm projectiles and reloads clear before the era rebuild.
- Confirm unavailable placements disappear safely.
- Confirm Eli and Morrow recover from changed collision.
- Confirm the sequence’s remaining steps use the new era’s dialogue and presentation.

## Boss introduction

- Enter the Underworks Sentinel activation area in Verdant.
- Confirm **The Sentinel Seals the Gallery** begins after engagement.
- Confirm the exit remains locked.
- Confirm boss health and phase state are not reset by playback.
- Confirm enemies do not attack during the cinematic.
- Confirm skipping returns to the same engaged phase.
- Repeat in Ashen and confirm the era-specific line.

## Boss conclusion

- Clear the Sentinel and Curator Echoes.
- Confirm durable boss rewards resolve before the conclusion begins.
- Confirm **The Missing Accession** frames the defeated Sentinel placement.
- Confirm the archive-release state is written once.
- Confirm the exit is already unlocked.
- Confirm saving is blocked during the conclusion.
- Confirm saving becomes available after completion.
- Skip the conclusion and verify the same durable result.
- Reload and confirm neither boss rewards nor cinematic effects duplicate.

## Menus and transitions

- Attempt to open inventory, Journal, merchant and save overlays during playback.
- Confirm none opens.
- Confirm an already open overlay closes before a cinematic starts.
- Confirm active dialogue closes safely.
- Confirm no reload or projectile survives into playback.
- Confirm map travel never carries an active cinematic into the destination map.

## Save durability

- Attempt a manual save during playback and confirm it is blocked.
- Trigger an autosave-worthy effect during playback and confirm the request remains deferred.
- Finish the sequence and confirm the deferred autosave can flush.
- Force-close the game after completion and reload.
- Confirm only durable completion and effects return.
- Confirm camera position, fade alpha, current line and step index are not restored.

## Validation and editor

- Open the **Cinematic** tab.
- Confirm all three reference sequences appear.
- Confirm the timeline preview matches source order.
- Edit a line and validate.
- Add a valid wait step and validate.
- Enter malformed JSON and confirm it is rejected.
- Reference a missing map and confirm the edit rolls back.
- Duplicate a sequence and confirm it receives a new stable ID and completion key.
- Attempt to delete a referenced cinematic and confirm complete validation prevents broken content.

## Accessibility

- Confirm all essential information appears as text.
- Confirm no critical progression depends on hearing audio.
- Confirm Escape and Start have equivalent skip behaviour.
- Confirm confirm-advance works with keyboard and controller.
- Confirm fades do not flash rapidly.
- Confirm sequences remain understandable without camera motion.
- Confirm the player is never required to react during a cinematic.

## Soak test

- Play every cinematic watched and skipped for at least ten repetitions.
- Alternate eras between repetitions.
- Travel between all maps.
- Save and reload after every sequence.
- Confirm no duplicate effects, stuck camera, stale letterbox, locked input, hidden HUD or unresolved autosave state remains.
