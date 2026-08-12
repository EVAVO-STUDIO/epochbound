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

## Next integration boundary

The model is deliberately isolated from campaign save and map-transition authority in this release. A later runtime bridge can start expeditions when the player leaves the authored Hideaway map, record a return on re-entry, publish facility interactions, and consume preparation effects through existing combat, supply and companion systems. Keeping that bridge separate makes the state contract testable before it can affect a live campaign.
