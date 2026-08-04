extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100


func _process(delta: float) -> void:
	var session := get_parent().get_node_or_null("MultiplayerSession") if get_parent() != null else null
	if session != null and session.has_method("post_runtime_process"):
		session.call("post_runtime_process", delta)


func multiplayer_post_tick_contract_ok() -> bool:
	return process_priority > 0 and process_mode == Node.PROCESS_MODE_ALWAYS
