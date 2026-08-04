extends Node

var previous_save_operation_depth := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -50


func _process(_delta: float) -> void:
	var runtime := get_parent()
	var session := runtime.get_node_or_null("MultiplayerSession") if runtime != null else null
	if runtime == null or session == null:
		return
	if session.has_method("blocks_manual_save") and bool(session.call("blocks_manual_save")) and Input.is_action_just_pressed("save_profiles"):
		runtime.set("dialogue", "Online companions and invaders are temporary. Close the online session before opening a manual save profile.")
		if session.has_method("set_notice"):
			session.call("set_notice", "MANUAL SAVING IS LOCKED WHILE REMOTE PEERS ARE PRESENT")
	if session.has_method("blocks_autosave") and bool(session.call("blocks_autosave")):
		var value: Variant = runtime.get("save_operation_depth")
		if typeof(value) == TYPE_INT:
			previous_save_operation_depth = int(value)
			runtime.set("save_operation_depth", previous_save_operation_depth + 1)


func restore_after_runtime() -> void:
	if previous_save_operation_depth < 0:
		return
	var runtime := get_parent()
	if runtime != null:
		runtime.set("save_operation_depth", previous_save_operation_depth)
	previous_save_operation_depth = -1


func multiplayer_save_guard_contract_ok() -> bool:
	return process_priority < 0 and process_mode == Node.PROCESS_MODE_ALWAYS
