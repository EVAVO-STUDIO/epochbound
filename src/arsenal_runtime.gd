extends "res://src/merchant_runtime.gd"

const ArsenalCatalog = preload("res://src/content/arsenal_catalog.gd")
const ArsenalValidator = preload("res://src/content/arsenal_validator.gd")
const ArsenalItemCatalog = preload("res://src/content/item_catalog.gd")
const ArsenalInventoryModel = preload("res://src/game/inventory_model.gd")
const ProjectileModel = preload("res://src/game/projectile_model.gd")
const ArsenalMapModel = preload("res://src/content/map_model.gd")
const ArsenalSaveProfile = preload("res://src/content/save_profile.gd")
const ArsenalSaveStore = preload("res://src/content/save_profile_store.gd")

const PROJECTILE_WORLD_STEP := 4.0
const RELOAD_NOTICE_DURATION := 1.1

var projectiles: Array = []
var loaded_ammo: Dictionary = {}
var reload_weapon_id := ""
var reload_timer := 0.0
var reload_duration := 0.0


func load_campaign(path: String) -> bool:
	var validation := ArsenalValidator.validate_campaign_path(path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		push_error("Arsenal validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	clear_arsenal_state()
	var loaded := super.load_campaign(path)
	if not loaded:
		return false
	reset_arsenal_state()
	return true


func load_fallback_campaign() -> void:
	clear_arsenal_state()
	super.load_fallback_campaign()
	reset_arsenal_state()


func clear_arsenal_state() -> void:
	projectiles.clear()
	loaded_ammo.clear()
	reload_weapon_id = ""
	reload_timer = 0.0
	reload_duration = 0.0


func reset_arsenal_state() -> void:
	projectiles.clear()
	loaded_ammo = ArsenalCatalog.sanitize_loaded_ammo({}, inventory, item_definitions)
	cancel_reload(false)
	last_durable_fingerprint = durable_progress_fingerprint()


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	projectiles.clear()
	cancel_reload(false)
	return super.activate_map(map_id, entry_id, requested_era, use_transition)


func shift_to_next_era() -> void:
	projectiles.clear()
	cancel_reload(false)
	super.shift_to_next_era()


func update_game(delta: float) -> void:
	if can_issue_reload_input() and Input.is_action_just_pressed("reload_weapon"):
		start_reload()
	super.update_game(delta)
	if flow != Flow.GAME or arsenal_simulation_paused():
		return
	update_reload(delta)
	update_projectiles(delta)


func can_issue_reload_input() -> bool:
	return flow == Flow.GAME and not arsenal_simulation_paused() and transition_lock <= 0.45


func arsenal_simulation_paused() -> bool:
	return (
		merchant_open
		or inventory_open
		or story_journal_open
		or save_overlay_open
		or not active_conversation_id.is_empty()
		or not dialogue.is_empty()
	)


func equipped_weapon_id() -> String:
	return str(equipped_items.get("weapon", ""))


func equipped_weapon_data() -> Dictionary:
	return ArsenalItemCatalog.item(item_definitions, equipped_weapon_id())


func equipped_ranged_weapon_data() -> Dictionary:
	var weapon_data := equipped_weapon_data()
	return weapon_data if ArsenalCatalog.is_ranged_weapon(weapon_data) else {}


func reserve_ammunition(weapon_data: Dictionary) -> int:
	var ammo_item_id := ArsenalCatalog.weapon_ammunition_id(weapon_data)
	return ArsenalInventoryModel.count(inventory, ammo_item_id)


func perform_player_attack() -> void:
	var weapon_data := equipped_ranged_weapon_data()
	if weapon_data.is_empty():
		super.perform_player_attack()
		return
	var weapon_id := equipped_weapon_id()
	if reload_timer > 0.0:
		set_combat_text("Reloading %s." % ArsenalItemCatalog.item_name(weapon_data, weapon_id), 0.55)
		return
	var rounds := ArsenalCatalog.loaded_rounds(loaded_ammo, weapon_id)
	if rounds <= 0:
		player_attack_lock = 0.15
		if reserve_ammunition(weapon_data) > 0:
			start_reload()
		else:
			set_combat_text("No %s remain." % ammunition_name(weapon_data), 0.9)
		return
	loaded_ammo[weapon_id] = rounds - 1
	player_attack_lock = ArsenalCatalog.fire_cooldown(weapon_data)
	player_attack_timer = 0.12
	spawn_player_projectile(weapon_id, weapon_data)
	if int(loaded_ammo.get(weapon_id, 0)) <= 0 and reserve_ammunition(weapon_data) > 0:
		set_combat_text("Magazine empty. Press reload.", 0.8)
	last_durable_fingerprint = durable_progress_fingerprint()


func ammunition_name(weapon_data: Dictionary) -> String:
	var ammo_item_id := ArsenalCatalog.weapon_ammunition_id(weapon_data)
	var ammo_data := ArsenalItemCatalog.item(item_definitions, ammo_item_id)
	return ArsenalItemCatalog.item_name(ammo_data, ammo_item_id)


func start_reload() -> bool:
	var weapon_id := equipped_weapon_id()
	var weapon_data := equipped_ranged_weapon_data()
	if weapon_id.is_empty() or weapon_data.is_empty():
		set_combat_text("The equipped weapon does not use ammunition.", 0.75)
		return false
	if reload_timer > 0.0:
		return false
	var current := ArsenalCatalog.loaded_rounds(loaded_ammo, weapon_id)
	var capacity := ArsenalCatalog.magazine_size(weapon_data)
	if current >= capacity:
		set_combat_text("Magazine already full.", 0.7)
		return false
	if reserve_ammunition(weapon_data) <= 0:
		set_combat_text("No %s remain." % ammunition_name(weapon_data), 0.9)
		return false
	reload_weapon_id = weapon_id
	reload_duration = ArsenalCatalog.reload_time(weapon_data)
	reload_timer = reload_duration
	player_attack_lock = maxf(player_attack_lock, reload_duration)
	set_combat_text("Reloading %s." % ArsenalItemCatalog.item_name(weapon_data, weapon_id), RELOAD_NOTICE_DURATION)
	return true


func update_reload(delta: float) -> void:
	if reload_timer <= 0.0:
		return
	if equipped_weapon_id() != reload_weapon_id:
		cancel_reload(true)
		return
	reload_timer = maxf(0.0, reload_timer - delta)
	if reload_timer <= 0.0:
		finish_reload()


func finish_reload() -> bool:
	var weapon_id := reload_weapon_id
	var weapon_data := ArsenalItemCatalog.item(item_definitions, weapon_id)
	if weapon_id.is_empty() or not ArsenalCatalog.is_ranged_weapon(weapon_data):
		cancel_reload(false)
		return false
	var ammo_item_id := ArsenalCatalog.weapon_ammunition_id(weapon_data)
	var current := ArsenalCatalog.loaded_rounds(loaded_ammo, weapon_id)
	var missing := maxi(0, ArsenalCatalog.magazine_size(weapon_data) - current)
	var available := ArsenalInventoryModel.count(inventory, ammo_item_id)
	var quantity := mini(missing, available)
	if quantity <= 0 or not ArsenalInventoryModel.remove_item(inventory, ammo_item_id, quantity):
		cancel_reload(false)
		set_combat_text("Reload failed without consuming ammunition.", 0.9)
		return false
	loaded_ammo[weapon_id] = current + quantity
	cancel_reload(false)
	set_combat_text("Loaded %d %s." % [quantity, ammunition_name(weapon_data)], 0.9)
	evaluate_story_progress()
	last_durable_fingerprint = durable_progress_fingerprint()
	return true


func cancel_reload(show_notice: bool = false) -> void:
	var was_reloading := reload_timer > 0.0
	reload_weapon_id = ""
	reload_timer = 0.0
	reload_duration = 0.0
	if show_notice and was_reloading:
		set_combat_text("Reload cancelled; ammunition preserved.", 0.8)


func spawn_player_projectile(weapon_id: String, weapon_data: Dictionary) -> void:
	var ammo_item_id := ArsenalCatalog.weapon_ammunition_id(weapon_data)
	var ammo_data := ArsenalItemCatalog.item(item_definitions, ammo_item_id)
	var direction := facing.normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector2.DOWN
	var damage := (
		player_attack_damage_value()
		+ ArsenalCatalog.weapon_damage_bonus(weapon_data)
		+ ArsenalCatalog.ammunition_damage_bonus(ammo_data)
	)
	var knockback := ArsenalCatalog.weapon_knockback(weapon_data) + ArsenalCatalog.ammunition_knockback_bonus(ammo_data)
	var origin := player + direction * ArsenalCatalog.muzzle_offset(weapon_data)
	projectiles.append(ProjectileModel.create_projectile(
		"player",
		weapon_id,
		player_name(),
		origin,
		direction,
		ArsenalCatalog.projectile_speed(weapon_data),
		ArsenalCatalog.projectile_range(weapon_data),
		ArsenalCatalog.projectile_radius(weapon_data),
		damage,
		knockback,
		ArsenalCatalog.weapon_projectile_color(weapon_data, ammo_data),
		"enemy"
	))


func damage_actor(actor_id: String, amount: int, attacker: Dictionary) -> void:
	if ArsenalCatalog.is_ranged_enemy(attacker) and not bool(attacker.get("_projectile_resolved", false)):
		spawn_enemy_projectile(actor_id, amount, attacker)
		return
	super.damage_actor(actor_id, amount, attacker)


func spawn_enemy_projectile(actor_id: String, amount: int, attacker: Dictionary) -> void:
	var origin_value: Variant = attacker.get("_position", Vector2.ZERO)
	var origin: Vector2 = origin_value if origin_value is Vector2 else Vector2.ZERO
	var target_position := player if actor_id == "player" else companion
	var direction := origin.direction_to(target_position)
	if direction.length_squared() <= 0.001:
		direction = Vector2.DOWN
	projectiles.append(ProjectileModel.create_projectile(
		"enemy",
		str(attacker.get("id", attacker.get("display_name", "enemy"))),
		str(attacker.get("display_name", "Enemy")),
		origin + direction * 10.0,
		direction,
		ArsenalCatalog.enemy_projectile_speed(attacker),
		ArsenalCatalog.enemy_projectile_range(attacker),
		ArsenalCatalog.enemy_projectile_radius(attacker),
		amount,
		ArsenalCatalog.enemy_projectile_knockback(attacker),
		ArsenalCatalog.enemy_projectile_color(attacker),
		actor_id
	))


func update_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		if typeof(projectiles[index]) != TYPE_DICTIONARY:
			projectiles.remove_at(index)
			continue
		var projectile: Dictionary = ProjectileModel.advance(projectiles[index], delta)
		if projectile_hits_map(projectile):
			projectiles.remove_at(index)
			continue
		var obstacle_index := ProjectileModel.first_solid_obstacle_hit(projectile, runtime_entities)
		if obstacle_index >= 0:
			projectiles.remove_at(index)
			continue
		var target_kind := str(projectile.get("target_kind", "enemy"))
		if target_kind == "enemy":
			var hit_index := ProjectileModel.first_enemy_hit(projectile, runtime_entities)
			if hit_index >= 0:
				damage_entity(hit_index, int(projectile.get("damage", 1)), str(projectile.get("source_name", player_name())))
				projectiles.remove_at(index)
				continue
		elif target_kind == "player":
			if ProjectileModel.hits_actor(projectile, player, PLAYER_RADIUS):
				apply_enemy_projectile_hit("player", projectile)
				projectiles.remove_at(index)
				continue
		elif target_kind == "companion":
			if ProjectileModel.hits_actor(projectile, companion, COMPANION_RADIUS):
				apply_enemy_projectile_hit("companion", projectile)
				projectiles.remove_at(index)
				continue
		if not bool(projectile.get("active", true)):
			projectiles.remove_at(index)
		else:
			projectiles[index] = projectile


func projectile_hits_map(projectile: Dictionary) -> bool:
	var start_value: Variant = projectile.get("previous_position", Vector2.ZERO)
	var finish_value: Variant = projectile.get("position", start_value)
	var start: Vector2 = start_value if start_value is Vector2 else Vector2.ZERO
	var finish: Vector2 = finish_value if finish_value is Vector2 else start
	var radius := maxf(1.0, float(projectile.get("radius", 1.0)))
	var distance := start.distance_to(finish)
	var steps := maxi(1, int(ceil(distance / maxf(PROJECTILE_WORLD_STEP, radius))))
	for step in range(1, steps + 1):
		var point := start.lerp(finish, float(step) / float(steps))
		if ArsenalMapModel.is_position_blocked(map_data, point, current_era_id, radius):
			return true
	return false


func apply_enemy_projectile_hit(actor_id: String, projectile: Dictionary) -> void:
	var context := {
		"display_name": str(projectile.get("source_name", "Enemy")),
		"_position": projectile.get("previous_position", Vector2.ZERO),
		"contact_knockback": float(projectile.get("knockback_distance", 0.0)),
		"_projectile_resolved": true
	}
	super.damage_actor(actor_id, int(projectile.get("damage", 1)), context)


func cycle_equipment_slot(slot_id: String) -> bool:
	var previous_weapon := equipped_weapon_id()
	var changed := super.cycle_equipment_slot(slot_id)
	if changed:
		if previous_weapon != equipped_weapon_id():
			cancel_reload(true)
		sanitize_loaded_ammo_state()
	return changed


func equip_specific_item(item_id: String) -> bool:
	var previous_weapon := equipped_weapon_id()
	var changed := super.equip_specific_item(item_id)
	if changed:
		if previous_weapon != equipped_weapon_id():
			cancel_reload(true)
		sanitize_loaded_ammo_state()
	return changed


func sanitize_loadout_after_inventory_change(before_max: int = -1) -> void:
	super.sanitize_loadout_after_inventory_change(before_max)
	sanitize_loaded_ammo_state()


func sanitize_loaded_ammo_state() -> void:
	loaded_ammo = ArsenalCatalog.sanitize_loaded_ammo(loaded_ammo, inventory, item_definitions)
	if not reload_weapon_id.is_empty() and reload_weapon_id != equipped_weapon_id():
		cancel_reload(false)


func can_open_save_overlay() -> bool:
	return reload_timer <= 0.0 and projectiles.is_empty() and super.can_open_save_overlay()


func can_flush_autosave() -> bool:
	return reload_timer <= 0.0 and projectiles.is_empty() and super.can_flush_autosave()


func draw_game() -> void:
	super.draw_game()
	if not arsenal_simulation_paused():
		draw_projectiles()


func draw_projectiles() -> void:
	for value in projectiles:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var projectile: Dictionary = value
		var position_value: Variant = projectile.get("position", Vector2.ZERO)
		var previous_value: Variant = projectile.get("previous_position", position_value)
		var position: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
		var previous: Vector2 = previous_value if previous_value is Vector2 else position
		var color_value: Variant = projectile.get("color", Color.WHITE)
		var color: Color = color_value if color_value is Color else Color.WHITE
		draw_line(previous, position, color.darkened(0.18), 2.0)
		draw_circle(position, float(projectile.get("radius", 3.0)), color)


func draw_hud(era_data: Dictionary) -> void:
	super.draw_hud(era_data)
	var weapon_id := equipped_weapon_id()
	var weapon_data := equipped_ranged_weapon_data()
	if weapon_id.is_empty() or weapon_data.is_empty():
		return
	var ammo_item_id := ArsenalCatalog.weapon_ammunition_id(weapon_data)
	var loaded := ArsenalCatalog.loaded_rounds(loaded_ammo, weapon_id)
	var reserve := ArsenalInventoryModel.count(inventory, ammo_item_id)
	draw_rect(Rect2(410, 9, 206, 24), Color(0.03, 0.04, 0.05, 0.86))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(420, 25),
		"AMMO %d / %d   G / L1 RELOAD" % [loaded, reserve],
		HORIZONTAL_ALIGNMENT_LEFT,
		188,
		9,
		Color("e5cf8c")
	)
	if reload_timer > 0.0 and reload_duration > 0.0:
		var progress := 1.0 - clampf(reload_timer / reload_duration, 0.0, 1.0)
		draw_rect(Rect2(410, 36, 206, 8), Color(0.03, 0.04, 0.05, 0.86))
		draw_rect(Rect2(412, 38, 202.0 * progress, 4), Color("d9b65c"))


func capture_save_profile(slot_id: String, reason: String = "Manual save") -> Dictionary:
	var profile := super.capture_save_profile(slot_id, reason)
	var payload_value: Variant = profile.get("payload", {})
	if typeof(payload_value) == TYPE_DICTIONARY:
		var payload: Dictionary = payload_value
		payload["loaded_ammo"] = ArsenalCatalog.sanitize_loaded_ammo(loaded_ammo, inventory, item_definitions)
		profile["payload"] = payload
		ArsenalSaveProfile.refresh_checksum(profile)
	return profile


func save_current_profile(slot_id: String, reason: String) -> bool:
	if save_operation_depth > 0:
		return false
	var profile := capture_save_profile(slot_id, reason)
	var validation := ArsenalValidator.validate_profile(profile, campaign_path)
	if not bool(validation.get("ok", false)):
		set_save_notice("Save validation failed: %s" % format_errors(validation.get("errors", [])), 2.4)
		return false
	var result := ArsenalSaveStore.write_profile(profile)
	if not bool(result.get("ok", false)):
		set_save_notice("Save failed: %s" % format_errors(result.get("errors", [])), 2.4)
		return false
	current_save_slot = slot_id
	pending_autosave_reason = ""
	last_durable_fingerprint = durable_progress_fingerprint()
	refresh_save_slot_cache()
	refresh_continue_profile()
	set_save_notice("%s SAVED" % ArsenalSaveProfile.slot_label(slot_id))
	return true


func apply_save_profile(profile: Dictionary, target_campaign_path: String) -> bool:
	var validation := ArsenalValidator.validate_profile(profile, target_campaign_path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		set_save_notice("Profile rejected: %s" % load_error, 2.6)
		return false
	clear_arsenal_state()
	var loaded := super.apply_save_profile(profile, target_campaign_path)
	if not loaded:
		return false
	var payload: Dictionary = profile.get("payload", {})
	loaded_ammo = ArsenalCatalog.sanitize_loaded_ammo(payload.get("loaded_ammo", {}), inventory, item_definitions)
	projectiles.clear()
	cancel_reload(false)
	last_durable_fingerprint = durable_progress_fingerprint()
	return true


func durable_progress_fingerprint() -> String:
	return ArsenalSaveProfile.canonical_json({
		"base": super.durable_progress_fingerprint(),
		"loaded_ammo": loaded_ammo
	})
