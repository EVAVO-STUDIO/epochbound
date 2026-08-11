extends "res://src/environment_animation_overlay.gd"

const CombatBossCatalog = preload("res://src/content/boss_catalog.gd")

const COMBAT_FLOW_GAME := 4
const COMBAT_FLOW_PAUSED := 5
const COMBAT_VIEW := Vector2(640, 360)
const MAX_PROJECTILE_OVERLAYS := 128
const PROJECTILE_TRAIL_LENGTH := 18.0
const PLAYER_SETTINGS_PANEL := Rect2(64, 18, 512, 324)
const PLAYER_SETTINGS_ROW_HEIGHT := 20.0


func player_setting_number(setting_id: String, fallback: float = 1.0) -> float:
	var runtime := runtime_root()
	if runtime == null or not runtime.has_method("player_setting_number"):
		return fallback
	return float(runtime.call("player_setting_number", setting_id, fallback))


func player_setting_bool(setting_id: String, fallback: bool = false) -> bool:
	var runtime := runtime_root()
	if runtime == null or not runtime.has_method("player_setting_bool"):
		return fallback
	return bool(runtime.call("player_setting_bool", setting_id, fallback))


func player_settings_is_open() -> bool:
	return runtime_boolean("player_settings_open")


func runtime_localise(key: String, fallback: String, replacements: Dictionary = {}) -> String:
	var runtime := runtime_root()
	if runtime != null and runtime.has_method("localise"):
		return str(runtime.call("localise", key, fallback, replacements))
	return fallback


func animation_should_freeze() -> bool:
	return player_settings_is_open() or super.animation_should_freeze()


func update_reactions(delta: float) -> void:
	if player_settings_is_open():
		return
	super.update_reactions(delta)


func update_atmosphere(delta: float) -> void:
	if player_settings_is_open():
		return
	super.update_atmosphere(delta * player_setting_number("environment_motion_intensity", 1.0))


func update_footsteps(delta: float) -> void:
	if player_settings_is_open():
		return
	super.update_footsteps(delta)


func update_impact_bursts(delta: float) -> void:
	if player_settings_is_open():
		return
	super.update_impact_bursts(delta)


func update_environment_animation(delta: float) -> void:
	var scale := player_setting_number("environment_motion_intensity", 1.0)
	if scale <= 0.001:
		ground_disturbances.clear()
	super.update_environment_animation(delta * scale)


func environment_spawn_allowed() -> bool:
	return player_setting_number("environment_motion_intensity", 1.0) > 0.001 and super.environment_spawn_allowed()


func trigger_shake(strength: float, duration: float) -> void:
	super.trigger_shake(strength * player_setting_number("camera_shake_intensity", 1.0), duration)


func apply_root_shake() -> void:
	var scale := player_setting_number("camera_shake_intensity", 1.0)
	if player_settings_is_open() or scale <= 0.001:
		shake_strength = 0.0
		shake_timer = 0.0
		var runtime := runtime_root()
		if runtime is Node2D:
			(runtime as Node2D).position = Vector2.ZERO
		return
	super.apply_root_shake()


func resolve_context_prompt() -> Dictionary:
	if not player_setting_bool("show_action_prompts", true):
		return {}
	return super.resolve_context_prompt()


func draw_context_prompt() -> void:
	if not player_setting_bool("show_action_prompts", true):
		return
	super.draw_context_prompt()


func interaction_world_pulse_allowed() -> bool:
	return player_setting_bool("show_action_prompts", true) and super.interaction_world_pulse_allowed()


func profile_color(key: String, fallback: String) -> Color:
	var resolved := super.profile_color(key, fallback)
	if not player_setting_bool("high_contrast_ui", false):
		return resolved
	match key:
		"ink", "ui_fill":
			return Color("050505")
		"ui_text":
			return Color("ffffff")
		"ui_frame":
			return Color("f4d35e")
		"danger":
			return Color("ff5a52")
	return resolved


func draw_screen_texture(multiplier: float) -> void:
	super.draw_screen_texture(multiplier * player_setting_number("screen_texture_intensity", 1.0))


func draw_title_finish() -> void:
	super.draw_title_finish()
	draw_player_settings_panel()


func draw_game_finish() -> void:
	var saved_era_flash := era_flash
	var saved_impact_flash := impact_flash
	var flash_scale := player_setting_number("flash_intensity", 1.0)
	era_flash *= flash_scale
	impact_flash *= flash_scale
	# The root runtime already draws its pause panel. Because this presentation
	# node lives on a higher CanvasLayer, redrawing the world here would cover it.
	if runtime_flow() == COMBAT_FLOW_PAUSED:
		draw_screen_texture(1.0)
		era_flash = saved_era_flash
		impact_flash = saved_impact_flash
		draw_player_settings_panel()
		return
	super.draw_game_finish()
	era_flash = saved_era_flash
	impact_flash = saved_impact_flash
	draw_player_settings_panel()


func draw_player_settings_panel() -> void:
	if not player_settings_is_open():
		return
	var runtime := runtime_root()
	if runtime == null or not runtime.has_method("player_settings_rows"):
		return
	var rows_value: Variant = runtime.call("player_settings_rows")
	var rows: Array = rows_value as Array if typeof(rows_value) == TYPE_ARRAY else []
	var selected := clampi(runtime_integer("player_settings_index", 0), 0, maxi(0, rows.size() - 1))
	var fill := profile_color("ui_fill", "15191b")
	var frame := profile_color("ui_frame", "9f8651")
	var text := profile_color("ui_text", "eee3c6")
	var accent := profile_color("accent", "d49a45")
	draw_rect(Rect2(Vector2.ZERO, COMBAT_VIEW), Color(0, 0, 0, 0.76))
	draw_rect(PLAYER_SETTINGS_PANEL, Color(fill, 0.99))
	draw_panel_frame(PLAYER_SETTINGS_PANEL, frame)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(PLAYER_SETTINGS_PANEL.position.x + 18.0, PLAYER_SETTINGS_PANEL.position.y + 28.0),
		runtime_localise("ui.options.title", "OPTIONS"),
		HORIZONTAL_ALIGNMENT_LEFT,
		210,
		18,
		text
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(PLAYER_SETTINGS_PANEL.position.x + 244.0, PLAYER_SETTINGS_PANEL.position.y + 27.0),
		runtime_localise("ui.options.header", "PLAYER LOCAL  •  VERSIONED  •  RECOVERABLE  •  REMAPPABLE"),
		HORIZONTAL_ALIGNMENT_RIGHT,
		248,
		7,
		frame.darkened(0.04)
	)
	var row_start_y := PLAYER_SETTINGS_PANEL.position.y + 58.0
	for index in range(rows.size()):
		if typeof(rows[index]) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = rows[index] as Dictionary
		var y := row_start_y + float(index) * PLAYER_SETTINGS_ROW_HEIGHT
		var active := index == selected
		if active:
			draw_rect(Rect2(PLAYER_SETTINGS_PANEL.position.x + 12.0, y - 13.0, PLAYER_SETTINGS_PANEL.size.x - 24.0, 18.0), Color(frame, 0.16))
			draw_rect(Rect2(Vector2(PLAYER_SETTINGS_PANEL.position.x + 17.0, y - 8.0), Vector2(4, 4)), accent)
		var label := str(row.get("label", row.get("id", "SETTING"))).to_upper()
		var value_text := str(row.get("value", ""))
		if str(row.get("kind", "")) == "action":
			value_text = runtime_localise("ui.options.confirm", "CONFIRM")
		draw_string(
			ThemeDB.fallback_font,
			Vector2(PLAYER_SETTINGS_PANEL.position.x + 30.0, y),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			300,
			9,
			text if active else text.darkened(0.24)
		)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(PLAYER_SETTINGS_PANEL.position.x + 350.0, y),
			value_text,
			HORIZONTAL_ALIGNMENT_RIGHT,
			190,
			9,
			accent if active else frame.darkened(0.18)
		)
	var notice := runtime_string("player_settings_notice").strip_edges()
	if not notice.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(PLAYER_SETTINGS_PANEL.position.x + 18.0, PLAYER_SETTINGS_PANEL.end.y - 29.0),
			notice.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER,
			int(PLAYER_SETTINGS_PANEL.size.x - 36.0),
			7,
			frame
		)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(PLAYER_SETTINGS_PANEL.position.x + 18.0, PLAYER_SETTINGS_PANEL.end.y - 12.0),
		runtime_localise(
			"ui.options.footer",
			"{confirm} SELECT   •   LEFT / RIGHT CHANGE   •   ESC / O BACK",
			{"confirm": "E / A"}
		),
		HORIZONTAL_ALIGNMENT_CENTER,
		int(PLAYER_SETTINGS_PANEL.size.x - 36.0),
		7,
		text.darkened(0.18)
	)


func draw_world_accents() -> void:
	super.draw_world_accents()
	draw_boss_arena_overlay()


func draw_runtime_entity_overlays() -> void:
	if environment_draw_allowed():
		draw_ground_disturbances()
	var records := combat_depth_records()
	last_depth_order.clear()
	for record_value in records:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_value as Dictionary
		var kind := str(record.get("kind", ""))
		last_depth_order.append(str(record.get("key", kind)))
		match kind:
			"player":
				draw_player_sprite(world_to_screen(runtime_vector("player")))
			"companion":
				draw_companion_sprite(world_to_screen(runtime_vector("companion")))
			"entity":
				var entity_value: Variant = record.get("entity", {})
				if typeof(entity_value) == TYPE_DICTIONARY:
					draw_entity_sprite(entity_value as Dictionary)
			"projectile":
				var projectile_value: Variant = record.get("projectile", {})
				if typeof(projectile_value) == TYPE_DICTIONARY:
					draw_projectile_overlay(projectile_value as Dictionary)
	draw_landmark_foregrounds()


func combat_depth_records() -> Array:
	var records: Array = super.depth_records()
	var projectile_values := runtime_array("projectiles")
	var limit := mini(projectile_values.size(), MAX_PROJECTILE_OVERLAYS)
	for index in range(limit):
		if typeof(projectile_values[index]) != TYPE_DICTIONARY:
			continue
		var projectile: Dictionary = projectile_values[index] as Dictionary
		if not bool(projectile.get("active", true)):
			continue
		var position_value: Variant = projectile.get("position", Vector2.ZERO)
		var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		records.append({
			"kind": "projectile",
			"key": projectile_key(projectile, index),
			"y": position.y,
			"tie": 4,
			"projectile": projectile
		})
	records.sort_custom(Callable(self, "depth_before"))
	return records


func projectile_key(projectile: Dictionary, index: int) -> String:
	return "projectile:%s:%s:%d" % [
		str(projectile.get("source_kind", "unknown")),
		str(projectile.get("source_id", "source")),
		index
	]


func draw_projectile_overlay(projectile: Dictionary) -> void:
	var segment := projectile_screen_segment(projectile)
	var start_value: Variant = segment.get("start", Vector2.ZERO)
	var finish_value: Variant = segment.get("finish", Vector2.ZERO)
	var start: Vector2 = start_value if start_value is Vector2 else Vector2.ZERO
	var finish: Vector2 = finish_value if finish_value is Vector2 else start
	if not Rect2(Vector2(-24, -24), COMBAT_VIEW + Vector2(48, 48)).has_point(finish):
		return
	var color_value: Variant = projectile.get("color", Color.WHITE)
	var color: Color = color_value if color_value is Color else Color.WHITE
	var ink := profile_color("ink", "13161a")
	var light := profile_color("light", "d7c99b")
	var radius := clampf(float(projectile.get("radius", 3.0)), 1.0, 10.0)
	draw_line(start, finish, Color(ink, 0.9), 3.0)
	draw_line(start, finish, Color(color, 0.92), 1.0)
	draw_circle(finish, radius + 1.0, Color(ink, 0.92))
	draw_circle(finish, radius, color)
	draw_rect(Rect2(finish + Vector2(-1, -1), Vector2(2, 2)), Color(light, 0.78))


func projectile_screen_segment(projectile: Dictionary) -> Dictionary:
	var finish_value: Variant = projectile.get("position", Vector2.ZERO)
	var start_value: Variant = projectile.get("previous_position", finish_value)
	var finish_world: Vector2 = finish_value if finish_value is Vector2 else Vector2.ZERO
	var start_world: Vector2 = start_value if start_value is Vector2 else finish_world
	var travel := finish_world - start_world
	if travel.length() > PROJECTILE_TRAIL_LENGTH:
		start_world = finish_world - travel.normalized() * PROJECTILE_TRAIL_LENGTH
	return {
		"start": world_to_screen(start_world),
		"finish": world_to_screen(finish_world)
	}


func draw_adventure_hud() -> void:
	super.draw_adventure_hud()
	draw_arsenal_status_overlay()
	draw_boss_status_overlay()
	draw_boss_banner_overlay()


func draw_arsenal_status_overlay() -> void:
	var snapshot := arsenal_status_snapshot()
	if snapshot.is_empty():
		return
	var fill := profile_color("ui_fill", "15191b")
	var frame := profile_color("ui_frame", "9f8651")
	var text := profile_color("ui_text", "eee3c6")
	var accent := profile_color("accent", "d49a45")
	# Mask the narrow left edge of the inherited prototype ammo panel that sits
	# outside the polished map plaque. The rest is already fully covered.
	draw_rect(Rect2(404, 7, 34, 47), Color(fill, 1.0))
	var rect := Rect2(438, 57, 195, 42)
	draw_rect(rect, Color(fill, 1.0))
	draw_panel_frame(rect, frame.darkened(0.12))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(rect.position.x + 11, rect.position.y + 16),
		"AMMO %02d / %02d" % [int(snapshot.get("loaded", 0)), int(snapshot.get("reserve", 0))],
		HORIZONTAL_ALIGNMENT_LEFT,
		112,
		9,
		text
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(rect.position.x + 126, rect.position.y + 16),
		"G / RT",
		HORIZONTAL_ALIGNMENT_RIGHT,
		56,
		8,
		accent
	)
	var reload_duration := float(snapshot.get("reload_duration", 0.0))
	var reload_timer := float(snapshot.get("reload_timer", 0.0))
	if reload_duration > 0.0 and reload_timer > 0.0:
		var progress := 1.0 - clampf(reload_timer / reload_duration, 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(11, 25), Vector2(173, 7)), Color(profile_color("ink", "13161a"), 0.94))
		draw_rect(Rect2(rect.position + Vector2(12, 26), Vector2(171.0 * progress, 5)), accent)
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 11, rect.position.y + 39), "RELOADING", HORIZONTAL_ALIGNMENT_LEFT, 173, 7, text.darkened(0.16))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 11, rect.position.y + 34), str(snapshot.get("weapon_name", "RANGED WEAPON")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 173, 7, text.darkened(0.16))


func arsenal_status_snapshot() -> Dictionary:
	var runtime := runtime_root()
	if runtime == null or not runtime.has_method("equipped_ranged_weapon_data"):
		return {}
	var weapon_value: Variant = runtime.call("equipped_ranged_weapon_data")
	if typeof(weapon_value) != TYPE_DICTIONARY or (weapon_value as Dictionary).is_empty():
		return {}
	var weapon_data: Dictionary = weapon_value as Dictionary
	var weapon_id := str(runtime.call("equipped_weapon_id")) if runtime.has_method("equipped_weapon_id") else ""
	var loaded_value: Variant = runtime.get("loaded_ammo")
	var loaded_ammo: Dictionary = loaded_value as Dictionary if typeof(loaded_value) == TYPE_DICTIONARY else {}
	var loaded := int(loaded_ammo.get(weapon_id, 0))
	var reserve := int(runtime.call("reserve_ammunition", weapon_data)) if runtime.has_method("reserve_ammunition") else 0
	return {
		"weapon_id": weapon_id,
		"weapon_name": str(weapon_data.get("display_name", weapon_id)),
		"loaded": loaded,
		"reserve": reserve,
		"reload_timer": runtime_number("reload_timer", 0.0),
		"reload_duration": runtime_number("reload_duration", 0.0)
	}


func draw_boss_arena_overlay() -> void:
	var context := runtime_dictionary_call("active_arena_context")
	if context.is_empty():
		return
	var definition := runtime_dictionary_call("context_definition", [context])
	if definition.is_empty():
		return
	var arena := CombatBossCatalog.arena_bounds(definition)
	if arena.size.x <= 0.0 or arena.size.y <= 0.0:
		return
	var screen_rect := Rect2(arena.position - runtime_camera_offset(), arena.size)
	var danger := profile_color("danger", "b94d45")
	draw_rect(screen_rect, Color(danger, 0.055))
	draw_rect(screen_rect, Color(danger, 0.58), false, 1.0)
	for corner in [screen_rect.position, Vector2(screen_rect.end.x, screen_rect.position.y), Vector2(screen_rect.position.x, screen_rect.end.y), screen_rect.end]:
		draw_circle(corner, 2.0, Color(danger, 0.72))


func draw_boss_status_overlay() -> void:
	var snapshot := boss_status_snapshot()
	if snapshot.is_empty():
		return
	var fill := profile_color("ui_fill", "15191b")
	var frame := profile_color("ui_frame", "9f8651")
	var text := profile_color("ui_text", "eee3c6")
	var danger := profile_color("danger", "b94d45")
	var rect := Rect2(86, 292, 468, 42)
	draw_rect(rect, Color(fill, 1.0))
	draw_panel_frame(rect, frame.darkened(0.1))
	if bool(snapshot.get("reinforcements_only", false)):
		draw_string(ThemeDB.fallback_font, Vector2(100, 317), "REINFORCEMENTS REMAIN", HORIZONTAL_ALIGNMENT_CENTER, 440, 10, danger.lightened(0.15))
		return
	var maximum := maxi(1, int(snapshot.get("maximum", 1)))
	var health := clampi(int(snapshot.get("health", maximum)), 0, maximum)
	draw_string(ThemeDB.fallback_font, Vector2(100, 309), str(snapshot.get("name", "BOSS")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 250, 11, text)
	draw_string(ThemeDB.fallback_font, Vector2(350, 309), str(snapshot.get("phase", "PHASE")).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, 190, 9, frame)
	draw_notched_bar(Rect2(98, 316, 444, 8), health, maximum, danger)


func draw_boss_banner_overlay() -> void:
	var banner := runtime_string("boss_banner").strip_edges()
	if banner.is_empty() or not presentation_world_layers_allowed():
		return
	var fill := profile_color("ui_fill", "15191b")
	var frame := profile_color("ui_frame", "9f8651")
	var text := profile_color("ui_text", "eee3c6")
	var rect := Rect2(92, 104, 456, 34)
	draw_rect(rect, Color(fill, 1.0))
	draw_panel_frame(rect, frame)
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 12, rect.position.y + 22), banner.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x - 24), 10, text)


func boss_status_snapshot() -> Dictionary:
	var runtime := runtime_root()
	if runtime == null or not runtime.has_method("current_boss_index"):
		return {}
	var index := int(runtime.call("current_boss_index"))
	var context := runtime_dictionary_call("active_arena_context")
	if index < 0:
		return {"reinforcements_only": true} if not context.is_empty() else {}
	var entities := runtime_array("runtime_entities")
	if index >= entities.size() or typeof(entities[index]) != TYPE_DICTIONARY:
		return {}
	var entity: Dictionary = entities[index] as Dictionary
	var definition_value: Variant = entity.get("definition", {})
	var definition: Dictionary = definition_value as Dictionary if typeof(definition_value) == TYPE_DICTIONARY else {}
	var maximum := maxi(1, int(definition.get("max_health", 1)))
	var placement_id := str(entity.get("placement_id", ""))
	var phase_ids_value: Variant = runtime.get("boss_phase_ids")
	var phase_ids: Dictionary = phase_ids_value as Dictionary if typeof(phase_ids_value) == TYPE_DICTIONARY else {}
	var phase := CombatBossCatalog.phase_by_id(definition, str(phase_ids.get(placement_id, "")))
	return {
		"reinforcements_only": false,
		"name": str(definition.get("display_name", "Boss")),
		"phase": CombatBossCatalog.phase_name(phase),
		"health": int(entity.get("health", maximum)),
		"maximum": maximum
	}


func runtime_dictionary_call(method_name: String, arguments: Array = []) -> Dictionary:
	var runtime := runtime_root()
	if runtime == null or not runtime.has_method(method_name):
		return {}
	var value: Variant = runtime.callv(method_name, arguments)
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func presentation_world_layers_allowed() -> bool:
	return (
		runtime_flow() == COMBAT_FLOW_GAME
		and not animation_should_freeze()
		and active_cinematic_id().is_empty()
	)


func combat_projectile_count() -> int:
	var count := 0
	for value in runtime_array("projectiles"):
		if typeof(value) == TYPE_DICTIONARY and bool((value as Dictionary).get("active", true)):
			count += 1
	return mini(count, MAX_PROJECTILE_OVERLAYS)


func combat_depth_order_keys() -> PackedStringArray:
	var output := PackedStringArray()
	for record_value in combat_depth_records():
		if typeof(record_value) == TYPE_DICTIONARY:
			var record: Dictionary = record_value as Dictionary
			output.append(str(record.get("key", record.get("kind", ""))))
	return output


func combat_readability_contract_ok() -> bool:
	return (
		environment_animation_contract_ok()
		and MAX_PROJECTILE_OVERLAYS > 0
		and MAX_PROJECTILE_OVERLAYS <= 160
		and PROJECTILE_TRAIL_LENGTH >= 8.0
		and PROJECTILE_TRAIL_LENGTH <= 32.0
	)


func player_settings_overlay_contract_ok() -> bool:
	return (
		combat_readability_contract_ok()
		and PLAYER_SETTINGS_PANEL.size.x >= 480.0
		and PLAYER_SETTINGS_PANEL.size.y >= 300.0
		and PLAYER_SETTINGS_ROW_HEIGHT >= 18.0
		and PLAYER_SETTINGS_ROW_HEIGHT <= 24.0
	)
