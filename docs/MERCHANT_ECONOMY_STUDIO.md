# Epochbound Merchant & Economy Studio

Merchant & Economy Studio is the campaign-authoring layer for currencies, shop inventories, pricing, merchant availability, NPC trade bindings and durable transaction state.

It does not create a separate shop inventory. Every traded good is an Item Forge item identified by the same stable item ID used by crafting, equipment, quests, rewards and save profiles.

The system separates four responsibilities:

- **Item Forge** defines what an item is, its stack limit and its baseline value.
- **Loadout Studio** defines equipment slots, modifiers and capabilities.
- **Story Studio** defines conditions and effects involving currency or progression.
- **Merchant & Economy Studio** defines who trades, which currency they use, what they stock and which transactions they accept.

All four layers consume the same source-controlled campaign records.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Trade** main-screen tab.
3. Choose a campaign.
4. Create or inspect a currency.
5. Set its starting and maximum balances.
6. Create or inspect a merchant.
7. Choose the transaction currency.
8. Set buy and sell multipliers.
9. Configure accepted item kinds and refused item IDs.
10. Author finite or unlimited stock entries.
11. Add optional Story Studio conditions to the merchant or individual stock entries.
12. Select an NPC definition on the **NPC Bindings** tab.
13. Bind that reusable NPC definition to the merchant.
14. Validate the complete campaign.
15. Run the campaign and verify buying, selling, stock depletion, blocked transactions and save restoration.

## Economy catalogue

Campaigns declare economy files in `campaign.json`:

```json
{
  "economy_files": [
    "economy/core.json"
  ]
}
```

An economy catalogue contains currencies and merchants:

```json
{
  "schema_version": 1,
  "currencies": [],
  "merchants": []
}
```

Multiple catalogues may be declared. IDs must remain unique across the complete campaign.

## Currency contract

A currency record looks like:

```json
{
  "id": "archive_chits",
  "display_name": "Archive Chits",
  "symbol": "AC",
  "starting_balance": 60,
  "max_balance": 999999
}
```

### Stable ID

`id` is the durable reference used by:

- merchant transaction records;
- player wallet state;
- Story Studio conditions;
- Story Studio effects;
- save profiles;
- State Studio inspection.

Changing a display name or symbol does not change the saved identity.

### Starting balance

`starting_balance` applies when a new economy is initialised.

It also applies when loading a valid pre-economy save whose migration explicitly marks `economy_initialized` as false. This gives older saves a deterministic campaign-authored starting wallet instead of guessing from play time or inventory value.

### Maximum balance

`max_balance` prevents integer growth and defines the wallet-capacity check used before a sale completes.

A sale that cannot fit its complete payment is rejected before the item is removed. Partial payment is not allowed.

## Merchant contract

A merchant record looks like:

```json
{
  "id": "bellweather_provisions",
  "display_name": "Bellweather Provisions",
  "currency_id": "archive_chits",
  "greeting": "The museum till still remembers honest prices.",
  "farewell": "Bring back anything the hours have not claimed.",
  "buy_multiplier": 1.0,
  "sell_multiplier": 0.5,
  "accepts_sales": true,
  "accepted_kinds": [
    "consumable",
    "material",
    "equipment"
  ],
  "refused_items": [
    "clockglass_lens"
  ],
  "resell_player_goods": true,
  "conditions": [],
  "stock": []
}
```

### Buy multiplier

The buy multiplier modifies the item’s baseline Item Forge value when a stock record does not provide an explicit `buy_price`.

```text
resolved buy price = ceil(item value × buy multiplier)
```

A positive item value always resolves to at least one unit of currency.

### Sell multiplier

The sell multiplier determines what the merchant pays for an accepted item when the stock record does not provide an explicit `sell_price`.

```text
resolved sell price = floor(item value × sell multiplier)
```

A positive accepted item resolves to at least one unit unless the merchant refuses it through another rule.

The validator warns when the resolved sell price is not lower than the buy price because that may create a trivial repeatable profit loop.

### Accepted kinds

`accepted_kinds` can contain supported Item Forge kinds:

- `consumable`
- `material`
- `key`
- `equipment`

Key items are normally omitted. A campaign may deliberately accept them, but doing so must not break progression or quest requirements.

### Refused items

`refused_items` overrides accepted kinds for specific item IDs.

The reference merchants refuse the Clockglass Lens and Archivist Lens so essential narrative and capability tools cannot be converted into currency accidentally.

### Reselling player goods

When `resell_player_goods` is true, a successfully sold item becomes merchant stock.

If the item already has finite authored stock, its quantity increases. If it was not initially stocked, a new durable merchant-stock entry is created.

When the field is false, sold goods leave the active economy after the player receives payment.

## Stock entries

A stock record looks like:

```json
{
  "item_id": "museum_tonic",
  "quantity": 3,
  "unlimited": false,
  "buy_price": 18,
  "sell_price": 10,
  "conditions": []
}
```

### Finite stock

A finite entry uses `unlimited: false` and a non-negative quantity.

Purchasing decrements its durable quantity. Selling a compatible item back can increase it when the merchant resells player goods.

Finite stock persists through save profiles.

### Unlimited stock

An unlimited entry uses `unlimited: true`.

Runtime state represents unlimited stock with `-1`, but authored content still uses a normal non-negative `quantity` field so the source format remains easy to validate. The quantity is ignored while unlimited is true.

Purchases never decrement unlimited stock.

### Explicit prices

A positive `buy_price` or `sell_price` overrides the merchant multiplier for that item.

A zero value requests a price derived from the Item Forge baseline value.

Negative prices are rejected.

### Conditions

Stock conditions use the same typed condition records as Story Studio.

The reference Underworks Exchange reveals Clockglass Fragments only while **The Missing Hour** is active.

## NPC merchant bindings

Reusable NPC definitions may declare:

```json
{
  "id": "museum_provisioner",
  "kind": "npc",
  "merchant_id": "bellweather_provisions"
}
```

Map placements continue to reference the reusable NPC definition. The definition then opens the selected merchant contract.

This allows one merchant to appear on multiple maps or in multiple eras without copying its stock and pricing rules.

The validator warns when `merchant_id` is placed on a non-NPC object definition.

## Runtime trade flow

Interacting with a valid merchant NPC opens a paused trade overlay.

| Action | Keyboard or controller navigation |
| --- | --- |
| Change Buy or Sell mode | Left / Right |
| Change selected item | Up / Down |
| Buy or sell one item | Confirm or Attack action |
| Close trade | Cancel or Field Satchel action |

The overlay displays:

- merchant name;
- active currency and wallet balance;
- buy and sell tabs;
- resolved price;
- finite or unlimited stock;
- owned quantity;
- item kind and description;
- equipped-item warning;
- transaction feedback.

Gameplay, combat and companion movement remain paused while trade is open.

Manual saving and autosave flushing are also deferred until the merchant overlay closes.

## Atomic purchase sequence

Buying follows this order:

1. Confirm the merchant exists and is available.
2. Confirm the item exists.
3. Confirm the item belongs to the merchant’s current stock.
4. Confirm stock conditions are satisfied.
5. Confirm enough finite or unlimited stock exists.
6. Confirm the complete quantity fits the player’s authored stack limit.
7. Resolve the unit and total price.
8. Confirm the wallet contains the full total.
9. Remove the full currency amount.
10. Add the full item quantity.
11. Decrement finite merchant stock.
12. Publish player-facing feedback.

If item insertion fails after the balance check, the currency removal is rolled back before the function returns.

A failed purchase cannot partially change the wallet, inventory or merchant stock.

## Atomic sale sequence

Selling follows this order:

1. Confirm the merchant exists and is available.
2. Confirm the player owns the full quantity.
3. Reject any currently equipped item.
4. Confirm the merchant accepts the item’s kind.
5. Apply specific refusal rules.
6. Resolve the complete payment.
7. Confirm the wallet can hold the complete payment.
8. Remove the full item quantity.
9. Add the full currency amount.
10. Add the item to merchant stock when reselling is enabled.
11. Publish player-facing feedback.

If payment insertion fails, item removal is rolled back.

A failed sale cannot partially change inventory, wallet or merchant stock.

## Equipment safety

Currently equipped items are protected from sale.

This prevents several failure cases:

- selling the active flashlight while inside a dark capability-gated map;
- selling armour while its maximum-health bonus is active;
- leaving a save profile with an equipped item no longer owned in inventory;
- creating a mismatch between active capabilities and owned gear.

The player must first unequip the item through the Field Satchel Equipment tab.

Item Forge safe deletion also checks merchant stock and refusal rules, so authors cannot delete an item while an economy record still references it.

## Story integration

Story Studio now supports:

```json
{
  "type": "currency_at_least",
  "currency_id": "archive_chits",
  "amount": 25
}
```

It also supports effects:

```json
{
  "type": "grant_currency",
  "currency_id": "archive_chits",
  "amount": 12
}
```

```json
{
  "type": "remove_currency",
  "currency_id": "archive_chits",
  "amount": 10
}
```

These records use the exact wallet state displayed by merchants and preserved in save profiles.

A quest reward does not create a second story-only balance.

The reference **Quiet the Ash Hunt** quest grants Archive Chits in addition to its existing item and clock-shard rewards.

## Capability and quest availability

Merchants and individual stock entries may use the complete Story Studio condition set, including:

- item ownership;
- durable state values;
- quest status or stage;
- map and era;
- clock-shard totals;
- active equipment capabilities;
- currency balances.

The Underworks Exchange requires `illuminate_dark`, so it opens only while the Museum Flashlight or another suitable light-granting tool is equipped.

## Durable save state

Save schema 3 adds:

```json
{
  "currency_balances": {
    "archive_chits": 42
  },
  "merchant_stock": {
    "bellweather_provisions": {
      "museum_tonic": 2
    }
  },
  "economy_initialized": true
}
```

The schema persists:

- every declared wallet balance;
- every merchant’s finite and dynamic stock;
- unlimited-stock sentinel values;
- whether authored starting economy defaults have already been applied.

Before runtime mutation, profile validation confirms:

- currency IDs still exist;
- balances remain within their maximums;
- merchant IDs still exist;
- stock item IDs still exist;
- unauthored dynamic stock is allowed only when reselling is enabled;
- unlimited stock retains the required sentinel;
- every declared currency and merchant is represented after initialisation.

## Migration from schema 2

Schema-2 profiles predate the economy layer.

Migration adds empty wallet and merchant-stock dictionaries and sets:

```json
{
  "economy_initialized": false
}
```

On load, the installed campaign’s current starting balances and initial stock are applied deterministically.

The migration does not infer wealth from inventory value, quest count, equipment or play time.

## Save & State Studio

State Studio now includes:

- **Wallet** tab for persisted balances;
- **Merchant Stock** tab for finite, unlimited and dynamically resold goods;
- wallet and merchant counts in the overview;
- schema-3 canonical JSON;
- economy-aware campaign and profile validation.

This makes transaction support and save recovery inspectable without editing files manually.

## Reference economy

### Archive Chits

The reference campaign uses Archive Chits (`AC`) as a museum and salvage exchange currency.

Eli begins with 60 AC.

### Bellweather Provisions

The Bellweather Provisioner appears in both Verdant and Ashen Bellweather Crossing.

Initial finite stock includes:

- Museum Tonic
- Brass Filings
- Ember Salve
- Museum Flashlight

The merchant accepts consumables, materials and equipment, but refuses progression-critical lenses.

### Underworks Exchange

The Underworks Salvager appears in Museum Underworks.

The merchant requires active illumination and stocks:

- Ashen Resin
- Clockglass Fragments while The Missing Hour is active
- Underworks Salvager Wrap

The Salvager Wrap provides greater defence and movement than the Museum Field Coat, but does not increase maximum health. This creates another loadout trade-off rather than a universal upgrade.

## Validation rules

Merchant & Economy validation rejects:

- unsafe or repeated economy file paths;
- unsupported catalogue schemas;
- invalid or duplicate currency IDs;
- missing currency names or symbols;
- invalid starting or maximum balances;
- invalid or duplicate merchant IDs;
- unknown merchant currencies;
- invalid buy or sell multipliers;
- malformed sales and resale flags;
- unsupported or repeated accepted item kinds;
- unknown or repeated refused items;
- malformed merchant or stock conditions;
- unknown stock items;
- repeated merchant stock entries;
- invalid finite quantities;
- negative price overrides;
- zero-value stock without an explicit buy price;
- unknown merchant bindings;
- unknown currency references in story content;
- invalid saved wallet or stock state;
- missing declared wallets or merchants in an initialised profile.

It warns about:

- zero starting balances without another earning route;
- empty merchant greetings or farewells;
- merchants that cannot buy any item kind;
- empty stock;
- finite stock that begins empty;
- prices that may permit trivial buy-and-sell profit loops;
- merchants not bound to any NPC definition;
- currencies unused by merchants or story content.

## Economy quality gates

A production economy should satisfy all of these principles.

### Purpose

- Currency rewards lead to meaningful decisions rather than an ever-growing unused number.
- Merchants support exploration, combat preparation, recovery or deliberate loadout choices.
- Essential progression is not dependent on grinding disposable enemies unless the campaign explicitly communicates that structure.

### Readability

- The player can distinguish buy price, sell price, wallet balance, owned quantity and remaining stock.
- Refusal and blocked-availability messages explain the missing requirement.
- Finite stock and unlimited stock are visibly different.
- A completed transaction provides immediate confirmation.

### Fairness

- The campaign provides at least one reasonable earning route before required purchases.
- Required items are not priced beyond the available authored economy.
- A player cannot unknowingly sell an equipped item or essential progression tool.
- Failed transactions do not remove currency or items.

### Balance

- Buy prices reflect item utility and scarcity.
- Sell prices do not create effortless repeatable profit loops.
- Finite stock matters without making recovery items permanently unavailable after an accidental purchase.
- Equipment prices account for combat, movement and capability impact rather than only baseline item value.

### Persistence

- Purchased finite stock remains depleted after saving and loading.
- Sold goods reappear only when the merchant’s resale rule allows it.
- Wallet balances restore exactly.
- Older saves initialise economy defaults once and never repeatedly grant starting currency.

### Accessibility

- Essential information is communicated through text and numbers, not colour alone.
- The selected row has a clear marker.
- Buy and Sell modes remain labelled.
- Important refusal messages remain on screen long enough to read.
- Controller and keyboard navigation reach every transaction action.

## Automated verification

The official Godot 4.6.2 gate now verifies:

1. economy catalogue, model, validator, runtime and Trade Studio compilation;
2. strict editor import with all nine plugins;
3. complete campaign economy validation;
4. inherited world, combat, companion, inventory, story, save and loadout behaviour;
5. initial wallet and stock creation;
6. successful finite-stock purchase;
7. successful sale and merchant restocking;
8. rollback when a player stack is full;
9. rejection of equipped-item sales;
10. capability-gated merchant availability;
11. Story Studio currency rewards and conditions;
12. schema-3 wallet and stock capture;
13. exact wallet and stock restoration;
14. schema-2 economy migration;
15. Trade Studio forms, selectors, NPC bindings and source parsing;
16. malformed currency, merchant, stock and profile rejection.

Run the same gate locally:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

## Future extensions

The current contracts are designed to support later additions without replacing authored content:

- merchant transaction dialogue and portrait presentation;
- multiple quantities and quantity selectors;
- limited restocking schedules;
- regional prices and scarcity;
- quest-, era- and reputation-driven discounts;
- service purchases such as healing, repair or transport;
- buyback history;
- equipment durability and repair;
- ammunition and ranged-weapon stock;
- economic telemetry and automated affordability analysis;
- campaign-wide progression-order and softlock probes.

Every extension should preserve the same rule: editor, validator, runtime, story and save systems consume one shared durable economy contract.
