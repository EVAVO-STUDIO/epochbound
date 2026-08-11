# Localisation Layout Safety

Epochbound renders its production interface at a fixed 640 by 360 viewport. Localised copy therefore cannot rely on desktop-sized controls, arbitrary clipping, or a later manual pass to repair every language. The runtime measures the actual Godot fallback font and applies one deterministic fitting policy before drawing critical text.

This layer protects layout. It does not translate copy, replace authored English, or change localisation fallback rules.

## Fitting order

Every protected single-line surface follows the same order:

1. Normalise embedded line breaks into spaces.
2. Measure the complete string at the authored preferred font size.
3. Reduce the size one integer step at a time down to the authored minimum.
4. When the minimum size still cannot fit, retain visible copy with one stable ellipsis.
5. Fail closed when the surface has no usable width or the font is unavailable.

Protected blocks use the equivalent bounded order:

1. Preserve authored paragraph breaks.
2. Wrap on deterministic word boundaries.
3. Split an individual long token only when it exceeds the full line width.
4. Reduce the font size only inside the authored range.
5. Respect the declared line count and height budget.
6. Ellipsise the final visible line when content must be omitted.

The utility never reads wall-clock time, random values, network services, machine translation, or platform-specific measurements.

## Production surfaces

Measured fitting now covers the fixed-viewport surfaces most exposed to text expansion:

- title menu entries and confirmation help;
- campaign titles, source labels, headings and help copy;
- campaign introduction pages;
- player and companion HUD names;
- map and era labels;
- Options title, header, setting labels, values, notices and footer;
- Controls title, header, action labels, binding values, capture notices and footer;
- contextual action prompts and reload hints.

The existing English text remains the exact authored fallback. The deterministic pseudo-localisation locale is measured against the same production pixel budgets so expansion problems are detected before human translations arrive.

## Authored constraints

The fitter does not invent layout dimensions. Every caller declares:

- the maximum pixel width;
- the preferred font size;
- the minimum permitted font size;
- for blocks, the maximum line count, height and line gap;
- the intended left, centre or right alignment.

This keeps the visual design authoritative. A new translation cannot silently enlarge a panel, move gameplay HUD elements, or change the 640 by 360 composition.

## Determinism and accessibility

The same string, font and constraints always produce the same fitted result. Tests compare complete result dictionaries between repeated calls and verify that every measured width and height remains inside its budget.

Visible ellipsis is preferred to invisible clipping. Critical current English and pseudo-localised strings are required to fit without truncation. The ellipsis path remains covered for future unusually long content and malformed authoring fixtures.

## Validation

The permanent gate includes:

- a fail-closed Python source contract;
- a dedicated Godot compilation probe;
- direct measurement of single-line shrink and ellipsis behaviour;
- deterministic block wrapping and height checks;
- current English and pseudo-localised UI budget checks;
- reference campaign intro-page measurement;
- canonical runtime, Options and Controls integration checks;
- primary, Audio and Sprite workflow coverage;
- exact-main schema `2.10` evidence through `localisationLayoutValidation`.

Any parser error, runtime error, overflow, missing integration, nondeterministic result, unexpected truncation, or tracked-source mutation fails the release gate.

## Deliberate boundaries

This foundation does not provide complete human translations, bidirectional layout, locale-specific fonts, font fallback authoring, hyphenation dictionaries, plural rules, gender rules, subtitle timing, or accessibility-scale UI reflow. Those remain separate production layers built on the same strict catalogue and measured layout contracts.
