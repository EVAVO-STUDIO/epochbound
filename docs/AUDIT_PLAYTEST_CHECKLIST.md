# Campaign Audit Review Checklist

Use this checklist after the automated Audit Studio report and before distributing a campaign package.

## Report integrity

- Run the same audit twice without editing source.
- Confirm both JSON exports are identical.
- Confirm all findings use stable severity, code, context and message fields.
- Confirm the report exposes all ten probes and the progression, merchant-only and affordability metrics.
- Confirm there are no blockers before release.
- Record an owner and rationale for every accepted warning.

## Map reachability

- Start a new journey from the authored start map and era.
- Visit every map that the audit marks reachable.
- Verify gated connections explain what is missing.
- Confirm every destination map has an intentional exit, defeat recovery or irreversible-transition design.
- Verify one-way transitions cannot invalidate active quests or strand required equipment.

## Temporal shift consequences

- Confirm **Temporal maps** reports every map with at least two declared eras.
- For each multi-era map, verify at least one route, threat, information, relationship or resource consequence is reachable in normal play.
- Confirm palette, lighting and landmark styling alone do not satisfy the automated probe.
- Review every `temporal.palette_only` warning and either author a meaningful consequence or remove the unsupported era state.
- Test both directions of each useful shift and confirm the player can understand what changed.
- Verify era-scoped routes preserve recovery anchors, companion recall and a valid return path.
- Verify era-scoped enemies and boss phases remain readable and cannot appear outside their authored era.
- Verify era-specific NPCs, clues, merchants and pickups preserve durable state when the player shifts away and back.

## Capability ordering

- List each capability gate in player encounter order.
- Prove the capability source is obtainable beforehand.
- For every `progression.capability_only_gated_sources` warning, record the earliest valid acquisition route.
- Confirm no merchant, chest, conversation or recipe providing a capability requires that same capability.
- Test shared-slot trade-offs so replacing one tool does not create a hidden softlock.
- Remove or sell optional gear and confirm protected progression routes remain recoverable.
- Reload an older profile and confirm capability reconstruction remains valid.

## Progression item sources

- List each item counted by `progression_item_count` and the quantity required by the first mandatory gate.
- Prove at least one authored source exists before that gate.
- Confirm disconnected interactions, separate conversations and unrelated records use the largest provable demand rather than being summed without evidence.
- For multiple `remove_item` effects in one effect bundle, verify every removal is counted.
- For conversation nodes joined by explicit `next` links, verify sequential removals accumulate.
- For mutually exclusive dialogue choices, verify the audit uses the largest one-branch cost rather than summing impossible choices.
- Confirm a paired `has_item` guard and `remove_item` effect represent one physical cost, not two.
- For recipe-derived items, start with an empty inventory and prove every ingredient can be acquired without using the output.
- Verify finite pickups, rewards and merchant stock satisfy output demand before any recipe ingredients are counted.
- Test partial supply, such as one pickup toward a two-item requirement, and verify only the residual unit expands into recipe ingredients.
- Verify output batch sizes and nested recipes produce the same cumulative ingredient quantities shown by the audit.
- Verify surplus from multi-unit recipe outputs is reused by later progression demand before another batch is counted.
- Confirm a locked recipe with no authored unlock route produces `progression.recipe_never_unlocked` rather than fabricated ingredient requirements.
- Confirm alternative recipes do not hide a dependency cycle.
- Exhaust every finite pickup and merchant stack used by progression and verify the required quantity remains obtainable.
- Confirm each merchant counted as a source has a reachable placed reusable NPC binding.
- Review every `progression.item_only_gated_sources` warning against the intended encounter order.

## Economy and recovery

- Exhaust healing consumables and verify a reasonable recovery source remains.
- Exhaust ranged ammunition and verify melee or merchant recovery remains viable.
- Confirm conditional merchants are not the only solution to the condition that unlocks them.
- Test starting balances against essential purchases.
- Split a required quantity across two bound merchants and confirm their finite stock combines instead of producing `economy.progression_item_not_for_sale`.
- Give the same required item valid stock in two independent currencies and confirm the audit evaluates each wallet separately rather than comparing nominal currency numbers.
- Verify the reported affordable-unit capacity matches the cheapest valid stock order inside each currency.
- Confirm a complete stock route that exceeds the starting wallets produces an affordability warning rather than a not-for-sale blocker.
- Create two individually affordable, merchant-only progression requirements in the same currency whose aggregate review total exceeds the starting balance.
- Confirm the report emits `economy.cumulative_progression_purchase_unaffordable` with that currency as context.
- Confirm the warning explicitly distinguishes its aggregate review envelope from proof that every requirement belongs to one mandatory route.
- Document which requirements truly co-occur and which live on disconnected or optional branches.
- Confirm multi-currency alternatives and capability-equipment choices are not added to the aggregate total without proof that one exact route is mandatory.
- For every affordability warning, document the earliest guaranteed currency source and its minimum value.
- Spend currency on optional goods before the required purchase and confirm the campaign still offers a recovery route.
- Confirm **Economy choices** matches the number of purchases executable from the starting inventory and wallets.
- Confirm every optional opening choice counted as recovery-safe leaves a healing item owned or still affordable.
- Review the preparation-category count and verify the opening economy offers intentional recovery, ammunition, equipment or material decisions.
- Exhaust renewable healing and ammunition stock, advance active play through the thirty-minute simulation horizon and compare actual replenishment with the report.
- Compare the cheapest unconditional buy price and highest same-currency sell price for every renewable item.
- Confirm no unlimited or replenishing stock produces `economy.repeatable_arbitrage`.
- Review `economy.recovery_endurance_risk` and `economy.ammo_endurance_risk` against non-merchant drops or rewards with an executable proof.
- Verify failed purchases and sales remain transactional.

## Quest startability

- Start every non-automatic quest through its intended conversation or trigger.
- Confirm the trigger remains reachable in every required era.
- Complete and reload each quest stage.
- Confirm optional quests do not block mandatory travel or campaign completion.
- Verify abandoned or superseded branches do not leave an objective permanently active.

## Save safety

- Confirm at least one save path is always available outside intentionally unresolved combat or cinematics.
- Test autosave after travel and durable progress.
- Test manual slots before and after gated transitions.
- Force a corrupt primary slot and verify backup recovery.
- Load profiles created before the latest campaign release metadata and confirm safe defaults.

## Companion and combat recovery

- Recall the companion from every gated route and arena boundary.
- Confirm recovery anchors keep the companion on traversable ground.
- Leave and re-enter every cleared encounter.
- Defeat bosses, watch and skip conclusions, then verify exits and saving unlock.
- Confirm large attacks cannot skip required phases or durable outcomes.

## Packaging handoff

- Export the campaign twice and compare package SHA-256 values.
- Inspect the manifest before installation.
- Install into a clean user campaign directory.
- Confirm the installed campaign produces the same ten-probe audit report as its source.
- Preserve the audit JSON beside the distributed package.
