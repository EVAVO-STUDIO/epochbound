# Campaign Audit Review Checklist

Use this checklist after the automated Audit Studio report and before distributing a campaign package.

## Report integrity

- Run the same audit twice without editing source.
- Confirm both JSON exports are identical.
- Confirm all findings use stable severity, code, context and message fields.
- Confirm the report exposes all eight probes and the progression, merchant-only and affordability metrics.
- Confirm there are no blockers before release.
- Record an owner and rationale for every accepted warning.

## Map reachability

- Start a new journey from the authored start map and era.
- Visit every map that the audit marks reachable.
- Verify gated connections explain what is missing.
- Confirm every destination map has an intentional exit, defeat recovery or irreversible-transition design.
- Verify one-way transitions cannot invalidate active quests or strand required equipment.

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
- For recipe-derived items, start with an empty inventory and prove every ingredient can be acquired without using the output.
- Confirm alternative recipes do not hide a dependency cycle.
- Exhaust every finite pickup and merchant stack used by progression and verify the required quantity remains obtainable.
- Confirm each merchant counted as a source has a reachable placed reusable NPC binding.
- Review every `progression.item_only_gated_sources` warning against the intended encounter order.

## Economy and recovery

- Exhaust healing consumables and verify a reasonable recovery source remains.
- Exhaust ranged ammunition and verify melee or merchant recovery remains viable.
- Confirm conditional merchants are not the only solution to the condition that unlocks them.
- Test starting balances against essential purchases.
- For every affordability warning, document the earliest guaranteed currency source and its minimum value.
- Spend currency on optional goods before the required purchase and confirm the campaign still offers a recovery route.
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
- Confirm the installed campaign produces the same eight-probe audit report as its source.
- Preserve the audit JSON beside the distributed package.
