extends Node2D

const VIEW := Vector2(640, 360)
const PROMPT_VERTICAL_OFFSET := 31.0
const CONTROL_PANEL := Rect2(64, 18, 512, 324)
const CONTROL_ROW_HEIGHT := 18.0


func _process(_delta: float) -> void:
	queue_redraw()


func runtime_root() -> Node:
	var layer := get_parent()
	return layer.get_parent() if layer != null else null


func presentation_overlay() -> Node:
	var layer := get_parent()
	return layer.get_node_or_null("PresentationOverlay") if layer != null else null


func runtime_boolean(property_name: String, fallback: bool = false) -> bool:
	var runtime := runtime_root()
	if runtime == null:
		return fallback
	var value: Variant = runtime.get(property_name)
	return bool(value) if typeof(value) == TYPE_BOOL else fallback


func runtime_integer(property_name: String, fallback: int = 0) -> int:
	var runtime := runtime_root()
	if runtime == null:
		return fallback
	var value: Variant = runtime.get(property_name)
	return int(value) if typeof(value) == TYPE_INT else fallback


func runtime_string(property_name: String) -> String:
	var runtime := runtime_root()
	return str(runtime.get(property_name)) if runtime != null else ""


func runtime_action_hint(action_id: String, fallback: String) -> String:
	var runtime := runtime_root()
	if runtime != null and runtime.has_method("input_action_hint"):
		var value := str(runtime.call("input_action_hint", action_id)).strip_edges()
		if not value.is_empty():
			return value
	return fallback


func profile_color(key: String, fallback: String) -> Color:
	var overlay := presentation_overlay()
	if overlay != null and overlay.has_method("profile_color"):
		var value: Variant = overlay.call("profile_color", key, fallback)
		if value is Color:
			return value
	return Color(fallback)


func draw_panel_frame(rect: Rect2, color: Color) -> void:
	var overlay := presentation_overlay()
	if overlay != null and overlay.has_method("draw_panel_frame"):
		overlay.call("draw_panel_frame", rect, color)
	else:
		draw_rect(rect, color, false, 1.0)


func _draw() -> void:
	draw_dynamic_context_prompt()
	draw_dynamic_reload_hint()
	draw_control_settings_panel()


func draw_control_settings_panel() -> void:
	if not runtime_boolean("player_settings_open"):
		return
	var runtime := runtime_root()
	if runtime == null or not runtime.has_method("player_settings_rows"):
		return
	var rows_value: Variant = runtime.call("player_settings_rows")
	var rows: Array = rows_value if typeof(rows_value) == TYPE_ARRAY else []
	var selected := clampi(runtime_integer("player_settings_index", 0), 0, maxi(0, rows.size() - 1))
	var controls_open := runtime_boolean("control_bindings_open")
	var capture_active := runtime_boolean("control_capture_active")
	var fill := profile_color("ui_fill", "15191b")
	var frame := profile_color("ui_frame", "9f8651")
	var text := profile_color("ui_text", "eee3c6")
	var accent := profile_color("accent", "d49a45")

	# This sibling draws after the inherited PresentationOverlay. Repaint the
	# complete panel so schema growth and the Controls submenu never overlap the
	# inherited fixed-row footer at the 640 by 360 base viewport.
	draw_rect(CONTROL_PANEL, Color(fill, 1.0))
	draw_panel_frame(CONTROL_PANEL, frame)
	var title := "OPTIONS"
	var header := "PLAYER LOCAL  •  VERSIONED  •  RECOVERABLE  •  REMAPPABLE"
	if controls_open:
		title = "CONTROLS — %s" % runtime_string("control_binding_device").replace("gamepad", "controller").to_upper()
		header = "14 GAMEPLAY ACTIONS  •  ESC / O / START RESERVED"
		if capture_active:
			title = "LISTENING — %s" % runtime_string("control_capture_action_id").replace("_", " ").to_upper()
	draw_string(ThemeDB.fallback_font, Vector2(CONTROL_PANEL.position.x + 18.0, CONTROL_PANEL.position.y + 28.0), title, HORIZONTAL_ALIGNMENT_LEFT, 230, 16, text)
	draw_string(ThemeDB.fallback_font, Vector2(CONTROL_PANEL.position.x + 244.0, CONTROL_PANEL.position.y + 27.0), header, HORIZONTAL_ALIGNMENT_RIGHT, 248, 7, frame.darkened(0.04))

	var row_start_y := CONTROL_PANEL.position.y + 54.0
	for index in range(rows.size()):
		if typeof(rows[index]) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = rows[index]
		var y := row_start_y + float(index) * CONTROL_ROW_HEIGHT
		var active := index == selected
		if active:
			draw_rect(Rect2(CONTROL_PANEL.position.x + 12.0, y - 12.0, CONTROL_PANEL.size.x - 24.0, 17.0), Color(frame, 0.16))
			draw_rect(Rect2(CONTROL_PANEL.position.x + 17.0, y - 7.0, 4.0, 4.0), accent)
		var label := str(row.get("label", row.get("id", "SETTING"))).to_upper()
		var value_text := str(row.get("value", ""))
		if str(row.get("kind", "")) == "action":
			value_text = "CONFIRM"
		draw_string(ThemeDB.fallback_font, Vector2(CONTROL_PANEL.position.x + 30.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, 310, 8, text if active else text.darkened(0.24))
		draw_string(ThemeDB.fallback_font, Vector2(CONTROL_PANEL.position.x + 346.0, y), value_text, HORIZONTAL_ALIGNMENT_RIGHT, 196, 8, accent if active else frame.darkened(0.18))

	var notice := runtime_string("player_settings_notice").strip_edges()
	if not notice.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(CONTROL_PANEL.position.x + 18.0, CONTROL_PANEL.end.y - 27.0), notice.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, int(CONTROL_PANEL.size.x - 36.0), 7, frame)
	var footer := "%s SELECT   •   LEFT / RIGHT CHANGE   •   ESC / O BACK" % runtime_action_hint("interact", "E / A")
	if controls_open:
		footer = "ESC / START CANCEL CAPTURE   •   O REMAINS RESERVED" if capture_active else "%s REBIND   •   LEFT / RIGHT DEVICE   •   ESC BACK" % runtime_action_hint("interact", "E / A")
	draw_string(ThemeDB.fallback_font, Vector2(CONTROL_PANEL.position.x + 18.0, CONTROL_PANEL.end.y - 10.0), footer, HORIZONTAL_ALIGNMENT_CENTER, int(CONTROL_PANEL.size.x - 36.0), 7, accent if capture_active else text.darkened(0.18))


func draw_dynamic_context_prompt() -> void:
	var overlay := presentation_overlay()
	if overlay == null or not overlay.has_method("feedback_draw_allowed") or not bool(overlay.call("feedback_draw_allowed")):
		return
	if not runtime_string("dialogue").is_empty():
		return
	var runtime := runtime_root()
	if runtime == null or float(runtime.get("transition_lock")) > 0.0:
		return
	var alpha_value: Variant = overlay.get("context_prompt_alpha")
	var alpha := float(alpha_value) if typeof(alpha_value) in [TYPE_INT, TYPE_FLOAT] else 0.0
	var prompt_value: Variant = overlay.get("context_prompt")
	if alpha <= 0.01 or typeof(prompt_value) != TYPE_DICTIONARY:
		return
	var prompt: Dictionary = prompt_value
	if prompt.is_empty() or not overlay.has_method("world_to_screen"):
		return
	var world_position_value: Variant = prompt.get("position", Vector2.ZERO)
	var world_position: Vector2 = world_position_value if world_position_value is Vector2 else Vector2.ZERO
	var screen_value: Variant = overlay.call("world_to_screen", world_position)
	var screen_position: Vector2 = screen_value if screen_value is Vector2 else world_position
	var bob := roundf(sin(Time.get_ticks_msec() * 0.008) * 2.0)
	var target_y := clampf(screen_position.y - PROMPT_VERTICAL_OFFSET + bob, 92.0, VIEW.y - 76.0)
	var action := str(prompt.get("action", "USE"))
	var target_name := str(prompt.get("target_name", ""))
	var enabled := bool(prompt.get("enabled", true))
	var frame := profile_color("ui_frame", "9f8651") if enabled else profile_color("danger", "b94d45")
	var text := profile_color("ui_text", "eee3c6")
	var fill := profile_color("ui_fill", "15191b")
	var label := "%s  %s" % [runtime_action_hint("interact", "E / A"), action]
	var original_label := "E / A  %s" % action
	var label_width := maxf(ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, ThemeDB.fallback_font.get_string_size(original_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x)
	var name_width := ThemeDB.fallback_font.get_string_size(target_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	var width := clampf(maxf(label_width, name_width) + 24.0, 82.0, 220.0)
	var height := 30.0 if not target_name.is_empty() else 22.0
	var left := clampf(screen_position.x - width * 0.5, 8.0, VIEW.x - width - 8.0)
	var rect := Rect2(left, target_y - height, width, height)
	draw_colored_polygon(PackedVector2Array([Vector2(screen_position.x - 4.0, target_y), Vector2(screen_position.x + 4.0, target_y), Vector2(screen_position.x, target_y + 5.0)]), Color(frame, 0.94 * alpha))
	draw_rect(rect, Color(fill, 0.94 * alpha))
	draw_rect(rect, Color(frame, 0.92 * alpha), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 8.0, rect.position.y + 14.0), label, HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x - 16.0), 9, Color(text, alpha))
	if not target_name.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 8.0, rect.position.y + 25.0), target_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x - 16.0), 7, Color(frame, 0.82 * alpha))


func draw_dynamic_reload_hint() -> void:
	var overlay := presentation_overlay()
	if overlay == null or not overlay.has_method("presentation_world_layers_allowed") or not bool(overlay.call("presentation_world_layers_allowed")):
		return
	if not overlay.has_method("arsenal_status_snapshot"):
		return
	var snapshot_value: Variant = overlay.call("arsenal_status_snapshot")
	if typeof(snapshot_value) != TYPE_DICTIONARY or (snapshot_value as Dictionary).is_empty():
		return
	var fill := profile_color("ui_fill", "15191b")
	var accent := profile_color("accent", "d49a45")
	var cover := Rect2(548, 61, 78, 18)
	draw_rect(cover, Color(fill, 1.0))
	draw_string(ThemeDB.fallback_font, Vector2(cover.position.x, cover.position.y + 12.0), runtime_action_hint("reload_weapon", "G / RT"), HORIZONTAL_ALIGNMENT_RIGHT, int(cover.size.x - 4.0), 8, accent)


func control_remapping_overlay_contract_ok() -> bool:
	return presentation_overlay() != null and CONTROL_PANEL.size.x >= 480.0 and CONTROL_PANEL.size.y >= 300.0 and CONTROL_ROW_HEIGHT >= 17.0 and CONTROL_ROW_HEIGHT <= 20.0 and runtime_root() != null
