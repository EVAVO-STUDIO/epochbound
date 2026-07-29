extends SceneTree

const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/story_validator.gd")
const StoryCatalog = preload("res://src/content/story_catalog.gd")
const StoryModel = preload("res://src/game/story_model.gd")
const InventoryModel = preload("res://src/game/inventory_model.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var validation := Validator.validate_campaign_path(CAMPAIGN_PATH)
	check(validation.get("ok", false), "Reference campaign must pass Story Studio validation.")
	check(int(validation.get("conversation_count", 0)) == 1, "Reference campaign must expose one authored conversation.")
	check(int(validation.get("quest_count", 0)) == 2, "Reference campaign must expose two authored quests.")

	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(campaign_result.get("ok", false), "Reference campaign must load.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var story_result := StoryCatalog.load_catalogs(CAMPAIGN_PATH, campaign)
	check(story_result.get("ok", false), "Reference story catalog must load.")
	var conversations: Dictionary = story_result.get("conversations", {})
	var quests: Dictionary = story_result.get("quests", {})
	var archivist := StoryCatalog.conversation(conversations, "archivist_missing_hour")
	check(not archivist.is_empty(), "Archivist conversation must resolve.")
	check(StoryCatalog.nodes(archivist).size() == 9, "Archivist conversation must retain its nine authored nodes.")
	var missing_hour := StoryCatalog.quest(quests, "the_missing_hour")
	check(StoryCatalog.stages(missing_hour).size() == 3, "The Missing Hour must retain three stages.")

	probe_runtime_scene()
	finish()


func probe_runtime_scene() -> void:
	var scene_resource := ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(scene_resource is PackedScene, "Runtime scene must load as a PackedScene.")
	if not scene_resource is PackedScene:
		return
	var runtime := (scene_resource as PackedScene).instantiate()
	check(runtime != null, "Runtime scene must instantiate.")
	if runtime == null:
		return
	var script_value: Variant = runtime.get_script()
	check(script_value is GDScript, "Runtime root must retain its GDScript.")
	if script_value is GDScript:
		check(
			str((script_value as GDScript).resource_path) == "res://src/story_runtime.gd",
			"Runtime scene must bind the Story runtime."
		)
	root.add_child(runtime)
	check(runtime.has_method("start_conversation"), "Runtime must expose authored conversation entry.")
	check(runtime.has_method("apply_story_effects"), "Runtime must expose typed story effects.")
	check(runtime.has_method("evaluate_story_progress"), "Runtime must expose deterministic quest evaluation.")
	check(runtime.has_method("open_story_journal"), "Runtime must expose the quest journal.")
	if not runtime.has_method("start_conversation"):
		root.remove_child(runtime)
		runtime.free()
		return

	var runtime_conversations: Variant = runtime.get("conversation_definitions")
	var runtime_quests: Variant = runtime.get("quest_definitions")
	check(typeof(runtime_conversations) == TYPE_DICTIONARY and (runtime_conversations as Dictionary).size() == 1, "Runtime must load one conversation definition.")
	check(typeof(runtime_quests) == TYPE_DICTIONARY and (runtime_quests as Dictionary).size() == 2, "Runtime must load two quest definitions.")

	# The first Archivist branch starts the missing-hour quest.
	check(bool(runtime.call("start_conversation", "archivist_missing_hour")), "Archivist conversation must start.")
	check(str(runtime.get("active_node_id")) == "greeting", "Conversation must begin at its authored start node.")
	runtime.call("enter_story_node", "questions")
	var choices := runtime.call("active_choices") as Array
	var begin_choice := find_choice(choices, "begin_missing_hour")
	check(not begin_choice.is_empty(), "Initial choices must expose the missing-hour quest branch.")
	if not begin_choice.is_empty():
		runtime.call("apply_story_effects", StoryCatalog.effects(begin_choice), false)
	var progress := runtime_dictionary(runtime, "quest_progress")
	check(StoryModel.quest_status(progress, "the_missing_hour") == StoryModel.STATUS_ACTIVE, "Choosing the branch must start The Missing Hour.")
	check(StoryModel.quest_stage_id(progress, "the_missing_hour") == "trace_the_name", "The Missing Hour must start at trace_the_name.")

	# Morrow's already-authored persistent clue advances the first objective.
	var state := runtime_dictionary(runtime, "session_state")
	state["bellweather:companion:well_name_scent"] = "discovered"
	runtime.set("session_state", state)
	runtime.call("evaluate_story_progress")
	progress = runtime_dictionary(runtime, "quest_progress")
	check(StoryModel.quest_stage_id(progress, "the_missing_hour") == "forge_the_lens", "Well evidence must advance the quest to lens crafting.")

	# Owning the crafted key item advances to the return stage.
	var inventory := runtime_dictionary(runtime, "inventory")
	var item_definitions := runtime_dictionary(runtime, "item_definitions")
	var add_result := InventoryModel.add_item(inventory, item_definitions, "clockglass_lens", 1)
	check(int(add_result.get("added", 0)) == 1, "Test setup must add one Clockglass Lens.")
	runtime.set("inventory", inventory)
	runtime.call("evaluate_story_progress")
	progress = runtime_dictionary(runtime, "quest_progress")
	check(StoryModel.quest_stage_id(progress, "the_missing_hour") == "return_to_archivist", "Crafting the lens must advance the return objective.")

	# The gated return response removes the lens, sets a durable flag and completes the quest exactly once.
	runtime.call("start_conversation", "archivist_missing_hour")
	runtime.call("enter_story_node", "questions")
	choices = runtime.call("active_choices") as Array
	var return_choice := find_choice(choices, "return_lens")
	check(not return_choice.is_empty(), "Return stage must expose the Clockglass Lens response.")
	if not return_choice.is_empty():
		runtime.call("apply_story_effects", StoryCatalog.effects(return_choice), false)
	progress = runtime_dictionary(runtime, "quest_progress")
	inventory = runtime_dictionary(runtime, "inventory")
	state = runtime_dictionary(runtime, "session_state")
	check(StoryModel.quest_status(progress, "the_missing_hour") == StoryModel.STATUS_COMPLETED, "Returning the lens must complete The Missing Hour.")
	check(InventoryModel.count(inventory, "clockglass_lens") == 0, "Returning the lens must consume the key item.")
	check(state.get("story:missing_hour:returned") == true, "Returning the lens must set the authored durable flag.")
	check(state.get("story:missing_hour:completed") == true, "Quest rewards must set the authored completion flag.")
	check(InventoryModel.count(inventory, "museum_tonic") == 2, "Quest completion must grant exactly one Museum Tonic.")
	check(int(runtime.get("clock_shards")) == 3, "Quest completion must grant three clock shards.")

	# Re-evaluation cannot duplicate completed quest rewards.
	runtime.call("evaluate_story_progress")
	inventory = runtime_dictionary(runtime, "inventory")
	check(InventoryModel.count(inventory, "museum_tonic") == 2, "Completed quest rewards must be idempotent.")
	check(int(runtime.get("clock_shards")) == 3, "Completed quest shard rewards must be idempotent.")

	# A second quest consumes Combat Director's stable clear-state record.
	var quiet_effects := [{"type": "start_quest", "quest_id": "quiet_the_hunt"}]
	runtime.call("apply_story_effects", quiet_effects, false)
	state = runtime_dictionary(runtime, "session_state")
	state["bellweather:zone:east_ash_hunt"] = "cleared"
	runtime.set("session_state", state)
	runtime.call("evaluate_story_progress")
	progress = runtime_dictionary(runtime, "quest_progress")
	inventory = runtime_dictionary(runtime, "inventory")
	check(StoryModel.quest_status(progress, "quiet_the_hunt") == StoryModel.STATUS_COMPLETED, "Combat-zone clear state must complete Quiet the Ash Hunt.")
	check(InventoryModel.count(inventory, "ashen_resin") == 1, "Quiet the Ash Hunt must grant one Ashen Resin.")
	check(int(runtime.get("clock_shards")) == 4, "Quiet the Ash Hunt must add one clock shard.")

	runtime.call("open_story_journal")
	check(bool(runtime.get("story_journal_open")), "Journal action must open the quest journal.")
	var completed := StoryModel.completed_quest_ids(progress, runtime_dictionary(runtime, "quest_definitions"))
	check(completed.size() == 2, "Journal model must expose both completed quests.")

	root.remove_child(runtime)
	runtime.free()


func find_choice(choices: Array, choice_id: String) -> Dictionary:
	for value in choices:
		if typeof(value) == TYPE_DICTIONARY:
			var choice: Dictionary = value
			if str(choice.get("id", "")) == choice_id:
				return choice
	return {}


func runtime_dictionary(runtime: Object, property_name: String) -> Dictionary:
	var value: Variant = runtime.get(property_name)
	return value if typeof(value) == TYPE_DICTIONARY else {}


func finish() -> void:
	if failures.is_empty():
		print("Story Studio smoke test passed: branching conversation, item gates, quest stages, rewards, combat state and journal are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
