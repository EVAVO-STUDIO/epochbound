# Action RPG Design Research

## Objective

Epochbound should feel like an unusually ambitious 1990s action RPG without inheriting the avoidable friction of that era. The goal is not to reproduce another game's content. It is to understand why certain structures remain memorable and then build an original, more legible and more authorable system.

## Research observations

### Flexible tools are part of game quality

Secret of Evermore lead programmer Brian Fehdrau described the team's map engine as flexible and recalled that visiting developers were interested in its early map editor. That matters because memorable authored worlds require iteration speed, not only runtime features.

Epochbound therefore treats Campaign Studio as a core production system. A map, encounter or era transition that is hard to inspect and revise will eventually become hard for players to understand.

### Revisit spaces with new meaning

Nintendo developers have described the value of reusing a known setting as a foundation for new discoveries. Epochbound's era system should follow that principle: the player learns a place once, then gains satisfaction from recognising what changed, what endured and what can now be manipulated.

The design test is not “does this era look different?” It is “does knowing the other era help the player make a better decision here?”

### Make experimentation system-safe

Nintendo's developers have also discussed letting players attempt ideas freely while engineering the system so unusual solutions do not break it. Epochbound should support curiosity without turning every alternate solution into a special-case script.

Campaign validation, deterministic world-state keys, companion recovery and explicit map connections are the first infrastructure for that promise.

### Design from the player's view

Nintendo's Ocarina of Time development discussion emphasised repeatedly testing how a level appears from the player's position rather than treating the map as an abstract plan. For Epochbound's top-down presentation, the equivalent is validating sightlines, silhouettes, approach direction, interaction range, combat readability and what is revealed at each screen edge.

The level editor therefore needs both a structural view and an accurate play-camera preview.

## What Epochbound should preserve

- Immediate movement and interaction
- Distinct regions with their own mechanical identity
- Compact dialogue with strong timing
- A loyal companion who affects play and story
- Secrets discovered through observation
- Memorable bosses with learnable patterns
- Strong audiovisual transitions between world states
- A handcrafted sense of place
- Progression that makes revisiting earlier spaces meaningful

## What Epochbound should improve

### Companion behaviour

The companion must never become an escort burden. It should:

- follow without body-blocking;
- recover from separation safely;
- use authored navigation capabilities;
- signal discoveries without repeatedly interrupting;
- contribute to combat without constant micromanagement;
- have context actions that remain useful across the campaign;
- retain a recognisable identity when its form changes between regions or eras.

### Combat clarity

Real-time combat should expose its rules visually:

- attack arcs and hitboxes match animation;
- enemy anticipation is readable;
- damage, stagger and invulnerability have distinct feedback;
- recovery windows are consistent;
- the player can understand why an attack missed;
- the companion cannot create unavoidable damage or trap the player;
- difficulty comes from decision pressure rather than input ambiguity.

### Progression without opaque grinding

Crafting, alchemy and equipment should create choices rather than hidden chores. Critical progression cannot depend on an untelegraphed rare drop or unexplained formula. Recipes should be learned through use, observation, characters and environmental clues.

### Era shifts as causal design

Every shift should produce at least one useful consequence:

1. reveal or remove a route;
2. alter a hazard or enemy ecology;
3. expose information;
4. change a relationship, faction or quest state;
5. create, destroy or transform a resource;
6. change the companion's available capability.

Good puzzles use several consequences across a place. Weak puzzles merely alternate a lock and key.

### Story that respects control

Cinematics should be pausable and skippable. Dialogue should allow fast advance without accidentally selecting choices. Important state changes should remain reviewable in a journal. The player should understand why the current objective matters without being forced through repeated exposition.

### No softlocks

The engine and content pipeline should detect or safely recover from:

- missing transition destinations;
- absent required actors or items;
- companion separation;
- arrival inside collision;
- quest states with no reachable next action;
- one-way era changes that remove the only exit;
- save files made during transient sequences;
- bosses that cannot reset cleanly after failure.

## Map quality rubric

A production map should be reviewed on six dimensions.

### Readability

The player can identify traversable space, hazards, exits, interactable landmarks and combat boundaries without relying on arbitrary invisible rules.

### Rhythm

Traversal, observation, dialogue, puzzle-solving and combat alternate intentionally. Empty distance exists only when mood, anticipation or world scale benefits from it.

### Connectivity

Routes form meaningful loops, shortcuts and returns. Connections are easy to author and impossible to leave dangling unnoticed.

### Era correspondence

Landmarks preserve enough identity to make comparison satisfying while changes communicate history, causality and mechanical opportunity.

### Companion value

At least some spaces let the companion notice, reach, track, distract or interpret something the player cannot handle alone.

### Replay and variation

Optional routes, discoveries, encounter states and consequences reward different decisions without requiring procedural filler.

## Editor implications

Campaign Studio should eventually provide:

- accurate camera framing at runtime resolution;
- era overlays and side-by-side comparison;
- heatmaps for empty travel and encounter density;
- reachable-area checks by player and companion capability;
- interaction-radius and combat-space previews;
- quest and world-state dependency graphs;
- map-connection graphs with reciprocal-link warnings;
- automated start-to-goal traversal probes;
- content linting for repeated dialogue, placeholder records and palette-only era copies;
- a rehearsal mode that starts at any map, era, quest state or boss phase.

The editor is not an optional convenience. It is how the project turns strong design intentions into repeatable, testable content.
