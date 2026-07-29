# Arsenal Runtime and Studio Playtest Checklist

Use this checklist after automated validation and before treating a ranged-combat slice as production ready. Record the Godot build, operating system, input device, campaign commit and save schema used for the pass.

## Test record

```text
Tester:
Date:
Godot version:
Operating system:
Keyboard/controller:
Campaign commit:
Save schema:
Display resolution:
Notes:
```

## Editor registration

- [ ] Open `project.godot` in Godot 4.6.2.
- [ ] Confirm the top toolbar includes `Arsenal`.
- [ ] Confirm Campaign, Encounter, Combat, Companion, Items, Story, State, Loadout and Trade remain available.
- [ ] Open Arsenal Studio without parser or plugin errors.
- [ ] Change to every other main-screen editor and return to Arsenal Studio.
- [ ] Close and reopen the project; confirm the plugin remains enabled.

## Campaign discovery

- [ ] Confirm Arsenal Studio discovers the reference campaign.
- [ ] Confirm the campaign selector remains stable after editor resource rescans.
- [ ] Create a new campaign through Campaign Studio.
- [ ] Open the new campaign in Arsenal Studio.
- [ ] Confirm an empty or starter Arsenal configuration is editable without JSON repair.
- [ ] Validate the new campaign and review warnings.

## Ammunition authoring

- [ ] Select Archive Bolts.
- [ ] Confirm the stable ID is unchanged.
- [ ] Confirm display name, description, stack limit and economy value are correct.
- [ ] Confirm damage and knockback bonuses are correct.
- [ ] Confirm projectile colour is valid.
- [ ] Create a temporary ammunition item with a valid stable ID.
- [ ] Confirm it appears in Item Forge and Arsenal Studio.
- [ ] Confirm it appears as an option for ranged weapons.
- [ ] Attempt to set stack limit to one; confirm validation rejects it.
- [ ] Attempt to set a negative damage bonus; confirm validation rejects it.
- [ ] Attempt to set excessive knockback; confirm validation rejects it.
- [ ] Attempt to enter an invalid colour; confirm the editor or validator rejects it.
- [ ] Delete the unused temporary ammunition item successfully.

## Ammunition reference safety

- [ ] Create a temporary ranged weapon that references temporary ammunition.
- [ ] Attempt to delete the referenced ammunition.
- [ ] Confirm deletion is blocked with an actionable reference message.
- [ ] Change the weapon to another ammunition item.
- [ ] Confirm the old ammunition can then be deleted.
- [ ] Confirm Item Forge also blocks unsafe deletion through the same stable reference.

## Ranged weapon authoring

- [ ] Select Clockglass Dartcaster.
- [ ] Confirm it uses the Weapon slot.
- [ ] Confirm Archive Bolts are selected.
- [ ] Confirm magazine size is four.
- [ ] Confirm projectile speed, range and radius match authored values.
- [ ] Confirm fire cooldown and reload time match authored values.
- [ ] Confirm weapon and ammunition bonuses are shown separately in source data.
- [ ] Confirm muzzle offset and projectile colour are correct.
- [ ] Create a temporary ranged weapon.
- [ ] Save and reload the editor; confirm its profile persists.
- [ ] Change its ammunition reference and validate.
- [ ] Attempt to reference a consumable instead of ammunition; confirm validation rejects it.
- [ ] Attempt to use a non-Weapon equipment slot; confirm validation rejects it.
- [ ] Attempt to set magazine size to zero; confirm validation rejects it.
- [ ] Attempt to set range below a practical threshold; review the warning.
- [ ] Delete the unused temporary weapon.

## Enemy projectile authoring

- [ ] Select Underworks Sentinel.
- [ ] Confirm projectile attack is enabled.
- [ ] Confirm attack radius does not exceed projectile range.
- [ ] Confirm attack damage, cooldown and windup are visible.
- [ ] Confirm projectile speed, range, radius, knockback and colour are visible.
- [ ] Disable the ranged profile and validate a temporary copy.
- [ ] Re-enable it and confirm the authored values return.
- [ ] Attempt to set projectile speed to zero; confirm validation rejects it.
- [ ] Attempt to set attack radius beyond range; confirm validation rejects it.
- [ ] Attempt to add `ranged_attack` to a non-enemy object; confirm validation rejects it.

## Reference merchant stock

- [ ] Open Trade Studio.
- [ ] Confirm Bellweather Provisions stocks Archive Bolts.
- [ ] Confirm Underworks Exchange stocks one Clockglass Dartcaster.
- [ ] Confirm merchants accept the `ammunition` item kind where intended.
- [ ] Confirm Archive Bolt buy and sell prices are readable.
- [ ] Confirm the Dartcaster price does not create an immediate buy/sell profit.
- [ ] Confirm finite quantities appear correctly.
- [ ] Confirm merchant validation counts all stock entries.

## Acquiring the weapon

- [ ] Start a new reference journey.
- [ ] Confirm Eli starts with the Brass Hook rather than the Dartcaster.
- [ ] Confirm the Dartcaster is not silently added to the starting inventory.
- [ ] Reach Museum Underworks with Illuminate Darkness active.
- [ ] Open Underworks Exchange.
- [ ] Confirm the Dartcaster appears once.
- [ ] Buy it if the wallet can afford it, or grant test currency through a controlled fixture.
- [ ] Confirm the wallet loses the complete price.
- [ ] Confirm inventory gains exactly one Dartcaster.
- [ ] Confirm merchant stock becomes zero.
- [ ] Close and reopen the merchant; confirm stock remains zero.

## Acquiring ammunition

- [ ] Open Bellweather Provisions.
- [ ] Buy one Archive Bolt stack unit.
- [ ] Confirm wallet, inventory and stock each change exactly once.
- [ ] Buy several rounds while watching the stack count.
- [ ] Attempt to buy when the ammunition stack is full.
- [ ] Confirm the failed purchase changes neither wallet nor stock.
- [ ] Sell one reserve round.
- [ ] Confirm the merchant pays the exact sale price.
- [ ] Confirm the sold round returns to merchant stock when resale is enabled.

## Equipping ranged and melee weapons

- [ ] Open the Field Satchel.
- [ ] Select the Equipment tab.
- [ ] Equip Clockglass Dartcaster in the Weapon slot.
- [ ] Confirm the HUD switches to ammunition information.
- [ ] Equip Brass Hook again.
- [ ] Confirm the ammunition HUD disappears.
- [ ] Confirm melee attack behaviour remains unchanged.
- [ ] Re-equip the Dartcaster.
- [ ] Confirm any previously loaded magazine remains attached to the owned weapon.

## Empty-magazine behaviour

- [ ] Equip the Dartcaster with zero loaded rounds and reserve ammunition available.
- [ ] Press attack.
- [ ] Confirm no projectile appears.
- [ ] Confirm no reserve ammunition is removed immediately.
- [ ] Confirm reload begins or the player receives the intended reload prompt.
- [ ] Repeat with no reserve ammunition.
- [ ] Confirm no projectile appears and the missing-ammunition message is clear.

## Reload input

- [ ] Press G on keyboard.
- [ ] Confirm reload begins.
- [ ] Press the right trigger on controller.
- [ ] Confirm reload begins.
- [ ] Rebind reload through Godot Input Map and confirm the new binding works.
- [ ] Confirm reload cannot start on a melee weapon.
- [ ] Confirm reloading a full magazine reports that it is full.
- [ ] Confirm reloading without reserve ammunition fails clearly.

## Reload timing and transaction safety

- [ ] Record reserve and loaded counts before reload.
- [ ] Start reload.
- [ ] Confirm reserve count remains unchanged during the progress interval.
- [ ] Confirm the visual progress bar advances.
- [ ] Let reload finish.
- [ ] Confirm only the required number of rounds moves from reserve to magazine.
- [ ] Confirm a partial reserve fills only as far as available ammunition permits.
- [ ] Confirm magazine count never exceeds authored capacity.
- [ ] Start reload and switch to Brass Hook before completion.
- [ ] Confirm reload cancels.
- [ ] Confirm reserve count remains unchanged.
- [ ] Re-equip the Dartcaster and confirm loaded count remains at its pre-reload value.
- [ ] Start reload and open a blocking transition if possible.
- [ ] Confirm no partial ammunition transfer occurs.

## Player firing

- [ ] Load four rounds.
- [ ] Face an open area and fire once.
- [ ] Confirm exactly one projectile appears.
- [ ] Confirm loaded count decreases by exactly one.
- [ ] Confirm reserve count does not change.
- [ ] Confirm the projectile begins outside Eli's centre silhouette.
- [ ] Confirm it travels in the current facing direction.
- [ ] Confirm the fire cooldown prevents unintended duplicate shots.
- [ ] Fire all four rounds and confirm the magazine reaches zero, not a negative value.

## Projectile travel and collision

- [ ] Fire at an Ash Hound from within range.
- [ ] Confirm the enemy does not take damage at button press.
- [ ] Confirm damage occurs when the projectile reaches it.
- [ ] Confirm the first enemy along the line is hit.
- [ ] Confirm the projectile is removed after impact.
- [ ] Fire across blocked terrain.
- [ ] Confirm the projectile stops at the collision boundary.
- [ ] Fire at a solid prop.
- [ ] Confirm the prop blocks the projectile.
- [ ] Fire past a non-solid pickup or marker.
- [ ] Confirm it does not act as unintended cover.
- [ ] Test at low and high frame rates.
- [ ] Confirm fast projectiles do not skip through targets.
- [ ] Fire beyond maximum range.
- [ ] Confirm the projectile expires cleanly.

## Damage and feedback

- [ ] Confirm Dartcaster damage uses the current player attack baseline.
- [ ] Confirm the weapon's ranged damage bonus is applied.
- [ ] Confirm ammunition damage bonus is applied.
- [ ] Confirm enemy defence rules, if later added, are applied consistently.
- [ ] Confirm successful hits produce enemy flash, stagger and knockback.
- [ ] Confirm misses do not produce hit feedback.
- [ ] Confirm projectile colour and shape remain visible on both era palettes.
- [ ] Confirm camera shake remains proportionate to the hit.

## Melee coexistence

- [ ] Equip Brass Hook after using the Dartcaster.
- [ ] Confirm normal melee target acquisition and damage remain correct.
- [ ] Confirm melee does not consume ammunition.
- [ ] Confirm reload input does not interfere with melee attacks.
- [ ] Confirm Cut Clockvines still comes from Brass Hook.
- [ ] Confirm weapon choice creates a real traversal and combat trade-off.

## Underworks Sentinel encounter

- [ ] Enter Ashen Museum Underworks.
- [ ] Confirm Underworks Gallery Watch activates at the intended distance.
- [ ] Confirm the Sentinel remains inside its authored leash.
- [ ] Confirm it displays the existing attack windup.
- [ ] Confirm no damage occurs at windup completion until a projectile reaches the target.
- [ ] Confirm the projectile is visually distinct from the player's shot.
- [ ] Move behind valid cover and confirm the shot is blocked.
- [ ] Move out of the firing line and confirm the shot can miss.
- [ ] Let the shot hit Eli and confirm active defence reduces damage.
- [ ] Let the Sentinel target Morrow and confirm target intent remains stable in flight.
- [ ] Confirm player projectiles never harm Morrow.
- [ ] Leave the encounter leash and confirm the Sentinel returns to spawn.
- [ ] Defeat the Sentinel and confirm persistent defeat and zone-clear state.

## Era shifting and map transitions

- [ ] Fire a projectile and shift era before impact.
- [ ] Confirm transient projectiles are cleared safely.
- [ ] Start reload and shift era.
- [ ] Confirm reload cancels without consuming reserve ammunition.
- [ ] Fire a projectile and use a map transition.
- [ ] Confirm the projectile does not enter the next map.
- [ ] Return to the previous map and confirm no stale projectile remains.
- [ ] Confirm loaded magazine state persists during normal map and era travel.

## Companion behaviour

- [ ] Test Follow while using the Dartcaster.
- [ ] Test Stay while using the Dartcaster.
- [ ] Test Seek while using the Dartcaster.
- [ ] Test Guard while using the Dartcaster.
- [ ] Confirm Morrow does not block player projectiles.
- [ ] Confirm enemy projectiles aimed at Morrow do not arbitrarily retarget Eli.
- [ ] Confirm Recall remains safe during ranged encounters.
- [ ] Confirm companion recovery does not place Morrow into unavoidable projectile damage.

## Merchant sale safety

- [ ] Equip the Dartcaster and attempt to sell it.
- [ ] Confirm it is absent from the sell list or the sale is rejected.
- [ ] Unequip it while rounds remain loaded.
- [ ] Attempt to sell it again.
- [ ] Confirm the loaded weapon remains protected.
- [ ] Confirm the refusal message explains that the item is equipped or contains ammunition.
- [ ] Empty the magazine, unequip the weapon and sell it.
- [ ] Confirm the sale succeeds only then.
- [ ] Confirm no loaded rounds disappear during any rejected sale.

## Save restrictions

- [ ] Fire a projectile and attempt to open Save Profiles before it resolves.
- [ ] Confirm saving remains blocked or deferred.
- [ ] Start reload and attempt to save.
- [ ] Confirm saving remains blocked or deferred.
- [ ] Wait until combat is stable and save successfully.
- [ ] Confirm transient projectiles are not present in raw save JSON.
- [ ] Confirm reload progress is not present in raw save JSON.
- [ ] Confirm loaded magazine counts are present.

## Schema-4 save and load

- [ ] Equip the Dartcaster.
- [ ] Load exactly two rounds.
- [ ] Save to a manual slot.
- [ ] Inspect the slot in State Studio.
- [ ] Confirm Loaded Ammo shows `2 / 4` for Clockglass Dartcaster.
- [ ] Fire or reload to change the count.
- [ ] Load the saved slot.
- [ ] Confirm exactly two rounds return.
- [ ] Confirm reserve ammunition returns to the exact saved quantity.
- [ ] Confirm equipment, wallet, merchant stock, quests and world state also restore.
- [ ] Confirm no projectile or partial reload resumes.

## Schema-3 migration

- [ ] Prepare or use a validated schema-3 fixture.
- [ ] Load it through the normal save path.
- [ ] Confirm migration succeeds.
- [ ] Confirm equipment, economy and previous durable state are preserved.
- [ ] Confirm `loaded_ammo` is created as an empty dictionary.
- [ ] Confirm no loaded rounds are guessed from reserve ammunition.
- [ ] Save the migrated profile.
- [ ] Confirm it rewrites as schema 4 with a valid checksum.

## Save validation failures

- [ ] Change a loaded-magazine key to an unknown item ID.
- [ ] Confirm validation rejects it.
- [ ] Reference a melee weapon in `loaded_ammo`.
- [ ] Confirm validation rejects it.
- [ ] Remove weapon ownership while retaining its loaded-magazine record.
- [ ] Confirm validation rejects it.
- [ ] Set loaded rounds above magazine capacity.
- [ ] Confirm validation rejects it.
- [ ] Set loaded rounds to a non-numeric value.
- [ ] Confirm validation rejects it.
- [ ] Confirm a rejected profile does not partially mutate runtime state.

## State Studio inspection

- [ ] Open the State tab.
- [ ] Select an occupied schema-4 slot.
- [ ] Confirm Overview shows the loaded-magazine count.
- [ ] Confirm Loaded Ammo lists weapon name, current rounds, capacity and ID.
- [ ] Confirm Inventory lists reserve ammunition separately.
- [ ] Confirm Equipment lists the active Weapon slot.
- [ ] Confirm Raw JSON contains canonical `loaded_ammo` data.
- [ ] Validate the profile from the editor.
- [ ] Confirm zero errors for a valid slot.

## Economy durability

- [ ] Buy ammunition and save.
- [ ] Load and confirm wallet, inventory and finite merchant stock restore exactly.
- [ ] Buy the one-stock Dartcaster and save.
- [ ] Load and confirm the merchant remains sold out.
- [ ] Sell reserve ammunition and save.
- [ ] Load and confirm dynamic or authored resale stock restores exactly.
- [ ] Confirm loaded rounds never appear as merchant stock unless explicitly returned to reserve first.

## Accessibility and presentation

- [ ] Test with game audio muted.
- [ ] Confirm reload and ammunition state remain understandable visually.
- [ ] Test with reduced colour discrimination.
- [ ] Confirm player and enemy projectiles remain distinguishable by more than colour.
- [ ] Test at the smallest supported window.
- [ ] Confirm loaded/reserve counts remain readable.
- [ ] Test keyboard-only navigation.
- [ ] Test controller-only navigation.
- [ ] Confirm reload can be rebound.
- [ ] Review camera shake for comfort.
- [ ] Review projectile flash and trails for photosensitivity concerns.

## Long-form soak test

- [ ] Play for at least one hour while alternating melee and ranged weapons.
- [ ] Perform at least fifty reloads.
- [ ] Fire at least two hundred projectiles.
- [ ] Change era repeatedly with different magazine states.
- [ ] Travel between all three maps.
- [ ] Use all companion commands.
- [ ] Buy and sell ammunition repeatedly.
- [ ] Save and load every slot.
- [ ] Confirm no ammunition duplication or unexplained loss.
- [ ] Confirm no stale projectiles survive transitions.
- [ ] Confirm no reload remains permanently locked.
- [ ] Confirm no progressive frame-time or memory degradation is obvious.

## Release gate

The Arsenal slice is ready for production only when:

- [ ] Official Godot 4.6.2 CI is green.
- [ ] Every automated Arsenal smoke test passes.
- [ ] All inherited system tests remain green.
- [ ] Keyboard and controller flows are complete.
- [ ] Reload rollback is verified manually.
- [ ] Projectile cover and collision are visually credible.
- [ ] Schema-3 migration and schema-4 restoration are verified.
- [ ] Loaded-weapon sale protection is verified.
- [ ] No progression route depends on irreplaceable ammunition.
- [ ] Economy pricing has no obvious positive resale loop.
- [ ] A long-form playtest finds no ammunition duplication, loss or softlock.
