extends Node2D

const MultiplayerCatalog = preload("res://src/content/multiplayer_catalog.gd")
const MultiplayerSessionModel = preload("res://src/game/multiplayer_session_model.gd")

const VIEW := Vector2(640, 360)
const LOBBY_PANEL := Rect2(116, 58, 408, 244)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func runtime_root() -> Node:
	var layer := get_parent()
	return layer.get_parent() if layer != null else null


func session_node() -> Node:
	var runtime := runtime_root()
	return runtime.get_node_or_null("MultiplayerSession") if runtime != null else null


func presentation_overlay() -> Node:
	var layer := get_parent()
	return layer.get_node_or_null("PresentationOverlay") if layer != null else null


func profile_color(key: String, fallback: String) -> Color:
	var overlay := presentation_overlay()
	if overlay != null and overlay.has_method("profile_color"):
		var value: Variant = overlay.call("profile_color", key, fallback)
		if value is Color:
			return value
	return Color(fallback)


func world_to_screen(position: Vector2) -> Vector2:
	var overlay := presentation_overlay()
	if overlay != null and overlay.has_method("world_to_screen"):
		var value: Variant = overlay.call("world_to_screen", position)
		if value is Vector2:
			return value
	return position


func _draw() -> void:
	draw_area_boundary()
	draw_remote_peers()
	draw_session_status()
	draw_online_lobby()


func draw_session_status() -> void:
	var session := session_node()
	if session == null:
		return
	var runtime := runtime_root()
	var flow := int(runtime.get("flow")) if runtime != null else 0
	var lobby_open := bool(session.get("lobby_open"))
	var status := str(session.call("online_status_text")) if session.has_method("online_status_text") else "OFFLINE"
	var notice := str(session.get("session_notice")).strip_edges()
	var text := profile_color("ui_text", "eee3c6")
	var frame := profile_color("ui_frame", "9f8651")
	var fill := profile_color("ui_fill", "15191b")
	var accent := profile_color("accent", "d49a45")
	if flow in [1, 4, 5] and not lobby_open:
		var width := 188.0 if status == "OFFLINE" else 258.0
		var rect := Rect2(VIEW.x - width - 8.0, 8.0, width, 20.0)
		draw_rect(rect, Color(fill, 0.9))
		draw_rect(rect, Color(frame, 0.82), false, 1.0)
		var label := "N / GUIDE  ONLINE" if status == "OFFLINE" else status
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(7, 13), label, HORIZONTAL_ALIGNMENT_RIGHT, int(rect.size.x - 14.0), 8, accent if status != "OFFLINE" else text.darkened(0.18))
	if not notice.is_empty() and not lobby_open:
		var notice_rect := Rect2(112, 34, 416, 22)
		draw_rect(notice_rect, Color(fill, 0.94))
		draw_rect(notice_rect, Color(frame, 0.86), false, 1.0)
		draw_string(ThemeDB.fallback_font, notice_rect.position + Vector2(8, 14), notice, HORIZONTAL_ALIGNMENT_CENTER, int(notice_rect.size.x - 16.0), 8, text)


func draw_online_lobby() -> void:
	var session := session_node()
	if session == null or not bool(session.get("lobby_open")):
		return
	var fill := profile_color("ui_fill", "15191b")
	var frame := profile_color("ui_frame", "9f8651")
	var text := profile_color("ui_text", "eee3c6")
	var accent := profile_color("accent", "d49a45")
	var danger := profile_color("danger", "b94d45")
	draw_rect(LOBBY_PANEL, Color(fill, 1.0))
	draw_rect(LOBBY_PANEL, frame, false, 2.0)
	draw_string(ThemeDB.fallback_font, LOBBY_PANEL.position + Vector2(18, 30), "ONLINE PLAY", HORIZONTAL_ALIGNMENT_LEFT, 180, 18, text)
	draw_string(ThemeDB.fallback_font, LOBBY_PANEL.position + Vector2(190, 28), "HOST-AUTHORITATIVE  •  DIRECT ENET", HORIZONTAL_ALIGNMENT_RIGHT, 198, 8, frame)
	var entries_value: Variant = session.call("online_menu_entries")
	var entries: Array = entries_value if typeof(entries_value) == TYPE_ARRAY else []
	var selected := clampi(int(session.get("lobby_index")), 0, maxi(0, entries.size() - 1))
	for index in range(entries.size()):
		var y := LOBBY_PANEL.position.y + 76.0 + float(index) * 32.0
		var active := index == selected
		if active:
			draw_rect(Rect2(LOBBY_PANEL.position.x + 18.0, y - 20.0, LOBBY_PANEL.size.x - 36.0, 26.0), Color(frame, 0.16))
			draw_rect(Rect2(LOBBY_PANEL.position.x + 29.0, y - 8.0, 5.0, 5.0), accent)
		draw_string(ThemeDB.fallback_font, Vector2(LOBBY_PANEL.position.x + 46.0, y), str(entries[index]), HORIZONTAL_ALIGNMENT_LEFT, 310, 13, text if active else text.darkened(0.28))
	var mode := str(session.get("mode"))
	var role := str(session.get("requested_role"))
	var address := str(session.get("connect_address"))
	var port := int(session.get("connect_port"))
	var policy_value: Variant = session.get("policy")
	var policy: Dictionary = policy_value if typeof(policy_value) == TYPE_DICTIONARY else {}
	var summary := "OFFLINE — HOST OR JOIN %s:%d" % [address, port]
	if mode != MultiplayerSessionModel.MODE_OFFLINE:
		summary = str(session.call("online_status_text"))
	elif selected == 2:
		summary = "INVASION REQUEST — ONLY AUTHORED PVP AREAS ACCEPT IT"
	elif role == MultiplayerSessionModel.ROLE_INVADER:
		summary = "NEXT JOIN ROLE: INVADER"
	draw_string(ThemeDB.fallback_font, Vector2(LOBBY_PANEL.position.x + 18.0, LOBBY_PANEL.end.y - 46.0), summary, HORIZONTAL_ALIGNMENT_CENTER, int(LOBBY_PANEL.size.x - 36.0), 8, danger if selected == 2 else frame)
	draw_string(ThemeDB.fallback_font, Vector2(LOBBY_PANEL.position.x + 18.0, LOBBY_PANEL.end.y - 29.0), "HOST SAVES ONLY  •  CO-OP FRIENDLY FIRE OFF  •  PVP REWARDS SESSION-ONLY", HORIZONTAL_ALIGNMENT_CENTER, int(LOBBY_PANEL.size.x - 36.0), 7, text.darkened(0.12))
	draw_string(ThemeDB.fallback_font, Vector2(LOBBY_PANEL.position.x + 18.0, LOBBY_PANEL.end.y - 13.0), "ARROWS SELECT  •  CONFIRM  •  ESC BACK  •  UDP %d" % int(policy.get("default_port", port)), HORIZONTAL_ALIGNMENT_CENTER, int(LOBBY_PANEL.size.x - 36.0), 7, accent)


func draw_area_boundary() -> void:
	var session := session_node()
	var overlay := presentation_overlay()
	if session == null or overlay == null or not overlay.has_method("presentation_world_layers_allowed"):
		return
	if not bool(overlay.call("presentation_world_layers_allowed")):
		return
	var area_value: Variant = session.call("online_area") if session.has_method("online_area") else {}
	if typeof(area_value) != TYPE_DICTIONARY or (area_value as Dictionary).is_empty():
		return
	var area: Dictionary = area_value
	var rect := MultiplayerCatalog.area_bounds(area)
	if not rect.has_area():
		return
	var top_left := world_to_screen(rect.position)
	var bottom_right := world_to_screen(rect.end)
	var screen_rect := Rect2(top_left, bottom_right - top_left)
	var kind := MultiplayerCatalog.area_kind(area)
	var color := profile_color("ui_frame", "9f8651")
	if kind == MultiplayerCatalog.AREA_PVP:
		color = profile_color("danger", "b94d45")
	elif kind == MultiplayerCatalog.AREA_SANCTUARY:
		color = profile_color("ui_text", "eee3c6").darkened(0.25)
	var pulse := 0.42 + sin(Time.get_ticks_msec() * 0.004) * 0.12
	draw_rect(screen_rect, Color(color, pulse), false, 1.0)
	var label_rect := Rect2(
		screen_rect.position + Vector2(4, 4),
		Vector2(minf(260.0, screen_rect.size.x - 8.0), 16.0)
	)
	if label_rect.size.x > 32.0:
		draw_rect(label_rect, Color(profile_color("ui_fill", "15191b"), 0.82))
		draw_string(ThemeDB.fallback_font, label_rect.position + Vector2(5, 11), MultiplayerCatalog.area_summary(area), HORIZONTAL_ALIGNMENT_LEFT, int(label_rect.size.x - 10.0), 7, color)


func draw_remote_peers() -> void:
	var session := session_node()
	var overlay := presentation_overlay()
	if session == null or overlay == null or not overlay.has_method("presentation_world_layers_allowed"):
		return
	if not bool(overlay.call("presentation_world_layers_allowed")):
		return
	var values: Variant = session.call("visible_peer_states") if session.has_method("visible_peer_states") else []
	if typeof(values) != TYPE_ARRAY:
		return
	for peer_value in values as Array:
		if typeof(peer_value) != TYPE_DICTIONARY:
			continue
		draw_remote_peer(peer_value as Dictionary)


func draw_remote_peer(peer: Dictionary) -> void:
	var position_value: Variant = peer.get("position", Vector2.ZERO)
	var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
	var screen := world_to_screen(position)
	var role := str(peer.get("role", MultiplayerSessionModel.ROLE_ALLY))
	var active := bool(peer.get("active", true))
	var color := Color("73b4b7")
	if role == MultiplayerSessionModel.ROLE_INVADER:
		color = profile_color("danger", "b94d45")
	elif role == MultiplayerSessionModel.ROLE_HOST:
		color = profile_color("accent", "d49a45")
	if not active:
		color = color.darkened(0.55)
	var facing_value: Variant = peer.get("facing", Vector2.DOWN)
	var facing: Vector2 = facing_value if facing_value is Vector2 else Vector2.DOWN
	var right := Vector2(-facing.y, facing.x).normalized()
	var nose := screen + facing.normalized() * 8.0
	var left := screen - facing.normalized() * 5.0 - right * 6.0
	var right_point := screen - facing.normalized() * 5.0 + right * 6.0
	draw_colored_polygon(PackedVector2Array([nose, left, right_point]), Color(color, 0.96))
	draw_polyline(PackedVector2Array([nose, left, right_point, nose]), color.lightened(0.28), 1.0)
	var maximum := maxi(1, int(peer.get("max_health", 32)))
	var health := clampi(int(peer.get("health", maximum)), 0, maximum)
	var bar := Rect2(screen + Vector2(-18, -17), Vector2(36, 4))
	draw_rect(bar, Color("090b0d"))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(health) / float(maximum), bar.size.y)), color)
	var label := "%s  %s" % [str(peer.get("display_name", "WANDERER")).to_upper(), role.to_upper()]
	draw_string(ThemeDB.fallback_font, screen + Vector2(-48, -22), label, HORIZONTAL_ALIGNMENT_CENTER, 96, 7, color.lightened(0.16))


func multiplayer_overlay_contract_ok() -> bool:
	return (
		runtime_root() != null
		and session_node() != null
		and presentation_overlay() != null
		and LOBBY_PANEL.size.x >= 400.0
		and LOBBY_PANEL.size.y >= 220.0
	)
