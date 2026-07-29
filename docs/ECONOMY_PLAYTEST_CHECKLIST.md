# Merchant & Economy Manual Playtest Checklist

Use this checklist after the automated Godot 4.6.2 gate passes. It covers player-facing presentation, controller flow, transaction reliability, balance, progression safety and durable restoration that headless tests cannot fully judge.

## Setup

- Pull the latest `main` branch.
- Open `project.godot` in Godot 4.6.2.
- Confirm the editor toolbar includes **Trade**.
- Run the complete PowerShell validation script before manual play.
- Start a new reference campaign rather than relying only on an older save.
- Keep a separate manual slot available for transaction restoration tests.

## Trade Studio editor

- Open the **Trade** tab.
- Confirm the reference campaign loads automatically.
- Confirm Archive Chits appears once in Currencies.
- Confirm Bellweather Provisions and Underworks Exchange appear once each in Merchants.
- Confirm currency name, symbol, starting balance and maximum balance populate correctly.
- Confirm each merchant retains the authored transaction currency.
- Confirm merchant greetings and farewells remain readable at the editor’s normal width.
- Confirm buy and sell multipliers show the authored values.
- Confirm accepted kinds and refused items round-trip without reordering important source data.
- Confirm every stock JSON line remains a complete object.
- Confirm Bellweather Provisions shows four stock entries.
- Confirm Underworks Exchange shows three stock entries.
- Confirm the NPC Bindings tab shows the Lost Archivist and both merchant NPC definitions.
- Confirm the provisioner and salvager bindings select the correct merchants.
- Enter malformed stock JSON and confirm the editor rejects it without modifying the catalogue.
- Attempt to delete Archive Chits while merchants use it and confirm deletion is blocked.
- Attempt to delete a bound merchant and confirm deletion is blocked.
- Clear a binding, validate, then undo the test change before committing anything.
- Confirm validation feedback remains readable and identifies the exact record.

## New-campaign scaffolding

Create a disposable campaign through Campaign Studio.

- Confirm `economy/core.json` is created.
- Confirm `campaign.json` declares `economy_files`.
- Confirm the default currency loads in Trade Studio.
- Confirm the default merchant loads in Trade Studio.
- Confirm its starter stock references existing default Item Forge items.
- Confirm the new campaign passes complete validation without manual JSON repair.
- Delete the disposable campaign after inspection.

## Bellweather Provisions presentation

Start a new reference journey.

- Confirm the HUD shows `AC 60`.
- Confirm the currency readout does not obscure health, companion, shard, map or era information.
- Approach the Bellweather Provisioner in Verdant Bellweather.
- Confirm the merchant NPC is visually distinct enough from the Lost Archivist.
- Interact and confirm the trade overlay opens rather than ordinary one-line dialogue.
- Confirm world movement, enemies and Morrow pause while trade is open.
- Confirm the merchant title, wallet, Buy and Sell labels are legible.
- Confirm the selected row has a clear marker independent of colour.
- Confirm finite stock quantities are visible.
- Confirm the selected item’s description, kind, price and owned quantity are visible.
- Close the overlay and confirm the farewell appears long enough to read.
- Shift to Ashen Bellweather and confirm the same persistent merchant remains available.

## Keyboard navigation

- Open Bellweather Provisions using E or Z.
- Use Left and Right to switch Buy and Sell.
- Use Up and Down to move through every visible entry.
- Confirm selection wraps predictably at the first and last row.
- Confirm a long list scrolls while keeping the selected row visible.
- Confirm E, Z, Space and C all activate the selected transaction as intended.
- Confirm Escape closes the merchant.
- Confirm I also closes the merchant without opening Field Satchel beneath it.
- Confirm no gameplay input leaks through while the overlay is open.

## Controller navigation

- Open the merchant with the South face button.
- Switch Buy and Sell with D-pad Left and Right.
- Select entries with D-pad Up and Down.
- Confirm with South or East face button.
- Close with the controller cancel or Field Satchel action.
- Confirm the selected row and current mode remain understandable from normal viewing distance.
- Confirm rapid repeated inputs do not execute duplicate transactions unexpectedly.

## Valid purchase

At Bellweather Provisions:

- Record the starting wallet, Museum Tonic quantity and merchant tonic stock.
- Buy one Museum Tonic.
- Confirm the wallet decreases by exactly 18 AC.
- Confirm inventory increases by exactly one.
- Confirm finite merchant stock decreases by exactly one.
- Confirm the transaction message names the item and complete price.
- Close and reopen the merchant.
- Confirm the new wallet, inventory and stock values remain visible.

## Stack-capacity rejection

- Fill Museum Tonic to its authored stack limit.
- Attempt to buy another tonic.
- Confirm the message explains that the stack cannot hold another.
- Confirm no currency is removed.
- Confirm merchant stock does not change.
- Confirm inventory does not exceed its stack limit.
- Repeat the attempt quickly and confirm state remains unchanged.

## Insufficient-funds rejection

- Spend or edit a test profile until the wallet contains less than the selected price.
- Attempt a purchase.
- Confirm the message explains insufficient currency.
- Confirm stock and inventory do not change.
- Confirm the wallet does not become negative.

## Finite stock depletion

- Purchase every available unit of a finite stock item.
- Confirm stock reaches zero and the item disappears or becomes clearly unavailable.
- Close and reopen the merchant.
- Confirm depleted stock remains depleted.
- Change era and return.
- Confirm depleted stock remains depleted.
- Save and reload.
- Confirm depleted stock remains depleted.

## Sale flow

- Switch to Sell mode.
- Confirm only items accepted by the current merchant are listed.
- Confirm key progression items do not appear when refused.
- Sell one Museum Tonic.
- Confirm inventory decreases by exactly one.
- Confirm the wallet increases by exactly the authored sell price.
- Confirm merchant stock increases because Bellweather Provisions resells player goods.
- Switch to Buy and confirm the sold item is available in the updated stock.

## Equipped-item protection

- Keep Brass Hook equipped.
- Open Sell mode.
- Confirm Brass Hook is absent from the sellable list, or a direct attempted sale is rejected.
- Confirm a clear equipped-item warning is shown where relevant.
- Confirm the item remains equipped and owned.
- Unequip Brass Hook through Field Satchel.
- Reopen the merchant and confirm it can now be sold if the merchant accepts it.
- Do not leave the reference save without restoring the intended loadout.

## Progression-item protection

- Obtain or inject Clockglass Lens and Archivist Lens in a test profile.
- Confirm Bellweather Provisions refuses both.
- Confirm Underworks Exchange refuses both.
- Confirm the refusal is based on stable item ID rather than display name.
- Confirm quest and capability progression cannot be broken by selling these tools.

## Wallet-capacity rejection

- Create a test profile whose Archive Chits balance is close to `max_balance`.
- Attempt to sell an item whose complete payment would exceed the maximum.
- Confirm the sale is rejected before item removal.
- Confirm the wallet does not exceed its maximum.
- Confirm inventory remains unchanged.

## Underworks Exchange availability

- Equip Museum Flashlight.
- Enter Museum Underworks.
- Approach the Underworks Salvager.
- Confirm the exchange opens while Illuminate Darkness is active.
- Close trade.
- Equip Archivist Lens in the shared Tool slot.
- Confirm Illuminate Darkness is no longer active.
- Attempt to open the exchange.
- Confirm the merchant remains unavailable and explains the missing light requirement.
- Re-equip Museum Flashlight and confirm trade opens again.
- Confirm failure does not open an empty or partially interactive overlay.

## Conditional stock

- Start **The Missing Hour**.
- Open Underworks Exchange with the flashlight equipped.
- Confirm Clockglass Fragment appears while the quest is active.
- Complete or leave the relevant quest state in a controlled test profile.
- Confirm stock visibility updates according to its condition.
- Confirm hidden stock cannot be bought through stale selection indices.

## Equipment purchase and trade-off

- Accumulate enough Archive Chits for Underworks Salvager Wrap.
- Purchase the wrap.
- Confirm the item enters inventory and merchant stock reaches zero.
- Equip it in the Body slot.
- Confirm defence and movement speed update immediately.
- Confirm maximum health changes according to the active coat trade-off.
- Compare against Museum Field Coat in actual movement and combat.
- Confirm the wrap feels like a distinct choice rather than an unconditional upgrade.

## Quest currency reward

- Begin **Quiet the Ash Hunt**.
- Record the current Archive Chits balance.
- Clear East Ash Hunt.
- Confirm the quest completes.
- Confirm 12 Archive Chits are granted once.
- Confirm the existing item and clock-shard rewards still occur.
- Reevaluate the completed quest or travel away and back.
- Confirm the currency reward cannot duplicate.

## Save schema 3

- Perform at least one purchase and one sale.
- Save to a manual slot.
- Record wallet and both merchants’ stock.
- Change wallet and stock through further transactions.
- Load the manual slot.
- Confirm exact wallet restoration.
- Confirm exact finite merchant stock restoration.
- Confirm dynamically resold stock restores.
- Confirm inventory, equipment, quests, companion state, map and era also restore as before.
- Confirm the merchant overlay is closed after load.

## Schema-2 migration

Using a backed-up schema-2 test profile:

- Load the profile through the normal Continue or Load flow.
- Confirm migration succeeds.
- Confirm campaign-authored starting wallet is applied once.
- Confirm initial merchant stock is applied once.
- Save the migrated profile.
- Reload it.
- Confirm starting currency and stock are not granted again.
- Inspect it in State Studio and confirm schema 3 with a valid checksum.

## Backup recovery

- Create an economy-aware manual save.
- Make a second save to produce a backup.
- Corrupt the promoted primary profile in a disposable test environment.
- Load the slot.
- Confirm backup recovery succeeds.
- Confirm recovered wallet and stock correspond to the backup, not a mixture of primary and backup values.
- Confirm State Studio reports backup recovery.

## State Studio inspection

- Open the **State** tab.
- Select an economy-aware profile.
- Confirm Overview shows wallet and merchant record counts.
- Confirm Wallet lists Archive Chits with symbol, amount and stable ID.
- Confirm Merchant Stock lists merchant name, item name, quantity and stable item ID.
- Confirm unlimited stock is labelled distinctly if present.
- Confirm Raw JSON contains `currency_balances`, `merchant_stock` and `economy_initialized`.
- Confirm profile validation passes.
- Confirm an invalid test profile with unknown currency or merchant is rejected.

## Merchant persistence across maps and eras

- Buy an item in Verdant Bellweather.
- Shift to Ashen Bellweather and reopen the provisioner.
- Confirm the same stock state remains.
- Travel to Clockwood and return.
- Confirm state remains.
- Visit Underworks Exchange and make a separate transaction.
- Return to Bellweather.
- Confirm the two merchants retain independent stock records.

## Transaction stress

- Rapidly alternate Buy and Sell modes.
- Repeat purchase input near a stack limit.
- Repeat sale input when only one item remains.
- Close the overlay during transaction feedback.
- Open and close the merchant repeatedly.
- Shift era immediately after closing.
- Travel immediately after closing.
- Save immediately after closing.
- Confirm no negative balances, duplicated items, negative finite stock or stuck overlays occur.

## Economy balance review

Play the available reference progression without editor cheats.

- Confirm the starting 60 AC supports at least one meaningful preparation choice.
- Confirm the player can earn the Quiet the Ash Hunt reward before any required purchase.
- Confirm tonic pricing makes recovery useful without trivialising damage.
- Confirm material prices do not make crafting irrelevant.
- Confirm Clockglass Fragment availability does not bypass the intended exploration loop too cheaply.
- Confirm Salvager Wrap price feels proportional to its defensive and movement trade-off.
- Confirm selling ordinary finds is useful but cannot create an effortless buy-sell loop.
- Record any item that is never worth buying or always worth selling.

## Accessibility and presentation

- Verify text at 1280×720 and the project’s base low-resolution viewport.
- Confirm selected rows use a marker and contrast, not colour alone.
- Confirm Buy and Sell modes remain labelled.
- Confirm wallet and price symbols are distinguishable.
- Confirm finite quantities and unlimited stock are not communicated only by glyph shape.
- Confirm transaction feedback remains visible long enough to read.
- Confirm long item names and descriptions do not overlap prices or quantities.
- Confirm every action is reachable by keyboard and controller.

## Failure reporting

For every defect, record:

- campaign and save slot;
- map and era;
- merchant ID;
- selected mode and item ID;
- wallet before and after;
- inventory before and after;
- stock before and after;
- input device;
- exact reproduction sequence;
- screenshot or recording where presentation is involved;
- relevant Godot output and validation logs.

Do not patch a balance or transaction defect only in the runtime. Correct the shared catalogue, model, validator, editor and executable test contract together.
