# Epochbound Arsenal Studio

Arsenal Studio is the ranged-combat and ammunition-authoring layer inside the Godot editor. It extends the existing Item Forge, Loadout Studio, Combat Director, Trade Studio and Save & State Studio contracts rather than creating parallel weapon, ammunition or persistence systems.

- **Item Forge** owns every weapon and ammunition item ID.
- **Loadout Studio** owns the active Weapon slot and normal equipment modifiers.
- **Arsenal Studio** owns ranged firing, magazine, reload and projectile profiles.
- **Encounter Studio** owns reusable enemy definitions.
- **Combat Director** owns enemy placement, activation, windup and encounter space.
- **Trade Studio** owns ammunition and weapon stock.
- **Save & State Studio** inspects durable loaded-magazine state.

All systems consume the same source-controlled records.

## Player promise

Ranged combat should add deliberate spacing and preparation without replacing Epochbound's close-range action combat.

The player should understand:

- which weapon is equipped;
- which ammunition it consumes;
- how many rounds are loaded;
- how much reserve ammunition remains;
- when a reload starts and finishes;
- why a projectile hit or missed;
- why an enemy projectile caused damage;
- what state will persist after saving.

A projectile is a moving gameplay object. Damage is not applied at the moment the fire input is pressed.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Arsenal** main-screen tab.
3. Choose the campaign.
4. Create or select an ammunition item.
5. Configure its stack limit, economy value, damage bonus, knockback bonus and visual colour.
6. Create or select a ranged weapon.
7. Choose the ammunition item it consumes.
8. Configure magazine size, damage, projectile movement, cooldown, reload and knockback.
9. Select an enemy definition to enable or tune a projectile attack.
10. Validate the complete campaign.
11. Stock the ammunition and weapon through Trade Studio where appropriate.
12. Place ranged enemies through Encounter Studio and direct their encounter space through Combat Director.
13. Test combat, reload, cancellation, save/load and merchant interactions in the playable campaign.

## Ammunition contract

Ammunition remains an Item Forge item:

```json
{
  "id": "archive_bolts",
  "display_name": "Archive Bolts",
  "kind": "ammunition",
  "description": "Short brass-fletched bolts stamped with changing accession numbers.",
  "stack_limit": 60,
  "value": 2,
  "use_effect": {"type": "none"},
  "ammunition": {
    "damage_bonus": 0,
    "knockback_bonus": 2,
    "projectile_color": "f3d27a"
  }
}
```

### Stack limit

Ammunition must stack above one. Reserve rounds use the same inventory and stack-limit rules as every other Item Forge item.

The magazine is separate from reserve inventory:

- reserve rounds are stored in `inventory`;
- loaded rounds are stored in `loaded_ammo`;
- reload transfers a complete, validated quantity from reserve to the magazine;
- firing removes one loaded round;
- cancelling a reload removes nothing.

### Damage bonus

`damage_bonus` supplements the active weapon and player attack calculation. It should distinguish ammunition types without making the weapon definition irrelevant.

### Knockback bonus

`knockback_bonus` supplements the weapon's projectile knockback. Large values require map and encounter testing because displacement can affect collision, leashes and enemy readability.

### Projectile colour

`projectile_color` is an HTML colour used by the current blockout renderer. Final sprites, trails and particles should preserve the same readability role.

Colour alone must not be the only way to distinguish ammunition. Shape, timing, sound and UI labels should provide redundant information in the final presentation.

## Ranged equipment contract

A ranged weapon is an ordinary equipment item with an additional `equipment.ranged` record:

```json
{
  "id": "clockglass_dartcaster",
  "display_name": "Clockglass Dartcaster",
  "kind": "equipment",
  "stack_limit": 1,
  "value": 68,
  "equipment": {
    "slot": "weapon",
    "attack_bonus": 0,
    "defense_bonus": 0,
    "max_health_bonus": 0,
    "move_speed_bonus": 0,
    "capabilities": [],
    "ranged": {
      "ammo_item_id": "archive_bolts",
      "magazine_size": 4,
      "damage_bonus": 2,
      "projectile_speed": 340,
      "projectile_range": 280,
      "projectile_radius": 4,
      "fire_cooldown": 0.42,
      "reload_time": 0.85,
      "knockback_distance": 14,
      "muzzle_offset": 15,
      "projectile_color": "f3d27a"
    }
  }
}
```

### Ammunition reference

`ammo_item_id` must reference a valid item whose kind is `ammunition`.

Deleting ammunition is blocked while any ranged weapon references it. Renaming display text is safe because references use stable IDs.

### Magazine size

`magazine_size` is the maximum number of loaded rounds for that weapon. It does not change the reserve item's stack limit.

A small magazine can create deliberate attack windows. A large magazine reduces reload pressure and should be balanced against fire rate, damage and ammunition availability.

### Damage

Ranged player damage currently resolves as:

```text
player baseline attack
+ normal equipped attack modifiers
+ ranged weapon damage bonus
+ ammunition damage bonus
```

The projectile carries the resolved damage at fire time. Changing equipment after firing does not retroactively change a projectile already in flight.

### Projectile speed

`projectile_speed` controls world-space travel per second.

Slower projectiles:

- are easier to read;
- create dodging and positioning play;
- are more sensitive to map collision;
- require more leading against moving targets.

Faster projectiles approach hitscan behaviour and should be used carefully.

### Projectile range

`projectile_range` is the maximum world distance before the projectile expires.

Range should reflect the intended camera, map scale and encounter geometry. Excessive range can pull combat language across unrelated rooms. Very short range can make a ranged weapon feel less reliable than melee without providing a clear benefit.

### Projectile radius

`projectile_radius` is used for swept collision against enemies, actors and solid placed objects. It is not merely a visual size.

Large radii improve accessibility but can create apparently impossible hits around narrow cover. The final visual must communicate the same effective collision size.

### Fire cooldown

`fire_cooldown` determines the minimum interval between player shots. It uses the existing player attack lock so the ranged and melee systems remain mutually coherent.

### Reload time

`reload_time` is an explicit interval before reserve ammunition is transferred into the magazine.

A reload:

- consumes no ammunition when it starts;
- consumes the resolved transfer quantity only when it finishes;
- fills no more than the authored magazine capacity;
- uses no more than the available reserve;
- is cancelled if the active weapon changes;
- preserves reserve ammunition when cancelled or failed;
- blocks saving while incomplete.

### Knockback distance

`knockback_distance` controls the weapon's contribution to enemy displacement. Ammunition can add to it.

### Muzzle offset

`muzzle_offset` moves the projectile origin away from the player's centre along the current facing direction. It prevents a projectile from beginning inside the player silhouette and supports later sprite-specific muzzle positions.

## Player controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Fire equipped ranged weapon | Space or C | East face button |
| Reload | G | Right trigger |
| Equip ranged weapon | Field Satchel Equipment tab | Field Satchel Equipment tab |

The normal attack input remains contextual to the active Weapon slot:

- melee equipment performs the existing close-range attack;
- ranged equipment fires a projectile;
- an empty ranged magazine starts reload when reserve ammunition exists;
- an empty magazine with no reserve reports the missing ammunition.

## Projectile simulation

Projectiles are deterministic runtime dictionaries containing:

- source kind and stable source ID;
- source display name;
- previous and current positions;
- normalised direction;
- speed;
- remaining range;
- collision radius;
- damage;
- knockback;
- visual colour;
- intended target kind.

Each update:

1. Advances the projectile by speed multiplied by elapsed time.
2. Preserves the previous position.
3. Sweeps between the two positions rather than checking only the endpoint.
4. Tests authored map collision along the travelled segment.
5. Tests solid placed objects.
6. Tests the nearest valid target along the segment.
7. Applies damage and removes the projectile on impact.
8. Removes the projectile when range is exhausted.

Swept collision prevents a fast projectile from skipping through a target between frames.

## Player projectile rules

A player projectile:

- begins at the authored muzzle offset;
- travels in the player's facing direction;
- resolves damage at fire time;
- cannot damage the player or companion;
- stops at blocked terrain or solid placed objects;
- damages the first active enemy reached along its segment;
- applies the existing enemy stagger and knockback response;
- consumes exactly one loaded round when created.

Firing never removes reserve ammunition directly.

## Enemy projectile contract

A reusable enemy definition can contain `ranged_attack`:

```json
{
  "id": "underworks_sentinel",
  "kind": "enemy",
  "attack_radius": 160,
  "attack_damage": 3,
  "attack_cooldown": 1.4,
  "attack_windup": 0.45,
  "ranged_attack": {
    "projectile_speed": 210,
    "projectile_range": 240,
    "projectile_radius": 4,
    "knockback_distance": 18,
    "projectile_color": "e4674d"
  }
}
```

The existing Combat Director state machine remains authoritative:

1. The encounter activates.
2. The enemy patrols or chases within its leash.
3. The target enters `attack_radius`.
4. The enemy begins its visible windup.
5. When the windup completes, Arsenal Runtime creates a projectile instead of applying immediate damage.
6. Damage occurs only if the projectile reaches its intended actor.
7. The existing attack cooldown begins.

Enemy `attack_radius` cannot exceed projectile range.

## Companion safety

Enemy ranged attacks choose the same player-or-companion target used by Combat Director at fire time.

The projectile records that target kind. It does not switch targets in flight merely because another actor crosses nearby. This keeps enemy intent readable and avoids arbitrary companion interception.

Player projectiles ignore Morrow. Future friendly-fire modes must be explicit campaign rules rather than accidental collision behaviour.

## Map and cover design

Ranged combat makes existing spatial authoring more important.

Authors should review:

- whether terrain collision provides believable cover;
- whether solid props visually match their projectile-blocking role;
- whether enemies can fire through scenery the player reads as solid;
- whether narrow corridors create unavoidable shots;
- whether the player can retreat without pulling another encounter;
- whether era shifts change cover in understandable ways;
- whether companion recovery anchors remain safe from ranged fire;
- whether merchant and dialogue spaces are outside encounter leashes.

## Merchant integration

Ammunition and ranged weapons use Trade Studio stock records:

```json
{
  "item_id": "archive_bolts",
  "quantity": 24,
  "unlimited": false,
  "buy_price": 3,
  "sell_price": 1,
  "conditions": []
}
```

Merchants must include `ammunition` in `accepted_kinds` to purchase ammunition from the player.

Loaded rounds are not a separate saleable inventory stack. Selling reserve ammunition uses normal Item Forge quantities.

A ranged weapon with loaded rounds is protected from sale even when unequipped. The player must empty the magazine first, preventing loaded rounds from disappearing during a transaction.

## Save schema 4

The durable profile payload now contains:

```json
{
  "loaded_ammo": {
    "clockglass_dartcaster": 2
  }
}
```

Validation requires:

- every key to reference a current ranged equipment item;
- the player to own that weapon in inventory;
- the quantity to be numeric and non-negative;
- the quantity not to exceed the current magazine size.

Projectiles, reload progress and attack locks are transient and are not saved.

On load:

- campaign content is loaded first;
- inventory and equipment are restored;
- loaded magazines are validated against current definitions and ownership;
- projectiles are cleared;
- incomplete reloads are cancelled;
- gameplay resumes from stable durable state.

### Schema-3 migration

Schema-3 profiles retain equipment, economy, quests and all previous durable state. Migration adds an empty `loaded_ammo` dictionary.

The migration deliberately does not guess:

- which ammunition was loaded;
- which owned weapon had a magazine;
- whether reserve ammunition had previously been transferred.

The player reloads deliberately after migration.

## Save & State Studio

The **State** editor includes a **Loaded Ammo** inspector showing:

- weapon display name;
- loaded rounds;
- current authored magazine capacity;
- stable weapon item ID.

Profile validation uses the final Arsenal-aware validator.

## Safe deletion

Ammunition deletion is blocked while referenced by a ranged weapon.

Existing safeguards continue to block item deletion when referenced by:

- starting inventory;
- starting equipment;
- recipes;
- pickup rewards;
- companion discoveries;
- story effects;
- merchant stock;
- merchant refusal rules.

## Validation rules

Arsenal validation rejects:

- ammunition with stack limits of one;
- negative or excessive ammunition bonuses;
- invalid projectile colours;
- ranged records on non-equipment items;
- ranged equipment outside the Weapon slot;
- unknown or non-ammunition `ammo_item_id` values;
- magazine sizes outside supported bounds;
- invalid speed, range, radius, cooldown or reload values;
- excessive knockback or muzzle offsets;
- ranged attacks on non-enemy object definitions;
- enemy attack radii beyond projectile range;
- loaded magazines for unknown weapons;
- loaded magazines for unowned weapons;
- quantities above magazine capacity;
- non-numeric loaded-round values.

Warnings identify unreferenced ammunition, campaigns without ranged equipment, very short weapon range and enemy profiles whose attack radius may not demonstrate ranged behaviour.

## Reference content

### Clockglass Dartcaster

The reference player weapon uses a four-round magazine and Archive Bolts. Its role is controlled mid-range pressure rather than superior universal damage.

The Brass Hook remains valuable because it:

- has no ammunition requirement;
- supports close combat without reload windows;
- grants Cut Clockvines;
- cannot be blocked by projectile cover in the same way.

### Archive Bolts

Archive Bolts are finite inventory resources sold by Bellweather Provisions. Their low unit price supports regular use while still making missed shots and reload planning meaningful.

### Underworks Sentinel

The Underworks Sentinel appears only in the Ashen Museum Underworks. Its encounter proves:

- a reusable ranged enemy definition;
- an authored encounter zone and leash;
- visible attack windup;
- delayed projectile damage;
- map and solid-object collision;
- player defence integration;
- persistent defeat state.

### Underworks Exchange

The capability-gated Underworks Exchange sells the Clockglass Dartcaster as finite stock. This connects exploration equipment, merchant access, ranged combat and durable economy state through existing contracts.

## Quality gates

### Readability

- The active weapon and loaded/reserve counts are visible.
- Reload progress is visible without relying only on sound.
- Player and enemy projectiles remain distinguishable.
- Enemy windup communicates the upcoming shot.
- Effective projectile size matches its visual presentation.

### Fairness

- Enemy damage occurs only after a readable projectile reaches its target.
- Projectiles respect map collision and solid cover.
- Reload never consumes reserve ammunition before completion.
- Cancelled reloads preserve reserve ammunition.
- A failed shot cannot consume more than one loaded round.
- The player is not trapped in an unavoidable firing lane after map entry or era shift.

### Reliability

- Fast projectiles use swept collision.
- Map transitions and era shifts clear transient projectiles.
- Saving is blocked while projectiles or reloads are active.
- Loaded magazines validate against ownership and current capacity.
- Ranged weapons with loaded rounds cannot be sold accidentally.
- Merchant, inventory and save operations cannot duplicate ammunition.

### Balance

- Ammunition availability supports intended encounter frequency.
- Buy and sell prices do not create a positive resale loop.
- Ranged damage does not make melee or companion assistance irrelevant.
- Reload timing creates decisions rather than dead time.
- Enemy projectile pressure works inside the authored encounter leash.

### Accessibility

- Reload status is visible.
- Projectile colour is not the sole identifying cue.
- Collision radii are not materially larger than visible shots.
- Required input can be rebound through Godot input actions.
- Final audio, flash and shake settings should support reduced-effects options.

## Automated verification

The official Godot 4.6.2 gate now covers:

1. direct compilation of Arsenal Runtime, catalogue, validator, projectile model, editor and tests;
2. strict project import with all ten editor plugins;
3. complete campaign validation including ranged content;
4. every inherited world, combat, companion, item, story, save, loadout and economy regression;
5. reload start, partial progress, completion and reserve transfer;
6. delayed player projectile damage;
7. reload cancellation without ammunition loss;
8. delayed enemy projectile damage through active defence;
9. schema-4 capture and exact loaded-magazine restoration;
10. Arsenal Studio form and catalogue state;
11. malformed ranged content and save-state rejection.

Run the complete Windows gate:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

## Future extensions

The current contracts can support later additions without replacing authored content:

- alternate ammunition types;
- spread and multi-projectile weapons;
- charging and held-fire profiles;
- burst fire;
- piercing and ricochet rules;
- elemental or era-specific projectile effects;
- enemy aim leading and firing roles;
- companion ranged commands;
- destructible cover;
- ammunition crafting;
- weapon upgrades;
- aim assists and accessibility profiles;
- boss projectile patterns;
- automated line-of-fire and unavoidable-damage probes.

Every extension should preserve the same rule: editor, validator, runtime, merchant, save profile and executable tests consume one shared authored contract.
