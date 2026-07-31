@tool
extends EditorPlugin

var studio: Control


func _enter_tree() -> void:
	studio = preload("res://addons/epochbound_audio_mood_studio/audio_mood_studio.gd").new()
	studio.name = "AudioMoodStudio"
	get_editor_interface().get_editor_main_screen().add_child(studio)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(studio):
		studio.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(studio):
		studio.visible = visible


func _get_plugin_name() -> String:
	return "Audio"


func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_base_control().get_theme_icon("AudioStreamPlayer", "EditorIcons")
