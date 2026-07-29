# Epochbound Loadout Studio

Loadout Studio is the equipment, derived-stat and capability-gating layer for Epochbound campaigns.

It sits beside the existing Godot production tools:

- **Campaign Studio** authors maps, eras, terrain, collision, navigation and travel.
- **Encounter Studio** defines reusable objects and stable map placements.
- **Combat Director** directs enemy groups, telegraphs, leashes and persistent clear states.
- **Companion Studio** authors commands, discoveries and recovery behaviour.
- **Item Forge** defines inventory ownership, stack limits, recipes and item rewards.
- **Story Studio** defines conversations, conditions, effects, quest stages and rewards.
- **Save & State Studio** inspects and migrates durable player profiles.
- **Loadout Studio** defines equipment slots, gear modifiers, capabilities, starting loadouts and gated interactions.

Equipment does not create a second ownership database. Every piece of gear remains a normal Item Forge item. The loadout records only which owned item occupies each campaign-authored slot.

## Design goals

The loadout layer follows these production rules:

1. Equipment ownership remains in the shared inventory dictionary.
2. Slot IDs are authored by the campaign and remain stable when display names change.
3. Equipped items must exist in inventory and match their declared slot.
4. Derived stats are calculated from current equipment rather than persisted as authoritative values.
5. Capabilities are stable semantic IDs, not arbitrary script method names.
6. Map gates, object interactions and story conditions consume the same active capability set.
7. A blocked gate always provides player-facing feedback.
8. Equipment changes take effect immediately and reevaluate story progression.
9. Gear-dependent maximum health is rebuilt safely when equipping, unequipping or loading.
10. Save profiles preserve the selected loadout but continue to validate against current campaign content.
11. Older schema-1 profiles migrate to schema 2 with an empty equipment record.
12. Existing campaigns that omit loadout fields retain backwards-compatible default slots and no required gear.
13. Equipment choices should create meaningful trade-offs, not a single mathematically mandatory answer.
14. Required progression gear must remain recoverable and understandable.
15. Editor, validator, runtime and tests consume one shared content contract.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Loadout** main-screen tab.
3. Choose a source campaign.
4. Open **Capabilities** and define stable semantic abilities.
5. Open **Campaign Loadout** and define equipment slots.
6. Add the required equipment items in **Equipment**.
7. Assign each item to one slot and configure its modifiers.
8. Select the capabilities granted by that item.
9. Configure starting equipment and ensure each starting item also exists in starting inventory.
10. Open **Capability Gates** and choose a map connection or interaction.
11. Select its required capabilities and author blocked dialogue.
12. Validate the complete campaign.
13. Run the campaign and verify the route or interaction both with and without the required loadout.
14. Save and reload while alternative gear is equipped.
15. Confirm that derived stats and capabilities rebuild from the restored item IDs.

## Content layout

A campaign may declare one or more capability catalogues:

```json
{
  "capability_files": [
    "capabilities/core.json"
  ]
}
```

A normal campaign directory now contains:

```text
campaigns/my_campaign/
  campaign.json
  capabilities/
    core.json
  items/
    core.json
  recipes/
    core.json
  story/
    core.json
  objects/
    core.json
  maps/
    first_crossing.json
```

Capability IDs must be unique across every declared capability file.

## Capability catalogue contract

A capability catalogue contains a schema version and an array of capability definitions:

```json
{
  "schema_version": 1,
  "capabilities": [
    {
      "id": "illuminate_dark",
      "display_name": "Illuminate Darkness",
      "description": "Allows the player to enter and interpret spaces beyond ordinary ambient light."
    }
  ]
}
```

The current capability-catalogue schema is `1`.

### Capability ID

`id` is a stable normalised lowercase identifier.

Good examples:

- `illuminate_dark`
- `cut_clockvines`
- `clockglass_sight`
- `cross_shallow_water`
- `read_old_imperial`
- `open_brass_seals`

Avoid IDs tied to a temporary presentation detail such as:

- `press_x_here`
- `use_blue_icon`
- `call_unlock_method`
- `special_case_12`

A capability should describe what the actor can now accomplish in the game world.

### Display name

`display_name` is player-facing and may change without breaking references.

### Description

`description` explains the production meaning of the capability. It should help map, quest and item authors decide when the capability is appropriate.

A useful description answers:

- what the capability permits;
- what kind of obstruction it resolves;
- what it does not automatically imply;
- which visual or narrative cues should communicate the requirement.

## Campaign equipment slots

A campaign declares its loadout slots in `campaign.json`:

```json
{
  "equipment_slots": [
    {"id": "weapon", "display_name": "Weapon"},
    {"id": "body", "display_name": "Body"},
    {"id": "tool", "display_name": "Tool"}
  ]
}
```

### Stable slot IDs

Slot IDs are source references. Display names can be localised or rewritten without invalidating equipment or saves.

A campaign may use different slots where its design requires them:

```json
{
  "equipment_slots": [
    {"id": "main_hand", "display_name": "Main Hand"},
    {"id": "coat", "display_name": "Coat"},
    {"id": "instrument", "display_name": "Instrument"},
    {"id": "charm", "display_name": "Charm"}
  ]
}
```

The runtime does not assume that every campaign must use weapon, body and tool. Those three are the backwards-compatible default when a campaign omits its slot list.

### Slot-count discipline

More slots are not automatically better. Every slot creates:

- another player decision;
- another editor and HUD responsibility;
- another save-profile reference;
- more possible combinations to test;
- more opportunities for one obvious best configuration.

Use the fewest slots necessary to express the campaign’s meaningful choices.

## Equipment item contract

Equipment remains an Item Forge item with `kind: "equipment"` and a nested equipment record:

```json
{
  "id": "brass_hook",
  "display_name": "Brass Hook",
  "kind": "equipment",
  "description": "A compact rigging hook sharpened along its inner curve.",
  "stack_limit": 1,
  "value": 45,
  "use_effect": {"type": "none"},
  "equipment": {
    "slot": "weapon",
    "attack_bonus": 2,
    "defense_bonus": 0,
    "max_health_bonus": 0,
    "move_speed_bonus": 0,
    "capabilities": [
      "cut_clockvines"
    ]
  }
}
```

### Stack limit

Equipment currently requires `stack_limit: 1`.

The first loadout model identifies a piece of gear by stable item ID rather than supporting multiple statistically different copies of the same ID. Durability, random affixes and instance-specific equipment would require a separate reviewed item-instance contract.

### Slot

`slot` must reference one campaign equipment-slot ID.

An item can occupy one slot at a time. The same item ID cannot be equipped in several slots within one save profile.

### Attack bonus

`attack_bonus` is added to the player’s baseline action-attack damage.

It should remain understandable in relation to enemy health. Large bonuses can invalidate authored stagger, encounter duration and healing economy.

### Defence bonus

`defense_bonus` reduces incoming player damage.

The current runtime always allows at least one point of damage through a completed enemy attack. Defence cannot make ordinary contact completely consequence-free.

### Maximum-health bonus

`max_health_bonus` increases the player’s derived maximum health.

When maximum health rises, the runtime grants the same difference to current health. When it falls, current health is clamped to the new maximum but never reduced below one solely because equipment changed.

The save profile stores current health and equipment IDs. It does not store a separate authoritative maximum-health number.

### Movement-speed bonus

`move_speed_bonus` is added to baseline movement and clamped to runtime safety bounds.

Movement changes affect:

- combat spacing;
- companion follow behaviour;
- navigation timing;
- hazard readability;
- speedrunning routes;
- camera motion;
- authored interaction timing.

Treat movement equipment as a major design choice, not a decorative statistic.

### Granted capabilities

`capabilities` is an array of stable capability IDs.

A piece of equipment may grant none, one or several capabilities. Prefer focused identities. A single mandatory item that grants every exploration ability removes the value of the loadout decision.

## Starting equipment

Campaigns can select an initial item for each slot:

```json
{
  "starting_equipment": {
    "weapon": "brass_hook",
    "body": "museum_coat",
    "tool": "museum_flashlight"
  }
}
```

Every starting-equipment item must also appear in `starting_inventory`:

```json
{
  "starting_inventory": [
    {"item_id": "brass_hook", "quantity": 1},
    {"item_id": "museum_coat", "quantity": 1},
    {"item_id": "museum_flashlight", "quantity": 1}
  ]
}
```

This preserves the single ownership rule. The loadout cannot equip an item the player does not own.

A campaign may leave any slot empty by omitting that key.

## Base capabilities

Campaigns can grant capabilities independently of equipment:

```json
{
  "base_capabilities": [
    "speak_common_language"
  ]
}
```

Base capabilities are appropriate for abilities that are permanently part of the player character or campaign rules.

Do not use base capabilities to bypass equipment decisions unintentionally. When a base capability and equipped item grant the same ID, the active set still contains that ID once.

## Runtime loadout workflow

The Field Satchel now contains three tabs:

```text
ITEMS
RECIPES
EQUIPMENT
```

Player controls remain:

| Action | Keyboard | Controller |
| --- | --- | --- |
| Open or close Field Satchel | `I` | Back / View |
| Change tab | Left / Right | D-pad Left / Right |
| Change selection | Up / Down | D-pad Up / Down |
| Use, craft or cycle selected slot | E, Z, Space or C | South or East face button |
| Close | Escape or `I` | Back / View |

On the Equipment tab, confirming a slot cycles through:

1. the empty state;
2. every compatible owned item in deterministic display-name order.

Selecting an equipment item from the Items tab equips it directly into its declared slot.

Equipment is never consumed merely by equipping it.

## Derived stats

The current runtime derives:

```text
Attack damage = baseline attack damage + equipment attack bonuses
Defence       = sum of equipment defence bonuses
Maximum health = actor base maximum + equipment health bonuses
Movement speed = baseline movement + equipment speed bonuses
```

Derived values are recalculated from stable item definitions whenever required. They are not copied into campaign world state.

The HUD shows the current attack and defence values. The Equipment tab shows each equipped item and its authored modifiers.

## Active capabilities

The active capability set is the sorted union of:

- campaign `base_capabilities`;
- capabilities granted by every currently equipped item.

The set changes immediately when gear changes.

The same set is supplied to:

- connection gates;
- map interaction gates;
- object-definition gates;
- Story Studio `has_capability` conditions;
- quest-stage evaluation;
- editor and runtime smoke tests.

## Capability-gated map connections

A map connection can require one or more capabilities:

```json
{
  "id": "stairs_to_underworks",
  "position": {"x": 548, "y": 272},
  "radius": 34,
  "target_map": "museum_underworks",
  "target_entry": "from_bellweather",
  "target_era": "same",
  "trigger": "interact",
  "available_eras": [],
  "required_capabilities": [
    "illuminate_dark"
  ],
  "blocked_dialogue": "The service stairs disappear into absolute darkness. Eli needs a dependable light before taking Morrow below."
}
```

When requirements are not met:

- travel does not occur;
- runtime state is not partially mutated;
- the gate displays its blocked dialogue;
- the blockout renderer marks the locked connection.

### Multiple requirements

Every listed capability is required:

```json
{
  "required_capabilities": [
    "illuminate_dark",
    "open_brass_seals"
  ]
}
```

Use several requirements only when the location clearly communicates both needs. Hidden compound requirements produce trial-and-error rather than meaningful preparation.

## Capability-gated interactions

Map interactions can use the same fields:

```json
{
  "id": "sealed_catalogue",
  "kind": "catalogue",
  "position": {"x": 462, "y": 190},
  "radius": 54,
  "available_eras": [],
  "required_capabilities": [
    "clockglass_sight"
  ],
  "blocked_dialogue": "The brass page is perfectly blank. Ordinary light only makes it more opaque.",
  "dialogue": "The hidden accession line returns beneath the lens."
}
```

The same requirement hook applies before ordinary dialogue, story effects or conversation entry.

## Capability-gated object definitions

Reusable object definitions may also declare `required_capabilities` and `blocked_dialogue`.

This is useful for shared objects such as:

- sealed mechanisms;
- language-specific inscriptions;
- lock types;
- destructible growth;
- hazardous materials;
- hidden surfaces.

Use map-level requirements when the gate belongs to one specific placement or route. Use object-level requirements when every instance should share the same rule.

## Story Studio condition

Story conditions now support:

```json
{
  "type": "has_capability",
  "capability_id": "clockglass_sight"
}
```

This condition can appear on:

- conversation availability;
- line nodes;
- choice nodes;
- individual choices;
- quest-stage completion conditions.

Story Studio validates the identifier syntax. Loadout validation additionally confirms that the capability exists in the campaign’s declared catalogues.

## Reference loadout

The reference campaign begins with:

### Brass Hook

- Slot: Weapon
- Attack: +2
- Capability: Cut Clockvines

### Museum Field Coat

- Slot: Body
- Defence: +1
- Maximum health: +4

### Museum Flashlight

- Slot: Tool
- Capability: Illuminate Darkness

The completed **Missing Hour** quest grants:

### Archivist Lens

- Slot: Tool
- Movement speed: +8
- Capability: Clockglass Sight

The flashlight and lens compete for the same Tool slot. This creates an explicit choice:

- the flashlight permits travel into the dark Underworks;
- the lens reveals the sealed catalogue inside;
- equipping one removes the other capability until the player changes the loadout again.

The player must understand and deliberately manage that trade-off rather than accumulating every tool as an always-active passive ability.

## Museum Underworks reference map

The new Museum Underworks map proves:

- capability-gated travel from Bellweather Crossing;
- map and era restoration through the same save contract;
- a Clockvine Bulkhead requiring the Brass Hook;
- a Sealed Catalogue requiring the Archivist Lens;
- clear blocked feedback when a requirement is missing;
- loadout changes within the destination;
- safe return travel to Bellweather;
- persistent tool selection across save and load.

The reference route remains original to Epochbound and does not reproduce a location from an existing game.

## Equipment-aware save profiles

Save schema `2` adds an equipment dictionary to the durable payload:

```json
{
  "equipment": {
    "weapon": "brass_hook",
    "body": "museum_coat",
    "tool": "archivist_lens"
  }
}
```

A saved equipment record must satisfy all of these rules:

- the slot exists in the installed campaign;
- the item exists;
- the player owns at least one copy in saved inventory;
- the item kind is equipment;
- the item’s declared slot matches the saved slot;
- the same item ID is not equipped more than once.

Loading validates the profile before altering live state.

After campaign data loads, the runtime rebuilds:

- the equipped-item dictionary;
- attack damage;
- defence;
- maximum health;
- movement speed;
- active capabilities;
- capability-gated story progress.

## Save migration

### Schema 1 to schema 2

Schema-1 profiles already contain the durable map, inventory, quest and world-state contract but no equipment dictionary.

Migration:

1. validates the schema-1 checksum;
2. preserves the existing metadata and payload;
3. adds an empty equipment dictionary;
4. builds a schema-2 profile;
5. calculates a new checksum;
6. validates against the installed campaign before rewrite.

The migration does not guess which inventory items should be equipped. The player resumes with empty slots and can choose deliberately.

### Schema 0 to schema 2

The existing schema-0 migration now also normalises any legacy equipment object when one is present and otherwise adds an empty equipment dictionary.

### Future schemas

Profiles newer than schema 2 remain fail-closed. The runtime does not guess unknown equipment or progression semantics.

## Save & State Studio

The **State** editor now includes an Equipment tab and summary count.

It shows:

- slot ID;
- item display name;
- stable item ID;
- complete canonical JSON.

Profile validation uses the equipment-aware campaign validator, so invalid ownership, slot or item references are visible before runtime load.

## Loadout Studio tabs

### Equipment

The Equipment tab can:

- create equipment items in the primary item catalogue;
- author display names and descriptions;
- assign a campaign slot;
- configure attack, defence, health and speed modifiers;
- select granted capabilities;
- update an existing definition;
- prevent deletion while starting loadout, recipes or story references still use the item.

Secondary item catalogues remain read-only in this first multi-file authoring slice.

### Capabilities

The Capabilities tab can:

- create stable capability definitions;
- edit player-facing names;
- edit production descriptions;
- block deletion while gear, gates, base abilities or story conditions reference the capability.

Secondary capability catalogues remain read-only in this slice.

### Campaign Loadout

The Campaign Loadout tab can:

- define slots using `slot_id = Display Name` lines;
- define starting gear using `slot_id = item_id` lines;
- choose base capabilities;
- validate the complete campaign before keeping the change.

Malformed or duplicate assignment rows are rejected with line-specific feedback.

### Capability Gates

The Capability Gates tab can:

- select a map;
- choose connections or interactions;
- select one stable record;
- choose its required capabilities;
- author blocked dialogue;
- remove a gate by clearing every capability;
- roll back a save that would invalidate the campaign.

## Safe deletion

Loadout Studio blocks capability deletion while referenced by:

- campaign base capabilities;
- equipment definitions;
- map connections;
- map interactions;
- Story Studio conditions.

It blocks equipment-item deletion while referenced by:

- starting inventory;
- starting equipment;
- recipe inputs or outputs;
- story records.

Item Forge also recognises starting-equipment references when checking whether an item can be deleted.

## Validation rules

Equipment validation rejects:

- unsafe or repeated capability catalogue paths;
- unsupported capability schemas;
- invalid or duplicate capability IDs;
- missing capability display names;
- excessively long capability descriptions;
- malformed equipment-slot arrays;
- invalid or duplicate slot IDs;
- slots without display names;
- equipment with stack limits other than one;
- missing or malformed equipment records;
- equipment assigned to unknown slots;
- negative or excessively large stat modifiers;
- malformed capability arrays;
- unknown or duplicate capability references;
- starting equipment assigned to unknown slots;
- starting equipment referencing unknown or non-equipment items;
- starting equipment not present in starting inventory;
- the same item equipped in several starting slots;
- gates referring to unknown capabilities;
- gates without blocked dialogue;
- story conditions referring to unknown capabilities;
- save profiles equipping unowned items;
- save profiles using unknown slots;
- save profiles placing gear into the wrong slot;
- save profiles equipping the same item more than once.

It warns about:

- omitted capability catalogues;
- omitted slot lists using the backwards-compatible default;
- omitted starting loadouts;
- empty capability catalogues;
- capabilities that are never granted or referenced;
- non-equipment items containing stray equipment records.

## Equipment quality gates

### Readability

- The player can identify which item occupies each slot.
- Stat changes are visible before or immediately after equipping.
- A capability-gated obstacle communicates the nature of the requirement.
- Blocked dialogue names the missing kind of solution without exposing internal IDs.
- Equipment descriptions explain purpose rather than only numerical bonuses.

### Meaningful choice

- At least two items in a contested slot support distinct uses.
- No item dominates every alternative across combat, traversal and story.
- Required progression gear does not permanently remove all viable combat options.
- Swapping gear is deliberate but not excessively burdensome.
- Equipment choices remain relevant after their first tutorial use.

### Combat balance

- Attack bonuses preserve readable encounter duration.
- Defence does not eliminate all ordinary damage.
- Health bonuses do not invalidate healing-item values.
- Movement bonuses do not bypass enemy telegraphs or authored hazards.
- Companion combat remains useful when the player changes gear.

### Exploration reliability

- Required gear is obtainable before the first required gate.
- A player cannot permanently discard or consume mandatory equipment.
- Returning from a gated area remains possible with the current or any valid loadout.
- Loadout changes cannot place actors inside collision.
- A route does not silently require a capability that no item or base ability grants.

### Narrative coherence

- Capability names describe actions that make sense in the world.
- Dialogue acknowledges the actual tool or ability where appropriate.
- Quest rewards that grant equipment have a clear narrative source.
- Story conditions use capabilities when they mean ability, and item ownership when they mean possession.
- Era changes may alter how a capability is expressed without changing its stable semantic ID unnecessarily.

### Save durability

- Every equipped item is owned.
- Saved slots and item IDs remain stable.
- Derived stats rebuild rather than drifting across repeated loads.
- Schema migrations are explicit and tested.
- Invalid equipment fails before any live state is mutated.
- Continue excludes incompatible or corrupt profiles.

### Accessibility

- Gates do not depend solely on colour.
- Equipped and empty states have text labels.
- Capability feedback is available through dialogue, not only a small icon.
- Equipment navigation works with keyboard and controller.
- Time-sensitive combat does not continue while the Field Satchel is open.

## Automated verification

The official Godot 4.6.2 gate now covers:

1. direct compilation of the equipment runtime, capability catalogue, validator, model and Loadout Studio;
2. strict project import with plugin errors treated as failures;
3. complete campaign, equipment, capability and gate validation;
4. inherited world, combat, companion, item, story and save regression tests;
5. starting-equipment and derived-stat verification;
6. tool-slot cycling and capability removal;
7. blocked and successful capability-gated travel;
8. capability-gated Underworks interactions;
9. Story Studio `has_capability` evaluation;
10. schema-2 profile capture and checksum verification;
11. exact equipment restoration through the normal slot API;
12. Loadout Studio widget, form, gate and parser tests;
13. malformed slot, stat, capability, gate and profile-ownership rejection tests.

Run the same validation on Windows:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

## Future extensions

The current contract is intended to support later additions without replacing existing campaign content:

- equipment acquisition through merchants;
- sell values and buyback rules;
- ranged weapons and ammunition;
- active equipment abilities;
- elemental or damage-type modifiers;
- status resistance;
- companion equipment where narratively appropriate;
- comparison panels and equipment presets;
- accessibility recommendations for required traversal gear;
- quest-reachability analysis using capability acquisition order;
- economy simulation around equipment prices;
- campaign packaging checks for every referenced capability;
- localisation of slot, item and capability copy;
- richer final pixel-art equipment presentation.

Every extension should preserve the central rule: ownership, loadout, capabilities, story gates and save profiles use stable shared records rather than parallel systems.
