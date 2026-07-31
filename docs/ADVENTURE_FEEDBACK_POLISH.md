# Adventure Feedback Polish

This presentation pass gives Epochbound two pieces of classic action-RPG grammar that should be understood without opening a manual: the game names a place when the player arrives, and it identifies the one nearby action that will occur when the interaction button is pressed.

The implementation is original to Epochbound. It does not reproduce another game's interface frames, wording, icons or screen composition.

## Area arrival cards

An area card appears when:

- gameplay begins after the campaign introduction;
- the player travels to another map;
- the active era changes on the current map.

The card resolves its text from authored data:

```text
BELLWEATHER CROSSING
VERDANT AGE
```

It uses the active Presentation profile's interface colours, remains centered away from the health HUD and fades through bounded timings. A map transition holds the card timer until the transition veil has mostly cleared, preventing the location name from disappearing behind a fade.

Area cards do not create durable state. Saving, loading, skipping cinematics or revisiting a map reconstructs them from the current map and era.

## Context-sensitive action prompts

While normal gameplay is active, the feedback layer selects the nearest valid interaction among:

- reusable NPCs;
- reusable examinable props;
- interact-driven map connections;
- authored map interactions.

The prompt uses a single compact form:

```text
E / A  TALK
LOST ARCHIVIST
```

Supported action language includes:

```text
TALK
TRADE
EXAMINE
ENTER
USE
LOCKED
```

The target name comes from the authored definition or map record. A prompt is positioned above the target in screen space and clamped away from the viewport edges.

## Nearest-target rule

Only one action prompt is shown at a time. Candidates are compared by world-space distance to Eli, and the nearest candidate wins.

This prevents:

- several prompts overlapping in dense scenes;
- uncertainty about which NPC will receive the interaction;
- a doorway prompt replacing a closer conversation;
- menu-like lists appearing during normal exploration.

Authors should still avoid placing several interaction centres on exactly the same point. Stable distance selection is a safety rule, not a substitute for readable level composition.

## Capability-aware locked prompts

Connections and map interactions use the same `authored_requirements_met` method as the playable runtime. If Eli lacks an equipped capability, the prompt changes before the interaction button is pressed:

```text
E / A  LOCKED
SEALED CATALOGUE
```

The underlying interaction remains responsible for presenting its authored blocked dialogue. The prompt communicates state; it does not duplicate quest logic or mutate progression.

This keeps these systems aligned:

- Loadout Studio capability definitions;
- equipped-item capability state;
- map gates;
- Story Studio conditions;
- blocked dialogue;
- contextual presentation.

## Suppression rules

Action prompts are hidden while:

- dialogue is open;
- a cinematic is active;
- a map transition is unresolved;
- the game is paused;
- Field Satchel is open;
- Journal is open;
- Save Profiles is open;
- a merchant interface is open.

The prompt fades rather than popping when targets change. Area cards and prompts are screen-space presentation and remain independent from world-camera shake.

## Visual rules

- Keep the prompt smaller than dialogue and objective UI.
- Use the active profile's frame, fill, text and danger colours.
- Keep button language readable at 640 by 360.
- Do not use platform-specific button art when a text fallback is needed.
- Keep target names concise enough for a single line.
- Do not show an action that the interaction system will not perform.
- Use `LOCKED` only when authored requirements actually fail.
- Keep area cards clear of permanent HUD information.

## Automated contract

The Sprite runtime regression verifies:

- the playable scene binds `adventure_feedback_overlay.gd`;
- the feedback layer retains grounded animation and depth guarantees;
- Bellweather Crossing resolves its authored map and era names;
- a nearby NPC resolves a `TALK` prompt;
- the nearest prompt identifies its target;
- an unmet capability gate resolves `LOCKED` before interaction;
- the locked prompt exposes a disabled state;
- all previous cadence, depth, foreground and pause rules remain intact.

The static Sprite integration audit requires the area-card, prompt-selection and requirement-checking functions to remain wired to the playable scene.
