# Campaign Audit Studio

Campaign Audit Studio performs deterministic production-readiness analysis after the normal content validator has confirmed that a campaign is structurally valid. Validation answers whether records are legal. Audit probes answer whether the legal records form a campaign that is likely to remain reachable, recoverable and maintainable during unattended play and automated releases.

## Audit contract

Every finding contains:

- `severity`: `blocker`, `warning` or `info`;
- `code`: a stable machine-readable identifier;
- `context`: the relevant map, capability, quest or policy ID;
- `message`: a player- and author-facing explanation.

Reports are sorted deterministically by severity, code, context and message. Identical campaign input must produce byte-equivalent JSON output.

## Six permanent probes

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

### 3. Capability-source coverage

Required capabilities are collected recursively from maps, story conditions and merchant conditions. Sources are collected from campaign base capabilities and equipment definitions.

Findings:

- `capability.no_source` — blocker
- `capability.late_source` — warning

A late-source warning is expected for optional or progression equipment. Authors must still prove that the item can be acquired before the corresponding gate becomes mandatory.

### 4. Economy and recovery

The audit checks for an immediately usable healing source and verifies that every authored ranged-ammunition type has a starting stack or an unconditional merchant source.

Findings:

- `economy.no_restorative_source` — blocker
- `economy.no_ammo_recovery` — warning

Conditional merchants are not counted as immediate recovery sources because their availability may depend on the very resource or capability the player has exhausted.

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

## Editor workflow

1. Open the **Audit** main-screen tab.
2. Select a built-in or installed campaign.
3. Select **Run Audit**.
4. Resolve every blocker.
5. Review and either resolve or document every warning.
6. Export the deterministic JSON report into `user://audit_reports`.
7. Attach the report to the release record or automated maintenance run.

## Automation use

Maintenance bots should treat:

- blockers as release-stopping failures;
- warnings as required review items;
- stable finding codes as the durable automation interface;
- finding messages as human-readable context, not parsing keys.

Bots must never silence a warning by deleting content, loosening a gate or granting items without proving the intended player journey remains intact.

## Scope boundaries

Campaign Audit Studio does not simulate every possible player action. It does not replace:

- the complete content validator;
- executable smoke tests;
- controller and accessibility review;
- economic balance playtests;
- long-form save/load soak tests;
- human assessment of story quality and encounter fairness.

It provides a deterministic early-warning layer that makes those later reviews more focused and safer to automate.
