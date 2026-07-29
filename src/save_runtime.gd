extends "res://src/story_runtime.gd"

const SaveProfile = preload("res://src/content/save_profile.gd")
const SaveProfileStore = preload("res://src/content/save_profile_store.gd")
const SaveValidator = preload("res://src/content/save_validator.gd")
const SaveRepository = preload("res://src/content/campaign_repository.gd")
const SaveMapModel = preload("res://src/content/map_model.gd")
const SaveStoryModel = preload("res://src/game/story_model.gd")

const SAVE_DEFAULT_CAMPAIGN_PATH := "res://campaigns/epochbound_demo/campaign.json"
const SAVE_NOTICE_DURATION := 1.6
const SAVE_SLOT_ROWS := 5

var save_overlay_open := false
var save_overlay_mode := 0
var save_slot_index := 0
var current_save_slot := ""
var save_notice := ""
var save_notice_timer := 0.0
var play_time_seconds := 0.0
var pending_autosave_reason := ""
var save_operation_depth := 0
var last_durable_fingerprint := ""
var save_slot_cache: Dictionary = {}
var continue_profile: Dictionary = {}
var continue_profile_path := ""


func load_campaign(path: String) -> bool:
	var validation: Dictionary = SaveValidator.validate_campaign_path(path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		push_error("Save-aware campaign validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	save_operation_depth += 1
	var loaded: bool = super.load_campaign(path)
	save_operation_depth -= 1
	if loaded:
		reset_save_runtime_state()
	return loaded


func load_fallback_campaign() -> void:
	save_operation_depth += 1
	super.load_fallback_campaign()
	save_operation_depth -= 1
	reset_save_runtime_state()


func reset_save_runtime_state() -> void:
	save_overlay_open = false
	save_overlay_mode = 0
	save_slot_index = 0
	current_save_slot = ""
	save_notice = ""
	save_notice_timer = 0.0
	play_time_seconds = 0.0
	pending_autosave_reason = ""
	last_durable_fingerprint = durable_progress_fingerprint()
	refresh_save_slot_cache()
	refresh_continue_profile()


func title_menu() -> Array[String]:
	return ["CONTINUE", "NEW JOURNEY", "CAMPAIGNS", "QUICK START", "QUIT"]


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
			if load_campaign(SAVE_DEFAULT_CAMPAIGN_PATH):
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
			get_tree().quit()


func continue_latest_profile() -> bool:
	refresh_continue_profile()
	if continue_profile.is_empty():
		load_error = "No valid save profile is available."
		set_save_notice(load_error)
		return false
	var campaign_id := str(continue_profile.get("campaign_id", ""))
	var path := resolve_campaign_path(campaign_id)
	if path.is_empty():
		load_error = "Saved campaign '%s' is not installed." % campaign_id
		set_save_notice(load_error)
		return false
	return apply_save_profile(continue_profile, path)


func begin_game() -> void:
	save_operation_depth += 1
	super.begin_game()
	save_operation_depth -= 1
	current_save_slot = ""
	play_time_seconds = 0.0
	last_durable_fingerprint = durable_progress_fingerprint()
	request_autosave("Journey begun")


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	var activated: bool = super.activate_map(map_id, entry_id, requested_era, use_transition)
	if activated and use_transition and save_operation_depth == 0:
		var policy_data := SaveProfile.policy(campaign)
		if bool(policy_data.get("autosave_on_travel", true)):
			request_autosave("Travelled to %s" % str(map_data.get("display_name", map_id)))
	return activated


func shift_to_next_era() -> void:
	var before := current_era_id
	super.shift_to_next_era()
	if current_era_id != before and save_operation_depth == 0:
		var policy_data := SaveProfile.policy(campaign)
		if bool(policy_data.get("autosave_on_travel", true)):
			request_autosave("Shifted to %s" % str(current_era().get("display_name", current_era_id)))


func update_game(delta: float) -> void:
	save_notice_timer = maxf(0.0, save_notice_timer - delta)
	if save_notice_timer <= 0.0:
		save_notice = ""
	if flow == Flow.GAME and not save_overlay_open:
		play_time_seconds += delta
	if flow == Flow.GAME and save_overlay_open:
		update_save_overlay()
		return
	if can_open_save_overlay() and Input.is_action_just_pressed("save_profiles"):
		open_save_overlay()
		return
	super.update_game(delta)
	if save_operation_depth == 0:
		var fingerprint := durable_progress_fingerprint()
		if fingerprint != last_durable_fingerprint:
			last_durable_fingerprint = fingerprint
			if bool(SaveProfile.policy(campaign).get("autosave_on_progress", true)):
				request_autosave("Progress updated")
	if can_flush_autosave():
		flush_pending_autosave()


func can_open_save_overlay() -> bool:
	if flow != Flow.GAME or save_overlay_open or inventory_open or story_journal_open:
		return false
	if not active_conversation_id.is_empty() or not dialogue.is_empty() or transition_lock > 0.45:
		return false
	if player_health <= 0:
		return false
	var policy_data := SaveProfile.policy(campaign)
	return bool(policy_data.get("allow_manual_save_in_combat", false)) or not combat_is_active()


func combat_is_active() -> bool:
	for value in runtime_entities:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = value
		if not bool(entity.get("active", true)):
			continue
		var mode := str(entity.get("mode", "idle"))
		if mode in ["chase", "windup", "staggered"]:
			return true
	return false


func open_save_overlay() -> void:
	save_overlay_open = true
	save_overlay_mode = 0
	save_slot_index = 0
	refresh_save_slot_cache()
	set_save_notice("Choose a slot.", 1.0)


func close_save_overlay() -> void:
	save_overlay_open = false
	save_notice = ""
	save_notice_timer = 0.0


func update_save_overlay() -> void:
	if Input.is_action_just_pressed("save_profiles") or Input.is_action_just_pressed("ui_cancel"):
		close_save_overlay()
		return
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right"):
		save_overlay_mode = 1 - save_overlay_mode
		save_slot_index = 0
		set_save_notice("LOAD" if save_overlay_mode == 1 else "SAVE", 0.8)
		return
	var slots := SaveProfile.all_slot_ids(campaign)
	if slots.is_empty():
		return
	if Input.is_action_just_pressed("move_up"):
		save_slot_index = posmod(save_slot_index - 1, slots.size())
	elif Input.is_action_just_pressed("move_down"):
		save_slot_index = posmod(save_slot_index + 1, slots.size())
	if confirm() or Input.is_action_just_pressed("attack"):
		save_slot_index = clampi(save_slot_index, 0, slots.size() - 1)
		var slot_id := str(slots[save_slot_index])
		if save_overlay_mode == 0:
			if slot_id == SaveProfile.AUTOSAVE_SLOT:
				set_save_notice("Autosave is managed by the journey.")
			else:
				save_current_profile(slot_id, "Manual save")
		else:
			load_profile_from_slot(str(campaign.get("id", "")), slot_id)


func save_current_profile(slot_id: String, reason: String) -> bool:
	if save_operation_depth > 0:
		return false
	var profile := capture_save_profile(slot_id, reason)
	var validation: Dictionary = SaveValidator.validate_profile(profile, campaign_path)
	if not bool(validation.get("ok", false)):
		set_save_notice("Save validation failed: %s" % format_errors(validation.get("errors", [])), 2.4)
		return false
	var result: Dictionary = SaveProfileStore.write_profile(profile)
	if not bool(result.get("ok", false)):
		set_save_notice("Save failed: %s" % format_errors(result.get("errors", [])), 2.4)
		return false
	current_save_slot = slot_id
	pending_autosave_reason = ""
	last_durable_fingerprint = durable_progress_fingerprint()
	refresh_save_slot_cache()
	refresh_continue_profile()
	set_save_notice("%s SAVED" % SaveProfile.slot_label(slot_id))
	return true


func capture_save_profile(slot_id: String, reason: String = "Manual save") -> Dictionary:
	var era_data: Dictionary = current_era()
	var active_ids := SaveStoryModel.active_quest_ids(quest_progress, quest_definitions)
	var completed_ids := SaveStoryModel.completed_quest_ids(quest_progress, quest_definitions)
	var metadata := {
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"play_time_seconds": snappedf(play_time_seconds, 0.001),
		"reason": reason,
		"map_id": str(map_data.get("id", "")),
		"map_name": str(map_data.get("display_name", map_data.get("id", ""))),
		"era_id": current_era_id,
		"era_name": str(era_data.get("display_name", current_era_id)),
		"active_quest_count": active_ids.size(),
		"completed_quest_count": completed_ids.size()
	}
	var recipe_ids: Array[String] = []
	for recipe_key in unlocked_recipes.keys():
		if bool(unlocked_recipes.get(recipe_key, false)):
			recipe_ids.append(str(recipe_key))
	recipe_ids.sort()
	var command := companion_command
	if not SaveProfile.ALLOWED_COMPANION_COMMANDS.has(command):
		command = "follow"
	var payload := {
		"map_id": str(map_data.get("id", "")),
		"era_id": current_era_id,
		"player_position": SaveRepository.vector_to_data(player),
		"companion_position": SaveRepository.vector_to_data(companion),
		"facing": SaveRepository.vector_to_data(facing),
		"player_health": player_health,
		"companion_health": companion_health,
		"clock_shards": clock_shards,
		"inventory": inventory.duplicate(true),
		"unlocked_recipes": recipe_ids,
		"session_state": session_state.duplicate(true),
		"quest_progress": quest_progress.duplicate(true),
		"companion_command": command,
		"companion_hold_position": SaveRepository.vector_to_data(companion_hold_position)
	}
	return SaveProfile.build_profile(str(campaign.get("id", "")), slot_id, metadata, payload)


func load_profile_from_slot(campaign_id: String, slot_id: String) -> bool:
	var result: Dictionary = SaveProfileStore.read_profile(campaign_id, slot_id)
	if not bool(result.get("ok", false)):
		set_save_notice("Load failed: %s" % format_errors(result.get("errors", [])), 2.4)
		return false
	var profile: Dictionary = result.get("profile", {})
	var path := resolve_campaign_path(str(profile.get("campaign_id", "")))
	if path.is_empty():
		set_save_notice("The saved campaign is not installed.", 2.0)
		return false
	var loaded := apply_save_profile(profile, path)
	if loaded and bool(result.get("migrated", false)):
		SaveProfileStore.rewrite_migrated_profile(result)
	return loaded


func apply_save_profile(profile: Dictionary, target_campaign_path: String) -> bool:
	var validation: Dictionary = SaveValidator.validate_profile(profile, target_campaign_path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		set_save_notice("Profile rejected: %s" % load_error, 2.6)
		return false
	var payload: Dictionary = profile.get("payload", {})
	save_operation_depth += 1
	var loaded: bool = super.load_campaign(target_campaign_path)
	if not loaded:
		save_operation_depth -= 1
		return false

	inventory = (payload.get("inventory", {}) as Dictionary).duplicate(true)
	unlocked_recipes = {}
	var recipe_value: Variant = payload.get("unlocked_recipes", [])
	if typeof(recipe_value) == TYPE_ARRAY:
		for recipe_id in recipe_value:
			unlocked_recipes[str(recipe_id)] = true
	session_state = (payload.get("session_state", {}) as Dictionary).duplicate(true)
	quest_progress = (payload.get("quest_progress", {}) as Dictionary).duplicate(true)
	clock_shards = int(payload.get("clock_shards", 0))
	player_health = int(payload.get("player_health", actor_health("player", 32)))
	companion_health = int(payload.get("companion_health", actor_health("companion", 24)))

	var map_id := str(payload.get("map_id", campaign.get("start_map", "")))
	var era_id := str(payload.get("era_id", campaign.get("start_era", "")))
	if not super.activate_map(map_id, "", era_id, false):
		save_operation_depth -= 1
		set_save_notice("Saved map could not be activated.", 2.0)
		return false
	player = SaveRepository.data_to_vector(payload.get("player_position"), player)
	companion = SaveRepository.data_to_vector(payload.get("companion_position"), companion)
	facing = SaveRepository.data_to_vector(payload.get("facing"), Vector2.DOWN)
	if facing.length_squared() <= 0.0001:
		facing = Vector2.DOWN
	else:
		facing = facing.normalized()
	player = recover_if_blocked(player, player, PLAYER_RADIUS)
	companion = recover_if_blocked(companion, companion, COMPANION_RADIUS)
	player = recover_from_entity_collision(player, PLAYER_RADIUS)
	companion = recover_from_entity_collision(companion, COMPANION_RADIUS)
	companion_command = str(payload.get("companion_command", "follow"))
	if not SaveProfile.ALLOWED_COMPANION_COMMANDS.has(companion_command):
		companion_command = "follow"
	companion_hold_position = SaveRepository.data_to_vector(payload.get("companion_hold_position"), companion)
	companion_hold_position = SaveMapModel.nearest_recovery_point(map_data, companion_hold_position, current_era_id, companion)
	companion_seek_target = {}
	sync_runtime_entities(false)
	evaluate_story_progress()
	finish_conversation(false)
	inventory_open = false
	story_journal_open = false
	save_overlay_open = false
	current_save_slot = str(profile.get("slot_id", ""))
	var metadata: Dictionary = profile.get("metadata", {})
	play_time_seconds = maxf(0.0, float(metadata.get("play_time_seconds", 0.0)))
	pending_autosave_reason = ""
	last_durable_fingerprint = durable_progress_fingerprint()
	save_operation_depth -= 1
	change_flow(Flow.GAME)
	refresh_save_slot_cache()
	refresh_continue_profile()
	set_save_notice("%s LOADED" % SaveProfile.slot_label(current_save_slot))
	return true


func resolve_campaign_path(campaign_id: String) -> String:
	for value in SaveRepository.scan_playable_campaigns():
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		if str(record.get("id", "")) == campaign_id:
			return str(record.get("path", ""))
	return ""


func request_autosave(reason: String) -> void:
	if save_operation_depth > 0:
		return
	var policy_data := SaveProfile.policy(campaign)
	if not bool(policy_data.get("autosave_enabled", true)):
		return
	pending_autosave_reason = reason


func can_flush_autosave() -> bool:
	if pending_autosave_reason.is_empty() or save_operation_depth > 0:
		return false
	if flow != Flow.GAME or save_overlay_open or inventory_open or story_journal_open:
		return false
	if not active_conversation_id.is_empty() or not dialogue.is_empty() or transition_lock > 0.0:
		return false
	return player_health > 0 and not combat_is_active()


func flush_pending_autosave() -> void:
	var reason := pending_autosave_reason
	pending_autosave_reason = ""
	if not save_current_profile(SaveProfile.AUTOSAVE_SLOT, reason):
		pending_autosave_reason = reason


func durable_progress_fingerprint() -> String:
	var recipe_ids: Array[String] = []
	for recipe_key in unlocked_recipes.keys():
		if bool(unlocked_recipes.get(recipe_key, false)):
			recipe_ids.append(str(recipe_key))
	recipe_ids.sort()
	return SaveProfile.canonical_json({
		"map_id": str(map_data.get("id", "")),
		"era_id": current_era_id,
		"inventory": inventory,
		"unlocked_recipes": recipe_ids,
		"session_state": session_state,
		"quest_progress": quest_progress,
		"clock_shards": clock_shards
	})


func refresh_save_slot_cache() -> void:
	save_slot_cache = {}
	var campaign_id := str(campaign.get("id", ""))
	if campaign_id.is_empty():
		return
	for slot_id in SaveProfile.all_slot_ids(campaign):
		var result: Dictionary = SaveProfileStore.read_profile(campaign_id, slot_id)
		if bool(result.get("ok", false)):
			var profile: Dictionary = result.get("profile", {})
			save_slot_cache[slot_id] = {
				"profile": profile,
				"summary": SaveProfile.profile_summary(profile),
				"migrated": bool(result.get("migrated", false)),
				"recovered_from_backup": bool(result.get("recovered_from_backup", false))
			}


func refresh_continue_profile() -> void:
	var result: Dictionary = SaveProfileStore.latest_profile()
	if bool(result.get("ok", false)):
		continue_profile = result.get("profile", {})
		continue_profile_path = str(result.get("path", ""))
	else:
		continue_profile = {}
		continue_profile_path = ""


func set_save_notice(message: String, duration: float = SAVE_NOTICE_DURATION) -> void:
	save_notice = message
	save_notice_timer = duration


func draw_title() -> void:
	super.draw_title()
	if not continue_profile.is_empty():
		var summary := SaveProfile.profile_summary(continue_profile)
		var text := "%s  •  %s / %s  •  %s" % [
			SaveProfile.slot_label(str(summary.get("slot_id", ""))),
			str(summary.get("map_id", "")).replace("_", " ").capitalize(),
			str(summary.get("era_id", "")).replace("_", " ").capitalize(),
			format_play_time(float(summary.get("play_time_seconds", 0.0)))
		]
		draw_centered(text, 302, 9, Color("7f939b"))
	else:
		draw_centered("NO SAVE PROFILE YET", 302, 9, Color("59666d"))
	if not save_notice.is_empty():
		draw_centered(save_notice, 319, 9, Color("d9b979"))


func draw_game() -> void:
	super.draw_game()
	if save_overlay_open:
		draw_save_overlay()


func draw_hud(era_data: Dictionary) -> void:
	super.draw_hud(era_data)
	if not save_notice.is_empty() and not save_overlay_open and dialogue.is_empty() and active_conversation_id.is_empty():
		draw_rect(Rect2(206, 126, 228, 24), Color(0.03, 0.04, 0.05, 0.88))
		draw_string(ThemeDB.fallback_font, Vector2(216, 142), save_notice, HORIZONTAL_ALIGNMENT_CENTER, 208, 9, Color("f0d99a"))


func draw_save_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.01, 0.015, 0.02, 0.94))
	draw_rect(Rect2(40, 26, 560, 308), Color("111820"))
	draw_rect(Rect2(40, 26, 560, 308), Color("75694d"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(58, 55), "SAVE PROFILES", HORIZONTAL_ALIGNMENT_LEFT, 240, 21, Color("f0dfad"))
	draw_string(ThemeDB.fallback_font, Vector2(398, 52), "SAVE" if save_overlay_mode == 0 else "LOAD", HORIZONTAL_ALIGNMENT_LEFT, 150, 13, Color("e7c66b"))
	var slots := SaveProfile.all_slot_ids(campaign)
	if slots.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(62, 112), "This campaign exposes no save slots.", HORIZONTAL_ALIGNMENT_LEFT, 500, 12, Color("87949b"))
		return
	save_slot_index = clampi(save_slot_index, 0, slots.size() - 1)
	var visible_count := mini(SAVE_SLOT_ROWS, slots.size())
	var start_index := clampi(save_slot_index - 2, 0, maxi(0, slots.size() - visible_count))
	for row in range(visible_count):
		var index := start_index + row
		var slot_id := str(slots[index])
		var active := index == save_slot_index
		var y := 98 + row * 38
		if active:
			draw_rect(Rect2(54, y - 20, 256, 32), Color("26323a"))
		draw_string(ThemeDB.fallback_font, Vector2(64, y), "◆" if active else "", HORIZONTAL_ALIGNMENT_LEFT, 18, 10, Color("e7c66b"))
		draw_string(ThemeDB.fallback_font, Vector2(84, y), SaveProfile.slot_label(slot_id), HORIZONTAL_ALIGNMENT_LEFT, 96, 12, Color("fff2c9") if active else Color("a7b0b3"))
		if save_slot_cache.has(slot_id):
			var record: Dictionary = save_slot_cache.get(slot_id, {})
			var summary: Dictionary = record.get("summary", {})
			draw_string(ThemeDB.fallback_font, Vector2(170, y), "%s / %s" % [str(summary.get("map_id", "")).replace("_", " ").capitalize(), str(summary.get("era_id", "")).replace("_", " ").capitalize()], HORIZONTAL_ALIGNMENT_LEFT, 130, 9, Color("b6b7ab"))
			draw_string(ThemeDB.fallback_font, Vector2(170, y + 11), format_play_time(float(summary.get("play_time_seconds", 0.0))), HORIZONTAL_ALIGNMENT_LEFT, 120, 8, Color("78858c"))
		else:
			draw_string(ThemeDB.fallback_font, Vector2(170, y), "EMPTY", HORIZONTAL_ALIGNMENT_LEFT, 100, 9, Color("68747e"))
	var selected_slot := str(slots[save_slot_index])
	draw_rect(Rect2(328, 78, 248, 198), Color("0c1218"))
	if save_slot_cache.has(selected_slot):
		var record: Dictionary = save_slot_cache.get(selected_slot, {})
		var summary: Dictionary = record.get("summary", {})
		draw_string(ThemeDB.fallback_font, Vector2(346, 104), str(summary.get("map_id", "")).replace("_", " ").to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 210, 13, Color("f1d483"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 125), str(summary.get("era_id", "")).replace("_", " ").to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 210, 10, Color("8fa9a5"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 153), "PLAY TIME  %s" % format_play_time(float(summary.get("play_time_seconds", 0.0))), HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color("c8c5b8"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 171), "HEALTH  %d" % int(summary.get("player_health", 0)), HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color("c8c5b8"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 189), "SHARDS  %d" % int(summary.get("clock_shards", 0)), HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color("c8c5b8"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 207), "QUESTS  %d ACTIVE / %d DONE" % [int(summary.get("active_quests", 0)), int(summary.get("completed_quests", 0))], HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color("c8c5b8"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 225), "STATE KEYS  %d" % int(summary.get("state_keys", 0)), HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color("c8c5b8"))
		draw_string(ThemeDB.fallback_font, Vector2(346, 251), str(summary.get("reason", "")), HORIZONTAL_ALIGNMENT_LEFT, 210, 8, Color("7f8a90"))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(346, 152), "EMPTY SLOT", HORIZONTAL_ALIGNMENT_CENTER, 210, 14, Color("68747e"))
	if not save_notice.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(58, 296), save_notice, HORIZONTAL_ALIGNMENT_LEFT, 520, 9, Color("e7cf8c"))
	draw_string(ThemeDB.fallback_font, Vector2(58, 318), "K / L3 CLOSE   LEFT / RIGHT MODE   UP / DOWN SLOT   CONFIRM", HORIZONTAL_ALIGNMENT_LEFT, 520, 8, Color("68747e"))


func format_play_time(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var remaining := total % 60
	return "%02d:%02d:%02d" % [hours, minutes, remaining]
