extends SceneTree

const RuntimeSceneContract = preload("res://src/game/runtime_scene_contract.gd")
const RUNTIME_SCENE := "res://src/app.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var packed: Resource = ResourceLoader.load(RUNTIME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(packed is PackedScene, "Canonical runtime scene must load as a PackedScene.")
	if not packed is PackedScene:
		finish()
		return

	var runtime := (packed as PackedScene).instantiate()
	check(runtime != null, "Canonical runtime scene must instantiate.")
	if runtime == null:
		finish()
		return
	root.add_child(runtime)
	await process_frame

	var contract_errors := RuntimeSceneContract.validate_runtime_scene(runtime)
	for error in contract_errors:
		failures.append(str(error))
	check(RuntimeSceneContract.runtime_scene_is_valid(runtime), "Canonical runtime contract must pass after ready.")

	var audio := runtime.get_node_or_null("AudioMood")
	if audio != null and audio.has_method("generator_players_ready"):
		check(bool(audio.call("generator_players_ready")), "Audio generators must be ready in the complete playable scene.")
		check(int(audio.call("generator_skip_count")) == 0, "Complete-scene startup must not report Audio generator underruns.")

	var capabilities_before: PackedStringArray = runtime.call("active_capabilities") as PackedStringArray
	runtime.set("suppress_root_combat_hud", true)
	check(not bool(runtime.call("root_presentation_suppression_contract_ok")), "The root suppression contract must report its temporary draw-only state.")
	var capabilities_during: PackedStringArray = runtime.call("active_capabilities") as PackedStringArray
	check(capabilities_during == capabilities_before, "Selective combat HUD suppression must not alter gameplay capabilities.")
	runtime.set("suppress_root_combat_hud", false)
	check(bool(runtime.call("root_presentation_suppression_contract_ok")), "Selective combat HUD suppression must restore immediately after drawing.")

	var overlay := runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	var layer := runtime.get_node_or_null("PresentationLayer")
	check(overlay != null and layer is CanvasLayer, "Presentation layer and overlay must exist for fallback testing.")
	if overlay != null and layer is CanvasLayer:
		(layer as CanvasLayer).remove_child(overlay)
		check(not bool(runtime.call("presentation_overlay_handles_combat_readability")), "Removing the overlay must restore root fallback ownership.")
		check(not bool(runtime.call("root_presentation_suppression_contract_ok")), "Root suppression must disable itself when the high presentation layer is unavailable.")
		(layer as CanvasLayer).add_child(overlay)
		check(bool(runtime.call("presentation_overlay_handles_combat_readability")), "Reattaching the overlay must restore presentation-owned combat rendering.")
		check(bool(runtime.call("root_presentation_suppression_contract_ok")), "Reattaching the overlay must restore duplicate-render suppression.")

	root.remove_child(runtime)
	runtime.free()
	finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func finish() -> void:
	if failures.is_empty():
		print("Runtime scene contract smoke test passed: canonical scripts, inherited systems, selective HUD ownership, Audio readiness, CanvasLayer fallback and restoration are coherent.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
