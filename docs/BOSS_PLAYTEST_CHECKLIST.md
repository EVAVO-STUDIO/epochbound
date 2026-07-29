# Epochbound Boss Encounter Playtest Checklist

Use this checklist after automated validation passes. It is intended for hands-on Windows editor, keyboard and controller review of every production boss encounter.

## Test setup

- [ ] Pull the latest `main` branch.
- [ ] Open the project in Godot 4.6.2.
- [ ] Confirm the **Boss** main-screen editor appears.
- [ ] Run `scripts/validate.ps1` successfully before manual testing.
- [ ] Start from a clean new journey for first-run checks.
- [ ] Keep a separate schema-4 save for restoration checks.
- [ ] Test both keyboard and controller inputs.
- [ ] Test at the native 640×360 viewport and the 1280×720 window override.

## Boss Studio

- [ ] Select the reference campaign.
- [ ] Confirm the Ash Hound and Underworks Sentinel appear in the enemy list.
- [ ] Confirm the Sentinel is labelled as a boss.
- [ ] Confirm the source map resolves to Museum Underworks.
- [ ] Confirm the arena selector resolves to Underworks Sentinel Gallery.
- [ ] Confirm `west_to_bellweather` is selected as a locked connection.
- [ ] Confirm the outcome key is `underworks:boss:sentinel`.
- [ ] Confirm three phase records are preserved.
- [ ] Confirm phase summary shows Catalogue Measure, Cinder Measure and Last Accession.
- [ ] Confirm Last Accession shows two reinforcements.
- [ ] Enter malformed JSON and confirm it is rejected without changing source.
- [ ] Enter a phase without a safe pause and confirm validation rejects it.
- [ ] Enter a phase with a very short windup and confirm validation rejects it.
- [ ] Enter a missing reinforcement placement and confirm validation rejects it.
- [ ] Confirm an invalid edit restores the previous source file and editor state.

## Arena approach

- [ ] Enter Museum Underworks from Bellweather.
- [ ] Confirm the fight does not begin at the entry point.
- [ ] Confirm Eli and Morrow can move normally before activation.
- [ ] Approach the eastern gallery deliberately.
- [ ] Confirm the boss introduction appears before the first damaging pattern.
- [ ] Confirm the arena boundary becomes visible.
- [ ] Confirm the return connection becomes locked.
- [ ] Confirm the player receives clear feedback when trying to leave.
- [ ] Confirm Eli is clamped inside the arena without snapping into collision.
- [ ] Confirm Morrow remains inside the arena and can continue navigating.

## Verdant opening phase

- [ ] Enter the fight in the Verdant era.
- [ ] Confirm the phase label reads Catalogue Measure.
- [ ] Confirm the boss health bar is visible and readable.
- [ ] Confirm projectile colour contrasts against Verdant terrain.
- [ ] Confirm the first aimed shot follows a visible windup.
- [ ] Confirm the three-shot fan leaves readable lanes.
- [ ] Confirm pause steps produce genuine recovery time.
- [ ] Confirm cover blocks projectiles.
- [ ] Confirm projectiles do not pass through solid props or NPCs.
- [ ] Confirm ordinary melee and ranged attacks can damage the boss.

## Ashen opening phase

- [ ] Begin or shift the fight into the Ashen era.
- [ ] Confirm the phase label changes to Cinder Measure at high health.
- [ ] Confirm unresolved projectiles are cleared during the era transition.
- [ ] Confirm an in-progress reload is cancelled without losing reserve ammunition.
- [ ] Confirm the arena remains locked after shifting.
- [ ] Confirm boss health persists exactly.
- [ ] Confirm projectile colour remains visible against Ashen terrain.
- [ ] Confirm the Ashen attack order differs from the Verdant order.
- [ ] Confirm attack timing remains readable with the faster phase profile.

## Phase boundary

- [ ] Damage the boss from above 55 percent health.
- [ ] Deliver a hit large enough to cross the threshold.
- [ ] Confirm the hit stops at the final-phase boundary rather than killing the boss.
- [ ] Confirm Last Accession is announced.
- [ ] Confirm active projectiles clear during the transition.
- [ ] Confirm the transition pause prevents immediate unavoidable damage.
- [ ] Confirm the boss pattern resets to the first final-phase step.
- [ ] Confirm both curator echoes activate once.
- [ ] Confirm neither echo was visible or dangerous before the phase.
- [ ] Confirm repeated threshold checks do not activate duplicate echoes.

## Last Accession pattern

- [ ] Confirm the opening five-shot fan appears.
- [ ] Confirm the fan has distinct gaps from close and medium range.
- [ ] Confirm the recovery pause is long enough to reposition or reload.
- [ ] Confirm the eight-shot radial burst leaves traversable lanes.
- [ ] Confirm radial projectiles do not overlap into a solid wall of damage.
- [ ] Confirm the second pause occurs before the pattern repeats.
- [ ] Confirm the pattern order is deterministic across repeated attempts.
- [ ] Confirm the boss does not silently skip a step after being staggered.
- [ ] Confirm damage, knockback and camera feedback remain readable.

## Reinforcements

- [ ] Confirm each curator echo uses ordinary Ash Hound movement and combat rules.
- [ ] Confirm each echo has its own health and state key.
- [ ] Confirm echoes remain inside the encounter leash.
- [ ] Confirm echoes cannot spawn on Eli or Morrow.
- [ ] Confirm companion assistance can target active echoes.
- [ ] Confirm defeating an echo does not prematurely clear the arena.
- [ ] Confirm defeating the boss while echoes remain displays “reinforcements remain.”
- [ ] Confirm the exit remains locked until both echoes are defeated.

## Completion

- [ ] Defeat the boss and both curator echoes.
- [ ] Confirm the encounter-zone clear key is written.
- [ ] Confirm `underworks:boss:sentinel` becomes `defeated`.
- [ ] Confirm the completion banner appears once.
- [ ] Confirm five authored clock shards are granted once.
- [ ] Confirm fifteen Archive Chits are granted once.
- [ ] Confirm `underworks:boss:archive_released` is written.
- [ ] Confirm the arena boundary disappears.
- [ ] Confirm the return connection unlocks.
- [ ] Confirm Save Profiles can open again.
- [ ] Leave and return to the map.
- [ ] Confirm the boss and echoes do not respawn.
- [ ] Confirm rewards do not duplicate.

## Player defeat and rewind

- [ ] Allow the boss to defeat Eli during an opening phase.
- [ ] Confirm projectiles are cleared.
- [ ] Confirm reload state is cancelled safely.
- [ ] Confirm Eli and Morrow recover at valid authored positions.
- [ ] Confirm transient arena and phase state resets.
- [ ] Confirm durable rewards and outcome keys were not written early.
- [ ] Re-enter the arena and confirm the boss reconstructs coherently.
- [ ] Repeat defeat during Last Accession and confirm reinforcements reset safely.

## Save restrictions

- [ ] Try to open Save Profiles while the arena is active.
- [ ] Confirm the overlay does not open.
- [ ] Trigger a durable progression change during the fight.
- [ ] Confirm autosave remains deferred.
- [ ] Clear the complete arena.
- [ ] Confirm manual saving becomes available.
- [ ] Confirm any pending autosave can complete at a safe frame.

## Save and load after completion

- [ ] Save after the boss outcome has been written.
- [ ] Leave the map and change era.
- [ ] Load the save.
- [ ] Confirm the exact map and era restore.
- [ ] Confirm wallet and clock-shard rewards restore.
- [ ] Confirm boss, echo and zone outcomes restore.
- [ ] Confirm the arena does not relock.
- [ ] Confirm no boss phase or projectile state is restored transiently.
- [ ] Confirm the State editor displays the durable boss keys in World State.

## Era-shift policy

- [ ] Confirm this reference boss allows era shifting.
- [ ] Set `allow_era_shift` to false on a test copy.
- [ ] Confirm the player receives explicit blocked feedback.
- [ ] Confirm the era does not partially change.
- [ ] Confirm projectiles and phase state remain coherent after a blocked shift.
- [ ] Restore the reference source after the test.

## Connection-lock reliability

- [ ] Attempt the locked connection by keyboard.
- [ ] Attempt the locked connection by controller.
- [ ] Confirm neither attempt changes map, era, actor positions or boss state.
- [ ] Confirm the lock remains while only the boss is defeated.
- [ ] Confirm the lock remains while only one reinforcement survives.
- [ ] Confirm the lock releases immediately after complete zone clearing.

## Keyboard controls

- [ ] WASD and arrow movement remain responsive inside the arena.
- [ ] Space and C use the active melee or ranged weapon correctly.
- [ ] G reloads only ranged weapons.
- [ ] Q and X shift eras when permitted.
- [ ] R cycles Morrow’s commands.
- [ ] F recalls Morrow without escaping the arena.
- [ ] I, J and K respect combat and save restrictions.
- [ ] Escape pauses or closes overlays without corrupting the fight.

## Controller controls

- [ ] Movement remains responsive with D-pad and left stick.
- [ ] East face button attacks or fires.
- [ ] Right trigger reloads.
- [ ] West face button shifts eras when permitted.
- [ ] North face button cycles companion commands.
- [ ] Recall keeps Morrow within the arena.
- [ ] Menu actions do not accidentally fire or advance a phase.
- [ ] Controller reconnect does not duplicate an attack or reload.

## Visual readability

- [ ] Boss bar does not overlap the ammo HUD or quest tracker.
- [ ] Phase label remains readable at every window scale.
- [ ] Arena border remains visible without obscuring collision or projectiles.
- [ ] Boss and reinforcement silhouettes remain distinct.
- [ ] Intro, phase and completion banners do not hide unavoidable attacks.
- [ ] Projectile trails make speed and direction understandable.
- [ ] Damage and stagger feedback remain distinct from phase transitions.
- [ ] Colour alone is not the only indicator of phase or danger.

## Audio and final-art integration

Complete this section after production audio and sprites exist.

- [ ] Each phase has a distinct but related animation language.
- [ ] Windup sound begins early enough to be useful.
- [ ] Projectile audio remains spatially readable.
- [ ] Phase transition sound cannot be confused with damage.
- [ ] Reinforcement arrival is announced visually and audibly.
- [ ] Music layers transition without restarting abruptly.
- [ ] Completion audio does not play before every arena member is defeated.
- [ ] Accessibility settings can reduce flashes, shake and audio intensity.

## Balance review

- [ ] Melee-only completion is possible.
- [ ] Ranged-only completion is possible with a reasonable ammunition budget.
- [ ] The boss cannot be stun-locked indefinitely.
- [ ] Reinforcements do not create an unavoidable body-block.
- [ ] Healing opportunities exist during authored pause steps.
- [ ] Reload opportunities exist during authored pause steps.
- [ ] Average completion time fits the surrounding chapter pacing.
- [ ] Failure teaches a readable timing or positioning lesson.
- [ ] No single equipment choice trivialises every phase.
- [ ] Era shifting creates a meaningful tactical change rather than a free reset.

## Stress and soak testing

- [ ] Run 20 consecutive boss attempts without restarting Godot.
- [ ] Alternate eras every attempt.
- [ ] Alternate melee and ranged loadouts.
- [ ] Change Morrow’s command repeatedly during the fight.
- [ ] Trigger repeated defeats during each phase.
- [ ] Confirm no projectile or reinforcement count grows between attempts.
- [ ] Confirm no duplicate completion rewards occur.
- [ ] Confirm memory use remains stable.
- [ ] Confirm no parser, runtime or orphan-node errors appear.
- [ ] Confirm the editor remains responsive after repeated play stops and starts.

## Sign-off record

Record the following for each release candidate:

```text
Build / commit:
Godot version:
Operating system:
Input devices:
Resolution and scale:
Campaign and boss:
Attempts completed:
Save slots tested:
Outstanding defects:
Balance notes:
Accessibility notes:
Reviewer:
Date:
```
