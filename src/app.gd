extends Node2D

# Phase 2: the playable reference slice is driven by the same campaign data
# that the editor creates and validates.

const CampaignRepository = preload("res://src/content/campaign_repository.gd")
const DEFAULT_CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const VIEW := Vector2(640, 360)
const PLAYER_SPEED := 105.0
const COMPANION_SPEED := 132.0
const COMPANION_FOLLOW_DISTANCE := 34.0

enum Flow { SPLASH, TITLE, INTRO, GAME, PAUSED }

var flow := Flow.SPLASH
var elapsed := 0.0
var intro_page := 0
var selected_menu := 0
var player := Vector2(312, 220)
var companion := Vector2(270, 230)
var facing := Vector2.DOWN
var dialogue := ""
var shift_lock := 0.0
var campaign_path := DEFAULT_CAMPAIGN_PATH
var campaign: Dictionary = {}
var map_data: Dictionary = {}
var current_era_id := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_campaign(campaign_path)
	queue_redraw()

func load_campaign(path: String) -> void:
	var campaign_result := CampaignRepository.read_json(path)
	if not campaign_result.get("ok", false):
		push_error("Campaign load failed: %s" % campaign_result.get("errors", []))
		campaign = CampaignRepository.default_campaign("epochbound_fallback", "EPOCHBOUND")
		map_data = CampaignRepository.default_map("first_crossing", "First Crossing")
	else:
		campaign = campaign_result.get("data", {})
		var start_map := String(campaign.get("start_map", ""))
		var map_path := CampaignRepository.find_map_path(path, campaign, start_map)
		var map_result := CampaignRepository.read_json(map_path)
		if map_result.get("ok", false):
			map_data = map_result.get("data", {})
		else:
			push_error("Map load failed: %s" % map_result.get("errors", []))
			map_data = CampaignRepository.default_map("first_crossing", "First Crossing")
	current_era_id = String(campaign.get("start_era", first_era_id()))
	if current_era_id.is_empty():
		current_era_id = first_era_id()
	reset_actor_positions()

func reset_actor_positions() -> void:
	var spawns: Dictionary = map_data.get("spawns", {})
	player = CampaignRepository.data_to_vector(spawns.get("player"), Vector2(312, 220))
	companion = CampaignRepository.data_to_vector(spawns.get("companion"), Vector2(270, 230))

func _process(delta: float) -> void:
	elapsed += delta
	shift_lock = maxf(0.0, shift_lock - delta)
	match flow:
		Flow.SPLASH:
			if elapsed > 2.4 or confirm():
				change_flow(Flow.TITLE)
		Flow.TITLE:
			update_title()
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

func update_title() -> void:
	if Input.is_action_just_pressed("ui_up"):
		selected_menu = wrapi(selected_menu - 1, 0, 3)
	if Input.is_action_just_pressed("ui_down"):
		selected_menu = wrapi(selected_menu + 1, 0, 3)
	if confirm():
		if selected_menu == 0:
			intro_page = 0
			change_flow(Flow.INTRO)
		elif selected_menu == 1:
			begin_game()
		else:
			get_tree().quit()

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
	change_flow(Flow.GAME)

func update_game(delta: float) -> void:
	if Input.is_action_just_pressed("pause_game"):
		change_flow(Flow.PAUSED)
		return
	if not dialogue.is_empty():
		if confirm() or Input.is_action_just_pressed("ui_cancel"):
			dialogue = ""
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.length_squared() > 0.01:
		facing = direction.normalized()
		player += facing * PLAYER_SPEED * delta
		clamp_player_to_map()
	var offset := player - companion
	if offset.length() > COMPANION_FOLLOW_DISTANCE:
		companion += offset.normalized() * minf(
			COMPANION_SPEED * delta,
			offset.length() - COMPANION_FOLLOW_DISTANCE
		)
	if Input.is_action_just_pressed("era_shift") and shift_lock <= 0.0:
		shift_to_next_era()
	if Input.is_action_just_pressed("interact"):
		interact()

func clamp_player_to_map() -> void:
	var bounds: Dictionary = map_data.get("bounds", {})
	player.x = clampf(player.x, float(bounds.get("left", 32.0)), float(bounds.get("right", VIEW.x - 32.0)))
	player.y = clampf(player.y, float(bounds.get("top", 96.0)), float(bounds.get("bottom", VIEW.y - 32.0)))

func shift_to_next_era() -> void:
	var era_ids := all_era_ids()
	if era_ids.size() < 2:
		return
	var index := era_ids.find(current_era_id)
	current_era_id = String(era_ids[(index + 1) % era_ids.size()])
	shift_lock = 0.65

func interact() -> void:
	var closest: Dictionary = {}
	var closest_distance := 999999.0
	for value in map_data.get("interactions", []):
		var interaction: Dictionary = value
		if not interaction_is_available(interaction):
			continue
		var position := CampaignRepository.data_to_vector(interaction.get("position"))
		var distance := player.distance_to(position)
		if distance <= float(interaction.get("radius", 32.0)) and distance < closest_distance:
			closest = interaction
			closest_distance = distance
	if closest.is_empty():
		dialogue = "%s sniffs the wind, then looks toward the nearest unfinished story." % companion_name().capitalize()
	else:
		dialogue = dialogue_for(closest)

func interaction_is_available(interaction: Dictionary) -> bool:
	var available: Array = interaction.get("available_eras", [])
	return available.is_empty() or available.has(current_era_id)

func dialogue_for(interaction: Dictionary) -> String:
	var value: Variant = interaction.get("dialogue", "")
	if typeof(value) == TYPE_STRING:
		return String(value)
	if typeof(value) == TYPE_DICTIONARY:
		return String(value.get(current_era_id, value.get("default", "...")))
	return "..."

func intro_pages() -> Array:
	var pages: Variant = campaign.get("intro", [])
	if typeof(pages) == TYPE_ARRAY and not pages.is_empty():
		return pages
	return ["A journey begins beyond the edge of the authored world."]

func first_era_id() -> String:
	for value in map_data.get("eras", []):
		return String(value.get("id", ""))
	return ""

func all_era_ids() -> Array:
	var ids: Array = []
	for value in map_data.get("eras", []):
		var era_id := String(value.get("id", ""))
		if not era_id.is_empty():
			ids.append(era_id)
	return ids

func current_era() -> Dictionary:
	for value in map_data.get("eras", []):
		if String(value.get("id", "")) == current_era_id:
			return value
	for value in map_data.get("eras", []):
		return value
	return {}

func palette_color(key: String, fallback: String) -> Color:
	var era_data := current_era()
	var palette: Dictionary = era_data.get("palette", {})
	return Color(String(palette.get(key, fallback)))

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

func _draw() -> void:
	match flow:
		Flow.SPLASH:
			draw_splash()
		Flow.TITLE:
			draw_title()
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
	draw_centered("PRESENTS", 190, 12, Color("788598"))

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
	draw_centered(String(campaign.get("title", "EPOCHBOUND")), 76, 42, Color("e7d7a2"))
	draw_centered(String(campaign.get("subtitle", "A NEW JOURNEY")), 111, 12, Color("8fa9a5"))
	var menu := ["NEW JOURNEY", "QUICK START", "QUIT"]
	for index in range(menu.size()):
		var active := index == selected_menu
		draw_string(
			ThemeDB.fallback_font,
			Vector2(220, 176 + index * 28),
			"◆" if active else "",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			Color("e7c66b")
		)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(244, 176 + index * 28),
			menu[index],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color("fff2c9") if active else Color("76858b")
		)
	draw_centered("E / Z / A  CONFIRM     ARROWS  SELECT", 336, 10, Color("58656b"))

func draw_intro() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("05070a"))
	draw_rect(Rect2(58, 52, 524, 242), Color("111820"))
	draw_rect(Rect2(58, 52, 524, 242), Color("7b6a4f"), false, 2.0)
	draw_circle(Vector2(320, 142), 66, Color("26343a"))
	draw_circle(Vector2(320, 142), 39, Color("d7b666"), false, 3.0)
	draw_line(
		Vector2(320, 142),
		Vector2(320 + cos(elapsed) * 29, 142 + sin(elapsed) * 29),
		Color("f2df9b"),
		2.0
	)
	draw_multiline_centered(String(intro_pages()[intro_page]), 226, 15, Color("e8e3d5"))
	draw_centered("CONFIRM TO CONTINUE   •   ESC TO SKIP", 330, 10, Color("68747e"))

func draw_game() -> void:
	var era_data := current_era()
	var canvas: Dictionary = map_data.get("canvas", {})
	var width := float(canvas.get("width", VIEW.x))
	var height := float(canvas.get("height", VIEW.y))
	draw_rect(Rect2(0, 0, width, height), palette_color("sky", "819a91"))
	var bounds: Dictionary = map_data.get("bounds", {})
	var ground_top := float(bounds.get("top", 96.0))
	draw_rect(Rect2(0, ground_top, width, height - ground_top), palette_color("ground", "4f6550"))
	for landmark in era_data.get("landmarks", []):
		draw_landmark(landmark)
	draw_companion()
	draw_player()
	draw_hud(era_data)
	if dialogue.is_empty():
		draw_centered("MOVE: WASD / ARROWS   INTERACT: E / Z   SHIFT: Q / X", 348, 9, Color("d7d0bd"))
	else:
		draw_dialogue()

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
	draw_rect(Rect2(10, 9, 224, 46), Color(0.03, 0.04, 0.05, 0.86))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(21, 29),
		"%s  %d / %d" % [player_name(), actor_health("player", 32), actor_health("player", 32)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color("f0e5c7")
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(21, 47),
		"%s  %d / %d" % [companion_name(), actor_health("companion", 24), actor_health("companion", 24)],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color("c8b998")
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(472, 24),
		String(era_data.get("display_name", current_era_id.capitalize())).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color("f3df9b")
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(472, 42),
		String(map_data.get("display_name", "MAP")).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		Color("d2c8aa")
	)

func draw_dialogue() -> void:
	draw_rect(Rect2(24, 270, 592, 72), Color("10151b"))
	draw_rect(Rect2(24, 270, 592, 72), Color("d0b978"), false, 2.0)
	draw_multiline(dialogue, Vector2(43, 295), 15, Color("f1ead8"))

func draw_pause() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0, 0, 0, 0.62))
	draw_rect(Rect2(202, 116, 236, 118), Color("111820"))
	draw_centered("JOURNEY PAUSED", 159, 22, Color("f0dfad"))
	draw_centered("ESC / START TO RETURN", 207, 11, Color("87949b"))

func draw_centered(text: String, y: float, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, int(VIEW.x), size, color)

func draw_multiline_centered(text: String, y: float, size: int, color: Color) -> void:
	var lines := text.split("\n")
	for index in range(lines.size()):
		draw_centered(lines[index], y + index * (size + 5), size, color)

func draw_multiline(text: String, start: Vector2, size: int, color: Color) -> void:
	var lines := text.split("\n")
	for index in range(lines.size()):
		draw_string(
			ThemeDB.fallback_font,
			start + Vector2(0, index * (size + 5)),
			lines[index],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size,
			color
		)
