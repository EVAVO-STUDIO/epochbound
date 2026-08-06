# Campaign Audit Studio

Campaign Audit Studio performs deterministic production-readiness analysis after the normal content validator has confirmed that a campaign is structurally valid. Validation answers whether records are legal. Audit probes answer whether the legal records form a campaign that is likely to remain reachable, recoverable and maintainable during unattended play and automated releases.

## Audit contract

Every finding contains:

- `severity`: `blocker`, `warning` or `info`;
- `code`: a stable machine-readable identifier;
- `context`: the relevant map, capability, item, quest, merchant, currency or policy ID;
- `message`: a player- and author-facing explanation.

Reports are sorted deterministically by severity, code, context and message. Identical campaign input must produce byte-equivalent JSON output.

Epochbound's built-in reference campaign has a stricter release contract: complete content validation and all eight audit probes must publish zero errors, blockers and warnings. The normal audit API still distinguishes blockers from review warnings for external campaigns.

The report also publishes bounded metrics for maps, capabilities, quests, restorative sources, progression items, progression capabilities, source risks, merchant-only progression and affordability risks. These counts are evidence and triage aids, not balance scores.

## Eight permanent probes

### 1. Map reachability

The audit builds a directed graph from every declared `target_map`. It starts at `campaign.start_map` and reports every map that cannot be reached structurally. Capability and story gates do not remove an edge from this graph; they are analysed separately.

Blockers:

- `map.missing_start`
- `map.unreachable`

### 2. Return-route safety

Every non-start map must contain at least one exit. The audit also checks whether a directed path can return to the start map and whether at least one exit is not capability- or condition-gated.

Findings:

- `travel.no_exit` — blocker
- `travel.no_return_path` — warning
- `travel.all_exits_gated` — warning

One-way story transitions remain possible, but authors must review the warning and prove that save, defeat and recovery flows cannot strand the player.

### 3. Capability-definition coverage

Journey-critical capabilities are collected from map connections, story conditions, merchant conditions and any map interaction explicitly marked `progression_required: true`. Ordinary map interactions remain optional exploration surfaces. Their capability IDs are retained in the `optional_capability_count` metric but do not become softlock requirements merely because they reveal lore or an optional reward.

All other map records continue to be scanned conservatively. Definitions are collected from campaign base capabilities and equipment records. The validator requires `progression_required`, when present, to be a strict boolean.

Findings:

- `capability.no_source` — blocker
- `capability.late_source` — warning

A late-source warning means a journey-critical capability is defined but is not present in the starting loadout. Probe 7 then checks whether the granting equipment itself has a usable acquisition route. Optional interaction gates remain visible for review without producing a false mandatory-progression warning.

### 4. Economy and recovery

The audit checks for an immediately usable healing source and verifies that every authored ranged-ammunition type has a starting stack or an unconditional merchant source.

Findings:

- `economy.no_restorative_source` — blocker
- `economy.no_ammo_recovery` — warning

Conditional merchants are not counted as immediate recovery sources because their availability may depend on the resource or capability the player has exhausted.

### 5. Quest startability

Every quest must be a starting quest, use `auto_start`, or be referenced by a `start_quest` effect in authored story data.

Finding:

- `quest.no_start_path` — warning

This is a conservative static probe. Dynamic external triggers may be valid, but they require a documented test and an explicit waiver.

### 6. Save-path safety

The audit reviews campaign save policy independently of profile-schema validation.

Findings:

- `save.no_path` — blocker
- `save.autosave_never_requested` — warning
- `save.manual_in_combat` — warning

### 7. Progression-source and softlock safety

The audit separates reusable possession requirements from consumptive item costs. It accumulates quantities only where campaign data proves sequence: multiple effects in one effect bundle or conversation nodes connected through explicit `next` links. Disconnected interactions, separate conversations, unrelated quests, maps and economy records retain the largest provable demand instead of being added as though every optional path were mandatory. Mutually exclusive dialogue choices use the largest one-branch requirement.

When a required item has one unambiguous recipe, the audit traces only the residual quantity not already covered by usable non-recipe sources. Sources are built from:

- starting inventory and starting equipment, with an equipped item already present in inventory counted only once;
- story and map item grants;
- the complete definitions behind placed reusable objects, including pickup grants, reward items and boss defeat effects;
- non-circular recipes that are available by default, listed in starting recipes or have an authored unlock route;
- merchant stock attached to a placed reusable NPC definition.

Required capabilities are then connected to the equipment items that grant them and to those items’ acquisition routes.

Blockers:

- `progression.item_no_source`
- `progression.item_self_lock`
- `progression.insufficient_finite_supply`
- `progression.merchant_source_unbound`
- `progression.recipe_cycle`
- `progression.recipe_never_unlocked`
- `progression.capability_item_no_source`
- `progression.capability_self_lock`

Warnings:

- `progression.item_only_gated_sources`
- `progression.capability_only_gated_sources`

A blocker is reserved for evidence the static records can prove: no route, a circular recipe, a required recipe with no default, starting or authored unlock, an exact self-gate, an unbound merchant definition, or authored finite supply below an explicit required quantity. A source that is merely conditional remains a warning because executable play may prove a valid ordering.

Recipe outputs are treated as repeatable for finite-supply accounting only after cycle detection and recipe-unlock verification. Usable pickups, rewards and bound merchant stock satisfy required output quantities before ingredient expansion. Partial direct supply expands only the residual craft quantity, and surplus from multi-unit recipe batches remains available to later progression demand. This prevents a legal crafting loop from being mistaken for a one-time pickup while rejecting recipes that require their own output directly or indirectly, or that can never become available through campaign data.

### 8. Merchant-only progression affordability

The audit identifies progression items and capability-granting equipment whose usable sources are all merchants. It uses the same authored unit-price calculation as the runtime.

A required quantity may be fulfilled by several bound merchants rather than one merchant carrying the complete stack. Stock is combined deterministically in ascending unit-price order. Unlimited entries remain bounded by the required quantity during planning, so cost calculations cannot overflow or fabricate extra demand.

Currencies remain independent. The probe never compares the nominal number of one currency with another. For each currency it calculates:

- total valid stock available for the requirement;
- the cheapest complete same-currency purchase cost where one exists;
- the exact number of units that currency’s starting wallet can fund.

Those independently affordable quantities may then combine across currencies for the same item. This supports campaigns where, for example, one required unit is bought with Archive Chits and another with a separate authored currency.

Blockers:

- `economy.progression_item_not_for_sale`
- `economy.capability_item_not_for_sale`

Warnings:

- `economy.progression_purchase_unaffordable`
- `economy.capability_purchase_unaffordable`
- `economy.cumulative_progression_purchase_unaffordable`

The first two warnings are emitted when valid merchant stock can provide the requirement but the starting wallets cannot fund the complete quantity. The message reports affordable unit capacity per currency instead of choosing a misleading numerically smallest currency.

The cumulative warning is an aggregate review envelope, not proof of one mandatory route or a minimum journey cost. It considers progression-item purchases only when:

- every usable source is a merchant;
- all valid routes use one currency;
- the item is individually affordable from that currency’s starting balance;
- at least two such statically identified requirements share the currency.

If their minimum complete costs together exceed the starting balance, the report asks authors to document which requirements actually co-occur and where cumulative earnings are available. Disconnected or optional campaign branches may legitimately explain the total. Multi-currency alternatives and capability-item overlaps are excluded because the static records do not prove which option the player must choose.

A price or aggregate review total above the starting balance is a warning, not a blocker. Enemy rewards, quest rewards and player sales may provide an intentional earning route. Authors must prove that route occurs before the relevant purchase becomes mandatory and cannot itself depend on that purchase.

The probe does not assume all optional upgrades must be affordable at campaign start. It evaluates only items and capabilities already identified as progression requirements.

## Editor workflow

1. Open the **Audit** main-screen tab.
2. Select a built-in or installed campaign.
3. Select **Run Audit**.
4. Review the two-line metrics summary, including progression and affordability counts.
5. Resolve every blocker.
6. Review and either resolve or document every warning.
7. Export the deterministic JSON report into `user://audit_reports`.
8. Attach the report to the release record or automated maintenance run.

## Automation use

Maintenance bots should treat:

- blockers as release-stopping failures;
- warnings as required review items;
- stable finding codes as the durable automation interface;
- finding messages as human-readable context, not parsing keys;
- metric counts as bounded triage data, not permission to rewrite campaign design;
- the built-in reference campaign's zero-warning gate as a release invariant rather than a reason to weaken audit rules.

Bots must never silence a warning by deleting content, loosening a gate, making every stock entry unlimited, lowering prices or granting items without proving the intended player journey remains intact.

## Scope boundaries

Campaign Audit Studio does not simulate every possible player action. It does not replace:

- the complete content validator;
- executable smoke tests;
- controller and accessibility review;
- economic balance playtests;
- long-form save/load soak tests;
- human assessment of story quality and encounter fairness.

The source and affordability probes are deliberately conservative. They do not model arbitrary sales, every reward order, exchange rates, optional spending, all recipe alternatives, every capability-equipment choice or dynamic scripts outside the campaign contract. They provide deterministic early warnings that make those later reviews more focused and safer to automate.
