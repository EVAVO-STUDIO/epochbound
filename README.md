# Epochbound

Epochbound is an original Godot 4.6.2 action RPG and campaign-authoring platform designed with the pacing, readability, tactile movement and authored surprise of a premium lost 1990s console adventure.

It learns from the design strengths of classic action RPGs and timeline-spanning adventures while using an entirely original world, cast, narrative, terminology, artwork and audio.

## Current playable flow

The repository now provides:

1. EVAVO Studio splash and animated title flow
2. Built-in and installed custom campaign browser
3. Validated campaign loading and campaign-defined prologues
4. Variable-size scrolling exploration maps
5. Responsive eight-direction movement with authored collision
6. A campaign-defined animal companion with commands, navigation, recovery, discovery and combat assistance
7. Contextual interactions and era-specific dialogue
8. Shifting between mechanically different versions of the same location
9. Named map entries and validated cross-map connections
10. Reusable props, NPCs, enemies and pickups authored outside engine code
11. Solid placed objects and persistent session state
12. Player action attacks, telegraphed enemy attacks, damage, stagger and knockback
13. Authored encounter zones with activation, patrol, pursuit, leash return and clearing
14. Follow, Stay, Seek, Guard and dedicated Recall companion behaviour
15. Era-scoped scent, clue, trail, warning and resource discoveries
16. Data-driven items, stack limits, starting loadouts and persistent session inventory
17. Consumable healing, quick-use items, recipe discovery and transactional crafting
18. Pickup and companion-discovery item rewards protected from duplication
19. Branching conversations with typed choices, conditions and effects
20. Multi-stage quests driven by real inventory, map, era, world and encounter state
21. Active-objective tracking and a keyboard/controller Journal
22. Versioned save profiles with deterministic checksums, migrations and backup recovery
23. Continue, autosave and three campaign-authored manual save slots
24. Exact durable restoration across maps, eras, inventory, quests and world outcomes
25. Campaign-authored equipment slots, starting loadouts and immediate derived stats
26. Capability-gated travel, interactions and story conditions with blocked feedback
27. A third Museum Underworks map with flashlight, hook and Archivist Lens trade-offs
28. Bidirectional travel between Bellweather Crossing, Clockwood Edge and the Museum Underworks
29. Campaign-authored currencies, finite merchant stock and durable wallet state
30. Atomic buy and sell transactions with stack, stock, balance and equipped-item protection
31. Two conditionally available reference merchants bound to reusable NPC definitions
32. Inventory-backed ammunition, explicit reloads and deterministic moving projectiles
33. Player and enemy ranged attacks that respect map collision, cover and existing combat feedback
34. Schema-4 loaded-magazine persistence and a ranged Underworks encounter
35. Pause, resume and safe transition flow

The runtime currently uses Godot drawing primitives so it remains executable before final artwork exists. These placeholders establish composition, scale, timing, camera, traversal, encounter, companion, inventory, story, save-state, loadout, capability-gating, merchant, economy, ammunition, projectile, reload and interaction contracts for the future pixel-art pipeline.

## Campaign Studio

The **Campaign** main-screen editor can:

- create campaigns and world-builder-ready starter maps;
- create and browse additional maps;
- preview every authored era;
- paint terrain with era-specific or shared brushes;
- paint and erase collision cells;
- paint companion navigation cells;
- zoom and pan around maps of different sizes;
- toggle collision, navigation and marker overlays;
- place player and companion spawns;
- add and edit interactions and era-specific dialogue;
- add named entry points and companion arrival positions;
- add recovery anchors that prevent companion softlocks;
- add validated interact or touch connections between maps;
- undo and redo map edits;
- validate the complete campaign before play.

### Campaign canvas controls

| Action | Input |
| --- | --- |
| Paint or place | Left mouse button |
| Erase current scoped cell | Right mouse button |
| Pan canvas | Middle mouse drag |
| Zoom canvas | Mouse wheel |

## Encounter Studio

The **Encounter** main-screen editor works on the same campaign and map records. It can:

- create reusable object types;
- define props, NPCs, enemies and pickups;
- configure blockout appearance, solidity and interaction radii;
- author NPC and prop dialogue without flattening era-specific variants;
- configure enemy health, movement, awareness, attack range, damage, cooldown and rewards;
- configure pickup values and messages;
- place instances visually on any map;
- restrict placements to selected eras;
- set facing and stable persistent-state keys;
- select, inspect, move, replace and delete placements;
- block unsafe object deletion while placements still reference it;
- undo and redo map-placement edits;
- validate every catalog and placement before saving.

Campaign object types are stored in catalog files such as `objects/core.json`. Maps reference them through `object_placements`, so one authored type can be reused across the entire campaign without copying its rules.

## Combat Director

The **Combat** main-screen editor turns placed enemies into authored encounters rather than independent chase agents. It can:

- place and select encounter zones visually;
- set combat, activation and leash radii;
- assign stable enemy placements to a zone;
- scope zones to particular eras;
- author persistent encounter-clear keys;
- tune enemy patrol radius and explicit leash overrides;
- tune attack windup, target memory and return speed;
- tune stagger, knockback and contact response;
- undo and redo zone changes;
- validate zones, enemy assignments and behaviour values before play.

The runtime supports deterministic idle patrol, zone activation, pursuit, visible attack windup, stagger, directional knockback and return-to-spawn behaviour. Enemies stop pursuing outside their authored leash, while cleared encounters publish stable state keys for quest progression and later save-profile persistence.

Reference proofs include the Ashen-only **East Ash Hunt** in Bellweather Crossing and the two-enemy **Clockwood Hound Pair** in Clockwood Edge.

## Companion Studio

The **Companion** main-screen editor turns the animal companion into an authored exploration and reliability system. It can:

- configure the companion name and maximum health;
- choose the available command cycle;
- tune follow, guard and recovery distances;
- tune seek radius, seek speed and Guard assistance range;
- place scent, clue, trail, resource and warning cues visually;
- author discovery messages and one-time rewards;
- hide cues until the companion finds them;
- scope discoveries to selected eras;
- assign stable persistent state keys;
- select, inspect, move and delete cues;
- undo and redo cue edits;
- validate the complete companion profile and discovery layer.

The player can cycle **Follow**, **Stay**, **Seek** and **Guard**, while **Recall** remains a dedicated safety action. Seek selects only the nearest unresolved cue available in the current era and returns to Follow after discovery. Stay suppresses automatic combat movement, Guard keeps the companion closer and extends assistance range, and Recall resolves an authored safe position near the player.

The reference campaign includes four companion discoveries across Bellweather Crossing and Clockwood Edge, with different clues in the Verdant and Ashen eras.

## Item Forge

The **Items** main-screen editor authors the inventory and crafting layer. It can:

- create consumable, material, key, equipment and ammunition item definitions;
- author player-facing names and descriptions;
- configure stack limits and reserved economy values;
- configure supported active effects such as healing;
- create recipes with validated ingredients and outputs;
- choose recipes unlocked by default;
- author campaign starting inventory quantities;
- choose campaign starting recipes;
- prevent deletion while starts, recipes, pickups, companion discoveries or merchant records reference a definition;
- validate item catalogs, recipe catalogs, grants and unlocks across the complete campaign.

The runtime provides a paused **Field Satchel** with Items, Recipes and Equipment tabs, deterministic item ordering, direct consumable use, quick-use healing, ingredient checks, output-capacity checks, atomic crafting and owned-gear selection. Inventory and equipped item IDs persist through the durable profile contract.

The reference campaign proves the complete loop:

- Eli starts with a Museum Tonic and Brass Filings;
- Morrow discovers additional brass and Ashen Resin;
- clock-shard pickups grant Clockglass Fragments;
- the Ember Salve recipe converts discovered materials into a stronger restorative;
- a Clockwood clue teaches the Clockglass Lens recipe;
- two fragments and remaining brass craft the Clockglass Lens key item.

## Story Studio

The **Story** main-screen editor authors branching conversations and multi-stage quests. It can:

- create conversation graphs with stable IDs;
- add line, choice and end nodes;
- preview authored branches through Godot `GraphEdit` nodes and connections;
- preserve draggable graph layout in source-controlled `editor_position` records;
- author plain or era-keyed dialogue text;
- author typed conditions against inventory, durable world state, quest status, quest stage, map, era, clock-shard totals, active capabilities and currency balances;
- author typed effects that start or advance quests, set state, grant or remove items, unlock recipes, grant clock shards and change durable currency balances;
- create quests with objectives, deterministic completion conditions and rewards;
- block unsafe deletion of referenced conversations, nodes, quests and stages;
- roll back a story save that would invalidate the campaign;
- validate graph reachability and every cross-system reference.

The runtime presents filtered dialogue choices, applies effects in authored order, advances quest stages after meaningful world-state changes and prevents completed quest rewards from duplicating. Active objectives appear during play, while the **Journal** exposes Active and Completed quest tabs without introducing a second quest database.

The reference campaign proves two arcs:

- **The Missing Hour** begins through the Lost Archivist, consumes Morrow’s well discovery, requires crafting the Clockglass Lens, returns the lens through a gated response and grants one-time rewards;
- **Quiet the Ash Hunt** begins in Ashen dialogue and completes from Combat Director’s stable `east_ash_hunt` clear-state key.

## Save & State Studio

The **State** main-screen editor inspects and manages versioned player profiles without writing them into campaign source. It can:

- discover autosave and manual slots for each campaign;
- show schema, checksum, timestamp, reason, map, era and play time;
- inspect persisted inventory, equipment, wallets, merchant stock, learned recipes, quest stages and durable world-state keys;
- validate a profile against the currently installed campaign definitions;
- rewrite supported legacy profiles through explicit migrations;
- recover a previous complete checkpoint from a rotated backup;
- delete a slot together with its backup and abandoned temporary file;
- expose canonical read-only JSON for support and review.

The runtime adds a title-screen **Continue** flow, one managed autosave slot and campaign-authored manual slots. Writes use temporary files and promotion rather than overwriting the only valid copy. Map, era, positions, health, inventory, equipment, wallets, merchant stock, recipes, discoveries, defeated enemies, cleared encounters, quest progress, clock shards, companion hold state and play time restore from one validated profile. Transient dialogue, attack windups, knockback and menu state reset safely.

The reference campaign exposes three manual slots, autosaves after safe travel or meaningful durable progress, and blocks manual saving during active directed combat.

## Loadout Studio

The **Loadout** main-screen editor authors equipment, derived stats and semantic gameplay capabilities while keeping ownership in Item Forge inventory. It can:

- create equipment items in the primary item catalogue;
- define campaign-specific equipment slots and player-facing slot names;
- configure attack, defence, maximum-health and movement-speed bonuses;
- create capability definitions with stable IDs and production descriptions;
- assign capabilities to equipment or grant them as campaign base abilities;
- configure starting equipment while enforcing starting-inventory ownership;
- add capability requirements and blocked dialogue to map connections and interactions;
- block deletion while gear, gates, story conditions or starting loadouts still reference a definition;
- roll back authoring changes that would invalidate the complete campaign.

The Field Satchel Equipment tab cycles each slot through the empty state and every compatible owned item. Equipping gear immediately rebuilds player attack, defence, maximum health, movement speed and active capabilities. The same capability set drives map gates and Story Studio's `has_capability` condition.

The reference loadout includes the Brass Hook, Museum Field Coat and Museum Flashlight. Completing **The Missing Hour** grants the Archivist Lens. The flashlight and lens share the Tool slot: one permits entry into the dark Museum Underworks, while the other reveals its sealed catalogue. This creates an explicit spatial and narrative trade-off rather than an always-active collection of passive tools.

Save schema 4 persists equipped item IDs, wallets, merchant stock and loaded ranged magazines. Schema-1 profiles migrate with empty equipment, while schema-2 profiles retain equipment and initialise the authored economy once; every restored slot, balance and stock record validates against current campaign definitions.


## Merchant & Economy Studio

The **Trade** main-screen editor authors currencies, merchant stock, prices, availability and reusable NPC trade bindings while keeping every traded good inside Item Forge inventory. It can:

- create stable campaign currency definitions;
- configure starting and maximum wallet balances;
- create merchants with greetings, farewells and transaction currencies;
- author buy and sell multipliers or item-specific price overrides;
- define finite or unlimited stock;
- condition merchants and individual stock through Story Studio records;
- choose accepted item kinds and explicit refusal rules;
- decide whether sold player goods become merchant stock;
- bind reusable NPC definitions to merchant contracts;
- prevent deletion while stock, refusal rules, story records or NPC bindings still reference a definition;
- roll back authoring changes that would invalidate the complete campaign.

Interacting with a merchant opens a paused Buy and Sell overlay. Purchases check availability, stock, stack capacity and the complete wallet cost before mutation. Sales reject equipped or refused items and confirm that the wallet can receive the complete payment before removing inventory. Any failed transaction leaves wallet, inventory and stock unchanged.

The reference campaign uses **Archive Chits** and includes **Bellweather Provisions** plus the capability-gated **Underworks Exchange**. Quiet the Ash Hunt grants currency through the same Story Studio effect contract. Save schema 3 restores exact wallet balances, finite stock and dynamically resold goods, while State Studio exposes dedicated Wallet and Merchant Stock inspectors.

## Arsenal Studio

The **Arsenal** main-screen editor authors ranged weapons, ammunition, reload timing, projectile movement and reusable enemy projectile profiles while preserving Item Forge ownership, Loadout Studio equipment and Combat Director encounter direction. It can:

- create ammunition items with stack, value, damage, knockback and projectile-colour records;
- create ranged Weapon-slot equipment that references stable ammunition IDs;
- configure magazine size, damage, speed, range, radius, cooldown, reload, knockback and muzzle offset;
- enable and tune projectile attacks on reusable enemy definitions;
- block ammunition deletion while a weapon still references it;
- validate weapon, ammunition, enemy and loaded-magazine records before play.

The active attack action fires a moving projectile when ranged equipment is selected and retains the existing melee attack when the Brass Hook or another close-range weapon is equipped. Reload transfers reserve Item Forge ammunition only when its authored interval completes. Switching weapons cancels reload without consuming reserve rounds. Fast projectiles use swept collision against map geometry, solid placed objects and the first valid target.

The reference Arsenal includes **Archive Bolts**, the four-round **Clockglass Dartcaster**, and the Ashen-only **Underworks Sentinel**. Bellweather Provisions stocks reserve bolts, while Underworks Exchange carries one Dartcaster. Enemy shots use the existing Combat Director windup but apply damage only after the projectile reaches Eli or Morrow.

Save schema 4 stores exact loaded rounds by stable weapon ID. Schema-3 profiles retain their previous durable state and migrate with empty magazines rather than guessing how reserve ammunition had been distributed. State Studio exposes a dedicated Loaded Ammo inspector.


## Content locations

Source campaigns live under `res://campaigns`. Installed player campaigns are discovered under `user://campaigns`.

Read:

- [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md) for the map editor workflow;
- [`docs/WORLD_BUILDER.md`](docs/WORLD_BUILDER.md) for map-production and quality rules;
- [`docs/ENCOUNTER_STUDIO.md`](docs/ENCOUNTER_STUDIO.md) for reusable objects and placement authoring;
- [`docs/COMBAT_DIRECTOR.md`](docs/COMBAT_DIRECTOR.md) for encounter zones, behaviour direction and combat-quality gates;
- [`docs/COMPANION_STUDIO.md`](docs/COMPANION_STUDIO.md) for commands, scent cues, recovery and companion-quality gates;
- [`docs/ITEM_FORGE.md`](docs/ITEM_FORGE.md) for item catalogs, inventory, crafting, rewards and item-quality gates;
- [`docs/STORY_STUDIO.md`](docs/STORY_STUDIO.md) for conversation graphs, typed conditions, quest stages, rewards and story-quality gates;
- [`docs/SAVE_STATE_STUDIO.md`](docs/SAVE_STATE_STUDIO.md) for save profiles, migration, backup recovery and durable-state quality gates;
- [`docs/LOADOUT_STUDIO.md`](docs/LOADOUT_STUDIO.md) for equipment slots, derived stats, capabilities, gates and loadout-quality rules;
- [`docs/MERCHANT_ECONOMY_STUDIO.md`](docs/MERCHANT_ECONOMY_STUDIO.md) for currencies, shops, pricing, stock, transactions and economy-quality rules;
- [`docs/ECONOMY_PLAYTEST_CHECKLIST.md`](docs/ECONOMY_PLAYTEST_CHECKLIST.md) for the complete manual merchant and economy review;
- [`docs/ARSENAL_STUDIO.md`](docs/ARSENAL_STUDIO.md) for ammunition, ranged weapons, reloads, projectiles and ranged-combat quality rules;
- [`docs/ARSENAL_PLAYTEST_CHECKLIST.md`](docs/ARSENAL_PLAYTEST_CHECKLIST.md) for the complete manual Arsenal review;
- [`docs/OBJECT_FORMAT.md`](docs/OBJECT_FORMAT.md) for the reusable object and placement contract;
- [`docs/CAMPAIGN_FORMAT.md`](docs/CAMPAIGN_FORMAT.md) for the campaign and world-map contract.

## Run

Open `project.godot` in Godot 4.6.2 and press **F6** or **F5**.

### Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | WASD or arrow keys | D-pad or left stick |
| Attack or fire equipped weapon | Space or C | East face button |
| Reload ranged weapon | G | Right trigger |
| Confirm, interact or use entrance | E or Z | South face button |
| Shift era | Q or X | West face button |
| Cycle companion command | R | North face button |
| Recall companion | F | Left stick click |
| Open or close Field Satchel | I | Back / View button |
| Quick-use restorative | V | Right shoulder button |
| Open or close Journal | J | Right stick click |
| Open or close Save Profiles | K | Left stick click |
| Back, pause or skip | Escape | Start |

Inside the Field Satchel, use Left and Right to change Items, Recipes or Equipment tabs, Up and Down to select, and E, Z, Space or C to use an item, craft a recipe or cycle compatible owned gear in the selected slot.

Inside the Journal, use Left and Right to change Active or Completed tabs and Up or Down to select a quest.

Inside Save Profiles, use Left and Right to change Save or Load mode, Up and Down to select a slot, and E, Z, Space or C to confirm. Autosave is managed by the campaign and cannot be overwritten manually.

Inside a merchant, use Left and Right to change Buy or Sell, Up and Down to select an item, E, Z, Space or C to complete one transaction, and Escape or I to close trade.

## Validate

From Windows PowerShell:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

The validation gate performs:

1. direct loading and compilation of the runtime, critical resources and all ten editor plugins;
2. headless project import with logged parser and plugin errors treated as failures;
3. complete campaign, map, object, placement, encounter-zone, companion, item, recipe, conversation, quest, save-policy, equipment, capability, gate, currency, merchant, stock and transaction validation;
4. executable terrain, collision, navigation, recovery and cross-map smoke tests;
5. executable object-catalog, placement, persistence and base-combat smoke tests;
6. executable zone activation, windup, damage, stagger, leash return and clear-state smoke tests;
7. executable companion command, Stay, Seek, discovery, reward-idempotence, Guard and Recall smoke tests;
8. executable item catalog, stack limit, pickup reward, companion reward, recipe unlock, crafting, healing and duplicate-protection smoke tests;
9. executable branching dialogue, item-gated objectives, world-state objectives, quest rewards and Journal smoke tests;
10. executable Story Studio graph and editor-state smoke tests;
11. malformed conversation, condition, effect and quest-stage rejection tests;
12. deterministic save capture, checksum, atomic write and exact runtime-restoration tests;
13. legacy migration, schema-1 equipment migration, schema-2 economy migration, future-schema rejection, corruption detection and backup-recovery tests;
14. executable Save & State Studio slot, equipment and inspector tests;
15. executable loadout stats, slot cycling, capability-gated travel, interaction and story-condition tests;
16. executable Loadout Studio equipment, capability, campaign-loadout and gate-editor tests;
17. malformed equipment slot, stat, capability, gate and saved-ownership rejection tests;
18. executable merchant buy, sell, rollback, gated availability, story-currency and exact economy-restoration tests;
19. executable Merchant & Economy Studio currency, merchant, stock, binding and source-parser tests;
20. malformed currency, merchant, price, stock and saved-economy rejection tests;
21. executable ranged firing, reload completion, cancellation, projectile collision, enemy shots and exact loaded-magazine restoration tests;
22. executable Arsenal Studio weapon, ammunition and enemy-profile editor tests;
23. malformed ammunition, ranged weapon, enemy projectile and saved-magazine rejection tests.

## Design pillars

- A loyal animal companion who is useful in exploration, combat and story
- Multiple versions of places whose changes matter mechanically
- Fast, readable real-time action combat without input clutter
- Dense environmental storytelling, puzzles, secrets and optional discoveries
- Cinematic sequences that respect player control and can be skipped
- Distinct regional systems instead of repeated content with new colours
- Strong authored pacing supported by data-driven production tools
- Authentic low-resolution presentation with modern accessibility and reliability
- Campaign creation that remains portable, inspectable and safe to validate
- Level design that treats collision, companion routes, entrances and recovery as one authored system
- Encounters built from reusable definitions, stable map instances and explicit spatial direction
- Damage that follows readable timing and feedback instead of unexplained contact
- Companion behaviour that communicates relationship and information rather than merely following the player
- Items and recipes that connect exploration, combat and progression through one inspectable campaign contract
- Conversations and quests that consume the same world, item, encounter and companion outcomes instead of parallel state
- Save profiles that serialise those same stable IDs and durable outcomes instead of the live scene tree
- Equipment choices that alter combat, movement, exploration and story through one shared capability contract
- Merchant transactions that reuse stable item, story, capability and save-state contracts without partial mutation
- Ranged combat that uses visible travel, explicit reloads and inventory-backed ammunition instead of unexplained hitscan damage

## Documentation

- [`docs/GAME_VISION.md`](docs/GAME_VISION.md): originality and player promise
- [`docs/GAME_DESIGN_RESEARCH.md`](docs/GAME_DESIGN_RESEARCH.md): research synthesis and map-quality rubric
- [`docs/CAMPAIGN_STUDIO.md`](docs/CAMPAIGN_STUDIO.md): editor workflow and authoring surfaces
- [`docs/WORLD_BUILDER.md`](docs/WORLD_BUILDER.md): terrain, navigation and connection production rules
- [`docs/ENCOUNTER_STUDIO.md`](docs/ENCOUNTER_STUDIO.md): object and placement production rules
- [`docs/COMBAT_DIRECTOR.md`](docs/COMBAT_DIRECTOR.md): directed combat and encounter production rules
- [`docs/COMPANION_STUDIO.md`](docs/COMPANION_STUDIO.md): companion command and discovery production rules
- [`docs/ITEM_FORGE.md`](docs/ITEM_FORGE.md): item, inventory and crafting production rules
- [`docs/STORY_STUDIO.md`](docs/STORY_STUDIO.md): branching dialogue and quest production rules
- [`docs/SAVE_STATE_STUDIO.md`](docs/SAVE_STATE_STUDIO.md): save profile, migration and durable-state production rules
- [`docs/LOADOUT_STUDIO.md`](docs/LOADOUT_STUDIO.md): equipment, derived-stat and capability-gate production rules
- [`docs/MERCHANT_ECONOMY_STUDIO.md`](docs/MERCHANT_ECONOMY_STUDIO.md): currency, merchant, pricing, stock and transaction production rules
- [`docs/ECONOMY_PLAYTEST_CHECKLIST.md`](docs/ECONOMY_PLAYTEST_CHECKLIST.md): manual merchant, controller, balance and persistence review
- [`docs/ARSENAL_STUDIO.md`](docs/ARSENAL_STUDIO.md): ammunition, ranged weapon, projectile and save-state production rules
- [`docs/ARSENAL_PLAYTEST_CHECKLIST.md`](docs/ARSENAL_PLAYTEST_CHECKLIST.md): manual ranged-combat, reload, controller and durability review
- [`docs/OBJECT_FORMAT.md`](docs/OBJECT_FORMAT.md): object catalog, placement and persistent-state schema
- [`docs/CAMPAIGN_FORMAT.md`](docs/CAMPAIGN_FORMAT.md): campaign and map schema and migration rules

## Next production layers

The next vertical slices will build on the current contracts rather than replace them: alternate ammunition, merchant restocking and regional scarcity, bosses, cinematics, campaign packaging and import/export, localisation, cloud-save integration, and automated affordability, capability-order, quest-reachability, save-compatibility, companion-recovery, damage and softlock probes.
