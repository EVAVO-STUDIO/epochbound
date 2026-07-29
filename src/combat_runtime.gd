extends "res://src/game_runtime.gd"

var defeat_rewind_pending := false


func update_game(delta: float) -> void:
	super.update_game(delta)
	if defeat_rewind_pending:
		defeat_rewind_pending = false
		rewind_after_defeat()


func damage_actor(actor_id: String, amount: int, attacker: Dictionary) -> void:
	var attacker_name := String(attacker.get("display_name", "Enemy"))
	if actor_id == "player":
		if player_hurt_lock > 0.0:
			return
		player_hurt_lock = 0.55
		player_health -= amount
		set_combat_text("%s hits %s for %d." % [attacker_name, player_name().capitalize(), amount])
		if player_health <= 0:
			defeat_rewind_pending = true
		return
	if companion_hurt_lock > 0.0:
		return
	companion_hurt_lock = 0.65
	companion_health -= amount
	set_combat_text("%s wounds %s for %d." % [attacker_name, companion_name().capitalize(), amount])
	if companion_health <= 0:
		companion_health = maxi(1, int(actor_health("companion", 24) / 2.0))
		var fallback := player - facing * COMPANION_FOLLOW_DISTANCE
		companion = MapModel.nearest_recovery_point(map_data, player, current_era_id, fallback)
		set_combat_text("%s retreats, then finds the trail again." % companion_name().capitalize(), 1.4)
