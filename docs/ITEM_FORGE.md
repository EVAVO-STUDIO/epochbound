# Epochbound Item Forge

Item Forge is the campaign-authoring and runtime contract for items, inventory, consumables, crafting and recipe discovery.

It sits beside the existing Godot tools rather than hiding item state inside scenes or scripts:

- **Campaign Studio** authors maps, eras, collision, navigation and travel.
- **Encounter Studio** defines reusable objects and places pickups.
- **Combat Director** directs enemy groups and combat spaces.
- **Companion Studio** authors commands and discoverable cues.
- **Item Forge** defines item and recipe catalogs, starting loadouts and crafting rules.

The editor, validator, runtime and automated tests all consume the same JSON records.

## Design goals

The item layer is built around several production rules:

1. Items are campaign data, not hard-coded script constants.
2. Recipes reference stable item IDs and remain inspectable in source control.
3. Inventory quantities are deterministic integers with explicit stack limits.
4. Durable outcomes use existing campaign state keys, preventing duplicate rewards.
5. Crafting cannot consume ingredients unless the output fits its stack.
6. A campaign can omit equipment depth without losing consumables, materials or key items.
7. The editor blocks deletion while active campaign records still reference an item or recipe.
8. New campaigns start with valid catalogs and a functioning starter crafting loop.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Items** tab.
3. Choose a campaign.
4. Use the **Items** section to create and tune item definitions.
5. Use the **Recipes** section to create ingredient and output contracts.
6. Use **Starting Loadout** to choose initial item quantities and known recipes.
7. Validate the complete campaign.
8. Author pickup grants in Encounter Studio or discovery grants in Companion Studio.
9. Run the campaign and verify acquisition, consumption, crafting, travel and era persistence.

## Content layout

A campaign declares separate item and recipe files:

```json
{
  "item_files": [
    "items/core.json"
  ],
  "recipe_files": [
    "recipes/core.json"
  ],
  "starting_inventory": [
    {"item_id": "museum_tonic", "quantity": 1}
  ],
  "starting_recipes": [
    "ember_salve_recipe"
  ]
}
```

A normal campaign directory therefore contains:

```text
campaigns/my_campaign/
  campaign.json
  items/
    core.json
  recipes/
    core.json
  objects/
    core.json
  maps/
    first_crossing.json
```

Additional item or recipe files can be declared later. IDs must remain unique across all declared files of the same catalog type.


## Cross-domain reference accounting

The unused-item and never-unlocked-recipe review is repository-wide, not limited to Item Forge files. A known item or recipe counts as intentionally authored when it appears in:

- starting inventory or starting equipment;
- recipe ingredients or output;
- reusable-object grants and boss outcomes;
- companion rewards and recipe discoveries;
- Story Studio conditions, effects and quest rewards;
- merchant stock and refusal lists;
- Cinematic effects.

Each owning domain still validates the reference itself. Cross-domain accounting marks only IDs that already exist, so an unknown item in a story or merchant record cannot be hidden by the usage scanner. This separation prevents false unused-content warnings without weakening fail-closed reference validation.

## Item catalog contract

An item catalog has a version and an `items` array:

```json
{
  "schema_version": 1,
  "items": [
    {
      "id": "ember_salve",
      "display_name": "Ember Salve",
      "kind": "consumable",
      "description": "A field salve that carries steady warmth without flame.",
      "stack_limit": 9,
      "value": 36,
      "use_effect": {
        "type": "heal",
        "amount": 18
      }
    }
  ]
}
```

### Item ID

`id` is the stable campaign reference. It must be a normalised lowercase identifier.

Good examples:

- `museum_tonic`
- `brass_filings`
- `clockglass_fragment`
- `clockglass_lens`

Display text may change without breaking references. IDs should not be renamed after content begins using them unless a migration updates every reference.

### Display name and description

`display_name` is player-facing text used in the inventory and crafting interface.

`description` explains the item’s identity or purpose. It should support worldbuilding without becoming a substitute for quest text.

Descriptions should answer at least one useful question:

- What is this object?
- Why is it unusual?
- What does it imply about the world or era?
- What practical use does it have?

### Item kinds

The current schema accepts four kinds.

#### Consumable

A directly usable item, normally removed by one quantity when its effect succeeds.

Current runtime support:

- healing the player;
- blocking use when health is already full;
- quick-use selection of the first available healing item;
- use from the inventory overlay.

#### Material

An ingredient or trade component. Materials cannot be used directly unless a later schema explicitly gives them an active effect.

#### Key

A durable progression object. Key items normally use a stack limit of one and are not consumed directly.

The current runtime stores key items but does not yet apply capability or quest gates from them. That extension should reference the same item ID rather than introducing a separate key-item system.

#### Equipment

A reserved item kind for later weapon, armour, accessory or tool slots. Item Forge can author the kind now, but equipment stats and equipping are not yet part of this runtime slice.

### Stack limit

`stack_limit` is the maximum quantity the inventory may hold for one item ID.

Current limits:

- minimum: 1;
- maximum: 999.

Every acquisition path uses the same stack rule:

- starting inventory;
- pickup rewards;
- companion discoveries;
- crafting output;
- future quest or merchant grants.

If a grant exceeds available capacity, the model reports the overflow instead of silently exceeding the stack.

### Value

`value` is a non-negative authored amount reserved for later merchant, economy and comparison systems. The current runtime does not spend or sell items.

### Use effect

`use_effect` is always an object.

Supported types:

```json
{"type": "none"}
```

```json
{"type": "heal", "amount": 10}
```

A heal amount must be positive. Non-consumables defining active effects produce a warning, and consumables with no active effect produce a warning.

Future effects should remain typed data rather than executable script names. Examples may include status recovery, temporary buffs or companion healing, but each new effect needs validation and executable tests before campaigns can rely on it.

## Recipe catalog contract

A recipe catalog has a version and a `recipes` array:

```json
{
  "schema_version": 1,
  "recipes": [
    {
      "id": "ember_salve_recipe",
      "display_name": "Mix Ember Salve",
      "description": "Bind Ashen resin with warm brass filings.",
      "ingredients": [
        {"item_id": "brass_filings", "quantity": 2},
        {"item_id": "ashen_resin", "quantity": 1}
      ],
      "output": {
        "item_id": "ember_salve",
        "quantity": 1
      },
      "unlocked_by_default": false
    }
  ]
}
```

### Recipe ID

`id` is a stable normalised reference used by starting loadouts and discovery unlocks.

### Ingredients

`ingredients` must contain at least one item reference. Each item may appear only once in a recipe.

Every ingredient quantity must be positive. Referenced items must exist in the campaign’s item catalogs.

### Output

`output` contains one item ID and a positive quantity. The output quantity cannot exceed the item’s stack limit.

The runtime checks output capacity before removing ingredients. A failed capacity check does not consume anything.

### Default unlock

`unlocked_by_default` makes a recipe known without a starting-loadout reference or discovery event.

A campaign may also declare recipes in `starting_recipes`. Both sources merge into one deterministic unlock set.

## Starting loadout

`starting_inventory` is an array of item quantities:

```json
{
  "starting_inventory": [
    {"item_id": "museum_tonic", "quantity": 1},
    {"item_id": "brass_filings", "quantity": 1}
  ]
}
```

Rules:

- every item must exist;
- quantities must be positive;
- one item ID may appear only once;
- quantities must not exceed the authored stack limit.

`starting_recipes` is an array of known recipe IDs. IDs must exist and may not repeat.

Starting state is rebuilt when a campaign is newly loaded. Later save profiles will replace this reset with a persisted inventory snapshot after validating its campaign and schema version.

## Pickup grants

Reusable pickup definitions may grant items through `item_grants`:

```json
{
  "id": "clock_shard",
  "kind": "pickup",
  "pickup_value": 1,
  "item_grants": [
    {"item_id": "clockglass_fragment", "quantity": 1}
  ]
}
```

The pickup’s existing persistent placement state protects both its original reward and its item grant. Once the placement is collected, returning to the map or changing era does not duplicate either result.

`item_grants` normally belong on pickup definitions. Validation warns when another object kind carries them because that can produce unclear acquisition behaviour.

## Companion discovery rewards

Companion cues may grant items:

```json
{
  "id": "cold_ash_cache",
  "kind": "resource",
  "reward_items": [
    {"item_id": "ashen_resin", "quantity": 1}
  ]
}
```

They may also unlock recipes:

```json
{
  "id": "future_bark_trail",
  "kind": "trail",
  "unlock_recipes": [
    "clockglass_lens_recipe"
  ]
}
```

Both operations are protected by the cue’s stable discovery state key. Re-running the discovery method cannot duplicate items or re-announce a recipe.

This allows companion exploration to feed progression without giving Morrow a separate inventory or hidden reward database.

## Runtime inventory

The runtime inventory is a dictionary of item IDs to integer quantities.

Example:

```json
{
  "museum_tonic": 1,
  "brass_filings": 3,
  "clockglass_fragment": 1
}
```

It persists while the player:

- changes era;
- travels between maps;
- collects pickups;
- discovers companion cues;
- crafts recipes;
- uses consumables.

The current persistence scope is the active session. Durable save profiles are a later layer.

## Inventory interface

Press **I** on keyboard or **Back/View** on controller to open the Field Satchel.

The overlay pauses world movement and combat by returning before the inherited gameplay update.

Controls:

| Action | Keyboard | Controller |
| --- | --- | --- |
| Open or close satchel | I | Back / View |
| Change Items or Recipes tab | Left / Right | D-pad Left / Right |
| Change selection | Up / Down | D-pad Up / Down |
| Use item or craft recipe | E, Z, Space or C | South or East face button |
| Close | Escape or I | Back / View |

The Items tab shows:

- display name;
- quantity;
- kind;
- description;
- current active effect where supported.

The Recipes tab shows:

- learned recipes only;
- ingredient availability;
- output;
- whether the current inventory can craft it.

## Quick-use item

Press **V** or the right shoulder button to use the first available healing consumable.

Selection is deterministic because inventory IDs are sorted by display name. A quick-use attempt reports when:

- no restorative exists;
- health is already full;
- an item was consumed successfully.

Later quick-slot authoring should build on explicit selected item IDs rather than changing this inventory contract.

## Crafting transaction

A craft follows this exact sequence:

1. Confirm the recipe is unlocked.
2. Confirm the recipe exists.
3. Confirm every ingredient quantity is available.
4. Confirm the output item exists.
5. Confirm the output fits within its stack limit.
6. Remove ingredients.
7. Add the complete output quantity.
8. Publish success feedback.

Steps 3 to 5 occur before inventory mutation. This prevents partial consumption on ordinary validation failures.

## Safe deletion

Item Forge refuses to delete an item while it is referenced by:

- a recipe ingredient;
- a recipe output;
- starting inventory;
- a reusable object grant;
- a companion-cue reward.

It refuses to delete a recipe while it is referenced by:

- starting recipes;
- a companion-cue unlock.

Definitions loaded from secondary catalog files remain read-only in this first editor slice. The primary catalog is the first safe declared file.

## Validation rules

The item validator rejects:

- missing or malformed item and recipe file arrays;
- unsafe catalog paths;
- duplicate paths;
- unsupported schema versions;
- malformed catalog arrays;
- invalid or duplicate IDs;
- duplicate IDs across declared files;
- unsupported item kinds;
- missing display names;
- stack limits outside 1 to 999;
- negative values;
- malformed or unsupported use effects;
- non-positive heal amounts;
- recipes without ingredients;
- unknown ingredient or output items;
- repeated ingredients;
- non-positive ingredient or output quantities;
- outputs larger than their item stack limit;
- malformed starting inventory;
- unknown or repeated starting recipes;
- unknown pickup or cue reward items;
- unknown discovery recipe unlocks.

It warns about:

- empty catalogs;
- empty descriptions;
- non-consumables with active effects;
- consumables without active effects;
- item grants on non-pickup definitions;
- items never used by starts, recipes or rewards;
- recipes that are never unlocked.

## Reference progression proof

The reference campaign demonstrates a complete authored loop.

### Starting state

Eli begins with:

- one Museum Tonic;
- one Brass Filings stack;
- knowledge of the Ember Salve recipe.

### Bellweather Crossing

- Morrow’s Verdant well clue grants two Brass Filings.
- The Verdant clock shard grants one Clockglass Fragment.

### Clockwood Edge

- The Ashen cache grants one Ashen Resin.
- Those materials can craft one Ember Salve.
- The Verdant future-bark trail teaches the Clockglass Lens recipe.
- The shared clock shard grants a second Clockglass Fragment.
- Two fragments and the remaining Brass Filings craft the Clockglass Lens key item.

The sequence proves:

- starting inventory;
- persistent pickup rewards;
- persistent companion rewards;
- recipe discovery;
- ingredient consumption;
- healing consumables;
- stack enforcement;
- durable key-item output;
- duplicate-reward protection across map and era changes.

## Automated verification

The official Godot 4.6.2 gate now checks:

1. direct compilation of the runtime, validators, smoke tests and all five editor plugins;
2. strict project import;
3. campaign, map, object, encounter, companion, item and recipe validation;
4. world traversal;
5. base encounter and combat behaviour;
6. directed encounter behaviour;
7. companion command and discovery behaviour;
8. item catalog loading, starting state, stack overflow, acquisition, recipe unlocking, crafting, healing and reward idempotence.

Run the same sequence locally:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

## Quality gates

A production item should pass these checks.

### Readability

- The name is distinct from similar items.
- The description explains identity or purpose.
- Consumable effects are visible before use.
- Materials are clearly differentiated from directly usable items.

### Economy

- Stack limits match expected acquisition frequency.
- Recipe costs do not create accidental dead ends.
- Required materials have enough authored sources.
- One-time rewards cannot be duplicated.
- Key items are not accidentally sellable or consumable in later economy layers.

### Crafting

- Recipes introduce a meaningful choice or progression result.
- Ingredient sources are discoverable before the recipe becomes mandatory.
- The output is useful when the player can first craft it.
- Recipe discovery is communicated clearly.
- Crafting cannot consume resources on a failed transaction.

### Exploration

- Pickups and companion discoveries support location identity.
- Rewards reinforce why the player explored or shifted era.
- Hidden materials do not make required progression depend on arbitrary pixel hunting.
- Morrow’s discoveries remain informative even when the item reward is already understood.

### Accessibility

- Required information is textual, not colour-only.
- The satchel can be operated without pointer input.
- Selection and craftability use labels as well as visual emphasis.
- Quick-use is optional rather than required for normal healing access.

## Future extensions

The current contracts are designed to support:

- equipment slots and stat modifiers;
- quick-slot selection;
- companion consumables;
- merchants and item value;
- loot tables;
- quest requirements and rewards;
- capability gates driven by key items;
- crafting stations and station tags;
- multi-output recipes;
- recipe categories and filtering;
- difficulty-based quantities;
- save-profile inventory persistence;
- campaign migration tools;
- automated economy and progression reachability probes.

Those layers should extend the same item IDs, inventory quantities and recipe definitions rather than introducing parallel databases.
