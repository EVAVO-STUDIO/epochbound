# Archive Hideaway Live Runtime

The Archive Hideaway is Epochbound's expedition refuge: a quiet return-home cadence inside an action RPG, not a separate farming simulator.

## Player loop

1. Enter the authored Archive Hideaway from western Bellweather Crossing.
2. Restore facilities with salvage using the normal attack button while standing nearby.
3. Spend one banked return opportunity with the normal interact button to prepare a restored facility.
4. Leave the refuge. One active-play expedition begins and one prepared charge from each available facility is consumed into a bounded expedition benefit.
5. Survive at least 90 seconds of durable gameplay time away from the refuge.
6. Return. The expedition closes exactly once, salvage is awarded deterministically and one return preparation is banked.

## Facilities and live effects

- Archive Hearth: one prepared warmth charge reduces the next incoming hit by two damage and can fully absorb a two-point hit.
- Sheltered Coldframe: one prepared recovery charge restores up to eight player health and six companion health on departure.
- Salvage Workbench: one prepared repair charge adds two damage to Eli's next successful melee hit.
- Morrow's Corner: one prepared companion-focus charge adds two damage to Morrow's next successful attack.

Prepared charges never grow on wall clock time and never punish the player for staying away.


## Visible refuge progression

The refuge now changes visibly as the existing four facilities are restored. No new durable field is needed: one deterministic presentation tier is derived from the sum of the twelve authored facility levels.

- **Unsettled Refuge**: zero to three total facility levels. The room remains spare and each station reads as an incomplete silhouette.
- **Sheltered Refuge**: four to seven total levels. Warmth, stored tools, hardy growth and Morrow's claimed space begin to make the Archive feel inhabited.
- **Established Refuge**: eight to eleven total levels. Each station carries a fuller silhouette and the shared room gains restrained shelter accents.
- **Archive Haven**: all twelve facility levels. The Hearth gains chimney glow, the Coldframe closes its glass canopy, the Workbench carries its complete tool arrangement and Morrow's Corner becomes a settled den.

This is presentation derived from already validated state, not a second progression database. It adds no daily calendar, maintenance cost, decay or offline growth.

## Capacity-aware planning

The three fixed Hideaway status lines now expose the current refuge tier, salvage and return-bank caps, total restoration, exact next facility cost and exact prepared charge capacity. Upgrade, preparation and failure dialogue uses the same values. A qualifying return reports both actual stored deltas, so a full return bank truthfully reports zero new opportunities just as a full salvage store reports zero new salvage.


## Journey memento shelf

The eastern shelf now reflects existing journey milestones rather than adding another progression currency. Six authored mementos appear from the first safe return, Morrow's well-name discovery, the Missing Hour, the quieted Ash Hunt, the Sentinel's defeat and the completed Archive Haven.

Each memory has Verdant and Ashen reflection copy plus a deterministic shelf symbol. Standing near the shelf shows the current unlocked count, and the normal interact action cycles through available entries in authored order.

Nothing is consumed. Inspection spends no salvage or return opportunity, grants no item or combat effect, and writes no new save flag. Availability is derived from the campaign and stewardship state already protected by existing save validation.

Read [`ARCHIVE_HIDEAWAY_MEMENTOS.md`](ARCHIVE_HIDEAWAY_MEMENTOS.md) for the authored entries, strict condition schema, package boundary and explicit exclusions.

## Hearthside quiet moments

The two cushions beside the Archive Hearth now hold eight optional present-tense scenes with Eli and Morrow. Availability is derived from existing return, facility, story and refuge state, and the normal interact action cycles through available entries in stable authored order.

No time passes. Listening does not alter active-play duration, expedition qualification, salvage, return opportunities, prepared charges, combat state or saves. The runtime cursor is local presentation state and resets when the player returns to the Hideaway.

The nook always begins with **Threshold Breaths**, then grows through the first safe return, restored facilities, the Missing Hour and completed Archive Haven. Verdant and Ashen copy, speaker labels, status text and controls use the strict localisation catalogue and measured fixed-viewport fitting.

Read [`ARCHIVE_HIDEAWAY_QUIET_MOMENTS.md`](ARCHIVE_HIDEAWAY_QUIET_MOMENTS.md) for the authored sequence, condition schema and reward-free, chore-free boundary.

## Truthful return feedback

A return below the 90-second active-play threshold now explains how many active-play seconds were still required. Qualifying returns report only the salvage actually stored, so a player at 98 salvage sees one recovered salvage when the authored 99 cap is reached rather than an overstated theoretical award. Return summaries, facility results, preparation feedback, status text and host-authority notices resolve through the strict localisation catalogue. The two fixed Hideaway status lines use measured font fitting inside their 464-pixel panel budget.

## Transient preparation validation

The warmth guard, repair strike and Morrow-focus counters remain one-use session values, but they are now semantically save-validated as exact integers in the range zero to one. JSON-safe fractional, negative or oversized values fail closed before a profile can be promoted or loaded.

## World and online boundaries

`archive_hideaway` is the fourth authored reference map with Verdant and Ashen identities. Both eras have dedicated presentation and procedural-audio profiles. A sanctuary multiplayer area allows allies but rejects invaders. Durable Hideaway mutations remain host-authoritative; clients can visit but cannot spend salvage or return opportunities.

## Living Morrow routines

Morrow now uses restored refuge spaces through eight optional ambient routines: threshold watch, pack circle, hearth sprawl, Verdant coldframe scent, Ashen cinder-glass watch, workbench listening, blanket curl and Archive Haven sleep. Availability is derived from existing return, facility, era and refuge state. The active cursor and dwell timer are visit-local presentation state; no new save field or unlock list is written.

The routines use active in-session delta only. Normal recovery distance still applies, and player commands always win: hold, seek, recall or any explicit command suspends ambient movement, with a four-second grace window before it can resume. Routines spend nothing, grant nothing and add no feeding, grooming, sleep, maintenance or daily chore loop.

## Persistence

The live bridge stores stewardship and bounded one-use expedition flags inside the existing JSON-safe `session_state` payload. Save validation calls `HideawayStewardship.validate_state()` whenever the semantic stewardship record is present, so malformed or fractional durable counters fail before load promotion. Connection profiles and multiplayer peer state remain outside saves as before.

## Release protection

The primary `scripts/validate.ps1` gate now runs the Hideaway source contract, compile probe, foundation smoke and live runtime smoke. The world model covers four maps, presentation/audio cover eight map-era contexts, multiplayer exposes five authored online areas, and the snapshot transport matrix covers all eight reference map/era states within the existing 1,200-byte wire budget.

## Runtime composition

`presentation_runtime_current.gd` remains the canonical scene root. It inherits `hideaway_runtime.gd`, which in turn inherits `presentation_runtime_base.gd`. This keeps every established root-level combat, save, audio, presentation and editor contract stable while inserting Hideaway stewardship as a composable gameplay layer.
