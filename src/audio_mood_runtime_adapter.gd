extends "res://src/audio_mood_controller.gd"


func _ready() -> void:
	super._ready()
	fill_music()
	fill_ambience()
	fill_sfx()


func create_generator_player(player_name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = player_name
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.bus = player_name
	var generator: AudioStreamGenerator = AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = BUFFER_LENGTH
	player.stream = generator
	add_child(player)
	player.play()
	return player
