# Player Settings and Accessibility

Epochbound now separates player-local preferences from campaign content and durable journey progress.

Player settings live at:

```text
user://settings/player_settings.json
```

They apply across built-in and installed campaigns. Campaign authors cannot force a player to use a particular volume, screen texture, camera shake, environmental-motion, flash, prompt or contrast level.

Campaign saves remain separate under `user://save_profiles`, and portable `.epochbound.zip` campaign packages do not contain player settings.

## Opening Options

Options is available from the title menu and from safe gameplay.

| Action | Keyboard | Controller |
| --- | --- | --- |
| Open Options directly | O | Use Pause, then Confirm |
| Move selection | Up / Down | D-pad Up / Down |
| Change selected value | Left / Right | D-pad Left / Right |
| Toggle or activate | E, Z, Space or C | South or East face button |
| Close and save | Escape, O or Start | Start |

During normal gameplay, Options opens only when no blocking dialogue, cinematic, transition, inventory, Journal, save menu or merchant interface is active. Gameplay simulation, animation and environmental time remain frozen while the panel is open.

Manual saves and autosaves are deferred until Options closes.

## Available settings

### Audio

- **Master Volume** multiplies every generated channel.
- **Music** controls exploration and combat music after the master level.
- **Ambience** controls location ambience after the master level.
- **Sound Effects** controls actions, impacts, menus, dialogue and event cues after the master level.

A zero channel value resolves to a bounded silent floor rather than an invalid logarithmic gain. The generated Music, Ambience and SFX players keep their existing bus routing and buffer contracts.

### Presentation intensity

- **Screen Texture** scales scanlines, dither and vignette together from zero to the authored maximum.
- **Camera Shake** scales all new impact and era-shift shake. Zero prevents new shake from starting.
- **World Motion** scales ambient foliage, ash, machinery motion and transient ground-response lifetime. Zero stops new movement disturbances.
- **Screen Flashes** scales era and impact flashes without changing combat outcomes.

These controls do not change collision, actor movement, projectile timing, combat damage, quest state or campaign data.

### Readability

- **Action Prompts** enables or disables nearest-target prompt boxes and their matching world pulse. Interactions remain usable when prompts are hidden.
- **High Contrast UI** uses black interface fills, white text, a brighter gold frame and a stronger danger colour. It does not rewrite campaign palettes or final sprite art.

## Atomic persistence

Player settings use a versioned schema and a guarded write sequence:

1. Sanitize every recognised value.
2. Validate the current schema and value ranges.
3. Write the complete settings object to a temporary file.
4. Flush and close it.
5. Rotate the previous valid primary file into a backup.
6. Promote the temporary file atomically.
7. Restore the previous valid file if promotion fails.

An invalid primary file is never rotated over a known-good backup. On startup, the store tries the primary file, then the backup, then safe defaults.

The current schema is `1`. Unknown future schemas are rejected rather than guessed. Older or partial supported records are migrated by preserving recognised values and filling newly introduced settings from safe defaults.

## Test isolation

The settings store accepts an alternate root for automated tests. The permanent regression suite uses:

```text
user://epochbound_test_player_settings
```

It never edits a developer or player’s real `user://settings` directory.

The regression verifies:

- default validation;
- range clamping and boolean fallback;
- schema-zero migration;
- future-schema rejection;
- exact range steps and toggles;
- temporary-file promotion;
- previous-file backup rotation;
- corrupt-primary backup recovery;
- safe promotion of recovered settings;
- title-menu Options exposure;
- gameplay save and autosave blocking;
- frozen animation while Options is open;
- independent Audio channel gains;
- zero-shake and zero-world-motion behaviour;
- disabled Action Prompts;
- High Contrast UI colours;
- Reset Defaults behaviour.

## Production rules

- Keep player preferences outside campaign JSON and save-profile payloads.
- Never package local settings with a campaign.
- Apply presentation settings at draw time or through bounded runtime multipliers.
- Do not let accessibility settings change durable progression outcomes.
- Keep every range between zero and one so future interfaces can represent values consistently.
- Add new fields with safe defaults and a migration path.
- Treat unknown future schemas as incompatible.
- Preserve the last complete valid settings file before replacement.
- Test title, pause, keyboard and controller access at native 640 by 360 and the 1280 by 720 window override.
