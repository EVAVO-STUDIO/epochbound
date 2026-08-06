@tool
extends EditorPlugin
const EditorPluginIcon = preload("res://addons/epochbound_editor_common/editor_plugin_icon.gd")
const ICON_CANDIDATES := ["AnimatedSprite2D", "Sprite2D"]

var studio: Control


func _enter_tree() -> void:
	studio = preload("res://addons/epochbound_sprite_animation_studio/sprite_animation_studio_current.gd").new()
	studio.name = "SpriteAnimationStudio"
	get_editor_interface().get_editor_main_screen().add_child(studio)
	_make_visible(false)


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
	return "Sprite"


func _get_plugin_icon() -> Texture2D:
	return EditorPluginIcon.resolve(get_editor_interface(), ICON_CANDIDATES)
