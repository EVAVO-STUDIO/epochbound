# Presentation Playtest Checklist

Use this checklist after the complete automated validation gate passes. Review the game at the native 640×360 viewport and at the 1280×720 window override.

## Source and editor

- [ ] The **Presentation** tab appears with the other main-screen editors.
- [ ] The reference campaign loads six profiles and six bindings.
- [ ] All nine palette fields display their authored colours.
- [ ] Camera, atmosphere, screen and actor values match source JSON.
- [ ] Saving a valid profile updates its catalogue.
- [ ] An invalid colour or unsafe value is rejected and rolled back.
- [ ] A campaign without presentation metadata can create a default catalogue.
- [ ] Legacy campaigns still load with the built-in fallback profile.

## Title and introduction

- [ ] The title remains readable against the mountain silhouette.
- [ ] Border accents and screen texture feel intentional rather than noisy.
- [ ] Menu selection remains immediately visible.
- [ ] Introduction text remains clear at both output sizes.
- [ ] Scanlines and dither do not break small text.
- [ ] No frame accent resembles an existing game’s distinctive interface asset.

## Bellweather Crossing

### Verdant

- [ ] The palette feels warm, living and slightly uncanny.
- [ ] Pollen or motes remain visible without hiding the road.
- [ ] Eli and Morrow separate clearly from grass and path colours.
- [ ] Brass and clockglass accents draw attention without becoming neon.
- [ ] The camera settles naturally after changing direction.
- [ ] Look-ahead reveals useful space without exposing outside the map.

### Ashen

- [ ] The palette shifts clearly through hue and value, not a red overlay alone.
- [ ] Embers move upward and remain sparse enough for combat readability.
- [ ] The Ash Hound silhouette remains readable over dark ground.
- [ ] Era shifting creates a restrained flash and short bounded shake.
- [ ] The service-stair marker remains visible near the screen edge.

## Clockwood Edge

### Verdant

- [ ] Vignette deepens the woods without hiding exits or clue markers.
- [ ] Fireflies remain decorative and do not resemble pickups or projectiles.
- [ ] Trees, actors and enemies have distinct silhouette values.
- [ ] Movement bob feels deliberate rather than floaty.

### Ashen

- [ ] Cinder atmosphere communicates heat without covering enemy windups.
- [ ] Danger colour remains distinct from objective and brass accents.
- [ ] Camera deadzone does not make narrow navigation feel delayed.
- [ ] Morrow’s cue and recovery behaviour remain easy to follow.

## Museum Underworks

### Verdant

- [ ] Dust and strong vignette create depth without obscuring floor edges.
- [ ] The flashlight cone points in Eli’s facing direction.
- [ ] Removing the flashlight immediately removes the cone.
- [ ] The Archivist Lens does not incorrectly produce ordinary light.
- [ ] Dialogue, trade and inventory overlays remain fixed while the world camera moves.

### Ashen

- [ ] Cinders remain readable against boss projectiles.
- [ ] The Underworks Sentinel and Curator Echoes remain distinct.
- [ ] Boss health and phase feedback stay above atmosphere.
- [ ] Screen shake never hides a windup or displaces the HUD.
- [ ] The boss introduction and conclusion retain exact cinematic camera framing.

## Player and companion silhouettes

- [ ] Eli’s head, coat, legs and facing remain readable in all four directions.
- [ ] The equipped weapon silhouette follows facing.
- [ ] Attack glints are brief and do not resemble projectiles.
- [ ] Morrow reads as a dog rather than an abstract marker.
- [ ] Morrow’s head and tail communicate facing and motion.
- [ ] Ground shadows provide contact without becoming large black blobs.
- [ ] Procedural silhouettes fully cover the old placeholder actors at normal play distance.

## Objects and enemies

- [ ] Crates, people, beasts, orbs and pillars have distinct silhouettes.
- [ ] NPCs are not visually confused with enemies.
- [ ] Pickup glow remains different from atmosphere particles.
- [ ] Hit flashes are short and bounded.
- [ ] Impact bursts occur at the struck actor or enemy.
- [ ] Enemy health bars remain readable and disappear at full health.
- [ ] Ranged projectile travel remains visible over every profile.

## Combat feel

- [ ] Melee attacks feel immediate at the authored cooldown.
- [ ] Damage produces a short impact burst and controlled shake.
- [ ] Player damage does not create rapid repeated full-screen flashes.
- [ ] Companion attacks remain readable beside player attacks.
- [ ] Reload, projectile and boss-pattern timing are unchanged.
- [ ] Presentation feedback never applies gameplay damage or rewards.
- [ ] Defeat rewind remains readable and does not leave camera offset behind.

## HUD and dialogue

- [ ] Player and companion health values are accurate.
- [ ] Notched health bars scale correctly after equipment changes maximum health.
- [ ] Clockglass count remains visible.
- [ ] Map and era labels fit within the plaque.
- [ ] Quick restorative name and quantity remain readable.
- [ ] Dialogue wraps to at most three clear lines.
- [ ] Confirm hint remains visible.
- [ ] Inventory, Journal, Save, Trade and Cinematic surfaces remain fully usable.
- [ ] Base placeholder HUD does not visibly bleed outside the new frame.

## Camera and motion safety

- [ ] The camera does not move for tiny movement inside the deadzone.
- [ ] The camera catches up smoothly after sustained movement.
- [ ] Direction look-ahead does not oscillate when facing changes quickly.
- [ ] Camera residual resets for title, intro and cinematics.
- [ ] The HUD remains completely stationary during camera motion.
- [ ] Screen shake returns the root node to zero offset.
- [ ] Pausing during or immediately after impact does not preserve an offset.
- [ ] No camera movement causes motion sickness during a ten-minute traversal.

## Accessibility

- [ ] Every interaction marker remains identifiable without colour alone.
- [ ] Health loss is communicated by value, bar length and text—not red alone.
- [ ] Verdant and Ashen eras remain distinguishable in grayscale.
- [ ] Small text is readable on a 1280×720 display from normal viewing distance.
- [ ] Scanline, dither and vignette values remain inside validated limits.
- [ ] There is no rapid flicker or repeated high-alpha full-screen flash.
- [ ] Cinematic subtitles remain legible over every era profile.

## Originality review

- [ ] No sprite, portrait, environment, prop, creature or interface element traces an existing game asset.
- [ ] No map composition recreates a protected location.
- [ ] No dialogue, story beat, terminology, sound or music is copied.
- [ ] The overall result reads as Epochbound’s Bellweather world, not a replica of another title.
- [ ] Genre influence is limited to broad production principles: readable low-resolution silhouettes, disciplined palette, tactile feedback, atmospheric exploration and compact framed UI.

## Soak review

- [ ] Play for at least thirty minutes across all three maps and both eras.
- [ ] Open and close every major overlay repeatedly.
- [ ] Shift eras during movement, after combat and near connections.
- [ ] Trigger melee, ranged, companion and boss impacts repeatedly.
- [ ] Watch and skip each cinematic.
- [ ] Save, load and Continue after presentation events.
- [ ] Confirm no particles, puffs, bursts or camera offsets accumulate indefinitely.
- [ ] Confirm performance remains stable on the target Windows machine.
