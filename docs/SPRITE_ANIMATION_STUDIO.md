# Sprite & Animation Studio

Sprite & Animation Studio is Epochbound's source-controlled character-art and frame-timing layer. It gives the game a proper mid-1990s action-RPG animation contract now, while retaining an original procedural fallback until final pixel atlases are supplied.

The system is not a recreation of another game's sprites, poses, animation sheets or palette. All final art must be created for Epochbound's own cast, creatures, equipment and world.

## Responsibilities

The Sprite system controls:

- stable animation profile IDs;
- player, companion, NPC, enemy, pickup and prop bindings;
- optional transparent PNG atlases;
- source-frame dimensions;
- in-game render dimensions;
- ground-contact pivots;
- one-row or four-direction layouts;
- idle, walk, attack and hurt timing;
- looping and non-looping playback;
- nearest-neighbour atlas rendering;
- deterministic procedural fallback animation;
- current-content validation before package installation.

Presentation Studio still controls palette, atmosphere, camera and interface treatment. Sprite Studio controls frame identity and timing. The two systems intentionally remain separate.

## Campaign declaration

A campaign declares one or more animation catalogues:

```json
{
  "animation_files": [
    "animation/core.json"
  ]
}
```

Campaigns without an animation catalogue remain playable through the built-in procedural profiles and receive a validation warning.

## Catalogue structure

```json
{
  "schema_version": 1,
  "profiles": [],
  "bindings": []
}
```

### Profile example

```json
{
  "id": "eli_field_kit",
  "display_name": "Eli Field Kit",
  "atlas": "sprites/eli_field_kit.png",
  "frame_size": {"x": 32, "y": 40},
  "render_size": {"x": 32, "y": 40},
  "pivot": {"x": 16, "y": 34},
  "directions": 4,
  "fallback_style": "hero",
  "animations": {
    "idle": {"row": 0, "frames": 4, "fps": 3.0, "loop": true},
    "walk": {"row": 4, "frames": 6, "fps": 10.0, "loop": true},
    "attack": {"row": 8, "frames": 5, "fps": 15.0, "loop": false},
    "hurt": {"row": 12, "frames": 2, "fps": 12.0, "loop": false}
  }
}
```

## Atlas layout

Sprite atlases are transparent PNG files arranged on a strict rectangular grid.

### Direction order

Four-direction profiles use this row order:

```text
0  Down
1  Left
2  Right
3  Up
```

Each animation's `row` is its first directional row. For example, a four-direction walk animation beginning at row 4 occupies rows 4 through 7.

One-direction profiles use only their authored base row. This is appropriate for pickups, static props and symmetrical effects.

Eight-direction profiles are deliberately rejected until the runtime implements and tests eight distinct directional rows. The editor exposes only one-row and four-row modes.

### State order

Every profile defines:

- `idle`
- `walk`
- `attack`
- `hurt`

States may use different frame counts and playback rates. Attack and hurt animations are normally non-looping. Idle and walk normally loop.

### Frame size

`frame_size` is the exact source-cell size in the PNG. The atlas width must contain the largest declared frame count, and its height must contain every declared state and direction row.

### Render size

`render_size` controls the size drawn in the 640 by 360 game view. It can differ from `frame_size`, but production profiles are limited to 128 pixels in either dimension to prevent oversized content from breaking composition and collision readability.

### Pivot

`pivot` is measured in source-frame pixels. It should identify the character's ground-contact point rather than the centre of the image.

A reliable actor pivot usually sits:

- near the horizontal centre;
- several pixels above the bottom edge;
- between the feet for humanoids;
- beneath the torso for animals;
- below the visual centre for hovering objects.

Pivots outside the source frame are rejected.

## Runtime state selection

The runtime resolves animation state from actual gameplay:

### Eli

- `hurt` while the player hurt lock is active;
- `attack` while the attack timer is active;
- `walk` while movement speed exceeds the authored threshold;
- otherwise `idle`.

### Morrow

- `hurt` during companion hurt recovery;
- `attack` during companion attack feedback;
- `walk` from Morrow's own movement, not Eli's facing;
- otherwise `idle`.

### Runtime entities

Entity animation derives from Combat Director modes:

- chase, pursue, patrol and return use `walk`;
- windup and attack use `attack`;
- stagger and hit flash use `hurt`;
- all other modes use `idle`.

## Binding resolution

Bindings connect runtime targets to profiles. More-specific targets are supplied before general fallbacks.

Supported target forms include:

```text
player
companion
placement:<placement_id>
object:<object_definition_id>
shape:<appearance_shape>
kind:<object_kind>
*
```

A profile may therefore animate one exact boss placement, every instance of an enemy definition, every beast-shaped object or every otherwise-unmatched prop.

Example:

```json
{
  "target": "shape:beast",
  "profile_id": "ash_beast_gait"
}
```

## Procedural fallback

An empty `atlas` field keeps the profile fully usable. The runtime draws original hard-edged animation frames for these styles:

- `hero`
- `dog`
- `humanoid`
- `beast`
- `orb`
- `prop`

The fallback now includes:

- six-frame walking cadence;
- alternating feet and arm swing;
- directional silhouettes;
- attack anticipation and follow-through;
- hurt recoil;
- Morrow's independent facing, trot and tail movement;
- entity windup, pursuit and stagger treatment;
- capability-aware flashlight illumination;
- profile-driven frame timing.

Final PNG atlases replace the drawn silhouette without changing gameplay state selection, bindings, editor data, validation or package rules.

## Image loading and filtering

Atlases are loaded with Godot `Image`, retained as `ImageTexture` objects and drawn through atlas source rectangles. The overlay holds textures in a cache so they remain alive across redraws.

The Sprite overlay enforces nearest-neighbour filtering. Campaigns should not pre-scale source sheets with smoothing or interpolation.

## Sprite Studio workflow

1. Open the **Sprite** tab.
2. Select a campaign and profile.
3. Enter an optional relative PNG atlas path.
4. Set source frame, render size and pivot.
5. Choose one-row or four-direction layout.
6. Select the procedural fallback style.
7. Configure row, frame count, FPS and loop state for all four animations.
8. Save the profile.
9. The editor validates the complete campaign.
10. Invalid edits restore the previous source file and editor state.
11. Run the exact Godot validation gate and the manual checklist.

## Asset preparation rules

Final production atlases should:

- use transparent RGBA PNG;
- avoid baked shadows unless the profile explicitly replaces runtime shadows;
- keep every frame on the same grid;
- keep feet or ground contact aligned to the profile pivot;
- use clean indexed-looking colour clusters rather than softened gradients;
- avoid subpixel placement and anti-aliased outer edges;
- preserve clear silhouettes at native 640 by 360 presentation size;
- keep weapons and held tools readable in every direction;
- maintain consistent character proportions across states;
- use original Epochbound designs.

Do not import ripped sprites, traced frames, edited commercial character sheets or recognisable animation sequences from an existing game.

## Validation

Validation rejects:

- unsafe catalogue paths;
- non-PNG atlas paths;
- absolute paths or traversal;
- duplicate profile IDs or bindings;
- unknown profile bindings;
- invalid frame, render or pivot records;
- unsupported direction counts;
- missing animation states;
- invalid rows, frame counts, FPS or loop flags;
- missing or unreadable authored atlases;
- atlases too small for their declared grid;
- oversized textures or render dimensions;
- pivots outside source frames;
- non-alpha atlas images.

The strict package installation service validates extracted animation content before promoting it into `user://campaigns`. A package can have a correct manifest and hashes and still be rejected when its sprite contract is invalid.

## Reference profiles

The Hours Beneath contains six original profiles:

- Eli Field Kit
- Morrow Field Gait
- Museum Humanoid
- Ash Beast Gait
- Clock Orb Pulse
- World Prop

They currently use the procedural fallback, proving production timing and bindings before final atlases arrive.

## Automated coverage

The permanent Sprite Animation gate verifies:

- direct compilation of the runtime, validators, editor and tests;
- strict project import;
- complete campaign validation;
- reference profile and binding resolution;
- deterministic frame advancement;
- Morrow's independent movement-facing;
- strict editor state and safe-path rejection;
- synthetic PNG dimension validation;
- malformed profile rejection;
- new-campaign animation scaffolding;
- rejection of hash-valid packages containing invalid animation data;
- clean source after validation.
