# Audio & Mood Playtest Checklist

Use this checklist after the automated Godot gate passes. Review with headphones, ordinary laptop speakers and the system volume reduced to a comfortable low level.

## Startup and title

- [ ] The EVAVO splash begins quietly rather than producing an abrupt transient.
- [ ] The title theme enters cleanly after the splash.
- [ ] Title music is recognisably original and does not resemble a protected melody.
- [ ] Menu movement and confirmation remain audible without becoming repetitive or sharp.
- [ ] Campaign selection reduces intensity without muting the identity of the title profile.
- [ ] Starting a campaign transitions into the prologue without a click, gap or doubled track.

## Map and era identity

- [ ] Bellweather Verdant sounds warmer and more open than Bellweather Ashen.
- [ ] Clockwood Verdant has a distinct wooded/insect character.
- [ ] Clockwood Ashen communicates dryness and danger without excessive high-frequency noise.
- [ ] Museum Underworks Verdant feels enclosed and mechanical.
- [ ] Museum Underworks Ashen adds furnace pressure without masking combat feedback.
- [ ] Every era shift produces a short original stinger.
- [ ] The underlying map/era profile changes after the shift without overlapping old and new patterns indefinitely.
- [ ] Travel between maps crossfades rather than restarting at an uncomfortable level.

## Exploration

- [ ] Exploration music remains below dialogue and important one-shot feedback.
- [ ] Ambience is noticeable when listening for it but not tiring during a ten-minute loop.
- [ ] Procedural noise does not create a constant DC-like buzz, clicking or harsh aliasing.
- [ ] Melody and bass rests create breathing room.
- [ ] Pattern repetition supports the scene without demanding constant attention.
- [ ] The companion, pickups and interactions remain readable over the mix.

## Combat

- [ ] Approaching an active enemy fades in the combat layer.
- [ ] Combat intensity does not restart the base theme from the beginning.
- [ ] Attack feedback begins immediately with the attack action.
- [ ] Enemy impacts sound different from the player receiving damage.
- [ ] Companion damage remains recognisable without being distressingly loud.
- [ ] Projectile attacks, melee impacts and boss patterns remain distinguishable.
- [ ] Combat audio fades out after the complete encounter resolves.
- [ ] Repeated attacks do not exceed a comfortable output level.
- [ ] Boss combat remains readable when reinforcement, projectile and player sounds overlap.

## Pickups, crafting and economy

- [ ] Clock-shard and pickup feedback feels positive and concise.
- [ ] Repeated pickups do not create runaway overlapping voices.
- [ ] Inventory, crafting and merchant menus duck the environment consistently.
- [ ] Purchase, sale, equip and craft feedback remain audible over the ducked mix.
- [ ] Closing a menu restores the current map/era mix smoothly.

## Dialogue and cinematics

- [ ] Dialogue opening receives only a restrained cue.
- [ ] Music and ambience reduce while text is on screen.
- [ ] Dialogue remains readable at normal and low display volume.
- [ ] Cinematic starts receive a restrained transition cue.
- [ ] Cinematic ducking leaves enough atmosphere to preserve location.
- [ ] Skipping a cinematic returns to the same correct map/era profile as watching it.
- [ ] Save operations after cinematic completion do not preserve or replay transient sound effects.

## Pause, save and load

- [ ] Pause reduces the mix without causing silence that resembles an audio failure.
- [ ] Unpausing restores the mix smoothly.
- [ ] Save and load overlays use the menu ducking level.
- [ ] Loading another map/era profile does not retain the previous combat layer.
- [ ] Reloading a save does not repeat pickup, damage, travel or era-shift sounds incorrectly.
- [ ] Continue from the title resolves the correct saved map and era profile.

## Accessibility and comfort

- [ ] No feedback sound is painfully sharp through headphones.
- [ ] Low-frequency ambience does not cause persistent speaker rattling.
- [ ] Music, ambience and feedback remain distinguishable at low master volume.
- [ ] Menus and dialogue receive enough ducking for players with auditory-processing difficulty.
- [ ] No essential gameplay fact is communicated only by sound.
- [ ] The game remains fully playable with master audio muted.
- [ ] Ten minutes of Underworks ambience does not cause obvious fatigue.

## Technical stability

- [ ] No audio buffer underruns or repeated clicks are heard during map travel.
- [ ] Opening and closing every overlay does not create additional duplicate players.
- [ ] Rapid era shifting remains bounded and does not accumulate voices indefinitely.
- [ ] Repeated combat entries do not leave the combat layer permanently active.
- [ ] The SFX voice limit prevents runaway overlap.
- [ ] Switching campaigns reloads the correct catalogue and title profile.
- [ ] A campaign without audio data uses the safe fallback profile.
- [ ] Invalid custom audio data fails validation and falls back safely at runtime.
- [ ] Headless runtime and editor smoke tests terminate cleanly.

## Originality review

- [ ] No profile reproduces a recognisable melody from another game.
- [ ] No ripped sample, soundfont, voice clip or proprietary driver data is included.
- [ ] Theme names and descriptions belong to Epochbound’s original fiction.
- [ ] Bellweather, Clockwood and Underworks remain sonically related but individually recognisable.
- [ ] The overall result evokes a broad mid-1990s console action-RPG craft standard while sounding like Epochbound.
