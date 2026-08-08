# Boss Phase Music Stems

Epochbound boss music extends the existing map-and-era Audio profile instead of replacing it with a disconnected track. A boss phase stem is a compact, original procedural layer selected by stable boss and phase identifiers.

The contract keeps exploration identity audible while allowing each authored phase to change rhythm, register, melodic pressure and percussion.

## Catalogue format

Audio catalogues may contain a `boss_stems` array beside `profiles` and `bindings`:

```json
{
  "boss_stems": [
    {
      "boss_id": "underworks_sentinel",
      "phase_id": "catalogue_measure",
      "display_name": "Catalogue Pulse",
      "tempo_multiplier": 0.92,
      "root_offset": 12,
      "melody_steps": [0, -99, 2, 4, -99, 3, 1, -99],
      "bass_steps": [0, -99, -99, 2, -99, -99, 1, -99],
      "waveform": "triangle",
      "pulse_width": 0.42,
      "gain": 0.10,
      "percussion_gain": 0.035
    }
  ]
}
```

The stable key is `boss_id|phase_id`. Duplicate keys are invalid even when they appear in different Audio catalogue files.

## Field behaviour

- `boss_id` references a loaded object definition whose Boss profile is enabled.
- `phase_id` references one phase declared by that boss.
- `display_name` is the author-facing stem name.
- `tempo_multiplier` scales the current map-and-era theme tempo without replacing its clock or tonal identity.
- `root_offset` transposes the stem relative to the active Audio profile root.
- `melody_steps` and `bass_steps` use scale degrees from the active profile. `-99` is a rest.
- `waveform` accepts the same original `pulse`, `triangle` or `sine` synthesis families as ordinary music profiles.
- `pulse_width` controls pulse timbre and remains validated even when another waveform is selected.
- `gain` controls the tonal stem layer.
- `percussion_gain` controls deterministic transient pressure.

No field may reference an external sample, script, soundfont, network asset or executable audio definition.

## Runtime selection

The Audio runtime reads the host runtime’s existing `engaged_bosses`, `boss_contexts` and `boss_phase_ids` dictionaries.

1. Only an actively engaged boss can select a stem.
2. The boss definition ID and current phase ID form the lookup key.
3. Multiple possible bosses are resolved in stable placement-ID order.
4. A missing stem leaves the ordinary map, era and combat mix intact.
5. A phase change resets only the phase-stem clock and oscillators.
6. The exploration theme, ambience, ducking and player volume settings continue uninterrupted.
7. Boss completion or disengagement fades the stem out and clears its transient context.

Boss stem state is presentation-only. It does not enter campaign saves, multiplayer snapshots, economy state or portable player profiles.

## Reference Sentinel direction

The built-in Underworks Sentinel authors three stems:

- **Catalogue Measure** keeps a restrained high-register mechanical pulse over Verdant Underworks.
- **Cinder Measure** accelerates the pressure and introduces a sharper pulse over the Ashen furnace profile.
- **Last Accession** adds the strongest rhythmic layer while preserving whichever Underworks era theme is currently active.

The phase stem follows the boss’s actual runtime phase, including an era shift at full health and the later health-threshold transition.

## Validation

Strict Audio validation rejects:

- malformed or duplicate stem keys;
- unknown object definitions;
- non-boss object references;
- unknown boss phase IDs;
- missing display names;
- fractional `root_offset` or sequence values;
- unsupported waveforms;
- empty, undersized or oversized sequences;
- values outside tempo, pitch, pulse-width or gain bounds.

Validation warns when an enabled authored boss phase has no corresponding stem. A missing stem is a review warning rather than a runtime failure because a campaign may deliberately retain only the ordinary combat layer.

## Editor support

Audio & Mood Studio displays the loaded boss-stem count and stable boss/phase bindings beside the map-and-era profile summary. Stem records remain source-controlled and use the same transactional campaign validation path as the rest of the Audio catalogue.

## Automated proof

The permanent regression:

- loads all three reference stems;
- resolves the Verdant Catalogue Measure stem on engagement;
- resolves Cinder Measure after the authored era shift;
- resets the phase-stem clock when the phase key changes;
- resolves Last Accession at the authored health threshold;
- clears the stem when no boss remains engaged;
- rejects malformed, duplicate and unknown boss-phase records;
- keeps the complete seventeen-system and real ENet gates green.

## Manual listening review

Automation proves deterministic selection and bounded synthesis, not musical quality. Before a release, listen for:

- audible continuity between exploration and boss layers;
- a distinct identity for each phase without abrupt volume jumps;
- enough rhythmic space for combat sound effects and dialogue;
- no clipping on laptop speakers or headphones;
- smooth era shifts while the boss remains engaged;
- a clear release when the arena is completed;
- originality rather than imitation of a recognisable protected soundtrack.
