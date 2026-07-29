extends SceneTree

const StoryStudio = preload("res://addons/epochbound_story_studio/story_studio.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var studio := StoryStudio.new()
	root.add_child(studio)
	check(studio != null, "Story Studio must instantiate.")
	if studio == null:
		finish()
		return

	var story_path := str(studio.get("active_story_path"))
	check(story_path.ends_with("campaigns/epochbound_demo/story/core.json"), "Story Studio must load the reference story catalog.")
	var conversations := dictionary_property(studio, "conversation_definitions")
	var quests := dictionary_property(studio, "quest_definitions")
	check(conversations.size() == 1, "Story Studio must expose one reference conversation.")
	check(quests.size() == 2, "Story Studio must expose two reference quests.")
	check(str(studio.get("selected_conversation_id")) == "archivist_missing_hour", "Story Studio must select the reference conversation.")
	check(str(studio.get("selected_node_id")) == "greeting", "Story Studio must select the first authored node.")
	check(str(studio.get("selected_quest_id")) in ["quiet_the_hunt", "the_missing_hour"], "Story Studio must select a reference quest.")

	var graph_value: Variant = studio.get("graph")
	check(graph_value is GraphEdit, "Story Studio must expose a GraphEdit conversation preview.")
	if graph_value is GraphEdit:
		var graph := graph_value as GraphEdit
		var graph_nodes := 0
		for child in graph.get_children():
			if child is GraphNode:
				graph_nodes += 1
		check(graph_nodes == 9, "Graph preview must contain every authored Archivist node.")
		check(graph.get_connection_list().size() >= 8, "Graph preview must render authored conversation connections.")

	var parse_lines: Variant = studio.call(
		"parse_json_lines",
		'{"type":"has_item","item_id":"clockglass_lens","quantity":1}\n{"type":"quest_status","quest_id":"the_missing_hour","status":"active"}',
		"test conditions"
	)
	check(typeof(parse_lines) == TYPE_DICTIONARY and bool((parse_lines as Dictionary).get("ok", false)), "Story Studio must parse typed JSON-line conditions.")
	if typeof(parse_lines) == TYPE_DICTIONARY:
		check((parse_lines as Dictionary).get("entries", []).size() == 2, "JSON-line parsing must preserve both typed conditions.")

	var text_result: Variant = studio.call(
		"parse_text_value",
		'{"verdant":"Green hour","ashen":"Burned hour","default":"Missing hour"}',
		"test dialogue"
	)
	check(typeof(text_result) == TYPE_DICTIONARY and bool((text_result as Dictionary).get("ok", false)), "Story Studio must parse era-keyed dialogue text.")
	if typeof(text_result) == TYPE_DICTIONARY:
		check(typeof((text_result as Dictionary).get("value")) == TYPE_DICTIONARY, "Era-keyed dialogue must remain a dictionary rather than flattened text.")

	var malformed: Variant = studio.call("parse_json_lines", "not-json", "bad conditions")
	check(typeof(malformed) == TYPE_DICTIONARY and not bool((malformed as Dictionary).get("ok", true)), "Story Studio must reject malformed JSON-line records.")

	root.remove_child(studio)
	studio.free()
	finish()


func dictionary_property(object: Object, property_name: String) -> Dictionary:
	var value: Variant = object.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func finish() -> void:
	if failures.is_empty():
		print("Story Studio editor smoke test passed: catalogs, forms, graph nodes, connections and typed source parsing are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
