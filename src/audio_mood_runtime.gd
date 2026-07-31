extends "res://src/audio_mood_controller.gd"

const RUNTIME_SAMPLE_RATE := 22050.0
const RUNTIME_BUFFER_LENGTH := 0.35
const RUNTIME_MAX_FRAMES_PER_FILL := 4096

var ambience_sample_clock := 0


func _ready() -> void:
	super._ready()
	# Godot's generator workflow starts playback before retrieving the playback
	# object, then fills the available buffer immediately to avoid a startup gap.
	update_mix(RUNTIME_BUFFER_LENGTH)
	fill_music()
	fill_ambience()
	fill_sfx()


func create_generator_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.bus = player_name if AudioServer.get_bus_index(player_name) >= 0 else "Master"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = RUNTIME_SAMPLE_RATE
	generator.buffer_length = RUNTIME_BUFFER_LENGTH
	player.stream = generator
	add_child(player)
	player.play()
	return player


func resolve_active_profile(force: bool) -> void:
	var previous_profile_id := active_profile_id
	super.resolve_active_profile(force)
	if force or previous_profile_id != active_profile_id:
		ambience_sample_clock = 0
		ambience_phase = 0.0
		ambience_filter = 0.0


func fill_ambience() -> void:
	if ambience_player == null:
		return
	var playback := ambience_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := mini(playback.get_frames_available(), RUNTIME_MAX_FRAMES_PER_FILL)
	if frames <= 0:
		return
	var kind := AudioMoodCatalog.text(active_profile, "ambience", "kind", "room_tone")
	var tone_hz := clampf(AudioMoodCatalog.number(active_profile, "ambience", "tone_hz", 52.0), 20.0, 1200.0)
	var motion := clampf(AudioMoodCatalog.number(active_profile, "ambience", "motion", 0.22), 0.0, 1.0)
	for _frame_index in range(frames):
		var noise := deterministic_noise(ambience_sample_clock * 13)
		ambience_filter = lerpf(ambience_filter, noise, 0.002 + motion * 0.018)
		ambience_phase = fmod(ambience_phase + tone_hz / RUNTIME_SAMPLE_RATE, 1.0)
		var hum := sin(ambience_phase * TAU)
		var texture := ambience_sample(kind, ambience_phase, ambience_filter, ambience_sample_clock)
		var sample := soft_clip((hum * 0.24 + texture * 0.76) * ambience_gain_current)
		playback.push_frame(Vector2(sample * 0.96, sample))
		ambience_sample_clock += 1


func update_events() -> void:
	var flow := runtime_integer("flow", FLOW_SPLASH)
	var map_id := current_map_id()
	var era_id := runtime_string("current_era_id")
	var cinematic_id := runtime_string("active_cinematic_id")
	var dialogue_text := runtime_string("dialogue")
	var menu_open := menu_is_open()
	var player_health := runtime_integer("player_health", previous_player_health)
	var companion_health := runtime_integer("companion_health", previous_companion_health)
	var attack_timer := runtime_number("player_attack_timer", 0.0)
	var clock_shards := runtime_integer("clock_shards", previous_clock_shards)
	var combat_active := combat_is_active()
	var travel_queued := false
	if previous_flow >= 0 and flow != previous_flow:
		if flow == FLOW_GAME:
			queue_sound("travel")
			travel_queued = true
		elif flow == FLOW_TITLE:
			queue_sound("menu_open")
	if not previous_map_id.is_empty() and map_id != previous_map_id and not travel_queued:
		queue_sound("travel")
	if not previous_era_id.is_empty() and era_id != previous_era_id:
		queue_sound("shift")
	if previous_player_health >= 0 and player_health < previous_player_health:
		queue_sound("hurt")
	if previous_companion_health >= 0 and companion_health < previous_companion_health:
		queue_sound("companion_hurt")
	if attack_timer > 0.0 and previous_attack_timer <= 0.0:
		queue_sound("attack")
	if previous_clock_shards >= 0 and clock_shards > previous_clock_shards:
		queue_sound("pickup")
	if menu_open != previous_menu_open:
		queue_sound("menu_open" if menu_open else "menu_close")
	if previous_dialogue.is_empty() and not dialogue_text.is_empty():
		queue_sound("dialogue")
	if previous_cinematic_id.is_empty() and not cinematic_id.is_empty():
		queue_sound("cinematic")
	if combat_active != previous_combat_active:
		queue_sound("combat_start" if combat_active else "combat_end")
	update_entity_hit_events()
	previous_flow = flow
	previous_map_id = map_id
	previous_era_id = era_id
	previous_cinematic_id = cinematic_id
	previous_dialogue = dialogue_text
	previous_menu_open = menu_open
	previous_player_health = player_health
	previous_companion_health = companion_health
	previous_attack_timer = attack_timer
	previous_clock_shards = clock_shards
	previous_combat_active = combat_active


func update_entity_hit_events() -> void:
	var next_hits: Dictionary = {}
	var entities: Array = runtime_array("runtime_entities")
	for entity_value in entities:
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value as Dictionary
		var entity_id := str(entity.get("placement_id", entity.get("state_key", "")))
		if entity_id.is_empty():
			continue
		var is_hit := float(entity.get("hit_flash", 0.0)) > 0.0
		if is_hit and not bool(previous_entity_hits.get(entity_id, false)):
			queue_sound("impact")
		next_hits[entity_id] = is_hit
	previous_entity_hits = next_hits


func ambience_clock_value() -> int:
	return ambience_sample_clock


func generator_players_ready() -> bool:
	return (
		music_player != null
		and ambience_player != null
		and sfx_player != null
		and music_player.has_stream_playback()
		and ambience_player.has_stream_playback()
		and sfx_player.has_stream_playback()
	)
