extends SceneTree

const Validator = preload("res://src/content/story_validator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var items := {
		"known_item": {
			"id": "known_item",
			"display_name": "Known Item",
			"kind": "material",
			"stack_limit": 9,
			"value": 0,
			"use_effect": {"type": "none"}
		}
	}
	var recipes := {
		"known_recipe": {
			"id": "known_recipe",
			"display_name": "Known Recipe",
			"ingredients": [{"item_id": "known_item", "quantity": 1}],
			"output": {"item_id": "known_item", "quantity": 1},
			"unlocked_by_default": false
		}
	}
	var valid_quest := {
		"id": "known_quest",
		"title": "Known Quest",
		"summary": "Known summary.",
		"initial_stage": "known_stage",
		"auto_start": false,
		"stages": [
			{
				"id": "known_stage",
				"description": "Known objective.",
				"completion_conditions": [{"type": "always"}],
				"next_stage": ""
			}
		],
		"rewards": []
	}
	var quests := {"known_quest": valid_quest}
	var map_ids := {"known_map": true}
	var era_ids := {"known_era": true}
	var used_quests: Dictionary = {}
	var errors: Array[String] = []
	var warnings: Array[String] = []

	var malformed_conversation := {
		"id": "bad conversation",
		"display_name": "",
		"start_node": "missing_start",
		"conditions": [
			{"type": "has_item", "item_id": "missing_item", "quantity": 0},
			{"type": "era_is", "era_id": "missing_era"}
		],
		"nodes": [
			{
				"id": "opening",
				"kind": "line",
				"speaker": "",
				"text": "",
				"next": "missing_target",
				"conditions": [{"type": "unknown_condition"}],
				"effects": [{"type": "start_quest", "quest_id": "missing_quest"}],
				"editor_position": {"x": 10}
			},
			{
				"id": "choice",
				"kind": "choice",
				"prompt": "",
				"conditions": [],
				"effects": [],
				"choices": [
					{
						"id": "bad choice",
						"text": "",
						"conditions": [{"type": "map_is", "map_id": "missing_map"}],
						"effects": [{"type": "unlock_recipe", "recipe_id": "missing_recipe"}],
						"next": ""
					}
				]
			},
			{
				"id": "end",
				"kind": "unsupported",
				"effects": []
			}
		]
	}
	Validator.validate_conversation(
		malformed_conversation,
		"bad conversation",
		{"bad conversation": malformed_conversation},
		quests,
		items,
		recipes,
		map_ids,
		era_ids,
		used_quests,
		errors,
		warnings
	)
	check(errors.size() >= 14, "Malformed conversation must produce comprehensive validation errors.")
	check(contains_fragment(errors, "missing_start"), "Validation must reject an unknown conversation start node.")
	check(contains_fragment(errors, "missing_target"), "Validation must reject a dangling next-node reference.")
	check(contains_fragment(errors, "unknown_condition"), "Validation must reject unsupported condition types.")
	check(contains_fragment(errors, "missing_recipe"), "Validation must reject unknown recipe unlocks.")
	check(contains_fragment(errors, "editor_position requires x and y"), "Validation must reject incomplete graph positions.")

	errors.clear()
	warnings.clear()
	var malformed_quest := {
		"id": "bad quest",
		"title": "",
		"summary": "",
		"initial_stage": "missing_initial",
		"auto_start": "yes",
		"stages": [
			{
				"id": "bad stage",
				"description": "",
				"completion_conditions": [
					{"type": "quest_stage", "quest_id": "known_quest", "stage_id": "missing_stage"},
					{"type": "clock_shards_at_least", "amount": -1}
				],
				"next_stage": "missing_next"
			}
		],
		"rewards": [
			{"type": "grant_item", "item_id": "missing_item", "quantity": 0},
			{"type": "set_state", "key": ""},
			{"type": "message", "text": ""}
		]
	}
	Validator.validate_quest(
		malformed_quest,
		"bad quest",
		quests,
		items,
		recipes,
		map_ids,
		era_ids,
		used_quests,
		errors,
		warnings
	)
	check(errors.size() >= 12, "Malformed quest must produce comprehensive validation errors.")
	check(contains_fragment(errors, "missing_initial"), "Validation must reject an unknown initial quest stage.")
	check(contains_fragment(errors, "missing_next"), "Validation must reject an unknown next quest stage.")
	check(contains_fragment(errors, "missing_stage"), "Validation must reject unknown quest-stage conditions.")
	check(contains_fragment(errors, "description is required"), "Validation must inspect nested fields even when a stage ID is malformed.")
	check(contains_fragment(errors, "missing_item"), "Validation must reject unknown story reward items.")
	check(contains_fragment(errors, "auto_start must be boolean"), "Validation must enforce boolean auto_start records.")

	finish()


func contains_fragment(messages: Array[String], fragment: String) -> bool:
	for message in messages:
		if fragment in message:
			return true
	return false


func finish() -> void:
	if failures.is_empty():
		print("Story validation edge test passed: malformed graphs, cross-references, conditions, effects and quest stages are rejected.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
