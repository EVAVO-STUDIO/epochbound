# Archive Hideaway Journey Mementos

The Archive Hideaway memento shelf gives the refuge a memory of the journey. It is a reflective home feature, not a collectible currency, reward track or daily obligation.

## Design purpose

Epochbound takes the useful home-attachment lesson from life-simulation games without importing their routine-maintenance structure. Returning to the Hideaway should feel different because Eli and Morrow have changed the world, survived something difficult or made the refuge safer.

The shelf therefore reads existing durable campaign state. It does not create a second progression ledger.

## Authored reference mementos

The reference campaign provides six stable entries in authored order:

1. **First Safe Return** appears after the first qualifying active-play expedition returns to the Hideaway.
2. **Well Name Rubbing** reflects Morrow discovering the old Bellweather well name.
3. **Absent Chime Lens Case** reflects completion of the Missing Hour quest.
4. **Quieted Ash Mark** reflects clearing the eastern Bellweather Ash Hunt.
5. **Released Accession Plate** reflects defeating the Underworks Sentinel.
6. **Archive Haven Key** appears when all four facilities reach level three and the refuge becomes the Archive Haven.

Every entry has distinct Verdant and Ashen reflection copy and a deterministic blockout symbol on the shelf.

## Unlock contract

Mementos support three strict condition types:

- `state_equals` compares an existing JSON-safe campaign state key with an authored scalar value.
- `return_count_at_least` reads the already durable Hideaway return count.
- `refuge_tier_at_least` derives the current tier from existing facility levels.

All conditions on an entry must pass. Unknown condition types, unknown fields, duplicate IDs, non-finite numbers and malformed values fail validation.

## No new save field

The shelf stores no unlock list, inspection history or cursor in the campaign save. Availability is recalculated from existing validated state whenever it is needed.

The inspection cursor is session-local presentation state only. Loading a save, changing campaigns or restarting the runtime can safely reset it without losing progression.

## No reward payload

Memento records cannot contain item, currency, salvage, preparation, effect or grant payloads. Inspecting an entry changes only the visible dialogue and the transient shelf cursor.

Nothing is consumed. No salvage is spent. No prepared charge is used. No offline reward is generated.

## Data and map binding

A campaign opts in through:

```json
{
  "hideaway_stewardship_file": "hideaway_stewardship.json"
}
```

The definition owns the shelf interaction ID, slot budget and authored entries. The target Hideaway map must contain exactly the declared `hideaway_memento_shelf` interaction.

The complete campaign validator, direct package installer, fully verified install service and Package release validator all enforce this binding before content can be promoted.

## Presentation and localisation

The fixed Hideaway status panel shows unlocked and total memento counts when Eli stands near the shelf. The normal interact action cycles through available memories in authored order.

Names and both era reflections resolve through the strict UI localisation catalogue. English copy must exactly match the definition fallback, and pseudo-localisation exercises the shelf status inside the existing 464-pixel measured layout budget.

## Explicit exclusions

The memento system adds no:

- farming or watering loop;
- hunger, thirst or forced sleep;
- daily or weekly calendar;
- wall-clock growth;
- offline progress;
- maintenance or decay;
- random drops;
- combat advantage;
- economy reward;
- new save schema.
