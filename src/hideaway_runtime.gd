extends "res://src/presentation_runtime_base.gd"

const HideawayStewardship = preload("res://src/game/hideaway_stewardship.gd")
const HideawayEncounterModel = preload("res://src/game/encounter_model.gd")

const HIDEAWAY_MAP_ID := "archive_hideaway"
const HIDEAWAY_STATE_KEY := "hideaway:stewardship"
const HIDEAWAY_WARMTH_GUARD_KEY := "hideaway:buff:warmth_guard"
const HIDEAWAY_REPAIR_STRIKE_KEY := "hideaway:buff:repair_strike"
const HIDEAWAY_COMPANION_FOCUS_KEY := "hideaway:buff:companion_focus"
const HIDEAWAY_FACILITY_KIND := "hideaway_facility"
const HIDEAWAY_BONUS_DAMAGE := 2
const HIDEAWAY_WARMTH_REDUCTION := 2


func begin_game() -> void:
	super.begin_game()
	if not session_state.has(HIDEAWAY_STATE_KEY):
		store_hideaway_state(HideawayStewardship.default_state(play_time_seconds))


func activate_map(
	map_id: String,
	entry_id: String = "",
	requested_era: String = "same",
	use_transition: bool = true
) -> bool:
	var previous_map_id := str(map_data.get("id", ""))
	var activated := super.activate_map(map_id, entry_id, requested_era, use_transition)
	if not activated or not use_transition or not hideaway_has_durable_authority():
		return activated
	var next_map_id := str(map_data.get("id", ""))
	if previous_map_id == HIDEAWAY_MAP_ID and next_map_id != HIDEAWAY_MAP_ID:
		var departure := HideawayStewardship.begin_expedition(
			hideaway_state_snapshot(),
			next_map_id,
			play_time_seconds
		)
		if bool(departure.get("accepted", false)):
			store_hideaway_state(departure.get("state", {}))
			apply_hideaway_departure_preparation()
	elif previous_map_id != HIDEAWAY_MAP_ID and next_map_id == HIDEAWAY_MAP_ID:
		var returned := HideawayStewardship.record_return(
			hideaway_state_snapshot(),
			play_time_seconds
		)
		store_hideaway_state(returned.get("state", {}))
		if bool(returned.get("qualified", false)):
			var state := hideaway_state_snapshot()
			dialogue = (
				"The Archive Hideaway settles around you.\n"
				+ "Recovered %d salvage. %d return preparation%s banked."
				% [
					int(returned.get("salvage_awarded", 0)),
					int(state.get("banked_returns", 0)),
					"" if int(state.get("banked_returns", 0)) == 1 else "s",
				]
			)
	return activated


func update_game(delta: float) -> void:
	if (
		flow == Flow.GAME
		and is_in_archive_hideaway()
		and dialogue.is_empty()
		and transition_lock <= 0.45
		and Input.is_action_just_pressed("attack")
	):
		var facility := nearest_hideaway_facility()
		if not facility.is_empty():
			upgrade_hideaway_facility(StringName(str(facility.get("facility_id", ""))))
	super.update_game(delta)


func interact() -> void:
	if is_in_archive_hideaway():
		var facility := nearest_hideaway_facility()
		if not facility.is_empty():
			prepare_hideaway_facility(StringName(str(facility.get("facility_id", ""))))
			return
	super.interact()


func perform_player_attack() -> void:
	var before := enemy_health_snapshot()
	super.perform_player_attack()
	if hideaway_counter(HIDEAWAY_REPAIR_STRIKE_KEY) <= 0:
		return
	var index := first_damaged_enemy(before)
	if index < 0:
		return
	set_hideaway_counter(HIDEAWAY_REPAIR_STRIKE_KEY, 0)
	damage_entity(index, HIDEAWAY_BONUS_DAMAGE, "prepared gear")


func perform_companion_attack() -> void:
	var before := enemy_health_snapshot()
	super.perform_companion_attack()
	if hideaway_counter(HIDEAWAY_COMPANION_FOCUS_KEY) <= 0:
		return
	var index := first_damaged_enemy(before)
	if index < 0:
		return
	set_hideaway_counter(HIDEAWAY_COMPANION_FOCUS_KEY, 0)
	damage_entity(index, HIDEAWAY_BONUS_DAMAGE, "%s's focus" % companion_name().capitalize())


func damage_actor(actor_id: String, amount: int, attacker: Dictionary) -> void:
	if (
		actor_id == "player"
		and amount > 0
		and player_hurt_lock <= 0.0
		and hideaway_counter(HIDEAWAY_WARMTH_GUARD_KEY) > 0
	):
		set_hideaway_counter(HIDEAWAY_WARMTH_GUARD_KEY, 0)
		var reduced := maxi(0, amount - HIDEAWAY_WARMTH_REDUCTION)
		if reduced <= 0:
			player_hurt_lock = 0.35
			set_combat_text("Archive Hearth warmth turns the blow.", 1.1)
			return
		amount = reduced
	super.damage_actor(actor_id, amount, attacker)


func draw_game() -> void:
	super.draw_game()
	if not is_in_archive_hideaway():
		return
	draw_hideaway_facilities()
	draw_hideaway_status()


func hideaway_has_durable_authority() -> bool:
	var online := get_node_or_null("MultiplayerSession")
	return online == null or str(online.get("mode")) != "client"


func hideaway_state_snapshot() -> Dictionary:
	var value: Variant = session_state.get(HIDEAWAY_STATE_KEY)
	if typeof(value) == TYPE_DICTIONARY and HideawayStewardship.validate_state(value).is_empty():
		return (value as Dictionary).duplicate(true)
	var fallback := HideawayStewardship.default_state(play_time_seconds)
	if value != null:
		push_error("Invalid Archive Hideaway state reached runtime; using a bounded in-memory fallback.")
	if hideaway_has_durable_authority():
		session_state[HIDEAWAY_STATE_KEY] = fallback.duplicate(true)
	return fallback


func store_hideaway_state(value: Variant) -> bool:
	if not hideaway_has_durable_authority():
		return false
	var errors := HideawayStewardship.validate_state(value)
	if not errors.is_empty():
		push_error("Archive Hideaway state rejected: %s" % ", ".join(errors))
		return false
	session_state[HIDEAWAY_STATE_KEY] = (value as Dictionary).duplicate(true)
	return true


func upgrade_hideaway_facility(facility_id: StringName) -> Dictionary:
	if not hideaway_has_durable_authority():
		dialogue = "Only the host can change the Archive Hideaway while online."
		return {"accepted": false, "reason": "host_only"}
	var result := HideawayStewardship.upgrade_facility(hideaway_state_snapshot(), facility_id)
	if bool(result.get("accepted", false)):
		store_hideaway_state(result.get("state", {}))
		var state := hideaway_state_snapshot()
		var level := int((state.get("facilities", {}) as Dictionary).get(String(facility_id), 0))
		dialogue = "%s restored to level %d.\n%d salvage remains." % [
			hideaway_facility_name(facility_id),
			level,
			int(state.get("salvage", 0)),
		]
	else:
		dialogue = hideaway_failure_message(str(result.get("reason", "")), facility_id)
	return result


func prepare_hideaway_facility(facility_id: StringName) -> Dictionary:
	if not hideaway_has_durable_authority():
		dialogue = "Only the host can prepare the Archive Hideaway while online."
		return {"accepted": false, "reason": "host_only"}
	var result := HideawayStewardship.prepare_facility(hideaway_state_snapshot(), facility_id)
	if bool(result.get("accepted", false)):
		store_hideaway_state(result.get("state", {}))
		var state := hideaway_state_snapshot()
		dialogue = "%s prepared for the next expedition.\n%d return preparation%s remain." % [
			hideaway_facility_name(facility_id),
			int(state.get("banked_returns", 0)),
			"" if int(state.get("banked_returns", 0)) == 1 else "s",
		]
	else:
		dialogue = hideaway_failure_message(str(result.get("reason", "")), facility_id)
	return result


func apply_hideaway_departure_preparation() -> void:
	var state := hideaway_state_snapshot()
	var applied := PackedStringArray()
	for effect_value in [&"recovery", &"warmth", &"repair", &"companion_focus"]:
		var effect_id: StringName = effect_value
		var prepared: Dictionary = state.get("prepared", {})
		if int(prepared.get(String(effect_id), 0)) <= 0:
			continue
		if effect_id == &"warmth" and hideaway_counter(HIDEAWAY_WARMTH_GUARD_KEY) > 0:
			continue
		if effect_id == &"repair" and hideaway_counter(HIDEAWAY_REPAIR_STRIKE_KEY) > 0:
			continue
		if effect_id == &"companion_focus" and hideaway_counter(HIDEAWAY_COMPANION_FOCUS_KEY) > 0:
			continue
		var consumed := HideawayStewardship.consume_prepared_effect(state, effect_id)
		if not bool(consumed.get("accepted", false)):
			continue
		state = consumed.get("state", state)
		match effect_id:
			&"recovery":
				player_health = mini(actor_health("player", 32), player_health + 8)
				companion_health = mini(actor_health("companion", 24), companion_health + 6)
				applied.append("recovery")
			&"warmth":
				set_hideaway_counter(HIDEAWAY_WARMTH_GUARD_KEY, 1)
				applied.append("warmth")
			&"repair":
				set_hideaway_counter(HIDEAWAY_REPAIR_STRIKE_KEY, 1)
				applied.append("repair")
			&"companion_focus":
				set_hideaway_counter(HIDEAWAY_COMPANION_FOCUS_KEY, 1)
				applied.append("Morrow focus")
	store_hideaway_state(state)
	if not applied.is_empty():
		set_combat_text("Hideaway preparation: %s." % ", ".join(applied), 1.5)


func is_in_archive_hideaway() -> bool:
	return str(map_data.get("id", "")) == HIDEAWAY_MAP_ID


func nearest_hideaway_facility() -> Dictionary:
	if not is_in_archive_hideaway():
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for value in map_data.get("interactions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = value
		if str(interaction.get("kind", "")) != HIDEAWAY_FACILITY_KIND:
			continue
		if not MapModel.available_in_era(interaction, current_era_id):
			continue
		var position := CampaignRepository.data_to_vector(interaction.get("position"))
		var distance := player.distance_to(position)
		if distance <= float(interaction.get("radius", 32.0)) and distance < best_distance:
			best = interaction
			best_distance = distance
	return best


func hideaway_facility_name(facility_id: StringName) -> String:
	match facility_id:
		&"archive_hearth": return "Archive Hearth"
		&"sheltered_coldframe": return "Sheltered Coldframe"
		&"salvage_workbench": return "Salvage Workbench"
		&"morrows_corner": return "Morrow's Corner"
		_: return String(facility_id).replace("_", " ").capitalize()


func hideaway_failure_message(reason: String, facility_id: StringName) -> String:
	match reason:
		"facility_unrestored": return "%s must be restored first.\nATTACK near it to spend salvage." % hideaway_facility_name(facility_id)
		"no_return_opportunity": return "Complete a qualifying expedition before preparing %s." % hideaway_facility_name(facility_id)
		"preparation_full": return "%s already holds its full preparation." % hideaway_facility_name(facility_id)
		"insufficient_salvage": return "Not enough salvage to improve %s." % hideaway_facility_name(facility_id)
		"facility_unavailable": return "%s is already fully restored." % hideaway_facility_name(facility_id)
		_: return "%s cannot be changed right now." % hideaway_facility_name(facility_id)


func hideaway_counter(key: String) -> int:
	return maxi(0, int(session_state.get(key, 0)))


func set_hideaway_counter(key: String, value: int) -> void:
	if hideaway_has_durable_authority():
		session_state[key] = clampi(value, 0, 1)


func enemy_health_snapshot() -> Dictionary:
	var output: Dictionary = {}
	for index in range(runtime_entities.size()):
		if typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		if bool(entity.get("active", true)) and HideawayEncounterModel.kind(entity) == "enemy":
			output[index] = int(entity.get("health", 0))
	return output


func first_damaged_enemy(before: Dictionary) -> int:
	for index_value in before.keys():
		var index := int(index_value)
		if index < 0 or index >= runtime_entities.size() or typeof(runtime_entities[index]) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = runtime_entities[index]
		if int(entity.get("health", 0)) < int(before.get(index_value, 0)):
			return index
	return -1


func draw_hideaway_facilities() -> void:
	var state := hideaway_state_snapshot()
	var facilities: Dictionary = state.get("facilities", {})
	var offset := camera_offset()
	for value in map_data.get("interactions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = value
		if str(interaction.get("kind", "")) != HIDEAWAY_FACILITY_KIND:
			continue
		var facility_id := StringName(str(interaction.get("facility_id", "")))
		var level := int(facilities.get(String(facility_id), 0))
		var position := CampaignRepository.data_to_vector(interaction.get("position")) - offset
		var frame := palette_color("structure", "705b43")
		var accent := palette_color("accent", "d4aa63")
		draw_rect(Rect2(position - Vector2(15, 11), Vector2(30, 22)), Color(frame.r, frame.g, frame.b, 0.85), true)
		draw_rect(Rect2(position - Vector2(15, 11), Vector2(30, 22)), accent if level > 0 else Color("665c50"), false, 2.0)
		if facility_id == &"archive_hearth" and level > 0:
			draw_circle(position + Vector2(0, 2), 5.0 + level, Color("e59a4f"), true)
		elif facility_id == &"sheltered_coldframe" and level > 0:
			draw_line(position + Vector2(-10, 7), position + Vector2(0, -8), accent, 1.0)
			draw_line(position + Vector2(0, -8), position + Vector2(10, 7), accent, 1.0)
		elif facility_id == &"salvage_workbench" and level > 0:
			draw_line(position + Vector2(-10, 0), position + Vector2(10, 0), accent, 2.0)
		elif facility_id == &"morrows_corner" and level > 0:
			draw_circle(position, 6.0 + level, accent, false, 2.0)
		draw_string(
			ThemeDB.fallback_font,
			position + Vector2(-28, -17),
			"L%d" % level,
			HORIZONTAL_ALIGNMENT_LEFT,
			56,
			8,
			Color("ead9b7")
		)


func draw_hideaway_status() -> void:
	var state := hideaway_state_snapshot()
	draw_rect(Rect2(76, 300, 488, 50), Color(0.025, 0.022, 0.018, 0.9), true)
	draw_rect(Rect2(76, 300, 488, 50), Color("a88654"), false, 1.0)
	draw_centered(
		"ARCHIVE HIDEAWAY   SALVAGE %d   RETURNS %d" % [int(state.get("salvage", 0)), int(state.get("banked_returns", 0))],
		319,
		10,
		Color("ead9b7")
	)
	var facility := nearest_hideaway_facility()
	var hint := "RETURN TO THE ROAD WHEN READY"
	if not facility.is_empty():
		var facility_id := StringName(str(facility.get("facility_id", "")))
		var level := int((state.get("facilities", {}) as Dictionary).get(String(facility_id), 0))
		hint = "%s L%d   INTERACT PREPARE   ATTACK UPGRADE" % [hideaway_facility_name(facility_id).to_upper(), level]
	draw_centered(hint, 339, 8, Color("aeb8b0"))


func hideaway_runtime_contract_ok() -> bool:
	var state := hideaway_state_snapshot()
	return (
		HideawayStewardship.validate_state(state).is_empty()
		and HIDEAWAY_MAP_ID == String(HideawayStewardship.HIDEAWAY_ID)
		and HIDEAWAY_BONUS_DAMAGE == 2
		and HIDEAWAY_WARMTH_REDUCTION == 2
	)
