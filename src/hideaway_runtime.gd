extends "res://src/presentation_runtime_base.gd"

const HideawayStewardship = preload("res://src/game/hideaway_stewardship.gd")
const HideawayMementoModel = preload("res://src/game/hideaway_memento_model.gd")
const HideawayQuietMomentModel = preload("res://src/game/hideaway_quiet_moment_model.gd")
const HideawayStewardshipValidator = preload("res://src/content/hideaway_stewardship_validator.gd")
const HideawayEncounterModel = preload("res://src/game/encounter_model.gd")

const HIDEAWAY_MAP_ID := "archive_hideaway"
const HIDEAWAY_STATE_KEY := "hideaway:stewardship"
const HIDEAWAY_WARMTH_GUARD_KEY := "hideaway:buff:warmth_guard"
const HIDEAWAY_REPAIR_STRIKE_KEY := "hideaway:buff:repair_strike"
const HIDEAWAY_COMPANION_FOCUS_KEY := "hideaway:buff:companion_focus"
const HIDEAWAY_FACILITY_KIND := "hideaway_facility"
const HIDEAWAY_MEMENTO_KIND := "hideaway_memento_shelf"
const HIDEAWAY_QUIET_MOMENT_KIND := "hideaway_quiet_moments"
const HIDEAWAY_BONUS_DAMAGE := 2
const HIDEAWAY_WARMTH_REDUCTION := 2
const HIDEAWAY_STATUS_WIDTH := 464.0

var hideaway_definition: Dictionary = {}
var hideaway_definition_key := ""
var hideaway_memento_cursor := 0
var hideaway_quiet_moment_cursor := 0


func load_campaign(path: String) -> bool:
	var validation := HideawayStewardshipValidator.validate_hideaway_only(path)
	if not bool(validation.get("ok", false)):
		load_error = format_errors(validation.get("errors", []))
		push_error("Archive Hideaway definition validation failed: %s" % load_error)
		if campaign.is_empty():
			load_fallback_campaign()
		return false
	var loaded := super.load_campaign(path)
	if not loaded:
		return false
	cache_hideaway_definition(path, validation.get("definition", {}))
	return true


func load_fallback_campaign() -> void:
	hideaway_definition = {}
	hideaway_definition_key = ""
	hideaway_memento_cursor = 0
	hideaway_quiet_moment_cursor = 0
	super.load_fallback_campaign()


func apply_save_profile(profile: Dictionary, target_campaign_path: String) -> bool:
	var restored := super.apply_save_profile(profile, target_campaign_path)
	if restored:
		refresh_hideaway_definition()
	return restored


func begin_game() -> void:
	super.begin_game()
	refresh_hideaway_definition()
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
	if not activated or not use_transition:
		return activated
	var next_map_id := str(map_data.get("id", ""))
	if previous_map_id != HIDEAWAY_MAP_ID and next_map_id == HIDEAWAY_MAP_ID:
		hideaway_quiet_moment_cursor = 0
	if not hideaway_has_durable_authority():
		return activated
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
		var state := hideaway_state_snapshot()
		var return_message := hideaway_return_message(returned, state)
		if not return_message.is_empty():
			dialogue = return_message
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
		var shelf := nearest_hideaway_memento_shelf()
		if not shelf.is_empty():
			inspect_hideaway_memento()
			return
		var quiet_nook := nearest_hideaway_quiet_nook()
		if not quiet_nook.is_empty():
			inspect_hideaway_quiet_moment()
			return
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
			set_combat_text(
				localise("ui.hideaway.warmth.absorb", "Archive Hearth warmth turns the blow."),
				1.1
			)
			return
		amount = reduced
	super.damage_actor(actor_id, amount, attacker)


func draw_game() -> void:
	super.draw_game()
	if not is_in_archive_hideaway():
		return
	draw_hideaway_facilities()
	draw_hideaway_quiet_nook()
	draw_hideaway_memento_shelf()
	draw_hideaway_status()


func hideaway_has_durable_authority() -> bool:
	var online := get_node_or_null("MultiplayerSession")
	return online == null or str(online.get("mode")) != "client"


func cache_hideaway_definition(path: String, value: Variant) -> void:
	hideaway_definition_key = "%s|%s" % [path, str(campaign.get("id", ""))]
	hideaway_definition = (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
	hideaway_memento_cursor = 0
	hideaway_quiet_moment_cursor = 0


func refresh_hideaway_definition() -> void:
	var key := "%s|%s" % [campaign_path, str(campaign.get("id", ""))]
	if key == hideaway_definition_key:
		return
	if campaign_path.is_empty():
		cache_hideaway_definition(campaign_path, {})
		return
	var report := HideawayStewardshipValidator.validate_hideaway_only(campaign_path)
	if not bool(report.get("ok", false)):
		push_error("Archive Hideaway definition refresh failed: %s" % format_errors(report.get("errors", [])))
		cache_hideaway_definition(campaign_path, {})
		return
	cache_hideaway_definition(campaign_path, report.get("definition", {}))


func hideaway_definition_snapshot() -> Dictionary:
	refresh_hideaway_definition()
	return hideaway_definition.duplicate(true)


func unlocked_hideaway_mementos() -> Array:
	return HideawayMementoModel.unlocked_entries(
		hideaway_definition_snapshot(),
		session_state,
		hideaway_state_snapshot()
	)


func hideaway_memento_summary() -> Dictionary:
	var definition := hideaway_definition_snapshot()
	var entries_value: Variant = definition.get("mementos", [])
	var total := (entries_value as Array).size() if typeof(entries_value) == TYPE_ARRAY else 0
	var slots := HideawayMementoModel.shelf_slots(definition)
	var unlocked := unlocked_hideaway_mementos()
	return {
		"unlocked": mini(unlocked.size(), slots),
		"total": mini(total, slots),
		"slots": slots,
	}


func nearest_hideaway_memento_shelf() -> Dictionary:
	if not is_in_archive_hideaway():
		return {}
	var definition := hideaway_definition_snapshot()
	var expected_id := HideawayMementoModel.shelf_interaction_id(definition)
	if expected_id.is_empty():
		return {}
	for value in map_data.get("interactions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = value
		if (
			str(interaction.get("id", "")) != expected_id
			or str(interaction.get("kind", "")) != HIDEAWAY_MEMENTO_KIND
			or not MapModel.available_in_era(interaction, current_era_id)
		):
			continue
		var position := CampaignRepository.data_to_vector(interaction.get("position"))
		if player.distance_to(position) <= float(interaction.get("radius", 32.0)):
			return interaction
	return {}


func inspect_hideaway_memento() -> Dictionary:
	var unlocked := unlocked_hideaway_mementos()
	if unlocked.is_empty():
		hideaway_memento_cursor = 0
		dialogue = localise(
			"ui.hideaway.memento.none",
			"The shelf is waiting for something worth carrying home."
		)
		return {}
	hideaway_memento_cursor = posmod(hideaway_memento_cursor, unlocked.size())
	var entry: Dictionary = unlocked[hideaway_memento_cursor]
	hideaway_memento_cursor = (hideaway_memento_cursor + 1) % unlocked.size()
	var name := hideaway_memento_name(entry)
	var reflection := hideaway_memento_reflection(entry)
	dialogue = name if reflection.is_empty() else "%s\n%s" % [name, reflection]
	return entry.duplicate(true)


func hideaway_memento_name(entry: Dictionary) -> String:
	return localise(
		str(entry.get("display_name_key", "")),
		str(entry.get("display_name", "Memento"))
	)


func hideaway_memento_reflection(entry: Dictionary) -> String:
	return localise(
		HideawayMementoModel.reflection_key(entry, current_era_id),
		HideawayMementoModel.reflection_fallback(entry, current_era_id)
	)


func available_hideaway_quiet_moments() -> Array:
	return HideawayQuietMomentModel.available_entries(
		hideaway_definition_snapshot(),
		session_state,
		hideaway_state_snapshot()
	)


func hideaway_quiet_moment_summary() -> Dictionary:
	var definition := hideaway_definition_snapshot()
	var entries_value: Variant = definition.get("quiet_moments", [])
	var total := (entries_value as Array).size() if typeof(entries_value) == TYPE_ARRAY else 0
	var slots := HideawayQuietMomentModel.nook_slots(definition)
	var available := available_hideaway_quiet_moments()
	return {
		"available": mini(available.size(), slots),
		"total": mini(total, slots),
		"slots": slots,
	}


func nearest_hideaway_quiet_nook() -> Dictionary:
	if not is_in_archive_hideaway():
		return {}
	var definition := hideaway_definition_snapshot()
	var expected_id := HideawayQuietMomentModel.nook_interaction_id(definition)
	if expected_id.is_empty():
		return {}
	for value: Variant in map_data.get("interactions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = value
		if (
			str(interaction.get("id", "")) != expected_id
			or str(interaction.get("kind", "")) != HIDEAWAY_QUIET_MOMENT_KIND
			or not MapModel.available_in_era(interaction, current_era_id)
		):
			continue
		var position := CampaignRepository.data_to_vector(interaction.get("position"))
		if player.distance_to(position) <= float(interaction.get("radius", 32.0)):
			return interaction
	return {}


func inspect_hideaway_quiet_moment() -> Dictionary:
	var available := available_hideaway_quiet_moments()
	if available.is_empty():
		hideaway_quiet_moment_cursor = 0
		dialogue = localise(
			"ui.hideaway.quiet.none",
			"The quiet nook has not found its first moment yet."
		)
		return {}
	hideaway_quiet_moment_cursor = posmod(hideaway_quiet_moment_cursor, available.size())
	var entry: Dictionary = available[hideaway_quiet_moment_cursor]
	hideaway_quiet_moment_cursor = (hideaway_quiet_moment_cursor + 1) % available.size()
	var speaker := hideaway_quiet_moment_speaker(entry)
	var name := hideaway_quiet_moment_name(entry)
	var reflection := hideaway_quiet_moment_reflection(entry)
	var heading := name if speaker.is_empty() else "%s — %s" % [speaker, name]
	dialogue = heading if reflection.is_empty() else "%s
%s" % [heading, reflection]
	return entry.duplicate(true)


func hideaway_quiet_moment_name(entry: Dictionary) -> String:
	return localise(
		str(entry.get("display_name_key", "")),
		str(entry.get("display_name", "Quiet Moment"))
	)


func hideaway_quiet_moment_reflection(entry: Dictionary) -> String:
	return localise(
		HideawayQuietMomentModel.reflection_key(entry, current_era_id),
		HideawayQuietMomentModel.reflection_fallback(entry, current_era_id)
	)


func hideaway_quiet_moment_speaker(entry: Dictionary) -> String:
	var speaker_id := str(entry.get("speaker", "hideaway"))
	var fallbacks := {
		"eli": "ELI",
		"morrow": "MORROW",
		"together": "ELI & MORROW",
		"hideaway": "THE HIDEAWAY",
	}
	return localise(
		"ui.hideaway.quiet.speaker.%s" % speaker_id,
		str(fallbacks.get(speaker_id, "THE HIDEAWAY"))
	)


func hideaway_return_message(returned: Dictionary, state: Dictionary) -> String:
	if bool(returned.get("qualified", false)):
		return localise(
			"ui.hideaway.return.qualified",
			(
				"The Archive Hideaway settles around you.\n"
				+ "Stored {salvage_delta} salvage ({salvage_total}/{salvage_cap}) and "
				+ "{return_delta} return preparation ({return_total}/{return_cap})."
			),
			{
				"salvage_delta": int(returned.get("salvage_awarded", 0)),
				"salvage_total": int(state.get("salvage", 0)),
				"salvage_cap": HideawayStewardship.MAX_SALVAGE,
				"return_delta": int(returned.get("return_opportunities_awarded", 0)),
				"return_total": int(state.get("banked_returns", 0)),
				"return_cap": HideawayStewardship.MAX_BANKED_RETURNS,
			}
		)
	if str(returned.get("reason", "")) == "expedition_too_short":
		var remaining := maxi(
			1,
			int(ceil(
				HideawayStewardship.MINIMUM_EXPEDITION_SECONDS
				- float(returned.get("elapsed_seconds", 0.0))
			))
		)
		return localise(
			"ui.hideaway.return.too_short",
			"This expedition was too short.\n{remaining} more active-play seconds were needed.",
			{"remaining": remaining}
		)
	return ""


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
		dialogue = localise(
			"ui.hideaway.host_only.change",
			"Only the host can change the Archive Hideaway while online."
		)
		return {"accepted": false, "reason": "host_only"}
	var result := HideawayStewardship.upgrade_facility(hideaway_state_snapshot(), facility_id)
	if bool(result.get("accepted", false)):
		store_hideaway_state(result.get("state", {}))
		var state := hideaway_state_snapshot()
		var status := HideawayStewardship.facility_status(state, facility_id)
		var next_cost := int(status.get("next_upgrade_cost", -1))
		dialogue = localise(
			(
				"ui.hideaway.facility.upgraded.complete"
				if bool(status.get("fully_restored", false))
				else "ui.hideaway.facility.upgraded.next"
			),
			(
				"{facility} is fully restored at level {level}.\n{salvage} salvage remains."
				if bool(status.get("fully_restored", false))
				else (
					"{facility} restored to level {level}.\n"
					+ "Next upgrade costs {next_cost}; {salvage} salvage remains."
				)
			),
			{
				"facility": hideaway_facility_name(facility_id),
				"level": int(status.get("level", 0)),
				"next_cost": next_cost,
				"salvage": int(state.get("salvage", 0)),
			}
		)
	else:
		dialogue = hideaway_failure_message(str(result.get("reason", "")), facility_id)
	return result


func prepare_hideaway_facility(facility_id: StringName) -> Dictionary:
	if not hideaway_has_durable_authority():
		dialogue = localise(
			"ui.hideaway.host_only.prepare",
			"Only the host can prepare the Archive Hideaway while online."
		)
		return {"accepted": false, "reason": "host_only"}
	var result := HideawayStewardship.prepare_facility(hideaway_state_snapshot(), facility_id)
	if bool(result.get("accepted", false)):
		store_hideaway_state(result.get("state", {}))
		var state := hideaway_state_snapshot()
		var status := HideawayStewardship.facility_status(state, facility_id)
		dialogue = localise(
			"ui.hideaway.facility.prepared",
			(
				"{facility} prepared for the next expedition.\n"
				+ "Stored {prepared}/{capacity}; {returns} return preparations remain."
			),
			{
				"facility": hideaway_facility_name(facility_id),
				"prepared": int(status.get("prepared", 0)),
				"capacity": int(status.get("preparation_capacity", 0)),
				"returns": int(state.get("banked_returns", 0)),
			}
		)
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
				applied.append(hideaway_effect_name(effect_id))
			&"warmth":
				set_hideaway_counter(HIDEAWAY_WARMTH_GUARD_KEY, 1)
				applied.append(hideaway_effect_name(effect_id))
			&"repair":
				set_hideaway_counter(HIDEAWAY_REPAIR_STRIKE_KEY, 1)
				applied.append(hideaway_effect_name(effect_id))
			&"companion_focus":
				set_hideaway_counter(HIDEAWAY_COMPANION_FOCUS_KEY, 1)
				applied.append(hideaway_effect_name(effect_id))
	store_hideaway_state(state)
	if not applied.is_empty():
		set_combat_text(
			localise(
				"ui.hideaway.preparation.applied",
				"Hideaway preparation: {effects}.",
				{"effects": ", ".join(applied)}
			),
			1.5
		)


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
	var fallback := String(facility_id).replace("_", " ").capitalize()
	return localise(
		"ui.hideaway.facility.%s" % String(facility_id),
		fallback
	)


func hideaway_effect_name(effect_id: StringName) -> String:
	var fallback := String(effect_id).replace("_", " ").capitalize()
	return localise("ui.hideaway.effect.%s" % String(effect_id), fallback)


func hideaway_failure_message(reason: String, facility_id: StringName) -> String:
	var facility := hideaway_facility_name(facility_id)
	match reason:
		"facility_unrestored":
			return localise(
				"ui.hideaway.failure.unrestored",
				"{facility} must be restored first.\nATTACK near it to spend salvage.",
				{"facility": facility}
			)
		"no_return_opportunity":
			return localise(
				"ui.hideaway.failure.no_return",
				"Complete a qualifying expedition before preparing {facility}.",
				{"facility": facility}
			)
		"preparation_full":
			var status := HideawayStewardship.facility_status(hideaway_state_snapshot(), facility_id)
			return localise(
				"ui.hideaway.failure.full",
				"{facility} already holds {prepared}/{capacity} preparations.",
				{
					"facility": facility,
					"prepared": int(status.get("prepared", 0)),
					"capacity": int(status.get("preparation_capacity", 0)),
				}
			)
		"insufficient_salvage":
			var status := HideawayStewardship.facility_status(hideaway_state_snapshot(), facility_id)
			return localise(
				"ui.hideaway.failure.salvage",
				"{facility} needs {cost} salvage; only {salvage} is stored.",
				{
					"facility": facility,
					"cost": int(status.get("next_upgrade_cost", -1)),
					"salvage": int(hideaway_state_snapshot().get("salvage", 0)),
				}
			)
		"facility_unavailable":
			return localise(
				"ui.hideaway.failure.complete",
				"{facility} is already fully restored.",
				{"facility": facility}
			)
		_:
			return localise(
				"ui.hideaway.failure.default",
				"{facility} cannot be changed right now.",
				{"facility": facility}
			)


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


func hideaway_memento_visual_descriptor(entry: Dictionary, slot_index: int) -> Dictionary:
	var symbol := str(entry.get("symbol", ""))
	return {
		"id": str(entry.get("id", "")),
		"symbol": symbol,
		"signature": "%s:%d" % [symbol, slot_index],
		"slot_index": maxi(0, slot_index),
		"unlocked": HideawayMementoModel.SYMBOL_IDS.has(symbol),
	}


func draw_hideaway_memento_shelf() -> void:
	var definition := hideaway_definition_snapshot()
	var shelf_id := HideawayMementoModel.shelf_interaction_id(definition)
	var slots := HideawayMementoModel.shelf_slots(definition)
	if shelf_id.is_empty() or slots <= 0:
		return
	var shelf: Dictionary = {}
	for value in map_data.get("interactions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var interaction: Dictionary = value
		if str(interaction.get("id", "")) == shelf_id and str(interaction.get("kind", "")) == HIDEAWAY_MEMENTO_KIND:
			shelf = interaction
			break
	if shelf.is_empty():
		return
	var position := CampaignRepository.data_to_vector(shelf.get("position")) - camera_offset()
	var accent := palette_color("accent", "d4aa63")
	var structure := palette_color("structure", "705b43")
	var width := float(slots * 10 + 10)
	draw_rect(Rect2(position + Vector2(-width * 0.5, -12), Vector2(width, 25)), Color(structure.r, structure.g, structure.b, 0.88), true)
	draw_rect(Rect2(position + Vector2(-width * 0.5, -12), Vector2(width, 25)), accent, false, 1.5)
	draw_line(position + Vector2(-width * 0.5 + 4, 8), position + Vector2(width * 0.5 - 4, 8), accent, 1.5)
	var unlocked := unlocked_hideaway_mementos()
	for slot_index in range(slots):
		var slot_position := position + Vector2(-float(slots - 1) * 5.0 + slot_index * 10.0, 1)
		draw_rect(Rect2(slot_position + Vector2(-4, -7), Vector2(8, 14)), Color(0.05, 0.045, 0.04, 0.7), true)
		if slot_index < unlocked.size():
			var entry: Dictionary = unlocked[slot_index]
			draw_hideaway_memento_symbol(slot_position, str(entry.get("symbol", "")), accent)
		else:
			draw_circle(slot_position, 1.2, Color(accent.r, accent.g, accent.b, 0.28), true)
	if not nearest_hideaway_memento_shelf().is_empty():
		draw_rect(Rect2(position + Vector2(-width * 0.5 - 2, -14), Vector2(width + 4, 29)), Color(accent.r, accent.g, accent.b, 0.5), false, 1.0)


func draw_hideaway_memento_symbol(position: Vector2, symbol: String, accent: Color) -> void:
	match symbol:
		"strap":
			draw_arc(position, 4.0, -PI * 0.7, PI * 0.7, 8, accent, 1.4)
		"rubbing":
			draw_rect(Rect2(position + Vector2(-3, -5), Vector2(6, 10)), Color("d8c7a4"), true)
			draw_line(position + Vector2(-2, -2), position + Vector2(2, -2), Color("4b4032"), 1.0)
			draw_line(position + Vector2(-2, 1), position + Vector2(2, 1), Color("4b4032"), 1.0)
		"lens_case":
			draw_circle(position, 3.8, accent, false, 1.4)
			draw_line(position + Vector2(2, 3), position + Vector2(4, 5), accent, 1.2)
		"ash_mark":
			draw_line(position + Vector2(-3, -5), position + Vector2(3, 5), Color("c9794b"), 2.0)
			draw_line(position + Vector2(2, -4), position + Vector2(-2, 4), Color("6d5144"), 1.0)
		"accession_plate":
			draw_rect(Rect2(position + Vector2(-4, -3), Vector2(8, 6)), Color("b98a4f"), true)
			draw_line(position + Vector2(-2, 0), position + Vector2(2, 0), Color("43372d"), 1.0)
		"haven_key":
			draw_circle(position + Vector2(-2, -1), 2.5, accent, false, 1.2)
			draw_line(position, position + Vector2(5, 4), accent, 1.5)
			draw_line(position + Vector2(3, 2), position + Vector2(3, 5), accent, 1.0)
		_:
			draw_circle(position, 2.0, accent, false, 1.0)


func hideaway_quiet_moment_visual_descriptor(entry: Dictionary, index: int) -> Dictionary:
	var speaker_id := str(entry.get("speaker", "hideaway"))
	return {
		"signature": "%s:%s:%d" % [speaker_id, str(entry.get("id", "quiet")), maxi(0, index)],
		"speaker": speaker_id,
		"index": maxi(0, index),
	}


func draw_hideaway_quiet_nook() -> void:
	if not is_in_archive_hideaway():
		return
	var definition := hideaway_definition_snapshot()
	var expected_id := HideawayQuietMomentModel.nook_interaction_id(definition)
	if expected_id.is_empty():
		return
	var interaction: Dictionary = {}
	for value: Variant in map_data.get("interactions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = value
		if (
			str(candidate.get("id", "")) == expected_id
			and str(candidate.get("kind", "")) == HIDEAWAY_QUIET_MOMENT_KIND
			and MapModel.available_in_era(candidate, current_era_id)
		):
			interaction = candidate
			break
	if interaction.is_empty():
		return
	var position := CampaignRepository.data_to_vector(interaction.get("position")) - camera_offset()
	var frame := palette_color("structure", "705b43")
	var accent := palette_color("accent", "d4aa63")
	var available_count := available_hideaway_quiet_moments().size()
	draw_rect(Rect2(position + Vector2(-20, 6), Vector2(40, 5)), Color(frame.r, frame.g, frame.b, 0.9), true)
	draw_circle(position + Vector2(-11, 2), 6.0, Color("776250"), true)
	draw_circle(position + Vector2(11, 2), 6.0, Color("655449"), true)
	draw_arc(position + Vector2(0, 1), 18.0, PI, TAU, 18, Color(accent.r, accent.g, accent.b, 0.42), 1.0)
	if available_count > 1:
		for index in range(mini(available_count, 4)):
			draw_circle(position + Vector2(-9 + index * 6, -8), 1.2, Color(accent.r, accent.g, accent.b, 0.7), true)
	if not nearest_hideaway_quiet_nook().is_empty():
		draw_circle(position, 26.0, Color(accent.r, accent.g, accent.b, 0.35), false, 1.0)


func hideaway_facility_visual_descriptor(
	facility_id: StringName,
	level: int
) -> Dictionary:
	var bounded := clampi(level, 0, HideawayStewardship.MAX_FACILITY_LEVEL)
	var descriptor := {
		"facility_id": String(facility_id),
		"stage": bounded,
		"footprint_scale": 1.0 + bounded * 0.12,
		"detail_count": bounded,
		"active": bounded > 0,
	}
	match facility_id:
		&"archive_hearth":
			descriptor["signature"] = "ember" if bounded == 1 else "flame" if bounded == 2 else "chimney_glow" if bounded == 3 else "cold_stone"
		&"sheltered_coldframe":
			descriptor["signature"] = "sprout" if bounded == 1 else "leaf_rows" if bounded == 2 else "glass_canopy" if bounded == 3 else "empty_frame"
		&"salvage_workbench":
			descriptor["signature"] = "tool" if bounded == 1 else "tool_rack" if bounded == 2 else "lit_lathe" if bounded == 3 else "bare_plank"
		&"morrows_corner":
			descriptor["signature"] = "blanket" if bounded == 1 else "bed_and_bowl" if bounded == 2 else "settled_den" if bounded == 3 else "empty_corner"
		_:
			descriptor["signature"] = "unknown"
	return descriptor


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
		var descriptor := hideaway_facility_visual_descriptor(facility_id, level)
		var position := CampaignRepository.data_to_vector(interaction.get("position")) - offset
		var frame := palette_color("structure", "705b43")
		var accent := palette_color("accent", "d4aa63")
		var scale := float(descriptor.get("footprint_scale", 1.0))
		var half_size := Vector2(15, 11) * scale
		draw_rect(Rect2(position - half_size, half_size * 2.0), Color(frame.r, frame.g, frame.b, 0.85), true)
		draw_rect(Rect2(position - half_size, half_size * 2.0), accent if level > 0 else Color("665c50"), false, 2.0)
		match facility_id:
			&"archive_hearth":
				draw_hideaway_hearth_stage(position, level, accent)
			&"sheltered_coldframe":
				draw_hideaway_coldframe_stage(position, level, accent)
			&"salvage_workbench":
				draw_hideaway_workbench_stage(position, level, accent)
			&"morrows_corner":
				draw_hideaway_morrow_stage(position, level, accent)


func draw_hideaway_hearth_stage(position: Vector2, level: int, accent: Color) -> void:
	draw_rect(Rect2(position + Vector2(-9, 4), Vector2(18, 5)), Color("4c3528"), true)
	if level <= 0:
		draw_line(position + Vector2(-5, 2), position + Vector2(5, 2), Color("665c50"), 1.0)
		return
	var glow := Color("e59a4f")
	draw_circle(position + Vector2(0, 2), 4.0 + level * 1.4, glow, true)
	if level >= 2:
		draw_line(position + Vector2(-7, -3), position + Vector2(0, -10), accent, 2.0)
		draw_line(position + Vector2(0, -10), position + Vector2(7, -3), accent, 2.0)
	if level >= 3:
		draw_rect(Rect2(position + Vector2(7, -13), Vector2(5, 17)), Color("554237"), true)
		draw_circle(position + Vector2(9, -16), 2.0, Color(glow.r, glow.g, glow.b, 0.45), true)


func draw_hideaway_coldframe_stage(position: Vector2, level: int, accent: Color) -> void:
	draw_line(position + Vector2(-11, 7), position + Vector2(0, -8), Color("665c50") if level <= 0 else accent, 1.0)
	draw_line(position + Vector2(0, -8), position + Vector2(11, 7), Color("665c50") if level <= 0 else accent, 1.0)
	draw_line(position + Vector2(-11, 7), position + Vector2(11, 7), Color("665c50") if level <= 0 else accent, 1.0)
	for index in range(level):
		var x := -7.0 + index * 7.0
		draw_line(position + Vector2(x, 5), position + Vector2(x + 2, 0), Color("82a66f"), 2.0)
		draw_circle(position + Vector2(x + 3, -1), 1.8, Color("a7c787"), true)
	if level >= 3:
		draw_line(position + Vector2(0, -8), position + Vector2(0, 7), Color(accent.r, accent.g, accent.b, 0.7), 1.0)


func draw_hideaway_workbench_stage(position: Vector2, level: int, accent: Color) -> void:
	draw_line(position + Vector2(-11, 1), position + Vector2(11, 1), accent if level > 0 else Color("665c50"), 2.0)
	draw_line(position + Vector2(-8, 1), position + Vector2(-8, 9), Color("4c3528"), 2.0)
	draw_line(position + Vector2(8, 1), position + Vector2(8, 9), Color("4c3528"), 2.0)
	if level >= 1:
		draw_line(position + Vector2(-5, -1), position + Vector2(-1, -7), Color("b7b0a0"), 2.0)
	if level >= 2:
		draw_rect(Rect2(position + Vector2(2, -8), Vector2(8, 5)), Color("69523e"), true)
		draw_line(position + Vector2(4, -6), position + Vector2(8, -6), Color("d1b778"), 1.0)
	if level >= 3:
		draw_circle(position + Vector2(8, -4), 3.0, Color("e2a252"), false, 1.5)
		draw_line(position + Vector2(8, -7), position + Vector2(8, -1), Color("e2a252"), 1.0)


func draw_hideaway_morrow_stage(position: Vector2, level: int, accent: Color) -> void:
	var bed := Color("765a48") if level > 0 else Color("665c50")
	draw_rect(Rect2(position + Vector2(-10, 1), Vector2(20, 8)), bed, true)
	if level >= 1:
		draw_line(position + Vector2(-8, 4), position + Vector2(8, 4), accent, 1.0)
	if level >= 2:
		draw_circle(position + Vector2(10, 6), 3.0, Color("b8a27a"), false, 1.2)
		draw_circle(position + Vector2(-7, -2), 2.5, Color("d2c5aa"), true)
	if level >= 3:
		draw_arc(position + Vector2(0, 3), 14.0, PI, TAU, 12, Color(accent.r, accent.g, accent.b, 0.65), 1.5)


func draw_hideaway_environment_progression(summary: Dictionary) -> void:
	var tier_index := int(summary.get("tier_index", 0))
	if tier_index <= 0:
		return
	var accent := palette_color("accent", "d4aa63")
	var warm := Color(accent.r, accent.g, accent.b, 0.18 + tier_index * 0.05)
	draw_circle(Vector2(320, 232) - camera_offset(), 20.0 + tier_index * 7.0, warm, false, 1.0)
	for index in range(tier_index + 1):
		var x := 270.0 + index * 32.0
		draw_circle(Vector2(x, 128) - camera_offset(), 1.5 + tier_index * 0.4, Color(warm.r, warm.g, warm.b, 0.65), true)


func hideaway_tier_name(tier_id: String) -> String:
	return localise(
		"ui.hideaway.tier.%s" % tier_id,
		tier_id.replace("_", " ").capitalize()
	)


func hideaway_facility_status_text(state: Dictionary, facility_id: StringName) -> String:
	var status := HideawayStewardship.facility_status(state, facility_id)
	if bool(status.get("fully_restored", false)):
		return localise(
			"ui.hideaway.status.facility.complete",
			"{facility} L{level}/{maximum}   FULLY RESTORED   PREP {prepared}/{capacity}",
			{
				"facility": hideaway_facility_name(facility_id).to_upper(),
				"level": int(status.get("level", 0)),
				"maximum": int(status.get("maximum_level", 0)),
				"prepared": int(status.get("prepared", 0)),
				"capacity": int(status.get("preparation_capacity", 0)),
			}
		)
	if int(status.get("level", 0)) <= 0:
		return localise(
			"ui.hideaway.status.facility.unrestored",
			"{facility} UNRESTORED   COST {cost}   SALVAGE {salvage}",
			{
				"facility": hideaway_facility_name(facility_id).to_upper(),
				"cost": int(status.get("next_upgrade_cost", -1)),
				"salvage": int(state.get("salvage", 0)),
			}
		)
	return localise(
		"ui.hideaway.status.facility.active",
		"{facility} L{level}/{maximum}   NEXT {cost}   PREP {prepared}/{capacity}",
		{
			"facility": hideaway_facility_name(facility_id).to_upper(),
			"level": int(status.get("level", 0)),
			"maximum": int(status.get("maximum_level", 0)),
			"cost": int(status.get("next_upgrade_cost", -1)),
			"prepared": int(status.get("prepared", 0)),
			"capacity": int(status.get("preparation_capacity", 0)),
		}
	)


func hideaway_facility_controls_text(state: Dictionary, facility_id: StringName) -> String:
	var status := HideawayStewardship.facility_status(state, facility_id)
	if int(status.get("level", 0)) <= 0:
		return localise(
			"ui.hideaway.controls.restore",
			"ATTACK RESTORE   •   INTERACT INSPECT"
		)
	if bool(status.get("fully_restored", false)):
		return localise(
			"ui.hideaway.controls.complete",
			"INTERACT PREPARE   •   FACILITY COMPLETE"
		)
	return localise(
		"ui.hideaway.controls.active",
		"INTERACT PREPARE   •   ATTACK UPGRADE"
	)


func draw_hideaway_status() -> void:
	var state := hideaway_state_snapshot()
	var summary := HideawayStewardship.refuge_summary(state)
	draw_hideaway_environment_progression(summary)
	draw_rect(Rect2(76, 288, 488, 64), Color(0.025, 0.022, 0.018, 0.92), true)
	draw_rect(Rect2(76, 288, 488, 64), Color("a88654"), false, 1.0)
	var header := localise(
		"ui.hideaway.status.overview",
		"{tier}   SALVAGE {salvage}/{salvage_cap}   RETURNS {returns}/{return_cap}",
		{
			"tier": hideaway_tier_name(str(summary.get("tier_id", "unsettled"))).to_upper(),
			"salvage": int(state.get("salvage", 0)),
			"salvage_cap": HideawayStewardship.MAX_SALVAGE,
			"returns": int(state.get("banked_returns", 0)),
			"return_cap": HideawayStewardship.MAX_BANKED_RETURNS,
		}
	)
	draw_fitted_line(header, Vector2(88, 305), HIDEAWAY_STATUS_WIDTH, 9, 5, Color("ead9b7"), HORIZONTAL_ALIGNMENT_CENTER)
	var shelf := nearest_hideaway_memento_shelf()
	var quiet_nook := nearest_hideaway_quiet_nook()
	var facility := nearest_hideaway_facility()
	var detail := localise(
		"ui.hideaway.status.restoration",
		"RESTORATION {total}/{maximum}   FACILITIES {restored}/{facilities}",
		{
			"total": int(summary.get("total_level", 0)),
			"maximum": int(summary.get("maximum_total_level", 0)),
			"restored": int(summary.get("restored_count", 0)),
			"facilities": int(summary.get("facility_count", 0)),
		}
	)
	var controls := localise("ui.hideaway.status.ready", "RETURN TO THE ROAD WHEN READY")
	if not shelf.is_empty():
		var mementos := hideaway_memento_summary()
		detail = localise(
			"ui.hideaway.status.mementos",
			"MEMENTOS {unlocked}/{total}   MEMORIES FROM THE ROAD",
			{
				"unlocked": int(mementos.get("unlocked", 0)),
				"total": int(mementos.get("total", 0)),
			}
		)
		controls = localise(
			"ui.hideaway.controls.mementos",
			"INTERACT REMEMBER   •   NOTHING IS CONSUMED"
		)
	elif not quiet_nook.is_empty():
		var moments := hideaway_quiet_moment_summary()
		detail = localise(
			"ui.hideaway.status.quiet",
			"QUIET MOMENTS {available}/{total}   HEARTHSIDE REFUGE",
			{
				"available": int(moments.get("available", 0)),
				"total": int(moments.get("total", 0)),
			}
		)
		controls = localise(
			"ui.hideaway.controls.quiet",
			"INTERACT LISTEN   •   NO TIME PASSES"
		)
	elif not facility.is_empty():
		var facility_id := StringName(str(facility.get("facility_id", "")))
		detail = hideaway_facility_status_text(state, facility_id)
		controls = hideaway_facility_controls_text(state, facility_id)
	draw_fitted_line(detail, Vector2(88, 325), HIDEAWAY_STATUS_WIDTH, 8, 5, Color("d7c9ae"), HORIZONTAL_ALIGNMENT_CENTER)
	draw_fitted_line(controls, Vector2(88, 344), HIDEAWAY_STATUS_WIDTH, 7, 5, Color("aeb8b0"), HORIZONTAL_ALIGNMENT_CENTER)


func hideaway_runtime_contract_ok() -> bool:
	var state := hideaway_state_snapshot()
	return (
		HideawayStewardship.validate_state(state).is_empty()
		and HIDEAWAY_MAP_ID == String(HideawayStewardship.HIDEAWAY_ID)
		and HIDEAWAY_BONUS_DAMAGE == 2
		and HIDEAWAY_WARMTH_REDUCTION == 2
		and HIDEAWAY_STATUS_WIDTH == 464.0
		and HIDEAWAY_MEMENTO_KIND == HideawayMementoModel.SHELF_KIND
		and HIDEAWAY_QUIET_MOMENT_KIND == HideawayQuietMomentModel.NOOK_KIND
		and HideawayMementoModel.memento_contract_ok()
		and HideawayQuietMomentModel.quiet_moment_contract_ok()
		and not HideawayStewardship.refuge_summary(state).is_empty()
		and (hideaway_definition_snapshot().is_empty() or HideawayStewardshipValidator.validate_definition(hideaway_definition_snapshot()).is_empty())
		and str(hideaway_facility_visual_descriptor(&"archive_hearth", 3).get("signature", "")) == "chimney_glow"
		and str(hideaway_quiet_moment_visual_descriptor({"id": "threshold_breaths", "speaker": "together"}, 0).get("signature", "")) == "together:threshold_breaths:0"
	)
