# Audio Runtime Reliability

This note defines the production safeguards around Epochbound's procedural Audio & Mood layer.

## Generator lifecycle

Epochbound follows Godot's `AudioStreamGenerator` lifecycle deliberately:

1. Create an `AudioStreamPlayer` and assign an `AudioStreamGenerator`.
2. Set the generator to 22,050 Hz, a documented lower mix rate suitable for GDScript generation.
3. Add the player to the active scene tree.
4. Start playback.
5. Retrieve `AudioStreamGeneratorPlayback`.
6. Fill the available buffer immediately.
7. Refill only the currently available frame capacity during subsequent process frames.

The runtime exposes separate Music, Ambience, and SFX players and routes them to dedicated buses. If a custom project removes one of those buses, that player safely falls back to Master.

## Timing model

Music and ambience use independent sample clocks.

- Music timing determines step, envelope, lead, bass, and combat-layer phase.
- Ambience timing determines deterministic noise, chirps, crackles, tonal motion, and filtering.
- SFX voices track their own remaining duration and phase.

A profile change resets the new profile's synthesis clocks and fades newly generated audio in through the authored crossfade gate. This avoids ambience drift caused by whichever generator happened to request frames first.

## Event de-duplication

The runtime snapshots durable and transient gameplay indicators and only emits feedback on an edge transition. A flow change into gameplay and a map change occurring in the same frame produce one travel cue, not two.

Other edge-triggered events include:

- attack start;
- first frame of entity impact flash;
- player or companion health reduction;
- clock-shard increase;
- menu open and close;
- dialogue opening;
- cinematic start;
- combat entering and resolving;
- era change.

The number of simultaneous procedural SFX voices is bounded.

## Package installation

Archive inspection verifies paths, extensions, sizes, manifest records, and SHA-256 hashes before extraction. Structural archive validity is not enough to install a campaign.

`CampaignInstallService` performs a second phase:

1. Install into an isolated temporary root.
2. Run the current Audio-aware campaign validator against the extracted campaign.
3. Reject and delete the temporary campaign when any current content contract fails.
4. Preserve an existing installed campaign as a backup.
5. Promote the fully validated campaign atomically.
6. Restore the backup if promotion fails.

This prevents a hash-valid package containing malformed Presentation or Audio content from reaching `user://campaigns`.

## New campaign scaffolding

Campaign Studio creates `audio/core.json`, adds `audio_files` to `campaign.json`, runs the current validator, and removes the incomplete campaign folder if any step fails.

## Validation evidence

The focused `.github/workflows/audio-mood-validation.yml` workflow is manual, read-only, and exact-SHA governed. It verifies the official Godot 4.6.2 archive, compiles every registered entrypoint, imports the project, validates campaign content, and runs:

- Audio runtime and buffer readiness;
- Audio Studio editor state;
- malformed Audio records;
- new-campaign Audio scaffolding;
- hash-valid invalid-Audio package rejection.

The Windows `scripts/validate.ps1` gate runs these checks as part of the complete sixteen-tool regression suite.
