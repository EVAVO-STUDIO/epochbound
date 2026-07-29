# Game Vision and Originality Contract

## Creative target

Epochbound should feel like a fully authored 16-bit-era action RPG that was ambitious enough to be remembered, while avoiding the friction, repetition and opaque rules that limited many games of that period.

The project is not a remake, sequel, fan game or asset recreation. It must never reproduce protected characters, dialogue, maps, music, enemy designs, visual compositions, names or story events from existing games.

## Player promise

The player travels with Morrow, a loyal dog whose behaviour, senses and relationship with the hero are central rather than decorative. Every major region exists in multiple historically linked states. Shifting between them changes navigation, ecology, factions, puzzles, available resources, enemy behaviours and the consequences of earlier choices.

## What to preserve from the era

- Immediate controller-first play
- Strong silhouettes and readable combat spaces
- Memorable authored locations rather than procedural filler
- Compact dialogue with characterful timing
- Secrets that reward observation
- Bosses with learnable behaviours
- Music, animation and screen composition working together
- A sense that each new region introduces a genuinely new idea

## What to improve

- Never hide critical progression behind untelegraphed grinding
- Avoid companion pathfinding frustration and accidental softlocks
- Keep combat hitboxes, recovery windows and damage feedback legible
- Explain crafting and progression through play, not manuals
- Make all cinematics pausable and skippable
- Preserve manual saves while also providing safe autosaves
- Support remapping, scalable UI, reduced flashing and assist options
- Record world-state changes deterministically for testing and saves

## World structure

The world is organised around anchor locations. Each anchor has several age states rather than being a completely separate map. Designers author explicit correspondences between doors, landmarks, hazards, NPC roles and puzzle state across those ages.

A shift should create one of four useful outcomes:

1. reveal a route;
2. alter a threat;
3. expose information;
4. change a relationship or resource.

A shift that only changes the palette is considered incomplete.

## Companion contract

Morrow must be able to:

- follow without blocking the player;
- recover safely if navigation fails;
- identify scents, tracks, hidden passages and temporal anomalies;
- receive a small set of context-sensitive commands;
- participate in combat without requiring constant micromanagement;
- express state through animation and sound;
- evolve differently across regions while remaining recognisably Morrow.

## Production principle

Every feature must be playable with temporary assets first. Final visuals and audio replace stable contracts rather than defining undocumented behaviour. Content data must be validated so a missing portrait, dialogue branch, transition target or era correspondence fails clearly during development.
