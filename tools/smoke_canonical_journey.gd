extends SceneTree

const HeadlessRuntimeCleanup = preload("res://tools/headless_runtime_cleanup.gd")
const ReferenceJourneyDriver = preload("res://tools/reference_journey_driver.gd")

const RUNTIME_SCENE := "res://src/app.tscn"
const CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_journey")


func run_journey() -> void:
	var packed := ResourceLoader.load(
		RUNTIME_SCENE,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	check(packed is PackedScene, "Canonical journey scene must load.")
	if not packed is PackedScene:
		finish()
		return
	var runtime := (packed as PackedScene).instantiate()
	check(runtime != null, "Canonical journey scene must instantiate.")
	if runtime == null:
		finish()
		return
	root.add_child(runtime)
	await process_frame

	var result := ReferenceJourneyDriver.complete(
		runtime,
		CAMPAIGN_PATH,
		Callable(self, "check")
	)
	var completion_value: Variant = result.get("completion_profile", {})
	check(
		typeof(completion_value) == TYPE_DICTIONARY,
		"Canonical journey driver must return its completion profile."
	)
	if typeof(completion_value) == TYPE_DICTIONARY:
		check(
			not str((completion_value as Dictionary).get("checksum", "")).is_empty(),
			"Canonical journey driver completion profile must remain checksummed."
		)

	await HeadlessRuntimeCleanup.release(self, runtime)
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Canonical journey smoke test passed: merchant purchase, discovery, crafting, travel, era shift, boss phases, durable outcomes and two exact save restorations are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
