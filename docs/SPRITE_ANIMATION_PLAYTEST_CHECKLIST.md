# Sprite Animation Playtest Checklist

Use this checklist after the automated Godot gate passes. Test at the native 640 by 360 viewport and the 1280 by 720 window override.

## Preparation

- Pull the exact `main` SHA being tested.
- Run `scripts/validate.ps1` with Godot 4.6.2.
- Confirm the Sprite tab appears in the Godot main-screen toolbar.
- Confirm no imported commercial or third-party sprite content is present.
- Test once with procedural profiles and once with a temporary original PNG atlas.

## Eli movement

- Stand idle facing down, left, right and up.
- Confirm the silhouette remains readable in every direction.
- Walk horizontally and vertically.
- Confirm the six-frame cadence advances smoothly without foot sliding.
- Change direction quickly and confirm facing changes immediately.
- Stop mid-step and confirm the animation resolves to idle cleanly.
- Walk against collision and confirm animation does not imply movement while position remains blocked for long periods.
- Confirm the flashlight cone follows the same direction as Eli.

## Eli attacks

- Attack in all four directions.
- Confirm a readable anticipation pose appears before maximum reach.
- Confirm follow-through ends near the gameplay damage window.
- Confirm the weapon never appears detached from Eli's hand.
- Confirm repeated attacks restart cleanly without impossible frame blending.
- Switch between melee and ranged equipment.
- Confirm attack presentation remains consistent with the equipped weapon type.
- Take damage during or immediately after an attack and confirm hurt feedback takes priority safely.

## Morrow movement

- Walk while Morrow follows from every side of Eli.
- Confirm Morrow faces his own travel direction rather than copying Eli.
- Issue Stay, Seek, Guard and Recall commands.
- Confirm command movement retains the dog gait and facing contract.
- Confirm tail and leg motion remain restrained rather than flickering.
- Confirm recovery relocation does not leave Morrow frozen in a walk frame.
- Confirm hurt and recovery states return to idle or walk correctly.

## NPC and enemy animation

- Speak with a humanoid NPC while approaching from multiple directions.
- Confirm NPC silhouettes and pivots stay grounded.
- Engage an Ash Hound.
- Confirm patrol and pursuit use walk frames.
- Confirm windup uses attack frames before damage.
- Confirm stagger and hit flash use hurt treatment.
- Confirm return-to-spawn does not face the wrong direction.
- Fight the Underworks Sentinel and Curator Echoes.
- Confirm boss and reinforcement animation does not break phase logic or arena readability.

## Pickups and props

- Inspect crates, pillars and static props.
- Confirm one-direction profiles do not jitter or rotate unexpectedly.
- Collect a Clock Orb or shard pickup.
- Confirm its pulse remains readable without overpowering the HUD.
- Confirm static props remain anchored to their authored positions.

## Atlas import

- Create an original transparent PNG using the documented grid.
- Set its relative path in Sprite Studio.
- Confirm the editor validates the file.
- Confirm nearest-neighbour rendering with no blurred edges.
- Confirm source frames do not bleed into neighbouring cells.
- Confirm pivot alignment remains stable between idle, walk, attack and hurt.
- Confirm atlas reload after editor save and game restart.
- Confirm missing, undersized and traversal paths are rejected.
- Confirm a non-alpha PNG is rejected.

## Map and era transitions

- Travel between Bellweather Crossing, Clockwood Edge and Museum Underworks.
- Shift between Verdant and Ashen eras.
- Confirm animation profiles remain loaded after every transition.
- Confirm animation state resets safely rather than resuming a stale attack or hurt frame.
- Confirm procedural and atlas profiles can coexist in one campaign.

## Menus, dialogue and cinematics

- Open the Field Satchel, Journal, Trade and Save overlays.
- Confirm character animation does not distract through paused interfaces.
- Open and close dialogue repeatedly.
- Play and skip each reference cinematic.
- Confirm actors return to a valid idle or movement state after cinematic blocking.
- Confirm camera, HUD and Sprite overlay remain aligned.

## Save and load

- Save while idle.
- Save after walking, attacking and changing era.
- Reload each profile.
- Confirm durable position and facing restore correctly.
- Confirm transient animation frame, attack timing and hurt timing are rebuilt rather than persisted.
- Confirm no atlas texture is serialized into save data.

## Performance and stability

- Travel continuously for at least ten minutes.
- Repeatedly switch eras and maps.
- Spawn and defeat multiple encounters.
- Confirm no growing atlas cache, duplicate overlay or redraw hitch is visible.
- Confirm no generator, parser or runtime errors appear in the Godot console.
- Confirm frame timing remains stable at the target frame rate.

## Visual quality

- Test on a laptop display, desktop monitor and scaled window.
- Confirm silhouettes read against both Verdant and Ashen palettes.
- Confirm outlines remain hard and pixel-appropriate.
- Confirm actor scale feels consistent with doors, props, collision and interaction radii.
- Confirm effects do not hide attacks, pickups or dialogue prompts.
- Confirm the result feels like an original premium 1990s-style action RPG rather than a copy of a specific game.

## Completion record

Record:

- tested commit SHA;
- Godot version;
- operating system;
- keyboard and controller models;
- profiles tested;
- atlas paths tested;
- failures and reproduction steps;
- screenshots or video references;
- final pass or blocker decision.
