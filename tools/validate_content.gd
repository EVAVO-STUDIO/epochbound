extends SceneTree

const FinalValidator = preload("res://src/content/audio_mood_strict_validator.gd")


func _initialize() -> void:
	var report: Dictionary = FinalValidator.validate_all()
	for warning in report.get("warnings", []):
		print_rich("[color=yellow]WARNING[/color] %s" % warning)
	for error in report.get("errors", []):
		push_error(str(error))
	print(
		"Content validation: %d campaign(s), %d map(s), %d object definition(s), %d placement(s), %d encounter zone(s), %d companion cue(s), %d item(s), %d recipe(s), %d conversation(s), %d quest(s), %d save policy record(s), %d equipment item(s), %d equipment slot(s), %d capability definition(s), %d capability gate(s), %d currency definition(s), %d merchant(s), %d merchant binding(s), %d stock entry(s), %d ammunition type(s), %d ranged weapon(s), %d ranged enemy profile(s), %d boss definition(s), %d boss placement(s), %d boss phase(s), %d boss pattern step(s), %d boss reinforcement(s), %d cinematic(s), %d cinematic step(s), %d cinematic trigger(s), %d release record(s), %d presentation profile(s), %d presentation binding(s), %d audio profile(s), %d audio binding(s), %d warning(s), %d error(s)." % [
			report.get("campaign_count", 0),
			report.get("map_count", 0),
			report.get("definition_count", 0),
			report.get("placement_count", 0),
			report.get("zone_count", 0),
			report.get("cue_count", 0),
			report.get("item_count", 0),
			report.get("recipe_count", 0),
			report.get("conversation_count", 0),
			report.get("quest_count", 0),
			report.get("save_policy_count", 0),
			report.get("equipment_item_count", 0),
			report.get("equipment_slot_count", 0),
			report.get("capability_count", 0),
			report.get("capability_gate_count", 0),
			report.get("currency_count", 0),
			report.get("merchant_count", 0),
			report.get("merchant_binding_count", 0),
			report.get("merchant_stock_count", 0),
			report.get("ammunition_count", 0),
			report.get("ranged_weapon_count", 0),
			report.get("ranged_enemy_count", 0),
			report.get("boss_count", 0),
			report.get("boss_placement_count", 0),
			report.get("boss_phase_count", 0),
			report.get("boss_pattern_step_count", 0),
			report.get("boss_reinforcement_count", 0),
			report.get("cinematic_count", 0),
			report.get("cinematic_step_count", 0),
			report.get("cinematic_trigger_count", 0),
			report.get("release_count", 0),
			report.get("presentation_profile_count", 0),
			report.get("presentation_binding_count", 0),
			report.get("audio_profile_count", 0),
			report.get("audio_binding_count", 0),
			report.get("warnings", []).size(),
			report.get("errors", []).size()
		]
	)
	quit(0 if bool(report.get("ok", false)) else 1)
