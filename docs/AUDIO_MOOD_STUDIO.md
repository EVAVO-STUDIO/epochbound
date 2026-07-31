# Audio & Mood Studio

Audio & Mood Studio provides Epochbound with an original, source-controlled sound direction layer for a mid-1990s 16-bit action RPG. It generates music, ambience and short feedback sounds in Godot at runtime. The system does not contain copied melodies, ripped samples, emulated sound-driver data or recordings from any existing game.

## Goals

The audio layer should make every playable state feel intentional before final mastered audio assets exist:

- each map and era has a recognisable musical and environmental identity;
- combat raises tension without replacing the exploration theme abruptly;
- era shifts, travel, attacks, damage, discoveries and menu actions receive immediate feedback;
- dialogue, cinematics, pause and menus reduce competing sound through authored ducking;
- sounds remain clear on laptop speakers, headphones and low-volume playback;
- profiles are deterministic, inspectable and validated;
- authored values are bounded to prevent clipping, painful frequencies and extreme transitions.

## Campaign declaration

A campaign declares one or more audio catalogues:

```json
{
  "audio_files": ["audio/core.json"]
}
```

Campaigns without an audio catalogue use the built-in `museum_after_hours` fallback profile and receive a validation warning.

## Catalogue structure

```json
{
  "schema_version": 1,
  "title_profile_id": "museum_after_hours",
  "profiles": [],
  "bindings": []
}
```

`title_profile_id` supplies splash, title, campaign-browser and prologue audio. Map and era bindings use the same most-specific-first resolution rule as Presentation & Feel Studio.

```json
{
  "map_id": "bellweather_crossing",
  "era_id": "verdant",
  "profile_id": "bellweather_verdant"
}
```

Bindings may use `*` for a map or era fallback. A specific map-and-era binding outranks a wildcard binding.

## Music profile

```json
{
  "music": {
    "tempo_bpm": 94.0,
    "root_midi": 50,
    "scale": [0, 2, 3, 7, 9],
    "melody_steps": [0, 2, 4, -99, 3, 2, 0, -99],
    "bass_steps": [0, -99, 0, -99, 3, -99, 1, -99],
    "waveform": "pulse",
    "pulse_width": 0.28,
    "gain": 0.17,
    "combat_gain": 0.10
  }
}
```

### Pitch language

- `root_midi` establishes the tonal centre.
- `scale` lists semitone offsets within one octave.
- melody and bass values are scale degrees rather than raw notes.
- `-99` represents a rest.
- positive degrees continue into higher octaves; negative degrees continue below the root.

This keeps each pattern compact while allowing a campaign to define pentatonic, modal, tense or unusual original pitch collections.

### Waveforms

Supported music waveforms are:

- `pulse` for clear, animated lead lines;
- `triangle` for softer melodic or bass treatment;
- `sine` for restrained, hollow or subterranean themes.

Pulse width is constrained between `0.10` and `0.90`. Audio Studio does not load arbitrary synthesiser code or executable sound definitions.

## Dynamic combat layer

`combat_gain` controls an additional high-register voice and restrained procedural percussion. Combat intensity fades in when directed enemies or a boss are actively threatening the player, and fades out after the encounter resolves.

The exploration theme continues underneath, avoiding a jarring complete track restart for every small encounter. Boss direction can later extend this same contract with authored phase-specific stems rather than replacing it.

## Ambience profile

```json
{
  "ambience": {
    "kind": "machinery",
    "gain": 0.085,
    "tone_hz": 58.0,
    "motion": 0.46
  }
}
```

Supported ambience kinds are:

- `room_tone`
- `pollen`
- `insects`
- `embers`
- `cinders`
- `machinery`
- `furnace`
- `wind`
- `rain`

Ambience is generated from deterministic filtered noise and low-frequency tonal motion. It does not read microphone input, external samples or network content.

## Mix and ducking

```json
{
  "mix": {
    "menu_duck": 0.42,
    "cinematic_duck": 0.27,
    "pause_duck": 0.18,
    "crossfade_seconds": 0.75
  }
}
```

Multipliers reduce music and ambience while another layer needs attention:

- menu and dialogue ducking protects text readability and interface feedback;
- cinematic ducking gives timed dialogue and staging room;
- pause ducking communicates suspended play without muting the world entirely;
- crossfade time controls safe profile and flow transitions.

Ducking values cannot exceed unity or fall below the validated minimum.

## Runtime feedback sounds

The controller synthesises bounded original feedback for:

- player attacks;
- enemy impacts;
- player and companion damage;
- pickups and clock-shard rewards;
- era shifts;
- map travel;
- menu opening and closing;
- dialogue opening;
- combat entering and resolving;
- cinematic starts.

No transient sound state is saved. Loading a profile rebuilds the correct map, era and flow mix from durable gameplay state.

## Editor workflow

1. Open the **Audio** main-screen tab.
2. Select a campaign and audio profile.
3. Set tempo, tonal root, waveform and gains.
4. Edit the scale, melody and bass patterns.
5. Select ambience character and movement.
6. Tune menu, cinematic and pause ducking.
7. Save the profile.
8. Audio Studio writes the catalogue, validates the complete campaign and rolls back invalid edits.
9. Run the full Godot gate and complete the listening checklist.

Pattern fields accept commas or spaces. Use `-`, `r`, `rest` or `-99` for a rest.

## Validation

Validation rejects:

- unsafe catalogue paths;
- unsupported schema versions;
- duplicate profile IDs or bindings;
- unknown map, era or profile references;
- invalid title-profile references;
- unsupported music waveforms or ambience kinds;
- unsafe tempos, root notes, pulse widths or gains;
- missing or oversized scale and sequence data;
- sequence values outside the supported degree range;
- ducking or transition values outside production bounds.

Warnings identify mixes whose combined exploration and combat gains may clip on small speakers and map/era contexts without explicit bindings.

## Originality rules

Audio profiles must not encode, transcribe or closely imitate a recognisable protected melody from another game. Do not import ripped console samples, soundfonts, voice clips, ambience recordings or proprietary audio-driver data.

Acceptable direction references broad qualities such as:

- uneasy museum stillness;
- warm wooded exploration;
- brittle ash and heat;
- mechanical subterranean tension;
- compact pulse leads;
- sparse pentatonic or modal writing;
- responsive combat layering.

The final result must remain identifiable as Epochbound and support its original Bellweather, Clockwood and Museum Underworks fiction.
