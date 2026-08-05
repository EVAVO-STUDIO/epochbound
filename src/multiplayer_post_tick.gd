extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100


func _process(delta: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var session := parent.get_node_or_null("MultiplayerSession")
	if session != null and session.has_method("post_runtime_process"):
		session.call("post_runtime_process", delta)
	var save_guard := parent.get_node_or_null("MultiplayerSaveGuard")
	if save_guard != null and save_guard.has_method("restore_after_runtime"):
		save_guard.call("restore_after_runtime")


func multiplayer_post_tick_contract_ok() -> bool:
	return process_priority > 0 and process_mode == Node.PROCESS_MODE_ALWAYS
