# Localisation Foundation

Epochbound now has a strict localisation foundation for player-facing runtime text and campaign title, subtitle and intro copy.

This layer does not replace the authored English text. **English remains the authored fallback** in campaign JSON and catalogue records, so a missing translation never destroys the source copy or makes a campaign unreadable.

The foundation currently exposes two player-local choices:

```text
en        English
qps-ploc  Pseudo-localisation
```

`qps-ploc` is a deterministic development locale. It expands and accents the existing English text so clipped labels, stale caches, hard-coded strings and insufficient layout space are visible during testing. It is not presented as a real language and it is not a machine-translation service.

## Catalogue format

The shared runtime catalogue lives at:

```text
res://localisation/ui.json
```

Campaign catalogues are data-only JSON files referenced from `campaign.json`:

```json
{
  "localisation_files": [
    "localisation/core.json"
  ]
}
```

A catalogue uses schema `1`:

```json
{
  "schema_version": 1,
  "default_locale": "en",
  "locales": {
    "en": "English"
  },
  "messages": {
    "campaign.example.title": {
      "en": "EXAMPLE CAMPAIGN"
    }
  }
}
```

Campaign catalogues may omit `locales` when they only extend the shared locale set. Every message must still contain the catalogue's `default_locale`.

## Stable keys and fallback copy

Campaign manifests may declare:

```json
{
  "title": "EXAMPLE CAMPAIGN",
  "title_key": "campaign.example.title",
  "subtitle": "A NEW JOURNEY",
  "subtitle_key": "campaign.example.subtitle",
  "intro": [
    "The first page.",
    "The second page."
  ],
  "intro_keys": [
    "campaign.example.intro.01",
    "campaign.example.intro.02"
  ]
}
```

The fallback fields remain required. Validation rejects a declared key when:

- the key format is invalid;
- the referenced message is missing;
- `intro_keys` is not an array;
- the number of intro keys differs from the number of intro pages;
- the fallback title or subtitle is empty.

New Campaign scaffolding writes a bound `localisation/core.json` containing title, subtitle and three intro messages without changing the campaign's original English copy.

## Strict validation

Localisation fails closed before runtime or package promotion when:

- a catalogue has an unsupported schema;
- the root, locale map, message map or translation entry has the wrong type;
- a locale ID or message key is malformed;
- a default-locale message is missing;
- locale display labels conflict across catalogues;
- two catalogues define the same message key;
- `localisation_files` contains traversal, an absolute path, backslashes, a non-JSON file or duplicate paths;
- a translation changes named or printf placeholder parity.

Placeholder parity includes named tokens such as `{action}` and printf tokens such as `%s` and `%d`. Pseudo-localisation preserves those tokens, then applies replacements after the visible pseudo transformation.

## Deterministic fallback order

Resolution uses this order:

1. the requested supported locale when a concrete translation exists;
2. the exact English catalogue message;
3. the caller's authored fallback text;
4. the stable message key as a visible final diagnostic.

For `qps-ploc`, the resolved English or fallback text is transformed deterministically at runtime. The pseudo locale therefore requires no duplicated authored catalogue copy and cannot drift from the English placeholders.

## Player-local language setting

Language is stored in schema `3` player settings at:

```text
user://settings/player_settings.json
```

The Language row sits alongside the existing Audio, presentation, readability and Controls settings. Changing it refreshes title, campaign, intro, Options and control-label caches immediately. The selection is persisted through the existing fail-closed atomic settings writer.

The localisation setting remains separate from campaign saves, multiplayer snapshots and portable campaign packages. Campaign authors cannot force or overwrite the player's language choice.

## Package and campaign safety

Campaign packages include referenced localisation JSON as ordinary data-only files. During installation, the staged campaign's localisation paths, catalogues and manifest key references are validated before the staging directory can replace an installed campaign.

No executable translation scripts, network requests, external translation APIs or hidden language database are accepted. Production translations beyond English and pseudo-localisation are a later authored-content boundary built on this same validated schema.

## Runtime surfaces covered

The foundation currently covers:

- splash and title menus;
- campaign browser headings and status copy;
- campaign title, subtitle and intro pages;
- Pause guidance;
- Options headings, setting labels, values and notices;
- Controls headings, action labels, device labels, capture prompts and conflict feedback;
- the compact gameplay control rail;
- campaign dialogue or interaction records that explicitly provide stable localisation keys;
- deterministic pseudo fallback for existing authored runtime strings.

Story graphs, item names, merchant copy and all final production translations remain opt-in authored catalogue work. Their existing English source remains unchanged.

## Regression coverage

The permanent gate proves:

- exact English fallback;
- pseudo expansion and visible bounding;
- named and printf placeholder preservation;
- traversal and duplicate path rejection;
- duplicate key and locale-label conflict rejection;
- reference campaign title, subtitle and intro key integrity;
- default campaign scaffolding;
- schema-two to schema-three player-setting migration;
- invalid locale fallback and raw validation rejection;
- live English-to-pseudo-to-English runtime switching;
- control-label cache rebuild only at locale mutation boundaries;
- staged package validation before promotion;
- repository-wide content counts and exact-main schema `2.9` evidence through `localisationValidation`.
