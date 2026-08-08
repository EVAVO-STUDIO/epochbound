extends Node

const AudioMoodCatalog = preload("res://src/content/audio_mood_catalog.gd")
const AudioMoodValidator = preload("res://src/content/audio_mood_validator.gd")

const SAMPLE_RATE := 22050.0
const BUFFER_LENGTH := 0.35
const MAX_FRAMES_PER_FILL := 4096
const FLOW_SPLASH := 0
const FLOW_TITLE := 1
const FLOW_CAMPAIGN_SELECT := 2
const FLOW_INTRO := 3
const FLOW_GAME := 4
const FLOW_PAUSED := 5
const REST_STEP := -99

var music_player: AudioStreamPlayer
var ambience_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

var definitions: Dictionary = {}
var bindings: Array[Dictionary] = []
var boss_stems: Dictionary = {}
var active_profile: Dictionary = {}
var active_profile_id := ""
var title_profile_id := AudioMoodCatalog.DEFAULT_PROFILE_ID
var loaded_campaign_key := ""
var loaded_context_key := ""
var active_boss_stem: Dictionary = {}
var active_boss_stem_key := ""

var music_sample_clock := 0
var music_phase := 0.0
var bass_phase := 0.0
var combat_phase := 0.0
var boss_stem_sample_clock := 0
var boss_stem_phase := 0.0
var boss_stem_bass_phase := 0.0
var boss_stem_mix_current := 0.0
var ambience_phase := 0.0
var ambience_filter := 0.0
var music_gain_current := 0.0
var ambience_gain_current := 0.0
var combat_mix_current := 0.0
var profile_gate := 0.0

var sfx_voices: Array[Dictionary] = []
var previous_flow := -1
var previous_map_id := ""
var previous_era_id := ""
var previous_cinematic_id := ""
var previous_dialogue := ""
var previous_menu_open := false
var previous_player_health := -1
var previous_companion_health := -1
var previous_attack_timer := 0.0
var previous_clock_shards := -1
var previous_entity_hits: Dictionary = {}
var previous_combat_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	create_audio_players()
	initialize_from_runtime()
	capture_runtime_state()


func runtime_root() -> Node:
	return get_parent()


func create_audio_players() -> void:
	music_player = create_generator_player("Music")
	ambience_player = create_generator_player("Ambience")
	sfx_player = create_generator_player("SFX")


func create_generator_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = BUFFER_LENGTH
	player.stream = generator
	add_child(player)
	player.play()
	return player


func initialize_from_runtime() -> void:
	var runtime := runtime_root()
	if runtime == null:
		return
	var campaign_value: Variant = runtime.get("campaign")
	var campaign: Dictionary = campaign_value as Dictionary if typeof(campaign_value) == TYPE_DICTIONARY else {}
	var campaign_path := str(runtime.get("campaign_path"))
	var campaign_id := str(campaign.get("id", "fallback"))
	loaded_campaign_key = "%s|%s" % [campaign_path, campaign_id]
	var result := AudioMoodCatalog.load_catalogs(campaign_path, campaign)
	definitions = result.get("definitions", {})
	boss_stems = result.get("boss_stems", {})
	bindings.clear()
	var bindings_value: Variant = result.get("bindings", [])
	if typeof(bindings_value) == TYPE_ARRAY:
		for binding_value in bindings_value as Array:
			if typeof(binding_value) == TYPE_DICTIONARY:
				bindings.append((binding_value as Dictionary).duplicate(true))
	title_profile_id = str(result.get("title_profile_id", AudioMoodCatalog.DEFAULT_PROFILE_ID))
	if not campaign_path.is_empty():
		var validation := AudioMoodValidator.validate_audio_only(campaign_path)
		if not bool(validation.get("ok", false)):
			definitions = {AudioMoodCatalog.DEFAULT_PROFILE_ID: AudioMoodCatalog.default_profile()}
			boss_stems.clear()
			bindings.clear()
			title_profile_id = AudioMoodCatalog.DEFAULT_PROFILE_ID
	resolve_active_profile(true)
	resolve_active_boss_stem(true)


func _process(delta: float) -> void:
	var runtime := runtime_root()
	if runtime == null:
		return
	var campaign_value: Variant = runtime.get("campaign")
	var campaign: Dictionary = campaign_value as Dictionary if typeof(campaign_value) == TYPE_DICTIONARY else {}
	var campaign_key := "%s|%s" % [str(runtime.get("campaign_path")), str(campaign.get("id", "fallback"))]
	if campaign_key != loaded_campaign_key:
		initialize_from_runtime()
	update_events()
	resolve_active_profile(false)
	resolve_active_boss_stem(false)
	update_mix(delta)
	fill_music()
	fill_ambience()
	fill_sfx()


func resolve_active_profile(force: bool) -> void:
	var runtime := runtime_root()
	if runtime == null:
		return
	var flow := runtime_integer("flow", FLOW_SPLASH)
	var map_id := ""
	var era_id := ""
	if flow == FLOW_GAME or flow == FLOW_PAUSED:
		var map_value: Variant = runtime.get("map_data")
		if typeof(map_value) == TYPE_DICTIONARY:
			map_id = str((map_value as Dictionary).get("id", ""))
		era_id = str(runtime.get("current_era_id"))
	var context_key := "%d|%s|%s" % [flow, map_id, era_id]
	if not force and context_key == loaded_context_key:
		return
	loaded_context_key = context_key
	var next_profile: Dictionary
	if flow == FLOW_GAME or flow == FLOW_PAUSED:
		next_profile = AudioMoodCatalog.resolved_profile(definitions, bindings, map_id, era_id)
	else:
		next_profile = AudioMoodCatalog.title_profile(definitions, title_profile_id)
	var next_id := str(next_profile.get("id", AudioMoodCatalog.DEFAULT_PROFILE_ID))
	if force or next_id != active_profile_id:
		active_profile = next_profile
		active_profile_id = next_id
		music_sample_clock = 0
		music_phase = 0.0
		bass_phase = 0.0
		combat_phase = 0.0
		profile_gate = 0.0


func current_boss_audio_context() -> Dictionary:
	var flow := runtime_integer("flow", FLOW_SPLASH)
	if flow != FLOW_GAME and flow != FLOW_PAUSED:
		return {}
	var engaged := runtime_dictionary("engaged_bosses")
	var contexts := runtime_dictionary("boss_contexts")
	var phases := runtime_dictionary("boss_phase_ids")
	var placement_ids := PackedStringArray()
	for placement_id_value in engaged.keys():
		if bool(engaged.get(placement_id_value, false)):
			placement_ids.append(str(placement_id_value))
	placement_ids.sort()
	for placement_id in placement_ids:
		var context_value: Variant = contexts.get(placement_id, {})
		if typeof(context_value) != TYPE_DICTIONARY:
			continue
		var context: Dictionary = context_value as Dictionary
		var boss_id := str(context.get("object_id", "")).strip_edges()
		var phase_id := str(phases.get(placement_id, "")).strip_edges()
		if boss_id.is_empty() or phase_id.is_empty():
			continue
		var stem := AudioMoodCatalog.boss_stem(boss_stems, boss_id, phase_id)
		if stem.is_empty():
			continue
		return {
			"key": AudioMoodCatalog.boss_stem_key(boss_id, phase_id),
			"boss_id": boss_id,
			"phase_id": phase_id,
			"placement_id": placement_id,
			"stem": stem
		}
	return {}


func resolve_active_boss_stem(force: bool) -> void:
	var context := current_boss_audio_context()
	var next_key := str(context.get("key", ""))
	if not force and next_key == active_boss_stem_key:
		return
	active_boss_stem_key = next_key
	var stem_value: Variant = context.get("stem", {})
	active_boss_stem = (stem_value as Dictionary).duplicate(true) if typeof(stem_value) == TYPE_DICTIONARY else {}
	boss_stem_sample_clock = 0
	boss_stem_phase = 0.0
	boss_stem_bass_phase = 0.0
	boss_stem_mix_current = 0.0


func boss_stem_snapshot() -> Dictionary:
	return {
		"key": active_boss_stem_key,
		"boss_id": str(active_boss_stem.get("boss_id", "")),
		"phase_id": str(active_boss_stem.get("phase_id", "")),
		"sample_clock": boss_stem_sample_clock,
		"tempo_multiplier": AudioMoodCatalog.boss_stem_number(active_boss_stem, "tempo_multiplier", 1.0),
		"melody_step_count": AudioMoodCatalog.boss_stem_integer_array(active_boss_stem, "melody_steps", []).size(),
		"stem": active_boss_stem.duplicate(true)
	}


func update_mix(delta: float) -> void:
	var music_gain := clampf(AudioMoodCatalog.number(active_profile, "music", "gain", 0.16), 0.0, 0.45)
	var ambience_gain := clampf(AudioMoodCatalog.number(active_profile, "ambience", "gain", 0.05), 0.0, 0.30)
	var flow := runtime_integer("flow", FLOW_SPLASH)
	var duck := 1.0
	if flow == FLOW_PAUSED:
		duck *= clampf(AudioMoodCatalog.number(active_profile, "mix", "pause_duck", 0.20), 0.05, 1.0)
	if menu_is_open() or not runtime_string("dialogue").is_empty() or not runtime_string("active_conversation_id").is_empty():
		duck *= clampf(AudioMoodCatalog.number(active_profile, "mix", "menu_duck", 0.42), 0.05, 1.0)
	if not runtime_string("active_cinematic_id").is_empty():
		duck *= clampf(AudioMoodCatalog.number(active_profile, "mix", "cinematic_duck", 0.28), 0.05, 1.0)
	if flow == FLOW_SPLASH:
		duck *= 0.0
	elif flow == FLOW_CAMPAIGN_SELECT:
		duck *= 0.72
	var fade_seconds := clampf(AudioMoodCatalog.number(active_profile, "mix", "crossfade_seconds", 0.8), 0.05, 4.0)
	var weight := 1.0 - exp(-maxf(delta, 0.0) * 5.0 / fade_seconds)
	profile_gate = lerpf(profile_gate, 1.0, clampf(weight, 0.0, 1.0))
	music_gain_current = lerpf(music_gain_current, music_gain * duck * profile_gate, clampf(weight, 0.0, 1.0))
	ambience_gain_current = lerpf(ambience_gain_current, ambience_gain * duck * profile_gate, clampf(weight, 0.0, 1.0))
	var combat_target := 1.0 if combat_is_active() else 0.0
	combat_mix_current = lerpf(combat_mix_current, combat_target, clampf(delta * 5.0, 0.0, 1.0))
	var boss_stem_target := 1.0 if not active_boss_stem.is_empty() else 0.0
	boss_stem_mix_current = lerpf(boss_stem_mix_current, boss_stem_target, clampf(delta * 3.5, 0.0, 1.0))


func fill_music() -> void:
	if music_player == null:
		return
	var playback := music_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := mini(playback.get_frames_available(), MAX_FRAMES_PER_FILL)
	if frames <= 0:
		return
	var tempo := clampf(AudioMoodCatalog.number(active_profile, "music", "tempo_bpm", 78.0), 40.0, 200.0)
	var root_midi := clampi(AudioMoodCatalog.integer(active_profile, "music", "root_midi", 45), 24, 84)
	var scale: Array[int] = AudioMoodCatalog.integer_array(active_profile, "music", "scale", [0, 2, 3, 7, 9])
	var melody: Array[int] = AudioMoodCatalog.integer_array(active_profile, "music", "melody_steps", [0, REST_STEP, 2, REST_STEP])
	var bass: Array[int] = AudioMoodCatalog.integer_array(active_profile, "music", "bass_steps", [0, REST_STEP, REST_STEP, REST_STEP])
	var waveform := AudioMoodCatalog.text(active_profile, "music", "waveform", "triangle")
	var pulse_width := clampf(AudioMoodCatalog.number(active_profile, "music", "pulse_width", 0.35), 0.10, 0.90)
	var combat_gain := clampf(AudioMoodCatalog.number(active_profile, "music", "combat_gain", 0.08), 0.0, 0.30)
	var stem_active := not active_boss_stem.is_empty()
	var stem_tempo := clampf(tempo * AudioMoodCatalog.boss_stem_number(active_boss_stem, "tempo_multiplier", 1.0), 40.0, 240.0)
	var stem_root := clampi(root_midi + int(active_boss_stem.get("root_offset", 0)), 0, 127)
	var stem_melody: Array[int] = AudioMoodCatalog.boss_stem_integer_array(active_boss_stem, "melody_steps", [0, REST_STEP, 2, REST_STEP])
	var stem_bass: Array[int] = AudioMoodCatalog.boss_stem_integer_array(active_boss_stem, "bass_steps", [0, REST_STEP, REST_STEP, REST_STEP])
	var stem_waveform := AudioMoodCatalog.boss_stem_text(active_boss_stem, "waveform", "triangle")
	var stem_pulse_width := clampf(AudioMoodCatalog.boss_stem_number(active_boss_stem, "pulse_width", 0.35), 0.10, 0.90)
	var stem_gain := clampf(AudioMoodCatalog.boss_stem_number(active_boss_stem, "gain", 0.0), 0.0, 0.25)
	var stem_percussion_gain := clampf(AudioMoodCatalog.boss_stem_number(active_boss_stem, "percussion_gain", 0.0), 0.0, 0.20)
	var samples_per_step := maxi(1, int(SAMPLE_RATE * 60.0 / tempo / 4.0))
	var stem_samples_per_step := maxi(1, int(SAMPLE_RATE * 60.0 / stem_tempo / 4.0))
	for _frame_index in range(frames):
		var step_index := int(music_sample_clock / samples_per_step)
		var step_phase := float(music_sample_clock % samples_per_step) / float(samples_per_step)
		var envelope := minf(1.0, step_phase / 0.06) * maxf(0.0, 1.0 - step_phase * 0.72)
		var sample := 0.0
		var melody_degree := melody[step_index % melody.size()]
		if melody_degree != REST_STEP:
			var melody_hz := degree_frequency(root_midi + 12, melody_degree, scale)
			music_phase = fmod(music_phase + melody_hz / SAMPLE_RATE, 1.0)
			sample += oscillator(waveform, music_phase, pulse_width) * envelope * 0.66
		var bass_degree := bass[step_index % bass.size()]
		if bass_degree != REST_STEP:
			var bass_hz := degree_frequency(root_midi - 12, bass_degree, scale)
			bass_phase = fmod(bass_phase + bass_hz / SAMPLE_RATE, 1.0)
			sample += oscillator("triangle", bass_phase, 0.5) * envelope * 0.34
		if combat_mix_current > 0.001:
			var combat_hz := degree_frequency(root_midi + 24, melody_degree if melody_degree != REST_STEP else 0, scale)
			combat_phase = fmod(combat_phase + combat_hz / SAMPLE_RATE, 1.0)
			var beat_gate := 1.0 if posmod(step_index, 2) == 0 else 0.35
			var percussion := deterministic_noise(music_sample_clock) * pow(1.0 - step_phase, 5.0) * beat_gate
			sample += (oscillator("pulse", combat_phase, 0.18) * 0.34 + percussion * 0.20) * combat_mix_current * combat_gain
		if stem_active:
			var stem_step_index := int(boss_stem_sample_clock / stem_samples_per_step)
			var stem_step_phase := float(boss_stem_sample_clock % stem_samples_per_step) / float(stem_samples_per_step)
			var stem_envelope := minf(1.0, stem_step_phase / 0.05) * maxf(0.0, 1.0 - stem_step_phase * 0.68)
			var stem_sample := 0.0
			var stem_melody_degree := stem_melody[stem_step_index % stem_melody.size()]
			if stem_melody_degree != REST_STEP:
				var stem_hz := degree_frequency(stem_root + 12, stem_melody_degree, scale)
				boss_stem_phase = fmod(boss_stem_phase + stem_hz / SAMPLE_RATE, 1.0)
				stem_sample += oscillator(stem_waveform, boss_stem_phase, stem_pulse_width) * stem_envelope * stem_gain
			var stem_bass_degree := stem_bass[stem_step_index % stem_bass.size()]
			if stem_bass_degree != REST_STEP:
				var stem_bass_hz := degree_frequency(stem_root - 12, stem_bass_degree, scale)
				boss_stem_bass_phase = fmod(boss_stem_bass_phase + stem_bass_hz / SAMPLE_RATE, 1.0)
				stem_sample += oscillator("triangle", boss_stem_bass_phase, 0.5) * stem_envelope * stem_gain * 0.58
			var stem_beat_gate := 1.0 if posmod(stem_step_index, 2) == 0 else 0.28
			var stem_percussion := deterministic_noise(boss_stem_sample_clock * 37 + 11) * pow(1.0 - stem_step_phase, 6.0) * stem_beat_gate
			stem_sample += stem_percussion * stem_percussion_gain
			sample += stem_sample * boss_stem_mix_current
			boss_stem_sample_clock += 1
		sample = soft_clip(sample * music_gain_current)
		playback.push_frame(Vector2(sample, sample))
		music_sample_clock += 1


func fill_ambience() -> void:
	if ambience_player == null:
		return
	var playback := ambience_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := mini(playback.get_frames_available(), MAX_FRAMES_PER_FILL)
	if frames <= 0:
		return
	var kind := AudioMoodCatalog.text(active_profile, "ambience", "kind", "room_tone")
	var tone_hz := clampf(AudioMoodCatalog.number(active_profile, "ambience", "tone_hz", 52.0), 20.0, 1200.0)
	var motion := clampf(AudioMoodCatalog.number(active_profile, "ambience", "motion", 0.22), 0.0, 1.0)
	for frame_index in range(frames):
		var noise := deterministic_noise(music_sample_clock + frame_index * 13)
		ambience_filter = lerpf(ambience_filter, noise, 0.002 + motion * 0.018)
		ambience_phase = fmod(ambience_phase + tone_hz / SAMPLE_RATE, 1.0)
		var hum := sin(ambience_phase * TAU)
		var texture := ambience_sample(kind, ambience_phase, ambience_filter, music_sample_clock + frame_index)
		var sample := (hum * 0.24 + texture * 0.76) * ambience_gain_current
		sample = soft_clip(sample)
		playback.push_frame(Vector2(sample * 0.96, sample))


func ambience_sample(kind: String, phase: float, filtered_noise: float, clock: int) -> float:
	match kind:
		"insects":
			var chirp_gate := 1.0 if fmod(float(clock) / SAMPLE_RATE * 3.7, 1.0) > 0.91 else 0.0
			return filtered_noise * 0.25 + sin(phase * TAU * 7.0) * chirp_gate * 0.45
		"embers", "cinders":
			var crackle := deterministic_noise(clock * 17) if absf(deterministic_noise(clock * 5)) > 0.985 else 0.0
			return filtered_noise * 0.42 + crackle * 0.58
		"machinery":
			return sin(phase * TAU * 0.5) * 0.36 + filtered_noise * 0.28 + sin(phase * TAU * 3.0) * 0.12
		"furnace":
			return filtered_noise * 0.56 + sin(phase * TAU * 0.33) * 0.34
		"pollen":
			return filtered_noise * 0.32 + sin(phase * TAU * 1.5) * 0.10
		"rain":
			return filtered_noise * 0.72 + deterministic_noise(clock * 31) * 0.16
		"wind":
			return filtered_noise * 0.70
		_:
			return filtered_noise * 0.42


func fill_sfx() -> void:
	if sfx_player == null:
		return
	var playback := sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := mini(playback.get_frames_available(), MAX_FRAMES_PER_FILL)
	if frames <= 0:
		return
	for _frame_index in range(frames):
		var sample := 0.0
		for index in range(sfx_voices.size() - 1, -1, -1):
			var voice: Dictionary = sfx_voices[index]
			var remaining := float(voice.get("remaining", 0.0))
			var duration := maxf(0.001, float(voice.get("duration", 0.1)))
			if remaining <= 0.0:
				sfx_voices.remove_at(index)
				continue
			var progress := 1.0 - remaining / duration
			var start_hz := float(voice.get("start_hz", 220.0))
			var end_hz := float(voice.get("end_hz", start_hz))
			var frequency := lerpf(start_hz, end_hz, progress)
			var phase := fmod(float(voice.get("phase", 0.0)) + frequency / SAMPLE_RATE, 1.0)
			var wave := str(voice.get("waveform", "pulse"))
			var tone := deterministic_noise(int(remaining * SAMPLE_RATE) * 19 + index * 31) if wave == "noise" else oscillator(wave, phase, float(voice.get("pulse_width", 0.25)))
			var envelope := pow(maxf(0.0, 1.0 - progress), float(voice.get("decay", 2.0)))
			sample += tone * envelope * float(voice.get("gain", 0.20))
			voice["phase"] = phase
			voice["remaining"] = remaining - 1.0 / SAMPLE_RATE
			sfx_voices[index] = voice
		sample = soft_clip(sample)
		playback.push_frame(Vector2(sample, sample))


func queue_sound(kind: String) -> void:
	match kind:
		"attack":
			add_voice(270.0, 88.0, 0.13, 0.20, "noise", 2.3)
		"impact":
			add_voice(115.0, 42.0, 0.16, 0.24, "triangle", 2.5)
			add_voice(760.0, 220.0, 0.07, 0.10, "noise", 3.0)
		"hurt":
			add_voice(190.0, 64.0, 0.24, 0.25, "pulse", 2.2)
		"companion_hurt":
			add_voice(330.0, 170.0, 0.18, 0.16, "triangle", 2.0)
		"pickup":
			add_voice(660.0, 990.0, 0.16, 0.16, "triangle", 1.6)
			add_voice(990.0, 1320.0, 0.12, 0.10, "sine", 1.8)
		"shift":
			add_voice(220.0, 440.0, 0.42, 0.16, "triangle", 1.3)
			add_voice(330.0, 660.0, 0.42, 0.13, "sine", 1.3)
			add_voice(495.0, 990.0, 0.42, 0.10, "sine", 1.3)
		"travel":
			add_voice(420.0, 210.0, 0.28, 0.13, "triangle", 1.7)
		"menu_open":
			add_voice(520.0, 680.0, 0.07, 0.10, "pulse", 1.8)
		"menu_close":
			add_voice(620.0, 420.0, 0.07, 0.09, "pulse", 1.8)
		"dialogue":
			add_voice(760.0, 710.0, 0.035, 0.045, "pulse", 1.5)
		"combat_start":
			add_voice(82.0, 55.0, 0.44, 0.18, "triangle", 1.1)
			add_voice(330.0, 247.0, 0.22, 0.10, "pulse", 1.8)
		"combat_end":
			add_voice(392.0, 523.0, 0.24, 0.10, "triangle", 1.6)
		"cinematic":
			add_voice(196.0, 294.0, 0.36, 0.10, "sine", 1.4)
		_:
			add_voice(440.0, 440.0, 0.08, 0.08, "triangle", 2.0)


func add_voice(start_hz: float, end_hz: float, duration: float, gain: float, waveform: String, decay: float) -> void:
	sfx_voices.append({
		"start_hz": start_hz,
		"end_hz": end_hz,
		"duration": duration,
		"remaining": duration,
		"gain": gain,
		"waveform": waveform,
		"pulse_width": 0.24,
		"decay": decay,
		"phase": 0.0
	})
	if sfx_voices.size() > 24:
		sfx_voices.pop_front()


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
	if previous_flow >= 0 and flow != previous_flow:
		if flow == FLOW_GAME:
			queue_sound("travel")
		elif flow == FLOW_TITLE:
			queue_sound("menu_open")
	if not previous_map_id.is_empty() and map_id != previous_map_id:
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
	var entities := runtime_array("runtime_entities")
	for entity_value in entities:
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value
		var entity_id := str(entity.get("placement_id", entity.get("state_key", "")))
		if entity_id.is_empty():
			continue
		var is_hit := float(entity.get("hit_flash", 0.0)) > 0.0
		if is_hit and not bool(previous_entity_hits.get(entity_id, false)):
			queue_sound("impact")
		next_hits[entity_id] = is_hit
	previous_entity_hits = next_hits


func capture_runtime_state() -> void:
	previous_flow = runtime_integer("flow", FLOW_SPLASH)
	previous_map_id = current_map_id()
	previous_era_id = runtime_string("current_era_id")
	previous_cinematic_id = runtime_string("active_cinematic_id")
	previous_dialogue = runtime_string("dialogue")
	previous_menu_open = menu_is_open()
	previous_player_health = runtime_integer("player_health", -1)
	previous_companion_health = runtime_integer("companion_health", -1)
	previous_attack_timer = runtime_number("player_attack_timer", 0.0)
	previous_clock_shards = runtime_integer("clock_shards", -1)
	previous_combat_active = combat_is_active()


func combat_is_active() -> bool:
	var runtime := runtime_root()
	if runtime == null or runtime_integer("flow", FLOW_SPLASH) != FLOW_GAME:
		return false
	var boss_value: Variant = runtime.get("boss_contexts")
	if typeof(boss_value) == TYPE_DICTIONARY:
		for context_value in (boss_value as Dictionary).values():
			if typeof(context_value) != TYPE_DICTIONARY:
				continue
			var context: Dictionary = context_value
			if bool(context.get("engaged", false)) and not bool(context.get("completed", false)):
				return true
	var player := runtime_vector("player")
	for entity_value in runtime_array("runtime_entities"):
		if typeof(entity_value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_value
		if not bool(entity.get("active", true)):
			continue
		var definition_value: Variant = entity.get("definition", {})
		if typeof(definition_value) != TYPE_DICTIONARY:
			continue
		var definition: Dictionary = definition_value
		if str(definition.get("kind", "")) != "enemy":
			continue
		var position_value: Variant = entity.get("position", Vector2.ZERO)
		var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var mode := str(entity.get("mode", entity.get("state", "")))
		if ["pursue", "windup", "attack", "stagger"].has(mode) or position.distance_to(player) <= 150.0:
			return true
	return false


func menu_is_open() -> bool:
	return (
		runtime_boolean("inventory_open")
		or runtime_boolean("story_journal_open")
		or runtime_boolean("save_overlay_open")
		or runtime_boolean("merchant_open")
	)


func current_map_id() -> String:
	var runtime := runtime_root()
	if runtime == null:
		return ""
	var map_value: Variant = runtime.get("map_data")
	return str((map_value as Dictionary).get("id", "")) if typeof(map_value) == TYPE_DICTIONARY else ""


func degree_frequency(root_midi: int, degree: int, scale: Array[int]) -> float:
	if scale.is_empty():
		return midi_frequency(root_midi)
	var octave := floori(float(degree) / float(scale.size()))
	var index := posmod(degree, scale.size())
	return midi_frequency(root_midi + scale[index] + octave * 12)


func midi_frequency(midi_note: int) -> float:
	return 440.0 * pow(2.0, (float(midi_note) - 69.0) / 12.0)


func oscillator(waveform: String, phase: float, pulse_width: float) -> float:
	match waveform:
		"pulse":
			return 1.0 if phase < pulse_width else -1.0
		"triangle":
			return 1.0 - 4.0 * absf(phase - 0.5)
		"sine":
			return sin(phase * TAU)
		"noise":
			return deterministic_noise(int(phase * 100000.0))
		_:
			return sin(phase * TAU)


func deterministic_noise(seed: int) -> float:
	var value := sin(float(seed) * 12.9898 + 78.233) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0


func soft_clip(value: float) -> float:
	return value / (1.0 + absf(value))


func runtime_array(property_name: String) -> Array:
	var runtime := runtime_root()
	if runtime == null:
		return []
	var value: Variant = runtime.get(property_name)
	return value as Array if typeof(value) == TYPE_ARRAY else []


func runtime_dictionary(property_name: String) -> Dictionary:
	var runtime := runtime_root()
	if runtime == null:
		return {}
	var value: Variant = runtime.get(property_name)
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func runtime_vector(property_name: String) -> Vector2:
	var runtime := runtime_root()
	if runtime == null:
		return Vector2.ZERO
	var value: Variant = runtime.get(property_name)
	return value if value is Vector2 else Vector2.ZERO


func runtime_number(property_name: String, fallback: float) -> float:
	var runtime := runtime_root()
	if runtime == null:
		return fallback
	var value: Variant = runtime.get(property_name)
	return float(value) if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT else fallback


func runtime_integer(property_name: String, fallback: int) -> int:
	var runtime := runtime_root()
	if runtime == null:
		return fallback
	var value: Variant = runtime.get(property_name)
	return int(value) if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT else fallback


func runtime_boolean(property_name: String) -> bool:
	var runtime := runtime_root()
	return bool(runtime.get(property_name)) if runtime != null else false


func runtime_string(property_name: String) -> String:
	var runtime := runtime_root()
	return str(runtime.get(property_name)) if runtime != null else ""


func queued_sfx_count() -> int:
	return sfx_voices.size()
