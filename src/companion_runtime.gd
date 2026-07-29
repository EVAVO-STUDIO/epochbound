extends "res://src/combat_director_runtime.gd"

const CompanionModel = preload("res://src/game/companion_model.gd")
const CompanionValidator = preload("res://src/content/companion_validator.gd")

const COMMAND_NOTICE_DURATION := 1.25
const SEEK_PULSE_SPEED := 5.5

var companion_command := "follow"
var companion_hold_position := Vector2.ZERO
var companion_seek_target: Dictionary = {}
var companion_notice := ""
var companion_notice_timer := 0.0
var companion_discovery_pulse := 0.0


func load_campaign(path: String) -> bool:
	var validation := CompanionValidator.validate_campaign_path(path)
	if not validation.get("ok", false):
		load_error = format_errors(validation.get("errors", []))
		push_error("Companion validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	var loaded := super.load_campaign(path)
	if loaded:
		reset_companion_director_state()
	return loaded


func load_fallback_campaign() -> void:
	super.load_fallback_campaign()
	reset_companion_director_state()


func reset_companion_director_state() -> void:
	companion_command = "follow"
	companion_hold_position = companion
	companion_seek_target = {}
	companion_notice = ""
	companion_notice_timer = 0.0
	companion_discovery_pulse = 0.0


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	var activated := super.activate_map(map_id, entry_id, requested_era, use_transition)
	if activated:
		companion_command = "follow"
		companion_hold_position = companion
		companion_seek_target = {}
	return activated


func shift_to_next_era() -> void:
	super.shift_to_next_era()
	companion_seek_target = {}
	if companion_command == "seek":
		start_seek()
	elif companion_command == "stay":
		companion_hold_position = recover_from_entity_collision(companion_hold_position, COMPANION_RADIUS)


func update_game(delta: float) -> void:
	companion_notice_timer = maxf(0.0, companion_notice_timer - delta)
	companion_discovery_pulse += delta * SEEK_PULSE_SPEED
	if companion_notice_timer <= 0.0:
		companion_notice = ""
	if (
		flow == Flow.GAME
		and dialogue.is_empty()
		and transition_lock <= 0.45
		and companion_enabled()
	):
		if Input.is_action_just_pressed("companion_command"):
			cycle_companion_command()
		if Input.is_action_just_pressed("companion_recall"):
			recall_companion()
	super.update_game(delta)


func companion_profile() -> Dictionary:
	return CompanionModel.profile(campaign)


func cycle_companion_command() -> void:
	var commands := CompanionModel.allowed_commands(companion_profile())
	if commands.is_empty():
		set_companion_command("follow")
		return
	var index := commands.find(companion_command)
	if index < 0:
		index = 0
	else:
		index = (index + 1) % commands.size()
	set_companion_command(commands[index])


func set_companion_command(command: String) -> void:
	var commands := CompanionModel.allowed_commands(companion_profile())
	if not commands.has(command):
		command = "follow"
	companion_command = command
	companion_seek_target = {}
	match command:
		"stay":
			companion_hold_position = companion
		"seek":
			start_seek()
		"guard", "follow":
			pass
		_:
			companion_command = "follow"
	set_companion_notice(
		CompanionModel.command_description(companion_command, companion_name()),
		COMMAND_NOTICE_DURATION
	)


func recall_companion() -> void:
	companion_command = "follow"
	companion_seek_target = {}
	var profile := companion_profile()
	var fallback := player - facing * CompanionModel.follow_distance(profile)
	companion = MapModel.nearest_recovery_point(map_data, player, current_era_id, fallback)
	companion = recover_from_entity_collision(companion, COMPANION_RADIUS)
	companion_hold_position = companion
	set_companion_notice("%s returns at once." % companion_name().capitalize(), COMMAND_NOTICE_DURATION)


func start_seek() -> void:
	companion_seek_target = CompanionModel.nearest_unresolved_cue(
		map_data,
		current_era_id,
		session_state,
		companion,
		CompanionModel.seek_radius(companion_profile())
	)
	if companion_seek_target.is_empty():
		companion_command = "follow"
		set_companion_notice(
			"%s finds no unbroken trail nearby." % companion_name().capitalize(),
			1.5
		)


func update_companion(delta: float) -> void:
	var profile := companion_profile()
	var recovery_distance := CompanionModel.recovery_distance(profile)
	var player_offset := player - companion
	if player_offset.length() > recovery_distance:
		if companion_command == "stay" and player_offset.length() <= recovery_distance * 1.5:
			return
		recall_companion()
		return
	match companion_command:
		"stay":
			move_companion_toward(companion_hold_position, COMPANION_SPEED, delta)
		"seek":
			update_companion_seek(delta)
		"guard":
			var guard_target := player - facing * CompanionModel.guard_distance(profile)
			move_companion_toward(guard_target, COMPANION_SPEED, delta)
		_:
			var follow_target := player - facing * CompanionModel.follow_distance(profile)
			move_companion_toward(follow_target, COMPANION_SPEED, delta)


func update_companion_seek(delta: float) -> void:
	if companion_seek_target.is_empty():
		start_seek()
		if companion_seek_target.is_empty():
			return
	var target_position := CompanionModel.cue_position(companion_seek_target)
	var reveal_radius := CompanionModel.cue_radius(companion_seek_target)
	if companion.distance_to(target_position) <= reveal_radius:
		reveal_companion_cue(companion_seek_target)
		return
	move_companion_toward(target_position, CompanionModel.seek_speed(companion_profile()), delta)


func move_companion_toward(target_position: Vector2, speed: float, delta: float) -> void:
	if companion.distance_to(target_position) <= 2.0:
		return
	var navigation_target := MapModel.navigation_step(map_data, companion, target_position, current_era_id)
	var direction := companion.direction_to(navigation_target)
	if direction.length_squared() <= 0.001:
		direction = companion.direction_to(target_position)
	if direction.length_squared() <= 0.001:
		return
	var distance := minf(speed * delta, companion.distance_to(navigation_target))
	move_actor("companion", companion + direction * distance)


func reveal_companion_cue(cue: Dictionary) -> void:
	var map_id := str(map_data.get("id", "map"))
	var state_key := CompanionModel.cue_state_key(map_id, cue)
	if session_state.has(state_key):
		companion_command = "follow"
		companion_seek_target = {}
		return
	session_state[state_key] = "discovered"
	var reward := CompanionModel.cue_reward(cue)
	clock_shards += reward
	var message := CompanionModel.cue_message(cue, companion_name())
	if reward > 0:
		message += "\nA clock shard answers the discovery."
	dialogue = message
	companion_command = "follow"
	companion_seek_target = {}
	companion_hold_position = companion
	set_companion_notice("TRAIL DISCOVERED", 1.6)


func perform_companion_attack() -> void:
	if companion_command in ["stay", "seek"]:
		return
	if companion_command != "guard":
		super.perform_companion_attack()
		return
	if not companion_enabled() or companion_attack_lock > 0.0 or companion_health <= 0:
		return
	var target_index := EncounterModel.nearest_entity_index(
		runtime_entities,
		companion,
		["enemy"],
		CompanionModel.guard_attack_range(companion_profile())
	)
	if target_index < 0:
		return
	companion_attack_lock = COMPANION_ATTACK_COOLDOWN
	companion_attack_timer = 0.18
	damage_entity(target_index, COMPANION_ATTACK_DAMAGE, companion_name())


func set_companion_notice(value: String, duration: float) -> void:
	companion_notice = value
	companion_notice_timer = duration


func draw_game() -> void:
	super.draw_game()
	draw_companion_cues()
	draw_companion_command_hud()


func draw_companion() -> void:
	super.draw_companion()
	match companion_command:
		"stay":
			draw_circle(companion + Vector2(0, -22), 4.0, Color("d7c78f"), false, 2.0)
			draw_line(companion + Vector2(-7, -22), companion + Vector2(7, -22), Color("d7c78f"), 2.0)
		"seek":
			var pulse := 12.0 + sin(companion_discovery_pulse) * 3.0
			draw_circle(companion, pulse, Color(0.9, 0.78, 0.35, 0.55), false, 2.0)
		"guard":
			draw_arc(companion + Vector2(0, -4), 16.0, -PI, 0.0, 16, Color("d97258"), 2.0)
		_:
			pass


func draw_companion_cues() -> void:
	var offset := camera_offset()
	var map_id := str(map_data.get("id", "map"))
	for value in CompanionModel.all_cues(map_data):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var cue: Dictionary = value
		if not CompanionModel.cue_is_available(cue, current_era_id):
			continue
		if session_state.has(CompanionModel.cue_state_key(map_id, cue)):
			continue
		var is_target := not companion_seek_target.is_empty() and str(companion_seek_target.get("id", "")) == str(cue.get("id", ""))
		if not is_target and not CompanionModel.visible_before_discovery(cue):
			continue
		var screen_position := CompanionModel.cue_position(cue) - offset
		var radius := CompanionModel.cue_radius(cue)
		var pulse := 1.0 + sin(companion_discovery_pulse + screen_position.x * 0.01) * 0.15
		var color := Color("f4d56e") if is_target else Color(0.7, 0.78, 0.66, 0.5)
		draw_circle(screen_position, radius * pulse, color, false, 2.0)
		draw_line(screen_position + Vector2(-5, 0), screen_position + Vector2(5, 0), color, 1.0)
		draw_line(screen_position + Vector2(0, -5), screen_position + Vector2(0, 5), color, 1.0)


func draw_companion_command_hud() -> void:
	if not companion_enabled():
		return
	var label := CompanionModel.command_label(companion_command)
	draw_rect(Rect2(286, 9, 164, 48), Color(0.03, 0.04, 0.05, 0.88))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(298, 29),
		"%s: %s" % [companion_name(), label],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("e9d48a")
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(298, 47),
		"R / Y COMMAND   F / LB RECALL",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		Color("a8b0b6")
	)
	if not companion_notice.is_empty() and dialogue.is_empty():
		draw_rect(Rect2(142, 96, 356, 26), Color(0.03, 0.04, 0.05, 0.86))
		draw_centered(companion_notice, 114, 10, Color("f3dda0"))
