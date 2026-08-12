extends SceneTree

const AudioMoodStudio = preload("res://addons/epochbound_audio_mood_studio/audio_mood_studio_current.gd")
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var studio := AudioMoodStudio.new()
	root.add_child(studio)
	check(studio.load_campaign_path(CAMPAIGN_PATH), "Strict Audio Studio must load the reference campaign.")
	check(studio.profile_count() == 9, "Audio Studio must expose nine reference profiles including both Hideaway eras.")
	check(studio.boss_stem_count() == 3, "Audio Studio must expose the three reference boss stems.")
	var pattern: Array[int] = studio.parse_pattern("0, 2 - 4 rest 5")
	check(pattern == [0, 2, -99, 4, -99, 5], "Pattern parser must preserve notes and explicit rests.")
	var encoded: String = studio.pattern_text(pattern, true)
	check(encoded == "0 2 - 4 - 5", "Pattern formatter must produce stable editor text.")
	var profile: Dictionary = studio.profile_by_id("underworks_ashen")
	check(str(profile.get("display_name", "")) == "Underworks Ashen", "Audio Studio must preserve profile identity.")
	root.remove_child(studio)
	studio.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Audio and Mood Studio smoke test passed: strict campaign loading, profile state, three reference boss stems and pattern editing are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
