# Epochbound Story Studio

Story Studio is the branching-dialogue and quest-authoring layer for Epochbound campaigns.

It sits beside the existing Godot production tools:

- **Campaign Studio** authors maps, eras, terrain, collision, navigation, interactions and travel.
- **Encounter Studio** defines reusable objects and places NPCs, props, enemies and pickups.
- **Combat Director** directs encounter groups, telegraphs, leashes and clear-state outcomes.
- **Companion Studio** authors Morrow’s commands, scent cues, discoveries and recovery behaviour.
- **Item Forge** defines inventory, consumables, materials, key items, recipes and starting loadouts.
- **Story Studio** defines conversations, choices, conditions, effects, quest stages and rewards.

All six tools write inspectable campaign records consumed by the same runtime, validator and executable tests. Story Studio does not store narrative logic in hidden scene metadata or execute arbitrary script names from content.

## Design goals

The story layer follows these production rules:

1. Conversations and quests use stable IDs that survive display-copy changes.
2. Branches are explicit graph records, not implicit line order.
3. Conditions are typed data evaluated against real world, inventory and quest state.
4. Effects are typed data applied through guarded runtime methods.
5. Quest objectives use the same persistent state keys already produced by maps, encounters, pickups and companion discoveries.
6. Item requirements and rewards reference Item Forge IDs rather than a parallel quest inventory.
7. Completed quest rewards are idempotent.
8. Story records remain source-control friendly and can be validated without launching a full play session.
9. The editor rolls back a save that would invalidate the campaign.
10. Required progression must remain understandable through the Journal and player-facing dialogue.

## Godot editor workflow

1. Open `project.godot` in Godot 4.6.2.
2. Select the **Story** main-screen tab.
3. Choose a source campaign.
4. Open **Conversations** to create a dialogue graph.
5. Add line, choice or end nodes.
6. Set the conversation’s start node.
7. Author node text, speakers, choices, conditions and effects.
8. Drag graph nodes into a readable layout.
9. Open **Quests** to create quest definitions and objective stages.
10. Add typed completion conditions and a next stage.
11. Add completion rewards.
12. Bind a conversation ID to an NPC object or map interaction.
13. Validate the complete campaign.
14. Run the campaign and verify every branch, requirement, reward and return path.

## Content layout

A campaign declares one or more story files:

```json
{
  "story_files": [
    "story/core.json"
  ],
  "starting_quests": []
}
```

A normal campaign directory now contains:

```text
campaigns/my_campaign/
  campaign.json
  story/
    core.json
  items/
    core.json
  recipes/
    core.json
  objects/
    core.json
  maps/
    first_crossing.json
```

Additional story files can be declared later. Conversation IDs must be unique across all declared story files. Quest IDs must also be unique across all declared story files.

New campaigns created through Campaign Studio receive a valid starter story catalog automatically.

## Story catalog contract

A story catalog contains a schema version, conversations and quests:

```json
{
  "schema_version": 1,
  "conversations": [],
  "quests": []
}
```

The current schema version is `1`.

## Conversation contract

A conversation has a stable ID, player-facing name, start node, optional availability conditions and a node array:

```json
{
  "id": "archivist_missing_hour",
  "display_name": "The Archivist and the Missing Hour",
  "start_node": "greeting",
  "conditions": [],
  "nodes": []
}
```

### Conversation ID

`id` is a normalised lowercase identifier.

Good examples:

- `archivist_missing_hour`
- `keeper_at_floodgate`
- `morrow_old_trail`
- `clockmaker_last_warning`

Display names may change without breaking NPC bindings, quest references or save migrations.

### Availability conditions

Conversation-level `conditions` decide whether the conversation can begin at all.

Use this for broad gates such as:

- a quest status;
- an era requirement;
- a required key item;
- a world flag;
- a minimum clock-shard total.

Do not hide ordinary flavour dialogue behind unnecessary progression conditions. A player who fails a gate should receive a clear fallback interaction rather than unexplained silence.

## Node kinds

The current graph supports three node kinds.

### Line node

A line node presents authored text and optionally advances to another node:

```json
{
  "id": "greeting",
  "kind": "line",
  "speaker": "LOST ARCHIVIST",
  "text": "You arrived between one chime and the next.",
  "next": "questions",
  "conditions": [],
  "effects": [],
  "editor_position": {"x": 80, "y": 180}
}
```

A line may end the conversation by using an empty `next` value.

### Choice node

A choice node presents a prompt and filtered response options:

```json
{
  "id": "questions",
  "kind": "choice",
  "prompt": "What will Eli ask?",
  "conditions": [],
  "effects": [],
  "choices": [
    {
      "id": "ask_about_hour",
      "text": "Ask about the missing hour.",
      "conditions": [],
      "effects": [],
      "next": "missing_hour_assignment"
    }
  ],
  "editor_position": {"x": 360, "y": 120}
}
```

Each choice has its own conditions and effects. Only currently available choices appear in the runtime.

A choice ID is local to its node but must be unique within that node.

### End node

An end node closes the conversation after applying its effects:

```json
{
  "id": "end",
  "kind": "end",
  "effects": [],
  "editor_position": {"x": 1080, "y": 300}
}
```

End nodes make graph intent explicit and provide a useful target for several branches.

## Era-aware text

Line text, choice prompts and choice labels may be plain text or era-keyed objects.

Plain text:

```json
{
  "text": "The catalogue changes when no one is looking."
}
```

Era-aware text:

```json
{
  "text": {
    "verdant": "The catalogue smells of rain and green ink.",
    "ashen": "The catalogue continues burning without losing a page.",
    "default": "The catalogue belongs to several years at once."
  }
}
```

The runtime uses the current map era, then `default`, then a safe fallback.

Do not use era variants only to recolour identical information. Era-aware dialogue should reveal a changed relationship, consequence, threat, route or interpretation.

## Graph layout

Every node may store an `editor_position`:

```json
{
  "editor_position": {"x": 480, "y": 220}
}
```

Story Studio uses Godot’s `GraphEdit` and `GraphNode` controls to render the conversation graph. Connections are generated from line `next` values and choice `next` values.

The graph layout is authoring metadata. Runtime traversal depends on stable node IDs and explicit next-node references, not screen coordinates.

A readable graph should:

- flow consistently from left to right or top to bottom;
- separate major branches;
- avoid crossing connections where practical;
- place endings and convergence points clearly;
- keep quest-changing effects visible in the node inspector;
- make loops intentional and easy to identify.

## Typed conditions

Every condition is an object with a `type`. All conditions in one array must pass.

### Always

```json
{"type": "always"}
```

Useful for explicit defaults and tests. Empty condition arrays also mean no gate.

### Has item

```json
{
  "type": "has_item",
  "item_id": "clockglass_lens",
  "quantity": 1
}
```

The item must exist in Item Forge and the quantity must be positive.

### State equals

```json
{
  "type": "state_equals",
  "key": "bellweather:zone:east_ash_hunt",
  "value": "cleared"
}
```

This reads the shared durable world-state dictionary used by pickups, encounters, discoveries and story effects.

Stable keys should describe durable outcomes rather than transient animation state.

### Quest status

```json
{
  "type": "quest_status",
  "quest_id": "the_missing_hour",
  "status": "active"
}
```

Supported statuses:

- `not_started`
- `active`
- `completed`

### Quest stage

```json
{
  "type": "quest_stage",
  "quest_id": "the_missing_hour",
  "stage_id": "return_to_archivist"
}
```

This requires the quest to be active at the exact stage.

### Map is

```json
{
  "type": "map_is",
  "map_id": "clockwood_edge"
}
```

### Era is

```json
{
  "type": "era_is",
  "era_id": "ashen"
}
```

### Clock shards at least

```json
{
  "type": "clock_shards_at_least",
  "amount": 5
}
```

The amount cannot be negative.

## Typed effects

Effects are applied in authored order.

### Start quest

```json
{"type": "start_quest", "quest_id": "the_missing_hour"}
```

Starting an already-active or completed quest has no effect.

### Advance quest

```json
{"type": "advance_quest", "quest_id": "the_missing_hour"}
```

This advances to the current stage’s `next_stage`, or completes the quest when no next stage exists.

### Complete quest

```json
{"type": "complete_quest", "quest_id": "the_missing_hour"}
```

Completion rewards run once because a completed quest cannot complete again.

### Set quest stage

```json
{
  "type": "set_quest_stage",
  "quest_id": "the_missing_hour",
  "stage_id": "return_to_archivist"
}
```

Use this only when a deliberate branch changes objective order. Ordinary linear progression should rely on completion conditions and `next_stage`.

### Set state

```json
{
  "type": "set_state",
  "key": "story:missing_hour:returned",
  "value": true
}
```

### Grant item

```json
{
  "type": "grant_item",
  "item_id": "museum_tonic",
  "quantity": 1
}
```

Stack limits still apply through the shared inventory model.

### Remove item

```json
{
  "type": "remove_item",
  "item_id": "clockglass_lens",
  "quantity": 1
}
```

The author should gate this effect with a matching `has_item` condition when the item is required.

### Unlock recipe

```json
{
  "type": "unlock_recipe",
  "recipe_id": "clockglass_lens_recipe"
}
```

### Grant clock shards

```json
{
  "type": "grant_clock_shards",
  "amount": 3
}
```

### Message

```json
{
  "type": "message",
  "text": "The lower-gallery route is now marked in the journal."
}
```

Messages supplement, rather than replace, clear dialogue and objective copy.

## Quest contract

A quest contains a stable ID, title, summary, initial stage, auto-start flag, stages and completion rewards:

```json
{
  "id": "the_missing_hour",
  "title": "The Missing Hour",
  "summary": "Restore the hour erased beneath Bellweather Museum.",
  "initial_stage": "trace_the_name",
  "auto_start": false,
  "stages": [],
  "rewards": []
}
```

### Starting quests

A campaign may start selected quests explicitly:

```json
{
  "starting_quests": [
    "first_errand"
  ]
}
```

A quest can also set `auto_start` to `true`.

Starting quest IDs must exist and may not repeat.

### Quest stages

Each stage contains an objective, completion conditions and optional next stage:

```json
{
  "id": "forge_the_lens",
  "description": "Discover the recipe and craft the Clockglass Lens.",
  "completion_conditions": [
    {
      "type": "has_item",
      "item_id": "clockglass_lens",
      "quantity": 1
    }
  ],
  "next_stage": "return_to_archivist"
}
```

An empty `next_stage` completes the quest when the stage conditions pass.

Stages with empty completion conditions advance immediately. Validation warns because this is easy to author accidentally.

### Automatic objective evaluation

Quest conditions are evaluated after meaningful state changes, including:

- campaign load;
- map travel;
- era shift;
- item acquisition;
- item use;
- crafting;
- companion discovery;
- pickup collection;
- encounter-zone clearing;
- story effects.

The evaluator advances every ready stage deterministically and caps transitions to prevent malformed instant loops.

### Quest rewards

Quest rewards use the same typed effects as conversations.

Rewards are applied once when the quest changes to `completed`. Re-evaluation cannot duplicate them.

## Binding conversations

### Reusable NPC or prop definitions

An Encounter Studio object may reference a conversation:

```json
{
  "id": "lost_archivist",
  "kind": "npc",
  "conversation_id": "archivist_missing_hour"
}
```

Every placement of that reusable object uses the same conversation graph, while the graph can branch on map, era, items and quest state.

### Map interactions

A map interaction may also reference a conversation:

```json
{
  "id": "sealed_archive_door",
  "conversation_id": "archive_door_warning",
  "story_conditions": [],
  "story_effects": []
}
```

If `story_conditions` fail, `blocked_dialogue` should explain what the player observes.

### Companion cues and pickup effects

Companion cues and reusable pickups may carry `story_effects`.

These effects run only after the cue or pickup’s existing persistent state key confirms a first-time discovery or collection. This preserves reward idempotence across map travel and era shifts.

## Runtime conversation flow

The runtime follows this sequence:

1. Resolve the conversation ID.
2. Check conversation availability conditions.
3. Enter `start_node`.
4. Check node conditions.
5. Apply node effects.
6. Present line text or filtered choices.
7. Follow the selected `next` reference.
8. Close on an end node or empty line target.

Choice lists are rebuilt against current state, so unavailable responses do not appear.

The player may close a conversation with Escape. Closing does not roll back effects already applied by visited nodes or choices.

## Journal

Press **J** on keyboard or click the right stick to open the Journal.

Controls:

| Action | Keyboard | Controller |
| --- | --- | --- |
| Open or close Journal | J | Right stick click |
| Change Active or Completed tab | Left / Right | D-pad Left / Right |
| Select quest | Up / Down | D-pad Up / Down |
| Close | Escape or J | Right stick click |

The Active tab shows the current objective for each active quest. The Completed tab records completed quest titles and summaries.

A compact active-objective tracker is also shown during normal play.

The Journal is a presentation of quest state, not a second quest database.

## Safe deletion

Story Studio refuses to delete a conversation while an object or map interaction references it.

It refuses to delete a quest while it is referenced by:

- campaign starting quests;
- conversation conditions;
- conversation effects;
- another quest’s conditions or rewards;
- map or object story effects.

It refuses to delete a node while another line or choice targets it, and refuses to delete the current start node.

It refuses to delete a stage while another stage or story record references it, and refuses to delete the current initial stage.

These checks protect common editor workflows before full campaign validation runs.

## Validation rules

Story validation rejects:

- missing or malformed `story_files` arrays;
- unsafe or duplicate story paths;
- duplicate conversation IDs across catalogs;
- duplicate quest IDs across catalogs;
- invalid conversation, node, choice, quest or stage IDs;
- missing display names or quest titles;
- missing or unknown start nodes;
- unknown node kinds;
- malformed line or era-aware text;
- choice nodes without choices;
- duplicate choice IDs;
- empty choice targets;
- dangling node targets;
- malformed graph positions;
- missing or unknown initial quest stages;
- dangling next-stage references;
- malformed condition or effect records;
- unsupported condition or effect types;
- unknown item, recipe, quest, stage, map or era references;
- non-positive item quantities;
- invalid clock-shard amounts;
- missing state keys or values;
- unknown NPC or interaction conversation bindings;
- unknown starting quests.

It warns about:

- empty story catalogs;
- unreachable conversation nodes;
- unreachable quest stages;
- empty speakers;
- quests with empty summaries;
- stages that advance immediately;
- conversations with no object or interaction binding;
- quests that are never started or referenced.

Validation proves structural and referential coherence. It does not prove narrative quality, tone, pacing or emotional clarity.

## Reference story proof

The reference campaign includes one branching conversation and two interconnected quest arcs.

### The Archivist and the Missing Hour

The Lost Archivist conversation changes available responses based on:

- current era;
- quest status;
- exact quest stage;
- ownership of the Clockglass Lens.

The graph starts quests, explains current work, accepts the crafted lens and reflects completed outcomes.

### The Missing Hour

The quest proves cross-system progression:

1. Speak with the Lost Archivist.
2. Start the quest through a dialogue choice.
3. Use Morrow’s Verdant well clue to satisfy `trace_the_name`.
4. Discover materials and the Clockglass Lens recipe.
5. Craft the Clockglass Lens through Item Forge.
6. Advance automatically to `return_to_archivist`.
7. Return the lens through a gated conversation response.
8. Complete the quest once.
9. Receive a Museum Tonic, three clock shards and a durable completion flag.

### Quiet the Ash Hunt

This quest proves Combat Director integration:

1. Ask the Archivist about the brass rhythm in the Ashen era.
2. Start `quiet_the_hunt`.
3. Clear every enemy assigned to `east_ash_hunt`.
4. Consume the existing encounter-zone clear state.
5. Complete the quest automatically.
6. Receive Ashen Resin and one clock shard once.

## Quality gates

### Narrative clarity

- The player understands why a choice is available.
- A hidden choice is not required unless its requirement is communicated elsewhere.
- Speakers remain identifiable without relying only on portrait colour.
- Quest titles and objectives use distinct, concrete language.
- Important consequences are acknowledged in later dialogue.

### Branching quality

- Choices differ in information, action, relationship or consequence.
- Cosmetic wording variations do not masquerade as meaningful branches.
- Converging branches remain logically consistent.
- Loops are intentional and do not trap the player.
- End nodes close at an appropriate conversational beat.

### Quest reliability

- Required states have at least one reachable source.
- Item requirements can be satisfied without consuming an irreplaceable item prematurely.
- Every mandatory quest has a completable stage path.
- Completion conditions cannot become impossible after era changes or map travel.
- Rewards fit stack limits and cannot duplicate.
- Quest completion does not depend on an undocumented transient runtime value.

### Cross-era design

- Era changes alter interpretation, evidence or available action.
- Era-specific text remains compatible with shared quest state.
- A quest does not silently require an era that the player cannot access.
- Shifting era during active work does not corrupt conversation or objective state.

### Accessibility

- Required information is textual and not colour-only.
- Dialogue and Journal navigation work without pointer input.
- Choice selection has a visible marker.
- Current objectives remain available after dialogue closes.
- The player can close conversations and the Journal predictably.
- Critical requirements are not communicated only through sound.

### Tone and originality

- Dialogue matches Epochbound’s original setting and cast.
- Copy avoids placeholder fantasy phrasing once content enters production.
- Character voice remains consistent across eras without repeating protected dialogue or characterisation from existing games.
- The game can learn from classic pacing and readability while retaining original maps, terminology, story, characters, art and audio.

## Automated verification

The official Godot 4.6.2 gate checks:

1. direct compilation of the runtime, story model, validator, Story Studio and all inherited systems;
2. strict project import with all six editor plugins enabled;
3. complete campaign, map, encounter, companion, item, recipe, conversation and quest validation;
4. inherited world, combat, companion and Item Forge smoke tests;
5. branching conversation availability;
6. quest start and stage transitions;
7. companion-discovery progression;
8. item-gated progression;
9. quest completion and reward idempotence;
10. Combat Director clear-state progression;
11. Journal state;
12. Story Studio graph nodes, generated connections and typed source parsing;
13. rejection of malformed graph references, conditions, effects and quest stages.

Run the complete sequence locally:

```powershell
Set-Location C:\GitRepos\epochbound
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

## Future extensions

The current contracts are designed to support:

- durable save-profile quest and conversation state;
- world-state inspection and migration tools;
- voiced-line IDs and localisation keys;
- portraits and expression records;
- conversation history;
- relationship and reputation values;
- OR condition groups and explicit negation;
- timed or interrupted conversations;
- quest categories and tracked-quest selection;
- optional objectives;
- failure states and recovery paths;
- merchant, equipment and capability-gate conditions;
- cinematic triggers;
- campaign packaging and schema migrations;
- automated quest reachability and softlock probes.

Those layers should extend the same stable conversation IDs, node IDs, quest IDs, stage IDs, item IDs and durable state keys rather than introducing parallel narrative databases.
