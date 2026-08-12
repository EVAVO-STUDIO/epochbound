extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")

const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/companion_validator.gd")
const CompanionModel = preload("res://src/game/companion_model.gd")

const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_smoke_test")


func run_smoke_test() -> void:
	var validation := Validator.validate_campaign_path(CAMPAIGN_PATH)
	check(validation.get("ok", false), "Reference campaign must pass Companion Studio validation.")
	check(int(validation.get("cue_count", 0)) == 6, "Reference campaign must expose six companion cues including two Hideaway observations.")
	check(int(validation.get("zone_count", 0)) == 3, "Companion validation must retain the three encounter zones.")

	var campaign_result := Repository.read_json(CAMPAIGN_PATH)
	check(campaign_result.get("ok", false), "Reference campaign must load.")
	var campaign: Dictionary = campaign_result.get("data", {})
	var profile := CompanionModel.profile(campaign)
	var commands := CompanionModel.allowed_commands(profile)
	check(commands == PackedStringArray(["follow", "stay", "seek", "guard"]), "Morrow must expose the four authored commands in order.")
	check(CompanionModel.seek_radius(profile) == 300.0, "Morrow must use the authored seek radius.")

	var bell := load_map(campaign, "bellweather_crossing")
	var clockwood := load_map(campaign, "clockwood_edge")
	check(CompanionModel.unresolved_cues(bell, "verdant", {}).size() == 1, "Verdant Bellweather must expose one unresolved companion cue.")
	check(CompanionModel.unresolved_cues(bell, "ashen", {}).size() == 1, "Ashen Bellweather must expose one unresolved companion cue.")
	check(CompanionModel.unresolved_cues(clockwood, "verdant", {}).size() == 1, "Verdant Clockwood must expose one unresolved companion cue.")
	check(CompanionModel.unresolved_cues(clockwood, "ashen", {}).size() == 1, "Ashen Clockwood must expose one unresolved companion cue.")
	var nearest := CompanionModel.nearest_unresolved_cue(bell, "verdant", {}, Vector2(270, 230), 300.0)
	check(str(nearest.get("id", "")) == "well_name_scent", "Morrow must select the nearest valid Verdant scent cue.")

	await probe_runtime_scene()
	finish()


func load_map(campaign: Dictionary, map_id: String) -> Dictionary:
	var path := Repository.find_exact_map_path(CAMPAIGN_PATH, campaign, map_id)
	var result := Repository.read_json(path)
	check(result.get("ok", false), "Map '%s' must load." % map_id)
	return result.get("data", {}) if result.get("ok", false) else {}


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
			str((script_value as GDScript).resource_path) in ["res://src/companion_runtime.gd", "res://src/inventory_runtime.gd", "res://src/story_runtime.gd", "res://src/save_runtime.gd", "res://src/equipment_runtime.gd", "res://src/merchant_runtime.gd", "res://src/arsenal_runtime.gd", "res://src/boss_runtime.gd", "res://src/cinematic_runtime.gd", "res://src/presentation_runtime_current.gd"],
			"Runtime scene must bind a companion-capable runtime."
		)
	root.add_child(runtime)
	check(runtime.has_method("set_companion_command"), "Runtime must expose companion commands.")
	check(runtime.has_method("recall_companion"), "Runtime must expose explicit recall.")
	check(runtime.has_method("reveal_companion_cue"), "Runtime must expose authored companion discovery.")
	if not runtime.has_method("set_companion_command"):
		await HeadlessRuntimeCleanup.release(self, runtime)
		return

	runtime.set("companion", Vector2(270, 230))
	runtime.call("set_companion_command", "stay")
	check(str(runtime.get("companion_command")) == "stay", "Stay command must become active.")
	var hold_value: Variant = runtime.get("companion_hold_position")
	check(hold_value is Vector2 and (hold_value as Vector2).is_equal_approx(Vector2(270, 230)), "Stay command must remember the hold position.")
	runtime.set("companion", Vector2(292, 230))
	runtime.call("update_companion", 0.1)
	var stayed_value: Variant = runtime.get("companion")
	check(stayed_value is Vector2 and (stayed_value as Vector2).x < 292.0, "Displaced companion must move back toward its hold position.")

	runtime.set("current_era_id", "verdant")
	runtime.set("companion", Vector2(270, 230))
	runtime.call("set_companion_command", "seek")
	var target_value: Variant = runtime.get("companion_seek_target")
	check(typeof(target_value) == TYPE_DICTIONARY, "Seek command must expose a cue target.")
	var target: Dictionary = target_value if typeof(target_value) == TYPE_DICTIONARY else {}
	check(str(target.get("id", "")) == "well_name_scent", "Seek must target the authored Bellweather clue.")
	var target_position := CompanionModel.cue_position(target)
	runtime.set("companion", target_position)
	var shards_before := int(runtime.get("clock_shards"))
	runtime.call("update_companion", 0.01)
	var session_value: Variant = runtime.get("session_state")
	var session: Dictionary = session_value if typeof(session_value) == TYPE_DICTIONARY else {}
	check(session.get("bellweather:companion:well_name_scent") == "discovered", "Resolved cue must persist its authored state key.")
	check(int(runtime.get("clock_shards")) == shards_before + 1, "Resolved clue must grant its authored reward once.")
	check(str(runtime.get("companion_command")) == "follow", "Companion must return to follow after discovery.")
	check(str(runtime.get("dialogue")).contains("VALE"), "Discovery must present the authored clue message.")

	runtime.call("reveal_companion_cue", target)
	check(int(runtime.get("clock_shards")) == shards_before + 1, "Discovered cue must not duplicate its reward.")

	runtime.set("dialogue", "")
	runtime.call("set_companion_command", "guard")
	check(str(runtime.get("companion_command")) == "guard", "Guard command must become active.")
	runtime.set("player", Vector2(312, 220))
	runtime.set("companion", Vector2(64, 320))
	runtime.call("recall_companion")
	var recalled_value: Variant = runtime.get("companion")
	check(recalled_value is Vector2, "Recall must keep a valid companion position.")
	if recalled_value is Vector2:
		check((recalled_value as Vector2).distance_to(Vector2(312, 220)) < 180.0, "Recall must recover the companion near the player.")
	check(str(runtime.get("companion_command")) == "follow", "Recall must restore follow mode.")

	await HeadlessRuntimeCleanup.release(self, runtime)


func finish() -> void:
	if failures.is_empty():
		print("Companion Director smoke test passed: commands, hold, seek, discovery, persistence, rewards and recall are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
