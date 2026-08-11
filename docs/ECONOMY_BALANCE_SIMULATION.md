# Deterministic Economy Balance Simulation

Epochbound’s content validator proves that currencies, merchants, prices, stock, supply routes and save data are structurally legal. The economy-balance simulation asks a different release question: do those legal records create an obviously broken opening choice, exhausted long-form recovery route or repeatable currency exploit?

The simulation is the tenth permanent Campaign Audit probe. It is deterministic, bounded and read-only. It does not run wall-clock time, random input, combat farming or arbitrary player scripts.

## Simulation horizon

Renewable stock is measured across a fixed 1,800 seconds of active play. For each finite replenishing stock entry, the model uses the authored supply-region interval and `restock_quantity` to calculate how many units can return during that horizon.

This is not offline progression. The calculation exists only to compare authored active-play pacing consistently across releases.

## Opening preparation choices

The model enumerates unconditional merchant stock against each currency’s authored starting balance. A purchase counts only when:

- the merchant and stock entry have no conditions;
- the item and currency resolve;
- finite stock is positive or the entry is unlimited;
- the authored runtime buy price is positive;
- the opening wallet can pay the price;
- the starting inventory is below the item’s stack limit.

For every executable purchase, the model checks whether the player still owns or can afford at least one healing item afterwards. It also records the number of distinct preparation categories represented by recovery, ammunition, equipment and materials.

Warnings:

- `economy.starting_wallet_no_choice`
- `economy.starting_wallet_single_choice`
- `economy.optional_spend_strands_recovery`

These findings do not demand that every upgrade be affordable. They flag an opening wallet that has no meaningful executable decision or an optional purchase that consumes the only visible recovery route.

## Repeatable arbitrage

For every unconditionally buyable item and currency, the model compares the cheapest authored buy price with the highest valid sell price offered by an unconditional merchant using the same currency.

A positive spread is counted as an arbitrage route. It becomes the release-stopping `economy.repeatable_arbitrage` finding only when the buy source is unlimited or replenishing. One-time finite price differences remain metrics because they may be intentional trading rewards and cannot mint currency indefinitely.

The model uses the same buy and sell price functions as the runtime. Merchants that refuse the item, reject its kind, use another currency or require conditions are excluded from the opening-market comparison.

## Recovery and ammunition endurance

The simulation identifies healing consumables and every ammunition item referenced by authored ranged equipment. It then measures sustainable merchant sources:

- unlimited stock;
- finite stock with positive replenishment tied to a valid supply region.

Warnings:

- `economy.recovery_endurance_risk`
- `economy.ammo_endurance_risk`

A warning is emitted only when the corresponding merchant resource exists but every merchant source is finite and non-renewable. Other pickups, quest rewards or encounter drops may still justify the design, but they must be proved through an executable route rather than assumed by the static merchant records.

## Published metrics

Campaign Audit Studio publishes:

- executable opening choices;
- recovery-safe opening choices;
- preparation categories;
- total bounded scenarios;
- economy-balance findings;
- arbitrage and repeatable-arbitrage route counts;
- renewable healing and ammunition units per 30-minute horizon;
- finite non-renewable equipment and key offers.

These values are evidence, not a fun score. A clean report does not prove ideal pacing, emotional reward or player understanding.

## Reference release contract

The built-in `epochbound_demo` campaign must retain:

- four executable opening preparation purchases;
- four recovery-safe choices;
- recovery, material and ammunition categories;
- zero repeatable arbitrage routes;
- twenty renewable healing units per 30-minute active-play horizon;
- eighty renewable ammunition units per 30-minute active-play horizon;
- three finite non-renewable equipment offers;
- zero economy-balance findings.

Any intentional change to these values must update the authored economy, the deterministic regression and the release documentation together.

## Human review still required

The simulation does not model every reward order, player sale, optional branch, encounter drop, repair cost, exchange rate or subjective value judgment. Before release, playtest:

- early purchases in several orders;
- recovery after repeated failed encounters;
- ammunition use with melee fallback;
- merchant access before and after capability gates;
- supply timing under realistic active play;
- whether finite upgrades feel scarce rather than merely unavailable;
- whether prices communicate meaningful choices without forcing one correct answer.

## Automated release gate

The production implementation is protected by `tools/check_economy_balance_contract.py`, the deterministic Godot smoke test, the complete local validation gate and the exact-main schema-2.8 receipt. The contract fails closed if the 30-minute horizon, authored finding identifiers, Campaign Audit integration, compile coverage, human playtest checklist or release evidence drifts.
