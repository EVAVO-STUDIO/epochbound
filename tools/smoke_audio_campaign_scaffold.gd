extends SceneTree

const CampaignStudio = preload("res://addons/epochbound_campaign_studio/campaign_studio_current.gd")
const Repository = preload("res://src/content/campaign_repository.gd")
const Validator = preload("res://src/content/audio_mood_validator.gd")
const CampaignPackage = preload("res://src/content/campaign_package.gd")

const CAMPAIGN_ID := "audio_scaffold_smoke"
const CAMPAIGN_ROOT := "res://campaigns/" + CAMPAIGN_ID
const CAMPAIGN_PATH := CAMPAIGN_ROOT + "/campaign.json"
const AUDIO_PATH := CAMPAIGN_ROOT + "/audio/core.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	CampaignPackage.remove_tree(CAMPAIGN_ROOT)
	var studio := CampaignStudio.new()
	root.add_child(studio)
	await process_frame
	var id_edit := studio.get("campaign_id_edit") as LineEdit
	check(id_edit != null, "Campaign Studio must expose its new-campaign ID field.")
	if id_edit != null:
		id_edit.text = CAMPAIGN_ID
		studio.call("create_campaign")
	check(FileAccess.file_exists(CAMPAIGN_PATH), "New Campaign must create campaign.json.")
	check(FileAccess.file_exists(AUDIO_PATH), "New Campaign must create audio/core.json.")
	if FileAccess.file_exists(CAMPAIGN_PATH):
		var campaign_result: Dictionary = Repository.read_json(CAMPAIGN_PATH)
		check(bool(campaign_result.get("ok", false)), "Scaffolded campaign manifest must parse.")
		var campaign: Dictionary = campaign_result.get("data", {})
		var audio_files_value: Variant = campaign.get("audio_files", [])
		var audio_files: Array = audio_files_value as Array if typeof(audio_files_value) == TYPE_ARRAY else []
		check(audio_files == ["audio/core.json"], "Scaffolded campaign must bind its Audio catalogue.")
		var validation: Dictionary = Validator.validate_campaign_path(CAMPAIGN_PATH)
		check(bool(validation.get("ok", false)), "Scaffolded campaign must pass the current Audio-aware validator.")
	root.remove_child(studio)
	studio.free()
	CampaignPackage.remove_tree(CAMPAIGN_ROOT)
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Audio campaign scaffold smoke test passed: new campaigns receive a bound valid Audio catalogue.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
