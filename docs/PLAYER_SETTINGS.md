# Player Settings, Accessibility and Controls

Epochbound separates player-local preferences from campaign content and durable journey progress.

Player settings live at:

```text
user://settings/player_settings.json
```

They apply across built-in and installed campaigns. Campaign authors cannot force a player to use a particular volume, screen texture, camera shake, environmental-motion, flash, prompt, contrast or control-binding level.

Campaign saves remain separate under `user://save_profiles`, and portable `.epochbound.zip` campaign packages do not contain player settings or input bindings.

## Opening Options

Options is available from the title menu and from safe gameplay.

| Action | Fixed recovery input |
| --- | --- |
| Open Options directly | O |
| Pause or close blocking menus | Escape or Start |
| Move menu selection | Arrow keys or D-pad |
| Confirm menu selection | Enter, E, Z, Space, C or controller confirm |

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

## Keyboard and controller remapping

The **Controls** row opens a player-local binding editor. It exposes fourteen gameplay actions:

```text
Move Up
Move Down
Move Left
Move Right
Interact / Confirm
Attack / Fire
Shift Era
Morrow Command
Recall Morrow
Field Satchel
Quick Restorative
Journal
Save Profiles
Reload
```

Left and Right switch between Keyboard and Controller bindings. Confirm begins capture for the selected action. Keyboard capture accepts a physical key and controller capture accepts a button or a deliberate axis movement. Analogue noise below the capture threshold is ignored.

Movement defaults preserve both WASD and arrow keys, D-pad movement and left-stick axes. Rebinding one device does not remove the other device’s bindings.

### Reserved recovery inputs

Escape, O and Start remain fixed recovery inputs and cannot be assigned to gameplay actions:

- **Escape** always provides cancel and Pause recovery.
- **O** always provides direct Options recovery.
- **Start** always provides Pause and controller-menu recovery.

This prevents a malformed or accidental remap from making Options inaccessible. The reserved actions remain in `project.godot`; only the fourteen gameplay actions are replaced through the runtime `InputMap` profile.

### Conflict-safe swapping

One physical input cannot silently control two managed gameplay actions. When a captured key, button or axis is already used, Epochbound performs a conflict-safe swap:

1. The selected action receives the captured input.
2. The displaced action receives the selected action’s previous bindings for that device.
3. The complete profile is validated.
4. The runtime `InputMap` is replaced only after the profile remains complete and unique.

The editor therefore avoids ambiguous duplicates without leaving either action unbound.

### Dynamic prompts and bounded caches

World interaction prompts, reload hints, title guidance, pause guidance and the gameplay instruction rail read the active binding profile. They update immediately after a successful capture and do not require a restart.

The complete profile is sanitized, validated and converted into keyboard rows, controller rows and prompt labels only when settings load or a binding actually changes. Draw-time hint reads consume those bounded caches without rebuilding the fourteen-action profile every frame. A cache revision changes after load, capture, conflict-safe swap or reset, but remains stable across repeated drawing and prompt queries.

**Reset Controls** restores only the authored keyboard and controller defaults. **Reset All Defaults** restores controls together with every Audio, presentation and readability setting.

## Atomic persistence

Player settings use schema `2`. The nested control profile uses its own schema so input descriptors can evolve independently.

The guarded write sequence is:

1. Sanitize every recognised setting and binding descriptor.
2. Validate schemas, value ranges, required actions, device coverage, reserved inputs and duplicate signatures.
3. Write the complete settings object to a temporary file.
4. Flush and close it.
5. Rotate the previous valid primary file into a backup.
6. Promote the temporary file atomically.
7. Restore the previous valid file if promotion fails.

An invalid primary file is never rotated over a known-good backup. On startup, the store tries the primary file, then the backup, then safe defaults.

When startup uses a valid backup or migrates an older supported schema, the sanitized settings remain marked as a pending repair. Options names the recovery or migration source instead of presenting it as an ordinary load. The next deliberate Options close writes the current complete settings through the same atomic path, recreates the primary file and prevents later launches from repeating the same recovery. Startup itself remains read-only.

Schema-one settings migrate by preserving every recognised Audio, presentation and readability value and adding the complete default keyboard/controller profile. Unknown future schemas are rejected rather than guessed.

## Test isolation

The settings and controls stores accept alternate roots for automated tests. Permanent regressions use:

```text
user://epochbound_test_player_settings
user://epochbound_test_player_settings_recovery
user://epochbound_test_input_bindings
```

They do not edit a developer or player’s real `user://settings` directory.

The regression suite verifies:

- schema-one migration into schema two;
- range clamping and boolean fallback;
- future-schema rejection;
- temporary-file promotion and backup rotation;
- corrupt-primary and backup-only recovery;
- pending repair after a recovered load;
- isolated primary healing on Options close;
- all fourteen managed gameplay actions;
- keyboard, button and axis descriptor validation;
- physical-key labels and controller labels;
- analogue capture thresholds;
- fixed Escape, O and Start recovery inputs;
- conflict-safe binding swaps;
- exact runtime `InputMap` replacement;
- atomic custom-binding persistence;
- bounded Controls pagination at 640 by 360;
- immediate dynamic prompt updates;
- binding-cache rebuilds only at profile mutation boundaries;
- stable cache revisions during repeated draw-time hint and row reads;
- rejected reserved inputs leaving the active cache unchanged;
- Reset Controls and Reset All Defaults;
- title-menu Options exposure;
- gameplay save and autosave blocking;
- frozen animation while Options is open;
- independent Audio channel gains;
- zero-shake and zero-world-motion behaviour;
- disabled Action Prompts;
- High Contrast UI colours.

## Production rules

- Keep player preferences and input bindings outside campaign JSON, save-profile payloads and campaign packages.
- Never allow campaign data to erase, replace or require a local binding.
- Keep Escape, O and Start reserved for recovery.
- Persist physical keyboard locations rather than language-specific typed characters.
- Store controller axes with explicit direction and ignore small capture noise.
- Apply the complete binding profile through `InputMap`; do not maintain a parallel gameplay-input system.
- Use conflict-safe swaps instead of duplicate managed bindings.
- Rebuild control rows and prompt-label caches only when the validated profile changes.
- Keep draw-time hint reads allocation-bounded and free of full-profile sanitization.
- Apply presentation settings at draw time or through bounded runtime multipliers.
- Do not let accessibility settings change durable progression outcomes.
- Add new settings or actions with safe defaults and an explicit migration path.
- Treat unknown future schemas as incompatible.
- Preserve the last complete valid settings file before replacement.
- Keep startup reads non-destructive; promote recovered or migrated values only through the atomic writer.
- Test title, pause, keyboard and controller access at native 640 by 360 and the 1280 by 720 window override.
