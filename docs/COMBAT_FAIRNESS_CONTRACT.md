# Combat Telegraph Fairness Contract

Epochbound combat should reward observation and successful interruption. An enemy attack telegraph must describe one pending action clearly enough that the player can understand who is being threatened and whether a counterattack stopped it.

This contract applies to directed melee attacks inherited by ordinary enemies, reinforcements and bosses. It strengthens runtime behaviour without changing authored damage, range, windup, stagger, knockback or cooldown values.

## Invariant 1: windup locks target identity

When an enemy enters `windup`, the runtime records the chosen actor in `attack_target_id`.

- The lock may be `player` or `companion`.
- A different actor becoming closer during the telegraph must not inherit the pending attack.
- The enemy may continue facing the locked actor's current position so a moving target remains readable.
- Damage may resolve only against the locked actor.
- If the locked actor becomes unavailable before resolution, the pending windup is cancelled rather than transferred.
- The target lock is cleared after resolution, cancellation, stagger or any non-windup state.

This prevents a visible telegraph aimed at Eli from silently turning into damage against Morrow, or the reverse.

## Invariant 2: stagger cancels pending damage

A successful hit that applies stagger is an interrupt.

- `damage_entity` clears the enemy's remaining `attack_windup`.
- It also clears `attack_target_id`.
- The enemy resolves authored stagger and knockback normally.
- After stagger ends, an enemy still in range must begin a fresh full windup before it can damage an actor.
- A paused pre-hit telegraph must never resume and land later.

This makes hit response tactical rather than cosmetic and ensures the player's successful counterattack has an observable consequence.

## Invariant 3: ordinary groups expose one active telegraph

The ordinary enemies share one active melee windup slot per actor.

- The first eligible ordinary enemy in deterministic runtime order may claim the slot.
- Other in-range ordinary enemies enter `pressure`, face the actor and wait without applying damage.
- A completed, missed, cancelled or interrupted attack releases the slot.
- The next waiting enemy must begin its own full windup before it can damage the actor.
- Eli and Morrow have independent pressure slots.
- Bosses do not consume the ordinary-enemy slot, preserving boss threat while preventing reinforcement dogpiles.
- Pressure is coordination state only; it does not change authored damage, cooldown, range, stagger or knockback values.

## Runtime state boundaries

`attack_target_id`, `attack_windup`, pressure mode, stagger timers and knockback velocity are transient encounter state.

They may be retained only while synchronising the currently active runtime entities. They are not campaign-authored fields and must not enter durable save profiles, portable campaign packages or multiplayer progression records.

## Deterministic verification

The Combat Director smoke test proves both invariants through the real runtime scene:

1. an Ash Hound starts a windup against Eli;
2. Morrow is moved closer during the telegraph;
3. the completed attack still damages Eli and leaves Morrow unchanged;
4. a second windup is interrupted with `damage_entity`;
5. the pending timer and target lock are cleared immediately;
6. advancing beyond the original windup and stagger windows causes no deferred damage;
7. any later attack starts a new target lock and a fresh telegraph;
8. the two Clockwood Hounds enter range together;
9. exactly one owns the windup while the other enters pressure;
10. one telegraphed hit resolves, then the waiting Hound receives the next fresh windup without extra damage.

The fail-closed source checker pins the runtime, smoke test, local gate, documentation and exact-main validation receipt together.

## Manual playtest review

Automation proves state ordering, not presentation quality. Before release, verify that:

- attack anticipation animation points toward the locked actor;
- the timing ring or equivalent cue resets after interruption;
- hit sound, flash and recoil make the cancellation obvious;
- Morrow crossing an enemy's path does not make telegraphs look misleading;
- bosses remain threatening when ordinary stagger interrupts are allowed;
- multiple nearby ordinary enemies communicate pressure without overlapping melee telegraphs;
- boss and reinforcement combinations remain threatening without becoming unreadable dogpiles;
- accessibility settings preserve enough contrast and duration to read the lock.

Do not weaken the invariant by making attacks instant, disabling stagger broadly or hiding target changes in presentation. Tune authored timing while preserving the same deterministic state contract.
