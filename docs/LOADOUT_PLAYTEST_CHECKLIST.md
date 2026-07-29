# Loadout and Capability Playtest Checklist

Use this checklist for every equipment or capability-gated campaign milestone.

## Starting state

- Every starting-equipment item exists in starting inventory.
- Every starting item occupies its declared slot.
- The HUD reports the expected attack and defence values.
- Current health and maximum health reflect starting body equipment.
- Movement speed matches the authored loadout.
- Active capabilities match the equipped items and campaign base capabilities.
- Emptying each slot produces a valid playable state.

## Field Satchel

- Items, Recipes and Equipment tabs are reachable by keyboard.
- Items, Recipes and Equipment tabs are reachable by controller.
- Equipment rows use clear slot and item labels.
- Confirm cycles through empty and all compatible owned items.
- Directly selecting an equipment item equips it into the correct slot.
- Equipping never consumes the item.
- Unequipping never removes the item from inventory.
- Stat changes appear immediately.
- Capability changes take effect immediately.
- Maximum-health changes cannot reduce current health below one.

## Combat

- Attack bonuses produce the expected damage.
- Defence reduces incoming damage but never below one.
- Health bonuses remain coherent with restorative values.
- Movement bonuses do not invalidate enemy telegraphs.
- Stagger and knockback still behave correctly with higher damage.
- Morrow remains useful with every supported loadout.
- Manual saving remains blocked during active directed combat unless the campaign explicitly allows it.

## Capability gates

Test every gate twice: once without the requirement and once with it.

- A missing capability prevents the action completely.
- Blocked dialogue explains the requirement in world-facing language.
- No partial travel, reward or story effect occurs while blocked.
- The gate succeeds immediately after equipping valid gear.
- Removing the gear blocks the gate again where appropriate.
- Multiple requirements enforce every listed capability.
- Locked connection markers are readable without relying only on colour.
- Return routes do not create a loadout softlock.

## Story integration

- `has_capability` conditions use the active loadout rather than inventory ownership.
- Item-possession conditions still use `has_item` where possession is the actual requirement.
- Conversation choices update immediately after equipment changes.
- Quest objectives reevaluate after equipment changes.
- Equipment quest rewards are granted once.
- Required equipment cannot be deleted while referenced.

## Save and load

- Schema-2 profiles include the exact equipped item IDs.
- Every saved equipped item is also present in saved inventory.
- Manual save and autosave both preserve the loadout.
- Loading restores each slot exactly.
- Attack, defence, health, speed and capabilities rebuild correctly.
- Transient menus and combat timing still reset safely.
- A schema-1 profile migrates with empty equipment rather than guessed gear.
- Invalid slot, item or ownership references fail before live state changes.
- Backup recovery preserves the previous complete loadout.
- Save & State Studio displays every equipped slot.

## Reference campaign route

- Museum Flashlight permits entry into Museum Underworks.
- Removing the flashlight blocks the Underworks stairs with clear feedback.
- Brass Hook satisfies the Clockvine Bulkhead.
- Missing Brass Hook blocks the bulkhead.
- Archivist Lens satisfies the Sealed Catalogue.
- Equipping Archivist Lens removes Illuminate Darkness because it replaces the flashlight.
- Re-equipping the flashlight restores safe dark-route access.
- The Underworks return connection remains usable with any loadout.
- Saving inside the Underworks restores map, era, position and loadout.

## Regression

- Campaign Studio still creates valid new campaigns.
- Encounter Studio still loads all maps.
- Combat Director still validates encounter zones.
- Companion Studio still resolves discoveries and recovery.
- Item Forge still crafts and grants equipment as ordinary inventory items.
- Story Studio still validates every existing conversation and quest.
- Save & State Studio still validates legacy and current profiles.
- All official Godot 4.6.2 smoke tests pass without parser or runtime errors.
