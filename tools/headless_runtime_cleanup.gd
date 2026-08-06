extends RefCounted

const AUDIO_PLAYER_NAMES := [&"Music", &"Ambience", &"SFX"]
const AUDIO_SETTLE_FRAMES := 30
const AUDIO_SETTLE_SECONDS := 0.25
const POST_TIMER_FRAMES := 2


static func release(tree: SceneTree, runtime: Node) -> void:
	if runtime == null or not is_instance_valid(runtime):
		return
	var audio := runtime.get_node_or_null("AudioMood")
	if audio != null:
		audio.set_process(false)
		for player_name in AUDIO_PLAYER_NAMES:
			var player := audio.get_node_or_null(NodePath(player_name)) as AudioStreamPlayer
			if player == null:
				continue
			player.stop()
			player.stream_paused = true
			player.stream = null
	if runtime.get_parent() != null:
		runtime.get_parent().remove_child(runtime)
	runtime.free()
	audio = null
	for _frame_index in range(AUDIO_SETTLE_FRAMES):
		await tree.process_frame
	await tree.create_timer(AUDIO_SETTLE_SECONDS).timeout
	for _frame_index in range(POST_TIMER_FRAMES):
		await tree.process_frame
