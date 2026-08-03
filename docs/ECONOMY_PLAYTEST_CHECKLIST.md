# Merchant, Economy and Regional Supply Manual Playtest Checklist

Use this checklist after the automated Godot 4.6.2 gate passes. It covers player-facing presentation, controller flow, transaction reliability, balance, durable restoration, regional supply and scarcity decisions that headless tests cannot fully judge.

## Setup

- Pull the latest `main` branch.
- Open `project.godot` in Godot 4.6.2.
- Confirm the toolbar includes **Trade**, **State**, **Package** and **Audit**.
- Run the complete PowerShell validation script.
- Start a new reference campaign.
- Keep one disposable manual slot for restoration tests.
- Record the exact commit SHA used for the session.

## Trade Studio editor

- Open **Trade** and select the reference campaign.
- Confirm Archive Chits appears once.
- Confirm Bellweather Provisions and Underworks Exchange appear once each.
- Confirm every stock line remains a complete JSON object.
- Confirm `restock_quantity` and `restock_target` remain visible on renewable entries.
- Confirm **Supply Routes** contains Bellweather Museum Route and Underworks Salvage Route.
- Confirm Bellweather uses a 180-second interval and four catch-up cycles.
- Confirm Underworks uses a 300-second interval and three catch-up cycles.
- Confirm each merchant selects the correct route.
- Confirm the route selector also supports static stock.
- Enter malformed route or stock JSON and confirm the write is rejected and rolled back.
- Attempt to delete a route while a merchant uses it and confirm deletion is blocked.
- Confirm validation identifies the exact route, merchant or stock item.

## Reference stock contract

Confirm renewable entries are exactly:

- Museum Tonic: +1 toward 3;
- Brass Filings: +2 toward 10;
- Ember Salve: +1 toward 1;
- Archive Bolts: +8 toward 24;
- Ashen Resin: +1 toward 4.

Confirm these remain finite and non-renewable:

- Museum Flashlight;
- Clockglass Fragment;
- Underworks Salvager Wrap;
- Clockglass Dartcaster;
- Clockglass Lens and Archivist Lens.

## Bellweather merchant presentation

- Start a new journey and confirm the HUD shows `AC 60`.
- Open Bellweather Provisions.
- Confirm the merchant name, wallet, Buy and Sell labels are legible.
- Confirm the route line names Bellweather Museum Route.
- Confirm the next supply countdown is readable and does not overlap item details.
- Confirm finite quantities remain visible.
- Confirm the selected row has a marker independent of colour.
- Confirm gameplay, enemies and Morrow pause while trade is open.
- Confirm closing trade restores gameplay without opening another menu underneath.

## Keyboard and controller navigation

- Open trade with keyboard and controller.
- Switch Buy and Sell with Left and Right.
- Move through all rows with Up and Down.
- Confirm selection wraps predictably.
- Confirm all supported confirmation actions execute one transaction.
- Confirm rapid repeat input does not duplicate a transaction.
- Close with Cancel and the Field Satchel action.
- Confirm no gameplay input leaks through while the overlay is open.

## Atomic purchase and sale

- Buy one Museum Tonic.
- Confirm wallet decreases by 18 AC.
- Confirm inventory increases by one.
- Confirm stock decreases by one.
- Fill the tonic stack and confirm another purchase fails without changing wallet or stock.
- Attempt a purchase without enough currency and confirm no state changes.
- Sell an accepted item and confirm inventory, wallet and resold merchant stock all change exactly once.
- Attempt to sell equipped gear and confirm it remains owned and equipped.
- Attempt a sale that would exceed `max_balance` and confirm the item is not removed.

## Regional supply and scarcity

### First Bellweather cycle

- Deplete at least one Museum Tonic, Brass Filings and Archive Bolts.
- Continue active gameplay until the 180-second Bellweather boundary is crossed.
- Reopen Bellweather Provisions.
- Confirm the expected quantities were added once.
- Confirm no item exceeds its authored target.
- Confirm the delivery message reports the total units added.
- Close and reopen immediately and confirm the same cycle does not deliver again.

### Independent Underworks interval

- Deplete Ashen Resin.
- Cross 180 seconds but remain below 300 seconds since the relevant origin.
- Confirm Bellweather may replenish while Underworks does not.
- Cross the 300-second Underworks boundary.
- Confirm Ashen Resin increases by one toward four.
- Confirm Clockglass Fragments remain unchanged.

### Target caps

- Leave a renewable entry one unit below target.
- Cross several cycles.
- Confirm it stops exactly at target.
- Buy one unit after the cycles are consumed.
- Confirm the prior cycles do not replay immediately.

### Full-stock cycle

- Fill every Bellweather renewable entry to its target.
- Save shortly before the next Bellweather boundary.
- Cross the boundary without buying anything.
- Confirm quantities remain unchanged.
- Save and reload.
- Buy an item.
- Confirm the already-consumed full-stock cycle does not deliver after reload.

### Bounded catch-up

- Use a disposable save or editor-assisted play-time state to create more elapsed cycles than a route permits.
- Confirm Bellweather applies at most four replenishment cycles.
- Confirm Underworks applies at most three replenishment cycles.
- Confirm excess cycles are discarded rather than queued.
- Save and reload.
- Confirm discarded cycles do not reappear.

### No offline restocking

- Save with depleted renewable stock.
- Close the game for several minutes.
- Reopen without adding active gameplay time.
- Confirm stock does not change.
- Change the operating-system clock in a disposable test environment.
- Confirm the game still does not grant stock.

### Progression equipment scarcity

- Purchase or deplete Museum Flashlight, Salvager Wrap and Clockglass Dartcaster in a disposable profile.
- Cross several supply cycles.
- Confirm progression equipment does not return automatically.
- Deplete conditional Clockglass Fragment stock.
- Confirm it does not replenish through Underworks supply.
- Verify another authored progression route remains available where the campaign requires one.

## Old save compatibility

Using a backed-up current-schema old save created before regional supply fields existed:

- Load through the normal Continue or Load flow.
- Confirm wallet and merchant stock restore exactly.
- Confirm no historical supply delivery occurs.
- Confirm the route cursor begins at the cycle derived from saved active play time.
- Save normally.
- Inspect the new profile and confirm `supply_region_cycles` and `supply_regions_initialized` are present.
- Reload and confirm no duplicate delivery occurs.

## Save and reload exactness

- Perform a purchase and cross one supply boundary.
- Record wallet, stock and route countdown.
- Save to a manual slot.
- Perform more transactions and cross another boundary.
- Reload the manual slot.
- Confirm wallet and stock return exactly.
- Confirm the saved route cursor returns exactly.
- Confirm the already-recorded delivery is not repeated.
- Confirm map, era, player, Morrow, quests, equipment, ammunition, boss and cinematic state still restore correctly.

## State Studio inspection

- Open **State** and select a supply-aware profile.
- Confirm Overview displays **REGIONAL SUPPLY** and initialisation state.
- Open **Supply Cycles**.
- Confirm both route IDs appear.
- Confirm saved and current cycle numbers are shown.
- Confirm time until next active-gameplay cycle is shown.
- Confirm Raw JSON contains `supply_region_cycles` and `supply_regions_initialized`.
- Validate the selected profile and confirm zero errors.
- Test an invalid copy with an unknown route and confirm validation rejects it.
- Test a cycle greater than the saved play-time-derived current cycle and confirm rejection.

## Package and installation

- Export the reference campaign.
- Inspect the package manifest and hashes.
- Install into a clean test root.
- Confirm the installed campaign retains both supply routes and all five renewable entries.
- Modify a disposable package so a renewable equipment entry or unknown route remains hash-valid.
- Confirm staged installation rejects it before promotion.
- Confirm a failed replacement restores the previous installed campaign.

## Audit Studio

- Run the reference audit twice.
- Confirm both JSON exports are identical.
- Confirm the report still exposes all eight production probes.
- Confirm metrics show two supply regions and five renewable stock entries.
- Confirm malformed supply data produces `supply.invalid` blockers.
- Confirm review-only supply concerns produce `supply.review` warnings.
- Confirm no automation responds by making every item unlimited or renewable.

## Merchant availability and conditional stock

- Equip Museum Flashlight and open Underworks Exchange.
- Replace it with a tool that does not grant illumination and confirm the exchange remains blocked.
- Start **The Missing Hour** and confirm Clockglass Fragment becomes visible.
- Change the quest state and confirm hidden stock cannot be bought through stale selection.
- Confirm supply timing does not bypass merchant or stock conditions.

## Progression and affordability

- Complete the available reference progression without editor cheats.
- Confirm starting 60 AC supports at least one meaningful preparation choice.
- Confirm the player can earn currency before mandatory purchases.
- Spend currency on optional goods and verify a reasonable recovery route remains.
- Confirm renewable recovery stock does not remove all scarcity pressure.
- Confirm progression equipment prices still matter because those items do not restock.
- Confirm selling ordinary finds cannot create a repeatable buy-sell profit loop.

## Backup recovery

- Produce a primary and backup supply-aware save.
- Corrupt the primary in a disposable test environment.
- Load the slot.
- Confirm backup recovery restores wallet, merchant stock and supply cursors from one coherent profile.
- Confirm no route combines a primary cursor with backup stock.
- Confirm the recovered profile can be promoted safely on the next normal save.

## Stress and boundary testing

- Cross a supply boundary while moving between maps.
- Cross a boundary immediately before opening a merchant.
- Close trade during delivery feedback.
- Save immediately after closing trade.
- Trigger an autosave request from another durable event at the same time.
- Pause at a boundary and confirm paused time does not create extra gameplay time.
- Open Options, State, Journal and Field Satchel near a boundary and confirm blocking interfaces remain safe.
- Confirm no negative stock, duplicated items, repeated cycles or stuck overlays occur.

## Accessibility and presentation

- Review at the base viewport and 1280×720.
- Confirm route name and countdown use text, not colour alone.
- Confirm **SCARCE STOCK** remains distinguishable.
- Confirm delivery feedback remains visible long enough to read.
- Confirm long route and item names do not overlap.
- Confirm keyboard and controller can reach every Trade and State action.
- Confirm high-contrast settings preserve stock and route readability.

## Failure reporting

Record:

- commit SHA;
- campaign and slot;
- map and era;
- merchant and route IDs;
- saved and current cycle values;
- active play time;
- wallet, inventory and stock before and after;
- exact input sequence;
- screenshots or recordings for presentation defects;
- Godot output and validation logs.

Do not patch a supply defect only in JSON or only in runtime. Correct the shared catalogue, deterministic model, validator, save contract, authoring tools, package path, audit and executable regression together.
