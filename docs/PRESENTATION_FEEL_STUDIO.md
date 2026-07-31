# Presentation & Feel Studio

Presentation & Feel Studio gives Epochbound a source-controlled visual and tactile direction layer for an original mid-1990s 16-bit action RPG. It is designed to capture the strengths of that era—strong silhouettes, restrained palettes, moody environmental contrast, readable combat, compact framed interfaces and responsive camera movement—without reproducing protected characters, maps, scenes, assets, dialogue, music, interface layouts or terminology from any existing game.

## Production goals

The presentation layer should make a playable blockout feel intentional before final art arrives:

- silhouettes read at 640×360 and at the 1280×720 integer-scaled window;
- each map and era has a limited but distinct palette;
- environmental motion communicates temperature, age and danger;
- player, companion and enemies remain readable over every ground tone;
- hits, attacks and era changes produce immediate but restrained feedback;
- camera movement supports exploration without causing nausea;
- HUD and dialogue remain legible over action and atmosphere;
- all settings remain data-driven and validated.

The layer augments the existing runtime. It does not replace campaign maps, collisions, items, combat rules, quests, cinematics, saves or editor contracts.

## Campaign declaration

A campaign may declare one or more presentation catalogues:

```json
{
  "presentation_files": ["presentation/core.json"]
}
```

Campaigns without a presentation catalogue continue to load through the built-in `heritage_adventure` fallback profile and receive a validation warning rather than a hard failure.

## Profile format

```json
{
  "id": "bellweather_verdant",
  "display_name": "Bellweather Verdant",
  "palette": {
    "ink": "171b19",
    "shadow": "2b3730",
    "midtone": "66735d",
    "light": "d6c99a",
    "accent": "c99642",
    "danger": "a94c3f",
    "ui_fill": "141916",
    "ui_frame": "a58b53",
    "ui_text": "eee5ca"
  },
  "camera": {
    "follow_strength": 8.5,
    "deadzone": 18.0,
    "look_ahead": 18.0,
    "maximum_shake": 5.0
  },
  "atmosphere": {
    "kind": "pollen",
    "density": 22,
    "speed": 7.0,
    "opacity": 0.22
  },
  "screen": {
    "scanline_alpha": 0.028,
    "vignette_alpha": 0.20,
    "dither_alpha": 0.055
  },
  "actors": {
    "movement_bob": 1.7,
    "shadow_scale": 1.0
  }
}
```

### Palette

Every profile provides nine six-digit hexadecimal colours.

- `ink` defines the deepest outline and screen-edge tone.
- `shadow` separates bodies, props and architecture from the ground.
- `midtone` supplies environmental detail and footstep treatment.
- `light` supplies highlights, flashlight bloom and readable contrast.
- `accent` communicates clockglass, brass, objectives and positive feedback.
- `danger` communicates damage and hostile health.
- `ui_fill`, `ui_frame` and `ui_text` define the framed interface.

Profiles should use hue and value relationships, not simply brighter or darker copies of another era. A warm Ashen profile and a cool Verdant profile must remain distinguishable in grayscale through value and silhouette as well as colour.

### Camera feel

The root runtime still owns authored map scrolling and cinematic camera tracks. `PresentationCamera` adds a residual camera transform for normal play:

- `follow_strength` controls how quickly the visual camera catches its target;
- `deadzone` prevents small player movements from constantly moving the frame;
- `look_ahead` reveals more space in the current facing direction;
- `maximum_shake` caps all presentation shake regardless of event strength.

Cinematics neutralise this residual camera so authored camera tracks remain exact. HUD, dialogue and screen treatment live in a separate `CanvasLayer`, so world camera movement never drags interface elements away from the viewport.

### Atmosphere

Supported atmosphere kinds are:

```text
none
motes
pollen
fireflies
dust
embers
cinders
```

Atmosphere is decorative and deterministic for a map/era/profile combination. It must never obscure interaction markers, projectiles, health bars, dialogue or the player silhouette.

### Screen treatment

Scanlines, dither and vignette are deliberately subtle. They should suggest display texture and palette cohesion, not simulate a damaged television. Validation constrains their values, and a vignette above the recommended threshold produces a warning.

### Actor motion

`movement_bob` controls the compact step rhythm used by the presentation silhouette. `shadow_scale` reserves an authoring value for ground-contact tuning as final sprites replace the procedural blockout.

## Binding resolution

Presentation bindings select profiles by map and era:

```json
{
  "map_id": "museum_underworks",
  "era_id": "ashen",
  "profile_id": "underworks_ashen"
}
```

Resolution priority is:

1. exact map and exact era;
2. exact map and wildcard era;
3. wildcard map and exact era;
4. wildcard map and wildcard era;
5. `heritage_adventure`;
6. first valid profile in stable ID order.

Duplicate bindings for the same map/era pair are rejected.

## Runtime presentation

The current procedural presentation pass adds:

- hard-edged low-resolution silhouettes for Eli, Morrow, NPCs, enemies, pickups and props;
- grounded oval shadows and compact movement bob;
- facing-aware weapon silhouettes and attack glints;
- a capability-aware flashlight cone;
- footstep puffs, damage bursts, era flashes and bounded screen shake;
- deterministic map texture accents;
- map/era-specific pollen, dust, fireflies, embers and cinders;
- notched player, companion and enemy health bars;
- a compact framed HUD, map plaque, restorative panel and dialogue frame;
- restrained scanlines, dither and vignette;
- title and introduction framing.

These are original procedural blockout elements. Final sprite art can replace them without changing profile, camera, validation or campaign contracts.

## Editor workflow

1. Open the **Presentation** main-screen tab.
2. Select a built-in or installed campaign.
3. Create a default catalogue when the campaign has none.
4. Select a profile.
5. Edit its palette, camera feel, atmosphere, screen treatment and actor motion.
6. Save the profile.
7. The editor validates the complete campaign.
8. Invalid changes are rolled back to the previous source file.
9. Run the full validation gate and the manual playtest checklist.

Bindings remain source-controlled JSON in this production slice. Keeping map/era assignment explicit makes large campaign reviews and merge conflicts easy to inspect.

## Validation rules

Presentation validation rejects:

- unsafe or repeated catalogue paths;
- duplicate or malformed profile IDs;
- missing display names;
- missing or malformed palette colours;
- unsafe camera, atmosphere, screen or actor values;
- unsupported atmosphere kinds;
- unknown maps, eras or profiles in bindings;
- duplicate map/era bindings.

It warns about map/era combinations without an explicit binding and potentially excessive vignette values.

## Accessibility and safety

- Essential state may never be communicated only by colour.
- Text and health bars must remain readable with atmosphere active.
- Screen shake must remain capped and short.
- No rapid full-screen flashing is permitted.
- Scanlines and dither must remain subtle at both supported window sizes.
- Vignette may not conceal edge interactions.
- Cinematic subtitles remain above the presentation layer and preserve their authored timing.
- The presentation layer does not mutate durable gameplay state or save profiles.

## Originality boundary

Authors may study broad genre principles such as low-resolution readability, palette discipline, deliberate animation, tactile impacts, environmental mood and compact framed menus. They must not trace, recreate or closely imitate a protected game’s characters, creatures, locations, props, sprites, portraits, dialogue, music, sound effects, story beats, exact interface arrangement or distinctive visual assets.

Epochbound’s reference profiles, silhouettes, UI frame, particles, camera values and effects are authored specifically for Bellweather, Clockwood, the Museum Underworks, Eli and Morrow.
