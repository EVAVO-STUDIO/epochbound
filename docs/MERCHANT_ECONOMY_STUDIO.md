# Epochbound Merchant, Economy and Supply Studio

Merchant, Economy and Supply Studio is the campaign-authoring layer for currencies, merchant inventories, pricing, availability, reusable NPC bindings, regional supply routes, scarcity and durable transaction state.

It does not create a parallel item database or a second economy clock. Every traded good is an Item Forge item, every availability rule uses Story Studio conditions, every equipment restriction uses Loadout Studio ownership, and every supply cycle uses the same durable gameplay time already stored in save metadata.

## Responsibilities

- **Item Forge** defines items, stack limits, baseline values and item kinds.
- **Loadout Studio** defines equipment slots, modifiers and capabilities.
- **Story Studio** defines typed currency, item, quest and capability conditions and effects.
- **Trade Studio** defines currencies, merchants, stock, prices, sale rules, NPC bindings and supply routes.
- **State Studio** inspects wallets, stock and saved regional supply cursors.
- **Package Studio** validates the complete economy and supply contract before export or installation.
- **Campaign Audit Studio** reports progression, affordability and regional supply evidence.

All systems consume the same source-controlled campaign records.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Trade** main-screen tab.
3. Choose a campaign.
4. Create or inspect currencies.
5. Create or inspect merchants.
6. Choose each merchant's transaction currency.
7. Configure buy and sell multipliers, accepted item kinds and refused item IDs.
8. Author finite or unlimited stock entries as complete JSON-line records.
9. Open **Supply Routes** and create the campaign's deterministic regional routes.
10. Configure each route's interval and maximum catch-up cycles.
11. Return to **Merchants** and assign an optional supply route.
12. Add replenishment amounts and targets only to appropriate finite stock records.
13. Bind each merchant to at least one placed reusable NPC definition.
14. Validate the complete campaign.
15. Run the reference route, exhaust stock, cross supply cycles, save, reload and review State Studio.

Trade Studio snapshots the current economy catalogue before every write. A change that fails complete economy and supply validation is restored on disk and in the editor.

## Economy catalogue

Campaigns declare economy files in `campaign.json`:

```json
{
  "economy_files": [
    "economy/core.json"
  ]
}
```

An economy catalogue may contain currencies, supply regions and merchants:

```json
{
  "schema_version": 1,
  "currencies": [],
  "supply_regions": [],
  "merchants": []
}
```

Multiple files may be declared. Currency, supply-route and merchant IDs must remain unique across the complete campaign.

## Currency contract

```json
{
  "id": "archive_chits",
  "display_name": "Archive Chits",
  "symbol": "AC",
  "starting_balance": 60,
  "max_balance": 999999
}
```

`id` is the durable reference used by merchants, Story Studio, wallets and save profiles. Display names and symbols may change without changing saved identity.

`starting_balance` applies once when a new economy is created or when a compatible pre-economy profile explicitly says that economy defaults have not yet been applied.

`max_balance` defines the wallet-capacity check. A sale that cannot fit its complete payment fails before inventory is removed. Partial payment is never allowed.

## Merchant contract

```json
{
  "id": "bellweather_provisions",
  "display_name": "Bellweather Provisions",
  "currency_id": "archive_chits",
  "supply_region_id": "bellweather_route",
  "greeting": "The museum till still remembers honest prices.",
  "farewell": "Bring back anything the hours have not claimed.",
  "buy_multiplier": 1.0,
  "sell_multiplier": 0.5,
  "accepts_sales": true,
  "accepted_kinds": [
    "consumable",
    "material",
    "equipment",
    "ammunition"
  ],
  "refused_items": [
    "clockglass_lens",
    "archivist_lens"
  ],
  "resell_player_goods": true,
  "conditions": [],
  "stock": []
}
```

### Prices

When a stock record has no positive `buy_price`, the runtime resolves:

```text
buy price = ceil(item value × buy multiplier)
```

When a stock record has no positive `sell_price`, the runtime resolves:

```text
sell price = floor(item value × sell multiplier)
```

A positive item value resolves to at least one unit. Negative overrides are rejected. The validator warns about buy-and-sell relationships that may create trivial profit loops.

### Accepted and refused items

`accepted_kinds` uses Item Forge kinds. `refused_items` overrides the kind list for specific stable IDs.

The reference merchants refuse the Clockglass Lens and Archivist Lens so narrative and capability tools cannot be sold accidentally.

Currently equipped items are protected from sale. The player must unequip them through the Field Satchel before a merchant can accept them.

### Reselling player goods

When `resell_player_goods` is true, a successful sale becomes durable merchant stock. Existing finite stock increases; an accepted item not originally stocked can become a dynamic stock entry.

When false, the sold item leaves the active economy after payment.

## Stock entries

### Finite stock

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

Purchasing decrements finite stock. Selling compatible goods back may increase it. The exact quantity persists in save profiles.

### Unlimited stock

```json
{
  "item_id": "basic_supply",
  "quantity": 1,
  "unlimited": true,
  "buy_price": 4,
  "conditions": []
}
```

Runtime state represents unlimited stock as `-1`. Purchases never decrement it. Unlimited stock cannot define replenishment fields because it already has no scarcity.

### Conditions

Merchant and stock conditions use the complete Story Studio condition set, including item ownership, durable state, quests, map, era, active capabilities, clock shards and currency balances.

The reference Underworks Exchange requires `illuminate_dark`. Clockglass Fragments appear only while **The Missing Hour** is active.

## Supply routes and scarcity

A supply route is a deterministic campaign-authored replenishment clock shared by one or more merchants.

```json
{
  "id": "bellweather_route",
  "display_name": "Bellweather Museum Route",
  "restock_interval_seconds": 180,
  "max_catchup_cycles": 4
}
```

### Stable route ID

`id` is saved in the merchant record and used as the key in `supply_region_cycles`. Renaming the display name is safe; changing the ID is a save-data migration.

### Restock interval

`restock_interval_seconds` must be between 30 seconds and 24 hours.

The cycle is calculated from durable `play_time_seconds`:

```text
current cycle = floor(play_time_seconds / restock_interval_seconds)
```

The system never uses wall-clock time, operating-system time or time spent while the game is closed.

### Bounded catch-up

`max_catchup_cycles` limits how many elapsed cycles can add stock during one catch-up operation. It must be between 1 and 32.

When more cycles elapsed than the limit:

1. only the bounded number contributes replenishment;
2. excess cycles are intentionally discarded;
3. the saved cursor still advances to the current cycle;
4. reloading cannot replay the discarded or already-consumed cycles.

This prevents extreme stock floods after long unattended sessions while keeping the result deterministic.

### No offline windfalls

Regional supply is based only on active durable gameplay time. Closing the game for a day, changing the system clock or loading a profile on another machine does not create stock.

### Full-stock cycles

An elapsed cycle is consumed even when every renewable entry is already at its target. The cycle cursor changes and is saved, while item quantities remain unchanged.

This prevents a player from waiting at full stock, purchasing immediately after the boundary and then reloading to replay an unrecorded delivery.

## Renewable stock

A finite stock entry becomes renewable only when it declares both a positive replenishment amount and target:

```json
{
  "item_id": "archive_bolts",
  "quantity": 24,
  "unlimited": false,
  "buy_price": 3,
  "sell_price": 1,
  "restock_quantity": 8,
  "restock_target": 24,
  "conditions": []
}
```

For each applied cycle:

```text
new quantity = min(restock_target, current quantity + restock_quantity)
```

`restock_target` cannot be below the authored initial quantity. The target is a cap, not a guaranteed minimum after every transaction.

### Allowed renewable kinds

Automatic replenishment is restricted to:

- consumables;
- materials;
- ammunition.

Equipment and key items remain scarce. This preserves loadout decisions, unique tools and progression safety.

### Progression scarcity

A stock record without replenishment fields remains finite even when its merchant belongs to a supply route.

The reference campaign deliberately keeps these scarce:

- Museum Flashlight;
- Clockglass Fragments;
- Underworks Salvager Wrap;
- Clockglass Dartcaster;
- narrative and capability lenses.

Regional supply supports recovery and combat preparation without converting progression equipment into infinitely renewable inventory.

## Reference routes

### Bellweather Museum Route

Interval: 180 seconds. Maximum catch-up: four cycles.

Renewable stock:

- Museum Tonic: +1 toward 3;
- Brass Filings: +2 toward 10;
- Ember Salve: +1 toward 1;
- Archive Bolts: +8 toward 24.

Museum Flashlight remains scarce.

### Underworks Salvage Route

Interval: 300 seconds. Maximum catch-up: three cycles.

Renewable stock:

- Ashen Resin: +1 toward 4.

Clockglass Fragments, Salvager Wrap and Clockglass Dartcaster remain scarce.

## Runtime trade flow

Interacting with a valid merchant pauses gameplay and opens the trade overlay.

| Action | Keyboard or controller |
| --- | --- |
| Change Buy or Sell | Left / Right |
| Change selected row | Up / Down |
| Buy or sell one | Confirm or Attack |
| Close | Cancel or Field Satchel |

The overlay shows merchant, wallet, mode, price, owned quantity, stock and transaction feedback. Supply-aware merchants also show the route name and time until the next active-gameplay cycle. A merchant with a route but no renewable entries is labelled **SCARCE STOCK**.

Before a merchant opens, any due cycle is applied to authoritative stock. A delivery that adds goods reports the number of units delivered. Supply checks never run inside custom drawing, so rendering cannot mutate economy state.

## Atomic transactions

A purchase confirms merchant availability, stock conditions, quantity, stack capacity and wallet balance before changing state. Currency removal is rolled back if item insertion fails.

A sale confirms ownership, equipment safety, merchant acceptance, complete payment and wallet capacity before changing state. Item removal is rolled back if payment insertion fails.

No failed transaction can partially change wallet, inventory or stock.

## NPC merchant bindings

Reusable NPC definitions may declare:

```json
{
  "id": "museum_provisioner",
  "kind": "npc",
  "merchant_id": "bellweather_provisions"
}
```

Map placements reference the reusable NPC definition. A merchant can therefore appear in several maps or eras while sharing one durable stock and supply contract.

Trade Studio blocks deletion of a supply route while any merchant still references it. The validator warns about merchants that are not bound to a reusable NPC.

## Durable save state

The current save schema remains compatible and carries additive supply fields in the signed payload:

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
  "economy_initialized": true,
  "supply_region_cycles": {
    "bellweather_route": 5,
    "underworks_route": 3
  },
  "supply_regions_initialized": true
}
```

The profile checksum covers the exact route cursors. A cursor cannot be negative, reference an unknown route or exceed the cycle derived from saved `play_time_seconds`.

Supply cursor changes are durable progress even when no stock was added. They participate in the runtime fingerprint and request autosave through the existing save policy.

## Old-save compatibility

A valid current-schema profile created before regional supply does not contain supply fields.

On load:

1. normal economy balances and merchant stock restore exactly;
2. each supply route initialises at the cycle derived from saved `play_time_seconds`;
3. no historical cycles are replayed;
4. no retroactive stock is granted;
5. the next normal save writes complete route cursors.

This is an additive compatibility path, not an inferred wall-clock migration.

## Save and State Studio

State Studio includes:

- **Wallet**;
- **Merchant Stock**;
- **Supply Cycles**;
- overview counts and initialisation state;
- exact saved and current cycle values;
- time until the next active-gameplay cycle;
- complete signed raw JSON;
- complete campaign and profile validation.

This makes route cursor behaviour inspectable without editing save files.

## Package and Audit integration

Package Studio validates the complete final content chain before export. Campaign installation validates the staged package again before promotion. A hash-valid archive with an unknown route, illegal replenishment kind or malformed target is rejected.

Campaign Audit Studio preserves its eight production probes and adds bounded evidence metrics:

- supply-region count;
- renewable-stock count.

Supply validation errors become `supply.invalid` blockers. Review warnings become `supply.review` findings. These findings do not grant permission to make every stock item renewable or unlimited.

## Validation rules

Regional supply validation rejects:

- unsafe or duplicate economy files;
- invalid or duplicate supply-route IDs;
- missing or overlong route names;
- intervals outside 30 to 86,400 seconds;
- catch-up limits outside 1 to 32;
- merchants referencing unknown routes;
- replenishment on unlimited stock;
- negative or oversized replenishment values;
- targets below initial quantities;
- positive replenishment without a positive target;
- renewable stock without a merchant route;
- automatic replenishment of equipment or key items;
- unknown, future or missing saved route cursors after initialisation.

It warns about:

- a merchant assigned to a route with no renewable entries;
- a target that has no effect because replenishment is zero;
- long routes with only one catch-up cycle;
- stale cursor data on a profile still marked uninitialised.

## Automated verification

The permanent Godot 4.6.2 suite verifies:

1. supply catalogue, validator, model, runtime and editor compilation;
2. two reference routes and five renewable entries;
3. separate route intervals;
4. deterministic replenishment amounts;
5. target caps;
6. bounded catch-up and discarded excess cycles;
7. idempotence within one cycle;
8. full-stock cursor advancement;
9. scarce equipment and progression stock;
10. exact save capture and reload without duplicate delivery;
11. old-save initialisation without retroactive stock;
12. malformed routes, kinds, targets and saved cursors;
13. Trade Studio route authoring and rollback;
14. State Studio supply inspection;
15. Package installation validation;
16. Audit metrics and deterministic JSON export.

The fail-closed static contract also verifies that the local gate, primary main-push workflow, focused Audio workflow and focused Sprite workflow retain the complete supply integration.

## Production rules

- Use active `play_time_seconds`, never wall-clock time.
- Consume every elapsed cycle exactly once, including full-stock cycles.
- Bound catch-up and discard excess cycles deliberately.
- Save route cursors atomically with merchant stock.
- Initialise old saves at their current cycle with no historical delivery.
- Replenish recovery goods and ammunition, not progression equipment.
- Keep targets finite and explain scarcity through stock counts and route text.
- Do not hide required progression behind an exhausted finite source without another authored route.
- Do not silence audit findings by making all stock unlimited.
- Test wallet pressure, optional spending and recovery routes by hand in addition to deterministic automation.
