extends "res://src/cinematic_runtime.gd"

const PlayerSettings = preload("res://src/game/player_settings.gd")
const PlayerSettingsStore = preload("res://src/game/player_settings_store.gd")

const PLAYER_SETTINGS_DEFAULT_CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const PLAYER_SETTINGS_NOTICE_DURATION := 1.6

var player_settings: Dictionary = PlayerSettings.default_settings()
var player_settings_open := false
var player_settings_index := 0
var player_settings_origin_flow := 1
var player_settings_dirty := false
var player_settings_notice := ""
var player_settings_notice_timer := 0.0
var player_settings_load_status := "defaults"
var suppress_root_combat_hud := false


func _ready() -> void:
	load_player_settings()
	super._ready()


func _process(delta: float) -> void:
	player_settings_notice_timer = maxf(0.0, player_settings_notice_timer - delta)
	if player_settings_notice_timer <= 0.0 and not player_settings_open:
		player_settings_notice = ""
	if player_settings_open:
		update_player_settings_menu()
		queue_redraw()
		return
	if Input.is_action_just_pressed("options_menu") and can_open_player_settings():
		open_player_settings()
		queue_redraw()
		return
	if flow == Flow.PAUSED and confirm():
		open_player_settings()
		queue_redraw()
		return
	super._process(delta)


func load_player_settings(root_path: String = PlayerSettingsStore.ROOT) -> void:
	apply_player_settings_load_result(PlayerSettingsStore.load_settings(root_path))


func apply_player_settings_load_result(result: Dictionary) -> void:
	player_settings = PlayerSettings.sanitize(result.get("settings", {}))
	set_localisation_locale(PlayerSettings.string(player_settings, "language", "en"))
	var recovered := bool(result.get("recovered_from_backup", false))
	var migrated := bool(result.get("migrated", false))
	if recovered:
		player_settings_load_status = "recovered"
	elif migrated:
		player_settings_load_status = "migrated"
	elif bool(result.get("used_defaults", false)):
		player_settings_load_status = "defaults"
	else:
		player_settings_load_status = "loaded"
	# Recovery and migration are safe reads. Keep the sanitized values pending so
	# the next deliberate Options close promotes them through the atomic writer.
	player_settings_dirty = recovered or migrated


func player_settings_open_notice() -> String:
	match player_settings_load_status:
		"recovered":
			return localise("ui.settings.recovered", "RECOVERED SETTINGS FROM BACKUP")
		"migrated":
			return localise("ui.settings.migrated", "SETTINGS UPDATED TO CURRENT VERSION")
		"saved":
			return localise("ui.settings.saved", "SETTINGS SAVED LOCALLY")
	return localise("ui.settings.local", "SETTINGS ARE SAVED LOCALLY")


func title_menu() -> Array[String]:
	return [
		localise("ui.title.continue", "CONTINUE"),
		localise("ui.title.new_journey", "NEW JOURNEY"),
		localise("ui.title.campaigns", "CAMPAIGNS"),
		localise("ui.title.quick_start", "QUICK START"),
		localise("ui.title.options", "OPTIONS"),
		localise("ui.title.quit", "QUIT")
	]


func update_title() -> void:
	var menu: Array[String] = title_menu()
	if Input.is_action_just_pressed("ui_up"):
		selected_menu = wrapi(selected_menu - 1, 0, menu.size())
	if Input.is_action_just_pressed("ui_down"):
		selected_menu = wrapi(selected_menu + 1, 0, menu.size())
	if not confirm():
		return
	match selected_menu:
		0:
			continue_latest_profile()
		1:
			if load_campaign(PLAYER_SETTINGS_DEFAULT_CAMPAIGN_PATH):
				current_save_slot = ""
				change_flow(Flow.INTRO)
		2:
			refresh_campaign_catalog()
			change_flow(Flow.CAMPAIGN_SELECT)
		3:
			current_save_slot = ""
			play_time_seconds = 0.0
			begin_game()
		4:
			open_player_settings()
		5:
			get_tree().quit()


func can_open_player_settings() -> bool:
	if player_settings_open:
		return false
	if flow == Flow.TITLE or flow == Flow.PAUSED:
		return true
	if flow != Flow.GAME:
		return false
	return (
		not inventory_open
		and not story_journal_open
		and not save_overlay_open
		and not merchant_open
		and active_conversation_id.is_empty()
		and dialogue.is_empty()
		and active_cinematic_id.is_empty()
		and transition_lock <= 0.0
		and player_health > 0
	)


func open_player_settings() -> bool:
	if not can_open_player_settings():
		return false
	player_settings_open = true
	player_settings_origin_flow = flow
	player_settings_index = clampi(player_settings_index, 0, maxi(0, PlayerSettings.entries().size() - 1))
	player_settings_notice = player_settings_open_notice()
	player_settings_notice_timer = PLAYER_SETTINGS_NOTICE_DURATION
	return true


func close_player_settings(root_path: String = PlayerSettingsStore.ROOT) -> bool:
	if not player_settings_open:
		return true
	if player_settings_dirty:
		var result := PlayerSettingsStore.write_settings(player_settings, root_path)
		if not bool(result.get("ok", false)):
			player_settings_notice = localise(
				"ui.settings.save_failed",
				"SAVE FAILED: {error}",
				{"error": format_errors(result.get("errors", []))}
			)
			player_settings_notice_timer = 3.0
			return false
		player_settings = PlayerSettings.sanitize(result.get("settings", player_settings))
		player_settings_dirty = false
		player_settings_load_status = "saved"
	player_settings_open = false
	player_settings_notice = ""
	player_settings_notice_timer = 0.0
	return true


func update_player_settings_menu() -> void:
	var definitions := PlayerSettings.entries()
	if definitions.is_empty():
		close_player_settings()
		return
	if (
		Input.is_action_just_pressed("ui_cancel")
		or Input.is_action_just_pressed("options_menu")
		or Input.is_action_just_pressed("pause_game")
	):
		close_player_settings()
		return
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
		player_settings_index = posmod(player_settings_index - 1, definitions.size())
		return
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
		player_settings_index = posmod(player_settings_index + 1, definitions.size())
		return
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left"):
		adjust_selected_player_setting(-1)
		return
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right"):
		adjust_selected_player_setting(1)
		return
	if confirm() or Input.is_action_just_pressed("attack"):
		activate_selected_player_setting()


func selected_player_setting_definition() -> Dictionary:
	var definitions := PlayerSettings.entries()
	if definitions.is_empty():
		return {}
	player_settings_index = clampi(player_settings_index, 0, definitions.size() - 1)
	var value: Variant = definitions[player_settings_index]
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func adjust_selected_player_setting(direction: int) -> bool:
	var definition := selected_player_setting_definition()
	var setting_id := str(definition.get("id", ""))
	var kind := str(definition.get("kind", ""))
	if setting_id.is_empty() or kind == "action":
		return false
	player_settings = PlayerSettings.adjusted(player_settings, setting_id, direction)
	if setting_id == "language":
		set_localisation_locale(PlayerSettings.string(player_settings, "language", "en"))
	player_settings_dirty = true
	player_settings_notice = "%s  %s" % [
		player_setting_label(definition).to_upper(),
		player_setting_value_text(setting_id)
	]
	player_settings_notice_timer = PLAYER_SETTINGS_NOTICE_DURATION
	return true


func activate_selected_player_setting() -> bool:
	var definition := selected_player_setting_definition()
	var setting_id := str(definition.get("id", ""))
	match setting_id:
		"reset_defaults":
			player_settings = PlayerSettings.default_settings()
			set_localisation_locale(PlayerSettings.string(player_settings, "language", "en"))
			player_settings_dirty = true
			player_settings_notice = localise("ui.settings.defaults_restored", "DEFAULT SETTINGS RESTORED")
			player_settings_notice_timer = PLAYER_SETTINGS_NOTICE_DURATION
			return true
		"back":
			return close_player_settings()
	if str(definition.get("kind", "")) == "boolean":
		return adjust_selected_player_setting(1)
	if str(definition.get("kind", "")) in ["range", "choice"]:
		return adjust_selected_player_setting(1)
	return false


func player_setting_number(setting_id: String, fallback: float = 1.0) -> float:
	return PlayerSettings.number(player_settings, setting_id, fallback)


func player_setting_bool(setting_id: String, fallback: bool = false) -> bool:
	return PlayerSettings.boolean(player_settings, setting_id, fallback)


func player_setting_string(setting_id: String, fallback: String = "") -> String:
	return PlayerSettings.string(player_settings, setting_id, fallback)


func player_setting_label(definition: Dictionary) -> String:
	return localise(
		str(definition.get("label_key", "")),
		str(definition.get("label", definition.get("id", "SETTING")))
	)


func player_setting_value_text(setting_id: String) -> String:
	if setting_id in ["show_action_prompts", "high_contrast_ui"]:
		return localise(
			"ui.settings.on" if PlayerSettings.boolean(player_settings, setting_id, false) else "ui.settings.off",
			"ON" if PlayerSettings.boolean(player_settings, setting_id, false) else "OFF"
		)
	if setting_id == "language":
		var locale := PlayerSettings.string(player_settings, setting_id, "en")
		return localise(
			"ui.settings.language.%s" % locale,
			PlayerSettings.value_text(player_settings, setting_id)
		)
	return PlayerSettings.value_text(player_settings, setting_id)


func player_settings_rows() -> Array:
	var output: Array = []
	for value in PlayerSettings.rows(player_settings):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = (value as Dictionary).duplicate(true)
		row["label"] = player_setting_label(row)
		row["value"] = player_setting_value_text(str(row.get("id", "")))
		output.append(row)
	return output


func player_settings_snapshot() -> Dictionary:
	return PlayerSettings.sanitize(player_settings)


func player_settings_entry_count() -> int:
	return PlayerSettings.entries().size()


func player_settings_contract_ok() -> bool:
	return (
		bool(PlayerSettings.validate(player_settings).get("ok", false))
		and player_settings_entry_count() >= 10
		and player_settings_index >= 0
		and player_settings_index < player_settings_entry_count()
		and ["defaults", "loaded", "recovered", "migrated", "saved"].has(player_settings_load_status)
		and player_setting_string("language", "en") == current_locale
		and localisation_contract_ok()
	)


func can_open_save_overlay() -> bool:
	return not player_settings_open and super.can_open_save_overlay()


func can_flush_autosave() -> bool:
	return not player_settings_open and super.can_flush_autosave()


func draw_pause() -> void:
	super.draw_pause()
	if not player_settings_open:
		draw_centered(
			localise("ui.pause.options", "{confirm}  OPTIONS", {"confirm": "E / A"}),
			187,
			10,
			Color("bba76d")
		)


func presentation_overlay_handles_combat_readability() -> bool:
	var overlay := get_node_or_null("PresentationLayer/PresentationOverlay")
	return overlay != null and overlay.has_method("combat_readability_contract_ok")


func root_presentation_suppression_contract_ok() -> bool:
	var overlay := get_node_or_null("PresentationLayer/PresentationOverlay")
	return (
		presentation_overlay_handles_combat_readability()
		and not suppress_root_combat_hud
		and overlay != null
		and overlay.has_method("draw_adventure_hud")
		and overlay.has_method("draw_boss_banner_overlay")
		and overlay.has_method("draw_projectile_overlay")
	)


func draw_game() -> void:
	if not presentation_overlay_handles_combat_readability():
		super.draw_game()
		return
	# The inherited Boss runtime draws its banner after the world. The higher
	# CanvasLayer owns that banner in the production scene, so temporarily hide
	# only the root copy while preserving the durable banner state.
	var preserved_banner := boss_banner
	boss_banner = ""
	super.draw_game()
	boss_banner = preserved_banner


func draw_hud(era_data: Dictionary) -> void:
	if not presentation_overlay_handles_combat_readability():
		super.draw_hud(era_data)
		return
	# Keep inherited quest, companion, notice and system HUD contributions. Only
	# make Arsenal and Boss HUD queries resolve empty while their polished copies
	# are drawn by the higher presentation layer.
	suppress_root_combat_hud = true
	super.draw_hud(era_data)
	suppress_root_combat_hud = false


func equipped_ranged_weapon_data() -> Dictionary:
	if suppress_root_combat_hud and presentation_overlay_handles_combat_readability():
		return {}
	return super.equipped_ranged_weapon_data()


func current_boss_index() -> int:
	if suppress_root_combat_hud and presentation_overlay_handles_combat_readability():
		return -1
	return super.current_boss_index()


func active_arena_context() -> Dictionary:
	if suppress_root_combat_hud and presentation_overlay_handles_combat_readability():
		return {}
	return super.active_arena_context()


func draw_projectiles() -> void:
	# Projectiles are redrawn in the high presentation CanvasLayer so they share
	# camera conversion and feet-based ordering with actors and world entities.
	if presentation_overlay_handles_combat_readability():
		return
	super.draw_projectiles()


func draw_active_boss_arena() -> void:
	# The presentation layer owns the arena frame when available. Retain the
	# inherited fallback for stripped-down or custom scenes without that layer.
	if presentation_overlay_handles_combat_readability():
		return
	super.draw_active_boss_arena()
