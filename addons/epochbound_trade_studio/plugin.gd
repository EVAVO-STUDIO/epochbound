@tool
extends EditorPlugin

const TradeStudio = preload("res://addons/epochbound_trade_studio/trade_studio_supply.gd")
const EditorPluginIcon = preload("res://addons/epochbound_editor_common/editor_plugin_icon.gd")
const ICON_CANDIDATES := ["AssetLib", "Resource"]

var studio


func _enter_tree() -> void:
	studio = TradeStudio.new()
	studio.name = "Trade"
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
	return "Trade"


func _get_plugin_icon() -> Texture2D:
	return EditorPluginIcon.resolve(get_editor_interface(), ICON_CANDIDATES)
