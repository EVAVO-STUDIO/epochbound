# Package & Release Studio

Package & Release Studio turns a validated Epochbound campaign directory into a portable, inspectable and tamper-evident data package. It also installs third-party campaigns into the writable `user://campaigns` location used by the campaign browser.

## Core rules

- Campaign packages are data-only.
- Stable campaign, map, object, item, story and cinematic IDs are preserved.
- Archive traversal, symbolic links, hidden source files and executable content are rejected.
- Duplicate and case-colliding paths are rejected.
- Every declared file is checked against its expanded size and SHA-256 before extraction.
- Extraction occurs in an isolated staging directory.
- The complete campaign validator must pass before installation is promoted.
- Existing campaigns are never overwritten without explicit replacement consent.
- Identical source input must produce identical package bytes.

## Release metadata

Each campaign declares a semantic version, channel, package name, minimum runtime and licence:

```json
{
  "release": {
    "version": "0.1.0",
    "channel": "development",
    "package_name": "epochbound_demo",
    "minimum_runtime": "0.1.0",
    "license": "All Rights Reserved"
  }
}
```

Supported channels are `development`, `alpha`, `beta` and `release`.

## Package layout

```text
epochbound-package.json
campaign/
  campaign.json
  maps/
  objects/
  items/
  recipes/
  story/
  capabilities/
  economy/
  cinematics/
  assets/
```

The manifest records campaign identity, release metadata, source schema and a sorted list containing every relative path, expanded size and SHA-256.

## Allowed content

Packages accept JSON, PNG, JPEG, WebP, Ogg, WAV, MP3, text and Markdown. Scripts, scenes, native libraries, executables and arbitrary engine resources are rejected. Campaign functionality must remain expressible through Epochbound’s shared data contracts.

## Export workflow

1. Open the **Package** editor tab.
2. Select a source campaign.
3. Author its release metadata.
4. Save and validate the campaign.
5. Select **Export Package**.
6. Review file count, expanded bytes and SHA-256.
7. Distribute the `.epochbound.zip` without modifying it.

Exports are written to `user://campaign_exports` by default.

## Safe installation

1. Browse to or enter a package path.
2. Select **Inspect Package**.
3. Confirm title, version, file count, expanded size and package hash.
4. Select **Install Package**.
5. Epochbound extracts into isolated staging.
6. The full campaign validator runs against the staged tree.
7. Only valid content is promoted into `user://campaigns/<campaign_id>`.
8. Existing custom content is preserved unless replacement is explicitly enabled.

Imported content cannot shadow a built-in campaign ID.

## Atomic replacement

When replacement is enabled, the installed campaign is renamed to a backup only after the new package is fully extracted and validated. A failed promotion restores that backup. The backup is removed only after successful installation.

## Future extensions

The package contract can later add publisher signatures, dependency manifests, downloadable catalogues, localisation packs and optional asset bundles without weakening the current data-only and validation-first boundary.
