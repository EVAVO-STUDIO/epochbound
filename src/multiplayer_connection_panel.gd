extends Control

const MultiplayerConnectionProfile = preload("res://src/game/multiplayer_connection_profile.gd")
const MultiplayerConnectionProfileStore = preload("res://src/game/multiplayer_connection_profile_store.gd")
const MultiplayerSessionModel = preload("res://src/game/multiplayer_session_model.gd")

const VIEW := Vector2(640, 360)
const PANEL_RECT := Rect2(94, 38, 452, 284)
const LOBBY_HINT_RECT := Rect2(332, 310, 198, 22)
const PROFILE_NOTICE_DURATION := 2.4

var editor_open := false
var profile_notice := ""
var profile_notice_timer := 0.0
var editor_controls: Array = []

var address_edit: LineEdit
var port_edit: SpinBox
var name_edit: LineEdit
var status_label: Label
var save_button: Button
var reset_button: Button
var back_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -200
	position = Vector2.ZERO
	size = VIEW
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_controls()
	set_editor_controls_visible(false)
	call_deferred("load_saved_profile")


func _process(delta: float) -> void:
	if editor_open or connection_setup_can_open():
		profile_notice_timer = maxf(0.0, profile_notice_timer - delta)
	if profile_notice_timer <= 0.0 and not editor_open:
		profile_notice = ""
	if not editor_open and connection_setup_can_open():
		if (
			Input.is_action_just_pressed("ui_right")
			or Input.is_action_just_pressed("ui_focus_next")
		):
			open_editor()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not editor_open:
		return
	if (
		event.is_action_pressed("ui_cancel")
		or event.is_action_pressed("pause_game")
		or event.is_action_pressed("network_menu")
	):
		close_editor(false)
		get_viewport().set_input_as_handled()


func runtime_root() -> Node:
	var layer := get_parent()
	return layer.get_parent() if layer != null else null


func session_node() -> Node:
	var runtime := runtime_root()
	return (
		runtime.get_node_or_null("MultiplayerSession")
		if runtime != null
		else null
	)


func profile_default_port() -> int:
	var session := session_node()
	if session == null:
		return MultiplayerConnectionProfile.DEFAULT_PORT
	var policy_value: Variant = session.get("policy")
	var policy: Dictionary = (
		policy_value if typeof(policy_value) == TYPE_DICTIONARY else {}
	)
	return clampi(
		int(
			policy.get(
				"default_port",
				MultiplayerConnectionProfile.DEFAULT_PORT
			)
		),
		MultiplayerConnectionProfile.MIN_PORT,
		MultiplayerConnectionProfile.MAX_PORT
	)


func profile_default_name() -> String:
	var session := session_node()
	if session != null and session.has_method("default_local_name"):
		return str(session.call("default_local_name"))
	return "WANDERER"


func connection_setup_can_open() -> bool:
	var session := session_node()
	if session == null:
		return false
	return (
		bool(session.get("lobby_open"))
		and str(session.get("mode")) == MultiplayerSessionModel.MODE_OFFLINE
		and not bool(session.get("connection_pending"))
	)


func has_connection_command_line_override() -> bool:
	for value in OS.get_cmdline_user_args():
		var argument := str(value)
		if (
			argument == "--host"
			or argument == "--invade"
			or argument.begins_with("--join=")
			or argument.begins_with("--port=")
			or argument.begins_with("--name=")
		):
			return true
	return false


func load_saved_profile(
	root_path: String = MultiplayerConnectionProfileStore.ROOT
) -> Dictionary:
	var session := session_node()
	if session == null or has_connection_command_line_override():
		return {
			"ok": session != null,
			"profile": current_session_profile(),
			"skipped_for_command_line": session != null,
			"errors": []
		}
	var result := MultiplayerConnectionProfileStore.load_profile(
		profile_default_port(),
		profile_default_name(),
		root_path
	)
	var load_errors_value: Variant = result.get("errors", [])
	var load_error_count := 0
	if typeof(load_errors_value) == TYPE_ARRAY:
		load_error_count = (load_errors_value as Array).size()
	elif typeof(load_errors_value) == TYPE_PACKED_STRING_ARRAY:
		load_error_count = (load_errors_value as PackedStringArray).size()
	if bool(result.get("ok", false)):
		apply_profile_to_session(
			result.get(
				"profile",
				MultiplayerConnectionProfile.default_profile(
					profile_default_port(),
					profile_default_name()
				)
			)
		)
		if bool(result.get("recovered_from_backup", false)):
			profile_notice = "RECOVERED SAVED CONNECTION"
			profile_notice_timer = PROFILE_NOTICE_DURATION
		elif bool(result.get("migrated", false)):
			profile_notice = "UPDATED SAVED CONNECTION"
			profile_notice_timer = PROFILE_NOTICE_DURATION
		elif bool(result.get("used_defaults", false)) and load_error_count > 0:
			profile_notice = "INVALID SAVED CONNECTION — LOCALHOST"
			profile_notice_timer = PROFILE_NOTICE_DURATION
	return result


func current_session_profile() -> Dictionary:
	var session := session_node()
	if session == null:
		return MultiplayerConnectionProfile.default_profile(
			profile_default_port(),
			profile_default_name()
		)
	return MultiplayerConnectionProfile.sanitize(
		{
			"schema_version": MultiplayerConnectionProfile.CURRENT_SCHEMA,
			"address": session.get("connect_address"),
			"port": session.get("connect_port"),
			"player_name": session.get("local_name")
		},
		profile_default_port(),
		profile_default_name()
	)


func apply_profile_to_session(value: Variant) -> Dictionary:
	var profile := MultiplayerConnectionProfile.sanitize(
		value,
		profile_default_port(),
		profile_default_name()
	)
	var session := session_node()
	if session != null:
		session.set("connect_address", str(profile.get("address")))
		session.set("connect_port", int(profile.get("port")))
		session.set("local_name", str(profile.get("player_name")))
	return profile


func open_editor() -> bool:
	if not connection_setup_can_open():
		return false
	var profile := current_session_profile()
	address_edit.text = str(
		profile.get(
			"address",
			MultiplayerConnectionProfile.DEFAULT_ADDRESS
		)
	)
	port_edit.value = float(
		profile.get("port", profile_default_port())
	)
	name_edit.text = str(profile.get("player_name", profile_default_name()))
	profile_notice = "PLAYER-LOCAL DETAILS — NOT PART OF CAMPAIGN SAVES"
	profile_notice_timer = 3600.0
	editor_open = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_editor_controls_visible(true)
	var session := session_node()
	if session != null:
		session.set_process(false)
	address_edit.grab_focus()
	address_edit.select_all()
	queue_redraw()
	return true


func close_editor(saved: bool) -> void:
	if not editor_open:
		return
	editor_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_editor_controls_visible(false)
	var session := session_node()
	if session != null:
		call_deferred("restore_session_polling")
		if saved and session.has_method("set_notice"):
			session.call("set_notice", "CONNECTION SETUP SAVED LOCALLY")
	profile_notice = ""
	profile_notice_timer = 0.0
	queue_redraw()


func restore_session_polling() -> void:
	var session := session_node()
	if session != null:
		session.set_process(true)


func save_current_profile(
	root_path: String = MultiplayerConnectionProfileStore.ROOT
) -> bool:
	if not editor_open:
		return false
	var raw_profile := {
		"schema_version": MultiplayerConnectionProfile.CURRENT_SCHEMA,
		"address": address_edit.text.strip_edges(),
		"port": int(round(port_edit.value)),
		"player_name": name_edit.text.strip_edges()
	}
	var validation := MultiplayerConnectionProfile.validate(raw_profile)
	if not bool(validation.get("ok", false)):
		set_profile_error(validation.get("errors", []))
		return false
	var result := MultiplayerConnectionProfileStore.write_profile(
		raw_profile,
		profile_default_port(),
		profile_default_name(),
		root_path
	)
	if not bool(result.get("ok", false)):
		set_profile_error(result.get("errors", []))
		return false
	apply_profile_to_session(result.get("profile", raw_profile))
	close_editor(true)
	return true


func reset_fields() -> void:
	address_edit.text = MultiplayerConnectionProfile.DEFAULT_ADDRESS
	port_edit.value = float(profile_default_port())
	name_edit.text = profile_default_name()
	profile_notice = "LOCAL TEST DEFAULTS RESTORED — SAVE TO KEEP THEM"
	profile_notice_timer = 3600.0
	address_edit.grab_focus()
	address_edit.select_all()


func set_profile_error(errors: Variant) -> void:
	var parts := PackedStringArray()
	if typeof(errors) == TYPE_ARRAY:
		for error in errors:
			parts.append(str(error))
	profile_notice = (
		"INVALID CONNECTION DETAILS"
		if parts.is_empty()
		else "INVALID: %s" % " ".join(parts)
	)
	profile_notice_timer = 3600.0
	status_label.text = profile_notice


func build_controls() -> void:
	var title := make_label(
		"CONNECTION SETUP",
		Vector2(118, 61),
		Vector2(270, 28),
		18,
		Color("eee3c6")
	)
	var scope := make_label(
		"PLAYER-LOCAL  •  DIRECT ENET / UDP",
		Vector2(350, 65),
		Vector2(172, 20),
		8,
		Color("9f8651"),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	var address_label := make_label(
		"HOSTNAME OR IPv4 / IPv6 ADDRESS",
		Vector2(120, 104),
		Vector2(280, 18),
		9,
		Color("cfc4a8")
	)
	address_edit = LineEdit.new()
	address_edit.name = "AddressEdit"
	address_edit.position = Vector2(120, 122)
	address_edit.size = Vector2(400, 30)
	address_edit.max_length = MultiplayerConnectionProfile.MAX_ADDRESS_LENGTH
	address_edit.placeholder_text = "127.0.0.1 or host.example"
	address_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	address_edit.select_all_on_focus = true
	configure_line_edit(address_edit)
	add_child(address_edit)
	editor_controls.append(address_edit)

	var port_label := make_label(
		"UDP PORT",
		Vector2(120, 163),
		Vector2(120, 18),
		9,
		Color("cfc4a8")
	)
	port_edit = SpinBox.new()
	port_edit.name = "PortEdit"
	port_edit.position = Vector2(120, 181)
	port_edit.size = Vector2(152, 30)
	port_edit.min_value = MultiplayerConnectionProfile.MIN_PORT
	port_edit.max_value = MultiplayerConnectionProfile.MAX_PORT
	port_edit.step = 1.0
	port_edit.value = profile_default_port()
	port_edit.allow_greater = false
	port_edit.allow_lesser = false
	port_edit.add_theme_font_size_override("font_size", 11)
	add_child(port_edit)
	editor_controls.append(port_edit)

	var name_label := make_label(
		"ONLINE DISPLAY NAME",
		Vector2(290, 163),
		Vector2(230, 18),
		9,
		Color("cfc4a8")
	)
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.position = Vector2(290, 181)
	name_edit.size = Vector2(230, 30)
	name_edit.max_length = MultiplayerSessionModel.MAX_NAME_LENGTH
	name_edit.placeholder_text = "WANDERER"
	name_edit.select_all_on_focus = true
	configure_line_edit(name_edit)
	add_child(name_edit)
	editor_controls.append(name_edit)

	status_label = make_label(
		"",
		Vector2(120, 218),
		Vector2(400, 28),
		8,
		Color("d49a45"),
		HORIZONTAL_ALIGNMENT_CENTER
	)

	save_button = make_button(
		"SAVE CONNECTION",
		Vector2(120, 258),
		Vector2(154, 32)
	)
	save_button.name = "SaveButton"
	save_button.pressed.connect(save_current_profile)
	reset_button = make_button(
		"RESET LOCALHOST",
		Vector2(282, 258),
		Vector2(132, 32)
	)
	reset_button.name = "ResetButton"
	reset_button.pressed.connect(reset_fields)
	back_button = make_button(
		"BACK",
		Vector2(422, 258),
		Vector2(98, 32)
	)
	back_button.name = "BackButton"
	back_button.pressed.connect(func() -> void: close_editor(false))

	configure_focus_navigation()

	address_edit.text_submitted.connect(
		func(_text: String) -> void: port_edit.grab_focus()
	)
	name_edit.text_submitted.connect(
		func(_text: String) -> void: save_current_profile()
	)

	for control in [
		title,
		scope,
		address_label,
		port_label,
		name_label,
		status_label,
		save_button,
		reset_button,
		back_button
	]:
		editor_controls.append(control)



func configure_focus_navigation() -> void:
	address_edit.focus_neighbor_bottom = address_edit.get_path_to(port_edit)
	port_edit.focus_neighbor_top = port_edit.get_path_to(address_edit)
	port_edit.focus_neighbor_right = port_edit.get_path_to(name_edit)
	port_edit.focus_neighbor_bottom = port_edit.get_path_to(save_button)
	name_edit.focus_neighbor_top = name_edit.get_path_to(address_edit)
	name_edit.focus_neighbor_left = name_edit.get_path_to(port_edit)
	name_edit.focus_neighbor_bottom = name_edit.get_path_to(reset_button)
	save_button.focus_neighbor_top = save_button.get_path_to(port_edit)
	save_button.focus_neighbor_right = save_button.get_path_to(reset_button)
	reset_button.focus_neighbor_top = reset_button.get_path_to(name_edit)
	reset_button.focus_neighbor_left = reset_button.get_path_to(save_button)
	reset_button.focus_neighbor_right = reset_button.get_path_to(back_button)
	back_button.focus_neighbor_top = back_button.get_path_to(name_edit)
	back_button.focus_neighbor_left = back_button.get_path_to(reset_button)

func make_label(
	text: String,
	at: Vector2,
	extent: Vector2,
	font_size: int,
	color: Color,
	alignment: int = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = extent
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func make_button(
	text: String,
	at: Vector2,
	extent: Vector2
) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = extent
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_color_override("font_color", Color("eee3c6"))
	button.add_theme_color_override(
		"font_focus_color",
		Color("fff3c4")
	)
	add_child(button)
	return button


func configure_line_edit(edit: LineEdit) -> void:
	edit.focus_mode = Control.FOCUS_ALL
	edit.add_theme_font_size_override("font_size", 11)
	edit.add_theme_color_override("font_color", Color("eee3c6"))
	edit.add_theme_color_override("font_selected_color", Color("15191b"))
	edit.add_theme_color_override("selection_color", Color("d49a45"))
	edit.add_theme_color_override("caret_color", Color("d49a45"))


func set_editor_controls_visible(value: bool) -> void:
	for control in editor_controls:
		if control is CanvasItem:
			(control as CanvasItem).visible = value
	if status_label != null:
		status_label.text = profile_notice


func _draw() -> void:
	if editor_open:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.02, 0.025, 0.03, 0.82))
		draw_rect(PANEL_RECT, Color("15191b"))
		draw_rect(PANEL_RECT, Color("9f8651"), false, 2.0)
		draw_line(
			PANEL_RECT.position + Vector2(22, 58),
			Vector2(PANEL_RECT.end.x - 22, PANEL_RECT.position.y + 58),
			Color("9f8651"),
			1.0
		)
		if status_label != null:
			status_label.text = profile_notice
		return
	if not connection_setup_can_open():
		return
	draw_rect(LOBBY_HINT_RECT, Color(Color("15191b"), 0.96))
	draw_rect(LOBBY_HINT_RECT, Color(Color("9f8651"), 0.9), false, 1.0)
	var hint_text := (
		profile_notice
		if profile_notice_timer > 0.0 and not profile_notice.is_empty()
		else "RIGHT / TAB  CONNECTION SETUP"
	)
	draw_string(
		ThemeDB.fallback_font,
		LOBBY_HINT_RECT.position + Vector2(8, 14),
		hint_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(LOBBY_HINT_RECT.size.x - 16.0),
		8,
		Color("d49a45")
	)


func profile_snapshot() -> Dictionary:
	return current_session_profile()


func multiplayer_connection_panel_contract_ok() -> bool:
	var session := session_node()
	return (
		session != null
		and address_edit != null
		and port_edit != null
		and name_edit != null
		and save_button != null
		and reset_button != null
		and back_button != null
		and process_mode == Node.PROCESS_MODE_ALWAYS
		and process_priority < int(session.get("process_priority"))
		and bool(
			MultiplayerConnectionProfile.validate(
				current_session_profile()
			).get("ok", false)
		)
	)
