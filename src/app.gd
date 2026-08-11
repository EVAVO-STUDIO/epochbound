extends Node2D

# The playable runtime consumes exactly the same campaign and world records as
# Campaign Studio. Placeholder drawing keeps every gameplay contract testable
# before final pixel art is introduced.

const CampaignRepository = preload("res://src/content/campaign_repository.gd")
const CampaignValidator = preload("res://src/content/campaign_validator.gd")
const MapModel = preload("res://src/content/map_model.gd")
const LocalisationCatalog = preload("res://src/content/localisation_catalog.gd")
const DEFAULT_CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const VIEW := Vector2(640, 360)
const PLAYER_SPEED := 105.0
const COMPANION_SPEED := 132.0
const COMPANION_FOLLOW_DISTANCE := 34.0
const COMPANION_RECOVERY_DISTANCE := 300.0
const PLAYER_RADIUS := 7.0
const COMPANION_RADIUS := 6.0


enum Flow { SPLASH, TITLE, CAMPAIGN_SELECT, INTRO, GAME, PAUSED }

var flow := Flow.SPLASH
var elapsed := 0.0
var intro_page := 0
var selected_menu := 0
var selected_campaign_index := 0
var player := Vector2(312, 220)
var companion := Vector2(270, 230)
var facing := Vector2.DOWN
var dialogue := ""
var shift_lock := 0.0
var transition_lock := 0.0
var campaign_path := DEFAULT_CAMPAIGN_PATH
var campaign: Dictionary = {}
var map_data: Dictionary = {}
var current_era_id := ""
var campaign_catalog: Array = []
var load_error := ""
var localisation_catalog: Dictionary = LocalisationCatalog.empty_catalog()
var current_locale := LocalisationCatalog.DEFAULT_LOCALE
var localisation_load_error := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_campaign_catalog()
	load_campaign(DEFAULT_CAMPAIGN_PATH)
	queue_redraw()


func refresh_campaign_catalog() -> void:
	campaign_catalog = CampaignRepository.scan_playable_campaigns()
	selected_campaign_index = clampi(selected_campaign_index, 0, maxi(0, campaign_catalog.size() - 1))


func load_campaign(path: String) -> bool:
	var validation := CampaignValidator.validate_campaign_path(path)
	if not validation.get("ok", false):
		load_error = format_errors(validation.get("errors", []))
		push_error("Campaign validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	var campaign_result := CampaignRepository.read_json(path)
	if not campaign_result.get("ok", false):
		load_error = format_errors(campaign_result.get("errors", []))
		push_error("Campaign load failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	campaign_path = path
	campaign = campaign_result.get("data", {})
	if not load_localisation_catalogs():
		load_error = localisation_load_error
		push_error("Localisation load failed: %s" % load_error)
		if map_data.is_empty():
			load_fallback_campaign()
		return false
	var start_map := String(campaign.get("start_map", ""))
	var start_era := String(campaign.get("start_era", ""))
	if not activate_map(start_map, "", start_era, false):
		load_error = "Start map '%s' could not be loaded." % start_map
		push_error(load_error)
		if map_data.is_empty():
			load_fallback_campaign()
		return false
	intro_page = 0
	load_error = ""
	return true


func load_fallback_campaign() -> void:
	campaign_path = ""
	campaign = CampaignRepository.default_campaign("epochbound_fallback", "EPOCHBOUND")
	load_localisation_catalogs()
	map_data = CampaignRepository.default_map("first_crossing", "First Crossing")
	current_era_id = first_era_id()
	reset_actor_positions()


func load_localisation_catalogs() -> bool:
	var result := LocalisationCatalog.load_catalogs(campaign_path, campaign)
	if not bool(result.get("ok", false)):
		localisation_catalog = LocalisationCatalog.empty_catalog()
		localisation_load_error = format_errors(result.get("errors", []))
		return false
	localisation_catalog = result
	localisation_load_error = ""
	localisation_changed()
	return true


func set_localisation_locale(locale_value: Variant) -> String:
	var resolved := LocalisationCatalog.sanitize_player_locale(locale_value)
	var changed := resolved != current_locale
	current_locale = resolved
	TranslationServer.set_locale(current_locale)
	if changed:
		localisation_changed()
	return current_locale


func localisation_changed() -> void:
	queue_redraw()


func localise(key: String, fallback: String = "", replacements: Dictionary = {}) -> String:
	return LocalisationCatalog.resolve(
		localisation_catalog,
		current_locale,
		key,
		fallback,
		replacements
	)


func localise_text(fallback: String, replacements: Dictionary = {}) -> String:
	return LocalisationCatalog.resolve(
		localisation_catalog,
		current_locale,
		"",
		fallback,
		replacements
	)


func localise_record(
	record: Dictionary,
	key_field: String,
	text_field: String,
	fallback: String = ""
) -> String:
	var text := str(record.get(text_field, fallback))
	var key := str(record.get(key_field, ""))
	return localise(key, text)


func campaign_title_text() -> String:
	return localise_record(campaign, "title_key", "title", "EPOCHBOUND")


func campaign_subtitle_text() -> String:
	return localise_record(campaign, "subtitle_key", "subtitle", "A NEW JOURNEY")


func localisation_contract_ok() -> bool:
	return (
		bool(localisation_catalog.get("ok", false))
		and LocalisationCatalog.supported_player_locales().has(current_locale)
		and LocalisationCatalog.has_message(localisation_catalog, "ui.title.options")
		and localise("ui.title.options", "OPTIONS") != "ui.title.options"
	)


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	var path := CampaignRepository.find_exact_map_path(campaign_path, campaign, map_id)
	if path.is_empty():
		return false
	var result := CampaignRepository.read_json(path)
	if not result.get("ok", false):
		return false
	var next_map: Dictionary = result.get("data", {})
	var previous_era := current_era_id
	var next_era := requested_era
	if next_era.is_empty() or next_era == "same":
		next_era = previous_era if map_has_era(next_map, previous_era) else first_era_id_for(next_map)
	elif not map_has_era(next_map, next_era):
		next_era = first_era_id_for(next_map)
	map_data = next_map
	current_era_id = next_era
	reset_actor_positions(entry_id)
	dialogue = ""
	transition_lock = 0.8 if use_transition else 0.0
	return true


func reset_actor_positions(entry_id: String = "") -> void:
	var spawns: Dictionary = map_data.get("spawns", {})
	var player_fallback := CampaignRepository.data_to_vector(spawns.get("player"), Vector2(312, 220))
	var companion_fallback := CampaignRepository.data_to_vector(spawns.get("companion"), Vector2(270, 230))
	if not entry_id.is_empty():
		var entry := MapModel.find_entry_point(map_data, entry_id, current_era_id)
		if not entry.is_empty():
			player = MapModel.entry_position(entry, "player", player_fallback)
			companion = MapModel.entry_position(entry, "companion", companion_fallback)
		else:
			player = player_fallback
			companion = companion_fallback
	else:
		player = player_fallback
		companion = companion_fallback
	player = recover_if_blocked(player, player_fallback, PLAYER_RADIUS)
	companion = recover_if_blocked(companion, companion_fallback, COMPANION_RADIUS)


func recover_if_blocked(position: Vector2, fallback: Vector2, radius: float) -> Vector2:
	if not MapModel.is_position_blocked(map_data, position, current_era_id, radius):
		return clamp_point_to_bounds(position, radius)
	var recovered := MapModel.nearest_recovery_point(map_data, position, current_era_id, fallback)
	return clamp_point_to_bounds(recovered, radius)


func format_errors(value: Variant) -> String:
	var lines := PackedStringArray()
	if typeof(value) == TYPE_ARRAY:
		for message in value:
			lines.append(String(message))
	return " | ".join(lines)


func _process(delta: float) -> void:
	elapsed += delta
	shift_lock = maxf(0.0, shift_lock - delta)
	transition_lock = maxf(0.0, transition_lock - delta)
	match flow:
		Flow.SPLASH:
			if elapsed > 2.4 or confirm():
				change_flow(Flow.TITLE)
		Flow.TITLE:
			update_title()
		Flow.CAMPAIGN_SELECT:
			update_campaign_select()
		Flow.INTRO:
			update_intro()
		Flow.GAME:
			update_game(delta)
		Flow.PAUSED:
			if Input.is_action_just_pressed("pause_game"):
				change_flow(Flow.GAME)
	queue_redraw()


func change_flow(next_flow: int) -> void:
	flow = next_flow
	elapsed = 0.0
	if next_flow != Flow.GAME:
		dialogue = ""


func confirm() -> bool:
	return Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept")


func title_menu() -> Array[String]:
	return [
		localise("ui.title.new_journey", "NEW JOURNEY"),
		localise("ui.title.campaigns", "CAMPAIGNS"),
		localise("ui.title.quick_start", "QUICK START"),
		localise("ui.title.quit", "QUIT")
	]


func update_title() -> void:
	var menu := title_menu()
	if Input.is_action_just_pressed("ui_up"):
		selected_menu = wrapi(selected_menu - 1, 0, menu.size())
	if Input.is_action_just_pressed("ui_down"):
		selected_menu = wrapi(selected_menu + 1, 0, menu.size())
	if confirm():
		match selected_menu:
			0:
				if load_campaign(DEFAULT_CAMPAIGN_PATH):
					change_flow(Flow.INTRO)
			1:
				refresh_campaign_catalog()
				change_flow(Flow.CAMPAIGN_SELECT)
			2:
				begin_game()
			3:
				get_tree().quit()


func update_campaign_select() -> void:
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause_game"):
		change_flow(Flow.TITLE)
		return
	if campaign_catalog.is_empty():
		return
	if Input.is_action_just_pressed("ui_up"):
		selected_campaign_index = wrapi(selected_campaign_index - 1, 0, campaign_catalog.size())
	if Input.is_action_just_pressed("ui_down"):
		selected_campaign_index = wrapi(selected_campaign_index + 1, 0, campaign_catalog.size())
	if confirm():
		var entry: Dictionary = campaign_catalog[selected_campaign_index]
		if load_campaign(String(entry.get("path", ""))):
			change_flow(Flow.INTRO)


func update_intro() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		begin_game()
	elif confirm():
		intro_page += 1
		if intro_page >= intro_pages().size():
			begin_game()


func begin_game() -> void:
	reset_actor_positions()
	current_era_id = String(campaign.get("start_era", first_era_id()))
	if current_era_id.is_empty():
		current_era_id = first_era_id()
	change_flow(Flow.GAME)


func update_game(delta: float) -> void:
	if Input.is_action_just_pressed("pause_game"):
		change_flow(Flow.PAUSED)
		return
	if transition_lock > 0.45:
		return
	if not dialogue.is_empty():
		if confirm() or Input.is_action_just_pressed("ui_cancel"):
			dialogue = ""
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.length_squared() > 0.01:
		facing = direction.normalized()
		move_actor("player", player + facing * player_move_speed_value() * delta)
	if companion_enabled():
		update_companion(delta)
	if transition_lock <= 0.0:
		var touch_connection := MapModel.find_connection_near(
			map_data,
			player,
			current_era_id,
			"touch"
		)
		if not touch_connection.is_empty() and travel_through(touch_connection):
			return
	if (
		Input.is_action_just_pressed("era_shift")
		and shift_lock <= 0.0
		and era_shifting_enabled()
	):
		shift_to_next_era()
	if Input.is_action_just_pressed("interact"):
		var connection := MapModel.find_connection_near(
			map_data,
			player,
			current_era_id,
			"interact"
		)
		if not connection.is_empty() and travel_through(connection):
			return
		interact()


func move_actor(actor_id: String, desired_position: Vector2) -> void:
	var radius := PLAYER_RADIUS if actor_id == "player" else COMPANION_RADIUS
	var current := player if actor_id == "player" else companion
	var target := clamp_point_to_bounds(desired_position, radius)
	var horizontal := Vector2(target.x, current.y)
	if not MapModel.is_position_blocked(map_data, horizontal, current_era_id, radius):
		current.x = horizontal.x
	var vertical := Vector2(current.x, target.y)
	if not MapModel.is_position_blocked(map_data, vertical, current_era_id, radius):
		current.y = vertical.y
	if actor_id == "player":
		player = current
	else:
		companion = current


func clamp_point_to_bounds(position: Vector2, radius: float) -> Vector2:
	var bounds: Dictionary = map_data.get("bounds", {})
	var left := float(bounds.get("left", 32.0)) + radius
	var right := float(bounds.get("right", VIEW.x - 32.0)) - radius
	var top := float(bounds.get("top", 96.0)) + radius
	var bottom := float(bounds.get("bottom", VIEW.y - 32.0)) - radius
	return Vector2(clampf(position.x, left, right), clampf(position.y, top, bottom))


func update_companion(delta: float) -> void:
	var offset := player - companion
	if offset.length() > COMPANION_RECOVERY_DISTANCE:
		var fallback := player - facing * COMPANION_FOLLOW_DISTANCE
		companion = MapModel.nearest_recovery_point(map_data, player, current_era_id, fallback)
		companion = recover_if_blocked(companion, fallback, COMPANION_RADIUS)
		return
	if offset.length() <= COMPANION_FOLLOW_DISTANCE:
		return
	var desired_follow := player - facing * COMPANION_FOLLOW_DISTANCE
	var navigation_target := MapModel.navigation_step(map_data, companion, desired_follow, current_era_id)
	var direction := companion.direction_to(navigation_target)
	if direction.length_squared() <= 0.001:
		return
	var distance := minf(COMPANION_SPEED * delta, companion.distance_to(navigation_target))
	move_actor("companion", companion + direction * distance)


func shift_to_next_era() -> void:
	var era_ids := all_era_ids()
	if era_ids.size() < 2:
		return
	var index := era_ids.find(current_era_id)
	current_era_id = String(era_ids[(index + 1) % era_ids.size()])
	shift_lock = 0.65
	var spawns: Dictionary = map_data.get("spawns", {})
	player = recover_if_blocked(
		player,
		CampaignRepository.data_to_vector(spawns.get("player"), player),
		PLAYER_RADIUS
	)
	companion = recover_if_blocked(
		companion,
		CampaignRepository.data_to_vector(spawns.get("companion"), companion),
		COMPANION_RADIUS
	)


func travel_through(connection: Dictionary) -> bool:
	if transition_lock > 0.0:
		return false
	if not authored_requirements_met(connection):
		dialogue = authored_blocked_message(connection)
		return false
	var target_map := String(connection.get("target_map", ""))
	var target_entry := String(connection.get("target_entry", ""))
	var target_era := String(connection.get("target_era", "same"))
	return activate_map(target_map, target_entry, target_era, true)


func interact() -> void:
	var closest: Dictionary = {}
	var closest_distance := INF
	for value in map_data.get("interactions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = value
		if not MapModel.available_in_era(interaction, current_era_id):
			continue
		var position := CampaignRepository.data_to_vector(interaction.get("position"))
		var distance := player.distance_to(position)
		if distance <= float(interaction.get("radius", 32.0)) and distance < closest_distance:
			closest = interaction
			closest_distance = distance
	if closest.is_empty():
		if companion_enabled():
			dialogue = localise_text(
				"%s sniffs the wind, then looks toward the nearest unfinished story." % companion_name().capitalize()
			)
		else:
			dialogue = localise_text("Nothing answers yet.")
	else:
		if authored_requirements_met(closest):
			dialogue = dialogue_for(closest)
		else:
			dialogue = authored_blocked_message(closest)


func player_move_speed_value() -> float:
	return PLAYER_SPEED


func authored_requirements_met(_record: Dictionary) -> bool:
	return true


func authored_blocked_message(record: Dictionary) -> String:
	return localise_record(
		record,
		"blocked_dialogue_key",
		"blocked_dialogue",
		"You cannot use this yet."
	)


func dialogue_for(interaction: Dictionary) -> String:
	var value: Variant = interaction.get("dialogue", "")
	if typeof(value) == TYPE_STRING:
		return localise(
			str(interaction.get("dialogue_key", "")),
			String(value)
		)
	if typeof(value) == TYPE_DICTIONARY:
		var dialogue_by_era: Dictionary = value
		var fallback := String(dialogue_by_era.get(current_era_id, dialogue_by_era.get("default", "...")))
		var keys_value: Variant = interaction.get("dialogue_keys", {})
		var keys: Dictionary = keys_value if typeof(keys_value) == TYPE_DICTIONARY else {}
		var key := str(keys.get(current_era_id, keys.get("default", "")))
		return localise(key, fallback)
	return localise_text("...")


func intro_pages() -> Array:
	var pages_value: Variant = campaign.get("intro", [])
	var pages: Array = pages_value if typeof(pages_value) == TYPE_ARRAY else []
	if pages.is_empty():
		return [localise_text("A journey begins beyond the edge of the authored world.")]
	var keys_value: Variant = campaign.get("intro_keys", [])
	var keys: Array = keys_value if typeof(keys_value) == TYPE_ARRAY else []
	var output: Array = []
	for index in range(pages.size()):
		var key := str(keys[index]) if index < keys.size() else ""
		output.append(localise(key, str(pages[index])))
	return output


func ruleset() -> Dictionary:
	return campaign.get("ruleset", {})


func companion_enabled() -> bool:
	return bool(ruleset().get("companion_enabled", true))


func era_shifting_enabled() -> bool:
	return bool(ruleset().get("era_shifting_enabled", true))


func first_era_id() -> String:
	return first_era_id_for(map_data)


func first_era_id_for(data: Dictionary) -> String:
	for value in data.get("eras", []):
		if typeof(value) == TYPE_DICTIONARY:
			var era: Dictionary = value
			return String(era.get("id", ""))
	return ""


func map_has_era(data: Dictionary, era_id: String) -> bool:
	if era_id.is_empty():
		return false
	for value in data.get("eras", []):
		if typeof(value) == TYPE_DICTIONARY and String(Dictionary(value).get("id", "")) == era_id:
			return true
	return false


func all_era_ids() -> Array:
	var ids: Array = []
	for value in map_data.get("eras", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var era: Dictionary = value
		var era_id := String(era.get("id", ""))
		if not era_id.is_empty():
			ids.append(era_id)
	return ids


func current_era() -> Dictionary:
	for value in map_data.get("eras", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var era: Dictionary = value
		if String(era.get("id", "")) == current_era_id:
			return era
	for value in map_data.get("eras", []):
		if typeof(value) == TYPE_DICTIONARY:
			return value
	return {}


func palette_color(key: String, fallback: String) -> Color:
	var era_data := current_era()
	var palette: Dictionary = era_data.get("palette", {})
	return Color.from_string(String(palette.get(key, fallback)), Color.from_string(fallback, Color.WHITE))


func player_name() -> String:
	var actors: Dictionary = campaign.get("actors", {})
	var actor: Dictionary = actors.get("player", {})
	return String(actor.get("name", "HERO"))


func companion_name() -> String:
	var actors: Dictionary = campaign.get("actors", {})
	var actor: Dictionary = actors.get("companion", {})
	return String(actor.get("name", "COMPANION"))


func actor_health(actor_id: String, fallback: int) -> int:
	var actors: Dictionary = campaign.get("actors", {})
	var actor: Dictionary = actors.get(actor_id, {})
	return int(actor.get("max_health", fallback))


func camera_offset() -> Vector2:
	var canvas: Dictionary = map_data.get("canvas", {})
	var world_size := Vector2(float(canvas.get("width", VIEW.x)), float(canvas.get("height", VIEW.y)))
	return Vector2(
		clampf(player.x - VIEW.x * 0.5, 0.0, maxf(0.0, world_size.x - VIEW.x)),
		clampf(player.y - VIEW.y * 0.5, 0.0, maxf(0.0, world_size.y - VIEW.y))
	)


func _draw() -> void:
	match flow:
		Flow.SPLASH:
			draw_splash()
		Flow.TITLE:
			draw_title()
		Flow.CAMPAIGN_SELECT:
			draw_campaign_select()
		Flow.INTRO:
			draw_intro()
		Flow.GAME:
			draw_game()
		Flow.PAUSED:
			draw_game()
			draw_pause()


func draw_splash() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("070a0f"))
	var pulse := 0.84 + sin(elapsed * 3.0) * 0.12
	draw_centered("EVAVO STUDIO", 148, 28, Color(0.91, 0.93, 0.96, pulse))
	draw_centered(localise("ui.splash.presents", "PRESENTS"), 190, 12, Color("788598"))


func draw_title() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("0b1017"))
	for index in range(11):
		var x := fmod(float(index * 83) + elapsed * (7.0 + index), 700.0) - 30.0
		draw_circle(Vector2(x, 52 + (index * 29) % 210), 1.2, Color("9eb6c7"))
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0, 280), Vector2(105, 238), Vector2(210, 271), Vector2(325, 208),
			Vector2(470, 270), Vector2(640, 224), Vector2(640, 360), Vector2(0, 360)
		]),
		Color("18282d")
	)
	draw_centered(campaign_title_text(), 65, 40, Color("e7d7a2"))
	draw_centered(campaign_subtitle_text(), 98, 12, Color("8fa9a5"))
	var menu := title_menu()
	for index in range(menu.size()):
		var active := index == selected_menu
		draw_string(ThemeDB.fallback_font, Vector2(205, 152 + index * 27), "◆" if active else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e7c66b"))
		draw_string(ThemeDB.fallback_font, Vector2(229, 152 + index * 27), menu[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff2c9") if active else Color("76858b"))
	draw_centered(localise("ui.title.confirm_select", "E / Z / A  CONFIRM     ARROWS  SELECT", {"confirm": "E / Z / A"}), 336, 10, Color("58656b"))


func draw_campaign_select() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("0a0e14"))
	draw_centered(localise("ui.campaigns.heading", "CHOOSE A CAMPAIGN"), 42, 24, Color("e7d7a2"))
	draw_centered(localise("ui.campaigns.subtitle", "Authored journeys share one runtime contract"), 65, 11, Color("7f939b"))
	if campaign_catalog.is_empty():
		draw_centered(localise("ui.campaigns.none", "NO VALID CAMPAIGNS FOUND"), 170, 16, Color("cc8d82"))
		draw_centered(localise("ui.campaigns.return", "ESC TO RETURN"), 210, 11, Color("78858c"))
		return
	var visible_count := mini(7, campaign_catalog.size())
	var start_index := clampi(selected_campaign_index - 3, 0, maxi(0, campaign_catalog.size() - visible_count))
	for row in range(visible_count):
		var index := start_index + row
		var entry: Dictionary = campaign_catalog[index]
		var active := index == selected_campaign_index
		var y := 104 + row * 30
		if active:
			draw_rect(Rect2(90, y - 20, 460, 26), Color("1f2a2f"))
		draw_string(ThemeDB.fallback_font, Vector2(108, y), "◆" if active else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e7c66b"))
		var entry_title := localise_text(String(entry.get("title", entry.get("id", "Campaign"))))
		var source_label := localise("ui.campaigns.custom", "CUSTOM") if entry.get("source", "built_in") == "user" else localise("ui.campaigns.built_in", "BUILT-IN")
		draw_string(ThemeDB.fallback_font, Vector2(132, y), entry_title, HORIZONTAL_ALIGNMENT_LEFT, 300, 15, Color("fff2c9") if active else Color("9aa7aa"))
		draw_string(ThemeDB.fallback_font, Vector2(455, y), source_label, HORIZONTAL_ALIGNMENT_LEFT, 90, 9, Color("88b8a1") if entry.get("source", "built_in") == "user" else Color("78858c"))
	if not load_error.is_empty():
		draw_centered(localise("ui.campaigns.load_failed", "SELECTED CAMPAIGN COULD NOT BE LOADED"), 319, 10, Color("d78f84"))
	else:
		draw_centered(localise("ui.campaigns.begin_return", "CONFIRM TO BEGIN   •   ESC TO RETURN"), 329, 10, Color("68747e"))


func draw_intro() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("05070a"))
	draw_rect(Rect2(58, 52, 524, 242), Color("111820"))
	draw_rect(Rect2(58, 52, 524, 242), Color("7b6a4f"), false, 2.0)
	draw_circle(Vector2(320, 142), 66, Color("26343a"))
	draw_circle(Vector2(320, 142), 39, Color("d7b666"), false, 3.0)
	draw_line(Vector2(320, 142), Vector2(320 + cos(elapsed) * 29, 142 + sin(elapsed) * 29), Color("f2df9b"), 2.0)
	var pages := intro_pages()
	var page_index := clampi(intro_page, 0, maxi(0, pages.size() - 1))
	draw_multiline_centered(String(pages[page_index]), 226, 15, Color("e8e3d5"))
	draw_centered(localise("ui.intro.continue_skip", "CONFIRM TO CONTINUE   •   ESC TO SKIP"), 330, 10, Color("68747e"))


func draw_game() -> void:
	var era_data: Dictionary = current_era()
	var canvas: Dictionary = map_data.get("canvas", {})
	var width := float(canvas.get("width", VIEW.x))
	var height := float(canvas.get("height", VIEW.y))
	var offset := camera_offset()
	draw_set_transform(-offset, 0.0, Vector2.ONE)
	draw_rect(Rect2(0, 0, width, height), palette_color("sky", "819a91"))
	var bounds: Dictionary = map_data.get("bounds", {})
	var ground_top := float(bounds.get("top", 96.0))
	draw_rect(Rect2(0, ground_top, width, height - ground_top), palette_color("ground", "4f6550"))
	draw_terrain_cells()
	for value in era_data.get("landmarks", []):
		if typeof(value) == TYPE_DICTIONARY:
			draw_landmark(value)
	draw_connections()
	if companion_enabled():
		draw_companion()
	draw_player()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_hud(era_data)
	if dialogue.is_empty():
		draw_centered(localise("ui.game.basic_controls", "MOVE: WASD / ARROWS   INTERACT: E / Z   SHIFT: Q / X"), 348, 9, Color("d7d0bd"))
	else:
		draw_dialogue()
	if transition_lock > 0.0:
		var alpha := clampf((transition_lock - 0.12) / 0.68, 0.0, 0.9)
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.03, 0.04, 0.05, alpha))


func draw_terrain_cells() -> void:
	var ground_fallback := palette_color("ground", "4f6550")
	for value in MapModel.resolved_cells(map_data, MapModel.TERRAIN_CELLS, current_era_id):
		var record: Dictionary = value
		var cell := Vector2i(int(record.get("x", -1)), int(record.get("y", -1)))
		var tile_id := String(record.get("tile", ""))
		var rect := MapModel.cell_rect(map_data, cell)
		var color := MapModel.terrain_color(map_data, tile_id, current_era_id, ground_fallback)
		draw_rect(rect, color)
		if tile_id == "water":
			draw_line(rect.position + Vector2(2, rect.size.y * 0.38), rect.position + Vector2(rect.size.x - 2, rect.size.y * 0.38), color.lightened(0.18), 1.0)
			draw_line(rect.position + Vector2(3, rect.size.y * 0.68), rect.position + Vector2(rect.size.x - 3, rect.size.y * 0.68), color.lightened(0.1), 1.0)
		elif tile_id == "cliff":
			draw_rect(rect.grow(-2.0), color.darkened(0.2), false, 2.0)


func draw_connections() -> void:
	for value in map_data.get("connections", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = value
		if not MapModel.available_in_era(connection, current_era_id):
			continue
		var position := CampaignRepository.data_to_vector(connection.get("position"))
		var radius := float(connection.get("radius", 24.0))
		var pulse := 0.55 + sin(elapsed * 3.5) * 0.18
		draw_circle(position, maxf(7.0, radius * 0.32), Color(0.91, 0.78, 0.35, pulse), false, 2.0)
		draw_line(position + Vector2(-5, 0), position + Vector2(5, 0), Color("f0d889"), 2.0)
		draw_line(position + Vector2(2, -3), position + Vector2(5, 0), Color("f0d889"), 2.0)
		draw_line(position + Vector2(2, 3), position + Vector2(5, 0), Color("f0d889"), 2.0)


func draw_landmark(landmark: Dictionary) -> void:
	var position := CampaignRepository.data_to_vector(landmark.get("position"))
	var size_value := float(landmark.get("size", 24.0))
	var kind := String(landmark.get("kind", "marker"))
	var accent := palette_color("accent", "e5d89f")
	var structure := palette_color("structure", "53625b")
	match kind:
		"sun":
			draw_circle(position, size_value, accent)
		"ruin":
			draw_rect(Rect2(position - Vector2(size_value * 0.5, size_value * 0.72), Vector2(size_value, size_value * 1.44)), structure)
			draw_rect(Rect2(position - Vector2(size_value * 0.18, size_value * 0.35), Vector2(size_value * 0.36, size_value * 0.7)), Color("1a2021"))
		"well":
			draw_circle(position + Vector2(0, 4), size_value, Color("313b3b"))
			draw_circle(position, size_value * 0.78, Color("10181b"))
		"tree":
			draw_line(position + Vector2(0, size_value), position - Vector2(0, size_value), structure, 6.0)
			draw_circle(position - Vector2(0, size_value * 0.55), size_value * 0.74, Color("3f5945"))
		"dead_tree":
			draw_line(position + Vector2(0, size_value), position - Vector2(0, size_value), structure, 5.0)
			draw_line(position - Vector2(0, size_value * 0.25), position + Vector2(size_value * 0.7, -size_value * 0.8), structure, 3.0)
			draw_line(position - Vector2(0, size_value * 0.1), position + Vector2(-size_value * 0.65, -size_value * 0.65), structure, 3.0)
		_:
			draw_circle(position, maxf(4.0, size_value * 0.25), accent)


func draw_companion() -> void:
	draw_circle(companion + Vector2(0, -4), 10, Color("3b2a24"))
	draw_circle(companion + Vector2(9, -9), 6, Color("5a3d2e"))
	draw_line(companion + Vector2(-7, -6), companion + Vector2(-14, -12), Color("3b2a24"), 3.0)


func draw_player() -> void:
	draw_circle(player + Vector2(0, -13), 8, Color("e2b38a"))
	draw_rect(Rect2(player + Vector2(-8, -6), Vector2(16, 22)), Color("334b68"))
	draw_line(player + Vector2(0, 6), player + facing * 18.0, Color("e8d69a"), 3.0)


func draw_hud(era_data: Dictionary) -> void:
	draw_rect(Rect2(10, 9, 236, 46), Color(0.03, 0.04, 0.05, 0.86))
	draw_string(ThemeDB.fallback_font, Vector2(21, 29), "%s  %d / %d" % [player_name(), actor_health("player", 32), actor_health("player", 32)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f0e5c7"))
	if companion_enabled():
		draw_string(ThemeDB.fallback_font, Vector2(21, 47), "%s  %d / %d" % [companion_name(), actor_health("companion", 24), actor_health("companion", 24)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c8b998"))
	draw_string(ThemeDB.fallback_font, Vector2(472, 24), String(era_data.get("display_name", current_era_id.capitalize())).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f3df9b"))
	draw_string(ThemeDB.fallback_font, Vector2(472, 42), String(map_data.get("display_name", "MAP")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("d2c8aa"))


func draw_dialogue() -> void:
	draw_rect(Rect2(24, 270, 592, 72), Color("10151b"))
	draw_rect(Rect2(24, 270, 592, 72), Color("d0b978"), false, 2.0)
	draw_text_lines(dialogue, Vector2(43, 295), 15, Color("f1ead8"))


func draw_pause() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0, 0, 0, 0.62))
	draw_rect(Rect2(202, 116, 236, 118), Color("111820"))
	draw_centered(localise("ui.pause.title", "JOURNEY PAUSED"), 159, 22, Color("f0dfad"))
	draw_centered(localise("ui.pause.return", "ESC / START TO RETURN"), 207, 11, Color("87949b"))


func draw_centered(text: String, y: float, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, int(VIEW.x), size, color)


func draw_multiline_centered(text: String, y: float, size: int, color: Color) -> void:
	var lines := text.split("\n")
	for index in range(lines.size()):
		draw_centered(lines[index], y + index * (size + 5), size, color)


func draw_text_lines(text: String, start: Vector2, size: int, color: Color) -> void:
	var lines := text.split("\n")
	for index in range(lines.size()):
		draw_string(ThemeDB.fallback_font, start + Vector2(0, index * (size + 5)), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
