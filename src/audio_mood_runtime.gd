extends "res://src/audio_mood_controller.gd"

const Catalog = preload("res://src/content/audio_mood_catalog.gd")
const StrictValidator = preload("res://src/content/audio_mood_strict_validator.gd")
const RUNTIME_SAMPLE_RATE := 22050.0
const RUNTIME_BUFFER_LENGTH := 0.35
const RUNTIME_MAX_FRAMES_PER_FILL := 4096
const RUNTIME_PRIME_PASSES := 4
const RUNTIME_STARTUP_MAX_ATTEMPTS := 8
const RUNTIME_FLOW_SPLASH := 0
const RUNTIME_FLOW_TITLE := 1
const RUNTIME_FLOW_GAME := 4
const PLAYER_VOLUME_FLOOR_DB := -80.0

var ambience_sample_clock := 0
var generator_startup_attempts := 0
var generator_startup_finished := false


func _ready() -> void:
	super._ready()
	# Child ready callbacks run before the root runtime has finished campaign,
	# map and authoring-system startup. Start every generator in a paused state
	# and complete priming only once Godot exposes all playback objects.
	start_generator_players_paused()
	apply_player_volume_settings()
	call_deferred("complete_generator_startup")


func _process(delta: float) -> void:
	super._process(delta)
	apply_player_volume_settings()


func create_generator_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.bus = player_name if AudioServer.get_bus_index(player_name) >= 0 else "Master"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = RUNTIME_SAMPLE_RATE
	generator.buffer_length = RUNTIME_BUFFER_LENGTH
	player.stream = generator
	player.stream_paused = true
	add_child(player)
	return player


func start_generator_players_paused() -> void:
	for player in [music_player, ambience_player, sfx_player]:
		if player == null:
			continue
		player.stream_paused = true
		player.play()


func complete_generator_startup() -> void:
	if not is_inside_tree() or generator_startup_finished:
		return
	generator_startup_attempts += 1
	if not generator_players_ready():
		schedule_generator_startup_retry()
		return
	var runtime_campaign_key := current_runtime_campaign_key()
	if not runtime_campaign_key.is_empty() and runtime_campaign_key != loaded_campaign_key:
		initialize_from_runtime()
	update_mix(RUNTIME_BUFFER_LENGTH)
	prime_generator_buffers()
	apply_player_volume_settings()
	if music_sample_clock <= 0 or ambience_sample_clock <= 0:
		schedule_generator_startup_retry()
		return
	generator_startup_finished = true
	resume_generator_players()


func schedule_generator_startup_retry() -> void:
	if generator_startup_attempts >= RUNTIME_STARTUP_MAX_ATTEMPTS:
		return
	get_tree().process_frame.connect(complete_generator_startup, CONNECT_ONE_SHOT)


func resume_generator_players() -> void:
	for player in [music_player, ambience_player, sfx_player]:
		if player != null:
			player.stream_paused = false


func prime_generator_buffers() -> void:
	for _pass in range(RUNTIME_PRIME_PASSES):
		var music_before := music_sample_clock
		var ambience_before := ambience_sample_clock
		fill_music()
		fill_ambience()
		fill_sfx()
		if music_sample_clock == music_before and ambience_sample_clock == ambience_before:
			break


func generator_startup_complete() -> bool:
	return generator_startup_finished and generator_players_ready()


func generator_startup_attempt_count() -> int:
	return generator_startup_attempts


func initialize_from_runtime() -> void:
	var runtime := runtime_root()
	if runtime == null:
		return
	var campaign_value: Variant = runtime.get("campaign")
	var campaign: Dictionary = campaign_value as Dictionary if typeof(campaign_value) == TYPE_DICTIONARY else {}
	var campaign_path := str(runtime.get("campaign_path"))
	var campaign_id := str(campaign.get("id", "fallback"))
	loaded_campaign_key = "%s|%s" % [campaign_path, campaign_id]
	var result: Dictionary = Catalog.load_catalogs(campaign_path, campaign)
	definitions = result.get("definitions", {})
	bindings.clear()
	var bindings_value: Variant = result.get("bindings", [])
	if typeof(bindings_value) == TYPE_ARRAY:
		for binding_value in bindings_value as Array:
			if typeof(binding_value) == TYPE_DICTIONARY:
				bindings.append((binding_value as Dictionary).duplicate(true))
	title_profile_id = str(result.get("title_profile_id", Catalog.DEFAULT_PROFILE_ID))
	if not campaign_path.is_empty():
		var validation: Dictionary = StrictValidator.validate_audio_only(campaign_path)
		if not bool(validation.get("ok", false)):
			definitions = {Catalog.DEFAULT_PROFILE_ID: Catalog.default_profile()}
			bindings.clear()
			title_profile_id = Catalog.DEFAULT_PROFILE_ID
	resolve_active_profile(true)


func current_runtime_campaign_key() -> String:
	var runtime := runtime_root()
	if runtime == null:
		return ""
	var campaign_value: Variant = runtime.get("campaign")
	var campaign: Dictionary = campaign_value as Dictionary if typeof(campaign_value) == TYPE_DICTIONARY else {}
	return "%s|%s" % [
		str(runtime.get("campaign_path")),
		str(campaign.get("id", "fallback"))
	]


func resolve_active_profile(force: bool) -> void:
	# Child _ready() callbacks run before the root runtime's _ready() callback.
	# An explicit profile resolution can therefore arrive after the parent has
	# loaded its campaign but before this node's first _process() refresh. Never
	# resolve against that stale fallback catalogue.
	var runtime_campaign_key := current_runtime_campaign_key()
	if not runtime_campaign_key.is_empty() and runtime_campaign_key != loaded_campaign_key:
		initialize_from_runtime()
		return
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
	var kind := Catalog.text(active_profile, "ambience", "kind", "room_tone")
	var tone_hz := clampf(Catalog.number(active_profile, "ambience", "tone_hz", 52.0), 20.0, 1200.0)
	var motion := clampf(Catalog.number(active_profile, "ambience", "motion", 0.22), 0.0, 1.0)
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
	var flow := runtime_integer("flow", RUNTIME_FLOW_SPLASH)
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
		if flow == RUNTIME_FLOW_GAME:
			queue_sound("travel")
			travel_queued = true
		elif flow == RUNTIME_FLOW_TITLE:
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


func menu_is_open() -> bool:
	return runtime_boolean("player_settings_open") or super.menu_is_open()


func player_setting_number(setting_id: String, fallback: float = 1.0) -> float:
	var runtime := runtime_root()
	if runtime == null or not runtime.has_method("player_setting_number"):
		return fallback
	return clampf(float(runtime.call("player_setting_number", setting_id, fallback)), 0.0, 1.0)


func gain_to_db(gain: float) -> float:
	if gain <= 0.0001:
		return PLAYER_VOLUME_FLOOR_DB
	return clampf(20.0 * log(gain) / log(10.0), PLAYER_VOLUME_FLOOR_DB, 0.0)


func apply_player_volume_settings() -> void:
	var master := player_setting_number("master_volume", 1.0)
	var music := master * player_setting_number("music_volume", 1.0)
	var ambience := master * player_setting_number("ambience_volume", 1.0)
	var sfx := master * player_setting_number("sfx_volume", 1.0)
	if music_player != null:
		music_player.volume_db = gain_to_db(music)
	if ambience_player != null:
		ambience_player.volume_db = gain_to_db(ambience)
	if sfx_player != null:
		sfx_player.volume_db = gain_to_db(sfx)


func player_volume_snapshot() -> Dictionary:
	var master := player_setting_number("master_volume", 1.0)
	var music := master * player_setting_number("music_volume", 1.0)
	var ambience := master * player_setting_number("ambience_volume", 1.0)
	var sfx := master * player_setting_number("sfx_volume", 1.0)
	return {
		"master": master,
		"music": music,
		"ambience": ambience,
		"sfx": sfx,
		"music_db": gain_to_db(music),
		"ambience_db": gain_to_db(ambience),
		"sfx_db": gain_to_db(sfx)
	}


func player_settings_audio_contract_ok() -> bool:
	if not generator_players_ready():
		return false
	var snapshot := player_volume_snapshot()
	return (
		music_player != null
		and ambience_player != null
		and sfx_player != null
		and is_equal_approx(music_player.volume_db, float(snapshot.get("music_db", 0.0)))
		and is_equal_approx(ambience_player.volume_db, float(snapshot.get("ambience_db", 0.0)))
		and is_equal_approx(sfx_player.volume_db, float(snapshot.get("sfx_db", 0.0)))
	)


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


func generator_skip_count() -> int:
	var total := 0
	for player in [music_player, ambience_player, sfx_player]:
		if player == null or not player.has_stream_playback():
			continue
		var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback != null:
			total += playback.get_skips()
	return total
