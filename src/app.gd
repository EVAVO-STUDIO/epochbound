extends Node2D

# Epochbound Phase 1: asset-independent playable flow.

enum Flow { SPLASH, TITLE, INTRO, GAME, PAUSED }
enum Era { VERDANT, ASHEN }

const VIEW := Vector2(640, 360)
var flow := Flow.SPLASH
var era := Era.VERDANT
var elapsed := 0.0
var intro_page := 0
var selected_menu := 0
var player := Vector2(312, 220)
var dog := Vector2(270, 230)
var facing := Vector2.DOWN
var dialogue := ""
var shift_lock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	shift_lock = maxf(0.0, shift_lock - delta)
	match flow:
		Flow.SPLASH:
			if elapsed > 2.4 or confirm(): change_flow(Flow.TITLE)
		Flow.TITLE: update_title()
		Flow.INTRO: update_intro()
		Flow.GAME: update_game(delta)
		Flow.PAUSED:
			if Input.is_action_just_pressed("pause_game"): change_flow(Flow.GAME)
	queue_redraw()

func change_flow(next: int) -> void:
	flow = next
	elapsed = 0.0
	if next != Flow.GAME: dialogue = ""

func confirm() -> bool:
	return Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept")

func update_title() -> void:
	if Input.is_action_just_pressed("ui_up"): selected_menu = wrapi(selected_menu - 1, 0, 3)
	if Input.is_action_just_pressed("ui_down"): selected_menu = wrapi(selected_menu + 1, 0, 3)
	if confirm():
		if selected_menu == 0:
			intro_page = 0
			change_flow(Flow.INTRO)
		elif selected_menu == 1: begin_game()
		else: get_tree().quit()

func update_intro() -> void:
	if Input.is_action_just_pressed("ui_cancel"): begin_game()
	elif confirm():
		intro_page += 1
		if intro_page >= intro_pages().size(): begin_game()

func begin_game() -> void:
	player = Vector2(312, 220)
	dog = Vector2(270, 230)
	era = Era.VERDANT
	change_flow(Flow.GAME)

func update_game(delta: float) -> void:
	if Input.is_action_just_pressed("pause_game"):
		change_flow(Flow.PAUSED)
		return
	if not dialogue.is_empty():
		if confirm() or Input.is_action_just_pressed("ui_cancel"): dialogue = ""
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.length_squared() > 0.01:
		facing = direction.normalized()
		player += facing * 105.0 * delta
		player.x = clampf(player.x, 32.0, VIEW.x - 32.0)
		player.y = clampf(player.y, 106.0, VIEW.y - 38.0)
	var offset := player - dog
	if offset.length() > 34.0:
		dog += offset.normalized() * minf(132.0 * delta, offset.length() - 34.0)
	if Input.is_action_just_pressed("era_shift") and shift_lock <= 0.0:
		era = Era.ASHEN if era == Era.VERDANT else Era.VERDANT
		shift_lock = 0.65
	if Input.is_action_just_pressed("interact"): interact()

func interact() -> void:
	if player.distance_to(Vector2(500, 170)) < 62.0:
		dialogue = "The brass dial answers your touch.\nTwo ages occupy the same wound."
	elif player.distance_to(Vector2(124, 206)) < 58.0:
		dialogue = "Morrow growls at the old well.\nSomething below knows his name."
	else:
		dialogue = "Morrow sniffs the wind, then looks toward the eastern ruins."

func intro_pages() -> Array[String]:
	return [
		"1997. A summer storm erased the power\nand opened a door beneath Bellweather Museum.",
		"Eli Vale entered with one flashlight,\none borrowed key, and his dog Morrow.",
		"They returned to a world that remembered\nevery age at once."
	]

func _draw() -> void:
	match flow:
		Flow.SPLASH: draw_splash()
		Flow.TITLE: draw_title()
		Flow.INTRO: draw_intro()
		Flow.GAME: draw_game()
		Flow.PAUSED:
			draw_game()
			draw_pause()

func draw_splash() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("070a0f"))
	draw_centered("EVAVO STUDIO", 148, 28, Color("e8edf5"))
	draw_centered("PRESENTS", 190, 12, Color("788598"))

func draw_title() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("0b1017"))
	for i in range(11):
		var x := fmod(float(i * 83) + elapsed * (7.0 + i), 700.0) - 30.0
		draw_circle(Vector2(x, 52 + (i * 29) % 210), 1.2, Color("9eb6c7"))
	draw_colored_polygon(PackedVector2Array([Vector2(0,280),Vector2(105,238),Vector2(210,271),Vector2(325,208),Vector2(470,270),Vector2(640,224),Vector2(640,360),Vector2(0,360)]), Color("18282d"))
	draw_centered("EPOCHBOUND", 76, 42, Color("e7d7a2"))
	draw_centered("THE HOURS BENEATH", 111, 12, Color("8fa9a5"))
	var menu := ["NEW JOURNEY", "QUICK START", "QUIT"]
	for i in menu.size():
		var active := i == selected_menu
		draw_string(ThemeDB.fallback_font, Vector2(220, 176 + i * 28), "◆" if active else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e7c66b"))
		draw_string(ThemeDB.fallback_font, Vector2(244, 176 + i * 28), menu[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff2c9") if active else Color("76858b"))
	draw_centered("E / Z / A  CONFIRM     ARROWS  SELECT", 336, 10, Color("58656b"))

func draw_intro() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("05070a"))
	draw_rect(Rect2(58, 52, 524, 242), Color("111820"))
	draw_rect(Rect2(58, 52, 524, 242), Color("7b6a4f"), false, 2.0)
	draw_circle(Vector2(320, 142), 66, Color("26343a"))
	draw_circle(Vector2(320, 142), 39, Color("d7b666"), false, 3.0)
	draw_line(Vector2(320,142), Vector2(320 + cos(elapsed) * 29, 142 + sin(elapsed) * 29), Color("f2df9b"), 2.0)
	draw_multiline_centered(intro_pages()[intro_page], 226, 15, Color("e8e3d5"))
	draw_centered("CONFIRM TO CONTINUE   •   ESC TO SKIP", 330, 10, Color("68747e"))

func draw_game() -> void:
	var verdant := era == Era.VERDANT
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("819a91") if verdant else Color("5e4541"))
	draw_circle(Vector2(530, 65), 28, Color("e5d89f") if verdant else Color("d77850"))
	draw_rect(Rect2(0, 96, 640, 264), Color("4f6550") if verdant else Color("52443a"))
	draw_rect(Rect2(470, 105, 62, 89), Color("53625b") if verdant else Color("392f2d"))
	draw_circle(Vector2(501, 166), 15, Color("c9b46f"), false, 3.0)
	draw_circle(Vector2(124, 211), 25, Color("313b3b"))
	draw_circle(Vector2(124, 207), 20, Color("10181b"))
	draw_circle(dog + Vector2(0,-4), 10, Color("3b2a24"))
	draw_circle(dog + Vector2(9,-9), 6, Color("5a3d2e"))
	draw_circle(player + Vector2(0,-13), 8, Color("e2b38a"))
	draw_rect(Rect2(player + Vector2(-8,-6), Vector2(16,22)), Color("334b68"))
	draw_line(player + Vector2(0,6), player + facing * 18.0, Color("e8d69a"), 3.0)
	draw_rect(Rect2(10, 9, 210, 46), Color(0.03,0.04,0.05,0.86))
	draw_string(ThemeDB.fallback_font, Vector2(21,29), "ELI  32 / 32", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f0e5c7"))
	draw_string(ThemeDB.fallback_font, Vector2(21,47), "MORROW  24 / 24", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c8b998"))
	draw_string(ThemeDB.fallback_font, Vector2(500,27), "VERDANT AGE" if verdant else "ASHEN AGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f3df9b"))
	if dialogue.is_empty(): draw_centered("MOVE: WASD / ARROWS   INTERACT: E / Z   SHIFT: Q / X", 348, 9, Color("d7d0bd"))
	else: draw_dialogue()

func draw_dialogue() -> void:
	draw_rect(Rect2(24,270,592,72), Color("10151b"))
	draw_rect(Rect2(24,270,592,72), Color("d0b978"), false, 2.0)
	draw_multiline(dialogue, Vector2(43,295), 15, Color("f1ead8"))

func draw_pause() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0,0,0,0.62))
	draw_rect(Rect2(202,116,236,118), Color("111820"))
	draw_centered("JOURNEY PAUSED", 159, 22, Color("f0dfad"))
	draw_centered("ESC / START TO RETURN", 207, 11, Color("87949b"))

func draw_centered(text: String, y: float, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(0,y), text, HORIZONTAL_ALIGNMENT_CENTER, int(VIEW.x), size, color)

func draw_multiline_centered(text: String, y: float, size: int, color: Color) -> void:
	for i in text.split("\n").size(): draw_centered(text.split("\n")[i], y + i * (size + 5), size, color)

func draw_multiline(text: String, start: Vector2, size: int, color: Color) -> void:
	for i in text.split("\n").size(): draw_string(ThemeDB.fallback_font, start + Vector2(0,i * (size + 5)), text.split("\n")[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
