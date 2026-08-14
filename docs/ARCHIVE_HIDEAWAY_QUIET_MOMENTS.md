# Archive Hideaway Hearthside Quiet Moments

The quiet nook gives Epochbound a present-tense return-home rhythm without turning the Archive Hideaway into a daily routine or reward dispenser.

## Player experience

Stand near the two cushions beside the Archive Hearth and use the normal interact action. The nook cycles through every currently available moment in stable authored order.

Each entry presents a localised speaker, title and Verdant or Ashen reflection. Listening is always optional.

## Authored moments

1. **Threshold Breaths** is available from the beginning and establishes that pausing is allowed.
2. **The First Watch** appears after the first qualifying safe return.
3. **Hearth Watch** appears after the Archive Hearth reaches level one.
4. **Rain on Glass** appears after the Sheltered Coldframe reaches level one.
5. **The Last Ring** appears after the Salvage Workbench reaches level two.
6. **Both Ears Down** appears after Morrow's Corner reaches level two.
7. **The Borrowed Hour** appears after the Missing Hour is completed.
8. **Archive Haven Stillness** appears when all twelve facility levels form Archive Haven.

## Data contract

`hideaway_stewardship.json` owns the quiet-nook interaction ID, bounded moment count, stable authored order, speaker, conditions and per-era copy.

Allowed conditions are deliberately narrow:

- `always`
- `state_equals`
- `return_count_at_least`
- `facility_level_at_least`
- `refuge_tier_at_least`

Exactly one baseline `always` entry is required so a new journey never arrives at an empty nook. Unknown condition types, unknown facilities, duplicate IDs, unsupported speakers, malformed localisation keys and excess entries fail closed.

## Persistence boundary

There is **No new save field**. Availability is reconstructed from existing campaign and stewardship state whenever the Hideaway loads. The runtime cursor is visit-local presentation state only.

There is **No reward payload**. Listening grants no item, currency, salvage, return opportunity, preparation charge, combat effect or progression gate.

There is **No time advancement**. The action does not alter durable active-play time, wall clock time or expedition qualification.

## Explicit exclusions

Quiet moments do not add:

- forced sleep;
- hunger or thirst;
- a daily schedule;
- crop or watering chores;
- maintenance or decay;
- offline production;
- relationship grinding;
- repeatable reward farming.

The design goal is emotional shelter between dangerous expeditions, not obligation.
