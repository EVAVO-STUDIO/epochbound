@tool
extends RefCounted

const CURRENT_RUNTIME_SCRIPT := "res://src/supply_runtime.gd"
const CURRENT_OVERLAY_SCRIPT := "res://src/combat_readability_overlay.gd"
const CURRENT_AUDIO_SCRIPT := "res://src/audio_mood_runtime.gd"
const CURRENT_CAMERA_SCRIPT := "res://src/presentation_camera.gd"

const REQUIRED_RUNTIME_METHODS := [
	"load_campaign",
	"update_game",
	"sync_runtime_entities",
	"start_conversation",
	"capture_save_profile",
	"active_capabilities",
	"open_merchant",
	"apply_due_supply_restock",
	"supply_region_status_text",
	"supply_runtime_contract_ok",
	"start_reload",
	"update_projectiles",
	"update_boss_engagements",
	"start_cinematic",
	"open_player_settings",
	"close_player_settings",
	"player_setting_number",
	"player_setting_bool",
	"player_settings_rows",
	"player_settings_contract_ok",
	"presentation_overlay_handles_combat_readability",
	"root_presentation_suppression_contract_ok"
]

const REQUIRED_OVERLAY_METHODS := [
	"initialize_from_runtime",
	"sprite_runtime_contract_ok",
	"animation_polish_contract_ok",
	"adventure_feedback_contract_ok",
	"environment_animation_contract_ok",
	"combat_readability_contract_ok",
	"player_settings_overlay_contract_ok",
	"draw_adventure_hud",
	"draw_projectile_overlay",
	"draw_boss_status_overlay",
	"draw_player_settings_panel"
]

const REQUIRED_AUDIO_METHODS := [
	"generator_players_ready",
	"generator_skip_count",
	"apply_player_volume_settings",
	"player_volume_snapshot",
	"player_settings_audio_contract_ok"
]


static func script_path(object: Object) -> String:
	if object == null:
		return ""
	var script_value: Variant = object.get_script()
	if script_value is Script:
		return str((script_value as Script).resource_path)
	return ""


static func missing_methods(object: Object, required: Array) -> PackedStringArray:
	var output := PackedStringArray()
	if object == null:
		for method_name in required:
			output.append(str(method_name))
		return output
	for method_name in required:
		if not object.has_method(str(method_name)):
			output.append(str(method_name))
	return output


static func validate_runtime_scene(runtime: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	if runtime == null:
		errors.append("Runtime scene did not instantiate.")
		return errors

	var runtime_path := script_path(runtime)
	if runtime_path != CURRENT_RUNTIME_SCRIPT:
		errors.append("Runtime root must use %s, found %s." % [CURRENT_RUNTIME_SCRIPT, runtime_path])
	for method_name in missing_methods(runtime, REQUIRED_RUNTIME_METHODS):
		errors.append("Runtime root is missing method '%s'." % method_name)

	var audio := runtime.get_node_or_null("AudioMood")
	if audio == null:
		errors.append("Runtime scene is missing AudioMood.")
	else:
		var audio_path := script_path(audio)
		if audio_path != CURRENT_AUDIO_SCRIPT:
			errors.append("AudioMood must use %s, found %s." % [CURRENT_AUDIO_SCRIPT, audio_path])
		for method_name in missing_methods(audio, REQUIRED_AUDIO_METHODS):
			errors.append("AudioMood is missing method '%s'." % method_name)
		if audio.has_method("player_settings_audio_contract_ok") and not bool(audio.call("player_settings_audio_contract_ok")):
			errors.append("AudioMood did not apply the current player volume settings.")

	var camera := runtime.get_node_or_null("PresentationCamera")
	if not camera is Camera2D:
		errors.append("Runtime scene is missing PresentationCamera as Camera2D.")
	else:
		var camera_path := script_path(camera)
		if camera_path != CURRENT_CAMERA_SCRIPT:
			errors.append("PresentationCamera must use %s, found %s." % [CURRENT_CAMERA_SCRIPT, camera_path])
		if not camera.has_method("desired_camera_offset"):
			errors.append("PresentationCamera is missing desired_camera_offset().")

	var layer := runtime.get_node_or_null("PresentationLayer")
	if not layer is CanvasLayer:
		errors.append("Runtime scene is missing PresentationLayer as CanvasLayer.")
	elif (layer as CanvasLayer).layer <= 0:
		errors.append("PresentationLayer must render above the world canvas.")

	var overlay := runtime.get_node_or_null("PresentationLayer/PresentationOverlay")
	if overlay == null:
		errors.append("Runtime scene is missing PresentationOverlay.")
	else:
		var overlay_path := script_path(overlay)
		if overlay_path != CURRENT_OVERLAY_SCRIPT:
			errors.append("PresentationOverlay must use %s, found %s." % [CURRENT_OVERLAY_SCRIPT, overlay_path])
		for method_name in missing_methods(overlay, REQUIRED_OVERLAY_METHODS):
			errors.append("PresentationOverlay is missing method '%s'." % method_name)
		if overlay.has_method("player_settings_overlay_contract_ok") and not bool(overlay.call("player_settings_overlay_contract_ok")):
			errors.append("PresentationOverlay did not preserve the player-settings presentation contract.")

	if runtime.has_method("supply_runtime_contract_ok") and not bool(runtime.call("supply_runtime_contract_ok")):
		errors.append("Runtime root did not initialise every regional supply cycle.")
	if runtime.has_method("player_settings_contract_ok") and not bool(runtime.call("player_settings_contract_ok")):
		errors.append("Runtime root did not confirm valid player-local settings.")
	if runtime.has_method("presentation_overlay_handles_combat_readability"):
		if not bool(runtime.call("presentation_overlay_handles_combat_readability")):
			errors.append("Runtime root did not recognise presentation-owned combat rendering.")
	if runtime.has_method("root_presentation_suppression_contract_ok"):
		if not bool(runtime.call("root_presentation_suppression_contract_ok")):
			errors.append("Runtime root did not confirm selective combat presentation suppression.")
	return errors


static func runtime_scene_is_valid(runtime: Node) -> bool:
	return validate_runtime_scene(runtime).is_empty()
