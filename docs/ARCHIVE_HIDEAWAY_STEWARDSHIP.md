# Archive Hideaway Stewardship

Epochbound's Archive Hideaway is an expedition refuge, not a farming simulator.

The useful life-simulation influence is the feeling of returning to a familiar place, seeing it become more cared for, and making small preparation decisions before going back into danger. The loop is intentionally closer to survival shelter stewardship than to a daily crop calendar.

## Foundation contract

- Expeditions qualify only from durable active-play time.
- A trip must last at least 90 seconds.
- One return opportunity is banked per qualifying expedition, capped at three.
- Salvage awards are deterministic and bounded from one to three units.
- Duplicate return calls cannot award twice.
- Four facilities have three authored levels and fixed costs.
- Prepared benefits are bounded by the restored facility level and consume exactly once.
- Exact-integral JSON numeric values restore safely; fractional durable counters fail closed.
- State is player-owned, versioned, JSON-safe and independent from wall-clock time.

## Facilities

| Facility | Preparation | Purpose |
| --- | --- | --- |
| Archive Hearth | Warmth | Safer preparation for cold or Ashen expeditions |
| Sheltered Coldframe | Recovery | Limited recovery preparation without crop chores |
| Salvage Workbench | Repair | Equipment and expedition-readiness preparation |
| Morrow's Corner | Companion Focus | A quiet bond and command-readiness benefit for Morrow |

## Explicit exclusions

This foundation does not add hunger, thirst, forced sleep, watering schedules, crop maintenance, offline growth, wall-clock deliveries, facility decay, or punishment for staying away. Those systems would turn the refuge into an obligation and conflict with Epochbound's action-RPG cadence.

## Live runtime bridge

The stewardship model is now connected to the authored `archive_hideaway` map. Leaving the refuge starts one active-play expedition, returning after at least 90 seconds awards bounded salvage and a preparation opportunity, and the four facilities are visible interaction points. `INTERACT` prepares a restored facility while `ATTACK` restores or upgrades it. Preparation remains optional and one-use: recovery restores a bounded amount of health, warmth softens one incoming hit, repair strengthens one successful Eli strike, and Morrow focus strengthens one successful companion strike. The complete state lives inside the existing durable session payload and is semantically save-validated; online clients cannot mutate it, and the Hideaway itself is an invasion-free sanctuary.
