extends Node

# Epochbound Phase 1: asset-independent playable flow.
# Everything is drawn from Godot primitives so the repository boots before final art exists.

enum Flow { SPLASH, TITLE, INTRO, GAME, PAUSED }
enum Era { VERDANT, ASHEN }

const VIEW := Vector2(640, 360)
const PLAYER_SPEED := 105.0
const DOG_SPEED := 132.0
const DOG_FOLLOW_DISTANCE := 34.0

var flow: Flow = Flow.SPLASH
var previous_flow: Flow = Flow.GAME
var era: Era = Era.VERDANT
var elapsed := 0.0
var intro_page := 0
var selected_menu := 0
var player_position := Vector2(312, 220)
var dog_position := Vector2(270, 230)
var facing := Vector2.DOWN
var dialogue_open := false
var dialogue_text := ""
var shift_cooldown := 0.0
var canvas: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	build_canvas()
	queue_redraw()

func build_canvas() -> void:
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)

func _process(delta: float) -> void:
	elapsed += delta
	shift_cooldown = maxf(0.0, shift_cooldown - delta)

	match flow:
		Flow.SPLASH:
			if elapsed > 2.4 or any_confirm_pressed():
				set_flow(Flow.TITLE)
		Flow.TITLE:
			process_title()
		Flow.INTRO:
			process_intro()
		Flow.GAME:
			process_game(delta)
		Flow.PAUSED:
			if Input.is_action_just_pressed("pause_game"):
				set_flow(previous_flow)

	queue_redraw()

func set_flow(next: Flow) -> void:
	flow = next
	elapsed = 0.0
	if next != Flow.GAME:
		dialogue_open = false

func any_confirm_pressed() -> bool:
	return Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept")

func process_title() -> void:
	if Input.is_action_just_pressed("ui_up"):
		selected_menu = wrapi(selected_menu - 1, 0, 3)
	if Input.is_action_just_pressed("ui_down"):
		selected_menu = wrapi(selected_menu + 1, 0, 3)
	if any_confirm_pressed():
		match selected_menu:
			0:
				intro_page = 0
				set_flow(Flow.INTRO)
			1:
				begin_game()
			2:
				get_tree().quit()

func process_intro() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		begin_game()
	elif any_confirm_pressed():
		intro_page += 1
		if intro_page >= intro_pages().size():
			begin_game()

func begin_game() -> void:
	player_position = Vector2(312, 220)
	dog_position = Vector2(270, 230)
	era = Era.VERDANT
	set_flow(Flow.GAME)

func process_game(delta: float) -> void:
	if Input.is_action_just_pressed("pause_game"):
		previous_flow = Flow.GAME
		set_flow(Flow.PAUSED)
		return

	if dialogue_open:
		if any_confirm_pressed() or Input.is_action_just_pressed("ui_cancel"):
			dialogue_open = false
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.length_squared() > 0.01:
		facing = direction.normalized()
		player_position += facing * PLAYER_SPEED * delta
		player_position.x = clampf(player_position.x, 32.0, VIEW.x - 32.0)
		player_position.y = clampf(player_position.y, 106.0, VIEW.y - 38.0)

	var dog_delta := player_position - dog_position
	if dog_delta.length() > DOG_FOLLOW_DISTANCE:
		dog_position += dog_delta.normalized() * minf(DOG_SPEED * delta, dog_delta.length() - DOG_FOLLOW_DISTANCE)

	if Input.is_action_just_pressed("era_shift") and shift_cooldown <= 0.0:
		era = Era.ASHEN if era == Era.VERDANT else Era.VERDANT
		shift_cooldown = 0.65

	if Input.is_action_just_pressed("interact"):
		interact()

func interact() -> void:
	var altar := Vector2(500, 170)
	var well := Vector2(124, 206)
	if player_position.distance_to(altar) < 62.0:
		dialogue_text = "The brass dial answers your touch.\nTwo ages occupy the same wound."
		dialogue_open = true
	elif player_position.distance_to(well) < 58.0:
		dialogue_text = "Morrow growls at the old well.\nSomething below knows his name."
		dialogue_open = true
	else:
		dialogue_text = "Morrow sniffs the wind, then looks toward the eastern ruins."
		dialogue_open = true

func intro_pages() -> Array[String]:
	return [
		"1997. A summer storm erased the power\nand opened a door beneath Bellweather Museum.",
		"Eli Vale entered with one flashlight,\none borrowed key, and his dog Morrow.",
		"They returned to a world that remembered\nevery age at once."
	]

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
	var pulse := 0.72 + sin(elapsed * 3.0) * 0.08
	draw_centered("EVAVO STUDIO", 148, 28, Color(0.92, 0.94, 0.98, pulse))
	draw_centered("PRESENTS", 190, 12, Color("788598"))

func draw_title() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("0b1017"))
	for i in range(11):
		var x := fmod(float(i * 83) + elapsed * (7.0 + i), 700.0) - 30.0
		draw_circle(Vector2(x, 52 + (i * 29) % 210), 1.2, Color("9eb6c7"))
	draw_rect(Rect2(0, 255, 640, 105), Color("111a20"))
	draw_colored_polygon(PackedVector2Array([Vector2(0,280), Vector2(105,238), Vector2(210,271), Vector2(325,208), Vector2(470,270), Vector2(640,224), Vector2(640,360), Vector2(0,360)]), Color("18282d"))
	draw_centered("EPOCHBOUND", 76, 42, Color("e7d7a2"))
	draw_centered("THE HOURS BENEATH", 111, 12, Color("8fa9a5"))
	var menu := ["NEW JOURNEY", "QUICK START", "QUIT"]
	for i in menu.size():
		var active := i == selected_menu
		if active:
			draw_string(ThemeDB.fallback_font, Vector2(220, 176 + i * 28), "◆", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e7c66b"))
		draw_string(ThemeDB.fallback_font, Vector2(244, 176 + i * 28), menu[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff2c9") if active else Color("76858b"))
	draw_centered("E / Z / A  CONFIRM     ARROWS  SELECT", 336, 10, Color("58656b"))

func draw_intro() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("05070a"))
	var panel := Rect2(58, 52, 524, 242)
	draw_rect(panel, Color("111820"))
	draw_rect(panel, Color("7b6a4f"), false, 2.0)
	var phase := float(intro_page) / maxf(1.0, intro_pages().size() - 1.0)
	draw_circle(Vector2(320, 142), 66, Color(0.15 + phase * 0.15, 0.20, 0.23 - phase * 0.08))
	draw_circle(Vector2(320, 142), 39, Color("d7b666"), false, 3.0)
	draw_line(Vector2(320,142), Vector2(320 + cos(elapsed) * 29, 142 + sin(elapsed) * 29), Color("f2df9b"), 2.0)
	draw_multiline_centered(intro_pages()[intro_page], 226, 15, Color("e8e3d5"))
	draw_centered("CONFIRM TO CONTINUE   •   ESC TO SKIP", 330, 10, Color("68747e"))

func draw_game() -> void:
	var verdant := era == Era.VERDANT
	var sky := Color("819a91") if verdant else Color("5e4541")
	var ground := Color("4f6550") if verdant else Color("52443a")
	draw_rect(Rect2(Vector2.ZERO, VIEW), sky)
	draw_circle(Vector2(530, 65), 28, Color("e5d89f") if verdant else Color("d77850"))
	draw_rect(Rect2(0, 96, 640, 264), ground)

	# Distant shrine and era-dependent environmental silhouette.
	draw_rect(Rect2(470, 105, 62, 89), Color("53625b") if verdant else Color("392f2d"))
	draw_rect(Rect2(481, 86, 40, 24), Color("718277") if verdant else Color("493633"))
	draw_circle(Vector2(501, 166), 15, Color("c9b46f"), false, 3.0)
	if verdant:
		for x in [54, 214, 392, 586]:
			draw_rect(Rect2(x, 119, 8, 54), Color("3f523f"))
			draw_circle(Vector2(x + 4, 112), 22, Color("46694a"))
	else:
		for x in [54, 214, 392, 586]:
			draw_line(Vector2(x + 4, 172), Vector2(x + 3, 112), Color("302b2a"), 7.0)
			draw_line(Vector2(x + 3, 126), Vector2(x - 12, 108), Color("302b2a"), 4.0)

	# Well interaction landmark.
	draw_circle(Vector2(124, 211), 25, Color("313b3b"))
	draw_circle(Vector2(124, 207), 20, Color("10181b"))
	draw_arc(Vector2(124, 205), 34, PI, TAU, 20, Color("69716c"), 4.0)

	# Dog companion and hero, primitive placeholders with readable silhouettes.
	draw_circle(dog_position + Vector2(0, -4), 10, Color("3b2a24"))
	draw_circle(dog_position + Vector2(9, -9), 6, Color("5a3d2e"))
	draw_line(dog_position + Vector2(-8,-5), dog_position + Vector2(-16,-13), Color("3b2a24"), 4.0)
	draw_circle(player_position + Vector2(0, -13), 8, Color("e2b38a"))
	draw_rect(Rect2(player_position + Vector2(-8,-6), Vector2(16,22)), Color("334b68"))
	draw_line(player_position + Vector2(0,6), player_position + facing * 18.0, Color("e8d69a"), 3.0)

	# HUD.
	draw_rect(Rect2(10, 9, 210, 46), Color(0.03, 0.04, 0.05, 0.86))
	draw_string(ThemeDB.fallback_font, Vector2(21, 29), "ELI  32 / 32", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f0e5c7"))
	draw_string(ThemeDB.fallback_font, Vector2(21, 47), "MORROW  24 / 24", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c8b998"))
	var era_label := "VERDANT AGE" if verdant else "ASHEN AGE"
	draw_string(ThemeDB.fallback_font, Vector2(500, 27), era_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f3df9b"))
	draw_string(ThemeDB.fallback_font, Vector2(498, 45), "Q / X  SHIFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("e1d6b4"))

	if dialogue_open:
		draw_dialogue()
	else:
		draw_centered("MOVE: WASD / ARROWS   INTERACT: E / Z   PAUSE: ESC", 348, 9, Color("d7d0bd"))

func draw_dialogue() -> void:
	var box := Rect2(24, 270, 592, 72)
	draw_rect(box, Color("10151b"))
	draw_rect(box, Color("d0b978"), false, 2.0)
	draw_multiline(dialogue_text, Vector2(43, 295), 15, Color("f1ead8"))
	draw_string(ThemeDB.fallback_font, Vector2(586, 329), "▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("d6bc71"))

func draw_pause() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.0, 0.0, 0.0, 0.62))
	draw_rect(Rect2(202, 116, 236, 118), Color("111820"))
	draw_rect(Rect2(202, 116, 236, 118), Color("a38e5d"), false, 2.0)
	draw_centered("JOURNEY PAUSED", 159, 22, Color("f0dfad"))
	draw_centered("ESC / START TO RETURN", 207, 11, Color("87949b"))

func draw_centered(text: String, y: float, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, int(VIEW.x), size, color)

func draw_multiline_centered(text: String, y: float, size: int, color: Color) -> void:
	var lines := text.split("\n")
	for i in lines.size():
		draw_centered(lines[i], y + i * (size + 5), size, color)

func draw_multiline(text: String, start: Vector2, size: int, color: Color) -> void:
	var lines := text.split("\n")
	for i in lines.size():
		draw_string(ThemeDB.fallback_font, start + Vector2(0, i * (size + 5)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
