# Epochbound World Builder

World Builder is the level-production layer inside Campaign Studio. Its purpose is not merely to draw a map. It authors the complete relationship between terrain, collision, companion movement, era changes, interactions and campaign travel.

A visually attractive room that traps the companion, hides its exit or changes only by palette is not considered complete.

## Production sequence

### 1. Define the map promise

Before painting, write one sentence describing what the player should understand or feel on first arrival.

Examples:

- a familiar crossing whose eastern ruin is behaving like a clock;
- a forest edge where dates carved into trees predict future events;
- a flooded market that becomes a dry graveyard in another era.

The promise should identify the location's dramatic identity, not its asset list.

### 2. Establish canvas, grid and bounds

Choose world dimensions large enough for the intended camera movement without creating empty travel. Keep the legal movement bounds inside the canvas and leave room for silhouettes, horizon treatment and HUD-safe composition.

The grid is an authoring unit, not a visual requirement. Final artwork may cross cell boundaries, but traversal contracts remain inspectable through the grid.

### 3. Paint the primary route

Use terrain to establish the first readable route from the default spawn or incoming entry point toward the location's main question.

A strong primary route:

- is visible or inferable within the first few seconds;
- provides at least one meaningful decision rather than a featureless corridor;
- keeps the player moving toward authored information;
- avoids forcing repeated backtracking through empty space;
- has enough width for both player and companion silhouettes.

### 4. Add terrain consequences

Terrain should communicate traversal before the player touches it.

Current blockout terrain can be:

- walkable shared ground;
- a readable path;
- blocked water;
- blocked cliff or debris;
- an era-specific replacement at the same cell.

Later tiles, sprites, sound and particles should reinforce these contracts rather than contradict them.

### 5. Paint explicit collision

Use collision cells for solid architecture and objects that cannot be represented by terrain blocking alone.

Review collision with these questions:

- Can the player approach every interaction closely enough?
- Are diagonals free of one-cell snag points?
- Does the player have space to leave every entry point?
- Can both actors pass through intended chokepoints?
- Does an era change ever place an actor inside a new blocker?

Collision should describe the authored boundary, not compensate for unclear visual composition.

### 6. Author companion navigation

Paint a connected navigation route through every intended traversal region.

The current runtime uses four-direction grid search. Therefore:

- adjacent navigation cells must share an edge;
- diagonal-only links are not connected;
- navigation cells should not overlap blocked terrain or collision;
- branches should reach interactions, entrances and recovery regions;
- dead ends should be deliberate and wide enough for recovery.

The direct-steering fallback is for blockout safety. A production map should not depend on it.

### 7. Place entry points

Every incoming connection names an entry point. Entry points contain separate player and companion positions.

Place arrivals so that:

- both actors begin in unblocked space;
- the companion does not overlap the player;
- the return connection is visible but does not retrigger immediately;
- the primary route reads from the arrival camera position;
- the preserved or explicit target era has a valid arrival.

Use stable names that describe the source or role, such as `from_bellweather`, `north_gate` or `after_flood_cinematic`.

### 8. Place recovery anchors

Recovery anchors are not teleport shortcuts. They are safe points used when navigation fails, actors become separated or an era change invalidates a position.

Good anchor locations include:

- just beyond an entry point;
- the safe side of a chokepoint;
- the centre of a large traversal region;
- before and after a major puzzle boundary;
- near companion-specific routes.

Avoid anchors inside transition radii, collision cells, blocked terrain or one-way puzzle spaces.

### 9. Add interactions

Interactions should answer or deepen the location's main question.

For each interaction, review:

- Is it reachable in every declared era?
- Does its radius fit the actual approach space?
- Does dialogue change when the world meaningfully changes?
- Is the interaction still useful after its first activation?
- Does the companion contribute observation, sensing or emotion where appropriate?

A map filled with unrelated flavour text is not automatically dense. Density means that discoveries reinforce place, character, systems or consequence.

### 10. Differentiate eras mechanically

Era-specific terrain, collision, navigation, landmarks, interactions, connections and recovery anchors can occupy the same map.

Each completed era change should do at least one of the following:

1. reveal or remove a route;
2. alter a threat or encounter;
3. expose new information;
4. change a relationship or faction response;
5. change a resource, puzzle or quest consequence.

Changing only sky and ground colours is a valid early blockout but not a final era design.

### 11. Connect the campaign

Connections must form an intentional world graph.

For every connection:

- verify the target map exists;
- verify the target entry exists;
- verify the target era rule;
- decide whether travel requires interaction or touch;
- author a reciprocal route when the story does not deliberately prevent return;
- keep activation radii clear of unrelated interactions;
- test travel in every available era.

The validator catches broken references. It cannot decide whether the world graph is narratively sensible, paced well or deliberately one-way.

### 12. Validate and play

Use **Validate All** before running the campaign. Then play the map from every entry point in every supported era.

A complete traversal review should include:

- default spawn to each exit;
- every incoming entry to its intended destination;
- companion follow through each chokepoint;
- era shifting near every blocked or changing cell;
- interaction approach from multiple directions;
- return travel through reciprocal links;
- pause and resume during traversal;
- repeated travel to detect immediate retrigger loops.

## Editor overlay review

### Terrain-only review

Disable collision, navigation and marker overlays. Confirm the location reads visually without production annotations.

### Collision review

Enable collision and inspect the true walkable silhouette. Look for accidental teeth, one-cell holes, blocked interaction approaches and mismatches between visuals and solids.

### Navigation review

Enable navigation and confirm the companion network is connected through intended routes. Any isolated island should be deliberate and paired with a recovery plan.

### Marker review

Enable markers and inspect the relationships among interactions, entries, recoveries and connections. Labels should remain distinct enough to select and audit.

### Combined review

Enable all overlays for the final production inspection. The map should still make sense as one system rather than four unrelated layers.

## Map quality gates

A map is not ready for content lock until it passes these gates.

### Readability

- The arrival view communicates a primary route or question.
- Important exits and interactions have distinct visual anchors.
- Collision agrees with visible boundaries.

### Traversal

- The player can reach every required objective and exit.
- No required route depends on walking through blocked cells.
- Chokepoints support the player and companion together.

### Companion safety

- Navigation reaches all intended traversal regions.
- Every entry provides a companion position.
- Recovery anchors cover major regions.
- Recovery cannot place the companion behind a progression lock.

### Era integrity

- Era-scoped cells resolve only in declared eras.
- Actor positions remain valid after shifting.
- Every era contributes mechanical or narrative change.
- Era-specific exits and interactions remain internally consistent.

### Campaign integrity

- Every connection resolves to a map and entry.
- Target eras exist.
- Reciprocal travel works where intended.
- Transition destinations do not immediately bounce the player back.

### Pacing

- Empty travel has been removed.
- Discoveries reinforce the map promise.
- Optional routes reward attention without hiding critical progression.
- The map introduces, develops or resolves at least one authored idea.

## Reference journey

The current reference campaign demonstrates the contract across two maps:

- **Bellweather Crossing** establishes shared path cells, blocked water, explicit ruin collision, navigation, two eras, interactions, recovery anchors and an eastern connection.
- **Clockwood Edge** uses a larger scrolling canvas, its own era treatment, a connected path network, era-specific cliff terrain, interactions and a reciprocal western connection.

These are production proofs, not final content scope. They exist so every editor feature has a runtime consumer and every runtime contract has validated example data.

## Future extensions

The world model is designed to accept later records without replacing the current map structure:

- tile-set and object-library references;
- object transforms and visual layers;
- one-way and capability-gated navigation;
- jump, climb, crawl, swim and companion-specific links;
- encounter and patrol zones;
- quest and world-state conditions;
- dynamic collision and destructible objects;
- cinematic camera tracks;
- streaming regions and large-world sectors;
- automated reachability and softlock probes.

Those additions should preserve the same rule: the editor, validator, runtime and tests must consume one shared authored contract.
