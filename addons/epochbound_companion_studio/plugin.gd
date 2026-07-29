@tool
extends EditorPlugin

const CompanionStudio = preload("res://addons/epochbound_companion_studio/companion_studio.gd")

var studio


func _enter_tree() -> void:
	studio = CompanionStudio.new()
	studio.name = "Companion Studio"
	studio.visible = false
	EditorInterface.get_editor_main_screen().add_child(studio)


func _exit_tree() -> void:
	if is_instance_valid(studio):
		studio.queue_free()
	studio = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(studio):
		studio.visible = visible


func _get_plugin_name() -> String:
	return "Companion"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("BoneAttachment2D", "EditorIcons")
